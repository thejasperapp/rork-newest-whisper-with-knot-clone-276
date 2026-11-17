import SwiftUI
import AppIntents
import BackgroundTasks
import WidgetKit
import UIKit
import CoreSpotlight

@main
struct WhisperFitnessAppApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        #if DEBUG
        print("[WhisperLaunch] app_initialized")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .scrollIndicators(.hidden)
                .modifier(WhisperNotesLinkHandling())
                .background { WhisperNotebookSyncAgent() }
                .background { WhisperKnotSyncAgent() }
                .modifier(WhisperKnotContactPresentation())
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                          let item = SpotlightService.IndexableItem(rawValue: identifier) else { return }
                    handleSpotlightNavigation(item)
                }
                .onOpenURL { url in
                    // Meeting links open the room IN the app — universal links
                    // (mydailywhisper.com/meet/…, meet.mydailywhisper.com/…)
                    // and the web lobby's whisper://meet/… hand-off.
                    if WhisperMeetingLinkRouter.handle(url) { return }
                    // Jasper's Allow screen bounces back via
                    // whisper://linked?code=…&state=… — hand it to the link
                    // service so the one-button connect flow completes
                    // (redeem → token mint → celebration). Without this the
                    // return link was silently dropped and the card sat on
                    // "Finish in Jasper" forever.
                    _ = WhisperWhisperLinkService.shared.handleReturn(url: url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    // Universal links arrive here on some launch paths.
                    guard let url = activity.webpageURL else { return }
                    _ = WhisperMeetingLinkRouter.handle(url)
                }
                .task {
                    // ONE query hydrates every role/badge gate (coach,
                    // athlete, recruiter, brand, verified/mod/admin/owner)
                    // right at launch — the briefcase and role tools are
                    // correct before the user ever opens the inbox.
                    await WhisperAccountStatusService.shared.refresh()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                Task { @MainActor in
                    WhisperPresenceService.shared.stopHeartbeat()
                }
                scheduleBackgroundRefresh()
                let userID = AuthenticationService.shared.currentUser.userID
                if userID != "guest" {
                    Task {
                        let profile = AuthenticationService.shared.currentUser
                        guard profile.userID == userID else { return }
                        await CloudKitService.shared.saveBackgroundSnapshot(profile)
                    }
                }
            }
            if newPhase == .active {
                // Heartbeat presence so "Active now" reflects real usage even
                // before the user opens the inbox.
                Task { @MainActor in
                    WhisperPresenceService.shared.startHeartbeat()
                    await WhisperPresenceService.shared.beat()
                }
                // Refresh the unified account status on foreground (60s
                // cache — a promotion granted while backgrounded shows up
                // without relaunching).
                Task { await WhisperAccountStatusService.shared.refresh() }
                WidgetCenter.shared.reloadAllTimelines()
                let activeUserID = AuthenticationService.shared.currentUser.userID
                if activeUserID != "guest" {
                    Task {
                        await CloudKitService.shared.restoreAllUserDataIfStale(userID: activeUserID)
                    }
                }
                // HealthKit data refresh on foreground — only if the user
                // has already granted access in the past. We deliberately do
                // NOT call requestAuthorization() here so Whisper never asks
                // for Health permission at launch/sign-up (HIG: ask in-context).
                Task {
                    await WhisperHealthRefreshCoordinator.shared.refresh(deferForLaunch: true)
                }
            }
        }
        .backgroundTask(.appRefresh("app.rork.jasper.widget.refresh")) {
            await MainActor.run {
                let service = HealthKitService()
                Task {
                    // No prompt from background tasks — fetchAllData no-ops
                    // gracefully if the user hasn't authorized HealthKit.
                    await service.fetchAllData()
                    WidgetCenter.shared.reloadAllTimelines()
                    scheduleBackgroundRefresh()
                }
            }
        }
        .backgroundTask(.appRefresh("app.rork.whisper.content.refresh")) {
            // Prefetch fresh social content (feed, inbox, first-screen images)
            // while backgrounded so the app opens onto new content instantly.
            await MainActor.run { scheduleBackgroundRefresh() }
            await WhisperBackgroundRefreshService.shared.refreshContent()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Buffered deep-link from a notification tap that arrived BEFORE MainTabView was
    /// subscribed to `.jasperDeepLink` (cold-launch from terminated state). MainTabView
    /// drains this on appear so taps are never lost. Cleared after consumption.
    @MainActor static var pendingDeepLink: [AnyHashable: Any]? = nil

    /// Same buffering for Whisper notification taps (DMs, missed calls,
    /// mentions, activity, new posts, follows) — drained by `WhisperRootView`
    /// once the shell mounts, so cold-launch taps still land on the right
    /// thread / post / profile.
    @MainActor static var pendingWhisperDeepLink: [AnyHashable: Any]? = nil

    /// Orientation gate: the app is portrait-only on iPhone EXCEPT while a
    /// rotation-aware screen (the film theater) is up — that screen widens
    /// the mask on appear and restores portrait on dismiss. iPad keeps every
    /// orientation.
    @MainActor static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad { return .all }
        return AppDelegate.orientationLock
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        WhisperImageCache.trimDecodedImages()
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if DEBUG
        print("[WhisperLaunch] delegate_started bundle=\(Bundle.main.bundleIdentifier ?? "unknown")")
        #endif
        // Replace the default UIRefreshControl gray circle with Whisper's
        // traced-W indicator (see WhisperRefreshable.swift).
        WhisperRefreshAppearance.install()

        // A social feed lives and dies on image cache hits — the default
        // URLCache (a few MB) forces avatars, grid tiles, and feed photos to
        // re-download on every scroll pass. Give AsyncImage (which rides
        // URLSession.shared) a real cache so tabs paint instantly from disk.
        URLCache.shared = URLCache(
            memoryCapacity: 96 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024
        )

        UNUserNotificationCenter.current().delegate = self
        WhisperLegacyNotificationCleanup.runIfNeeded()
        // Actionable categories (Answer/Decline buttons on incoming-call
        // banners) — registered AFTER the legacy cleanup, which clears the
        // category set.
        WhisperNotificationCategories.register()
        application.registerForRemoteNotifications()

        // VoIP PushKit + CallKit: incoming calls ring with the native
        // full-screen call UI (Answer / Decline) even when the app is
        // backgrounded or terminated.
        WhisperVoIPService.shared.start()
        Task { await WhisperVoIPService.shared.registerIfNeeded() }
        SpotlightService.indexAllItems()

        // Prepare haptics so first feedback fires without latency.
        Haptics.prepareAll()

        // Populate widgets from HealthKit on launch IF the user has
        // already authorized it. We never prompt here — Whisper is a social
        // app, not a fitness tracker, so a Health permission sheet on cold
        // launch (especially during sign-up) would feel like a dark pattern.
        // Permission is requested in-context wherever Health data is shown.
        Task { @MainActor in
            await WhisperHealthRefreshCoordinator.shared.refresh(deferForLaunch: true)
        }

        let dontDeleteAction = UIApplicationShortcutItem(
            type: "com.jasper.dontdelete",
            localizedTitle: "Wait! Don't delete me! \u{1F97A}",
            localizedSubtitle: "You're on the path to a better life.",
            icon: nil,
            userInfo: nil
        )
        application.shortcutItems = [dontDeleteAction]

        #if DEBUG
        print("[WhisperLaunch] delegate_ready")
        #endif
        return true
    }

    nonisolated func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        Task { @MainActor in
            UserDefaults.standard.set(token, forKey: "pushNotificationToken")
            WhisperPushService.shared.handleAPNsToken(token)
        }
    }

    nonisolated func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    }

    // NOTE: These MUST be the completion-handler variants, NOT the
    // `async` ones. The async variants' generated Objective-C thunks
    // invoke UIKit's internal completion (which snapshots app state via
    // _updateStateRestorationArchiveForBackgroundEvent) on a Swift
    // Concurrency BACKGROUND executor thread — UIKit asserts main-thread
    // and aborts. That was the notification-tap crash in TestFlight
    // reports 36B14A5B / 73E4C6C3: every tap on a push while the app was
    // cold killed it ~200ms after launch. Hopping to the main actor and
    // calling the handler there is the fix.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Remote pushes duplicate banners the in-app realtime pipeline
        // already fires while the app is OPEN (DMs, mentions, follows,
        // thought replies) — and incoming-call pushes compete with the live
        // in-app ring UI. Suppress those while active; show everything else.
        var kind: String?
        let isPush = notification.request.trigger is UNPushNotificationTrigger
        if isPush {
            let userInfo = notification.request.content.userInfo
            kind = userInfo["kind"] as? String
            if kind == nil, let data = userInfo["data"] as? [AnyHashable: Any] {
                kind = data["kind"] as? String
            }
        }
        let resolvedKind = kind
        let contentInfo = notification.request.content.userInfo
        let messageInfo = ((contentInfo["data"] as? [String: Any]) ?? contentInfo.reduce(into: [String: Any]()) { result, item in
            if let key = item.key as? String { result[key] = item.value }
        }).compactMapValues { $0 as? String }
        let eventIdentifier = notification.request.identifier
        Task { @MainActor in
            if isPush, resolvedKind == "knot_invitation" || resolvedKind == "knot_update" {
                guard messageInfo["recipient_user_id"]?.lowercased() == AccountStorage.currentUserID.lowercased() else { completionHandler([]); return }
                if resolvedKind == "knot_invitation" {
                    Task { await WhisperKnotContactService.shared.refresh() }
                    completionHandler([])
                } else { completionHandler(WhisperNotificationPrefs.isEnabled(.dm) ? [.banner, .sound] : []) }
                return
            }
            if isPush, let resolvedKind, ["like", "comment", "story_response", "whisper_new_post"].contains(resolvedKind) {
                completionHandler(WhisperNotificationService.shared.shouldPresentRemoteSocial(messageInfo, kind: resolvedKind, fallbackID: eventIdentifier) ? [.banner, .sound, .badge] : [])
                return
            }
            if isPush, resolvedKind == "dm" || resolvedKind == "group" {
                completionHandler(WhisperNotificationService.shared.shouldPresentRemoteMessage(messageInfo) ? [.banner, .sound, .badge] : [])
                return
            }
            let coveredLocally: Set<String> = [
                "dm", "group", "mention", "follow", "whisper_thought_reply",
                "call_invite", "call_missed"
            ]
            if isPush,
               let resolvedKind,
               coveredLocally.contains(resolvedKind),
               UIApplication.shared.applicationState == .active {
                completionHandler([])
                return
            }
            completionHandler([.banner, .sound, .badge])
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let category = response.notification.request.content.categoryIdentifier
        let identifier = response.notification.request.identifier
        let actionIdentifier = response.actionIdentifier
        let title = response.notification.request.content.title
        let body = response.notification.request.content.body
        // Flatten userInfo to Sendable String pairs before hopping actors —
        // this carries the Whisper deep-link payload (kind, usernames, post
        // ids). Remote APNs pushes nest their payload under a `data` dict,
        // so nested dictionaries are merged up to the top level (skipping
        // `aps`, whose alert title/body would collide).
        var info: [String: String] = [:]
        func absorb(_ dict: [AnyHashable: Any]) {
            for (key, value) in dict {
                guard let k = key as? String, k != "aps" else { continue }
                if let s = value as? String {
                    info[k] = s
                } else if let n = value as? NSNumber {
                    info[k] = n.stringValue
                } else if let nested = value as? [AnyHashable: Any] {
                    absorb(nested)
                }
            }
        }
        absorb(response.notification.request.content.userInfo)
        let userInfo = info
        let receivedAt = response.notification.date
        Task { @MainActor in
            handleNotificationResponse(
                category: category,
                identifier: identifier,
                action: actionIdentifier,
                title: title,
                body: body,
                userInfo: userInfo,
                receivedAt: receivedAt
            )
            completionHandler()
        }
    }
}

private func handleSpotlightNavigation(_ item: SpotlightService.IndexableItem) {
    if let tabIndex = item.tabIndex {
        NotificationCenter.default.post(name: .jasperDeepLink, object: nil, userInfo: ["tab": tabIndex])
    } else {
        switch item {
        case .ember:
            NotificationCenter.default.post(name: .jasperDeepLink, object: nil, userInfo: ["action": "ember"])
        case .sleep:
            NotificationCenter.default.post(name: .jasperDeepLink, object: nil, userInfo: ["tab": 2, "action": "sleep"])
        case .meditation:
            NotificationCenter.default.post(name: .jasperDeepLink, object: nil, userInfo: ["tab": 2, "action": "meditation"])
        case .journal:
            NotificationCenter.default.post(name: .jasperDeepLink, object: nil, userInfo: ["tab": 2, "action": "journal"])
        default: break
        }
    }
}

@MainActor
private func handleNotificationResponse(
    category: String,
    identifier: String,
    action: String,
    title: String,
    body: String,
    userInfo: [String: String] = [:],
    receivedAt: Date = Date()
) {
    if ["knot_update", "knot_invitation"].contains(userInfo["kind"] ?? "") {
        WhisperKnotContactService.shared.receive(userInfo)
        return
    }
    // Call banner action buttons (alert-push fallback path — CallKit
    // handles Answer/Decline natively when a VoIP token is registered).
    if action == WhisperNotificationCategories.answerCallAction {
        handleCallNotificationAction(answer: true, info: userInfo, receivedAt: receivedAt)
        return
    }
    if action == WhisperNotificationCategories.declineCallAction {
        handleCallNotificationAction(answer: false, info: userInfo, receivedAt: receivedAt)
        return
    }

    // Whisper notifications carry a `kind` payload — route them straight to
    // their destination (DM thread, post, profile, calendar) instead of the
    // legacy Jasper tab fallback.
    if let kind = userInfo["kind"], kind.hasPrefix("whisper") {
        dispatchWhisperDeepLink(normalizedWhisperPayload(userInfo, title: title) ?? userInfo)
        return
    }

    // Remote APNs pushes use short snake_case kinds ("dm", "follow",
    // "like", …) — normalize them into the canonical whisper_* shape the
    // router understands. This is what makes TAPPING a push land on the
    // right thread/post/profile instead of the Home tab.
    if let normalized = normalizedWhisperPayload(userInfo, title: title) {
        if normalized["kind"] == "whisper_call_invite" {
            // Tapping the call banner = answering the call (WhatsApp
            // behavior). handleCallNotificationAction reconstructs the
            // invite from the push payload (works from cold launch), joins
            // when the ring is still fresh, and falls back to the caller's
            // thread (missed-call card) when it rang out long ago.
            handleCallNotificationAction(answer: true, info: userInfo, receivedAt: receivedAt)
            return
        }
        dispatchWhisperDeepLink(normalized)
        return
    }

    // Handle explicit action buttons first.
    switch action {
    case "SNOOZE":
        // Legacy snooze action — Whisper no longer fires fitness reminders.
        return
    case "DISMISS", UNNotificationDismissActionIdentifier:
        return
    case "LOG_WATER":
        let key = "jasper_water_glasses_\(todayKey())"
        let current = AccountStorage.integer(forKey: key)
        AccountStorage.set(current + 1, forKey: key)
        NotificationCenter.default.post(name: Notification.Name("jasperWaterLogged"), object: nil)
        dispatchDeepLink(["tab": 3])
        return
    case "START_WORKOUT":
        dispatchDeepLink(["tab": 1, "action": "start_workout"])
        return
    case "CHECK_IN":
        dispatchDeepLink(["tab": 0, "action": "checkin"])
        return
    case "VIEW_SUMMARY":
        dispatchDeepLink(["tab": 0, "action": "weekly_summary"])
        return
    case "OPEN_BEACH":
        dispatchDeepLink(["action": "beach_bonanza"])
        return
    default:
        break // fall through to category routing (default tap)
    }

    // Default tap = route by category / id. Anything we don't recognize falls back
    // to Home so we NEVER fail to open the app — this prevents crashes from
    // unhandled categories and guarantees the user always lands somewhere safe.
    let payload: [AnyHashable: Any]
    switch category {
    case "DEEPLINK_HOME":
        payload = ["tab": 0]
    case "DEEPLINK_WORKOUTS":
        payload = ["tab": 1]
    case "DEEPLINK_WELLNESS":
        payload = ["tab": 2]
    case "DEEPLINK_NUTRITION":
        payload = ["tab": 3]
    case "DEEPLINK_CHECKIN":
        payload = ["tab": 0, "action": "checkin"]
    case "DEEPLINK_WEEKLY":
        payload = ["tab": 0, "action": "weekly_summary"]
    case "DEEPLINK_BEACH_BONANZA":
        payload = ["action": "beach_bonanza"]
    case "DEEPLINK_EMBER":
        payload = ["action": "ember"]
    case "SMART_NOTIFICATION":
        let id = identifier.lowercased()
        if id.contains("workout") {
            payload = ["tab": 1]
        } else if id.contains("sleep") {
            payload = ["tab": 2]
        } else if id.contains("hydration") || id.contains("macro") || id.contains("nutrition") {
            payload = ["tab": 3]
        } else if id.contains("meditation") || id.contains("stress") || id.contains("breath") {
            payload = ["tab": 2]
        } else if id.contains("morning_brief") || id.contains("ember") {
            payload = ["action": "ember"]
        } else {
            payload = ["tab": 0]
        }
    default:
        payload = ["tab": 0]
    }
    dispatchDeepLink(payload)
}

/// Maps a remote push's snake_case payload (`kind: dm/follow/like/…` +
/// `from_user_id`-style ids nested under `data`) into the canonical
/// `whisper_*` deep-link shape used by local notifications and the router.
@MainActor
func normalizedWhisperPayload(_ info: [String: String], title: String) -> [String: String]? {
    guard let raw = info["kind"] else { return nil }
    switch raw {
    case "group":
        return ["kind": "whisper_group", "groupID": info["group_id"] ?? "", "recipientUID": info["recipient_user_id"] ?? "", "messageID": info["message_id"] ?? ""]
    case "dm":
        if let group = info["group_id"], UUID(uuidString: group) != nil {
            return ["kind": "whisper_group", "groupID": group, "recipientUID": info["recipient_user_id"] ?? "", "messageID": info["message_id"] ?? ""]
        }
        // The DM push title has always been the sender's username — use it
        // as a fallback for pushes sent before `from_username` existed.
        let titleName = title.hasPrefix("@") ? String(title.dropFirst()) : title
        return [
            "kind": "whisper_dm",
            "recipientUID": info["recipient_user_id"] ?? "",
            "fromUID": info["from_user_id"] ?? "",
            "fromUsername": info["from_username"] ?? (info["social_teams"] == "v1" ? "" : titleName),
            "messageID": info["message_id"] ?? "",
            "threadID": info["thread_id"] ?? ""
        ]
    case "call_missed":
        return [
            "kind": "whisper_missed_call",
            "groupID": info["group_id"] ?? "",
            "recipientUID": info["recipient_user_id"] ?? "",
            "fromUID": info["from_user_id"] ?? "",
            "fromUsername": info["from_username"] ?? ""
        ]
    case "call_invite":
        return [
            "kind": "whisper_call_invite",
            "groupID": info["group_id"] ?? "",
            "recipientUID": info["recipient_user_id"] ?? "",
            "fromUID": info["from_user_id"] ?? "",
            "fromUsername": info["from_username"] ?? "",
            "callID": info["call_id"] ?? "",
            "mode": info["mode"] ?? "audio"
        ]
    case "follow":
        return [
            "kind": "whisper_follow",
            "recipientUID": info["recipient_user_id"] ?? "",
            "followerID": info["follower_user_id"] ?? "",
            "followerUsername": info["follower_username"] ?? ""
        ]
    case "whisper_new_post":
        return ["kind": "whisper_new_post", "postID": info["post_id"] ?? info["postID"] ?? "",
                "recipientUID": info["recipient_user_id"] ?? info["recipientUID"] ?? ""]
    case "like":
        return [
            "kind": "whisper_activity",
            "postID": info["post_id"] ?? "",
            "actorUsername": info["liker_username"] ?? "",
            "recipientUID": info["recipient_user_id"] ?? ""
        ]
    case "comment":
        return [
            "kind": "whisper_activity",
            "postID": info["post_id"] ?? "",
            "actorUsername": info["commenter_username"] ?? "",
            "commentID": info["comment_id"] ?? "",
            "recipientUID": info["recipient_user_id"] ?? ""
        ]
    case "mention":
        return [
            "kind": "whisper_mention",
            "recipientUID": info["recipient_user_id"] ?? "",
            "sourceType": info["source_type"] ?? "",
            "sourceID": info["source_id"] ?? "",
            "fromUID": info["author_user_id"] ?? "",
            "fromUsername": info["author_username"] ?? ""
        ]
    case "story_response":
        return ["kind": "whisper_story_response", "storyID": info["story_id"] ?? "",
                "responseID": info["response_id"] ?? "", "recipientUID": info["recipient_user_id"] ?? ""]
    default:
        return nil
    }
}

/// Answer / Decline pressed on an incoming-call banner. Works from cold
/// launch too: the push payload carries everything needed to reconstruct
/// the invite (call id, caller, mode) before joining or declining.
@MainActor
private func handleCallNotificationAction(answer: Bool, info: [String: String], receivedAt: Date) {
    let callID = info["call_id"] ?? ""
    let fromUID = info["from_user_id"] ?? ""
    let fromUsername = info["from_username"] ?? "Unknown"
    let mode: WhisperCallSignal.Mode = (info["mode"] == "video") ? .video : .audio
    guard !callID.isEmpty, !fromUID.isEmpty else { return }
    let calls = WhisperCallService.shared

    if !answer {
        if let call = calls.active, call.id == callID {
            calls.declineIncoming()
        } else {
            // No in-app ring to dismiss — fire the decline signal directly
            // so the caller's ring stops, without flashing any UI here.
            let payload = WhisperCallSignal.Payload(id: callID, kind: .decline, mode: mode)
            let body = WhisperCallSignal.encode(payload)
            if !body.isEmpty {
                Task {
                    _ = await WhisperBackendService.shared.sendMessage(
                        toUserID: fromUID,
                        toUsername: fromUsername,
                        body: body
                    )
                }
            }
        }
        return
    }

    // Answer: a ring older than ~50s is long over — land in the thread
    // (missed-call card) instead of joining a dead room.
    if Date().timeIntervalSince(receivedAt) > 50 {
        dispatchWhisperDeepLink([
            "kind": "whisper_missed_call",
            "groupID": info["group_id"] ?? "",
            "recipientUID": info["recipient_user_id"] ?? "",
            "fromUID": fromUID,
            "fromUsername": fromUsername
        ])
        return
    }
    if let invite = WhisperCallSignal.pushInvite(info) {
        calls.handleSignal(
            invite,
            fromUserID: fromUID,
            fromUsername: fromUsername,
            currentUID: AccountStorage.currentUserID
        )
    }
    if let call = calls.active, call.id == callID, call.direction == .incoming, call.state == .ringing {
        calls.answerIncoming()
    } else {
        dispatchWhisperDeepLink([
            "kind": "whisper_missed_call",
            "groupID": info["group_id"] ?? "",
            "recipientUID": info["recipient_user_id"] ?? "",
            "fromUID": fromUID,
            "fromUsername": fromUsername
        ])
    }
}

/// Posts the Whisper deep link AND buffers it for cold launches. The re-posts
/// cover the window where the target tab / screen is still mounting.
@MainActor
private func dispatchWhisperDeepLink(_ payload: [String: String]) {
    let info: [AnyHashable: Any] = payload
    if WhisperExternalRouteStore.shared.enqueue(notification: info) { return }
    AppDelegate.pendingWhisperDeepLink = info
    let name = Notification.Name("WhisperNotificationDeepLink")
    NotificationCenter.default.post(name: name, object: nil, userInfo: info)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
        NotificationCenter.default.post(name: name, object: nil, userInfo: info)
    }
}

/// Posts the deep link AND stores it as `pendingDeepLink` so cold-launches
/// (where MainTabView hasn't subscribed yet) still get routed once it mounts.
/// Re-posts after a short delay as a safety net for slow mount paths.
@MainActor
private func dispatchDeepLink(_ payload: [AnyHashable: Any]) {
    AppDelegate.pendingDeepLink = payload
    NotificationCenter.default.post(name: .jasperDeepLink, object: nil, userInfo: payload)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
        NotificationCenter.default.post(name: .jasperDeepLink, object: nil, userInfo: payload)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        NotificationCenter.default.post(name: .jasperDeepLink, object: nil, userInfo: payload)
    }
}

private func todayKey() -> String {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    return df.string(from: Date())
}

extension Notification.Name {
    static let jasperDeepLink = Notification.Name("jasperDeepLink")
    static let emberDeepLinkStartWorkout = Notification.Name("emberDeepLinkStartWorkout")
    static let emberDeepLinkWeeklyDigest = Notification.Name("emberDeepLinkWeeklyDigest")
    static let emberDeepLinkWellnessAction = Notification.Name("emberDeepLinkWellnessAction")
    /// Generic Jasper deep link for newer surfaces (friends, leaderboard,
    /// bookmarks, ambient sounds, etc). Listeners inspect `userInfo["action"]`.
    static let emberDeepLinkGeneric = Notification.Name("emberDeepLinkGeneric")
}

private func scheduleBackgroundRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: "app.rork.jasper.widget.refresh")
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
    try? BGTaskScheduler.shared.submit(request)

    // Social-content prefetch — iOS decides the exact moment, typically
    // shortly before the user's habitual open times, so feed + DMs are
    // already fresh when the app comes to the foreground.
    let content = BGAppRefreshTaskRequest(identifier: "app.rork.whisper.content.refresh")
    content.earliestBeginDate = Date(timeIntervalSinceNow: 20 * 60)
    try? BGTaskScheduler.shared.submit(content)
}
