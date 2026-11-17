import Foundation
import UserNotifications

@Observable
@MainActor
class NotificationService {
    static let shared = NotificationService()

    var isAuthorized: Bool = false
    var hasCompletedSetup: Bool {
        AccountStorage.bool(forKey: "notificationSetupComplete")
    }

    private let center = UNUserNotificationCenter.current()

    struct NotificationPreference: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let color: String
        var isEnabled: Bool
        var frequency: NotificationFrequency
    }

    nonisolated enum NotificationFrequency: String, CaseIterable, Sendable {
        case everyTwoHours = "Every 2 Hours"
        case daily = "Daily"
        case twiceDaily = "Twice Daily"
        case weekly = "Weekly"
        case threeTimesWeek = "3x per Week"
    }

    var preferences: [NotificationPreference] = [
        NotificationPreference(id: "workout_reminder", title: "Workout Reminders", subtitle: "Stay on track with your programs", icon: "dumbbell.fill", color: "purple", isEnabled: true, frequency: .daily),
        NotificationPreference(id: "hydration", title: "Hydration", subtitle: "Remember to drink water", icon: "drop.fill", color: "cyan", isEnabled: true, frequency: .twiceDaily),
        NotificationPreference(id: "step_goal", title: "Step Goals", subtitle: "Get motivated to hit your target", icon: "figure.walk", color: "green", isEnabled: true, frequency: .daily),
        NotificationPreference(id: "sleep_reminder", title: "Bedtime Reminder", subtitle: "Wind down for better sleep", icon: "moon.fill", color: "indigo", isEnabled: false, frequency: .daily),
        NotificationPreference(id: "checkin", title: "Daily Check-In", subtitle: "Keep your streak going", icon: "checkmark.circle.fill", color: "orange", isEnabled: true, frequency: .daily),
        NotificationPreference(id: "mindfulness", title: "Mindfulness", subtitle: "Take a moment to breathe", icon: "brain.head.profile.fill", color: "teal", isEnabled: false, frequency: .daily),
        NotificationPreference(id: "weekly_summary", title: "Weekly Summary", subtitle: "Review your progress", icon: "chart.bar.fill", color: "blue", isEnabled: true, frequency: .weekly),
        NotificationPreference(id: "beach_bonanza", title: "Beach Bonanza", subtitle: "Event updates & motivation", icon: "beach.umbrella.fill", color: "orange", isEnabled: true, frequency: .daily),
        NotificationPreference(id: "contextual_health", title: "Smart Health Alerts", subtitle: "HRV drops, recovery tips, training readiness", icon: "heart.text.clipboard.fill", color: "pink", isEnabled: true, frequency: .daily),
    ]

    func requestAuthorization() async {
        do {
            let options: UNAuthorizationOptions = [.alert, .badge, .sound, .providesAppNotificationSettings, .timeSensitive]
            let granted = try await center.requestAuthorization(options: options)
            isAuthorized = granted
            registerCategories()
        } catch {
            isAuthorized = false
        }
    }

    /// Registers all notification categories with their action buttons.
    /// Categories must be registered on every launch so the system can
    /// render action buttons + route taps back through the AppDelegate.
    func registerCategories() {
        let openAction = UNNotificationAction(identifier: "OPEN_APP", title: "Open", options: [.foreground])
        let snoozeAction = UNNotificationAction(identifier: "SNOOZE", title: "Remind in 1 hour", options: [])
        let dismissAction = UNNotificationAction(identifier: "DISMISS", title: "Dismiss", options: [.destructive])
        let logWaterAction = UNNotificationAction(identifier: "LOG_WATER", title: "Log a Glass", options: [.foreground])
        let startWorkoutAction = UNNotificationAction(identifier: "START_WORKOUT", title: "Start Workout", options: [.foreground])
        let logCheckInAction = UNNotificationAction(identifier: "CHECK_IN", title: "Check In", options: [.foreground])
        let viewSummaryAction = UNNotificationAction(identifier: "VIEW_SUMMARY", title: "View Summary", options: [.foreground])
        let beachJoinAction = UNNotificationAction(identifier: "OPEN_BEACH", title: "Open Bonanza", options: [.foreground])

        let home = UNNotificationCategory(identifier: "DEEPLINK_HOME", actions: [openAction, snoozeAction, dismissAction], intentIdentifiers: [], hiddenPreviewsBodyPlaceholder: "A new Whisper update", categorySummaryFormat: "%u Whisper updates today", options: [.customDismissAction])

        let workouts = UNNotificationCategory(identifier: "DEEPLINK_WORKOUTS", actions: [startWorkoutAction, snoozeAction, dismissAction], intentIdentifiers: [], hiddenPreviewsBodyPlaceholder: "Time to train", categorySummaryFormat: "%u workout reminders", options: [.customDismissAction])

        let wellness = UNNotificationCategory(identifier: "DEEPLINK_WELLNESS", actions: [openAction, snoozeAction, dismissAction], intentIdentifiers: [], hiddenPreviewsBodyPlaceholder: "Wellness reminder", categorySummaryFormat: "%u wellness reminders", options: [.customDismissAction])

        let nutrition = UNNotificationCategory(identifier: "DEEPLINK_NUTRITION", actions: [logWaterAction, snoozeAction, dismissAction], intentIdentifiers: [], hiddenPreviewsBodyPlaceholder: "Nutrition reminder", categorySummaryFormat: "%u nutrition reminders", options: [.customDismissAction])

        let checkin = UNNotificationCategory(identifier: "DEEPLINK_CHECKIN", actions: [logCheckInAction, snoozeAction, dismissAction], intentIdentifiers: [], hiddenPreviewsBodyPlaceholder: "Daily check-in", categorySummaryFormat: "%u check-ins waiting", options: [.customDismissAction])

        let weekly = UNNotificationCategory(identifier: "DEEPLINK_WEEKLY", actions: [viewSummaryAction, dismissAction], intentIdentifiers: [], hiddenPreviewsBodyPlaceholder: "Weekly summary", categorySummaryFormat: "%u summaries ready", options: [.customDismissAction])

        let beach = UNNotificationCategory(identifier: "DEEPLINK_BEACH_BONANZA", actions: [beachJoinAction, snoozeAction, dismissAction], intentIdentifiers: [], hiddenPreviewsBodyPlaceholder: "Beach Bonanza", categorySummaryFormat: "%u Beach Bonanza updates", options: [.customDismissAction])

        let smart = UNNotificationCategory(identifier: "SMART_NOTIFICATION", actions: [openAction, snoozeAction, dismissAction], intentIdentifiers: [], hiddenPreviewsBodyPlaceholder: "Smart insight", categorySummaryFormat: "%u smart insights", options: [.customDismissAction])

        let ember = UNNotificationCategory(identifier: "DEEPLINK_EMBER", actions: [openAction, snoozeAction, dismissAction], intentIdentifiers: [], hiddenPreviewsBodyPlaceholder: "Jasper", categorySummaryFormat: "%u Jasper updates", options: [.customDismissAction])

        // Union with the Whisper set — setNotificationCategories REPLACES
        // the registered categories, and losing WHISPER_CALL would strip
        // the Answer/Decline buttons off incoming-call banners.
        let legacy: Set<UNNotificationCategory> = [home, workouts, wellness, nutrition, checkin, weekly, beach, smart, ember]
        center.setNotificationCategories(legacy.union(WhisperNotificationCategories.all))
    }

    /// Reschedules a notification 1 hour from now (used by Snooze action).
    func snooze(identifier: String, title: String, body: String, categoryIdentifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.threadIdentifier = categoryIdentifier
        content.interruptionLevel = .active
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60 * 60, repeats: false)
        let req = UNNotificationRequest(identifier: "\(identifier)_snoozed_\(Int(Date().timeIntervalSince1970))", content: content, trigger: trigger)
        center.add(req)
    }

    func checkAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    func completeSetup() {
        AccountStorage.set(true, forKey: "notificationSetupComplete")
        savePreferences()
        scheduleAllNotifications()
    }

    func ensureNotificationsScheduled() {
        Task {
            await checkAuthorizationStatus()
            guard isAuthorized else { return }
            loadPreferences()
            let pending = await center.pendingNotificationRequests()
            if pending.isEmpty && hasCompletedSetup {
                scheduleAllNotifications()
            }
        }
    }

    func savePreferences() {
        var dict: [String: [String: Any]] = [:]
        for pref in preferences {
            dict[pref.id] = [
                "enabled": pref.isEnabled,
                "frequency": pref.frequency.rawValue,
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            AccountStorage.set(data, forKey: "notificationPreferences")
        }
    }

    func loadPreferences() {
        guard let data = AccountStorage.data(forKey: "notificationPreferences"),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return }

        for i in preferences.indices {
            if let prefData = dict[preferences[i].id] {
                preferences[i].isEnabled = prefData["enabled"] as? Bool ?? false
                if let freqStr = prefData["frequency"] as? String,
                   let freq = NotificationFrequency(rawValue: freqStr) {
                    preferences[i].frequency = freq
                }
            }
        }
    }

    func scheduleAllNotifications() {
        // Rescheduling preferences must not erase explicit Knot reminders,
        // Calendar reminders or unrelated account-owned requests.
        let identifiers = preferences.flatMap { preference in
            [preference.id, "\(preference.id)_morning", "\(preference.id)_evening"]
            + (0...2).map { "\(preference.id)_\($0)" }
            + stride(from: 8, through: 22, by: 2).map { "\(preference.id)_h\($0)" }
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        for pref in preferences where pref.isEnabled {
            scheduleNotification(for: pref)
        }

    }

    private func scheduleNotification(for pref: NotificationPreference) {
        let messages = notificationMessages(for: pref.id)
        guard !messages.isEmpty else { return }

        switch pref.frequency {
        case .everyTwoHours:
            for hour in stride(from: 8, through: 22, by: 2) {
                scheduleDailyNotification(id: "\(pref.id)_h\(hour)", title: pref.title, messages: messages, hour: hour)
            }
        case .daily:
            scheduleDailyNotification(id: pref.id, title: pref.title, messages: messages, hour: notificationHour(for: pref.id))
        case .twiceDaily:
            scheduleDailyNotification(id: "\(pref.id)_morning", title: pref.title, messages: messages, hour: 9)
            scheduleDailyNotification(id: "\(pref.id)_evening", title: pref.title, messages: messages, hour: 15)
        case .weekly:
            scheduleWeeklyNotification(id: pref.id, title: pref.title, messages: messages, weekday: 2, hour: 9)
        case .threeTimesWeek:
            for (i, day) in [2, 4, 6].enumerated() {
                scheduleWeeklyNotification(id: "\(pref.id)_\(i)", title: pref.title, messages: messages, weekday: day, hour: notificationHour(for: pref.id))
            }
        }
    }

    private func scheduleDailyNotification(id: String, title: String, messages: [String], hour: Int, deepLink: String? = nil) {
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = 0

        let category = deepLink ?? deepLinkCategory(for: id)
        let content = makeContent(title: title, body: messages.randomElement() ?? "", category: category, threadId: category, baseId: id)

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request)
    }

    private func scheduleWeeklyNotification(id: String, title: String, messages: [String], weekday: Int, hour: Int, deepLink: String? = nil) {
        var dateComponents = DateComponents()
        dateComponents.weekday = weekday
        dateComponents.hour = hour

        let category = deepLink ?? deepLinkCategory(for: id)
        let content = makeContent(title: title, body: messages.randomElement() ?? "", category: category, threadId: category, baseId: id)

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request)
    }

    /// Builds an adaptive notification: thread grouping, interruption level,
    /// relevance score, summary argument, and a clean subtitle.
    private func makeContent(title: String, body: String, category: String, threadId: String, baseId: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        content.threadIdentifier = threadId
        content.summaryArgument = title
        content.targetContentIdentifier = category
        content.userInfo = ["deepLink": category, "id": baseId]

        switch baseId {
        case let s where s.contains("workout"):
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 0.9
        case let s where s.contains("sleep"):
            content.interruptionLevel = .active
            content.relevanceScore = 0.7
        case let s where s.contains("checkin"):
            content.interruptionLevel = .active
            content.relevanceScore = 0.6
        case let s where s.contains("hydration"):
            content.interruptionLevel = .passive
            content.relevanceScore = 0.4
        case let s where s.contains("weekly"):
            content.interruptionLevel = .active
            content.relevanceScore = 0.5
        default:
            content.interruptionLevel = .active
            content.relevanceScore = 0.5
        }
        return content
    }

    private func deepLinkCategory(for id: String) -> String {
        var baseId = id
        if let range = baseId.range(of: "_h[0-9]", options: .regularExpression) {
            baseId = String(baseId[baseId.startIndex..<range.lowerBound])
        }
        baseId = baseId.replacingOccurrences(of: "_morning", with: "")
        baseId = baseId.replacingOccurrences(of: "_evening", with: "")
        for suffix in ["_0", "_1", "_2"] {
            if baseId.hasSuffix(suffix) {
                baseId = String(baseId.dropLast(suffix.count))
            }
        }
        switch baseId {
        case "workout_reminder": return "DEEPLINK_WORKOUTS"
        case "hydration": return "DEEPLINK_NUTRITION"
        case "step_goal": return "DEEPLINK_HOME"
        case "sleep_reminder": return "DEEPLINK_WELLNESS"
        case "checkin": return "DEEPLINK_HOME"
        case "mindfulness": return "DEEPLINK_WELLNESS"
        case "weekly_summary": return "DEEPLINK_HOME"
        case "beach_bonanza": return "DEEPLINK_BEACH_BONANZA"
        default: return "DEEPLINK_HOME"
        }
    }

    private func notificationHour(for id: String) -> Int {
        switch id {
        case "workout_reminder": return 8
        case "hydration": return 10
        case "step_goal": return 14
        case "sleep_reminder": return 21
        case "checkin": return 9
        case "mindfulness": return 12
        case "weekly_summary": return 9
        case "beach_bonanza": return 8
        default: return 9
        }
    }

    private func notificationMessages(for id: String) -> [String] {
        switch id {
        case "workout_reminder":
            return [
                "Time to crush your workout! Your body will thank you.",
                "Your workout program is waiting. Let's build strength today!",
                "Consistency is key — get your session in today.",
            ]
        case "hydration":
            return [
                "Stay hydrated! Grab a glass of water.",
                "Water break! Your muscles need hydration to recover.",
                "Don't forget to drink water — your body needs it.",
            ]
        case "step_goal":
            return [
                "How are your steps looking? Get moving!",
                "A short walk can boost your energy and mood.",
                "Every step counts — keep pushing towards your goal.",
            ]
        case "sleep_reminder":
            return [
                "Time to start winding down for better sleep tonight.",
                "Put down the phone and relax — your sleep score depends on it.",
                "Good sleep = better recovery. Start your bedtime routine.",
            ]
        case "checkin":
            return [
                "Don't break your streak! Tap to check in today.",
                "Your daily check-in is waiting. Keep the momentum!",
                "Check in now to extend your streak!",
            ]
        case "mindfulness":
            return [
                "Take 5 minutes to breathe and reset.",
                "A moment of calm can transform your day.",
                "Time for a breathing exercise — your mind will thank you.",
            ]
        case "weekly_summary":
            return [
                "Your weekly health summary is ready. See how you did!",
                "Week in review — check your progress in Whisper.",
            ]
        case "beach_bonanza":
            return [
                "Your Beach Bonanza journey awaits! Check your challenges 🏖️",
                "Beach Bonanza update — see how you're doing! ☀️",
                "Time to crush a beach workout! 🌊",
            ]
        case "contextual_health":
            return [
                "Your body's recovery signals look great — today's a prime day for a hard workout!",
                "Take it easy today — your recovery metrics suggest lighter activity.",
                "Great sleep last night! You're primed for a solid training session.",
                "Your HRV trend is improving — keep up the consistency!",
                "Don't forget to hydrate — it impacts your recovery and performance.",
            ]
        default:
            return []
        }
    }

    func scheduleContextualNotification(title: String, body: String, delay: TimeInterval = 5) {
        let category = "DEEPLINK_WELLNESS"
        let content = makeContent(title: title, body: body, category: category, threadId: category, baseId: "contextual")

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delay, 1), repeats: false)
        let request = UNNotificationRequest(identifier: "contextual_\(UUID().uuidString.prefix(8))", content: content, trigger: trigger)
        center.add(request)
    }

    /// Fires a one-shot test notification for every routable category. Used by the
    /// simulator overlay so the team can validate that every tap path opens the
    /// correct screen without crashing.
    func fireTestNotificationsForAllCategories() {
        Task {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                await requestAuthorization()
            }
            let cases: [(id: String, title: String, body: String, category: String, delay: TimeInterval)] = [
                ("test_home", "Test → Home", "Should land on the Home tab", "DEEPLINK_HOME", 3),
                ("test_workouts", "Test → Workouts", "Should land on the Workouts tab", "DEEPLINK_WORKOUTS", 6),
                ("test_wellness", "Test → Wellness", "Should land on the Wellness tab", "DEEPLINK_WELLNESS", 9),
                ("test_nutrition", "Test → Nutrition", "Should land on the Nutrition tab", "DEEPLINK_NUTRITION", 12),
                ("test_checkin", "Test → Check-In", "Should open Home + check-in banner", "DEEPLINK_CHECKIN", 15),
                ("test_weekly", "Test → Weekly Summary", "Should open weekly digest", "DEEPLINK_WEEKLY", 18),
                ("test_beach", "Test → Beach Bonanza", "Should open Beach Bonanza", "DEEPLINK_BEACH_BONANZA", 21),
                ("test_ember", "Test → Jasper", "Should open Jasper assistant", "DEEPLINK_EMBER", 24),
                ("test_smart_workout", "Test → Smart (workout)", "Routes via SMART_NOTIFICATION", "SMART_NOTIFICATION", 27),
            ]
            for c in cases {
                let content = UNMutableNotificationContent()
                content.title = c.title
                content.body = c.body
                content.sound = .default
                content.categoryIdentifier = c.category
                content.userInfo = ["deepLink": c.category, "id": c.id]
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: c.delay, repeats: false)
                let req = UNNotificationRequest(identifier: c.id, content: content, trigger: trigger)
                try? await center.add(req)
            }
        }
    }
}
