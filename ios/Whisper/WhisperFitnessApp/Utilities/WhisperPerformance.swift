import Foundation
import os

/// Local Instruments intervals only: no URLs, identities, captions or telemetry.
nonisolated enum WhisperPerformance {
    static let signposter = OSSignposter(subsystem: "app.whisper.performance", category: "FeedAndImages")
    static let logger = Logger(subsystem: "app.whisper.performance", category: "ResourceBudgets")

    @MainActor private static var waveItems = 0
    @MainActor static func waveItemChanged(by delta: Int) {
        waveItems = max(0, waveItems + delta)
        logger.debug("Resident Waves items=\(waveItems)")
    }

    /// Unique IDs distinguish overlapping screens; abandoned work is not a successful readiness sample.
    final class Span: @unchecked Sendable {
        private let lock = NSLock()
        private let name: StaticString
        private let state: OSSignpostIntervalState
        private var ended = false

        init(_ name: StaticString) {
            self.name = name
            state = signposter.beginInterval(name, id: signposter.makeSignpostID())
        }

        func finish(completed: Bool = false) {
            lock.withLock {
                guard !ended else { return }
                ended = true
                signposter.endInterval(name, state, "completed=\(completed)")
            }
        }
        deinit { finish() }
    }
}
