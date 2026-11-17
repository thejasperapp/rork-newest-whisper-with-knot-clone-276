import AVFoundation
import Observation
import UIKit

@MainActor @Observable final class WhisperWaveCoverModel {
    var image: UIImage?
    var imageTime: Double?
    var frames: [Int: UIImage] = [:]
    var error: String?
    var isSeeking: Bool = false
    private var generator: AVAssetImageGenerator?
    private var stripGenerator: AVAssetImageGenerator?
    private var seekTask: Task<Void, Never>?
    private var operation: UUID = UUID()
    private var seekID: UUID = UUID()

    func load(_ request: WhisperWaveRenderRequest, selectedTime: Double) async {
        stop(); error = nil
        let token = operation
        guard let built = await WhisperWaveClipStudio.makeComposition(request.clips, muteOriginal: true, filter: request.filter, adjustments: request.adjustments, effect: request.effect, fx: request.fx, quality: .final, texts: request.texts, captions: request.captions) else {
            if token == operation { error = "Couldn't read this edit. Your existing cover is unchanged." }
            return
        }
        guard token == operation, !Task.isCancelled else { return }
        generator = Self.generator(asset: built.asset, video: built.video, size: 720)
        let strip = Self.generator(asset: built.asset, video: built.video, size: 144)
        stripGenerator = strip
        seek(selectedTime)
        let duration = WhisperWaveTimeline.duration(request.clips)
        for index in 0..<10 {
            guard token == operation, !Task.isCancelled else { return }
            let time = max(0, duration - 0.04) * Double(index) / 9
            if let frame = try? await strip.image(at: CMTime(seconds: time, preferredTimescale: 600)).image {
                guard token == operation, !Task.isCancelled else { return }
                frames[index] = UIImage(cgImage: frame)
            }
        }
    }

    func seek(_ time: Double) {
        guard let generator else { return }
        seekTask?.cancel(); generator.cancelAllCGImageGeneration()
        seekID = UUID(); let token = seekID; isSeeking = true
        seekTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(45))
                let result = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
                guard token == seekID, !Task.isCancelled else { return }
                image = UIImage(cgImage: result.image); imageTime = result.actualTime.seconds
                isSeeking = false; error = nil
            } catch {
                guard token == seekID, !Task.isCancelled else { return }
                isSeeking = false; image = nil; imageTime = nil
                self.error = "Couldn't read this frame. Slide a little further or retry."
            }
        }
    }

    func stop() {
        operation = UUID(); seekID = UUID(); seekTask?.cancel()
        generator?.cancelAllCGImageGeneration(); stripGenerator?.cancelAllCGImageGeneration()
        generator = nil; stripGenerator = nil; isSeeking = false
    }

    nonisolated static func generator(asset: AVAsset, video: AVVideoComposition, size: CGFloat) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.videoComposition = video
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: size, height: size * 16 / 9)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return generator
    }
}
