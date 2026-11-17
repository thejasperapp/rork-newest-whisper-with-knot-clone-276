import UIKit

/// Produces one bounded photo payload; the caller keeps caption and style editable in metadata.
nonisolated enum WhisperStoryPhotoCardRenderer {
    static func prepare(_ data: [Data], strip: Bool) -> Data? {
        guard !data.isEmpty, data.count <= (strip ? 4 : 1), !Task.isCancelled else { return nil }
        let images = data.compactMap { WhisperImageCache.decode($0, maxPixelSize: 1600) }
        guard images.count == data.count else { return nil }
        if !strip { return images.first?.jpegData(compressionQuality: 0.9) }
        let width: CGFloat = 640
        let cellHeight: CGFloat = 800
        let gap: CGFloat = 32
        let size = CGSize(width: width, height: cellHeight * CGFloat(images.count) + gap * CGFloat(images.count - 1))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let result = UIGraphicsImageRenderer(size: size, format: format).image { context in
            for (index, image) in images.enumerated() {
                let rect = CGRect(x: 0, y: CGFloat(index) * (cellHeight + gap), width: width, height: cellHeight)
                let scale = max(rect.width / max(1, image.size.width), rect.height / max(1, image.size.height))
                let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                context.cgContext.saveGState()
                context.cgContext.clip(to: rect)
                image.draw(in: CGRect(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2, width: drawn.width, height: drawn.height))
                context.cgContext.restoreGState()
            }
        }
        guard !Task.isCancelled else { return nil }
        return result.pngData()
    }
}
