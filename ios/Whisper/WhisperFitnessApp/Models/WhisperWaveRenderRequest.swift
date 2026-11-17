import Foundation

/// The complete render identity. Caption and cover time do not invalidate the encoded video.
nonisolated struct WhisperWaveRenderRequest: Equatable, Sendable {
    let clips: [WhisperWaveClip]
    let music: WhisperStoryMusic?
    let volume: Double
    let muted: Bool
    let texts: [WaveTextOverlay]
    let filter: SnapFilter
    let effect: WhisperAREffect
    let adjustments: WhisperWaveColorAdjustments
    var fx: WhisperWaveFXSetting? = nil
    var captions: WhisperWaveCaptions? = nil
}
