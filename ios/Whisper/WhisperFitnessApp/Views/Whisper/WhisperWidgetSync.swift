import Foundation
import UIKit
import WidgetKit

/// Centralized sync layer that mirrors a compact snapshot of Whisper state
/// into the App Group `UserDefaults` so the Whisper widgets, Lock-Screen
/// complications, and the Apple Watch app can render without hitting the
/// network. Also persists a copy of the user's Supabase session (access +
/// refresh tokens) so widgets can pull fresh data directly from Supabase
/// even when the app hasn't been opened recently.
///
/// Keys live under the suite `group.com.mydailywhisper.whisper`:
///   - whisper_unread_dm_count   (Int)
///   - whisper_last_sender       (String)
///   - whisper_last_preview      (String)
///   - whisper_last_date         (Double, unix timestamp)
///   - whisper_my_thought        (String?)
///   - whisper_followers         (Int)
///   - whisper_following         (Int)
///   - whisper_active_story_count (Int)
///   - whisper_story_authors     (Data — JSON array of {name, userID, avatar})
///   - whisper_top_threads       (Data — JSON array of CompactThread)
///   - whisper_activity_count    (Int — unread notifications in last 24h)
///   - whisper_activity_preview  (String — short text of newest activity)
///   - whisper_last_synced       (Double, unix timestamp)
///   - whisper_session_access_token   (String)
///   - whisper_session_refresh_token  (String)
///   - whisper_session_expires_at     (Double, unix timestamp)
///   - whisper_session_user_id        (String)
@MainActor
enum WhisperWidgetSync {
    static let suite = "group.com.mydailywhisper.whisper"

    static func clearAccountState() {
        guard let d = UserDefaults(suiteName: suite) else { return }
        for key in d.dictionaryRepresentation().keys where key.hasPrefix("whisper_") { d.removeObject(forKey: key) }
        d.set(UUID().uuidString, forKey: "whisper_snapshot_epoch")
        WhisperWidgetAvatarCache.shared.invalidate()
        WidgetCenter.shared.reloadAllTimelines()
        WhisperWatchSync.shared.pushSoon()
    }

    struct CompactThread: Codable {
        let user: String
        let preview: String
        let when: Double
        let fromMe: Bool
        let unread: Bool
        /// Other participant's Supabase user_id. Used as the avatar cache key
        /// and to deep-link the widget tap into the specific thread.
        var userID: String? = nil
        /// Filename (just the leaf, e.g. `<uid>.jpg`) of the cached avatar
        /// inside the App Group container's `widget-avatars/` directory.
        var avatar: String? = nil
        var owner: String? = nil
        var threadID: String? = nil
    }

    struct StoryAuthor: Codable {
        let name: String
        var userID: String? = nil
        var avatar: String? = nil
    }

    /// One upcoming shared-calendar event for the Calendar widget + watch.
    struct CompactEvent: Codable {
        let title: String
        let when: Double
        let type: String
        var host: String? = nil
        var link: Bool = false
    }

    /// One active coaching client for the Coach Clients widget + watch.
    struct CompactClient: Codable {
        let name: String
        var userID: String? = nil
        var avatar: String? = nil
        var since: Double? = nil
    }

    /// Lightweight (name, userID, avatarURLString) tuple used by the story
    /// service when mirroring active story authors.
    struct StoryAuthorInfo {
        let name: String
        let userID: String?
        let avatarURL: String?
    }

    /// Writes the snapshot derived from the current state of the in-memory
    /// Whisper services. Safe to call repeatedly — it cheaply diffs into
    /// UserDefaults.
    static func write(
        threads: [WhisperConversationSummary],
        threadAvatarURLs: [String: String] = [:],
        activeStoryAuthors: [StoryAuthorInfo],
        followerCount: Int,
        followingCount: Int,
        activityCount: Int = 0,
        activityPreview: String? = nil
    ) {
        guard let d = WhisperWidgetSnapshotDefaults(suiteName: suite) else {
            print("[WhisperWidget] write FAILED — App Group suite \(suite) returned nil. Check entitlements.")
            return
        }

        // Unread = threads with an inbound latest message I haven't read.
        guard UUID(uuidString: AccountStorage.currentUserID) != nil else { return }
        let unread = threads.reduce(0) { $0 + ((!$1.lastFromMe && !$1.lastReadByMe) ? 1 : 0) }
        d.set(unread, forKey: "whisper_unread_dm_count")
        WhisperNotificationService.shared.refreshAppIconBadge()

        if let latest = threads.first {
            d.set(latest.otherUsername, forKey: "whisper_last_sender")
            d.set(friendlyPreview(latest.lastMessage), forKey: "whisper_last_preview")
            d.set(latest.lastDate.timeIntervalSince1970, forKey: "whisper_last_date")
        } else {
            for key in ["whisper_last_sender", "whisper_last_preview", "whisper_last_date"] { d.removeObject(forKey: key) }
        }

        // Top 5 threads as JSON so the widget/watch can show a real list.
        let compact: [CompactThread] = threads.prefix(5).map { t in
            let url = threadAvatarURLs[t.otherUserID]
            return CompactThread(
                user: t.otherUsername,
                preview: friendlyPreview(t.lastMessage),
                when: t.lastDate.timeIntervalSince1970,
                fromMe: t.lastFromMe,
                unread: !t.lastReadByMe,
                userID: t.otherUserID,
                avatar: url.flatMap { _ in avatarFilename(for: t.otherUserID) },
                owner: AccountStorage.currentUserID.lowercased(),
                threadID: t.kind.threadID(AccountStorage.currentUserID, t.otherUserID)
            )
        }
        if let data = try? JSONEncoder().encode(compact) {
            d.set(data, forKey: "whisper_top_threads")
        }

        // Active story authors (dedup by username, exclude "me" — caller filters).
        var seen = Set<String>()
        let unique = activeStoryAuthors.filter {
            let k = $0.name.lowercased()
            if k.isEmpty || seen.contains(k) { return false }
            seen.insert(k)
            return true
        }
        d.set(unique.count, forKey: "whisper_active_story_count")
        let authors = unique.prefix(8).map { info -> StoryAuthor in
            StoryAuthor(
                name: info.name,
                userID: info.userID,
                avatar: info.avatarURL.flatMap { _ in info.userID.map { avatarFilename(for: $0) } } ?? nil
            )
        }
        if let data = try? JSONEncoder().encode(authors) {
            d.set(data, forKey: "whisper_story_authors")
        }

        d.set(followerCount, forKey: "whisper_followers")
        d.set(followingCount, forKey: "whisper_following")
        d.set(activityCount, forKey: "whisper_activity_count")
        if let p = activityPreview, !p.isEmpty {
            d.set(p, forKey: "whisper_activity_preview")
        } else { d.removeObject(forKey: "whisper_activity_preview") }
        d.set(Date().timeIntervalSince1970, forKey: "whisper_last_synced")

        print("[WhisperWidget] wrote snapshot — threads=\(threads.count) unread=\(unread) stories=\(unique.count) followers=\(followerCount)")

        // Kick off avatar downloads. Fires WidgetCenter reload after each
        // newly cached image so the widget swaps from monogram to photo.
        var avatarTargets: [(userID: String, url: String)] = []
        for t in threads.prefix(5) {
            if let url = threadAvatarURLs[t.otherUserID], !url.isEmpty {
                avatarTargets.append((t.otherUserID, url))
            }
        }
        for info in unique.prefix(8) {
            if let uid = info.userID, let url = info.avatarURL, !url.isEmpty {
                avatarTargets.append((uid, url))
            }
        }
        WhisperWidgetAvatarCache.shared.refresh(targets: avatarTargets)

        WidgetCenter.shared.reloadAllTimelines()
        WhisperWatchSync.shared.pushSoon()
    }

    /// Mirrors the next upcoming shared-calendar events so the Shared
    /// Calendar widget and the watch can render without the app open.
    static func writeCalendar(_ events: [CompactEvent]) {
        guard let d = WhisperWidgetSnapshotDefaults(suiteName: suite) else { return }
        if let data = try? JSONEncoder().encode(events) {
            d.set(data, forKey: "whisper_calendar_events")
        }
        WidgetCenter.shared.reloadAllTimelines()
        WhisperWatchSync.shared.pushSoon()
    }

    /// Mirrors the coach's active client roster for the Coach Clients
    /// widget and the watch.
    static func writeCoachClients(_ clients: [CompactClient], isCoach: Bool) {
        guard let d = WhisperWidgetSnapshotDefaults(suiteName: suite) else { return }
        if let data = try? JSONEncoder().encode(clients) {
            d.set(data, forKey: "whisper_coach_clients")
        }
        d.set(isCoach, forKey: "whisper_is_coach")
        WidgetCenter.shared.reloadAllTimelines()
        WhisperWatchSync.shared.pushSoon()
    }

    /// Convenience for partial updates (thought, story authors, etc) without
    /// having to pass everything else.
    static func writeThought(_ text: String?) {
        guard let d = WhisperWidgetSnapshotDefaults(suiteName: suite) else { return }
        if let text, !text.trimmingCharacters(in: .whitespaces).isEmpty {
            d.set(text, forKey: "whisper_my_thought")
        } else {
            d.removeObject(forKey: "whisper_my_thought")
        }
        WidgetCenter.shared.reloadAllTimelines()
        WhisperWatchSync.shared.pushSoon()
    }

    static func writeStoryAuthors(_ authors: [StoryAuthorInfo]) {
        guard let d = WhisperWidgetSnapshotDefaults(suiteName: suite) else { return }
        var seen = Set<String>()
        let unique = authors.filter {
            let k = $0.name.lowercased()
            if k.isEmpty || seen.contains(k) { return false }
            seen.insert(k)
            return true
        }
        d.set(unique.count, forKey: "whisper_active_story_count")
        let payload = unique.prefix(8).map { info -> StoryAuthor in
            StoryAuthor(
                name: info.name,
                userID: info.userID,
                avatar: info.avatarURL.flatMap { _ in info.userID.map { avatarFilename(for: $0) } } ?? nil
            )
        }
        if let data = try? JSONEncoder().encode(payload) {
            d.set(data, forKey: "whisper_story_authors")
        }
        var avatarTargets: [(userID: String, url: String)] = []
        for info in unique.prefix(8) {
            if let uid = info.userID, let url = info.avatarURL, !url.isEmpty {
                avatarTargets.append((uid, url))
            }
        }
        WhisperWidgetAvatarCache.shared.refresh(targets: avatarTargets)
        WidgetCenter.shared.reloadAllTimelines()
        WhisperWatchSync.shared.pushSoon()
    }

    static func writeFollowCounts(followers: Int, following: Int) {
        guard let d = WhisperWidgetSnapshotDefaults(suiteName: suite) else { return }
        d.set(followers, forKey: "whisper_followers")
        d.set(following, forKey: "whisper_following")
        WidgetCenter.shared.reloadAllTimelines()
        WhisperWatchSync.shared.pushSoon()
    }

    /// Mirror the live Supabase auth session into the App Group so the
    /// widget extension can hit Supabase directly when the app hasn't been
    /// opened recently. Pass `nil` on sign-out to clear.
    static func writeSession(
        accessToken: String?,
        refreshToken: String?,
        expiresAt: Date?,
        userID: String?
    ) {
        guard let userID, !userID.isEmpty else { clearAccountState(); return }
        guard userID.lowercased() == AccountStorage.currentUserID.lowercased() else { return }
        guard let d = WhisperWidgetSnapshotDefaults(suiteName: suite) else { return }
        if let t = accessToken, !t.isEmpty {
            d.set(t, forKey: "whisper_session_access_token")
        } else {
            d.removeObject(forKey: "whisper_session_access_token")
        }
        // The extension is read-only and must never rotate or retain refresh credentials.
        d.removeObject(forKey: "whisper_session_refresh_token")
        if let exp = expiresAt {
            d.set(exp.timeIntervalSince1970, forKey: "whisper_session_expires_at")
        } else {
            d.removeObject(forKey: "whisper_session_expires_at")
        }
        if !userID.isEmpty {
            d.set(userID.lowercased(), forKey: "whisper_session_user_id")
        } else {
            d.removeObject(forKey: "whisper_session_user_id")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Wire-token translation

    /// Shared-card wire tokens → friendly preview lines, so the widgets and
    /// the watch NEVER show raw JSON/payload text. Mirrors the web inbox
    /// translator (group wire, stickers, shared posts/films/articles,
    /// plan quizzes, meeting notes, generic JSON cards).
    nonisolated static func friendlyPreview(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Sent a photo" }

        // Group wire: ::wg-v1::{id}::{name}::{body} — label with the group name.
        if trimmed.hasPrefix("::wg-v1::") {
            let rest = String(trimmed.dropFirst("::wg-v1::".count))
            let parts = rest.components(separatedBy: "::")
            let name = parts.count > 1 && !parts[1].isEmpty ? parts[1] : "Group"
            let inner = parts.count > 2 ? parts.dropFirst(2).joined(separator: "::") : ""
            return "\(name): \(friendlyPreview(inner))"
        }

        if trimmed.contains("jasper-sticker://") { return "Sent a sticker" }
        if trimmed.hasPrefix("\u{1F4CB} Meeting notes \u{2014} ") {
            return trimmed.components(separatedBy: "\n").first ?? "Meeting notes"
        }

        // Structured share tokens — may ride mid-text after a caption.
        if let tokenRange = trimmed.range(of: "::whisper-") {
            let label: String
            if trimmed.contains("::whisper-film-v1::") { label = "Shared a film" }
            else if trimmed.contains("::whisper-article-v1::") { label = "Shared an article" }
            else if trimmed.contains("::whisper-matchreq-v1::") { label = "Wants to match 💘" }
            else if trimmed.contains("::whisper-matched-v1::") { label = "It's a match! 💘" }
            else if trimmed.contains("::whisper-plan-quiz-answers-v1::") { label = "Sent quiz answers" }
            else if trimmed.contains("::whisper-plan-quiz-v1::") { label = "Sent a check-in quiz" }
            else if trimmed.contains("::whisper-story-v1::") || trimmed.contains("::whisper-storytag-v1::") { label = "Shared a story" }
            else if trimmed.contains("::whisper-sharedpost") { label = "Shared a post" }
            else { label = "Shared a card" }
            let caption = String(trimmed[..<tokenRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return caption.isEmpty ? label : "\(caption) · \(label)"
        }

        // Any JSON-shaped payload (shared profiles/cards) → friendly label.
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if trimmed.contains("profile") { return "Shared a profile" }
            if trimmed.contains("post") { return "Shared a post" }
            return "Shared a card"
        }

        // URL-only bodies are sticker/GIF/media sends.
        if (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"))
            && !trimmed.contains(" ") && !trimmed.contains("\n") {
            return trimmed.contains("giphy") ? "Sent a GIF" : "Sent an attachment"
        }

        return trimmed.components(separatedBy: "\n").first ?? trimmed
    }

    // MARK: - Avatar filenames

    /// Deterministic file name for the cached avatar of a given user_id.
    /// The widget reads it back from the App Group container with the same
    /// helper, see `WhisperWidgetAvatarCache.fileURL(forUserID:)`.
    nonisolated fileprivate static func avatarFilename(for userID: String) -> String {
        let safe = userID
            .lowercased()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        let epoch = UserDefaults(suiteName: "group.com.mydailywhisper.whisper")?.string(forKey: "whisper_snapshot_epoch") ?? "initial"
        return "\(epoch)-\(safe).jpg"
    }
}

// MARK: - Avatar cache

/// Downloads small avatar images and persists them to the App Group
/// container so the widget extension can render them with
/// `UIImage(contentsOfFile:)` (which is synchronous and safe inside the
/// widget process). Coalesces in-flight downloads per user_id.
@MainActor
final class WhisperWidgetAvatarCache {
    static let shared = WhisperWidgetAvatarCache()

    private var inflight: Set<String> = []
    /// Maps user_id -> last URL string we wrote to disk, so we skip
    /// re-downloading when the remote URL is unchanged.
    private var lastURLByUserID: [String: String] = [:]

    private init() {}

    func invalidate() { inflight = []; lastURLByUserID = [:] }

    /// Returns the directory inside the App Group container where avatar
    /// JPEGs live. Creates it lazily.
    static func directoryURL() -> URL? {
        guard let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WhisperWidgetSync.suite) else {
            return nil
        }
        let dir = base.appendingPathComponent("widget-avatars", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    func refresh(targets: [(userID: String, url: String)]) {
        guard let dir = Self.directoryURL() else { return }
        for (userID, url) in targets {
            let key = userID.lowercased()
            if inflight.contains(key) { continue }
            if lastURLByUserID[key] == url,
               FileManager.default.fileExists(atPath: dir.appendingPathComponent(WhisperWidgetSync.avatarFilename(for: userID)).path) {
                continue
            }
            guard let remote = URL(string: url) else { continue }
            inflight.insert(key)
            let generation = AccountStorage.generation
            let filename = WhisperWidgetSync.avatarFilename(for: userID)
            Task.detached(priority: .utility) {
                defer {
                    Task { @MainActor in
                        if generation == AccountStorage.generation { WhisperWidgetAvatarCache.shared.inflight.remove(key) }
                    }
                }
                guard let (data, _) = try? await URLSession.shared.data(from: remote) else { return }
                // Down-sample to ~120pt @ 3x = 360px square for a small file.
                let resized = WhisperWidgetAvatarCache.downsample(data: data, maxPixelSize: 360) ?? data
                let fileURL = dir.appendingPathComponent(filename)
                try? resized.write(to: fileURL, options: .atomic)
                await MainActor.run {
                    guard generation == AccountStorage.generation else { return }
                    WhisperWidgetAvatarCache.shared.lastURLByUserID[key] = url
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }
    }

    nonisolated private static func downsample(data: Data, maxPixelSize: CGFloat) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide = max(image.size.width, image.size.height)
        guard maxSide > 0 else { return nil }
        let scale = min(1, maxPixelSize / maxSide)
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: 0.8)
    }
}
