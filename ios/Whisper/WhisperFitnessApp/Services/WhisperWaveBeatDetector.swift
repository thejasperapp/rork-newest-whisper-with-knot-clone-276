import AVFoundation
import Accelerate

/// On-device beat detection for a sound or a clip's own audio. Spectral-flux
/// onsets → an autocorrelation tempo with a gentle preference for dance
/// tempos → dynamic-programming beat tracking (Ellis 2007), then the downbeat
/// phase whose beats carry the most energy. Nothing leaves the device; results
/// are cached per file so re-opening the editor is instant.
nonisolated final class WhisperWaveBeatDetector: @unchecked Sendable {
    static let shared = WhisperWaveBeatDetector()

    private static let sampleRate: Double = 22_050
    private static let window: Int = 1024
    private static let hop: Int = 256
    private static var framesPerSecond: Double { sampleRate / Double(hop) }
    /// Analysis stops after this much audio — more than any wave needs.
    private static let maxSeconds: Double = 600

    private let lock = NSLock()
    private var cache: [String: WhisperWaveBeatMap] = [:]
    private var misses: Set<String> = []
    private var inFlight: [String: Task<WhisperWaveBeatMap?, Never>] = [:]

    private init() {}

    /// The beat map for `url`, or nil when the file has no usable audio.
    func analyze(_ url: URL) async -> WhisperWaveBeatMap? {
        let key = Self.key(url)
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        if misses.contains(key) { lock.unlock(); return nil }
        if let running = inFlight[key] { lock.unlock(); return await running.value }
        let task = Task.detached(priority: .utility) { () -> WhisperWaveBeatMap? in
            guard let samples = await Self.decode(url) else { return nil }
            return Self.track(samples)
        }
        inFlight[key] = task
        lock.unlock()
        let result = await task.value
        lock.lock()
        inFlight[key] = nil
        if let result { cache[key] = result } else { misses.insert(key) }
        lock.unlock()
        return result
    }

    private static func key(_ url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return "\(url.path)#\(size)"
    }

    // MARK: Decoding

    /// Mono 22.05 kHz float samples, peak-normalized.
    private static func decode(_ url: URL) async -> [Float]? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        var samples: [Float] = []
        samples.reserveCapacity(Int(sampleRate * 45))
        let cap = Int(sampleRate * maxSeconds)
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            guard length >= 4 else { continue }
            var chunk = [Float](repeating: 0, count: length / 4)
            let status = chunk.withUnsafeMutableBytes { raw -> OSStatus in
                guard let base = raw.baseAddress else { return -1 }
                return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
            }
            guard status == kCMBlockBufferNoErr else { continue }
            samples.append(contentsOf: chunk)
            if samples.count >= cap { break }
        }
        if reader.status == .reading { reader.cancelReading() }
        let total = samples.count
        guard total > Int(sampleRate * 1.5) else { return nil }
        var peak: Float = 0
        samples.withUnsafeBufferPointer { vDSP_maxmgv($0.baseAddress!, 1, &peak, vDSP_Length(total)) }
        guard peak > 1e-4 else { return nil }
        var gain = 1 / peak
        samples.withUnsafeMutableBufferPointer { vDSP_vsmul($0.baseAddress!, 1, &gain, $0.baseAddress!, 1, vDSP_Length(total)) }
        return samples
    }

    // MARK: Onsets

    /// Log-compressed spectral flux per hop: how much louder each moment is
    /// than the one before, across the bands where kicks, snares and hats live.
    private static func onsetEnvelope(_ samples: [Float]) -> [Float] {
        let n = window
        let half = n / 2
        guard samples.count >= n else { return [] }
        let frames = (samples.count - n) / hop + 1
        guard frames > 8, let fft = vDSP.FFT(log2n: vDSP_Length(log2(Double(n))), radix: .radix2, ofType: DSPSplitComplex.self) else { return [] }
        let hann = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)

        let realIn = UnsafeMutablePointer<Float>.allocate(capacity: half)
        let imagIn = UnsafeMutablePointer<Float>.allocate(capacity: half)
        let realOut = UnsafeMutablePointer<Float>.allocate(capacity: half)
        let imagOut = UnsafeMutablePointer<Float>.allocate(capacity: half)
        let magnitudes = UnsafeMutablePointer<Float>.allocate(capacity: half)
        defer { realIn.deallocate(); imagIn.deallocate(); realOut.deallocate(); imagOut.deallocate(); magnitudes.deallocate() }
        realIn.initialize(repeating: 0, count: half)
        imagIn.initialize(repeating: 0, count: half)
        realOut.initialize(repeating: 0, count: half)
        imagOut.initialize(repeating: 0, count: half)
        var input = DSPSplitComplex(realp: realIn, imagp: imagIn)
        var output = DSPSplitComplex(realp: realOut, imagp: imagOut)

        var windowed = [Float](repeating: 0, count: n)
        var previous = [Float](repeating: 0, count: half)
        var flux = [Float](repeating: 0, count: frames)
        let lowBin = 1
        let highBin = min(half - 1, Int(8_000 / (sampleRate / Double(n))))
        let gamma: Float = 100
        let norm: Float = 1 / Float(n)

        samples.withUnsafeBufferPointer { source in
            hann.withUnsafeBufferPointer { taper in
                for frame in 0..<frames {
                    windowed.withUnsafeMutableBufferPointer { out in
                        vDSP_vmul(source.baseAddress! + frame * hop, 1, taper.baseAddress!, 1, out.baseAddress!, 1, vDSP_Length(n))
                    }
                    windowed.withUnsafeBytes { raw in
                        vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &input, 1, vDSP_Length(half))
                    }
                    fft.forward(input: input, output: &output)
                    vDSP_zvmags(&output, 1, magnitudes, 1, vDSP_Length(half))
                    var sum: Float = 0
                    for bin in lowBin...highBin {
                        let compressed = log1pf(gamma * sqrtf(magnitudes[bin]) * norm)
                        let rise = compressed - previous[bin]
                        if rise > 0 { sum += rise }
                        previous[bin] = compressed
                    }
                    flux[frame] = sum
                }
            }
        }
        flux[0] = 0
        // A touch of smoothing so a single noisy bin never reads as a hit.
        var smoothed = flux
        for i in 1..<(frames - 1) { smoothed[i] = (flux[i - 1] + 2 * flux[i] + flux[i + 1]) / 4 }
        return smoothed
    }

    // MARK: Tempo + tracking

    private static func track(_ samples: [Float]) -> WhisperWaveBeatMap? {
        let envelope = onsetEnvelope(samples)
        let count = envelope.count
        guard count > 32 else { return nil }
        let fps = framesPerSecond
        let duration = Double(samples.count) / sampleRate

        // Normalize by the standard deviation so scores are level-independent.
        var mean: Float = 0
        var deviation: Float = 0
        vDSP_normalize(envelope, 1, nil, 1, &mean, &deviation, vDSP_Length(count))
        guard deviation > 1e-6 else { return nil }
        let localscore = envelope.map { $0 / deviation }
        let centered = envelope.map { $0 - mean }

        // Tempo: autocorrelation over 60–200 BPM, weighted toward 120.
        let minLag = max(2, Int(fps * 60 / 200))
        let maxLag = min(count / 2, Int(fps * 60 / 60))
        guard maxLag > minLag + 2 else { return nil }
        var energy: Float = 0
        vDSP_dotpr(centered, 1, centered, 1, &energy, vDSP_Length(count))
        guard energy > 0 else { return nil }
        var bestLag = minLag
        var bestScore: Float = -.greatestFiniteMagnitude
        var bestCoefficient: Float = 0
        var correlations: [Float] = Array(repeating: 0, count: maxLag + 1)
        for lag in minLag...maxLag {
            var dot: Float = 0
            centered.withUnsafeBufferPointer { p in
                vDSP_dotpr(p.baseAddress!, 1, p.baseAddress! + lag, 1, &dot, vDSP_Length(count - lag))
            }
            let coefficient = dot / energy * Float(count) / Float(count - lag)
            correlations[lag] = coefficient
            let bpm = 60 * fps / Double(lag)
            let prior = Float(exp(-0.5 * pow(log2(bpm / 120) / 0.9, 2)))
            let score = coefficient * prior
            if score > bestScore { bestScore = score; bestLag = lag; bestCoefficient = coefficient }
        }
        // Parabolic refinement of the lag for a truer BPM readout.
        var period = Double(bestLag)
        if bestLag > minLag, bestLag < maxLag {
            let a = Double(correlations[bestLag - 1]), b = Double(correlations[bestLag]), c = Double(correlations[bestLag + 1])
            let denominator = a - 2 * b + c
            if abs(denominator) > 1e-9 { period += 0.5 * (a - c) / denominator }
        }
        let bpm = 60 * fps / period
        let isSteady = bestCoefficient > 0.12

        // Dynamic programming: each frame picks the predecessor about one
        // period back that maximizes accumulated onset strength.
        let periodFrames = max(2, Int(period.rounded()))
        let earliest = -2 * periodFrames
        let latest = -max(1, Int((period / 2).rounded()))
        let offsets = Array(earliest...latest)
        let tightness: Float = 100
        let weights: [Float] = offsets.map { -tightness * Float(pow(log(Double(-$0) / period), 2)) }
        var cumulative = [Float](repeating: 0, count: count)
        var backlink = [Int](repeating: -1, count: count)
        let ceiling = localscore.max() ?? 0
        var firstBeat = true
        for i in 0..<count {
            var best: Float = -.greatestFiniteMagnitude
            var choice = -1
            for (j, offset) in offsets.enumerated() {
                let candidate = i + offset
                let score = candidate >= 0 ? weights[j] + cumulative[candidate] : weights[j]
                if score > best { best = score; choice = candidate }
            }
            cumulative[i] = localscore[i] + best
            if firstBeat && localscore[i] < 0.01 * ceiling {
                backlink[i] = -1
            } else {
                backlink[i] = choice
                firstBeat = false
            }
        }

        // Last beat: the strongest late local maximum, then walk back.
        var maxima: [Int] = []
        for i in 1..<(count - 1) where cumulative[i] > cumulative[i - 1] && cumulative[i] >= cumulative[i + 1] { maxima.append(i) }
        guard !maxima.isEmpty else { return nil }
        let median = maxima.map { cumulative[$0] }.sorted()[maxima.count / 2]
        var tail = maxima.last ?? (count - 1)
        var tailScore: Float = -.greatestFiniteMagnitude
        for i in maxima where cumulative[i] >= 0.5 * median && cumulative[i] > tailScore { tailScore = cumulative[i]; tail = i }
        var frames: [Int] = []
        var cursor = tail
        while cursor >= 0 {
            frames.append(cursor)
            cursor = backlink[cursor]
        }
        frames.reverse()
        guard frames.count >= 2 else { return nil }

        // Drop leading and trailing beats that sit on near-silence.
        let strengths = frames.map { localscore[$0] }
        let rms = sqrt(strengths.reduce(0) { $0 + $1 * $1 } / Float(strengths.count))
        var lower = 0
        var upper = frames.count - 1
        while lower < upper, strengths[lower] < 0.35 * rms { lower += 1 }
        while upper > lower, strengths[upper] < 0.35 * rms { upper -= 1 }
        let kept = Array(frames[lower...upper])
        guard kept.count >= 2 else { return nil }
        let center = Double(window) / 2 / sampleRate
        let beats = kept.map { Double($0 * hop) / sampleRate + center }

        // Downbeats: the phase whose every-fourth beats carry the most energy.
        var phase = 0
        var phaseScore: Float = -1
        for candidate in 0..<min(4, kept.count) {
            var total: Float = 0
            var i = candidate
            while i < kept.count { total += localscore[kept[i]]; i += 4 }
            if total > phaseScore { phaseScore = total; phase = candidate }
        }

        // A 240-bar picture of the sound for the strip, max-pooled.
        let bars = 240
        var picture = [Float](repeating: 0, count: bars)
        for (i, value) in envelope.enumerated() {
            let bar = min(bars - 1, i * bars / count)
            picture[bar] = max(picture[bar], value)
        }
        let top = picture.max() ?? 1
        if top > 0 { picture = picture.map { $0 / top } }

        return WhisperWaveBeatMap(beats: beats, bpm: bpm, downbeatPhase: phase, envelope: picture, duration: duration, isSteady: isSteady)
    }
}
