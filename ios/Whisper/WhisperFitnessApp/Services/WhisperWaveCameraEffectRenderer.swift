import CoreImage
import Vision

nonisolated enum WhisperWaveCameraEffectRenderer {
    static func render(_ image: CIImage, effect: WhisperWaveCameraEffect, time: Double, quality: WhisperWaveRenderQuality) throws -> CIImage {
        var result = image
        if effect == .cloneWall { return try cloneCrowd(image, quality: quality) }
        if effect == .mono { result = image.applyingFilter("CIPhotoEffectNoir") }
        if effect == .stardust {
            result = image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.06, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0.85, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1.12, w: 0)
            ])
        }
        if let fx = effect.fx { result = WhisperWaveFXRenderer.shared.render(result, fx: fx, time: time, quality: quality) }
        return result.cropped(to: image.extent)
    }

    private static func cloneCrowd(_ image: CIImage, quality: WhisperWaveRenderQuality) throws -> CIImage {
        let fallback = CIImage(color: CIColor(red: 0.12, green: 0.15, blue: 0.18)).cropped(to: image.extent)
        let settings = WhisperWaveBackground(url: URL(fileURLWithPath: "/generated-clone-wall"), media: .photo, removal: .person)
        guard let face = try WhisperWaveFaceRenderer.detect(image).max(by: { $0.boundingBox.width < $1.boundingBox.width }) else {
            return try WhisperWaveBackgroundRenderer.render(image, face: nil, settings: settings, background: fallback, keyCube: nil, spillCube: nil, quality: quality)
        }
        let e = image.extent, b = face.boundingBox
        let rect = CGRect(x: e.minX + b.minX * e.width, y: e.minY + b.minY * e.height, width: b.width * e.width, height: b.height * e.height).insetBy(dx: -b.width * e.width * 0.12, dy: -b.height * e.height * 0.2).intersection(e)
        guard rect.width > 4, rect.height > 4 else { throw CocoaError(.coderInvalidValue) }
        let mask = CIFilter(name: "CIRadialGradient", parameters: ["inputCenter": CIVector(x: 0, y: 0), "inputRadius0": 0.85, "inputRadius1": 1.0, "inputColor0": CIColor.white, "inputColor1": CIColor.black])?.outputImage
        guard let mask else { throw CocoaError(.coderInvalidValue) }
        let oval = mask.transformed(by: CGAffineTransform(scaleX: rect.width / 2, y: rect.height / 2).concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY)))
        let head = image.applyingFilter("CIBlendWithMask", parameters: ["inputMaskImage": oval, "inputBackgroundImage": CIImage(color: .clear)]).cropped(to: rect)
        var wall = CIImage(color: CIColor(red: 0.12, green: 0.15, blue: 0.18)).cropped(to: e)
        let width = e.width / 4
        let height = width * rect.height / rect.width
        let rows = min(12, Int(ceil(e.height / max(1, height))) + 1)
        for row in 0..<rows {
            for column in 0..<5 {
                let transform = CGAffineTransform(translationX: -rect.minX, y: -rect.minY)
                    .concatenating(CGAffineTransform(scaleX: width / rect.width, y: width / rect.width))
                    .concatenating(CGAffineTransform(translationX: e.minX + CGFloat(column) * width - (row % 2 == 0 ? 0 : width / 2), y: e.minY + CGFloat(row) * height))
                wall = head.transformed(by: transform).composited(over: wall)
            }
        }
        return try WhisperWaveBackgroundRenderer.render(image, face: nil, settings: settings, background: wall.cropped(to: e), keyCube: nil, spillCube: nil, quality: quality)
    }
}
