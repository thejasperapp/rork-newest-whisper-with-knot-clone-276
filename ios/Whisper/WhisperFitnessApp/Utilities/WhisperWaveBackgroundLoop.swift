import AVFoundation

/// Gap-free, rational-time loops; short tails are retained instead of clamped like audio previews.
nonisolated enum WhisperWaveBackgroundLoop {
    struct Segment: Sendable {
        let source: CMTimeRange
        let destination: CMTime
    }
    static func segments(available: CMTimeRange, offset: Double, output: CMTimeRange) -> [Segment] {
        guard available.duration.isNumeric, available.duration.seconds > 0.1, output.duration.isNumeric, output.duration.seconds > 0 else { return [] }
        let seconds = (offset.isFinite ? max(0, offset) : 0).truncatingRemainder(dividingBy: available.duration.seconds)
        var local = CMTime(seconds: seconds, preferredTimescale: max(60_000, available.duration.timescale))
        if local >= available.duration { local = .zero }
        var cursor = output.start
        var result: [Segment] = []
        while cursor < output.end {
            let length = CMTimeMinimum(CMTimeSubtract(available.duration, local), CMTimeSubtract(output.end, cursor))
            guard length > .zero else { break }
            result.append(Segment(source: CMTimeRange(start: CMTimeAdd(available.start, local), duration: length), destination: cursor))
            cursor = CMTimeAdd(cursor, length)
            local = .zero
        }
        return result
    }
}
