import SwiftUI
import CoreImage

/// The creation host owns one preview; Waves only supplies its current recipe.
@Observable
final class WhisperCapturePreviewBridge {
    var configuration: WhisperWaveLiveFrameRenderer.Configuration = .init()
    var photo: CIImage?
    var video: WhisperWaveLiveVideoBackground?
    var preparedURL: URL?
    var issue: String?
    var suspended: Bool = false
    var browsing: Bool = false
    var modeLocked: Bool = true
    var hidesModeStrip: Bool = false
    let thumbnails: WhisperWaveEffectThumbnails = .init()
}
