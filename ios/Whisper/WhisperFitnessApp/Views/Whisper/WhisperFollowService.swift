import Foundation
import Foundation
import Supabase

// MARK: - Supabase schema (run once in SQL editor)
//
// create table if not exists public.whisper_follows (
//   follower_id uuid not null references auth.users(id) on delete cascade,
//   followee_id uuid not null references auth.users(id) on delete cascade,
//   followee_username text not null,
//   created_at timestamptz not null default now(),
//   primary key (follower_id, followee_id)
// );
// create index if not exists whisper_follows_followee_idx
//   on public.whisper_follows (followee_id);
// alter table public.whisper_follows enable row level security;
// create policy "wf read all" on public.whisper_follows for select using (true);
// create policy "wf insert self" on public.whisper_follows
//   for insert with check (auth.uid() = follower_id);
// create policy "wf delete self" on public.whisper_follows
//   for delete using (auth.uid() = follower_id);

nonisolated struct WhisperFollowRow: Codable, Sendable, Hashable {
    let follower_id: String
    let followee_id: String
    let followee_username: String
    let created_at: String?
}

nonisolated struct WhisperFollowInsert: Codable, Sendable {
    let follower_id: String
    let followee_id: String
    let followee_username: String
}

/// Real Supabase-backed follow graph for Whisper. Independent from the
/// reciprocal friendships table — a follow is one-way like Instagram.
@MainActor
@Observable
final class WhisperFollowService {
    static let shared = WhisperFollowService()

    private let client = SupabaseService.shared.client

    /// Users I'm following (followee_id set + usernames).
    var following: Set<String> = []
    /// Users who follow me (lowercased follower_id set). Used by the DM
    /// privacy filter to route requests from non-mutuals into Requests.
    var followers: Set<String> = []
    /// Cached username lookup for followees.
    var followingUsernames: [String: String] = [:]
    /// Counts indexed by user_id. `@Observable` strips user-defined
    /// `didSet` observers, so mutations must call `syncWidgetCounts()`
    /// explicitly to push fresh values into the App Group.
    var followerCount: Int = 0
    var followingCount: Int = 0

    private func syncWidgetCounts() {
        WhisperWidgetSync.writeFollowCounts(followers: followerCount, following: followingCount)
    }
    /// Last surfaced error so callers can show a banner.
    var lastError: String?

    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    private var followersChannel: RealtimeChannelV2?
    private var followersTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    private var lastRefresh: Date?
    private var activeMutations: Int = 0

    private func invalidateRefresh() {
        lastRefresh = nil
        refreshTask?.cancel(); refreshTask = nil
    }

    private func beginMutation() { activeMutations += 1; invalidateRefresh() }
    private func endMutation() { activeMutations = max(0, activeMutations - 1); invalidateRefresh() }
    private(set) var hasLoadedFollowing: Bool = false

    private init() {}

    /// Subscribes to new rows in `whisper_follows` where `followee_id = me`.
    /// Posts a local banner via `WhisperNotificationService` for each new
    /// follower in real time.
    func startFollowersRealtime() {
        guard isRemote, followersChannel == nil else { return }
        let uid = currentUID
        let generation = AccountStorage.generation
        let channel = SupabaseService.shared.client.realtimeV2.channel("whisper-followers-\(uid)")
        followersChannel = channel
        let stream = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "whisper_follows",
            filter: "followee_id=eq.\(uid)"
        )
        followersTask = Task { [weak self] in
            await channel.subscribe()
            for await change in stream {
                guard let self, !Task.isCancelled, generation == AccountStorage.generation else { return }
                guard let row = try? change.decodeRecord(as: WhisperFollowRow.self, decoder: JSONDecoder()) else { continue }
                let key = row.follower_id.lowercased()
                self.invalidateRefresh()
                self.followers.insert(key)
                self.followerCount += 1
                // Look up the follower's username for a friendlier banner.
                let label: String
                if let cached = self.followingUsernames[key] {
                    label = cached
                } else if let p = await WhisperBackendService.shared.fetchPublicProfile(userID: row.follower_id),
                          let u = p.username {
                    label = u
                } else {
                    label = String(row.follower_id.prefix(6))
                }
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                WhisperNotificationService.shared.notifyNewFollower(
                    followerID: row.follower_id,
                    followerUsername: label
                )
            }
        }
    }

    func resetForCurrentAccount() {
        stopFollowersRealtime()
        refreshTask?.cancel(); refreshTask = nil
        lastRefresh = nil; hasLoadedFollowing = false; activeMutations = 0
        following = []; followers = []; followingUsernames = [:]
        followerCount = 0; followingCount = 0; lastError = nil
    }

    func stopFollowersRealtime() {
        followersTask?.cancel()
        followersTask = nil
        if let ch = followersChannel {
            Task { await ch.unsubscribe() }
        }
        followersChannel = nil
    }

    func isFollowing(userID: String) -> Bool {
        following.contains(userID.lowercased())
    }

    func isFollowedBy(userID: String) -> Bool {
        followers.contains(userID.lowercased())
    }

    /// Refresh both directions for the current user. Failures are
    /// swallowed without overwriting the existing counts so a flaky
    /// pull-to-refresh never flashes 0/0 on the profile while the real
    /// numbers were still cached and correct.
    func refreshIfStale(maxAge: TimeInterval = 60) async {
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < maxAge { return }
        await refresh()
    }

    func refresh() async {
        guard activeMutations == 0, !Task.isCancelled else { return }
        if let refreshTask { await refreshTask.value; return }
        let generation = AccountStorage.generation
        let owner = currentUID
        let task = Task { await self.loadFollows(owner: owner, generation: generation) }
        refreshTask = task
        await task.value
        if refreshTask == task { refreshTask = nil }
    }

    private func loadFollows(owner: String, generation: UUID) async {
        guard !Task.isCancelled, generation == AccountStorage.generation else { return }
        guard isRemote else {
            following = []
            followerCount = 0
            followingCount = 0
            syncWidgetCounts()
            return
        }
        async let outRowsResult: [WhisperFollowRow]? = {
            do {
                return try await client
                    .from("whisper_follows")
                    .select()
                    .eq("follower_id", value: owner)
                    .execute()
                    .value
            } catch {
                print("[Whisper] follows refresh (out) error: \(error)")
                return nil
            }
        }()
        async let inRowsResult: [WhisperFollowRow]? = {
            do {
                return try await client
                    .from("whisper_follows")
                    .select()
                    .eq("followee_id", value: owner)
                    .execute()
                    .value
            } catch {
                print("[Whisper] follows refresh (in) error: \(error)")
                return nil
            }
        }()
        let (out, inb) = await (outRowsResult, inRowsResult)
        guard !Task.isCancelled, generation == AccountStorage.generation else { return }
        lastError = out == nil || inb == nil ? "Some follow counts couldn't refresh. Pull down to try again." : nil
        if out != nil && inb != nil { lastRefresh = Date() }
        if let out {
            hasLoadedFollowing = true
            following = Set(out.map { $0.followee_id.lowercased() })
            followingUsernames = Dictionary(uniqueKeysWithValues: out.map { ($0.followee_id.lowercased(), $0.followee_username) })
            followingCount = out.count
        }
        if let inb {
            followers = Set(inb.map { $0.follower_id.lowercased() })
            followerCount = inb.count
        }
        syncWidgetCounts()
    }

    /// Result of attempting to follow another user. `requested` means the
    /// target is a private account and a pending follow request was filed
    /// instead of inserting the follow row.
    enum FollowOutcome: Equatable {
        case followed
        case requested
        case alreadyFollowing
        case failed
    }

    /// Pretty wrapper around `attemptFollow` for the existing call sites
    /// that just want a Bool. Returns `true` for `.followed` *or*
    /// `.requested` — both are "success" from a UI perspective.
    @discardableResult
    func follow(userID: String, username: String) async -> Bool {
        let outcome = await attemptFollow(userID: userID, username: username)
        if outcome == .followed || outcome == .requested { WhisperFeedback.followed() }
        return outcome == .followed || outcome == .requested || outcome == .alreadyFollowing
    }

    /// Follow attempt that surfaces whether the target is a private account
    /// (in which case a pending request is created instead of a direct
    /// follow). Use this when the UI needs to flip a button to "Requested".
    @discardableResult
    func attemptFollow(userID: String, username: String) async -> FollowOutcome {
        let account = currentUID; let epoch = AccountStorage.generation
        guard !Task.isCancelled else { return .failed }
        guard userID != currentUID else { return .failed }
        guard isRemote else {
            lastError = "You need to be signed in to follow people."
            return .failed
        }
        let key = userID.lowercased()
        if following.contains(key) { return .alreadyFollowing }
        beginMutation()
        defer { if epoch == AccountStorage.generation { endMutation() } }

        // Private-account check — if the target has flipped Private on,
        // file a follow request instead of inserting the follow row.
        // Failures fall through to the normal follow path so the feature
        // degrades gracefully if the `is_private` column hasn't been
        // provisioned yet.
        let targetPrivate = await WhisperUserService.shared.isPrivate(userID: userID)
        guard !Task.isCancelled, epoch == AccountStorage.generation, account == currentUID else { return .failed }
        if targetPrivate {
            let ok = await WhisperFollowRequestService.shared.request(
                targetID: userID,
                targetUsername: username
            )
            guard !Task.isCancelled, epoch == AccountStorage.generation, account == currentUID else { return .failed }
            if ok {
                Analytics.record("follow_requested", ["target": userID])
                return .requested
            }
            // Couldn't queue a request — surface the same error path as a
            // normal follow failure.
            lastError = "Couldn't send follow request to @\(username)."
            return .failed
        }

        // Optimistic update so the UI flips immediately.
        let wasFollowing = following.contains(key)
        if !wasFollowing {
            following.insert(key)
            followingUsernames[key] = username
            followingCount += 1
            syncWidgetCounts()
        }
        let row = WhisperFollowInsert(
            follower_id: account,
            followee_id: userID,
            followee_username: username
        )
        do {
            try await client
                .from("whisper_follows")
                .upsert(row, onConflict: "follower_id,followee_id")
                .execute()
            guard !Task.isCancelled, epoch == AccountStorage.generation, account == currentUID else { return .failed }
            lastError = nil
            Analytics.record("follow", ["target": userID])
            return .followed
        } catch is CancellationError {
            return .failed
        } catch {
            guard epoch == AccountStorage.generation, account == currentUID else { return .failed }
            // Roll back optimistic state.
            if !wasFollowing {
                following.remove(key)
                followingUsernames.removeValue(forKey: key)
                followingCount = max(0, followingCount - 1)
                syncWidgetCounts()
            }
            lastError = "Couldn't follow @\(username): \(error.localizedDescription)"
            WhisperErrorService.shared.report("Couldn't follow @\(username). Try again.")
            Analytics.record("follow_failed", ["reason": String(error.localizedDescription.prefix(80))])
            print("[Whisper] follow error: \(error)")
            return .failed
        }
    }

    /// Fetches full Whisper profile rows for users the current user follows.
    /// Used to power Instagram-style "Suggested" lists in the New Message sheet.
    func followingProfiles(limit: Int = 50) async -> [WhisperUserRow] {
        guard isRemote, !following.isEmpty else { return [] }
        let ids = Array(following).prefix(limit).map { $0 }
        do {
            let rows: [WhisperUserRow] = try await client
                .from("whisper_profiles")
                .select()
                .in("user_id", values: ids)
                .execute()
                .value
            return rows
        } catch {
            // Fallback: synthesize lightweight rows from cached usernames so
            // the suggestions list still renders even if the profiles table
            // query fails.
            return ids.compactMap { id in
                guard let name = followingUsernames[id] else { return nil }
                return WhisperUserRow(
                    user_id: id,
                    username: name,
                    display_name: nil,
                    bio: nil,
                    interests: nil,
                    profile_image_url: nil,
                    onboarded_at: nil,
                    is_private: nil
                )
            }
        }
    }

    /// Lists the users that follow `userID` (returns lightweight rows with
    /// the follower's user_id + cached username). Used by the followers list.
    func followers(forUserID userID: String, limit: Int = 200) async -> [WhisperFollowRow] {
        guard isRemote else { return [] }
        do {
            let rows: [WhisperFollowRow] = try await client
                .from("whisper_follows")
                .select()
                .eq("followee_id", value: userID)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            return rows
        } catch {
            print("[Whisper] followers error: \(error)")
            return []
        }
    }

    /// Lists the users that `userID` follows. Returns rows including
    /// `followee_id` + cached `followee_username` so the UI can render names
    /// without a second roundtrip.
    func following(forUserID userID: String, limit: Int = 200) async -> [WhisperFollowRow] {
        guard isRemote else { return [] }
        do {
            let rows: [WhisperFollowRow] = try await client
                .from("whisper_follows")
                .select()
                .eq("follower_id", value: userID)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            return rows
        } catch {
            print("[Whisper] following error: \(error)")
            return []
        }
    }

    /// Number of followers for any user (count of whisper_follows rows where
    /// followee_id = userID). Used by `WhisperUserProfileView`.
    func followerCount(forUserID userID: String) async -> Int {
        guard isRemote else { return 0 }
        do {
            let response = try await client.from("whisper_follows")
                .select("followee_id", head: true, count: .exact)
                .eq("followee_id", value: userID).execute()
            return response.count ?? 0
        } catch {
            return 0
        }
    }

    /// Statistics use the same authenticated RLS visibility as list reads, without
    /// transferring every relationship or imposing the member browser's 200-row cap.
    func followingCount(forUserID userID: String) async -> Int {
        guard isRemote else { return 0 }
        do {
            let response = try await client.from("whisper_follows")
                .select("follower_id", head: true, count: .exact)
                .eq("follower_id", value: userID).execute()
            return response.count ?? 0
        } catch { return 0 }
    }

    @discardableResult
    func unfollow(userID: String) async -> Bool {
        let account = currentUID; let epoch = AccountStorage.generation
        guard !Task.isCancelled else { return false }
        guard isRemote else { return false }
        let key = userID.lowercased()
        beginMutation()
        defer { if epoch == AccountStorage.generation { endMutation() } }
        let cachedUsername = followingUsernames[key]
        let wasFollowing = following.contains(key)
        if wasFollowing {
            following.remove(key)
            followingUsernames.removeValue(forKey: key)
            followingCount = max(0, followingCount - 1)
            syncWidgetCounts()
        }
        do {
            try await client
                .from("whisper_follows")
                .delete()
                .eq("follower_id", value: currentUID)
                .eq("followee_id", value: userID)
                .execute()
            guard !Task.isCancelled, epoch == AccountStorage.generation, account == currentUID else { return false }
            lastError = nil
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard epoch == AccountStorage.generation, account == currentUID else { return false }
            if wasFollowing {
                following.insert(key)
                if let u = cachedUsername { followingUsernames[key] = u }
                followingCount += 1
                syncWidgetCounts()
            }
            lastError = "Couldn't unfollow: \(error.localizedDescription)"
            print("[Whisper] unfollow error: \(error)")
            return false
        }
    }

    /// Removes one of MY followers — deletes their follow edge pointing at
    /// me (Instagram's "Remove follower"). Optimistically drops the local
    /// follower entry and restores it if the delete fails.
    @discardableResult
    func removeFollower(userID: String) async -> Bool {
        guard isRemote else { return false }
        let epoch = AccountStorage.generation
        beginMutation()
        defer { if epoch == AccountStorage.generation { endMutation() } }
        let key = userID.lowercased()
        let wasFollower = followers.contains(key)
        if wasFollower {
            followers.remove(key)
            followerCount = max(0, followerCount - 1)
            syncWidgetCounts()
        }
        do {
            try await client
                .from("whisper_follows")
                .delete()
                .eq("follower_id", value: userID)
                .eq("followee_id", value: currentUID)
                .execute()
            guard !Task.isCancelled, epoch == AccountStorage.generation else { return false }
            lastError = nil
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard epoch == AccountStorage.generation else { return false }
            if wasFollower {
                followers.insert(key)
                followerCount += 1
                syncWidgetCounts()
            }
            lastError = "Couldn't remove follower: \(error.localizedDescription)"
            print("[Whisper] removeFollower error: \(error)")
            return false
        }
    }
}
