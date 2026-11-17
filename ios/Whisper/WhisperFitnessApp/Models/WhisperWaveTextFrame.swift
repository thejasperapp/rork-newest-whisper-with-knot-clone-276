import CoreImage
import UIKit

/// Rasterize typography once, not for every video frame. Time-based animation is seekable.
nonisolated struct WhisperWaveTextFrame: @unchecked Sendable {
    let layer: WaveTextOverlay
    let image: CIImage

    @MainActor static func prepare(_ overlays: [WaveTextOverlay], canvas: CGSize) -> [WhisperWaveTextFrame] {
        overlays.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.compactMap { overlay in
            let group = WhisperWaveStudio.textLayerGroup(overlay, renderSize: canvas)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let art = UIGraphicsImageRenderer(size: group.bounds.size, format: format).image { context in
                group.render(in: context.cgContext)
            }
            guard let cgImage = art.cgImage else { return nil }
            return WhisperWaveTextFrame(layer: overlay, image: CIImage(cgImage: cgImage))
        }
    }

    func frame(at time: Double, canvas: CGSize) -> CIImage? {
        guard time >= layer.start, layer.end <= 0 || time < layer.end else { return nil }
        let age = max(0, time - layer.start)
        var art = image
        var scale: CGFloat = 1
        var opacity: Double = 1
        var rise: CGFloat = 0
        switch layer.animation {
        case .none: break
        case .fade: opacity = min(1, age / 0.75)
        case .rise:
            opacity = min(1, age / 0.4)
            rise = canvas.height * 0.05 * CGFloat(pow(1 - min(1, age / 0.55), 2))
        case .pop:
            let p = min(1, age / 0.5)
            if p < 0.55 { scale = 0.35 + 0.79 * CGFloat(p / 0.55) }
            else if p < 0.8 { scale = 1.14 - 0.18 * CGFloat((p - 0.55) / 0.25) }
            else { scale = 0.96 + 0.04 * CGFloat((p - 0.8) / 0.2) }
        case .typewriter:
            let duration = min(2.2, max(0.5, Double(layer.text.count) * 0.06))
            art = art.cropped(to: CGRect(x: 0, y: 0, width: image.extent.width * min(1, age / duration), height: image.extent.height))
        }
        let x = canvas.width * layer.x - image.extent.width * scale / 2
        let y = canvas.height * (1 - layer.y) - image.extent.height * scale / 2 - rise
        art = art.transformed(by: CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: x, y: y)))
        if opacity < 1 { art = art.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)]) }
        return art
    }
}
