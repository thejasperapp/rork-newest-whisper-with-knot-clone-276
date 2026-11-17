import Foundation
import UIKit
import UserNotifications
import Intents

/// Per-category Whisper notification preferences. Persisted via
/// `AccountStorage` so they survive sign-out (per-account) and default
/// to ON for every category until the user turns one off in
/// Settings → Notifications.
enum WhisperNotificationCategory: String, CaseIterable, Identifiable {
    case dm = "dm"
    case mention = "mention"
    case like = "like"
    case comment = "comment"
    case follow = "follow"
    case storyResponse = "storyResponse"
    case newPost = "newPost"
    case calls = "calls"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dm:            return "Direct messages"
        case .mention:       return "@mentions"
        case .like:          return "Likes"
        case .comment:       return "Comments"
        case .follow:        return "New followers"
        case .storyResponse: return "Story responses"
        case .newPost:       return "New posts"
        case .calls:         return "Missed calls"
        }
    }

    var subtitle: String {
        switch self {
        case .dm:            return "New DMs and message embeds"
        case .mention:       return "When someone tags you in a post, comment, or DM"
        case .like:          return "When someone likes your post"
        case .comment:       return "Replies on your posts"
        case .follow:        return "Someone started following you"
        case .storyResponse: return "Poll votes, slider ratings, and question replies"
        case .newPost:       return "Occasional alerts when people you follow and interact with post after a break"
        case .calls:         return "When you miss a video or audio call"
        }
    }

    var icon: String {
        switch self {
        case .dm:            return "paperplane.fill"
        case .mention:       return "at"
        case .like:          return "heart.fill"
        case .comment:       return "bubble.right.fill"
        case .follow:        return "person.fill.badge.plus"
        case .storyResponse: return "chart.bar.doc.horizontal"
        case .newPost:       return "square.and.pencil"
        case .calls:         return "phone.arrow.down.left.fill"
        }
    }

    fileprivate var storageKey: String { "whisper.push.\(rawValue)" }
}

enum WhisperNotificationPrefs {
    /// Account-scoped preferences, queued for background push synchronization.
    static var masterEnabled: Bool {
        get { AccountStorage.object(forKey: "whisper.push") as? Bool ?? true }
        set {
            AccountStorage.set(newValue, forKey: "whisper.push")
            WhisperPushPreferenceSync.shared.changed(storageKey: "whisper.push", value: newValue)
        }
    }

    /// Quiet mode silences everything without changing per-category prefs.
    static var quietMode: Bool {
        get { AccountStorage.bool(forKey: "whisper.quiet") }
        set {
            AccountStorage.set(newValue, forKey: "whisper.quiet")
            WhisperPushPreferenceSync.shared.changed(storageKey: "whisper.quiet", value: newValue)
        }
    }

    static func isEnabled(_ category: WhisperNotificationCategory) -> Bool {
        guard masterEnabled, !quietMode else { return false }
        return AccountStorage.object(forKey: category.storageKey) as? Bool ?? true
    }

    static func setEnabled(_ category: WhisperNotificationCategory, _ on: Bool) {
        AccountStorage.set(on, forKey: category.storageKey)
        WhisperPushPreferenceSync.shared.changed(storageKey: category.storageKey, value: on)
    }
}

/// Whisper-side local notification scheduler. Hooked into the realtime
/// message ingestor + the follow service so users get a banner whenever
/// they receive a new DM or a new follower while the app is running.
///
/// We schedule local notifications (no push server required) — the
/// Supabase realtime channels deliver the row in real-time, then we
/// post a `UNNotificationRequest` with a 0.1s trigger. iOS suppresses
/// banners for messages received while the user is actively in the
/// matching thread.
@MainActor
@Observable
final class WhisperNotificationService {
    static let shared = WhisperNotificationService()

    /// Lowercased UID of the thread that's currently on-screen, so we
    /// don't pop a banner for a message that's already visible.
    var activeThreadOtherUID: String? = nil
    var activeThreadKind: WhisperConversationKind = .direct
    var activeGroupID: UUID?

    private let center = UNUserNotificationCenter.current()
    private var seenMessageIDs: Set<String> = []
    private var seenFollowerIDs: Set<String> = []
    private var seenSocialEvents: Set<String> = []
    private var notificationGeneration: UUID = AccountStorage.generation

    private init() {}

    private func prepareDedupe() {
        if notificationGeneration != AccountStorage.generation {
            notificationGeneration = AccountStorage.generation
            seenMessageIDs = []; seenFollowerIDs = []; seenSocialEvents = []
            activeThreadOtherUID = nil; activeGroupID = nil
        }
        if seenMessageIDs.count > 2048 { seenMessageIDs.removeAll(keepingCapacity: true) }
        if seenFollowerIDs.count > 2048 { seenFollowerIDs.removeAll(keepingCapacity: true) }
        if seenSocialEvents.count > 2048 { seenSocialEvents.removeAll(keepingCapacity: true) }
    }

    /// APNs-only social events must use the same foreground preferences as local banners.
    func shouldPresentRemoteSocial(_ info: [String: String], kind: String, fallbackID: String) -> Bool {
        prepareDedupe()
        let owner = info["recipient_user_id"] ?? ""
        guard UUID(uuidString: AccountStorage.currentUserID) != nil,
              owner.isEmpty || owner.lowercased() == AccountStorage.currentUserID.lowercased() else { return false }
        let category: WhisperNotificationCategory
        switch kind {
        case "like": category = .like
        case "comment": category = .comment
        case "story_response": category = .storyResponse
        case "whisper_new_post": category = .newPost
        default: return false
        }
        guard WhisperNotificationPrefs.isEnabled(category) else { return false }
        if kind == "whisper_new_post", UUID(uuidString: owner) == nil { return false }
        let id = info["response_id"] ?? info["comment_id"] ?? info["like_id"] ?? info["post_id"] ?? fallbackID
        return seenSocialEvents.insert(kind + ":" + id).inserted
    }

    /// Requests notification permission for Whisper. Safe to call on every
    /// app launch — iOS only shows the prompt once.
    func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                await UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            // ignore — user can enable later in Settings
        }
    }

    /// Schedules a banner for a freshly-received Whisper DM. No-ops if:
    /// - the message is one we sent
    /// - the message arrived while we were already viewing that thread
    /// - we've already scheduled this exact message id
    func notifyIncomingMessage(
        messageID: String,
        fromUsername: String,
        fromUID: String,
        currentUID: String,
        body: String,
        threadID: String? = nil
    ) {
        prepareDedupe()
        // APNs owns background delivery; local banners are only the foreground fallback.
        guard UIApplication.shared.applicationState == .active else { return }
        let inner = WhisperMessagePreview.group(body)?.body ?? body
        // Teams banners are server-authorized APNs only; writable wire text is not provenance.
        guard !inner.hasPrefix("::whisper-teams-"), !inner.hasPrefix("::whisper-storytag-v1::") else { return }
        guard !inner.hasPrefix("::whisper-call-"), !inner.hasPrefix("::whisper-callsummary-") else { return }
        let me = currentUID.lowercased()
        let other = fromUID.lowercased()
        guard other != me else { return }
        guard !seenMessageIDs.contains(messageID) else { return }
        seenMessageIDs.insert(messageID)
        guard WhisperNotificationPrefs.isEnabled(.dm) else { return }
        let group = WhisperMessagePreview.group(body)
        if let group {
            let service = WhisperGroupChatService.shared
            guard !service.muted.contains(group.id.uuidString.lowercased()), !service.left.contains(group.id.uuidString.lowercased()), activeGroupID != group.id else { return }
        }
        if group == nil, let active = activeThreadOtherUID, active.lowercased() == other,
           activeThreadKind == .resolve(threadID: threadID, first: me, second: other),
           UIApplication.shared.applicationState == .active {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = group?.name ?? "@\(fromUsername)"
        content.body = group == nil ? WhisperMessagePreview.text(body) : "\(WhisperMessagePreview.text(fromUsername)): \(WhisperMessagePreview.text(group?.body ?? ""))"
        content.threadIdentifier = group.map { "group-\($0.id.uuidString.lowercased())" } ?? threadID ?? other
        content.sound = .default
        content.categoryIdentifier = "WHISPER_DM"
        content.userInfo = [
            "kind": group == nil ? "whisper_dm" : "whisper_group",
            "groupID": group?.id.uuidString.lowercased() ?? "",
            "recipientUID": currentUID,
            "messageID": messageID,
            "threadID": threadID ?? "",
            "fromUID": fromUID,
            "fromUsername": fromUsername
        ]
        let request = UNNotificationRequest(
            identifier: "whisper-dm-\(messageID)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        center.add(request) { _ in }
    }

    /// The first foreground transport to handle a message owns its banner.
    func shouldPresentRemoteMessage(_ info: [String: String]) -> Bool {
        prepareDedupe()
        let owner = info["recipient_user_id"] ?? ""
        guard owner.isEmpty || owner.lowercased() == AccountStorage.currentUserID.lowercased(),
              WhisperNotificationPrefs.isEnabled(.dm) else { return false }
        if info["story_tag"] == "v1", !WhisperNotificationPrefs.isEnabled(.mention) { return false }
        if info["social_teams"] == "v1" {
            guard let sender = info["from_user_id"], !WhisperDMPrivacyService.shared.isDenied(sender),
                  !WhisperBlockService.shared.isBlocked(userID: sender) else { return false }
            let privacy = WhisperDMPrivacyService.shared
            if privacy.isPrivate && !privacy.isApproved(sender)
                && !WhisperFollowService.shared.isFollowing(userID: sender)
                && !WhisperFollowService.shared.isFollowedBy(userID: sender) { return false }
        }
        if let raw = info["group_id"], let id = UUID(uuidString: raw) {
            let service = WhisperGroupChatService.shared
            guard activeGroupID != id, !service.muted.contains(raw.lowercased()), !service.left.contains(raw.lowercased()) else { return false }
        } else if let sender = info["from_user_id"], activeThreadOtherUID?.lowercased() == sender.lowercased(),
                  activeThreadKind == .resolve(threadID: info["thread_id"], first: AccountStorage.currentUserID, second: sender) { return false }
        let deliveryID = info["message_reaction"] == "v1"
            ? info["reaction_event_id"].map { "reaction:\($0)" } : info["message_id"]
        if let id = deliveryID, !id.isEmpty {
            guard seenMessageIDs.insert(id).inserted else { return false }
        }
        return true
    }

    /// Schedules a "Missed call" banner — tapping it deep-links straight
    /// into the caller's DM thread (where the missed-call card lives).
    /// The caller's avatar renders on the banner (communication style),
    /// matching DM notifications.
    func notifyMissedCall(
        callID: String,
        fromUID: String,
        fromUsername: String,
        isVideo: Bool,
        avatarURL: URL? = nil,
        groupID: String? = nil,
        groupName: String? = nil
    ) {
        guard WhisperNotificationPrefs.isEnabled(.calls) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Missed \(isVideo ? "video" : "audio") call"
        content.body = "@\(fromUsername) tried to call you — tap to call back"
        content.sound = .default
        content.categoryIdentifier = "WHISPER_DM"
        if let groupName { content.title = "Missed call · \(groupName)" }
        content.userInfo = [
            "kind": "whisper_missed_call",
            "groupID": groupID ?? "",
            "recipientUID": AccountStorage.currentUserID,
            "fromUID": fromUID,
            "fromUsername": fromUsername
        ]
        scheduleCallBanner(
            identifier: "whisper-missedcall-\(callID)",
            content: content,
            fromUID: fromUID,
            fromUsername: fromUsername,
            isVideo: isVideo,
            avatarURL: avatarURL ?? cachedAvatarURL(forUID: fromUID)
        )
    }

    /// Rings a banner for an incoming call that arrived over the realtime
    /// socket while the app is backgrounded — the window where the VoIP
    /// push hasn't (or won't) fire. Category WHISPER_CALL carries the
    /// Answer/Decline actions; tapping the banner body answers directly.
    /// The payload mirrors the remote push shape (snake_case keys) so the
    /// same answer/decline routing handles both.
    func notifyIncomingCall(
        callID: String,
        fromUID: String,
        fromUsername: String,
        isVideo: Bool,
        avatarURL: URL? = nil,
        invite: WhisperCallSignal.Payload? = nil
    ) {
        guard WhisperNotificationPrefs.masterEnabled, !WhisperNotificationPrefs.quietMode else { return }
        let content = UNMutableNotificationContent()
        content.title = invite?.groupName ?? "Incoming \(isVideo ? "video" : "audio") call"
        content.body = "@\(fromUsername) is calling — tap to answer"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = "WHISPER_CALL"
        content.userInfo = [
            "kind": "call_invite",
            "call_id": callID,
            "from_user_id": fromUID,
            "from_username": fromUsername,
            "mode": isVideo ? "video" : "audio"
        ]
        if let invite {
            content.userInfo["meeting_id"] = invite.roomID
            content.userInfo["group_id"] = invite.groupId
            content.userInfo["group_name"] = invite.groupName
            content.userInfo["recipient_user_id"] = invite.toUserId ?? AccountStorage.currentUserID
            if let at = invite.at { content.userInfo["at"] = String(at) }
        }
        scheduleCallBanner(
            identifier: "whisper-call-\(callID)",
            content: content,
            fromUID: fromUID,
            fromUsername: fromUsername,
            isVideo: isVideo,
            avatarURL: avatarURL ?? cachedAvatarURL(forUID: fromUID)
        )
    }

    // MARK: - Call banner communication styling

    /// Avatar URL from the DM-thread profile cache — free when the caller
    /// has an existing conversation, which is nearly always true for calls.
    private func cachedAvatarURL(forUID uid: String) -> URL? {
        let key = uid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        return WhisperBackendService.shared.threadProfiles[key]?
            .profile_image_url
            .flatMap(URL.init(string:))
    }

    /// Posts a call banner, upgrading it to a communication notification
    /// (caller avatar replaces the app icon) when the photo can be fetched
    /// within a tight budget. Any failure falls back to the plain banner —
    /// the ring alert is never blocked on the avatar download.
    private func scheduleCallBanner(
        identifier: String,
        content: UNMutableNotificationContent,
        fromUID: String,
        fromUsername: String,
        isVideo: Bool,
        avatarURL: URL?
    ) {
        Task {
            let styled = await self.callCommunicationContent(
                base: content,
                fromUID: fromUID,
                fromUsername: fromUsername,
                isVideo: isVideo,
                avatarURL: avatarURL
            )
            let request = UNNotificationRequest(
                identifier: identifier,
                content: styled,
                trigger: nil
            )
            self.center.add(request) { _ in }
        }
    }

    /// Wraps the banner content in an `INStartCallIntent` whose caller
    /// `INPerson` carries the avatar — the same mechanism the notification
    /// service extension uses for remote DM pushes.
    private func callCommunicationContent(
        base: UNMutableNotificationContent,
        fromUID: String,
        fromUsername: String,
        isVideo: Bool,
        avatarURL: URL?
    ) async -> UNNotificationContent {
        var avatar: INImage?
        if let avatarURL {
            var req = URLRequest(url: avatarURL)
            req.timeoutInterval = 2
            if let (data, response) = try? await URLSession.shared.data(for: req),
               (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
               !data.isEmpty {
                // File-URL images render more reliably on the lock screen
                // than raw data payloads.
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("whisper-call-avatar-\(UUID().uuidString).jpg")
                if (try? data.write(to: tmp, options: .atomic)) != nil {
                    avatar = INImage(url: tmp)
                } else {
                    avatar = INImage(imageData: data)
                }
            }
        }
        let handle = INPersonHandle(value: fromUID.isEmpty ? fromUsername : fromUID, type: .unknown)
        let caller = INPerson(
            personHandle: handle,
            nameComponents: nil,
            displayName: fromUsername.hasPrefix("@") ? fromUsername : "@\(fromUsername)",
            image: avatar,
            contactIdentifier: nil,
            customIdentifier: fromUID.isEmpty ? fromUsername : fromUID
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
        if let updated = try? base.updating(from: intent) {
            return updated
        }
        return base
    }

    /// Pulls the incoming-call banner the moment the ring resolves
    /// (answered, declined, cancelled, timed out) so a dead banner can't
    /// linger in Notification Center and get tapped into a stale join.
    func clearIncomingCallBanner(callID: String) {
        let id = "whisper-call-\(callID)"
        center.removeDeliveredNotifications(withIdentifiers: [id])
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Schedules a banner for a new follower.
    func notifyNewFollower(followerID: String, followerUsername: String) {
        prepareDedupe()
        guard UIApplication.shared.applicationState == .active else { return }
        guard !seenFollowerIDs.contains(followerID) else { return }
        seenFollowerIDs.insert(followerID)
        guard WhisperNotificationPrefs.isEnabled(.follow) else { return }
        let content = UNMutableNotificationContent()
        content.title = "New follower"
        content.body = "@\(followerUsername) started following you"
        content.sound = .default
        content.categoryIdentifier = "WHISPER_FOLLOW"
        content.userInfo = [
            "kind": "whisper_follow",
            "followerID": followerID,
            "followerUsername": followerUsername
        ]
        let request = UNNotificationRequest(
            identifier: "whisper-follow-\(followerID)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        center.add(request) { _ in }
    }

    /// Schedules a banner when a post you made gets a new like / comment.
    func notifyPostInteraction(postID: String, kind: String, actorUsername: String) {
        let category: WhisperNotificationCategory? = {
            switch kind {
            case "like":    return .like
            case "comment": return .comment
            default:        return nil
            }
        }()
        if let category, !WhisperNotificationPrefs.isEnabled(category) { return }
        let id = "whisper-\(kind)-\(postID)-\(actorUsername)"
        let content = UNMutableNotificationContent()
        switch kind {
        case "like":
            content.title = "@\(actorUsername) liked your post"
            content.body = "Tap to view"
        case "comment":
            content.title = "@\(actorUsername) commented"
            content.body = "Tap to view the comment"
        default:
            content.title = "@\(actorUsername)"
            content.body = "New activity on your post"
        }
        content.sound = .default
        content.categoryIdentifier = "WHISPER_ACTIVITY"
        content.userInfo = [
            "kind": "whisper_activity",
            "postID": postID,
            "actorUsername": actorUsername
        ]
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        center.add(request) { _ in }
    }

    /// Schedules a banner when someone @mentions the current user in a
    /// post / comment / reel / DM. iOS dedupes by identifier so the same
    /// mention id only ever fires once even if the realtime channel echoes.
    func notifyMention(
        mentionID: String,
        fromUsername: String,
        sourceType: String,
        sourceID: String
    ) {
        guard WhisperNotificationPrefs.isEnabled(.mention) else { return }
        let content = UNMutableNotificationContent()
        content.title = "@\(fromUsername) mentioned you"
        switch sourceType {
        case "post":    content.body = "Tap to view the post"
        case "comment": content.body = "Tap to view the comment"
        case "reel":    content.body = "Tap to view the reel"
        case "dm":      content.body = "Tap to open the chat"
        default:        content.body = "Tap to view"
        }
        content.sound = .default
        content.categoryIdentifier = "WHISPER_MENTION"
        content.userInfo = [
            "kind": "whisper_mention",
            "sourceType": sourceType,
            "sourceID": sourceID,
            "fromUsername": fromUsername
        ]
        let request = UNNotificationRequest(
            identifier: "whisper-mention-\(mentionID)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        center.add(request) { _ in }
    }

    /// Schedules a banner when the current user just earned a Liar Liar
    /// strike for a false / misleading fact-check on one of their posts.
    /// Fires every time so the user is aware of how close they are to the
    /// auto-badge threshold (3 strikes / 30 days).
    func notifyLiarStrike(
        strikeID: String,
        count: Int,
        threshold: Int,
        verdictLabel: String,
        claimPreview: String
    ) {
        // Compatibility for older callers: automatic reputation notifications are retired.
    }

    /// Recomputes the app icon badge from the union of unread DMs +
    /// unread mentions + unread story responses, and applies it via
    /// `UNUserNotificationCenter.setBadgeCount(_:)`. Idempotent and safe
    /// to call on every realtime event.
    func refreshAppIconBadge() {
        let dms = WhisperWidgetSnapshotDefaults(suiteName: "group.com.mydailywhisper.whisper")?
            .integer(forKey: "whisper_unread_dm_count") ?? 0
        let mentions = WhisperMentionsService.shared.unreadCount
        let stories = WhisperStoryResponseService.shared.unreadCount
        let total = max(0, dms + mentions + stories)
        center.setBadgeCount(total) { _ in }
    }

    private func previewBody(_ body: String) -> String {
        if body.hasPrefix("::whisper-program-v1::") { return "Sent you a program" }
        if let w = WhisperWorkoutEmbed.decode(body) {
            let t = w.displayName.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? "Shared a workout" : "Shared workout · \(t)"
        }
        if body.hasPrefix(WhisperSharedCommunityEmbed.prefix) { return "Shared a community" }
        if let p = WhisperSharedPostEmbed.decode(body) {
            return "Shared @\(p.username)'s post"
        }
        if let p = WhisperProfileShareEmbed.decode(body) {
            return "Shared @\(p.username)'s profile"
        }
        if let r = WhisperRecipeEmbed.decode(body) {
            let t = r.title.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? "Shared a recipe" : "Shared recipe · \(t)"
        }
        if let g = WhisperGroceryListEmbed.decode(body) {
            let t = g.title.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? "Sent a grocery list" : "Grocery list · \(t)"
        }
        if WhisperMacrosShareEmbed.decode(body) != nil { return "Shared today's macros" }
        if WhisperCheckinEmbed.decode(body) != nil { return "Sent a check-in" }
        if WhisperChartEmbed.decode(body) != nil { return "Shared a chart" }
        if WhisperMapEmbed.decode(body) != nil { return "Sent a location" }
        if WhisperEmberAnswerEmbed.decode(body) != nil { return "Shared an Jasper answer" }
        if WhisperFactCheckEmbed.decode(body) != nil { return "Shared a fact-check" }
        if WhisperWorkoutProposalEmbed.decode(body) != nil { return "Sent a workout proposal" }
        if WhisperCoachMacrosEmbed.decode(body) != nil { return "Sent a macros plan" }
        if WhisperCoachDietPlanEmbed.decode(body) != nil { return "Sent a diet plan" }
        // Call control + summary signals are protocol chatter — never show
        // the raw JSON if one slips into this path.
        if body.hasPrefix("::whisper-call-v1::") { return "Incoming call" }
        if let summary = WhisperCallSummaryEmbed.decode(body) {
            if summary.connected {
                return "\(summary.isVideo ? "Video" : "Audio") call · \(summary.durationLabel)"
            }
            return "Missed \(summary.isVideo ? "video" : "audio") call"
        }
        if body.hasPrefix("::whisper-coach-proposal-v1::") { return "New coach suggestion" }
        if let cal = WhisperCalendarEmbed.decode(body) {
            return "Calendar invite · \(cal.title)"
        }
        if body.hasPrefix("http"), body.contains("whisper-media") { return "Sent a photo" }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 140 { return String(trimmed.prefix(140)) + "…" }
        return trimmed
    }
}
