import Foundation
import UserNotifications

/// Schedules a calendar-trigger local notification every day at 8pm that
/// nudges the user about remaining calories + missing workouts. Tap the
/// notification to deep-link straight into Jasper with a pre-baked prompt.
nonisolated enum EmberStreakNudgeService {
    static let identifier = "ember-streak-nudge-evening"
    static let categoryID = "DEEPLINK_EMBER_NUDGE"

    /// Schedules (or reschedules) the recurring 8pm reminder. Idempotent —
    /// safe to call from app launch.
    static func scheduleEveningNudge() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        // Clear the existing copy so we don't stack duplicates.
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let snapshot = await snapshotForBody()
        let content = UNMutableNotificationContent()
        content.title = "Jasper"
        content.body = snapshot
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.userInfo = [
            "deepLink": "DEEPLINK_EMBER",
            "prompt": "I have \(snapshot). Suggest a 15-minute finisher to hit my goals."
        ]
        var date = DateComponents()
        date.hour = 20
        date.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let req = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(req)
    }

    @MainActor
    private static func snapshotForBody() async -> String {
        let store = NutritionStore.shared
        let remaining = max(0, store.goals.calories - store.totalCalories)
        if remaining == 0 {
            return "You hit your calorie goal — want a quick finisher to lock the streak in?"
        }
        return "\(remaining) cal from goal and 0 workouts logged — want a 15-min finisher?"
    }
}
