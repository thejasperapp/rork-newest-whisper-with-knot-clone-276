import SwiftUI
import Observation

/// App-wide Whisper appearance preferences. Currently a single switch:
/// **Pitch Black** — swaps the dark-mode indigo surfaces for true black
/// (OLED-friendly, higher contrast). Views never read this directly;
/// `WhisperTheme.surface/card/hairline` consult it, so flipping the toggle
/// re-renders every screen that draws themed surfaces.
@Observable
final class WhisperAppearance {
    static let shared = WhisperAppearance()

    private static let pitchBlackKey = "whisper.pitchBlack"

    /// True black dark mode. Only affects `.dark` color scheme surfaces.
    var pitchBlack: Bool {
        didSet { UserDefaults.standard.set(pitchBlack, forKey: Self.pitchBlackKey) }
    }

    private init() {
        pitchBlack = UserDefaults.standard.bool(forKey: Self.pitchBlackKey)
    }
}
