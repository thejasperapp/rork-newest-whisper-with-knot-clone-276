import AVFoundation
import CoreImage

/// Sequential local-video decoder. After preparation, accessed only by the camera frame queue.
nonisolated final class WhisperWaveLiveVideoBackground: @unchecked Sendable {
    private let asset: AVURLAsset
    private let track: AVAssetTrack
    private let available: CMTimeRange
    private let transform: CGAffineTransform
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var next: CMSampleBuffer?
    private var current: CMSampleBuffer?
    private var previousTime: Double = -1

    private init(asset: AVURLAsset, track: AVAssetTrack, available: CMTimeRange, transform: CGAffineTransform) {
        self.asset = asset; self.track = track; self.available = available; self.transform = transform
    }

    @concurrent static func prepare(_ url: URL) async throws -> WhisperWaveLiveVideoBackground {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw CocoaError(.fileReadCorruptFile) }
        let range = try await track.load(.timeRange)
        let size = try await track.load(.naturalSize)
        let preferred = try await track.load(.preferredTransform)
        guard range.duration.seconds.isFinite, range.duration.seconds > 0.1 else { throw CocoaError(.fileReadCorruptFile) }
        let bounds = CGRect(origin: .zero, size: size).applying(preferred)
        let normalized = preferred.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
        let transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)
            .concatenating(normalized)
            .concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: bounds.height))
        return WhisperWaveLiveVideoBackground(asset: asset, track: track, available: range, transform: transform)
    }

    func frame(seconds: Double) throws -> CIImage {
        let phase = max(0, seconds.isFinite ? seconds : 0).truncatingRemainder(dividingBy: available.duration.seconds)
        let target = available.start.seconds + phase
        if reader == nil || target < previousTime || target - previousTime > 0.5 {
            reader?.cancelReading()
            let newReader = try AVAssetReader(asset: asset)
            let newOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            newOutput.alwaysCopiesSampleData = false
            guard newReader.canAdd(newOutput) else { throw CocoaError(.fileReadCorruptFile) }
            newReader.add(newOutput)
            let start = CMTime(seconds: target, preferredTimescale: 60000)
            newReader.timeRange = CMTimeRange(start: start, end: available.end)
            guard newReader.startReading() else { throw newReader.error ?? CocoaError(.fileReadCorruptFile) }
            reader = newReader; output = newOutput; current = nil
            next = newOutput.copyNextSampleBuffer()
        }
        previousTime = target
        while let sample = next {
            if current != nil && CMSampleBufferGetPresentationTimeStamp(sample).seconds > target { break }
            current = sample
            next = output?.copyNextSampleBuffer()
        }
        if reader?.status == .failed { throw reader?.error ?? CocoaError(.fileReadCorruptFile) }
        guard let sample = current, let pixels = CMSampleBufferGetImageBuffer(sample) else { throw CocoaError(.fileReadCorruptFile) }
        return CIImage(cvPixelBuffer: pixels).transformed(by: transform)
    }

    deinit { reader?.cancelReading() }
}
