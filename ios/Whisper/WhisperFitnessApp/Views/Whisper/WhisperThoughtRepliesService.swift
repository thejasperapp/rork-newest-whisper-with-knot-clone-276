import Foundation
import Supabase
import UIKit
import UserNotifications

// MARK: - Supabase schema (run once in SQL editor)
//
// create table if not exists public.whisper_thought_replies (
//   id uuid primary key default gen_random_uuid(),
//   thought_user_id uuid not null references auth.users(id) on delete cascade,
//   replier_user_id uuid not null references auth.users(id) on delete cascade,
//   replier_username text not null,
//   replier_avatar_url text,
//   body text not null,
//   thought_text text not null default '',
//   thought_style text,
//   thought_accent text,
//   thought_emoji text,
//   thought_color_hex text,
//   thought_owner_username text,
//   created_at timestamptz not null default now(),
//   read_at timestamptz
// );
// alter table public.whisper_thought_replies enable row level security;
//
// -- Group-chat read policy: the thought owner sees every reply addressed
// -- to them, AND anyone who has replied to a given thought can see every
// -- other reply on that same thought (so repliers see each other too).
// drop policy if exists "wtr read mine" on public.whisper_thought_replies;
// create policy "wtr read mine" on public.whisper_thought_replies
//   for select using (
//     auth.uid() = thought_user_id
//     or auth.uid() = replier_user_id
//     or exists (
//       select 1 from public.whisper_thought_replies r2
//       where r2.thought_user_id = whisper_thought_replies.thought_user_id
//         and r2.replier_user_id = auth.uid()
//     )
//   );
//
// drop policy if exists "wtr insert any" on public.whisper_thought_replies;
// create policy "wtr insert any" on public.whisper_thought_replies
//   for insert with check (auth.uid() = replier_user_id);
// drop policy if exists "wtr update owner" on public.whisper_thought_replies;
// create policy "wtr update owner" on public.whisper_thought_replies
//   for update using (auth.uid() = thought_user_id);

nonisolated struct WhisperThoughtReplyRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let thought_user_id: String
    let replier_user_id: String
    let replier_username: String
    let replier_avatar_url: String?
    let body: String
    let thought_text: String?
    let thought_style: String?
    let thought_accent: String?
    let thought_emoji: String?
    let thought_color_hex: String?
    let thought_owner_username: String?
    let created_at: String?
    let read_at: String?
}

nonisolated struct WhisperThoughtReplyInsert: Codable, Sendable {
    let thought_user_id: String
    let replier_user_id: String
    let replier_username: String
    let replier_avatar_url: String?
    let body: String
    let thought_text: String
    let thought_style: String?
    let thought_accent: String?
    let thought_emoji: String?
    let thought_color_hex: String?
    let thought_owner_username: String?
}

/// Replies to "What's on your mind" thoughts. Lives separate from the DM
/// thread so the conversation stays attached to the thought bubble on the
/// owner's profile instead of cluttering chat.
@MainActor
@Observable
final class WhisperThoughtRepliesService {
    static let shared = WhisperThoughtRepliesService()

    private let client = SupabaseService.shared.client

    /// All replies addressed to me, newest first.
    var incoming: [WhisperThoughtReplyRow] = []
    /// Group-chat rows keyed by thought-owner UID — populated when a
    /// replier opens the chat from someone else's profile.
    var groupByOwner: [String: [WhisperThoughtReplyRow]] = [:]
    var lastError: String?
    var isLoading: Bool = false
    /// Per-owner cache so visiting another user's profile can show how
    /// many replies they've received (only the owner can read their own
    /// replies under RLS, so this is only ever populated for `me`).
    private var seenIDs: Set<String> = []

    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    /// Thought chat rooms are strictly 24-hour spaces — they live and die
    /// with the thought bubble. Any reply row older than 24h is filtered
    /// out everywhere so a room never lingers past its window.
    nonisolated private static func isFresh(_ row: WhisperThoughtReplyRow) -> Bool {
        guard let d = WhisperBackendService.parseISO(row.created_at) else { return false }
        return Date().timeIntervalSince(d) < 24 * 3600
    }

    /// Live session UID, lowercased — used by the community-chat sheet to
    /// right-align the owner's own bubbles without leaking Supabase types
    /// into the view layer.
    var mySessionUIDLower: String {
        (client.auth.currentSession?.user.id.uuidString
            ?? client.auth.currentUser?.id.uuidString
            ?? currentUID).lowercased()
    }

    private init() {}

    /// Best-effort resolver for the live user's display handle. Falls back
    /// through the cached username sources, then performs a live profile
    /// lookup before giving up — so we never write a generic "user" row
    /// even when the username caches haven't hydrated yet on cold start.
    private func resolveMyUsername() async -> String {
        let candidates: [String?] = [
            WhisperUserService.shared.me?.username,
            LeaderboardService.shared.savedUsername,
            AuthenticationService.shared.currentUser.username
        ]
        for c in candidates {
            if let s = c?.trimmingCharacters(in: .whitespacesAndNewlines),
               !s.isEmpty, s.lowercased() != "user" {
                return s
            }
        }
        let uid = client.auth.currentSession?.user.id.uuidString
            ?? client.auth.currentUser?.id.uuidString
            ?? currentUID
        if let p = await WhisperBackendService.shared.fetchPublicProfile(userID: uid),
           let u = p.username?.trimmingCharacters(in: .whitespacesAndNewlines),
           !u.isEmpty, u.lowercased() != "user" {
            return u
        }
        return ""
    }

    /// Unread count drives the badge dot on the thought bubble. Only
    /// counts replies still inside the 24-hour room window.
    var unreadCount: Int {
        incoming.filter { $0.read_at == nil && Self.isFresh($0) }.count
    }

    /// Sends a reply to a user's active thought. Returns true on success.
    /// `snapshot` captures the thought as it was when the user replied so
    /// the bubble in the owner's expand sheet always renders with the
    /// original style even if the thought rotates later.
    @discardableResult
    func send(
        toUserID: String,
        toUsername: String,
        thoughtText: String,
        thoughtStyle: String?,
        thoughtAccent: String?,
        thoughtEmoji: String?,
        thoughtColorHex: String?,
        body: String
    ) async -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isRemote else { return false }
        // Pull the live session UID so RLS (auth.uid() = replier_user_id) passes.
        // Lowercase to match Postgres uuid canonical form — otherwise the
        // optimistic row's UID won't match the server row's UID and the
        // sender sees their bubble twice.
        let sessionUID = (client.auth.currentSession?.user.id.uuidString
            ?? client.auth.currentUser?.id.uuidString
            ?? currentUID).lowercased()
        let toUserIDNorm = toUserID.lowercased()
        let resolvedUsername = await resolveMyUsername()
        guard !resolvedUsername.isEmpty else {
            lastError = "Couldn't send — finish setting up your profile first."
            return false
        }
        let myUsername = resolvedUsername
        let myAvatar = AuthenticationService.shared.currentUser.profileImageURL
        let payload = WhisperThoughtReplyInsert(
            thought_user_id: toUserIDNorm,
            replier_user_id: sessionUID,
            replier_username: myUsername,
            replier_avatar_url: myAvatar,
            body: String(trimmed.prefix(280)),
            thought_text: thoughtText,
            thought_style: thoughtStyle,
            thought_accent: thoughtAccent?.isEmpty == true ? nil : thoughtAccent,
            thought_emoji: thoughtEmoji?.isEmpty == true ? nil : thoughtEmoji,
            thought_color_hex: thoughtColorHex?.isEmpty == true ? nil : thoughtColorHex,
            thought_owner_username: toUsername
        )
        // Optimistically append so the sender sees their own bubble
        // instantly, even before the network round-trip completes.
        let optimistic = WhisperThoughtReplyRow(
            id: "local-\(UUID().uuidString)",
            thought_user_id: toUserIDNorm,
            replier_user_id: sessionUID,
            replier_username: myUsername,
            replier_avatar_url: myAvatar,
            body: payload.body,
            thought_text: payload.thought_text,
            thought_style: payload.thought_style,
            thought_accent: payload.thought_accent,
            thought_emoji: payload.thought_emoji,
            thought_color_hex: payload.thought_color_hex,
            thought_owner_username: payload.thought_owner_username,
            created_at: ISO8601DateFormatter().string(from: Date()),
            read_at: nil
        )
        let key = toUserIDNorm
        var current = groupByOwner[key] ?? []
        current.append(optimistic)
        groupByOwner[key] = current
        do {
            try await client
                .from("whisper_thought_replies")
                .insert(payload)
                .execute()
            lastError = nil
            return true
        } catch {
            // Roll back the optimistic row on failure so the UI doesn't lie.
            groupByOwner[key] = (groupByOwner[key] ?? []).filter { $0.id != optimistic.id }
            lastError = "Couldn't send reply: \(error.localizedDescription)"
            return false
        }
    }

    /// Owner posts a message into their own thought-replies community group.
    /// Stored as a row where `thought_user_id == replier_user_id == me`, with
    /// the current active thought snapshot so the pinned bubble keeps rendering
    /// even if the thought rotates later.
    @discardableResult
    func sendAsOwner(
        body: String,
        thoughtText: String,
        thoughtStyle: String?,
        thoughtAccent: String?,
        thoughtEmoji: String?,
        thoughtColorHex: String?
    ) async -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isRemote else { return false }
        let sessionUID = (client.auth.currentSession?.user.id.uuidString
            ?? client.auth.currentUser?.id.uuidString
            ?? currentUID).lowercased()
        let resolvedUsername = await resolveMyUsername()
        guard !resolvedUsername.isEmpty else {
            lastError = "Couldn't post — finish setting up your profile first."
            return false
        }
        let myUsername = resolvedUsername
        let myAvatar = AuthenticationService.shared.currentUser.profileImageURL
        let payload = WhisperThoughtReplyInsert(
            thought_user_id: sessionUID,
            replier_user_id: sessionUID,
            replier_username: myUsername,
            replier_avatar_url: myAvatar,
            body: String(trimmed.prefix(280)),
            thought_text: thoughtText,
            thought_style: thoughtStyle,
            thought_accent: thoughtAccent?.isEmpty == true ? nil : thoughtAccent,
            thought_emoji: thoughtEmoji?.isEmpty == true ? nil : thoughtEmoji,
            thought_color_hex: thoughtColorHex?.isEmpty == true ? nil : thoughtColorHex,
            thought_owner_username: myUsername
        )
        // Optimistic append on the owner's own incoming feed so the
        // composer bubble appears instantly without waiting for the
        // network round-trip + RLS read.
        let optimistic = WhisperThoughtReplyRow(
            id: "local-\(UUID().uuidString)",
            thought_user_id: sessionUID,
            replier_user_id: sessionUID,
            replier_username: myUsername,
            replier_avatar_url: myAvatar,
            body: payload.body,
            thought_text: payload.thought_text,
            thought_style: payload.thought_style,
            thought_accent: payload.thought_accent,
            thought_emoji: payload.thought_emoji,
            thought_color_hex: payload.thought_color_hex,
            thought_owner_username: payload.thought_owner_username,
            created_at: ISO8601DateFormatter().string(from: Date()),
            read_at: nil
        )
        incoming.insert(optimistic, at: 0)
        do {
            try await client
                .from("whisper_thought_replies")
                .insert(payload)
                .execute()
            lastError = nil
            await refreshForMe()
            return true
        } catch {
            // Roll back the optimistic row on failure.
            incoming.removeAll { $0.id == optimistic.id }
            lastError = "Couldn't send: \(error.localizedDescription)"
            return false
        }
    }

    /// Fetches my incoming thought replies. Fires a local notification
    /// for any reply we haven't surfaced yet (so users get a banner the
    /// first time the row appears in our cache).
    func refreshForMe() async {
        guard isRemote else { return }
        let sessionUID = client.auth.currentSession?.user.id.uuidString
            ?? client.auth.currentUser?.id.uuidString
            ?? currentUID
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched: [WhisperThoughtReplyRow] = try await client
                .from("whisper_thought_replies")
                .select()
                .eq("thought_user_id", value: sessionUID)
                .order("created_at", ascending: false)
                .limit(100)
                .execute()
                .value
            // 24-hour room: drop anything older than the thought window so
            // the chat room disappears when the thought does.
            let rows = fetched.filter(Self.isFresh)
            // Detect brand-new replies (not in seenIDs yet) so we can fire
            // a local notification banner.
            let firstRun = seenIDs.isEmpty && incoming.isEmpty
            let newRows = rows.filter { !seenIDs.contains($0.id) }
            for r in newRows {
                seenIDs.insert(r.id)
                // Never notify the owner about their OWN reply — posting in
                // your own thought room echoes back as a row here, which
                // used to fire a "you replied to your thought" banner.
                if !firstRun, r.read_at == nil,
                   r.replier_user_id.caseInsensitiveCompare(sessionUID) != .orderedSame {
                    fireLocalNotification(for: r)
                }
            }
            // On first run, treat existing rows as already-known so we
            // don't fire a banner storm for old replies.
            if firstRun {
                for r in rows { seenIDs.insert(r.id) }
            }
            // Preserve optimistic owner-posted rows that haven't surfaced
            // from the server yet so the owner's bubble doesn't flicker.
            let pending = incoming.filter { $0.id.hasPrefix("local-") }
            let keepPending = pending.filter { p in
                !rows.contains { r in
                    r.replier_user_id.caseInsensitiveCompare(p.replier_user_id) == .orderedSame
                        && r.body == p.body
                        && r.thought_user_id.caseInsensitiveCompare(p.thought_user_id) == .orderedSame
                }
            }
            incoming = rows + keepPending
        } catch {
            // Surface so the sheet can show *why* persistence is failing
            // (missing table, RLS, missing column, etc.) instead of just
            // silently dropping bubbles.
            lastError = "Couldn't load replies: \(error.localizedDescription)"
        }
    }

    /// Lightweight no-rollover refresh used by the open sheet to pick up
    /// new replies while the user is reading.
    func pollForOwner(_ ownerUID: String) async {
        await refreshForOwner(ownerUID)
    }

    /// Fetches the group-chat rows for an arbitrary thought owner. Used
    /// by repliers to open the same community chat from the owner's
    /// profile. Requires the group-read RLS policy to be installed; if
    /// the policy is still the legacy two-party one, the user will only
    /// see their own contributions + the owner's.
    func refreshForOwner(_ ownerUID: String) async {
        guard isRemote, !ownerUID.isEmpty else { return }
        do {
            let fetched: [WhisperThoughtReplyRow] = try await client
                .from("whisper_thought_replies")
                .select()
                .eq("thought_user_id", value: ownerUID)
                .order("created_at", ascending: false)
                .limit(200)
                .execute()
                .value
            // 24-hour room: expired replies never render, so stale rooms
            // stop persisting past the thought's lifetime.
            let rows = fetched.filter(Self.isFresh)
            // Preserve any optimistic local rows that haven't round-tripped
            // yet so the sender's bubble doesn't flicker away.
            let key = ownerUID.lowercased()
            let existing = groupByOwner[key] ?? []
            let pending = existing.filter { $0.id.hasPrefix("local-") }
            let serverIDs = Set(rows.map { $0.id })
            // Drop optimistic rows that now have a matching server row
            // (body + replier + thought_user). Best-effort dedupe.
            let keepPending = pending.filter { p in
                !rows.contains { r in
                    r.replier_user_id.caseInsensitiveCompare(p.replier_user_id) == .orderedSame
                        && r.body == p.body
                        && r.thought_user_id.caseInsensitiveCompare(p.thought_user_id) == .orderedSame
                }
            }
            _ = serverIDs
            groupByOwner[key] = rows + keepPending
        } catch {
            lastError = "Couldn't load chat: \(error.localizedDescription)"
        }
    }

    /// Marks every visible reply as read. Called when the user opens the
    /// expand sheet so the unread dot clears.
    func markAllRead() async {
        guard isRemote, !incoming.isEmpty else { return }
        let unreadIDs = incoming.filter { $0.read_at == nil }.map { $0.id }
        guard !unreadIDs.isEmpty else { return }
        struct ReadStamp: Codable, Sendable { let read_at: Date }
        do {
            try await client
                .from("whisper_thought_replies")
                .update(ReadStamp(read_at: Date()))
                .in("id", values: unreadIDs)
                .execute()
            // Reflect locally without round-tripping.
            let stamp = ISO8601DateFormatter().string(from: Date())
            incoming = incoming.map { row in
                guard row.read_at == nil else { return row }
                return WhisperThoughtReplyRow(
                    id: row.id,
                    thought_user_id: row.thought_user_id,
                    replier_user_id: row.replier_user_id,
                    replier_username: row.replier_username,
                    replier_avatar_url: row.replier_avatar_url,
                    body: row.body,
                    thought_text: row.thought_text,
                    thought_style: row.thought_style,
                    thought_accent: row.thought_accent,
                    thought_emoji: row.thought_emoji,
                    thought_color_hex: row.thought_color_hex,
                    thought_owner_username: row.thought_owner_username,
                    created_at: row.created_at,
                    read_at: stamp
                )
            }
        } catch {
            // Silent — the badge will simply persist until next launch.
        }
    }

    private func fireLocalNotification(for row: WhisperThoughtReplyRow) {
        let content = UNMutableNotificationContent()
        content.title = "@\(row.replier_username) replied to your thought"
        content.body = row.body
        content.sound = .default
        content.categoryIdentifier = "WHISPER_THOUGHT_REPLY"
        content.userInfo = [
            "kind": "whisper_thought_reply",
            "replyID": row.id,
            "replierUsername": row.replier_username
        ]
        let request = UNNotificationRequest(
            identifier: "whisper-thought-reply-\(row.id)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
