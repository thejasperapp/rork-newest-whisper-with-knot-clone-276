import Foundation

/// A private device draft retains source clips and edits, without requiring an export or network access.
nonisolated struct WhisperWaveEditDraft: Codable, Sendable {
    let owner: String
    var clips: [WhisperWaveClip]
    let caption: String
    let music: WhisperStoryMusic?
    let volume: Double
    let muted: Bool
    let texts: [WaveTextOverlay]
    let filterName: String
    let effect: String
    let audience: String
    let ghost: Bool
    let shareToFeed: Bool
    let publicationID: String
    var publicationPending: Bool? = nil
    var adjustments: WhisperWaveColorAdjustments? = nil
    var allowComments: Bool? = nil
    var allowSaves: Bool? = nil
    var coverTime: Double? = nil
    var fx: WhisperWaveFXSetting? = nil
    var captions: WhisperWaveCaptions? = nil
}
