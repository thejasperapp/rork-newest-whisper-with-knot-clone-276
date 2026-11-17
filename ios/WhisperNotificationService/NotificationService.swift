import UserNotifications
import Intents
import UniformTypeIdentifiers

/// Notification Service Extension that turns Whisper DM pushes into
/// **Communication Notifications**: the sender's avatar replaces the app icon
/// in the banner (large round image), and the Whisper app icon appears as a
/// small badge in the corner — the same look as Messages / WhatsApp.
///
/// The Edge Function (`whisper-push-fanout`) includes the sender's
/// `profile_image_url` and stable `from_user_id` inside `aps.payload` (see
/// `data` block). We download the avatar, build an `INSendMessageIntent` with
/// an `INPerson` whose `image` is that avatar, then return the request
/// `updating(from:)` the donated intent so iOS renders the communication
/// style banner.
final class NotificationService: UNNotificationServiceExtension {

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        guard let mutable = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        self.bestAttemptContent = mutable

        // Defensive rewrite: if any push body still carries a raw Whisper
        // control prefix (`::whisper-call-v1::{...}`, etc.) replace it with
        // a friendly fallback so the user never sees protocol chatter on
        // their lock screen.
        if let range = mutable.body.range(of: "::wg-v1::") {
            let pieces = mutable.body[range.upperBound...].components(separatedBy: "::")
            if pieces.count >= 3, UUID(uuidString: pieces[0]) != nil {
                var info = mutable.userInfo
                var data = (info["data"] as? [String: Any]) ?? [:]
                data["kind"] = "group"; data["group_id"] = pieces[0].lowercased()
                info["kind"] = "group"; info["group_id"] = pieces[0].lowercased(); info["data"] = data
                mutable.userInfo = info
                let sender = mutable.title
                mutable.title = sanitize(pieces[1])
                mutable.body = "\(sender): \(sanitize(pieces.dropFirst(2).joined(separator: "::")))"
                mutable.threadIdentifier = "group-\(pieces[0].lowercased())"
            }
        }
        mutable.body = sanitize(mutable.body)

        let userInfo: [String: Any] = mutable.userInfo.reduce(into: [:]) { acc, pair in
            if let key = pair.key as? String { acc[key] = pair.value }
        }
        // Communication style applies to DMs (message intent) and the two
        // call banners (call intent): the alert-push invite fallback for
        // devices without a VoIP token, and the "Missed call" banner. All
        // three carry `sender_avatar_url` from the fanout.
        let kind = (userInfo["kind"] as? String)
            ?? ((userInfo["data"] as? [String: Any])?["kind"] as? String)

        if userInfo["social_teams"] as? String == "v1"
            || (userInfo["data"] as? [String: Any])?["social_teams"] as? String == "v1" {
            mutable.title = "Whisper"
            mutable.body = "You have a team invitation. Open Whisper to review it."
            contentHandler(mutable)
            return
        }
        let isCall = (kind == "call_invite" || kind == "call_missed")
        let isGroup = kind == "group"
        guard kind == "dm" || isGroup || isCall else {
            contentHandler(mutable)
            return
        }

        // Pull sender identifiers from either the top-level payload (legacy)
        // or the nested `data` dict we send today.
        let data = (userInfo["data"] as? [String: Any]) ?? userInfo
        let senderID = (data["from_user_id"] as? String)
            ?? (userInfo["from_user_id"] as? String)
            ?? ""
        // Call pushes title as "Incoming call" / "Missed call" with the
        // handle in the data payload; DMs title as the sender's handle.
        let senderName: String
        if isCall || isGroup {
            senderName = stripLeadingAt(
                (data["from_username"] as? String) ?? "Someone"
            )
        } else {
            senderName = stripLeadingAt(mutable.title.isEmpty ? "Someone" : mutable.title)
        }
        let avatarURLString = (data["sender_avatar_url"] as? String)
            ?? (data["avatar_url"] as? String)
            ?? (userInfo["sender_avatar_url"] as? String)
        let isVideo = ((data["mode"] as? String) ?? "audio") == "video"
        let senderUsername = (data["from_username"] as? String).map(stripLeadingAt)
            ?? senderName

        Task {
            // The fanout may not include the avatar URL (older deploys) —
            // resolve it directly from Supabase as a fallback so banners
            // always carry the sender's photo.
            var resolvedAvatarURL = avatarURLString
            if resolvedAvatarURL == nil || resolvedAvatarURL?.isEmpty == true {
                resolvedAvatarURL = await fetchAvatarURL(userID: senderID, username: senderUsername)
            }
            let avatarImage: INImage? = await loadAvatar(urlString: resolvedAvatarURL)
            let groupID = isGroup ? (data["group_id"] as? String).flatMap { UUID(uuidString: $0)?.uuidString.lowercased() } : nil
            let groupName = groupID == nil ? nil : (data["group_name"] as? String ?? mutable.title)
            let groupAvatar = groupID == nil ? nil : await loadPrivateGroupAvatar(data["group_avatar_url"] as? String, groupID: groupID ?? "")
            if isCall {
                await self.deliverCallCommunication(
                    content: mutable,
                    senderID: senderID,
                    senderName: senderName,
                    avatar: avatarImage,
                    isVideo: isVideo,
                    contentHandler: contentHandler
                )
            } else {
                await self.deliverCommunication(
                    content: mutable,
                    senderID: senderID,
                    senderName: senderName,
                    avatar: avatarImage,
                    groupID: groupID,
                    groupName: groupName,
                    groupAvatar: groupAvatar,
                    contentHandler: contentHandler
                )
            }
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // Avatar download took too long — fall back to a plain banner.
        if let handler = contentHandler, let content = bestAttemptContent {
            handler(content)
        }
    }

    // MARK: - Helpers

    private func stripLeadingAt(_ s: String) -> String {
        s.hasPrefix("@") ? String(s.dropFirst()) : s
    }

    /// Friendly labels for every Whisper wire token — pushes must NEVER show
    /// protocol chatter (raw `::whisper-…::{json}` blobs) on the lock screen.
    private static let tokenLabels: [(prefix: String, label: String)] = [
        ("::whisper-call-v1::", "Incoming call"),
        ("::whisper-callsummary-v1::", "Call ended"),
        ("::whisper-program-v1::", "Sent you a program"),
        ("::whisper-workout-v1::", "Sent you a workout"),
        ("::whisper-workoutproposal-v1::", "Sent a workout proposal"),
        ("::whisper-coach-proposal-v1::", "New coach suggestion"),
        ("::whisper-coach-macros-v1::", "Sent your macros"),
        ("::whisper-coach-dietplan-v1::", "Sent a diet plan"),
        ("::whisper-postmeta-v1::", "Shared a post"),
        ("::whisper-post-v1::", "Shared a post"),
        ("::whisper-story-v1::", "Shared a story"),
        ("::whisper-storytag-v1::", "Shared a story"),
        ("::whisper-film-v1::", "Shared a film"),
        ("::whisper-article-v1::", "Shared an article"),
        ("::whisper-profile-v1::", "Shared a profile"),
        ("::whisper-quiz-v1::", "Sent a quiz"),
        ("::whisper-ember-v1::", "Shared a Jasper answer"),
        ("::whisper-jasper-v1::", "Shared a Jasper answer"),
        ("::whisper-factcheck-v1::", "Sent a fact-check"),
        ("::whisper-map-v1::", "Sent a map"),
        ("::whisper-chart-v1::", "Sent a chart"),
        ("::whisper-recipe-v1::", "Shared a recipe"),
        ("::whisper-grocery-v1::", "Sent a grocery list"),
        ("::whisper-macros-v1::", "Shared today's macros"),
        ("::whisper-checkin-v1::", "Sent a check-in"),
        ("::whisper-meeting-v1::", "Meeting invite"),
        ("::whisper-calendar-v1::", "Calendar event"),
        ("::whisper-clientcard-v1::", "Shared a client card"),
        ("::whisper-thought-v1::", "Replied to your note"),
        ("::whisper-matchreq-v1::", "Wants to match with you 💘"),
        ("::whisper-matched-v1::", "It's a match! 💘"),
    ]

    /// Rewrites a push body so raw wire tokens never reach the banner:
    /// - Bodies that ARE a token → the friendly label ("Shared a post").
    /// - Captions with a wire token → label only, including malformed payloads.
    /// - Sticker links (`jasper-sticker://…`) → "Sent a sticker".
    private func sanitize(_ body: String) -> String {
        guard body.utf8.count <= 262_144 else { return "New message" }
        var text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("::wg-v1::") {
            let parts = text.components(separatedBy: "::")
            guard parts.count >= 5, UUID(uuidString: parts[2]) != nil else { return "New message" }
            text = parts.dropFirst(4).joined(separator: "::")
        }
        if text.hasPrefix("Document invitation:") { return "Document invitation" }
        if text.hasPrefix("Signature request:") { return "Signature request" }
        if text.contains("::wg-") || text.hasPrefix("{") || text.hasPrefix("[") { return "New message" }
        if let marker = text.range(of: "::whisper-") {
            let tail = text[marker.lowerBound...]
            return Self.tokenLabels.first { tail.hasPrefix($0.prefix) }?.label ?? "New message"
        }

        if text.contains("jasper-sticker://") || text.contains("ember-sticker://") {
            return "Sent a sticker"
        }
        return text.isEmpty ? "New message" : String(text.prefix(180))
    }

    // MARK: - Supabase avatar lookup (fallback when payload lacks the URL)

    /// Public Supabase project endpoint + anon key (safe to embed — the same
    /// values ship inside the app bundle). Used only for a read-only profile
    /// avatar lookup when the push payload doesn't carry `sender_avatar_url`.
    private static let supabaseURL = "https://uryyyegnbtlmyhqlgndy.supabase.co"
    private static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVyeXl5ZWduYnRsbXlocWxnbmR5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUyMzM3MDcsImV4cCI6MjA5MDgwOTcwN30.fBo6K9yNHmk1nTArspc5ByMsWEiI2SahCFk6Mdp7qUQ"

    private struct ProfileAvatarRow: Decodable {
        let profile_image_url: String?
    }

    /// Resolves the sender's avatar URL from `whisper_profiles`, trying the
    /// stable user id first and falling back to the username. Best-effort
    /// with a tight timeout — the NSE has ~30s total and the avatar download
    /// still has to happen after this.
    private func fetchAvatarURL(userID: String, username: String) async -> String? {
        var queries: [String] = []
        if !userID.isEmpty {
            queries.append("user_id=eq.\(userID)")
        }
        let uname = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if !uname.isEmpty, uname.lowercased() != "someone" {
            let escaped = uname.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? uname
            queries.append("username=eq.\(escaped)")
        }
        guard !queries.isEmpty else { return nil }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        let session = URLSession(configuration: config)

        for query in queries {
            guard let url = URL(
                string: "\(Self.supabaseURL)/rest/v1/whisper_profiles?\(query)&select=profile_image_url&limit=1"
            ) else { continue }
            var request = URLRequest(url: url)
            request.setValue(Self.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(Self.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
                let rows = try JSONDecoder().decode([ProfileAvatarRow].self, from: data)
                if let found = rows.first?.profile_image_url, !found.isEmpty {
                    return found
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private func loadAvatar(urlString: String?) async -> INImage? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return nil
            }
            // Write to a temp file and load via URL — iOS renders avatars from
            // a file URL more reliably on the lock screen than from raw data.
            let ext = (url.pathExtension.isEmpty ? "jpg" : url.pathExtension)
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("whisper-avatar-\(UUID().uuidString).\(ext)")
            do {
                try data.write(to: tmp, options: .atomic)
                return INImage(url: tmp)
            } catch {
                return INImage(imageData: data)
            }
        } catch {
            return nil
        }
    }

    private func loadPrivateGroupAvatar(_ value: String?, groupID: String) async -> INImage? {
        guard let value, let url = URL(string: value), url.scheme == "https",
              url.host == "uryyyegnbtlmyhqlgndy.supabase.co",
              url.path.hasPrefix("/storage/v1/object/sign/whisper-group-avatars/\(groupID)/") else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
        request.httpMethod = "GET"
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.url?.host == url.host, http.expectedContentLength <= 1_048_576 else { return nil }
            var data = Data()
            for try await byte in bytes { guard data.count < 1_048_576 else { return nil }; data.append(byte) }
            return INImage(imageData: data)
        } catch { return nil }
    }

    @MainActor
    private func deliverCommunication(
        content: UNMutableNotificationContent,
        senderID: String,
        senderName: String,
        avatar: INImage?,
        groupID: String?,
        groupName: String?,
        groupAvatar: INImage?,
        contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        let handle = INPersonHandle(value: senderID.isEmpty ? senderName : senderID, type: .unknown)
        let sender = INPerson(
            personHandle: handle,
            nameComponents: nil,
            displayName: senderName,
            image: avatar,
            contactIdentifier: nil,
            customIdentifier: senderID.isEmpty ? senderName : senderID
        )
        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: content.body,
            speakableGroupName: groupName.map { INSpeakableString(spokenPhrase: $0) },
            conversationIdentifier: groupID.map { "group-\($0)" } ?? (senderID.isEmpty ? senderName : senderID),
            serviceName: nil,
            sender: sender,
            attachments: nil
        )
        if let avatar { intent.setImage(avatar, forParameterNamed: \.sender) }
        if let groupAvatar { intent.setImage(groupAvatar, forParameterNamed: \.speakableGroupName) }

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.donate { _ in }

        do {
            let updated = try content.updating(from: intent)
            contentHandler(updated)
        } catch {
            contentHandler(content)
        }
    }

    /// Call-flavored communication notification — the caller's avatar
    /// replaces the app icon on the "Incoming call" / "Missed call"
    /// banner, matching the DM banner treatment.
    @MainActor
    private func deliverCallCommunication(
        content: UNMutableNotificationContent,
        senderID: String,
        senderName: String,
        avatar: INImage?,
        isVideo: Bool,
        contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        let handle = INPersonHandle(value: senderID.isEmpty ? senderName : senderID, type: .unknown)
        let caller = INPerson(
            personHandle: handle,
            nameComponents: nil,
            displayName: senderName,
            image: avatar,
            contactIdentifier: nil,
            customIdentifier: senderID.isEmpty ? senderName : senderID
        )
        let intent = INStartCallIntent(
            callRecordFilter: nil,
            callRecordToCallBack: nil,
            audioRoute: .unknown,
            destinationType: .normal,
            contacts: [caller],
            callCapability: isVideo ? .videoCall : .audioCall
        )

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.donate { _ in }

        do {
            let updated = try content.updating(from: intent)
            contentHandler(updated)
        } catch {
            contentHandler(content)
        }
    }
}
