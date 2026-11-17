import Foundation
import UserNotifications

/// One-time cleanup that removes every locally-scheduled notification left
/// over from the old Whisper fitness app (workout reminders, hydration nudges,
/// step goals, Jasper daily plan, evening streak nudges, etc).
///
/// Whisper is a social app — none of those reminders are relevant anymore.
/// The cleanup runs exactly once per install and also nukes the legacy
/// notification categories so action buttons like "Log a Glass" / "Start
/// Workout" never appear again.
nonisolated enum WhisperLegacyNotificationCleanup {
    private static let runKey = "whisper.legacy.notifs.cleared.v1"

    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: runKey) else { return }

        let center = UNUserNotificationCenter.current()

        // Wipe every pending local request. Whisper does not rely on any
        // recurring local schedule — all of its banners are fired ad-hoc by
        // WhisperNotificationService in response to live events.
        center.removeAllPendingNotificationRequests()

        // Also clear any delivered legacy banners from Notification Center so
        // users don't tap a stale "Time to crush your workout" reminder on
        // first launch after the update.
        center.removeAllDeliveredNotifications()

        // Drop the legacy categories but keep Whisper's own set — wiping to
        // [] would also remove the Answer/Decline actions from call banners.
        center.setNotificationCategories(WhisperNotificationCategories.all)

        defaults.set(true, forKey: runKey)
    }
}
