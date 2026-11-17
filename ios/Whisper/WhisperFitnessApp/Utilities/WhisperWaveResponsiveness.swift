import Foundation
import OSLog

/// Samples main-actor scheduling delay around Wave returns without logging media or account data.
nonisolated enum WhisperWaveResponsiveness {
    static func sampleReturn() {
        Task.detached(priority: .utility) {
            let clock = ContinuousClock()
            var maximum: Double = 0
            for _ in 0..<16 {
                do { try await Task.sleep(for: .milliseconds(125)) } catch { return }
                let scheduled = clock.now
                let serviced = await MainActor.run { clock.now }
                let elapsed = scheduled.duration(to: serviced).components
                maximum = max(maximum, Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
            }
            Logger(subsystem: "Whisper", category: "WaveReturn").info("Main-actor maximum scheduling delay after Wave return: \(maximum, privacy: .public) ms")
        }
    }
}
