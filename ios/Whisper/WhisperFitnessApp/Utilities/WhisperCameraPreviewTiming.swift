import Foundation

/// Frame metadata is not observable: capture reads it without redrawing SwiftUI every frame.
@MainActor final class WhisperCameraPreviewTiming {
    var elapsed: Double = 0
}
