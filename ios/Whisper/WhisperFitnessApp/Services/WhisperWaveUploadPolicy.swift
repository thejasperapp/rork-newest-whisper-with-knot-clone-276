import Foundation

/// The deployed public-media bucket permits 50 MiB. Leave headroom for
/// variable bitrate and MP4 overhead; never shorten footage to fit bytes.
nonisolated enum WhisperWaveUploadPolicy {
    static let maximumDuration: Double = 360
    static let maximumBytes: Int = 50 * 1024 * 1024
    static let targetBytes: Int = 44 * 1024 * 1024
    static let audioBitRate: Int = 96_000
    static let durationTolerance: Double = 0.1

    static func accepts(duration: Double) -> Bool {
        duration.isFinite && duration > 0 && duration <= maximumDuration + durationTolerance
    }

    static func videoBitRate(duration: Double, hasAudio: Bool) -> Int {
        guard accepts(duration: duration) else { return 0 }
        let audio = hasAudio ? audioBitRate : 0
        return min(6_000_000, max(100_000, Int(Double(targetBytes) * 8 / duration) - audio))
    }
}
