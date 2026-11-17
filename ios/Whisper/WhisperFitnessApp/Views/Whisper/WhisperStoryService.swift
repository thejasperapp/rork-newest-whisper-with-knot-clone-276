import Foundation
import SwiftUI
import Supabase
import UIKit

// MARK: - Supabase schema (run once in SQL editor)
//
// create table if not exists public.whisper_stories (
//   id uuid primary key default gen_random_uuid(),
//   user_id uuid not null references auth.users(id) on delete cascade,
//   username text not null,
//   image_url text not null,
//   caption text,
//   metadata jsonb,
//   music_url text,
//   music_title text,
//   music_artist text,
//   music_artwork text,
//   created_at timestamptz not null default now(),
//   expires_at timestamptz not null default (now() + interval '24 hours')
// );
// alter table public.whisper_stories add column if not exists metadata jsonb;
// alter table public.whisper_stories add column if not exists music_url text;
// alter table public.whisper_stories add column if not exists music_title text;
// alter table public.whisper_stories add column if not exists music_artist text;
// alter table public.whisper_stories add column if not exists music_artwork text;
// create index if not exists whisper_stories_recent_idx
//   on public.whisper_stories (expires_at desc);
// alter table public.whisper_stories enable row level security;
// create policy "ws read fresh" on public.whisper_stories
//   for select using (expires_at > now());
// create policy "ws insert own" on public.whisper_stories
//   for insert with check (auth.uid() = user_id);
// create policy "ws delete own" on public.whisper_stories
//   for delete using (auth.uid() = user_id);

nonisolated struct WhisperStoryRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let user_id: String
    let username: String
    let image_url: String
    let caption: String?
    let metadata: String?
    let music_url: String?
    let music_title: String?
    let music_artist: String?
    let music_artwork: String?
    let created_at: String?
    let expires_at: String?
    /// Round 77 — video stories. The poster frame stays in `image_url` so
    /// strips/highlights/old clients keep working; the clip rides here.
    var video_url: String? = nil

    init(
        id: String, user_id: String, username: String, image_url: String,
        caption: String?, metadata: String?, music_url: String?, music_title: String?,
        music_artist: String?, music_artwork: String?, created_at: String?, expires_at: String?,
        video_url: String? = nil
    ) {
        self.id = id
        self.user_id = user_id
        self.username = username
        self.image_url = image_url
        self.caption = caption
        self.metadata = metadata
        self.music_url = music_url
        self.music_title = music_title
        self.music_artist = music_artist
        self.music_artwork = music_artwork
        self.created_at = created_at
        self.expires_at = expires_at
        self.video_url = video_url
    }

    /// True when this story is a video clip (poster in `image_url`).
    var isVideo: Bool { !(video_url ?? "").isEmpty }
}

nonisolated struct WhisperStoryInsert: Codable, Sendable {
    let id: String
    let user_id: String
    let username: String
    let image_url: String
    let caption: String?
    let metadata: String?
    let music_url: String?
    let music_title: String?
    let music_artist: String?
    let music_artwork: String?
    var video_url: String? = nil
}

/// 24-hour ephemeral stories. Image stored in `whisper-media`, row in
/// `whisper_stories`. Auto-filtered by Postgres `expires_at > now()`.
@MainActor
@Observable
final class WhisperStoryService {
    static let shared = WhisperStoryService()

    private let client = SupabaseService.shared.client
    private static let bucket = "whisper-media"

    /// Mutations must be followed by `syncWidgetAuthors()` — `@Observable`
    /// strips `didSet` observers from tracked properties.
    var stories: [WhisperStoryRow] = []

    /// The story being posted RIGHT NOW — the strips wrap "Your story" in a
    /// brand-gradient progress ring over the new picture while it uploads,
    /// then pop when it lands. Nil when idle.
    struct UploadState: Equatable {
        let preview: UIImage?
        var progress: Double
        var failed: Bool = false
    }
    var uploading: UploadState?
    private var uploadOperation: UUID = UUID()
    @ObservationIgnored private var publicationInFlight: (operation: UUID, generation: UUID)?

    /// Clears the upload state after the landing pop has played.
    private func finishUpload(failed: Bool) {
        uploading?.progress = 1
        uploading?.failed = failed
        let operation = uploadOperation
        let generation = AccountStorage.generation
        Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(failed ? 1400 : 900)) } catch { return }
            guard operation == uploadOperation, generation == AccountStorage.generation else { return }
            uploading = nil
        }
    }
    var lastError: String?
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    private var lastFetch: Date?
    private var contentRevision: UUID = UUID()

    /// Maximum lifetime of a story — matches the Postgres default of
    /// `created_at + 24h`. Client-side filter so in-memory rows age out even
    /// if the app is left open past midnight, and so legacy rows without
    /// `expires_at` still disappear after a day.
    private static let storyTTL: TimeInterval = 60 * 60 * 24

    /// ISO8601 parser shared across freshness checks.
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Returns true if the row's `expires_at` is in the future, OR if
    /// `expires_at` is missing but `created_at` is within the 24-hour TTL.
    /// Falls back to keeping the row if both timestamps are unparseable.
    private static func isFresh(_ row: WhisperStoryRow, now: Date = Date()) -> Bool {
        if let exp = row.expires_at, let d = parseDate(exp) {
            return d > now
        }
        if let created = row.created_at, let d = parseDate(created) {
            return now.timeIntervalSince(d) < storyTTL
        }
        return true
    }

    private static func parseDate(_ s: String) -> Date? {
        if let d = iso.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }

    /// Story IDs the current user has already opened. Persisted across launches
    /// so the unread ring stays correct after a relaunch (Instagram parity).
    var seenStoryIDs: Set<String> = []

    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    private static let seenKey = "whisperStoryService_seenIDs"

    private init() {
        if let data = AccountStorage.data(forKey: Self.seenKey),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            seenStoryIDs = Set(ids)
        }
    }

    /// Mark every story for a single user as seen — called when the viewer
    /// opens that user's segment. Persists immediately so the ring stays
    /// neutral after relaunch.
    func markSeen(storyIDs: [String]) {
        var changed = false
        for id in storyIDs where !seenStoryIDs.contains(id) {
            seenStoryIDs.insert(id)
            changed = true
        }
        guard changed else { return }
        if let data = try? JSONEncoder().encode(Array(seenStoryIDs)) {
            AccountStorage.set(data, forKey: Self.seenKey)
        }
    }

    /// Index of the first unseen story in `list` (chronological order).
    /// Returns 0 when every story has already been seen — that way the
    /// viewer still opens at the beginning instead of refusing to play.
    /// Instagram parity: tapping a ring with one unseen segment jumps
    /// straight to that segment rather than replaying earlier ones.
    func firstUnseenIndex(in list: [WhisperStoryRow]) -> Int {
        if let i = list.firstIndex(where: { !seenStoryIDs.contains($0.id) }) {
            return i
        }
        return 0
    }

    /// Whether the given user has any unseen, non-expired stories — used
    /// to decide the blue (unseen) vs neutral (seen) ring colour in the
    /// strip.
    func hasUnseenStories(userID: String) -> Bool {
        let uid = userID.lowercased()
        let now = Date()
        for s in stories where s.user_id.lowercased() == uid && Self.isFresh(s, now: now) {
            if !seenStoryIDs.contains(s.id) { return true }
        }
        return false
    }

    /// Push the current set of active story authors into the App Group so
    /// the Whisper widgets + watch app can show the live story ring count.
    private func syncWidgetAuthors() {
        let me = (LeaderboardService.shared.savedUsername ?? "").lowercased()
        let backend = WhisperBackendService.shared
        let infos: [WhisperWidgetSync.StoryAuthorInfo] = storiesByUser()
            .filter { !$0.username.isEmpty && $0.username.lowercased() != me }
            .map { group in
                let url = backend.avatarURLString(forUsername: group.username)
                    ?? backend.threadProfiles[group.userID]?.profile_image_url
                return WhisperWidgetSync.StoryAuthorInfo(
                    name: group.username,
                    userID: group.userID,
                    avatarURL: url
                )
            }
        WhisperWidgetSync.writeStoryAuthors(infos)
    }

    /// Stories grouped by user (newest first per user). Expired rows are
    /// dropped client-side as a defence-in-depth against rows the server
    /// hasn't pruned yet.
    func storiesByUser() -> [(username: String, userID: String, latest: WhisperStoryRow, all: [WhisperStoryRow])] {
        let now = Date()
        let blocks = WhisperBlockService.shared
        var groups: [String: [WhisperStoryRow]] = [:]
        for s in stories where Self.isFresh(s, now: now) {
            if blocks.shouldHide(userID: s.user_id, username: s.username) { continue }
            groups[s.user_id, default: []].append(s)
        }
        return groups
            .map { (uid, list) -> (String, String, WhisperStoryRow, [WhisperStoryRow]) in
                let sorted = list.sorted { ($0.created_at ?? "") > ($1.created_at ?? "") }
                let latest = sorted.first!
                return (latest.username, uid, latest, sorted)
            }
            .sorted { ($0.2.created_at ?? "") > ($1.2.created_at ?? "") }
            .map { (username: $0.0, userID: $0.1, latest: $0.2, all: $0.3) }
    }

    /// Whether the current user has at least one fresh story.
    var meHasActiveStory: Bool {
        let uid = currentUID.lowercased()
        let now = Date()
        return stories.contains { $0.user_id.lowercased() == uid && Self.isFresh($0, now: now) }
    }

    /// All of my active stories, oldest-first (the order the viewer plays).
    func myStories() -> [WhisperStoryRow] {
        let uid = currentUID.lowercased()
        let now = Date()
        return stories
            .filter { $0.user_id.lowercased() == uid && Self.isFresh($0, now: now) }
            .sorted { ($0.created_at ?? "") < ($1.created_at ?? "") }
    }

    func resetForCurrentAccount() {
        fetchTask?.cancel(); fetchTask = nil; lastFetch = nil
        contentRevision = UUID()
        stories = []; lastError = nil
        uploadOperation = UUID(); uploading = nil
        seenStoryIDs = AccountStorage.data(forKey: Self.seenKey)
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) }
            .map(Set.init) ?? []
    }

    /// Passive tab activation keeps already loaded stories visible while refreshing.
    func fetchIfStale(maxAge: TimeInterval = 30) async {
        if let lastFetch, Date().timeIntervalSince(lastFetch) < maxAge { return }
        await fetch()
    }

    func fetch() async {
        guard isRemote, !Task.isCancelled else { return }
        if let fetchTask { await fetchTask.value; return }
        let generation = AccountStorage.generation
        let revision = contentRevision
        let task = Task { await self.loadStories(generation: generation, revision: revision) }
        fetchTask = task
        await task.value
        if fetchTask == task { fetchTask = nil }
    }

    private func loadStories(generation: UUID, revision: UUID) async {
        guard !Task.isCancelled, generation == AccountStorage.generation else { return }
        do {
            let rows: [WhisperStoryRow] = try await client
                .from("whisper_stories")
                .select()
                .gt("expires_at", value: ISO8601DateFormatter().string(from: Date()))
                .order("created_at", ascending: false)
                .limit(200)
                .execute()
                .value
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            guard revision == contentRevision else { return }
            stories = rows.filter { Self.isFresh($0) }
            lastFetch = Date(); lastError = nil
            syncWidgetAuthors()
        } catch {
            guard !Task.isCancelled, generation == AccountStorage.generation, revision == contentRevision else { return }
            lastError = "Stories couldn't refresh. Please try again."
        }
    }

    @discardableResult
    func postStory(
        image: UIImage,
        caption: String? = nil,
        metadata: String? = nil,
        music: WhisperStoryMusic? = nil,
        videoURL: URL? = nil,
        publicationID: String? = nil,
        uploader: WhisperWaveUploadService = WhisperWaveUploadService()
    ) async -> WhisperStoryRow? {
        guard isRemote else { return nil }
        let generation = AccountStorage.generation
        let owner = currentUID
        let username = LeaderboardService.shared.savedUsername ?? AuthenticationService.shared.currentUser.username ?? "you"
        let id = publicationID ?? UUID().uuidString.lowercased()
        let path = "\(owner)/stories/\(id).jpg"
        guard let data = image.jpegData(compressionQuality: 0.82) else { return nil }
        guard publicationInFlight?.generation != generation else {
            lastError = "Another Story is still uploading. Please wait, then retry."
            return nil
        }
        let operation = UUID()
        publicationInFlight = (operation, generation)
        uploadOperation = operation
        defer {
            if publicationInFlight?.operation == operation { publicationInFlight = nil }
            if Task.isCancelled, operation == uploadOperation, generation == AccountStorage.generation { uploading = nil }
        }
        uploading = UploadState(preview: image, progress: 0.08)
        do {
            if publicationID != nil {
                let existing: [WhisperStoryRow] = try await client.from("whisper_stories").select()
                    .eq("id", value: id).eq("user_id", value: owner).limit(1).execute().value
                guard !Task.isCancelled, generation == AccountStorage.generation, owner == currentUID else { return nil }
                if let row = existing.first {
                    contentRevision = UUID(); lastFetch = nil
                    fetchTask?.cancel(); fetchTask = nil
                    if !stories.contains(where: { $0.id.lowercased() == row.id.lowercased() }) { stories.insert(row, at: 0) }
                    lastError = nil; syncWidgetAuthors(); finishUpload(failed: false)
                    return row
                }
            }
            if let videoURL {
                let size = try videoURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0, size < WhisperWaveUploadPolicy.maximumBytes,
                      ["mp4", "mov", "m4v"].contains(videoURL.pathExtension.lowercased()) else {
                    throw URLError(.dataLengthExceedsMaximum)
                }
            }
            _ = try await client.storage
                .from(Self.bucket)
                .upload(
                    path,
                    data: data,
                    options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: true)
                )
            guard !Task.isCancelled, generation == AccountStorage.generation, owner == currentUID else { return nil }
            let url = try client.storage.from(Self.bucket).getPublicURL(path: path)
            uploading?.progress = videoURL == nil ? 0.72 : 0.45

            // Video stories: the clip uploads beside the poster. Capped so a
            // 60-second hold-to-record never becomes a 200 MB upload.
            var clipURL: String? = nil
            if let videoURL {
                let ext = videoURL.pathExtension.lowercased()
                let type = ext == "mov" ? "video/quicktime" : (ext == "m4v" ? "video/x-m4v" : "video/mp4")
                let clipPath = "\(owner.lowercased())/stories/\(id).\(ext)"
                clipURL = try await WhisperBackendService.shared.uploadReel(
                    file: videoURL, path: clipPath, uploader: uploader, contentType: type, bucket: Self.bucket
                ) { [weak self] progress in
                    guard generation == AccountStorage.generation, owner == self?.currentUID, operation == self?.uploadOperation else { return }
                    self?.uploading?.progress = 0.45 + progress * 0.37
                }
                guard !Task.isCancelled, generation == AccountStorage.generation, owner == currentUID else { return nil }
            }

            guard !Task.isCancelled, generation == AccountStorage.generation, owner == currentUID else { return nil }
            let payload = WhisperStoryInsert(
                id: id,
                user_id: owner,
                username: username,
                image_url: url.absoluteString,
                caption: caption?.isEmpty == false ? caption : nil,
                metadata: metadata,
                music_url: music?.previewURL,
                music_title: music?.title,
                music_artist: music?.artist,
                music_artwork: music?.artworkURL,
                video_url: clipURL
            )
            let inserted: [WhisperStoryRow] = try await client
                .from("whisper_stories")
                .insert(payload)
                .select()
                .execute()
                .value
            guard !Task.isCancelled, generation == AccountStorage.generation, owner == currentUID else { return nil }
            if let row = inserted.first {
                contentRevision = UUID(); lastFetch = nil
                fetchTask?.cancel(); fetchTask = nil
                stories.insert(row, at: 0)
                syncWidgetAuthors()
                Analytics.record("story_created", [
                    "has_music": music == nil ? "0" : "1",
                    "has_metadata": metadata == nil ? "0" : "1",
                    "is_video": clipURL == nil ? "0" : "1"
                ])
                finishUpload(failed: false)
                return row
            }
            finishUpload(failed: true)
        } catch {
            guard !Task.isCancelled, generation == AccountStorage.generation, owner == currentUID else { return nil }
            lastError = (error as? URLError)?.code == .dataLengthExceedsMaximum
                ? "Choose a playable MP4 or MOV video under 50 MiB, then try again."
                : "Story upload failed. Your story hasn’t been replaced with a photo. Please try again."
            WhisperErrorService.shared.report(lastError ?? "Couldn't post story. Please try again.")
            Analytics.record("story_failed", ["reason": String(error.localizedDescription.prefix(80))])
            finishUpload(failed: true)
        }
        return nil
    }

    func deleteStory(id: String) async {
        guard isRemote else { return }
        let owner = currentUID
        let generation = AccountStorage.generation
        do {
            try await client.from("whisper_stories")
                .delete()
                .eq("id", value: id)
                .eq("user_id", value: owner)
                .execute()
            guard !Task.isCancelled, generation == AccountStorage.generation, owner == currentUID else { return }
            contentRevision = UUID(); lastFetch = nil
            fetchTask?.cancel(); fetchTask = nil
            stories.removeAll { $0.id == id }
            syncWidgetAuthors()
            // Story replies (poll votes, slider ratings, question answers)
            // are FK-cascaded server-side via `on delete cascade`, but on
            // older DBs the cascade may not have been migrated yet. Belt-
            // and-suspenders: fire an explicit delete and prune the local
            // inbox so the Activity tab updates immediately.
            try? await client.from("whisper_story_responses")
                .delete()
                .eq("story_id", value: id)
                .execute()
            guard !Task.isCancelled, generation == AccountStorage.generation, owner == currentUID else { return }
            WhisperStoryResponseService.shared.removeResponses(forStoryID: id)
        } catch {
            guard !Task.isCancelled, generation == AccountStorage.generation, owner == currentUID else { return }
            lastError = "Couldn't delete this story. Please try again."
        }
    }
}
