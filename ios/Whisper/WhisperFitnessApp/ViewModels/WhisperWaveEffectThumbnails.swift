import CoreImage
import Observation

@MainActor @Observable
final class WhisperWaveEffectThumbnails {
    private(set) var images: [String: CGImage] = [:]
    private var task: Task<Void, Never>?

    func prepare(_ seed: CGImage, effects: [WhisperWaveCameraEffect] = WhisperWaveCameraEffect.available) {
        task?.cancel()
        task = Task {
            let worker = Task.detached(priority: .utility) { () -> [String: CGImage] in
                let image = CIImage(cgImage: seed)
                let context = CIContext(options: [.cacheIntermediates: false])
                let faces = (try? WhisperWaveFaceRenderer.detect(image)) ?? []
                var result: [String: CGImage] = [:]
                for effect in effects {
                    if Task.isCancelled { break }
                    autoreleasepool {
                        guard let face = try? WhisperWaveFaceRenderer.render(image, setting: .current(effect.faceKind), observations: faces, time: 0.6) else { return }
                        if let rendered = try? WhisperWaveCameraEffectRenderer.render(face, effect: effect, time: 0.6, quality: .preview),
                           let cg = context.createCGImage(rendered, from: image.extent) { result[effect.id] = cg }
                    }
                }
                return result
            }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            images = result
        }
    }

    func clear() { task?.cancel(); task = nil; images = [:] }
}
