import AVFoundation
import CoreImage

/// Immutable instructions retain the existing track transforms and transition ramps.
nonisolated final class WhisperWaveVideoInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let base: AVVideoCompositionInstruction
    let filter: SnapFilter
    let adjustments: WhisperWaveColorAdjustments
    let effect: WhisperAREffect
    /// The wave effect, if any, and the seconds it covers (nil = whole wave).
    let fx: WhisperWaveFXSetting?
    let fxWindow: ClosedRange<Double>?
    let quality: WhisperWaveRenderQuality
    let textFrames: [WhisperWaveTextFrame]
    /// Caption phrases, ascending by start, plus the layout they were baked for.
    let captionFrames: [WhisperWaveCaptionFrame]
    let captionY: Double
    let captionScale: Double
    let canvas: CGSize
    let subjects: [WhisperWaveSubjectFrame]
    var timeRange: CMTimeRange { base.timeRange }
    var enablePostProcessing: Bool { true }
    var containsTweening: Bool { true }
    var requiredSourceTrackIDs: [NSValue]? {
        let ids = base.layerInstructions.map(\.trackID) + subjects.compactMap(\.backgroundTrackID)
        return Array(Set(ids)).map { NSNumber(value: $0) }
    }
    var passthroughTrackID: CMPersistentTrackID { kCMPersistentTrackID_Invalid }

    init(base: AVVideoCompositionInstruction, filter: SnapFilter, adjustments: WhisperWaveColorAdjustments, effect: WhisperAREffect, fx: WhisperWaveFXSetting? = nil, fxWindow: ClosedRange<Double>? = nil, quality: WhisperWaveRenderQuality = .final, textFrames: [WhisperWaveTextFrame], captionFrames: [WhisperWaveCaptionFrame] = [], captionY: Double = 0.74, captionScale: Double = 1, canvas: CGSize, subjects: [WhisperWaveSubjectFrame] = []) {
        self.base = base
        self.filter = filter
        self.adjustments = adjustments
        self.effect = effect
        self.fx = fx
        self.fxWindow = fxWindow
        self.quality = quality
        self.textFrames = textFrames
        self.captionFrames = captionFrames
        self.captionY = captionY
        self.captionScale = captionScale
        self.canvas = canvas
        self.subjects = subjects
        super.init()
    }

    /// The effect to draw at `seconds`, honoring a per-clip window.
    func activeFX(at seconds: Double) -> WhisperWaveFXSetting? {
        guard let fx else { return nil }
        if let fxWindow, !fxWindow.contains(seconds) { return nil }
        return fx
    }
}
