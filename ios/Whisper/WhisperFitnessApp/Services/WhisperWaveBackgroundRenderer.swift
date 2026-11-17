import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// On-device cutout. A required matte or background failing is an error, never an unedited-room fallback.
nonisolated enum WhisperWaveBackgroundRenderer {
    static func render(_ input: CIImage, subject: WhisperWaveSubjectFrame, background: CIImage?, quality: WhisperWaveRenderQuality, time: Double = 0) throws -> CIImage {
        try render(input, face: subject.face, settings: subject.background, background: background, keyCube: subject.keyCube, spillCube: subject.spillCube, quality: quality, time: time)
    }

    static func render(_ input: CIImage, face faceSetting: WhisperWaveFaceSetting?, settings: WhisperWaveBackground?, background: CIImage?, keyCube: Data?, spillCube: Data?, quality: WhisperWaveRenderQuality, observations suppliedObservations: [VNFaceObservation]? = nil, frames: [WhisperARProcessor.FaceFrame]? = nil, segmentationRequest: VNGeneratePersonSegmentationRequest? = nil, time: Double = 0) throws -> CIImage {
        let observations = try suppliedObservations ?? (faceSetting?.isActive == true ? WhisperWaveFaceRenderer.detect(input) : [])
        var foreground = input
        if var face = faceSetting {
            // Accessories are added after cutout so ears/halos aren't erased by the person matte.
            if face.kind.accessory != nil { face.kind = .none }
            foreground = try WhisperWaveFaceRenderer.render(foreground, setting: face, observations: observations)
        }
        guard let settings else {
            if let face = faceSetting, face.kind.accessory != nil { return try WhisperWaveFaceRenderer.render(foreground, setting: face.accessoryOnly, observations: observations, frames: frames, time: time, quality: quality) }
            return foreground
        }
        let extent = input.extent
        guard let background else { throw failure("The green screen background couldn't be read. Replace it or retry; nothing was posted.") }
        var mask: CIImage
        if settings.removal == .person {
            let request = segmentationRequest ?? VNGeneratePersonSegmentationRequest()
            request.qualityLevel = .balanced
            request.outputPixelFormat = kCVPixelFormatType_OneComponent8
            let factor = min(1, (quality == .preview ? 640 : 1280) / max(extent.width, extent.height))
            let analysis = foreground.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
            do { try VNImageRequestHandler(ciImage: analysis, options: [:]).perform([request]) }
            catch { throw failure("Person cutout couldn't process a frame. Try Color key or retry the preview.") }
            guard let buffer = request.results?.first?.pixelBuffer else { throw failure("Person cutout couldn't create a mask. Your original clip is safe.") }
            let raw = CIImage(cvPixelBuffer: buffer)
            mask = raw.transformed(by: CGAffineTransform(scaleX: extent.width / raw.extent.width, y: extent.height / raw.extent.height)).transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
        } else {
            guard let keyCube else { throw failure("The selected key color couldn't be prepared.") }
            mask = foreground.applyingFilter("CIColorCube", parameters: ["inputCubeDimension": 32, "inputCubeData": keyCube])
            if let spillCube { foreground = foreground.applyingFilter("CIColorCube", parameters: ["inputCubeDimension": 32, "inputCubeData": spillCube]) }
        }
        let cleanup = WhisperWaveBackground.bounded(settings.edge, -1...1) * extent.width / 180
        if abs(cleanup) > 0.01 {
            mask = mask.clampedToExtent().applyingFilter(cleanup > 0 ? "CIMorphologyMinimum" : "CIMorphologyMaximum", parameters: ["inputRadius": abs(cleanup)]).cropped(to: extent)
        }
        let feather = WhisperWaveBackground.bounded(settings.feather, 0...1) * extent.width / 150
        if feather > 0 { mask = mask.clampedToExtent().applyingGaussianBlur(sigma: feather).cropped(to: extent) }
        // Outside a fitted clip is transparent, not an opaque black rectangle.
        let alpha = input.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 0, y: 0, z: 0, w: 1), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1), "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 1), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)])
        mask = mask.applyingFilter("CIMultiplyCompositing", parameters: ["inputBackgroundImage": alpha])
        let clear = CIImage(color: .clear).cropped(to: extent)
        foreground = foreground.applyingFilter("CIBlendWithRedMask", parameters: ["inputMaskImage": mask, "inputBackgroundImage": clear]).cropped(to: extent)
        if let face = faceSetting, face.kind.accessory != nil {
            foreground = try WhisperWaveFaceRenderer.render(foreground, setting: face.accessoryOnly, observations: observations, frames: frames, preservesExtent: true, time: time, quality: quality)
        }
        let scale = WhisperWaveBackground.bounded(settings.subjectScale, 0.25...1.5, fallback: 1)
        let x = WhisperWaveBackground.bounded(settings.subjectX, -0.7...0.7) * extent.width
        let y = -WhisperWaveBackground.bounded(settings.subjectY, -0.7...0.7) * extent.height
        let transform = CGAffineTransform(translationX: -extent.midX, y: -extent.midY).concatenating(CGAffineTransform(scaleX: scale, y: scale)).concatenating(CGAffineTransform(translationX: extent.midX + x, y: extent.midY + y))
        return foreground.transformed(by: transform).composited(over: background).cropped(to: extent)
    }

    static func fitPhoto(_ image: CIImage, settings: WhisperWaveBackground, canvas: CGRect) -> CIImage {
        let extent = image.extent
        let scale = max(canvas.width / extent.width, canvas.height / extent.height) * WhisperWaveBackground.bounded(settings.zoom, 1...3, fallback: 1)
        let overflowX = max(0, (extent.width * scale - canvas.width) / 2)
        let overflowY = max(0, (extent.height * scale - canvas.height) / 2)
        let x = min(overflowX, max(-overflowX, WhisperWaveBackground.bounded(settings.x, -1...1) * canvas.width))
        let y = -min(overflowY, max(-overflowY, WhisperWaveBackground.bounded(settings.y, -1...1) * canvas.height))
        let transform = CGAffineTransform(translationX: -extent.midX, y: -extent.midY).concatenating(CGAffineTransform(scaleX: scale, y: scale)).concatenating(CGAffineTransform(translationX: canvas.midX + x, y: canvas.midY + y))
        return image.transformed(by: transform).cropped(to: canvas).composited(over: CIImage(color: .black).cropped(to: canvas))
    }

    /// Brightness-normalized color distance; cubes are built once per edit, not per video frame.
    static func cubes(_ settings: WhisperWaveBackground) -> (mask: Data, spill: Data) {
        let red = linearKeyComponent(settings.keyRed)
        let green = linearKeyComponent(settings.keyGreen)
        let blue = linearKeyComponent(settings.keyBlue)
        let total = max(0.001, red + green + blue)
        let key = [red / total, green / total, blue / total]
        let threshold = 0.02 + WhisperWaveBackground.bounded(settings.tolerance, 0...1) * 0.7
        let softness = 0.03 + WhisperWaveBackground.bounded(settings.feather, 0...1) * 0.12
        let spill = WhisperWaveBackground.bounded(settings.spill, 0...1)
        let dominant = green >= max(red, blue) ? 1 : (blue >= red ? 2 : 0)
        var matte: [Float] = []; matte.reserveCapacity(32 * 32 * 32 * 4)
        var color: [Float] = []; color.reserveCapacity(32 * 32 * 32 * 4)
        for b in 0..<32 { for g in 0..<32 { for r in 0..<32 {
            var rgb = [Double(r) / 31, Double(g) / 31, Double(b) / 31]
            let sum = max(0.001, rgb.reduce(0, +))
            let distance = sqrt(zip(rgb, key).reduce(0.0) { $0 + pow($1.0 / sum - $1.1, 2) })
            let t = min(1, max(0, (distance - threshold) / softness))
            let keep = t * t * (3 - 2 * t)
            matte.append(contentsOf: [Float(keep), Float(keep), Float(keep), 1])
            let other = rgb.enumerated().filter { $0.offset != dominant }.map(\.element).max() ?? 0
            rgb[dominant] -= max(0, rgb[dominant] - other) * spill * max(0, 1 - distance / (threshold + softness + 0.2))
            color.append(contentsOf: [Float(rgb[0]), Float(rgb[1]), Float(rgb[2]), 1])
        } } }
        return (matte.withUnsafeBytes { Data($0) }, color.withUnsafeBytes { Data($0) })
    }

    static func linearKeyComponent(_ value: Double) -> Double {
        let v = WhisperWaveBackground.bounded(value, 0...1)
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "WhisperWaveEdit", code: 20, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
