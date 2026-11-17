import Foundation
import BackgroundTasks
import UserNotifications

/// Pre-computes a short daily coaching plan at 6am via BGTaskScheduler and surfaces it as a
/// local notification so Jasper feels proactive — not just reactive.
nonisolated struct EmberDailyPlanService: Sendable {
    static let taskIdentifier = "app.rork.jasper.ember.dailyplan"

    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        // 6am tomorrow
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 6
        components.minute = 0
        var target = calendar.date(from: components) ?? now.addingTimeInterval(3600)
        if target <= now {
            target = calendar.date(byAdding: .day, value: 1, to: target) ?? target.addingTimeInterval(86400)
        }
        request.earliestBeginDate = target
        try? BGTaskScheduler.shared.submit(request)
    }

    static func runDailyPlanGeneration() async {
        let summary = await fetchSnapshot()
        let plan = composePlan(summary: summary)
        await postNotification(plan: plan)
        scheduleNext()
    }

    private static func composePlan(summary: String) -> String {
        // Lightweight, deterministic plan — no network needed for the BG path.
        return "Today's focus: \(summary). Tap to open your plan."
    }

    @MainActor
    private static func fetchSnapshot() async -> String {
        let shared = UserDefaults(suiteName: "group.com.mydailywhisper.whisper")
        let steps = shared?.integer(forKey: "widget_steps") ?? 0
        let readiness = shared?.integer(forKey: "widget_readinessScore") ?? 0
        let sleep = shared?.double(forKey: "widget_sleepHours") ?? 0
        if readiness > 0 && readiness < 50 {
            return "recovery first — readiness \(readiness)/100, sleep \(String(format: "%.1f", sleep))h"
        }
        if sleep > 0 && sleep < 6 {
            return "easy effort + mobility — only slept \(String(format: "%.1f", sleep))h"
        }
        return "primed to train — \(steps) steps yesterday, readiness \(readiness)/100"
    }

    private static func postNotification(plan: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "Jasper's plan for today"
        content.body = plan
        content.sound = .default
        content.categoryIdentifier = "DEEPLINK_EMBER"
        content.userInfo = ["deepLink": "DEEPLINK_EMBER"]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let req = UNNotificationRequest(identifier: "ember-daily-plan-\(Int(Date().timeIntervalSince1970))", content: content, trigger: trigger)
        try? await center.add(req)
    }
}
