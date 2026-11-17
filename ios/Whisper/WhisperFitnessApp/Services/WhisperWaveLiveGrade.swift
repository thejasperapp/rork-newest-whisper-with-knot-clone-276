import Foundation

/// Preview-only overrides for the look, adjustments and effect. Turning a dial
/// in the editor updates this snapshot and asks the player to redraw its
/// current frame, instead of rebuilding the whole composition and swapping
/// the player item on every tick. The final encode and cover never read it —
/// they use the values frozen into their own instructions.
nonisolated final class WhisperWaveLiveGrade: @unchecked Sendable {
    static let shared = WhisperWaveLiveGrade()

    /// Where and how large the captions draw — the Captions rulers move
    /// these live without re-rasterizing a single word.
    nonisolated struct CaptionLayout: Sendable, Equatable {
        let y: Double
        let scale: Double
    }

    nonisolated struct Snapshot: Sendable {
        let filter: SnapFilter
        let adjustments: WhisperWaveColorAdjustments
        let fx: WhisperWaveFXSetting?
        var captionLayout: CaptionLayout? = nil
    }

    private let lock = NSLock()
    private var current: Snapshot?

    private init() {}

    var override: Snapshot? {
        get { lock.lock(); defer { lock.unlock() }; return current }
        set { lock.lock(); current = newValue; lock.unlock() }
    }
}
