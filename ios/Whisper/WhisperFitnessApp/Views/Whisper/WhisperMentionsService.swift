import Foundation
import Supabase

/// Row in the `whisper_mentions` table — one per `@handle` reference
/// inside a post / comment / reel / DM. Recipient-facing.
nonisolated struct WhisperMentionRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let source_type: String   // "post" | "comment" | "reel" | "dm"
    let source_id: String
    let author_id: String
    let mentioned_user_id: String
    let mentioned_username: String
    let created_at: String?
    let read_at: String?
}

/// Wraps everything needed to power the in-app `@mentions` feature:
/// recording mentions when content is created, fetching the current
/// user's inbox of mentions, marking them read, and dispatching local
/// notification banners + Activity tab badges when new mentions arrive
/// via Supabase realtime.
@MainActor
@Observable
final class WhisperMentionsService {
    static let shared = WhisperMentionsService()

    /// Recent mentions of the current user, most recent first.
    var mentions: [WhisperMentionRow] = []
    /// Count of mentions whose `read_at` is nil — drives the Activity badge.
    var unreadCount: Int = 0

    private let client = SupabaseService.shared.client
    @ObservationIgnored private var fetches: [Int: WhisperAccountRefresh] = [:]
    private var channel: RealtimeChannelV2?
    private var channelTask: Task<Void, Never>?
    private var bannerSeenIDs: Set<String> = []

    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    /// Local fallback read cutoff. The server `read_at` stamp is the source
    /// of truth, but if the column update fails (schema not migrated yet,
    /// RLS, offline) this device-side cutoff still clears the badge — so
    /// "tagged you in a post" rows can ALWAYS be marked read.
    private let localReadKey = "whisper.mentions.lastReadAt.v1"

    private var localReadCutoff: Date {
        let t = UserDefaults.standard.double(forKey: localReadKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : .distantPast
    }

    /// True when a mention should render as unread: no server read stamp
    /// AND newer than the local read cutoff.
    func isUnread(_ row: WhisperMentionRow) -> Bool {
        guard row.read_at == nil else { return false }
        guard let iso = row.created_at,
              let date = WhisperBackendService.parseISO(iso) else { return false }
        return date > localReadCutoff
    }

    private func recomputeUnread() {
        unreadCount = mentions.reduce(0) { $0 + (isUnread($1) ? 1 : 0) }
    }

    private init() {}

    // MARK: - Fetch / read state

    /// Pulls the latest mentions for the current user. Safe to call as a
    /// pull-to-refresh on the Activity tab.
    func fetch(limit: Int = 100) async {
        let refresh = fetches[limit] ?? WhisperAccountRefresh()
        fetches[limit] = refresh
        await refresh.run { [self] generation in await loadMentions(limit: limit, generation: generation) }
    }

    private func loadMentions(limit: Int, generation: UUID) async {
        guard isRemote, !Task.isCancelled, generation == AccountStorage.generation else { return }
        let owner = currentUID
        do {
            let rows: [WhisperMentionRow] = try await client
                .from("whisper_mentions")
                .select()
                .eq("mentioned_user_id", value: currentUID)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            guard !Task.isCancelled, generation == AccountStorage.generation, owner == currentUID else { return }
            mentions = rows
            recomputeUnread()
            WhisperNotificationService.shared.refreshAppIconBadge()
        } catch {
            // Table may not be deployed yet — keep the UI quiet rather than
            // surfacing a noisy error banner.
            print("[Whisper] mentions fetch error: \(error)")
        }
    }

    /// Marks every unread mention as read. Local cutoff is stamped FIRST so
    /// the badge always clears, then the server `read_at` update runs as a
    /// best-effort sync (it can fail if the column hasn't been migrated).
    func markAllRead() async {
        guard isRemote, unreadCount > 0 else { return }
        let now = Date()
        let nowISO = ISO8601DateFormatter().string(from: now)
        // 1. Local read state — authoritative for the badge on this device.
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: localReadKey)
        mentions = mentions.map { row in
            row.read_at == nil
                ? WhisperMentionRow(
                    id: row.id,
                    source_type: row.source_type,
                    source_id: row.source_id,
                    author_id: row.author_id,
                    mentioned_user_id: row.mentioned_user_id,
                    mentioned_username: row.mentioned_username,
                    created_at: row.created_at,
                    read_at: nowISO
                )
                : row
        }
        unreadCount = 0
        WhisperNotificationService.shared.refreshAppIconBadge()
        // 2. Best-effort server sync so other devices agree.
        do {
            try await client
                .from("whisper_mentions")
                .update(["read_at": nowISO])
                .eq("mentioned_user_id", value: currentUID)
                .is("read_at", value: nil)
                .execute()
        } catch {
            print("[Whisper] mentions markAllRead server sync skipped: \(error)")
        }
    }

    // MARK: - Record mentions on the author side

    /// Parses `@handles` out of `body`, resolves each to a Supabase user_id
    /// via `whisper_profiles`, and inserts one row per (source, recipient)
    /// pair into `whisper_mentions`. Safe to call from any actor — wraps
    /// the work in a detached Task internally if needed. Silent on schema
    /// or RLS errors so the calling write (post / DM / comment) succeeds
    /// even if the mentions table hasn't been deployed yet.
    func record(
        sourceType: SourceType,
        sourceID: String,
        body: String,
        authorID: String,
        authorUsername: String
    ) async {
        guard isRemote, !sourceID.isEmpty else { return }
        let handles = WhisperMentionParser.mentions(in: body)
        guard !handles.isEmpty else { return }
        // Resolve every handle in one round-trip. Filter out self-mentions
        // and the author themselves so we never notify a user about their
        // own post / comment / DM.
        let lower = Array(Set(handles.map { $0.lowercased() }))
        do {
            let rows: [WhisperUserRow] = try await client
                .from("whisper_profiles")
                .select("user_id,username")
                .in("username", values: lower)
                .execute()
                .value
            let authorLower = authorID.lowercased()
            var inserts: [[String: AnyJSON]] = []
            var seen: Set<String> = []
            for row in rows {
                let uid = row.user_id
                guard !uid.isEmpty, uid.lowercased() != authorLower else { continue }
                guard seen.insert(uid.lowercased()).inserted else { continue }
                inserts.append([
                    "source_type": .string(sourceType.rawValue),
                    "source_id": .string(sourceID),
                    "author_id": .string(authorID),
                    "mentioned_user_id": .string(uid),
                    "mentioned_username": .string(row.username)
                ])
            }
            guard !inserts.isEmpty else { return }
            _ = authorUsername
            // Upsert against the (source_type, source_id, mentioned_user_id)
            // unique index so a quick edit/retry doesn't create duplicates.
            try await client
                .from("whisper_mentions")
                .upsert(inserts, onConflict: "source_type,source_id,mentioned_user_id")
                .execute()
        } catch {
            // Table may not exist yet, or RLS is blocking — log only.
            print("[Whisper] mentions record error: \(error)")
        }
    }

    nonisolated enum SourceType: String, Sendable {
        case post, comment, reel, dm
    }

    // MARK: - Realtime

    /// Subscribes to `whisper_mentions` inserts addressed to the current
    /// user. Each new row triggers a local notification banner and refreshes
    /// the cached list so the Activity tab badge stays live. Idempotent.
    func start() {
        guard isRemote, channel == nil else { return }
        let uid = currentUID
        let ch = client.realtimeV2.channel("whisper-mentions-\(uid)")
        channel = ch
        let stream = ch.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "whisper_mentions",
            filter: "mentioned_user_id=eq.\(uid)"
        )
        channelTask = Task { [weak self] in
            await ch.subscribe()
            for await change in stream {
                await self?.ingest(change)
            }
        }
    }

    func stop() {
        channelTask?.cancel()
        channelTask = nil
        if let ch = channel {
            Task { await ch.unsubscribe() }
        }
        channel = nil
    }

    private func ingest(_ action: InsertAction) async {
        guard let row = try? action.decodeRecord(
            as: WhisperMentionRow.self,
            decoder: JSONDecoder()
        ) else {
            await fetch()
            return
        }
        if !mentions.contains(where: { $0.id == row.id }) {
            mentions.insert(row, at: 0)
            recomputeUnread()
            WhisperNotificationService.shared.refreshAppIconBadge()
        }
        // De-dupe banners so the same realtime echo doesn't double-fire.
        guard bannerSeenIDs.insert(row.id).inserted else { return }
        // Resolve author username for a nicer banner title. Fall back to
        // the bare `@you were mentioned` copy if the lookup fails.
        var authorName = "Someone"
        if let profile = await WhisperBackendService.shared.fetchPublicProfile(userID: row.author_id),
           let uname = profile.username, !uname.isEmpty {
            authorName = uname
        }
        WhisperNotificationService.shared.notifyMention(
            mentionID: row.id,
            fromUsername: authorName,
            sourceType: row.source_type,
            sourceID: row.source_id
        )
    }
}
