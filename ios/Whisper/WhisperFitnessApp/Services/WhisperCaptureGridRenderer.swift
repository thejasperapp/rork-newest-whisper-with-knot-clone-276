import UIKit

nonisolated enum WhisperCaptureGridRenderer {
    @concurrent static func render(_ photos: [UIImage], grid: WhisperCaptureGrid) async throws -> UIImage {
        try Task.checkCancellation()
        guard photos.count == grid.cells.count else { throw CocoaError(.fileReadCorruptFile) }
        let size = CGSize(width: 1080, height: 1920)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill(); context.fill(CGRect(origin: .zero, size: size))
            for (index, cell) in grid.cells.enumerated() {
                let image = photos[index]
                let rect = CGRect(x: cell.minX * size.width, y: cell.minY * size.height, width: cell.width * size.width, height: cell.height * size.height)
                let factor = max(rect.width / max(1, image.size.width), rect.height / max(1, image.size.height))
                let fitted = CGSize(width: image.size.width * factor, height: image.size.height * factor)
                context.cgContext.saveGState(); context.cgContext.clip(to: rect)
                image.draw(in: CGRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2, width: fitted.width, height: fitted.height))
                context.cgContext.restoreGState()
            }
        }
    }
}
