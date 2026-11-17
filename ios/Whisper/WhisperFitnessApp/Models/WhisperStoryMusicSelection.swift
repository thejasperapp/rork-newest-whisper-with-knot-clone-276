import Foundation

/// Offsets refer to the available preview asset, never the full catalog track.
nonisolated struct WhisperStoryMusicSelection: Codable, Sendable, Hashable {
    let startSeconds: Double
    let durationSeconds: Double

    init(startSeconds: Double, durationSeconds: Double, availableDuration: Double = 30) {
        let available = availableDuration.isFinite ? min(600, max(0.5, availableDuration)) : 30
        let duration = durationSeconds.isFinite ? durationSeconds : 7
        self.durationSeconds = min(available, max(min(3, available), min(30, duration)))
        self.startSeconds = min(max(0, startSeconds.isFinite ? startSeconds : 0), available - self.durationSeconds)
    }
}
