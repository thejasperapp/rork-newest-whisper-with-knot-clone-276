import UIKit
import SwiftUI

/// Centralised haptic helpers so feedback is consistent across the app.
/// Usage: `Haptics.tap()`, `Haptics.success()`, `Haptics.selection()`
@MainActor
enum Haptics {
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private static let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private static let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private static let selectionFB = UISelectionFeedbackGenerator()
    private static let notificationFB = UINotificationFeedbackGenerator()

    static func prepareAll() {
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
        softImpact.prepare()
        rigidImpact.prepare()
        selectionFB.prepare()
        notificationFB.prepare()
    }

    /// Subtle tap — use for routine button presses.
    static func tap() { lightImpact.impactOccurred() }

    /// Medium press — use for primary CTAs and confirmations.
    static func press() { mediumImpact.impactOccurred() }

    /// Heavy thunk — use for major state changes (workout complete, etc).
    static func thud() { heavyImpact.impactOccurred(intensity: 1.0) }

    /// Soft, muted bump — use for swipes and gentle transitions.
    static func soft() { softImpact.impactOccurred() }

    /// Crisp rigid tap — use for toggles and chip selection.
    static func rigid() { rigidImpact.impactOccurred() }

    /// Selection change — use when scrolling through pickers / segments.
    static func selection() { selectionFB.selectionChanged() }

    /// Success notification.
    static func success() { notificationFB.notificationOccurred(.success) }

    /// Warning notification.
    static func warning() { notificationFB.notificationOccurred(.warning) }

    /// Error notification.
    static func error() { notificationFB.notificationOccurred(.error) }
}
