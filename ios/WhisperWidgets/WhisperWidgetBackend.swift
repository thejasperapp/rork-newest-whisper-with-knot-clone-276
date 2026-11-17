import Foundation
import WidgetKit
import UIKit

/// Direct Supabase REST client used inside the widget extension so DMs and
/// Stories widgets can pull fresh data without depending on the app having
/// been opened recently. Reads a mirrored Supabase session (access +
/// refresh tokens) from the App Group, refreshes the access token on 401
/// or expiry, and writes the resulting snapshot into the same App Group
/// `UserDefaults` keys the rest of the widget code already reads.
nonisolated enum WhisperWidgetBackend {
    private static let supabaseURL = "https://uryyyegnbtlmyhqlgndy.supabase.co"
    private static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVyeXl5ZWduYnRsbXlocWxnbmR5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUyMzM3MDcsImV4cCI6MjA5MDgwOTcwN30.fBo6K9yNHmk1nTArspc5ByMsWEiI2SahCFk6Mdp7qUQ"
    private static let suite = "group.com.mydailywhisper.whisper"

    private static var defaults: WhisperWidgetSnapshotDefaults? { WhisperWidgetSnapshotDefaults(suiteName: suite) }

    // MARK: - Public entry point

    /// Fetches the latest DMs + stories and persists a fresh snapshot. Safe
    /// to call from a widget `getTimeline` block. Silently no-ops when no
    /// mirrored session is available.
    static func refreshSnapshot() async {
        guard let token = await validAccessToken(), !token.isEmpty,
              let uid = defaults?.string(forKey: "whisper_session_user_id"), !uid.isEmpty else {
            return
        }

        // Fetch DMs and stories in parallel.
        async let messages = fetchMessages(userID: uid, token: token)
        async let storyRows = fetchStories(token: token)
        let (msgs, stories) = await (messages, storyRows)

        // Keep the last good snapshot on authorization/network failure.
        guard msgs != nil, stories != nil else { return }

        await writeMessagesSnapshot(msgs ?? [], currentUID: uid, token: token)
        await writeStoriesSnapshot(stories ?? [], currentUID: uid, token: token)
    }

    // MARK: - Token management

    private static func validAccessToken() async -> String? {
        guard let d = defaults else { return nil }
        let token = d.string(forKey: "whisper_session_access_token") ?? ""
        let exp = d.double(forKey: "whisper_session_expires_at")
        if token.isEmpty { return nil }
        // Refresh 60s before expiry to be safe.
        if exp > 0 && Date().timeIntervalSince1970 + 60 < exp {
            return token
        }
        // The app owns refresh-token rotation. Expired widget sessions wait for its next sync.
        return nil
    }

    // MARK: - REST calls

    private struct MessageRow: Decodable {
        let id: String
        let from_user_id: String
        let from_username: String?
        let to_user_id: String
        let to_username: String?
        let body: String?
        let created_at: String?
        let read_at: String?
        let thread_id: String?
    }

    private struct StoryRow: Decodable {
        let id: String
        let user_id: String
        let username: String
        let created_at: String?
        let expires_at: String?
    }

    private struct ProfileRow: Decodable {
        let id: String
        let username: String?
        let profile_image_url: String?
    }

    private static func fetchMessages(userID: String, token: String) async -> [MessageRow]? {
        // PostgREST: rows where to_user_id == me OR from_user_id == me.
        let filter = "or=(to_user_id.eq.\(userID),from_user_id.eq.\(userID))"
        let path = "/rest/v1/whisper_messages?\(filter)&order=created_at.desc&limit=200"
        return await get(path: path, token: token)
    }

    private static func fetchStories(token: String) async -> [StoryRow]? {
        let nowIso = ISO8601DateFormatter().string(from: Date())
        // PostgREST filter syntax for "expires_at > now".
        let path = "/rest/v1/whisper_stories?expires_at=gt.\(nowIso)&order=created_at.desc&limit=200"
        return await get(path: path, token: token)
    }

    private static func fetchProfiles(userIDs: [String], token: String) async -> [String: ProfileRow] {
        let ids = Array(Set(userIDs)).filter { !$0.isEmpty }
        guard !ids.isEmpty else { return [:] }
        let inList = ids.joined(separator: ",")
        let path = "/rest/v1/profiles?select=id,username,profile_image_url&id=in.(\(inList))"
        let rows: [ProfileRow] = (await get(path: path, token: token)) ?? []
        var map: [String: ProfileRow] = [:]
        for r in rows { map[r.id] = r }
        return map
    }

    private static func get<T: Decodable>(path: String, token: String) async -> T? {
        guard let url = URL(string: supabaseURL + path) else { return nil }
        var req = URLRequest(url: url)
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Wire-token translation

    /// Shared-card wire tokens → friendly preview lines so the widget NEVER
    /// shows raw JSON/payload text. Kept in sync with the app-side
    /// `WhisperWidgetSync.friendlyPreview` (this file compiles in the widget
    /// target, so the helper is duplicated by design).
    static func friendlyPreview(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Sent a photo" }

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

        if let tokenRange = trimmed.range(of: "::whisper-") {
            let label: String
            if trimmed.contains("::whisper-film-v1::") { label = "Shared a film" }
            else if trimmed.contains("::whisper-article-v1::") { label = "Shared an article" }
            else if trimmed.contains("::whisper-plan-quiz-answers-v1::") { label = "Sent quiz answers" }
            else if trimmed.contains("::whisper-plan-quiz-v1::") { label = "Sent a check-in quiz" }
            else if trimmed.contains("::whisper-story-v1::") || trimmed.contains("::whisper-storytag-v1::") { label = "Shared a story" }
            else if trimmed.contains("::whisper-sharedpost") { label = "Shared a post" }
            else { label = "Shared a card" }
            let caption = String(trimmed[..<tokenRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return caption.isEmpty ? label : "\(caption) · \(label)"
        }

        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if trimmed.contains("profile") { return "Shared a profile" }
            if trimmed.contains("post") { return "Shared a post" }
            return "Shared a card"
        }

        if (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"))
            && !trimmed.contains(" ") && !trimmed.contains("\n") {
            return trimmed.contains("giphy") ? "Sent a GIF" : "Sent an attachment"
        }

        return trimmed.components(separatedBy: "\n").first ?? trimmed
    }

    // MARK: - Snapshot writers

    private static func writeMessagesSnapshot(_ rows: [MessageRow], currentUID: String, token: String) async {
        guard let d = defaults, d.string(forKey: "whisper_session_user_id")?.lowercased() == currentUID.lowercased(), d.string(forKey: "whisper_session_access_token") == token else { return }
        let me = currentUID.lowercased()

        // Group by the "other" participant.
        struct Latest {
            var row: MessageRow
            var unread: Bool
            var fromMe: Bool
        }
        var byOther: [String: Latest] = [:]
        let iso = ISO8601DateFormatter()
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func parse(_ s: String?) -> Date? {
            guard let s else { return nil }
            return isoFrac.date(from: s) ?? iso.date(from: s)
        }

        for row in rows {
            guard !(row.body ?? "").hasPrefix("::wg-"), !(row.body ?? "").hasPrefix("::whisper-call-") else { continue }
            let fromLower = row.from_user_id.lowercased()
            let toLower = row.to_user_id.lowercased()
            let other = fromLower == me ? toLower : fromLower
            if other == me || other.isEmpty { continue }
            let fromMe = fromLower == me
            let unread = !fromMe && (row.read_at == nil)
            let key = other + ":" + (row.thread_id?.lowercased() ?? "legacy")
            if let existing = byOther[key] {
                let existingDate = parse(existing.row.created_at) ?? .distantPast
                let newDate = parse(row.created_at) ?? .distantPast
                if newDate > existingDate {
                    byOther[key] = Latest(row: row, unread: unread || existing.unread, fromMe: fromMe)
                } else { byOther[key]?.unread = existing.unread || unread }
            } else {
                byOther[key] = Latest(row: row, unread: unread, fromMe: fromMe)
            }
        }

        // Match the app's conversation count; group/control rows aren't personal threads.
        let unreadTotal = byOther.values.filter { $0.unread }.count

        // Sort threads newest first.
        let sorted = byOther.values.sorted {
            let a = parse($0.row.created_at) ?? .distantPast
            let b = parse($1.row.created_at) ?? .distantPast
            return a > b
        }

        // Hydrate avatars: fetch profiles for the top other_ids we don't yet
        // have an avatar for.
        let otherIDs = Array(sorted.prefix(5)).map { $0.row.from_user_id.lowercased() == me ? $0.row.to_user_id : $0.row.from_user_id }
        let profiles = await fetchProfiles(userIDs: otherIDs, token: token)

        var compact: [CompactThread] = []
        var avatarTargets: [(String, String)] = []
        for latest in sorted.prefix(5) {
            let row = latest.row
            let other = row.from_user_id.lowercased() == me ? row.to_user_id : row.from_user_id
            let otherName: String = {
                if latest.fromMe { return row.to_username ?? "" }
                return row.from_username ?? ""
            }()
            let when = (parse(row.created_at) ?? Date()).timeIntervalSince1970
            let profile = profiles[other]
            let displayName = (otherName.isEmpty ? profile?.username : otherName) ?? ""
            if let avatarURL = profile?.profile_image_url, !avatarURL.isEmpty {
                avatarTargets.append((other, avatarURL))
            }
            compact.append(CompactThread(
                user: displayName,
                preview: friendlyPreview(row.body),
                when: when,
                fromMe: latest.fromMe,
                unread: latest.unread,
                userID: other,
                avatar: profiles[other]?.profile_image_url.map { _ in avatarFilename(for: other) },
                owner: currentUID.lowercased(),
                threadID: row.thread_id
            ))
        }

        d.set(unreadTotal, forKey: "whisper_unread_dm_count")
        if let first = compact.first {
            d.set(first.user, forKey: "whisper_last_sender")
            d.set(first.preview, forKey: "whisper_last_preview")
            d.set(first.when, forKey: "whisper_last_date")
        } else {
            for key in ["whisper_last_sender", "whisper_last_preview", "whisper_last_date"] { d.removeObject(forKey: key) }
        }
        if let data = try? JSONEncoder().encode(compact) {
            d.set(data, forKey: "whisper_top_threads")
        }
        d.set(Date().timeIntervalSince1970, forKey: "whisper_last_synced")

        // Fire-and-forget avatar downloads.
        await downloadAvatars(avatarTargets)

        print("[WhisperWidget] direct fetch — threads=\(compact.count) unread=\(unreadTotal)")
    }

    private static func writeStoriesSnapshot(_ rows: [StoryRow], currentUID: String, token: String) async {
        guard let d = defaults, d.string(forKey: "whisper_session_user_id")?.lowercased() == currentUID.lowercased(), d.string(forKey: "whisper_session_access_token") == token else { return }
        let me = currentUID.lowercased()
        // Group by user_id, keep one entry per author.
        var byUser: [String: StoryRow] = [:]
        for row in rows {
            let key = row.user_id.lowercased()
            if key == me { continue }
            if byUser[key] == nil { byUser[key] = row }
        }
        let authorRows = Array(byUser.values)
        let profiles = await fetchProfiles(userIDs: authorRows.map { $0.user_id }, token: token)

        var seen = Set<String>()
        var payload: [StoryAuthor] = []
        var avatarTargets: [(String, String)] = []
        for row in authorRows {
            let nameKey = row.username.lowercased()
            if nameKey.isEmpty || seen.contains(nameKey) { continue }
            seen.insert(nameKey)
            let avatarURL = profiles[row.user_id]?.profile_image_url
            if let url = avatarURL, !url.isEmpty {
                avatarTargets.append((row.user_id, url))
            }
            payload.append(StoryAuthor(
                name: row.username,
                userID: row.user_id,
                avatar: avatarURL.map { _ in avatarFilename(for: row.user_id) }
            ))
            if payload.count >= 8 { break }
        }
        d.set(payload.count, forKey: "whisper_active_story_count")
        if let data = try? JSONEncoder().encode(payload) {
            d.set(data, forKey: "whisper_story_authors")
        }
        await downloadAvatars(avatarTargets)
        print("[WhisperWidget] direct fetch — stories authors=\(payload.count)")
    }

    // MARK: - Extras: shared calendar + coach clients

    private struct CalendarEventREST: Decodable {
        let title: String
        let event_type: String?
        let start_time: String
        let meeting_link: String?
        let created_by_username: String?
    }

    private struct CoachRequestREST: Decodable {
        let client_user_id: String
        let client_username: String
        let status: String?
        let updated_at: String?
    }

    /// Fetches the next upcoming shared-calendar events + the coach's active
    /// client roster and persists them into the snapshot keys the Shared
    /// Calendar and Coach Clients widgets read. Safe inside `getTimeline`;
    /// silently no-ops when no mirrored session is available.
    static func refreshExtras() async {
        guard let token = await validAccessToken(), !token.isEmpty,
              let uid = defaults?.string(forKey: "whisper_session_user_id"), !uid.isEmpty else {
            return
        }
        async let eventRows = fetchCalendarEvents(token: token)
        async let clientRows = fetchCoachClients(userID: uid, token: token)
        let (events, clients) = await (eventRows, clientRows)
        guard defaults?.string(forKey: "whisper_session_user_id") == uid, defaults?.string(forKey: "whisper_session_access_token") == token else { return }
        if let events { writeCalendarSnapshot(events, token: token) }
        if let clients { await writeClientsSnapshot(clients, token: token) }
    }

    private static func fetchCalendarEvents(token: String) async -> [CalendarEventREST]? {
        let nowIso = ISO8601DateFormatter().string(from: Date())
        let path = "/rest/v1/whisper_calendar_events?start_time=gte.\(nowIso)&order=start_time.asc&limit=8"
        return await get(path: path, token: token)
    }

    private static func fetchCoachClients(userID: String, token: String) async -> [CoachRequestREST]? {
        let path = "/rest/v1/whisper_coach_requests?coach_user_id=eq.\(userID)&status=eq.accepted&order=updated_at.desc&limit=6"
        return await get(path: path, token: token)
    }

    private static func parseISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return isoFrac.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    private static func writeCalendarSnapshot(_ rows: [CalendarEventREST], token: String) {
        guard let d = defaults, d.string(forKey: "whisper_session_access_token") == token else { return }
        let compact: [CompactEvent] = rows.compactMap { row in
            guard let start = parseISO(row.start_time) else { return nil }
            return CompactEvent(
                title: row.title,
                when: start.timeIntervalSince1970,
                type: row.event_type ?? "event",
                host: row.created_by_username,
                link: (row.meeting_link?.isEmpty == false)
            )
        }
        if let data = try? JSONEncoder().encode(compact) {
            d.set(data, forKey: "whisper_calendar_events")
        }
        print("[WhisperWidget] direct fetch — calendar events=\(compact.count)")
    }

    private static func writeClientsSnapshot(_ rows: [CoachRequestREST], token: String) async {
        guard let d = defaults, d.string(forKey: "whisper_session_access_token") == token else { return }
        let profiles = await fetchProfiles(userIDs: rows.map { $0.client_user_id }, token: token)
        var avatarTargets: [(String, String)] = []
        let compact: [CompactClient] = rows.map { row in
            if let url = profiles[row.client_user_id]?.profile_image_url, !url.isEmpty {
                avatarTargets.append((row.client_user_id, url))
            }
            return CompactClient(
                name: row.client_username,
                userID: row.client_user_id,
                avatar: profiles[row.client_user_id]?.profile_image_url.map { _ in avatarFilename(for: row.client_user_id) },
                since: parseISO(row.updated_at)?.timeIntervalSince1970
            )
        }
        if let data = try? JSONEncoder().encode(compact) {
            d.set(data, forKey: "whisper_coach_clients")
        }
        // Only assert coach-ness on positive signal — an empty roster must
        // not clear a flag the app wrote from richer data (pending requests).
        if !compact.isEmpty {
            d.set(true, forKey: "whisper_is_coach")
        }
        await downloadAvatars(avatarTargets)
        print("[WhisperWidget] direct fetch — coach clients=\(compact.count)")
    }

    // MARK: - Avatar disk cache

    static func avatarFilename(for userID: String) -> String {
        let safe = userID
            .lowercased()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        let epoch = defaults?.string(forKey: "whisper_snapshot_epoch") ?? "initial"
        return "\(epoch)-\(safe).jpg"
    }

    static func avatarsDirectory() -> URL? {
        guard let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: suite) else { return nil }
        let dir = base.appendingPathComponent("widget-avatars", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func cachedAvatar(userID: String?) -> UIImage? {
        guard let uid = userID, !uid.isEmpty, let dir = avatarsDirectory() else { return nil }
        let url = dir.appendingPathComponent(avatarFilename(for: uid))
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private static func downloadAvatars(_ targets: [(String, String)]) async {
        guard let dir = avatarsDirectory() else { return }
        await withTaskGroup(of: Void.self) { group in
            for (userID, urlString) in targets {
                let file = dir.appendingPathComponent(avatarFilename(for: userID))
                if FileManager.default.fileExists(atPath: file.path) { continue }
                guard let remote = URL(string: urlString) else { continue }
                group.addTask {
                    guard let (data, _) = try? await URLSession.shared.data(from: remote) else { return }
                    try? data.write(to: file, options: .atomic)
                }
            }
        }
    }
}
