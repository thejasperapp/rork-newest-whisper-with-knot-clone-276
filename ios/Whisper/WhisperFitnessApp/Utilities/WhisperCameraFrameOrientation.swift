import CoreImage
import Foundation

/// Capture delivers unrotated, unmirrored Wave pixels. Normalize once, before any crop or Vision request.
nonisolated struct WhisperCameraFrameOrientation: Equatable, Sendable {
    var clockwiseDegrees: Int
    var mirrored: Bool

    static func quarterTurn(_ degrees: CGFloat) -> Int {
        guard degrees.isFinite else { return 0 }
        return ((Int((degrees / 90).rounded()) % 4) + 4) % 4 * 90
    }

    func normalize(_ image: CIImage) -> CIImage {
        let exif: Int32
        switch Self.quarterTurn(CGFloat(clockwiseDegrees)) {
        case 90: exif = 6
        case 180: exif = 3
        case 270: exif = 8
        default: exif = 1
        }
        let upright = image.oriented(forExifOrientation: exif)
        let extent = upright.extent
        let zeroed = upright.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        guard mirrored else { return zeroed }
        return zeroed.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: extent.width, ty: 0))
    }
}
