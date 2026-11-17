import AVFoundation
import CoreImage

/// Prepared resources for one source clip. Background video is decoded by AVFoundation on the composition clock.
nonisolated struct WhisperWaveSubjectFrame: @unchecked Sendable {
    let trackID: CMPersistentTrackID
    let range: CMTimeRange
    let face: WhisperWaveFaceSetting?
    let background: WhisperWaveBackground?
    let photo: CIImage?
    let backgroundTrackID: CMPersistentTrackID?
    let backgroundTransform: CGAffineTransform
    let keyCube: Data?
    let spillCube: Data?
    var cameraEffect: WhisperWaveCameraEffect? = nil
    var effectTimeOffset: Double = 0
    /// Unique per prepared placement, including split clips sharing the same AV track.
    var trackingID: UUID = UUID()

    static func prepare(clip: WhisperWaveClip, trackID: CMPersistentTrackID, range: CMTimeRange, composition: AVMutableComposition, canvas: CGSize) async throws -> WhisperWaveSubjectFrame {
        var photo: CIImage?
        var backgroundID: CMPersistentTrackID?
        var transform = CGAffineTransform.identity
        if let background = clip.background {
            guard background.url.isFileURL, FileManager.default.fileExists(atPath: background.url.path) else { throw CocoaError(.fileNoSuchFile) }
            if background.media == .photo {
                photo = try WhisperWaveBackgroundImporter.image(at: background.url)
            } else {
                let asset = AVURLAsset(url: background.url)
                guard let source = try await asset.loadTracks(withMediaType: .video).first,
                      let destination = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw CocoaError(.fileReadCorruptFile) }
                let available = try await source.load(.timeRange)
                guard available.duration.seconds.isFinite, available.duration.seconds > 0.1 else { throw CocoaError(.fileReadCorruptFile) }
                let preferred = try await source.load(.preferredTransform)
                let size = try await source.load(.naturalSize)
                // Link the background clock to the source, preserving continuity after a split.
                let offset = max(0, background.startTime + clip.trimStart / max(0.1, clip.speed)).truncatingRemainder(dividingBy: available.duration.seconds)
                let segments = WhisperWaveBackgroundLoop.segments(available: available, offset: offset, output: range)
                for segment in segments {
                    try Task.checkCancellation()
                    try destination.insertTimeRange(segment.source, of: source, at: segment.destination)
                }
                var framing = WhisperWaveClip(url: background.url, duration: available.duration.seconds)
                framing.fillsFrame = true
                framing.zoom = WhisperWaveBackground.bounded(background.zoom, 1...3, fallback: 1)
                framing.offsetX = WhisperWaveBackground.bounded(background.x, -1...1)
                framing.offsetY = WhisperWaveBackground.bounded(background.y, -1...1)
                transform = WhisperWaveTimeline.transform(framing, naturalSize: size, preferred: preferred, canvas: canvas)
                backgroundID = destination.trackID
            }
        }
        let cubes = clip.background.flatMap { $0.removal == .chroma ? WhisperWaveBackgroundRenderer.cubes($0) : nil }
        return WhisperWaveSubjectFrame(trackID: trackID, range: range, face: clip.face, background: clip.background, photo: photo, backgroundTrackID: backgroundID, backgroundTransform: transform, keyCube: cubes?.mask, spillCube: cubes?.spill, cameraEffect: clip.cameraEffect, effectTimeOffset: clip.trimStart / max(0.1, clip.speed))
    }
}
