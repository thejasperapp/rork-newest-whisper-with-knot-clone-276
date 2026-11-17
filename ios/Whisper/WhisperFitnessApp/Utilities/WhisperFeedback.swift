import UIKit

/// One vocabulary for "something just happened" across the app: each moment
/// pairs a haptic with the matching synthesized bell so likes, sends,
/// arrivals, refreshes and failures all feel like the same instrument.
/// Sounds ride AudioToolbox system sounds so they honor the ringer switch.
@MainActor
enum WhisperFeedback {
    /// A like landed — soft impact plus the two-note pop.
    static func liked() {
        Haptics.tap()
        WhisperMeetChime.playLike()
    }

    /// A like was taken back — a muted bump, no sound.
    static func unliked() {
        Haptics.soft()
    }

    /// A message, comment or reply left the device successfully.
    static func sent() {
        Haptics.success()
        WhisperMeetChime.playSend()
    }

    /// A new message arrived while the app is in front.
    static func received() {
        Haptics.soft()
        WhisperMeetChime.playReceive()
    }

    /// A post, wave or story went live.
    static func published() {
        Haptics.success()
        WhisperMeetChime.playPublished()
    }

    /// Something the user asked for could not be completed.
    static func failed() {
        Haptics.error()
        WhisperMeetChime.playError()
    }

    /// A pull-to-refresh finished fetching from the server.
    static func refreshed() {
        Haptics.soft()
        WhisperMeetChime.playTickQuiet()
    }

    /// A full-screen page turned (waves, stories).
    static func pageTurned() {
        Haptics.soft()
    }

    /// The user now follows someone.
    static func followed() {
        Haptics.success()
        WhisperMeetChime.playTickQuiet()
    }

    /// The app finished warming up and the splash lifted.
    static func ready() {
        Haptics.soft()
    }
}
