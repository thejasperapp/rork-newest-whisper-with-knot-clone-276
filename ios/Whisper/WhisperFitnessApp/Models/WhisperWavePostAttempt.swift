import Foundation
import Observation

/// Per-composer outcome: only an insert whose response is uncertain locks editing.
@MainActor @Observable final class WhisperWavePostAttempt {
    enum Phase { case preparing, submitting, rejected, published }
    var phase: Phase = .preparing
    var message: String?
    var needsReconciliation: Bool { phase == .submitting }
}
