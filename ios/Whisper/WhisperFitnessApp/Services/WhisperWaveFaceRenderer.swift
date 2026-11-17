import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// Re-detects landmarks on the requested frame, so seeking/export never reuse a different face or stale pose.
nonisolated enum WhisperWaveFaceRenderer {
    static func detect(_ image: CIImage, request: VNDetectFaceLandmarksRequest = VNDetectFaceLandmarksRequest()) throws -> [VNFaceObservation] {
        let extent = image.extent
        guard !extent.isInfinite, !extent.isNull, extent.width.isFinite, extent.height.isFinite,
              extent.width > 8, extent.height > 8 else { throw CocoaError(.coderInvalidValue) }
        let scale = min(1, 720 / max(extent.width, extent.height))
        let analysis = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale)))
        try VNImageRequestHandler(ciImage: analysis, options: [:]).perform([request])
        return Array((request.results ?? []).filter { $0.confidence >= 0.65 && abs($0.yaw?.doubleValue ?? 0) < 0.9 }.prefix(3))
    }

    static func render(_ image: CIImage, setting: WhisperWaveFaceSetting, observations: [VNFaceObservation]? = nil, frames: [WhisperARProcessor.FaceFrame]? = nil, preservesExtent: Bool = false, time: Double = 0, quality: WhisperWaveRenderQuality = .preview) throws -> CIImage {
        guard setting.isActive else { return image }
        let extent = image.extent
        let faces = try observations ?? detect(image)
        var output = image
        for face in faces {
            guard let landmarks = face.landmarks else { continue }
            let box = face.boundingBox
            func point(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
                guard let points = region?.normalizedPoints, !points.isEmpty else { return nil }
                let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
                return CGPoint(x: extent.minX + (box.minX + box.width * sum.x / CGFloat(points.count)) * extent.width,
                               y: extent.minY + (box.minY + box.height * sum.y / CGFloat(points.count)) * extent.height)
            }
            let faceRect = CGRect(x: extent.minX + box.minX * extent.width, y: extent.minY + box.minY * extent.height, width: box.width * extent.width, height: box.height * extent.height)
            if setting.clampedSmoothing > 0 {
                var mask = ellipse(faceRect.insetBy(dx: faceRect.width * 0.12, dy: faceRect.height * 0.05), extent: extent)
                // Preserve eyes, eyebrows and lips rather than blurring the entire face.
                for region in [landmarks.leftEye, landmarks.rightEye, landmarks.leftEyebrow, landmarks.rightEyebrow, landmarks.outerLips] {
                    guard let center = point(region) else { continue }
                    let width = faceRect.width * (region === landmarks.outerLips ? 0.5 : 0.32)
                    let exclusion = ellipse(CGRect(x: center.x - width / 2, y: center.y - width * 0.27, width: width, height: width * 0.54), extent: extent).applyingFilter("CIColorInvert")
                    mask = mask.applyingFilter("CIMultiplyCompositing", parameters: ["inputBackgroundImage": exclusion])
                }
                mask = mask.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: setting.clampedSmoothing * 0.65, y: 0, z: 0, w: 0)])
                let softened = output.applyingFilter("CINoiseReduction", parameters: ["inputNoiseLevel": 0.025 + setting.clampedSmoothing * 0.06, "inputSharpness": 0.5]).cropped(to: extent)
                output = blend(softened, over: output, mask: mask)
            }
            let strength = setting.clampedAmount
            switch setting.kind {
            case .bigEyes:
                for eye in [landmarks.leftEye, landmarks.rightEye] {
                    if let center = point(eye) { output = bump(output, center: center, radius: faceRect.width * 0.26, scale: strength * 0.7) }
                }
            case .bigMouth:
                if let center = point(landmarks.outerLips) { output = bump(output, center: center, radius: faceRect.width * 0.38, scale: strength * 0.65) }
            case .tinyNose:
                if let center = point(landmarks.nose) { output = bump(output, center: center, radius: faceRect.width * 0.24, scale: -strength * 0.5) }
            default: break
            }
        }
        if let accessory = setting.kind.accessory, setting.clampedAmount > 0 {
            let poses = frames ?? WhisperARProcessor.shared.faceFrames(faces, extent: extent)
            let decorated = try WhisperFace3DRenderer.shared.render(output, effect: accessory, frames: poses, time: time, quality: quality, preservesExtent: preservesExtent)
            if setting.clampedAmount >= 1 { output = decorated }
            else {
                let mask = CIImage(color: CIColor(red: setting.clampedAmount, green: setting.clampedAmount, blue: setting.clampedAmount)).cropped(to: preservesExtent ? decorated.extent : extent)
                output = blend(decorated, over: output, mask: mask)
            }
        }
        return preservesExtent ? output : output.cropped(to: extent)
    }

    private static func bump(_ image: CIImage, center: CGPoint, radius: CGFloat, scale: Double) -> CIImage {
        image.clampedToExtent().applyingFilter("CIBumpDistortion", parameters: ["inputCenter": CIVector(cgPoint: center), "inputRadius": max(1, radius), "inputScale": scale]).cropped(to: image.extent)
    }

    private static func ellipse(_ rect: CGRect, extent: CGRect) -> CIImage {
        let radial = CIFilter.radialGradient()
        radial.center = .zero
        radial.radius0 = 0.7
        radial.radius1 = 1
        radial.color0 = .white
        radial.color1 = .black
        let transform = CGAffineTransform(scaleX: max(1, rect.width / 2), y: max(1, rect.height / 2)).concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY))
        return (radial.outputImage ?? CIImage(color: .black)).transformed(by: transform).cropped(to: extent)
    }

    private static func blend(_ image: CIImage, over background: CIImage, mask: CIImage) -> CIImage {
        image.applyingFilter("CIBlendWithRedMask", parameters: ["inputBackgroundImage": background, "inputMaskImage": mask])
    }
}
