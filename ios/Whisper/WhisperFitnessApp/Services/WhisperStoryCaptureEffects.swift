import AVFoundation
import CoreImage
import UIKit

/// Effects are frozen at the shutter and baked once before Story editing. The
/// editor, poster, publication, and saved media all receive the same rendered pixels.
nonisolated struct WhisperStoryCaptureEffects: Sendable {
    var effect: WhisperWaveCameraEffect = .none
    var filter: SnapFilter = .none
    var background: WhisperWaveBackground?
    var cameraFraming: Bool = true
    var photoTime: Double = 0
    var face: WhisperWaveFaceSetting {
        .current(effect.faceKind)
    }
    var configuration: WhisperWaveLiveFrameRenderer.Configuration {
        .init(face: face, background: background, filter: filter, cameraEffect: effect)
    }
    @concurrent func photo(_ image: UIImage) async throws -> UIImage {
        try Task.checkCancellation()
        guard let source = image.normalizedUpright().cgImage else { throw CocoaError(.fileReadCorruptFile) }
        let canvas = cameraFraming ? CGRect(x: 0, y: 0, width: 1080, height: 1920) : CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let upright = cameraFraming ? WhisperWaveLiveFrameRenderer.fitCamera(CIImage(cgImage: source), canvas: canvas) : CIImage(cgImage: source)
        var backdrop: CIImage?
        if let background {
            let raw: CIImage
            if background.media == .photo { raw = try WhisperWaveBackgroundImporter.image(at: background.url) }
            else {
                let video = try await WhisperWaveLiveVideoBackground.prepare(background.url)
                raw = try video.frame(seconds: background.startTime)
            }
            backdrop = WhisperWaveBackgroundRenderer.fitPhoto(raw, settings: background, canvas: canvas)
        }
        let cubes = background.map { WhisperWaveBackgroundRenderer.cubes($0) }
        let decorated = try WhisperWaveBackgroundRenderer.render(upright, face: face, settings: background, background: backdrop, keyCube: cubes?.mask, spillCube: cubes?.spill, quality: .final, time: photoTime)
        let creative = try WhisperWaveCameraEffectRenderer.render(decorated, effect: effect, time: photoTime, quality: .final)
        let graded = WhisperWaveColorAdjustments().process(creative, filter: filter)
        guard let result = CIContext(options: [.cacheIntermediates: false]).createCGImage(graded, from: canvas) else { throw CocoaError(.fileReadCorruptFile) }
        return UIImage(cgImage: result)
    }
    @concurrent func video(_ url: URL) async throws -> URL {
        let duration = await WhisperWaveClipStudio.duration(of: url)
        guard duration.isFinite, duration > 0 else { throw CocoaError(.fileReadCorruptFile) }
        var clip = WhisperWaveClip(url: url, duration: duration)
        clip.fillsFrame = cameraFraming
        clip.face = face.isActive ? face : nil
        clip.background = background
        clip.cameraEffect = effect == .none ? nil : effect
        guard let built = await WhisperWaveClipStudio.makeComposition([clip], filter: filter) else { throw CocoaError(.fileReadCorruptFile) }
        // The shared encoder ignores empty audio lanes and verifies full picture
        // and sound coverage; preset export rejects some silent compositions.
        return try await WhisperWaveBudgetEncoder().encode(asset: built.asset, video: built.video, audio: built.audio, progress: { _, _ in })
    }
}
