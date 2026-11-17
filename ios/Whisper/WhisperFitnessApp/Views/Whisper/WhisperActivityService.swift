import Foundation
import Supabase

/// Real-data backing for the in-app Activity tab (the bell screen). Aggregates
/// recent likes + comments on the current user's posts, plus new followers,
/// into a single chronological feed. Read-state is tracked locally via
/// `UserDefaults` so the bell unread dot clears the first time the user
/// opens Activity after new events come in.
@MainActor
@Observable
final class WhisperActivityService {
    static let shared = WhisperActivityService()

    nonisolated struct Item: Identifiable, Sendable, Hashable {
        enum Kind: String, Sendable { case like, comment, follow }
        let id: String
        let kind: Kind
        let actorUserID: String
        let actorUsername: String
        let postID: String?
        let commentBody: String?
        let createdAt: Date
        /// First media URL of the post the activity refers to (likes /
        /// comments). Used by the Activity row to show a thumbnail at
        /// the trailing edge — Instagram parity.
        let postMediaURL: String?
    }

    var items: [Item] = []
    var isLoading: Bool = false

    private let client = SupabaseService.shared.client
    @ObservationIgnored private let refresh = WhisperAccountRefresh()
    private let lastReadKey = "whisper.activity.lastReadAt.v1"

    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    /// Last time the user opened the Activity tab; everything newer is unread.
    /// Mirrored to Supabase via `whisper_activity_state.last_read_at` so the
    /// bell badge stays consistent across devices instead of being a
    /// per-device UserDefaults bool.
    var lastReadAt: Date {
        let t = UserDefaults.standard.double(forKey: lastReadKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : .distantPast
    }

    var unreadCount: Int {
        let cutoff = lastReadAt
        return items.reduce(0) { $0 + ($1.createdAt > cutoff ? 1 : 0) }
    }

    private init() {}

    // MARK: - Read state

    /// Removes any cached activity items that reference the given post id —
    /// used when tapping a like/comment row resolves to a deleted post so
    /// the orphan row disappears from the bell screen.
    func removeItems(forPostID postID: String) {
        let pid = postID.lowercased()
        items.removeAll { ($0.postID?.lowercased() ?? "") == pid }
    }

    func markAllRead() {
        let now = Date()
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastReadKey)
        Task { await self.pushReadState(now) }
    }

    /// Pulls the server-side `last_read_at` so a fresh install / new device
    /// inherits whatever cutoff the user already has. Only adopts the
    /// remote value if it's newer than the local one — protects against
    /// a flaky offline window resetting a freshly-read state.
    func refreshReadStateFromServer() async {
        guard isRemote else { return }
        let generation = AccountStorage.generation
        let owner = currentUID
        do {
            let rows: [ActivityStateRow] = try await client
                .from("whisper_activity_state")
                .select("user_id,last_read_at")
                .eq("user_id", value: currentUID)
                .limit(1)
                .execute()
                .value
            guard !Task.isCancelled, generation == AccountStorage.generation, owner == currentUID,
                  let raw = rows.first?.last_read_at,
                  let remote = WhisperBackendService.parseISO(raw) else { return }
            if remote > lastReadAt {
                UserDefaults.standard.set(remote.timeIntervalSince1970, forKey: lastReadKey)
            }
        } catch {
            // Silent — table may not exist yet on first run.
        }
    }

    private func pushReadState(_ when: Date) async {
        guard isRemote else { return }
        let iso = ISO8601DateFormatter().string(from: when)
        let payload = ActivityStateUpsert(user_id: currentUID, last_read_at: iso)
        do {
            try await client
                .from("whisper_activity_state")
                .upsert(payload, onConflict: "user_id")
                .execute()
        } catch {
            // Silent — local UserDefaults is still authoritative.
        }
    }

    nonisolated struct ActivityStateRow: Decodable, Sendable {
        let user_id: String
        let last_read_at: String?
    }
    nonisolated struct ActivityStateUpsert: Encodable, Sendable {
        let user_id: String
        let last_read_at: String
    }

    // MARK: - Fetch

    /// Pulls the freshest ~40 activity events for the current user. Safe to
    /// call repeatedly — replaces `items` atomically on success, leaves the
    /// previous cache in place on failure.
    func fetch() async {
        await refresh.run { [self] generation in await loadActivity(generation: generation) }
    }

    private func loadActivity(generation: UUID) async {
        guard isRemote, !Task.isCancelled, generation == AccountStorage.generation else { return }
        isLoading = true
        defer { if generation == AccountStorage.generation { isLoading = false } }

        let me = currentUID
        // Step 1: my recent post ids (last ~60 posts is plenty for the bell).
        // Track success vs failure separately so a transient Supabase blip
        // doesn't blow away the cached items list (the "refresh clears
        // everything" bug). If ANY upstream query fails outright, we keep
        // the previous items and bail.
        async let myPostsRowsTask: [MyPostRow]? = {
            do {
                return try await client
                    .from("whisper_posts")
                    .select("id")
                    .eq("user_id", value: me)
                    .order("created_at", ascending: false)
                    .limit(60)
                    .execute()
                    .value
            } catch { return nil }
        }()

        async let followsTask: [WhisperFollowRow]? = {
            do {
                return try await client
                    .from("whisper_follows")
                    .select()
                    .eq("followee_id", value: me)
                    .order("created_at", ascending: false)
                    .limit(30)
                    .execute()
                    .value
            } catch { return nil }
        }()

        let (myPostsRowsOpt, followsOpt) = await (myPostsRowsTask, followsTask)
        guard !Task.isCancelled, generation == AccountStorage.generation, me == currentUID else { return }

        // Hard-fail guard: if both upstream queries errored, do NOT touch
        // `items` — leaves whatever was on screen before the refresh in
        // place so the user never sees a flash-to-empty list.
        if myPostsRowsOpt == nil && followsOpt == nil { return }

        let myPostsRows = myPostsRowsOpt ?? []
        let follows = followsOpt ?? []
        let postIDs = myPostsRows.map { $0.id }

        // Step 3: recent likes + comments on those posts.
        async let likesTask: [LikeWithDate] = await fetchLikes(postIDs: postIDs, excluding: me)
        async let commentsTask: [WhisperCommentRow] = await fetchRecentComments(postIDs: postIDs, excluding: me)
        async let postMediaTask: [String: String] = await fetchPostMedia(postIDs: postIDs)
        let (likes, comments, postMedia) = await (likesTask, commentsTask, postMediaTask)
        guard !Task.isCancelled, generation == AccountStorage.generation, me == currentUID else { return }

        // Resolve every actor uid in one batch so each row has a real
        // @username (likes don't carry one inline).
        var uids = Set<String>()
        for l in likes { uids.insert(l.user_id) }
        for c in comments { uids.insert(c.user_id) }
        for f in follows { uids.insert(f.follower_id) }
        let profiles = await WhisperBackendService.shared.fetchPublicProfiles(userIDs: Array(uids))
        guard !Task.isCancelled, generation == AccountStorage.generation, me == currentUID else { return }

        func username(for uid: String, fallback: String? = nil) -> String {
            if let u = profiles[uid]?.username, !u.isEmpty { return u }
            if let fb = fallback, !fb.isEmpty { return fb }
            return String(uid.prefix(6))
        }

        var out: [Item] = []
        out.reserveCapacity(likes.count + comments.count + follows.count)
        for l in likes {
            guard let date = WhisperBackendService.parseISO(l.created_at) else { continue }
            out.append(Item(
                id: "like:\(l.post_id):\(l.user_id)",
                kind: .like,
                actorUserID: l.user_id,
                actorUsername: username(for: l.user_id),
                postID: l.post_id,
                commentBody: nil,
                createdAt: date,
                postMediaURL: postMedia[l.post_id]
            ))
        }
        for c in comments {
            guard let date = WhisperBackendService.parseISO(c.created_at) else { continue }
            out.append(Item(
                id: "comment:\(c.id)",
                kind: .comment,
                actorUserID: c.user_id,
                actorUsername: username(for: c.user_id, fallback: c.username),
                postID: c.post_id,
                commentBody: c.body,
                createdAt: date,
                postMediaURL: postMedia[c.post_id]
            ))
        }
        for f in follows {
            guard let date = WhisperBackendService.parseISO(f.created_at) else { continue }
            out.append(Item(
                id: "follow:\(f.follower_id)",
                kind: .follow,
                actorUserID: f.follower_id,
                // No fallback — `followee_username` is *me*, not the
                // follower. If the profile lookup fails, let `username(for:)`
                // fall through to a prefix-of-uid so the row never reads
                // "@<my own handle> started following you".
                actorUsername: username(for: f.follower_id),
                postID: nil,
                commentBody: nil,
                createdAt: date,
                postMediaURL: nil
            ))
        }
        let merged = out.sorted { $0.createdAt > $1.createdAt }
        // Never overwrite a non-empty cache with an empty list — that's the
        // "refresh clears notifications" symptom. If the fetch genuinely
        // returned nothing AND we previously had items, keep what we had;
        // the next successful refresh will reconcile.
        if merged.isEmpty && !items.isEmpty { return }
        items = merged
    }

    // MARK: - Helpers

    private struct MyPostRow: Decodable, Sendable { let id: String }
    private struct LikeWithDate: Decodable, Sendable {
        let post_id: String
        let user_id: String
        let created_at: String?
    }

    private func fetchLikes(postIDs: [String], excluding me: String) async -> [LikeWithDate] {
        guard !postIDs.isEmpty else { return [] }
        do {
            let rows: [LikeWithDate] = try await client
                .from("whisper_post_likes")
                .select("post_id,user_id,created_at")
                .in("post_id", values: postIDs)
                .neq("user_id", value: me)
                .order("created_at", ascending: false)
                .limit(40)
                .execute()
                .value
            return rows
        } catch {
            return []
        }
    }

    private struct PostMediaRow: Decodable, Sendable {
        let id: String
        let media_urls: [String]?
    }

    /// One-shot fetch of every referenced post's first media URL so the
    /// Activity row can show a thumbnail next to like/comment events.
    private func fetchPostMedia(postIDs: [String]) async -> [String: String] {
        guard !postIDs.isEmpty else { return [:] }
        do {
            let rows: [PostMediaRow] = try await client
                .from("whisper_posts")
                .select("id,media_urls")
                .in("id", values: postIDs)
                .execute()
                .value
            var map: [String: String] = [:]
            for r in rows {
                if let first = r.media_urls?.first, !first.isEmpty {
                    map[r.id] = first
                }
            }
            return map
        } catch {
            return [:]
        }
    }

    private func fetchRecentComments(postIDs: [String], excluding me: String) async -> [WhisperCommentRow] {
        guard !postIDs.isEmpty else { return [] }
        do {
            let rows: [WhisperCommentRow] = try await client
                .from("whisper_post_comments")
                .select()
                .in("post_id", values: postIDs)
                .neq("user_id", value: me)
                .order("created_at", ascending: false)
                .limit(40)
                .execute()
                .value
            return rows
        } catch {
            return []
        }
    }
}
