import Foundation

/// Capture-queue-only, phase-preserving throttle. A 30 fps source must not become 15 fps.
nonisolated struct WhisperCameraFrameCadence {
    private var nextDeadline: Double?
    private var previousTime: Double?
    let framesPerSecond: Double = 24

    mutating func admits(_ time: Double) -> Bool {
        guard time.isFinite else { return false }
        let interval = 1 / framesPerSecond
        if let previousTime, time < previousTime || time - previousTime > 0.5 { nextDeadline = nil }
        previousTime = time
        guard let deadline = nextDeadline else { nextDeadline = time + interval; return true }
        guard time + 0.000001 >= deadline else { return false }
        let skipped = floor(max(0, time - deadline + 0.000001) / interval)
        nextDeadline = deadline + (skipped + 1) * interval
        return true
    }
}
