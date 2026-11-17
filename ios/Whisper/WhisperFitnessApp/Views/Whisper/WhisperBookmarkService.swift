import Foundation
import Supabase

// MARK: - Supabase schema (run once in SQL editor)
//
// create table if not exists public.whisper_bookmarks (
//   user_id uuid not null references auth.users(id) on delete cascade,
//   post_id uuid not null references public.whisper_posts(id) on delete cascade,
//   created_at timestamptz not null default now(),
//   primary key (user_id, post_id)
// );
// create index if not exists whisper_bookmarks_user_idx
//   on public.whisper_bookmarks (user_id, created_at desc);
// alter table public.whisper_bookmarks enable row level security;
// drop policy if exists "wb read own" on public.whisper_bookmarks;
// create policy "wb read own" on public.whisper_bookmarks
//   for select using (auth.uid() = user_id);
// drop policy if exists "wb insert own" on public.whisper_bookmarks;
// create policy "wb insert own" on public.whisper_bookmarks
//   for insert with check (auth.uid() = user_id);
// drop policy if exists "wb delete own" on public.whisper_bookmarks;
// create policy "wb delete own" on public.whisper_bookmarks
//   for delete using (auth.uid() = user_id);

nonisolated struct WhisperBookmarkRow: Codable, Sendable, Hashable {
    let user_id: String
    let post_id: String
    let created_at: String?
}

nonisolated struct WhisperBookmarkInsert: Codable, Sendable {
    let user_id: String
    let post_id: String
}

/// Persistent bookmarks for Whisper posts, backed by Supabase. Mirrors the
/// like service in shape so it slots into existing post UI cleanly.
///
/// Categories are stored *locally* (UserDefaults) keyed by the current user.
/// That keeps the feature working without a server migration — each device
/// keeps its own folders for organizing saved posts.
@MainActor
@Observable
final class WhisperBookmarkService {
    static let shared = WhisperBookmarkService()

    private let client = SupabaseService.shared.client
    private var bookmarkRevision = UUID()
    private var bookmarkRead: Task<[WhisperBookmarkRow], Error>?
    private var bookmarkReadKey: String?
    private var bookmarkReadID = UUID()
    private var mutatingPostIDs: Set<String> = []

    func resetForAccountChange() {
        bookmarkRevision = UUID(); bookmarkReadID = UUID()
        bookmarkRead?.cancel(); bookmarkRead = nil; bookmarkReadKey = nil
        mutatingPostIDs = []; bookmarkedPostIDs = []; categoryByPostID = [:]; lastError = nil
        loadLocalCategories()
    }

    private func readBookmarks(owner: String, generation: UUID) async throws -> [WhisperBookmarkRow] {
        let key = "\(owner)/\(generation)/\(bookmarkRevision)"
        if bookmarkReadKey == key, let bookmarkRead { return try await bookmarkRead.value }
        bookmarkRead?.cancel()
        let requestID = UUID(); bookmarkReadID = requestID; bookmarkReadKey = key
        let task = Task<[WhisperBookmarkRow], Error> {
            try await client.from("whisper_bookmarks").select().eq("user_id", value: owner)
                .order("created_at", ascending: false).limit(500).execute().value
        }
        bookmarkRead = task
        defer { if bookmarkReadID == requestID { bookmarkRead = nil; bookmarkReadKey = nil } }
        return try await task.value
    }

    /// Set of post UUIDs the local user has bookmarked. Updated optimistically
    /// from `toggle(postID:)` and refreshed by `refresh()`.
    var bookmarkedPostIDs: Set<String> = []
    var lastError: String?

    /// User-defined categories, persisted locally.
    static let defaultCategories: [String] = ["All", "Recipes", "Workouts", "Inspo", "Reels"]
    var categories: [String] = []
    /// post_id -> category name. Posts not in the map fall back to "All".
    var categoryByPostID: [String: String] = [:]

    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }
    private var categoriesKey: String { "whisper.bookmark.categories.\(currentUID)" }
    private var assignmentsKey: String { "whisper.bookmark.assignments.\(currentUID)" }

    private init() {
        loadLocalCategories()
    }

    // MARK: - Categories (local-only)

    private func loadLocalCategories() {
        let defaults = UserDefaults.standard
        if let stored = defaults.array(forKey: categoriesKey) as? [String], !stored.isEmpty {
            categories = stored
        } else {
            categories = Self.defaultCategories
        }
        categoryByPostID = defaults.dictionary(forKey: assignmentsKey) as? [String: String] ?? [:]
    }

    private func persistCategories() {
        let d = UserDefaults.standard
        d.set(categories, forKey: categoriesKey)
        d.set(categoryByPostID, forKey: assignmentsKey)
    }

    func addCategory(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !categories.contains(where: { $0.lowercased() == trimmed.lowercased() }) else { return }
        categories.append(trimmed)
        persistCategories()
    }

    func removeCategory(_ name: String) {
        guard name != "All" else { return }
        categories.removeAll { $0 == name }
        // Move any posts in that category back to "All" (unassigned).
        for (postID, cat) in categoryByPostID where cat == name {
            categoryByPostID.removeValue(forKey: postID)
        }
        persistCategories()
    }

    func category(forPostID id: String) -> String {
        categoryByPostID[id] ?? "All"
    }

    func setCategory(_ name: String, forPostID id: String) {
        if name == "All" {
            categoryByPostID.removeValue(forKey: id)
        } else {
            categoryByPostID[id] = name
        }
        persistCategories()
    }

    /// Pulls the current user's bookmarks. Safe no-op for guests.
    func refresh() async {
        loadLocalCategories()
        guard isRemote else { bookmarkedPostIDs = []; return }
        let owner = currentUID, generation = AccountStorage.generation, revision = bookmarkRevision
        do {
            let rows = try await readBookmarks(owner: owner, generation: generation)
            guard !Task.isCancelled, owner == currentUID, generation == AccountStorage.generation,
                  revision == bookmarkRevision, mutatingPostIDs.isEmpty else { return }
            bookmarkedPostIDs = Set(rows.map { $0.post_id })
        } catch {
            // Silently ignore — table may not exist on a fresh project.
            print("[Whisper] bookmarks refresh error: \(error)")
        }
    }

    func isBookmarked(_ postID: String) -> Bool {
        bookmarkedPostIDs.contains(postID)
    }

    /// Toggles a bookmark and returns the resulting state. Optimistically
    /// updates `bookmarkedPostIDs` so the UI flips instantly.
    @discardableResult
    func toggle(postID: String) async -> Bool {
        guard isRemote else { return false }
        guard !mutatingPostIDs.contains(postID) else { return isBookmarked(postID) }
        mutatingPostIDs.insert(postID)
        let owner = currentUID, generation = AccountStorage.generation
        bookmarkRevision = UUID(); bookmarkRead?.cancel()
        defer {
            if generation == AccountStorage.generation, owner == currentUID {
                mutatingPostIDs.remove(postID); bookmarkRevision = UUID()
            }
        }
        let bookmarked = bookmarkedPostIDs.contains(postID)
        if bookmarked {
            bookmarkedPostIDs.remove(postID)
            do {
                try await client.from("whisper_bookmarks")
                    .delete()
                    .eq("user_id", value: owner)
                    .eq("post_id", value: postID)
                    .execute()
                return false
            } catch {
                guard generation == AccountStorage.generation, owner == currentUID else { return false }
                lastError = error.localizedDescription
                bookmarkedPostIDs.insert(postID)
                return true
            }
        } else {
            bookmarkedPostIDs.insert(postID)
            do {
                let row = WhisperBookmarkInsert(user_id: owner, post_id: postID)
                try await client.from("whisper_bookmarks")
                    .upsert(row, onConflict: "user_id,post_id")
                    .execute()
                return true
            } catch {
                guard generation == AccountStorage.generation, owner == currentUID else { return false }
                lastError = error.localizedDescription
                bookmarkedPostIDs.remove(postID)
                return false
            }
        }
    }

    /// Fetches the full rows for the bookmarks tab (joined to the original
    /// posts so we can render the same grid UI used elsewhere).
    func fetchBookmarkedPosts(limit: Int = 200) async -> [WhisperPostRow] {
        (try? await loadBookmarkedPosts(limit: limit)) ?? []
    }

    func loadBookmarkedPosts(limit: Int = 200) async throws -> [WhisperPostRow] {
        guard isRemote else { return [] }
        let owner = currentUID
        let generation = AccountStorage.generation, revision = bookmarkRevision
            loadLocalCategories()
            let rows = try await readBookmarks(owner: owner, generation: generation)
            guard !Task.isCancelled, generation == AccountStorage.generation, owner == currentUID,
                  revision == bookmarkRevision, mutatingPostIDs.isEmpty else { throw CancellationError() }
            bookmarkedPostIDs = Set(rows.map { $0.post_id })
            let ids = Array(rows.prefix(max(0, limit))).map { $0.post_id }
            guard !ids.isEmpty else { return [] }
            let posts: [WhisperPostRow] = try await client
                .from("whisper_posts")
                .select()
                .in("id", values: ids)
                .execute()
                .value
            let visible = try await WhisperPostVisibilityService.visible(posts)
            guard !Task.isCancelled, generation == AccountStorage.generation, owner == currentUID,
                  revision == bookmarkRevision, mutatingPostIDs.isEmpty else { throw CancellationError() }
            WhisperBackendService.shared.schedulePostLikes(postIDs: posts.map(\.id))
            // Preserve bookmark order (rows came back newest-first).
            let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
            return visible.sorted { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
    }
}
