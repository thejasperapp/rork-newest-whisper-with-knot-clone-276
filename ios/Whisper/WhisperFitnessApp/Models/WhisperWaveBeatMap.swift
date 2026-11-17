import Foundation

/// The beats found in one audio file, in that file's own seconds.
nonisolated struct WhisperWaveBeatMap: Equatable, Sendable {
    /// Seconds into the source audio of every beat, ascending.
    let beats: [Double]
    let bpm: Double
    /// Index into `beats` of the first downbeat; every fourth beat after it is one too.
    let downbeatPhase: Int
    /// Onset strength 0…1, evenly spaced across `duration` — the strip's waveform.
    let envelope: [Float]
    let duration: Double
    /// False when the pulse was faint. The beats still work as snap targets.
    let isSteady: Bool

    /// Beats counted from the first downbeat — 0, 4, 8… are downbeats.
    func rank(_ index: Int) -> Int { index - downbeatPhase }

    func envelope(at seconds: Double) -> Float {
        guard !envelope.isEmpty, duration > 0 else { return 0 }
        let index = Int(seconds / duration * Double(envelope.count))
        return envelope[min(envelope.count - 1, max(0, index))]
    }
}

/// The beat map moved onto the wave's output clock — through the song's start
/// offset and looping when a sound is chosen, or through each clip's trim and
/// speed when the wave relies on its own audio.
nonisolated struct WhisperWaveBeatGrid: Equatable, Sendable {
    nonisolated struct Beat: Equatable, Sendable {
        let time: Double
        /// Beats since the first downbeat (may be negative before it).
        let rank: Int
        var isDownbeat: Bool { ((rank % 4) + 4) % 4 == 0 }
    }

    nonisolated enum Source: Equatable, Sendable {
        case music(String)
        case clips
    }

    let beats: [Beat]
    let bpm: Double
    let isSteady: Bool
    let source: Source
    /// Onset strength sampled evenly across `duration`.
    let envelope: [Float]
    let duration: Double

    var times: [Double] { beats.map(\.time) }
    var isEmpty: Bool { beats.isEmpty }

    var sourceLabel: String {
        switch source {
        case .music(let title): return title
        case .clips: return "your clips' sound"
        }
    }

    /// Every `n`-th beat, phased from a downbeat — the cut points for a montage.
    func cuts(every n: Int) -> [Double] {
        let step = max(1, n)
        return beats.filter { ((($0.rank % step) + step) % step) == 0 }.map(\.time)
    }

    /// The beat closest to `time`, when one lies within `tolerance` seconds.
    func nearest(to time: Double, within tolerance: Double) -> Double? {
        Self.nearest(in: times, to: time, within: tolerance)
    }

    static func nearest(in times: [Double], to time: Double, within tolerance: Double) -> Double? {
        guard let best = times.min(by: { abs($0 - time) < abs($1 - time) }), abs(best - time) <= tolerance else { return nil }
        return best
    }

    /// A chosen sound: beats follow the song's start offset and its loops.
    static func music(_ map: WhisperWaveBeatMap, start: Double, length: Double, title: String) -> WhisperWaveBeatGrid {
        let segments = WhisperWaveTimeline.audioSegments(duration: map.duration, start: start, length: length)
        var beats: [Beat] = []
        for segment in segments {
            for (index, beat) in map.beats.enumerated() where beat >= segment.source && beat < segment.source + segment.length {
                beats.append(Beat(time: segment.destination + (beat - segment.source), rank: map.rank(index)))
            }
        }
        let envelope = sample(length: length) { time in
            guard let segment = segments.first(where: { time >= $0.destination && time < $0.destination + $0.length }) else { return 0 }
            return map.envelope(at: segment.source + (time - segment.destination))
        }
        return WhisperWaveBeatGrid(beats: beats, bpm: map.bpm, isSteady: map.isSteady, source: .music(title), envelope: envelope, duration: length)
    }

    /// No sound chosen: beats come from each clip's own audio, through its trim and speed.
    static func clips(_ maps: [String: WhisperWaveBeatMap], clips: [WhisperWaveClip]) -> WhisperWaveBeatGrid? {
        var beats: [Beat] = []
        var weightedBPM: Double = 0
        var weight: Double = 0
        var steady = false
        var windows: [(start: Double, end: Double, clip: WhisperWaveClip, map: WhisperWaveBeatMap)] = []
        for clip in clips {
            guard let map = maps[clip.url.path] else { continue }
            let start = WhisperWaveTimeline.start(of: clip.id, in: clips)
            windows.append((start, start + clip.effectiveSeconds, clip, map))
            for (index, beat) in map.beats.enumerated() where beat >= clip.trimStart && beat <= clip.trimEnd {
                beats.append(Beat(time: start + (beat - clip.trimStart) / max(0.1, clip.speed), rank: map.rank(index)))
            }
            weightedBPM += map.bpm * clip.speed * clip.effectiveSeconds
            weight += clip.effectiveSeconds
            steady = steady || map.isSteady
        }
        guard !beats.isEmpty, weight > 0 else { return nil }
        let length = WhisperWaveTimeline.duration(clips)
        let envelope = sample(length: length) { time in
            guard let window = windows.first(where: { time >= $0.start && time < $0.end }) else { return 0 }
            return window.map.envelope(at: window.clip.trimStart + (time - window.start) * window.clip.speed)
        }
        return WhisperWaveBeatGrid(beats: beats.sorted { $0.time < $1.time }, bpm: weightedBPM / weight, isSteady: steady, source: .clips, envelope: envelope, duration: length)
    }

    private static func sample(length: Double, count: Int = 240, _ value: (Double) -> Float) -> [Float] {
        guard length > 0 else { return [] }
        return (0..<count).map { value(length * (Double($0) + 0.5) / Double(count)) }
    }
}
