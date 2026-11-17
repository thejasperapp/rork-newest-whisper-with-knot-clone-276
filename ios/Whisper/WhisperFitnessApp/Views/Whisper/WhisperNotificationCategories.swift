import Foundation
import UserNotifications

/// Single source of truth for every notification category Whisper
/// registers. `setNotificationCategories` REPLACES the whole set, so all
/// call sites must include this set — otherwise the last caller silently
/// wipes the Answer/Decline buttons off incoming-call banners.
nonisolated enum WhisperNotificationCategories {
    static let answerCallAction = "ANSWER_CALL"
    static let declineCallAction = "DECLINE_CALL"

    static var all: Set<UNNotificationCategory> {
        // Incoming-call banner (the alert-push fallback path — CallKit
        // shows its own native Answer/Decline when a VoIP token exists).
        let answer = UNNotificationAction(
            identifier: answerCallAction,
            title: "Answer",
            options: [.foreground]
        )
        let decline = UNNotificationAction(
            identifier: declineCallAction,
            title: "Decline",
            options: [.destructive]
        )
        let call = UNNotificationCategory(
            identifier: "WHISPER_CALL",
            actions: [answer, decline],
            intentIdentifiers: [],
            options: []
        )
        let missed = UNNotificationCategory(
            identifier: "WHISPER_CALL_MISSED",
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        return [call, missed]
    }

    static func register() {
        UNUserNotificationCenter.current().setNotificationCategories(all)
    }
}
