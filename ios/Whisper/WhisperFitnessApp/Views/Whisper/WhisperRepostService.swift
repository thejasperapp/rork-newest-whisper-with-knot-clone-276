import Foundation
import Supabase

// MARK: - Supabase schema (optional — service degrades to local-only if missing)
//
// create table if not exists public.whisper_reposts (
//   user_id uuid not null references auth.users(id) on delete cascade,
//   post_id uuid not null,
//   created_at timestamptz not null default now(),
//   primary key (user_id, post_id)
// );
// create index if not exists whisper_reposts_post_idx
//   on public.whisper_reposts (post_id);
// alter table public.whisper_reposts enable row level security;
// create policy "wr read all" on public.whisper_reposts for select using (true);
// create policy "wr insert self" on public.whisper_reposts
//   for insert with check (auth.uid() = user_id);
// create policy "wr delete self" on public.whisper_reposts
//   for delete using (auth.uid() = user_id);

nonisolated struct WhisperRepostRow: Codable, Sendable {
    let user_id: String
    let post_id: String
}

/// Tracks which posts the current user has reposted. Backed by Supabase
/// when available; falls back to UserDefaults for guest / offline use so
/// the heart-style toggle still works without a server round-trip.
@MainActor
@Observable
final class WhisperRepostService {
    static let shared = WhisperRepostService()

    private let client = SupabaseService.shared.client
    private let storageKey = "whisper.repost.ownedIDs.v2"
    private var stateGeneration: UUID = AccountStorage.generation
    private(set) var contentRevision: Int = 0
    private var pendingMutations: Set<String> = []
    private var mutationRevision: Int = 0

    /// Set of lowercased post IDs the current user has reposted.
    private(set) var repostedPostIDs: Set<String> = []
    /// Aggregate repost counts keyed by lowercased post ID. Used by the
    /// feed action row.
    private(set) var counts: [String: Int] = [:]
    private var tableDisabled: Bool = false

    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    private init() {
        let arr = AccountStorage.object(forKey: storageKey) as? [String] ?? []
        repostedPostIDs = Set(arr.map { $0.lowercased() })
    }

    private func ensureAccount() {
        guard stateGeneration != AccountStorage.generation else { return }
        stateGeneration = AccountStorage.generation
        repostedPostIDs = Set((AccountStorage.object(forKey: storageKey) as? [String] ?? []).map { $0.lowercased() })
        pendingMutations = []; counts = [:]; fetchedCountIDs = []; tableDisabled = false
        mutationRevision += 1
    }

    func isReposted(_ postID: String) -> Bool {
        guard stateGeneration == AccountStorage.generation else { return false }
        return repostedPostIDs.contains(postID.lowercased())
    }

    func count(for postID: String) -> Int {
        guard stateGeneration == AccountStorage.generation else { return 0 }
        return counts[postID.lowercased()] ?? 0
    }

    /// Read confirmed account-owned reposts. Loading never replays legacy local IDs as writes.
    func refreshMine() async {
        ensureAccount()
        let generation = AccountStorage.generation
        let owner = currentUID
        let revision = mutationRevision
        guard isRemote, !tableDisabled else { return }
        do {
            let rows: [WhisperRepostRow] = try await client
                .from("whisper_reposts")
                .select()
                .eq("user_id", value: owner)
                .execute()
                .value
            guard !Task.isCancelled, generation == AccountStorage.generation, revision == mutationRevision else { return }
            let server = Set(rows.map { $0.post_id.lowercased() })
            repostedPostIDs = server.subtracting(pendingMutations).union(repostedPostIDs.intersection(pendingMutations))
            persistLocal()
        } catch {
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            let msg = error.localizedDescription.lowercased()
            if msg.contains("relation") && msg.contains("does not exist") {
                tableDisabled = true
            }
        }
    }

    /// Toggle repost state. Optimistic — flips local state immediately,
    /// rolls back on failure. Returns the new state.
    @discardableResult
    func toggle(postID: String) async -> Bool {
        ensureAccount()
        let epoch = AccountStorage.generation
        let owner = currentUID
        let key = postID.lowercased()
        guard !pendingMutations.contains(key) else { return repostedPostIDs.contains(key) }
        pendingMutations.insert(key); mutationRevision += 1
        defer {
            if epoch == AccountStorage.generation {
                pendingMutations.remove(key); mutationRevision += 1; contentRevision += 1
            }
        }
        let wasReposted = repostedPostIDs.contains(key)
        let previousCount = counts[key]
        if wasReposted {
            repostedPostIDs.remove(key)
            counts[key] = max((counts[key] ?? 1) - 1, 0)
        } else {
            repostedPostIDs.insert(key)
            counts[key] = (counts[key] ?? 0) + 1
        }
        persistLocal()
        let nowReposted = !wasReposted

        guard isRemote, !tableDisabled else { return nowReposted }

        do {
            if nowReposted {
                // Plain INSERT — exactly like the likes path, which works.
                // (An upsert compiles to INSERT … ON CONFLICT DO UPDATE and
                // the table has no UPDATE policy, so RLS rejected every
                // repost and the old code silently rolled the heart back.)
                let row = WhisperRepostRow(user_id: owner, post_id: postID)
                try await client
                    .from("whisper_reposts")
                    .insert(row)
                    .execute()
            } else {
                try await client
                    .from("whisper_reposts")
                    .delete()
                    .eq("user_id", value: owner)
                    .eq("post_id", value: postID)
                    .execute()
            }
            guard epoch == AccountStorage.generation else { return false }
            return nowReposted
        } catch {
            guard epoch == AccountStorage.generation else { return false }
            let msg = error.localizedDescription.lowercased()
            // Already reposted server-side — the optimistic state is right.
            if msg.contains("duplicate") || msg.contains("23505") {
                return nowReposted
            }
            print("[Whisper] Repost update failed")
            if msg.contains("relation") && msg.contains("does not exist") {
                tableDisabled = true
            }
            if wasReposted { repostedPostIDs.insert(key) } else { repostedPostIDs.remove(key) }
            counts[key] = previousCount
            persistLocal()
            return wasReposted
        }
    }

    /// Post IDs whose repost count has already been fetched from the
    /// server this session — lets feed cards skip redundant round-trips
    /// when they remount during scrolling.
    private var fetchedCountIDs: Set<String> = []

    /// Session-cached variant of `fetchCount` — returns the cached count
    /// when this post was already fetched once this session. Feed cards use
    /// this; detail views keep calling `fetchCount` for a fresh number.
    func fetchCountIfNeeded(for postID: String) async -> Int {
        let key = postID.lowercased()
        if fetchedCountIDs.contains(key) { return counts[key] ?? 0 }
        return await fetchCount(for: postID)
    }

    /// Fetch the live repost count for a post (head-count). Falls back to
    /// the local optimistic counter when the table is unavailable.
    func fetchCount(for postID: String) async -> Int {
        ensureAccount()
        let generation = AccountStorage.generation
        let key = postID.lowercased()
        guard !tableDisabled else { return counts[key] ?? 0 }
        do {
            let resp = try await client
                .from("whisper_reposts")
                .select("post_id", head: true, count: .exact)
                .eq("post_id", value: postID)
                .execute()
            guard !Task.isCancelled, generation == AccountStorage.generation else { return 0 }
            let n = resp.count ?? 0
            counts[key] = n
            fetchedCountIDs.insert(key)
            return n
        } catch {
            let msg = error.localizedDescription.lowercased()
            if msg.contains("relation") && msg.contains("does not exist") {
                tableDisabled = true
            }
            return counts[key] ?? 0
        }
    }

    private func persistLocal() {
        guard stateGeneration == AccountStorage.generation else { return }
        AccountStorage.set(Array(repostedPostIDs), forKey: storageKey)
    }

    /// Fetches the full rows for posts the current user has reposted.
    /// Returns them in reverse-chronological order by `created_at` of the
    /// underlying post so the profile tab reads newest-first. When the
    /// reposts table is unreachable, falls back to the locally-persisted
    /// repost IDs so the profile tab still works.
    func fetchPublicReposts(userID: String, limit: Int = 100) async throws -> [WhisperPostRow] {
        ensureAccount()
        let generation = AccountStorage.generation
        let revision = mutationRevision
        let rows: [WhisperRepostRow] = try await client.from("whisper_reposts").select()
            .eq("user_id", value: userID).order("created_at", ascending: false).limit(limit).execute().value
        guard !Task.isCancelled, generation == AccountStorage.generation else { throw CancellationError() }
        if userID.lowercased() == currentUID.lowercased(), revision == mutationRevision {
            let server = Set(rows.map { $0.post_id.lowercased() })
            if rows.count < limit { repostedPostIDs = server.subtracting(pendingMutations).union(repostedPostIDs.intersection(pendingMutations)) }
            else { repostedPostIDs.formUnion(server.subtracting(pendingMutations)) }
            persistLocal()
        }
        guard !rows.isEmpty else { return [] }
        let ids = rows.map(\.post_id)
        let posts: [WhisperPostRow] = try await client.from("whisper_posts").select()
            .in("id", values: ids).execute().value
        guard !Task.isCancelled, generation == AccountStorage.generation else { throw CancellationError() }
        WhisperBackendService.shared.schedulePostLikes(postIDs: posts.map(\.id))
        let byID = Dictionary(posts.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0.lowercased()] }
    }

    func fetchRepostedPosts(limit: Int = 200, userID: String? = nil) async -> [WhisperPostRow] {
        let target = userID ?? currentUID
        let generation = AccountStorage.generation
        var ids: [String] = []
        if isRemote && !tableDisabled {
            do {
                let rows: [WhisperRepostRow] = try await client
                    .from("whisper_reposts")
                    .select()
                    .eq("user_id", value: target)
                    .order("created_at", ascending: false)
                    .limit(limit)
                    .execute()
                    .value
                ids = rows.map { $0.post_id }
            } catch {
                let msg = error.localizedDescription.lowercased()
                if msg.contains("relation") && msg.contains("does not exist") {
                    tableDisabled = true
                }
                print("[Whisper] fetchRepostedPosts error: \(error)")
            }
        }
        // Local fallback — the optimistic set knows what the user reposted
        // even when the server table is missing or the fetch failed.
        guard !Task.isCancelled, generation == AccountStorage.generation else { return [] }
        if ids.isEmpty && userID == nil { ids = Array(repostedPostIDs) }
        guard !ids.isEmpty else { return [] }
        do {
            let posts: [WhisperPostRow] = try await client
                .from("whisper_posts")
                .select()
                .in("id", values: ids)
                .execute()
                .value
            guard !Task.isCancelled, generation == AccountStorage.generation else { return [] }
            WhisperBackendService.shared.schedulePostLikes(postIDs: posts.map(\.id))
            let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1.lowercased(), $0) })
            return posts.sorted { (order[$0.id.lowercased()] ?? .max) < (order[$1.id.lowercased()] ?? .max) }
        } catch {
            print("[Whisper] fetchRepostedPosts posts error: \(error)")
            return []
        }
    }
}
