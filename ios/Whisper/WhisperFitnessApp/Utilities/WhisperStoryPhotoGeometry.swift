import Foundation
import CoreGraphics

nonisolated enum WhisperStoryPhotoGeometry {
    /// Crop enlarged media within its fitted bounds; keep smaller photos reachable without changing zoom.
    static func boundedOffset(_ offset: CGSize, scale: CGFloat, image: CGSize, stage: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0, stage.width > 0, stage.height > 0 else { return .zero }
        let fit = min(stage.width / image.width, stage.height / image.height)
        let width = image.width * fit * scale
        let height = image.height * fit * scale
        let x = width > stage.width ? (width - stage.width) / 2 : stage.width * 0.45
        let y = height > stage.height ? (height - stage.height) / 2 : stage.height * 0.45
        return CGSize(width: min(x, max(-x, offset.width)), height: min(y, max(-y, offset.height)))
    }
}
