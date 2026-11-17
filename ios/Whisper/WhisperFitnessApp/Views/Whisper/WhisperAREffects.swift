import SwiftUI
import UIKit
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

// MARK: - Catalog

/// The AR EFFECTS for waves — Instagram's face + background filters, done
/// Whisper's way. Two families, one pipeline:
///
/// - BACKGROUND effects run Vision's person segmentation every frame and
///   swap what's behind you: a soft blur, the Ghost Room (the Whisper brand
///   gradient), or a dark Studio.
/// - FACE effects use Vision landmarks and head pose with original Metal 3D
///   accessories: Puppy, Bunny, Sunnies and Halo. The stable catalog IDs also
///   upgrade editable legacy recipes; baked media is never rewritten.
///
/// The SAME `WhisperARProcessor.render` serves the live viewfinder (down-
/// scaled, fast segmentation) and the publish bake (full frame, balanced
/// segmentation). Story/Waves use the shared tracked compositor for capture/export.
enum WhisperAREffect: String, CaseIterable, Identifiable, Hashable {
    case none
    case blur, ghostRoom, studio
    case puppy, bunny, sunnies, halo

    static var available: [Self] { [.none, .blur, .ghostRoom, .studio] }
    nonisolated var availableEffect: Self { isFace ? .none : self }

    var id: String { rawValue }

    var name: String {
        switch self {
        case .none: return "None"
        case .blur: return "Blur"
        case .ghostRoom: return "Ghost room"
        case .studio: return "Studio"
        case .puppy: return "Puppy"
        case .bunny: return "Bunny"
        case .sunnies: return "Sunnies"
        case .halo: return "Halo"
        }
    }

    /// The glyph on the Effects tray tile.
    var glyph: String {
        switch self {
        case .none: return "✕"
        case .blur: return "🫧"
        case .ghostRoom: return "👻"
        case .studio: return "🎬"
        case .puppy: return "🐶"
        case .bunny: return "🐰"
        case .sunnies: return "🕶️"
        case .halo: return "😇"
        }
    }

    nonisolated var isBackground: Bool {
        switch self {
        case .blur, .ghostRoom, .studio: return true
        default: return false
        }
    }

    nonisolated var isFace: Bool {
        switch self {
        case .puppy, .bunny, .sunnies, .halo: return true
        default: return false
        }
    }

    /// Tile tint for the tray.
    var tint: [Color] {
        switch self {
        case .none: return [Color(white: 0.30), Color(white: 0.12)]
        case .blur: return [Color(red: 0.55, green: 0.75, blue: 0.95), Color(red: 0.25, green: 0.35, blue: 0.65)]
        case .ghostRoom: return WhisperBrandGradient.colors
        case .studio: return [Color(white: 0.28), Color(white: 0.05)]
        case .puppy: return [Color(red: 0.75, green: 0.52, blue: 0.30), Color(red: 0.42, green: 0.25, blue: 0.12)]
        case .bunny: return [Color(red: 0.98, green: 0.85, blue: 0.90), Color(red: 0.85, green: 0.55, blue: 0.70)]
        case .sunnies: return [Color(red: 0.35, green: 0.35, blue: 0.40), Color(red: 0.05, green: 0.05, blue: 0.08)]
        case .halo: return [Color(red: 0.95, green: 0.90, blue: 0.55), WhisperBrandGradient.mint]
        }
    }
}

// MARK: - Processor

/// Vision/Core Image backgrounds and pose extraction, with Metal 3D accessories.
/// Reusable Vision requests are serialized; catalog images contain no camera data.
nonisolated final class WhisperARProcessor: @unchecked Sendable {
    static let shared = WhisperARProcessor()

    enum Quality {
        /// Live viewfinder — fast segmentation on a half-size frame.
        case live
        /// Publish bake — balanced segmentation on the full frame.
        case export
    }

    private let lock = NSLock()
    private let fastSegmentation: VNGeneratePersonSegmentationRequest
    private let balancedSegmentation: VNGeneratePersonSegmentationRequest
    private let landmarks: VNDetectFaceLandmarksRequest
    private var art: [String: CIImage] = [:]

    private init() {
        fastSegmentation = VNGeneratePersonSegmentationRequest()
        fastSegmentation.qualityLevel = .fast
        fastSegmentation.outputPixelFormat = kCVPixelFormatType_OneComponent8
        balancedSegmentation = VNGeneratePersonSegmentationRequest()
        balancedSegmentation.qualityLevel = .balanced
        balancedSegmentation.outputPixelFormat = kCVPixelFormatType_OneComponent8
        landmarks = VNDetectFaceLandmarksRequest()
    }

    /// Renders one frame with the effect. Returns the input untouched for
    /// `.none` or when Vision finds nothing to work with.
    func render(_ input: CIImage, effect: WhisperAREffect, quality: Quality, time: Double = 0) throws -> CIImage {
        guard effect != .none else { return input }
        let extent = input.extent
        guard extent.width > 8, extent.height > 8 else { return input }
        lock.lock()
        defer { lock.unlock() }
        if effect.isBackground {
            return renderBackground(input, effect: effect, quality: quality) ?? input
        }
        if effect.isFace {
            let faces = try WhisperWaveFaceRenderer.detect(input, request: landmarks)
            return try decorate(input, effect: effect, faces: faces, time: time, quality: quality == .live ? .preview : .final)
        }
        return input
    }

    /// The person matte for the AI wave effects: white where Vision sees a
    /// person, black elsewhere, resampled to the frame and softened at the
    /// edge. Nil when Vision finds nobody or the request fails. Serialized
    /// on the same lock as `render` because the Vision requests are reused.
    func personMask(_ image: CIImage, quality: Quality) -> CIImage? {
        let extent = image.extent
        guard extent.width > 8, extent.height > 8 else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return matte(image, quality: quality)
    }

    // MARK: Background

    /// Runs person segmentation and returns the frame-sized, edge-softened
    /// matte. Callers hold `lock`.
    private func matte(_ image: CIImage, quality: Quality) -> CIImage? {
        let extent = image.extent
        let request = quality == .live ? fastSegmentation : balancedSegmentation
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        guard let maskBuffer = request.results?.first?.pixelBuffer else { return nil }
        var mask = CIImage(cvPixelBuffer: maskBuffer)
        let sx = extent.width / mask.extent.width
        let sy = extent.height / mask.extent.height
        mask = mask.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .transformed(by: CGAffineTransform(translationX: extent.origin.x - mask.extent.origin.x * sx, y: extent.origin.y - mask.extent.origin.y * sy))
        // Soften the matte edge a touch so hair doesn't cut like paper.
        return mask.clampedToExtent().applyingGaussianBlur(sigma: quality == .live ? 1.5 : 2.5).cropped(to: extent)
    }

    private func renderBackground(_ image: CIImage, effect: WhisperAREffect, quality: Quality) -> CIImage? {
        let extent = image.extent
        guard let mask = matte(image, quality: quality) else { return nil }

        let background: CIImage
        switch effect {
        case .blur:
            let blurred = image.clampedToExtent().applyingGaussianBlur(sigma: quality == .live ? 14 : 26).cropped(to: extent)
            background = colorControls(blurred, saturation: 0.9, brightness: -0.04, contrast: 1.0)
        case .ghostRoom:
            background = ghostRoom(extent: extent, base: image, live: quality == .live)
        case .studio:
            background = studio(extent: extent)
        default:
            return nil
        }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = image
        blend.backgroundImage = background
        blend.maskImage = mask
        return blend.outputImage?.cropped(to: extent)
    }

    /// The Whisper brand gradient as a room — mint → emerald → indigo
    /// diagonally, with the blurred, desaturated real room ghosting through
    /// at ~30% so the space still has depth.
    private func ghostRoom(extent: CGRect, base: CIImage, live: Bool) -> CIImage {
        let top = CIFilter.linearGradient()
        top.color0 = CIColor(red: 0.608, green: 0.910, blue: 0.769)
        top.color1 = CIColor(red: 0.055, green: 0.624, blue: 0.463)
        top.point0 = CGPoint(x: extent.minX, y: extent.maxY)
        top.point1 = CGPoint(x: extent.midX, y: extent.midY)
        let bottom = CIFilter.linearGradient()
        bottom.color0 = CIColor(red: 0.055, green: 0.624, blue: 0.463)
        bottom.color1 = CIColor(red: 0.353, green: 0.373, blue: 0.910)
        bottom.point0 = CGPoint(x: extent.midX, y: extent.midY)
        bottom.point1 = CGPoint(x: extent.maxX, y: extent.minY)
        let upper = (top.outputImage ?? CIImage(color: CIColor(red: 0.06, green: 0.6, blue: 0.45))).cropped(to: extent)
        let lower = (bottom.outputImage ?? CIImage(color: CIColor(red: 0.35, green: 0.37, blue: 0.91))).cropped(to: extent)
        // Split the two halves along the diagonal with a soft mask.
        let diag = CIFilter.linearGradient()
        diag.color0 = CIColor(red: 1, green: 1, blue: 1)
        diag.color1 = CIColor(red: 0, green: 0, blue: 0)
        diag.point0 = CGPoint(x: extent.minX + extent.width * 0.35, y: extent.maxY - extent.height * 0.35)
        diag.point1 = CGPoint(x: extent.minX + extent.width * 0.65, y: extent.maxY - extent.height * 0.65)
        let diagMask = (diag.outputImage ?? CIImage(color: CIColor(red: 1, green: 1, blue: 1))).cropped(to: extent)
        let merge = CIFilter.blendWithMask()
        merge.inputImage = upper
        merge.backgroundImage = lower
        merge.maskImage = diagMask
        let gradient = (merge.outputImage ?? upper).cropped(to: extent)

        // Ghost the real room through at low alpha.
        let softRoom = colorControls(
            base.clampedToExtent().applyingGaussianBlur(sigma: live ? 12 : 22).cropped(to: extent),
            saturation: 0.35, brightness: 0.0, contrast: 1.05
        )
        let faded = alpha(softRoom, 0.30)
        let composite = faded.composited(over: gradient).cropped(to: extent)
        return vignette(composite, intensity: 0.6, radius: 1.8)
    }

    /// A near-black studio backdrop with one soft key light from the top.
    private func studio(extent: CGRect) -> CIImage {
        let base = CIImage(color: CIColor(red: 0.07, green: 0.07, blue: 0.085)).cropped(to: extent)
        let key = CIFilter.radialGradient()
        key.center = CGPoint(x: extent.midX, y: extent.maxY - extent.height * 0.12)
        key.radius0 = 0
        key.radius1 = Float(extent.height * 0.75)
        key.color0 = CIColor(red: 0.28, green: 0.29, blue: 0.33, alpha: 1)
        key.color1 = CIColor(red: 0.07, green: 0.07, blue: 0.085, alpha: 1)
        let lit = (key.outputImage ?? base).cropped(to: extent)
        return lit.composited(over: base).cropped(to: extent)
    }

    // MARK: Face

    struct FaceFrame: Sendable {
        let eyeMid: CGPoint
        let eyeDistance: CGFloat
        let angle: CGFloat
        let up: CGVector
        let faceWidth: CGFloat
        let faceHeight: CGFloat
        let noseTip: CGPoint
        let mouth: CGPoint
        let mouthOpening: CGFloat
        var yaw: CGFloat = 0
        var pitch: CGFloat = 0
    }

    func decorate(_ image: CIImage, effect: WhisperAREffect, faces: [VNFaceObservation], frames: [FaceFrame]? = nil, preservesExtent: Bool = false, time: Double = 0, quality: WhisperWaveRenderQuality = .preview) throws -> CIImage {
        try WhisperFace3DRenderer.shared.render(image, effect: effect, frames: frames ?? faceFrames(faces, extent: image.extent), time: time, quality: quality, preservesExtent: preservesExtent)
    }

    func faceFrames(_ faces: [VNFaceObservation], extent: CGRect) -> [FaceFrame] {
        faces.prefix(3).compactMap { faceFrame($0, extent: extent) }
    }

    /// Smooth expression activation, normalized to eye spacing and independent of resolution.
    static func puppyTongueAmount(opening: CGFloat) -> CGFloat {
        let t = min(1, max(0, (opening - 0.045) / 0.16))
        return t * t * (3 - 2 * t)
    }

    /// Eye centers → roll angle, the face's up vector, and anchors, all in
    /// CIImage coordinates (origin bottom-left, y up).
    private func faceFrame(_ face: VNFaceObservation, extent: CGRect) -> FaceFrame? {
        guard let lm = face.landmarks, let left = lm.leftEye, let right = lm.rightEye,
              left.pointCount > 0, right.pointCount > 0 else { return nil }
        let size = CGSize(width: extent.width, height: extent.height)
        let l = centroid(left.pointsInImage(imageSize: size))
        let r = centroid(right.pointsInImage(imageSize: size))
        let roll = CGFloat(face.roll?.doubleValue ?? atan2(r.y-l.y, r.x-l.x))
        let eyeCenter = CGPoint(x: (l.x+r.x)/2, y: (l.y+r.y)/2)
        let mouthReference = lm.outerLips.flatMap { $0.pointCount > 0 ? centroid($0.pointsInImage(imageSize: size)) : nil }
            ?? CGPoint(x: eyeCenter.x + sin(roll)*hypot(r.x-l.x,r.y-l.y), y: eyeCenter.y-cos(roll)*hypot(r.x-l.x,r.y-l.y))
        guard let basis = WhisperFaceBasis(left: l, right: r, mouth: mouthReference) else { return nil }
        let eyeDistance = basis.distance
        let angle = basis.angle
        let up = basis.up
        let eyeMid = CGPoint(x: (l.x + r.x) / 2 + extent.origin.x, y: (l.y + r.y) / 2 + extent.origin.y)
        // Eye-relative sizing doesn't inflate when the axis-aligned face box rotates.
        let faceWidth = eyeDistance * 2.35
        let faceHeight = eyeDistance * 2.95
        let noseTip: CGPoint
        let noseRegion = [lm.noseCrest, lm.nose].compactMap { $0 }.first { $0.pointCount > 0 }
        if let nose = noseRegion {
            let pts = nose.pointsInImage(imageSize: size)
            // The lowest point of the nose crest is the tip.
            let tip = pts.min(by: { $0.x * up.dx + $0.y * up.dy < $1.x * up.dx + $1.y * up.dy }) ?? centroid(pts)
            noseTip = CGPoint(x: tip.x + extent.origin.x, y: tip.y + extent.origin.y)
        } else {
            noseTip = offset(eyeMid, along: up, by: -eyeDistance * 0.62)
        }
        let mouth: CGPoint
        if let lips = lm.outerLips, lips.pointCount > 0 {
            let c = centroid(lips.pointsInImage(imageSize: size))
            mouth = CGPoint(x: c.x + extent.origin.x, y: c.y + extent.origin.y)
        } else {
            mouth = offset(eyeMid, along: up, by: -eyeDistance * 1.25)
        }
        let lipHeights = lm.innerLips?.pointsInImage(imageSize: size).map { $0.x * up.dx + $0.y * up.dy } ?? []
        let mouthOpening = min(1, max(0, ((lipHeights.max() ?? 0) - (lipHeights.min() ?? 0)) / eyeDistance))
        guard [noseTip.x, noseTip.y, mouth.x, mouth.y, mouthOpening].allSatisfy(\.isFinite) else { return nil }
        let yaw = CGFloat(face.yaw?.doubleValue ?? 0)
        let pitch = CGFloat(face.pitch?.doubleValue ?? 0)
        return FaceFrame(eyeMid: eyeMid, eyeDistance: eyeDistance, angle: angle, up: up,
                         faceWidth: faceWidth, faceHeight: faceHeight, noseTip: noseTip, mouth: mouth, mouthOpening: mouthOpening,
                         yaw: yaw.isFinite ? min(0.9, max(-0.9, yaw)) : 0,
                         pitch: pitch.isFinite ? min(0.65, max(-0.65, pitch)) : 0)
    }

    private func centroid(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    private func offset(_ p: CGPoint, along v: CGVector, by d: CGFloat) -> CGPoint {
        CGPoint(x: p.x + v.dx * d, y: p.y + v.dy * d)
    }

    /// Places accessory art: local offset (anchor point inside the art as a
    /// fraction of its height, from the bottom) → scale to `width` → rotate
    /// by the face roll → move to `anchor`. Composited over the frame.
    private func place(_ art: CIImage, on image: CIImage, anchor: CGPoint, width: CGFloat, angle: CGFloat, anchorY: CGFloat) -> CIImage {
        let w = art.extent.width
        let h = art.extent.height
        guard w > 0, h > 0 else { return image }
        let s = width / w
        var t = CGAffineTransform(translationX: anchor.x, y: anchor.y)
        t = t.rotated(by: angle)
        t = t.scaledBy(x: s, y: s)
        t = t.translatedBy(x: -w / 2, y: -h * anchorY)
        return art.transformed(by: t).composited(over: image)
    }

    // MARK: Accessory art (drawn once, cached)

    private let artworkLock = NSLock()
    private let iconLock = NSLock()
    private let iconContext = CIContext(options: [.cacheIntermediates: false])
    private var iconCache: [String: CGImage] = [:]
    /// Uses the actual accessory geometry on a neutral 3D display bust.
    /// No captured face or private background is used for these catalog icons.
    func accessoryIcon(_ effect: WhisperAREffect) -> CGImage? {
        guard effect.isFace else { return nil }
        iconLock.lock(); defer { iconLock.unlock() }
        let cacheKey = effect.rawValue + "-3d-v2"
        if let icon = iconCache[cacheKey] { return icon }
        let size = CGSize(width: 240, height: 240)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            WhisperCameraEffectPortrait.draw(ctx.cgContext, size: size, effect: effect)
        }
        guard let source = image.cgImage else { return nil }
        let frame = FaceFrame(eyeMid: CGPoint(x: 120, y: 110), eyeDistance: 41, angle: 0,
            up: CGVector(dx: 0, dy: 1), faceWidth: 112, faceHeight: 137,
            noseTip: CGPoint(x: 120, y: 89), mouth: CGPoint(x: 120, y: 67), mouthOpening: 0.22)
        guard let output = try? WhisperFace3DRenderer.shared.render(CIImage(cgImage: source), effect: effect, frames: [frame], time: 0.6, quality: .preview, includesPortrait: true) else { return nil }
        // Live accessories may extend beyond the source before person cutout;
        // the picker still has a fixed square canvas and must not inherit that extent.
        let icon = iconContext.createCGImage(output, from: CGRect(origin: .zero, size: size))
        iconCache[cacheKey] = icon
        return icon
    }

    private func artNamed(_ key: String, draw: @escaping (CGContext, CGSize) -> Void) -> CIImage {
        artworkLock.lock(); defer { artworkLock.unlock() }
        if let cached = art[key] { return cached }
        let size = CGSize(width: 720, height: 480)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in draw(ctx.cgContext, size) }
        let ci = image.cgImage.map { CIImage(cgImage: $0) } ?? CIImage.empty()
        art[key] = ci
        return ci
    }

    /// Floppy puppy ears — two soft brown teardrops hanging from the head's
    /// top corners with lighter inner ears.
    private static func drawPuppyEars(_ c: CGContext, _ size: CGSize) {
        let brown = UIColor(red: 0.47, green: 0.29, blue: 0.14, alpha: 1)
        let inner = UIColor(red: 0.78, green: 0.56, blue: 0.36, alpha: 1)
        func ear(x: CGFloat, flip: Bool) {
            c.saveGState()
            c.translateBy(x: x, y: size.height * 0.10)
            if flip { c.scaleBy(x: -1, y: 1) }
            c.rotate(by: -0.28)
            let outer = UIBezierPath()
            outer.move(to: CGPoint(x: -40, y: 10))
            outer.addCurve(to: CGPoint(x: -105, y: 340), controlPoint1: CGPoint(x: -125, y: 40), controlPoint2: CGPoint(x: -155, y: 240))
            outer.addCurve(to: CGPoint(x: 78, y: 345), controlPoint1: CGPoint(x: -80, y: 440), controlPoint2: CGPoint(x: 90, y: 440))
            outer.addCurve(to: CGPoint(x: 65, y: 60), controlPoint1: CGPoint(x: 110, y: 265), controlPoint2: CGPoint(x: 145, y: 95))
            outer.addQuadCurve(to: CGPoint(x: -40, y: 10), controlPoint: CGPoint(x: 10, y: -15))
            outer.close()
            c.setShadow(offset: CGSize(width: 0, height: 8), blur: 12, color: UIColor.black.withAlphaComponent(0.45).cgColor)
            brown.setFill(); outer.fill()
            c.saveGState(); outer.addClip()
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [UIColor(red: 0.32, green: 0.18, blue: 0.09, alpha: 1).cgColor, brown.cgColor, UIColor(red: 0.68, green: 0.44, blue: 0.24, alpha: 1).cgColor] as CFArray, locations: [0, 0.45, 1]) {
                c.drawLinearGradient(gradient, start: CGPoint(x: -90, y: 250), end: CGPoint(x: 80, y: 100), options: [])
            }
            c.restoreGState()
            c.setShadow(offset: .zero, blur: 0, color: nil)
            UIColor(red: 0.25, green: 0.12, blue: 0.06, alpha: 1).setStroke()
            outer.lineWidth = 7; outer.stroke()
            let innerPath = UIBezierPath(ovalIn: CGRect(x: -52, y: 82, width: 104, height: 278))
            inner.setFill(); innerPath.fill()
            let highlight = UIBezierPath(ovalIn: CGRect(x: -56, y: 52, width: 28, height: 168))
            UIColor(red: 0.94, green: 0.72, blue: 0.47, alpha: 0.65).setFill(); highlight.fill()
            c.restoreGState()
        }
        ear(x: size.width * 0.18, flip: false)
        ear(x: size.width * 0.82, flip: true)
    }

    /// Puppy nose (black, glossy) with a tongue hanging beneath.
    private static func drawPuppyNose(_ c: CGContext, _ size: CGSize) {
        let cx = size.width / 2
        c.setShadow(offset: CGSize(width: 0, height: 6), blur: 10, color: UIColor.black.withAlphaComponent(0.35).cgColor)
        for x in [cx - 180, cx + 20] {
            let muzzle = UIBezierPath(ovalIn: CGRect(x: x, y: size.height * 0.36, width: 160, height: 120))
            UIColor(red: 0.89, green: 0.72, blue: 0.50, alpha: 1).setFill(); muzzle.fill()
        }
        c.setShadow(offset: .zero, blur: 0, color: nil)
        // Nose — a wide rounded shape with a soft bottom point
        let nose = UIBezierPath()
        nose.move(to: CGPoint(x: cx - 150, y: size.height * 0.30))
        nose.addQuadCurve(to: CGPoint(x: cx + 150, y: size.height * 0.30), controlPoint: CGPoint(x: cx, y: size.height * 0.02))
        nose.addQuadCurve(to: CGPoint(x: cx, y: size.height * 0.66), controlPoint: CGPoint(x: cx + 150, y: size.height * 0.60))
        nose.addQuadCurve(to: CGPoint(x: cx - 150, y: size.height * 0.30), controlPoint: CGPoint(x: cx - 150, y: size.height * 0.60))
        nose.close()
        UIColor(red: 0.08, green: 0.07, blue: 0.08, alpha: 1).setFill(); nose.fill()
        let gloss = UIBezierPath(ovalIn: CGRect(x: cx - 90, y: size.height * 0.22, width: 70, height: 36))
        UIColor.white.withAlphaComponent(0.55).setFill(); gloss.fill()
    }

    private static func drawPuppyTongue(_ c: CGContext, _ size: CGSize) {
        let rect = CGRect(x: size.width * 0.30, y: 40, width: size.width * 0.40, height: 370)
        let tongue = UIBezierPath(roundedRect: rect, cornerRadius: 125)
        c.setShadow(offset: CGSize(width: 0, height: 5), blur: 9, color: UIColor.black.withAlphaComponent(0.3).cgColor)
        UIColor(red: 1, green: 0.43, blue: 0.56, alpha: 1).setFill(); tongue.fill()
        c.setShadow(offset: .zero, blur: 0, color: nil)
        tongue.lineWidth = 8
        UIColor(red: 0.71, green: 0.18, blue: 0.30, alpha: 1).setStroke(); tongue.stroke()
        let crease = UIBezierPath()
        crease.move(to: CGPoint(x: size.width / 2, y: 65)); crease.addLine(to: CGPoint(x: size.width / 2, y: 325))
        crease.lineWidth = 10; crease.lineCapStyle = .round; crease.stroke()
    }

    /// Tall bunny ears with pink inner ears.
    private static func drawBunnyEars(_ c: CGContext, _ size: CGSize) {
        let fur = UIColor(red: 0.98, green: 0.97, blue: 0.96, alpha: 1)
        let pink = UIColor(red: 0.99, green: 0.72, blue: 0.80, alpha: 1)
        func ear(x: CGFloat, tilt: CGFloat) {
            c.saveGState()
            c.translateBy(x: x, y: size.height * 0.98)
            c.rotate(by: tilt)
            let outer = UIBezierPath(ovalIn: CGRect(x: -70, y: -470, width: 140, height: 470))
            c.setShadow(offset: CGSize(width: 0, height: 4), blur: 12, color: UIColor.black.withAlphaComponent(0.22).cgColor)
            fur.setFill(); outer.fill()
            c.setShadow(offset: .zero, blur: 0, color: nil)
            c.saveGState(); outer.addClip()
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [UIColor(white: 0.78, alpha: 1).cgColor, fur.cgColor, UIColor.white.cgColor] as CFArray, locations: [0, 0.35, 1]) {
                c.drawLinearGradient(gradient, start: CGPoint(x: -70, y: -200), end: CGPoint(x: 70, y: -200), options: [])
            }
            c.restoreGState()
            let innerPath = UIBezierPath(ovalIn: CGRect(x: -38, y: -420, width: 76, height: 360))
            pink.setFill(); innerPath.fill()
            c.saveGState(); innerPath.addClip()
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [UIColor(red: 0.79, green: 0.39, blue: 0.49, alpha: 1).cgColor, pink.cgColor] as CFArray, locations: [0, 1]) {
                c.drawLinearGradient(gradient, start: CGPoint(x: -38, y: -220), end: CGPoint(x: 38, y: -220), options: [])
            }
            c.restoreGState()
            c.restoreGState()
        }
        ear(x: size.width * 0.36, tilt: -0.16)
        ear(x: size.width * 0.64, tilt: 0.16)
    }

    /// Bunny nose + whiskers.
    private static func drawBunnyNose(_ c: CGContext, _ size: CGSize) {
        let cx = size.width / 2
        let cy = size.height / 2
        UIColor(red: 0.98, green: 0.97, blue: 0.96, alpha: 0.95).setStroke()
        for (i, dy) in [-34.0, 0.0, 34.0].enumerated() {
            let curve: CGFloat = CGFloat(i - 1) * 22
            for dir in [-1.0, 1.0] {
                let p = UIBezierPath()
                p.move(to: CGPoint(x: cx + CGFloat(dir) * 60, y: cy + CGFloat(dy)))
                p.addQuadCurve(
                    to: CGPoint(x: cx + CGFloat(dir) * 330, y: cy + CGFloat(dy) + curve),
                    controlPoint: CGPoint(x: cx + CGFloat(dir) * 200, y: cy + CGFloat(dy) - 8)
                )
                p.lineWidth = 9
                p.lineCapStyle = .round
                p.stroke()
            }
        }
        let nose = UIBezierPath()
        nose.move(to: CGPoint(x: cx - 62, y: cy - 30))
        nose.addLine(to: CGPoint(x: cx + 62, y: cy - 30))
        nose.addQuadCurve(to: CGPoint(x: cx, y: cy + 58), controlPoint: CGPoint(x: cx + 62, y: cy + 40))
        nose.addQuadCurve(to: CGPoint(x: cx - 62, y: cy - 30), controlPoint: CGPoint(x: cx - 62, y: cy + 40))
        nose.close()
        UIColor(red: 0.96, green: 0.52, blue: 0.64, alpha: 1).setFill(); nose.fill()
    }

    /// Black wayfarer sunnies with a reflection streak.
    private static func drawSunnies(_ c: CGContext, _ size: CGSize) {
        let cy = size.height / 2
        let black = UIColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1)
        func lens(x: CGFloat) {
            let frame = UIBezierPath(roundedRect: CGRect(x: x - 150, y: cy - 95, width: 300, height: 200), cornerRadius: 58)
            black.setFill(); frame.fill()
            let glass = UIBezierPath(roundedRect: CGRect(x: x - 134, y: cy - 80, width: 268, height: 170), cornerRadius: 50)
            UIColor(red: 0.12, green: 0.13, blue: 0.18, alpha: 1).setFill(); glass.fill()
            let streak = UIBezierPath()
            streak.move(to: CGPoint(x: x - 100, y: cy + 60))
            streak.addLine(to: CGPoint(x: x - 20, y: cy - 60))
            streak.lineWidth = 22
            streak.lineCapStyle = .round
            UIColor.white.withAlphaComponent(0.22).setStroke(); streak.stroke()
        }
        lens(x: size.width * 0.27)
        lens(x: size.width * 0.73)
        let bridge = UIBezierPath(roundedRect: CGRect(x: size.width * 0.27 + 140, y: cy - 30, width: size.width * 0.46 - 280, height: 40), cornerRadius: 20)
        black.setFill(); bridge.fill()
    }

    /// The Jasper halo — a mint→gold ring with a soft glow and three sparkles.
    private static func drawHalo(_ c: CGContext, _ size: CGSize) {
        let cx = size.width / 2
        let cy = size.height / 2
        let ring = UIBezierPath(ovalIn: CGRect(x: cx - 300, y: cy - 70, width: 600, height: 140))
        c.saveGState()
        c.setShadow(offset: .zero, blur: 40, color: UIColor(red: 0.61, green: 0.91, blue: 0.77, alpha: 0.9).cgColor)
        ring.lineWidth = 48
        UIColor(red: 0.98, green: 0.90, blue: 0.55, alpha: 1).setStroke(); ring.stroke()
        c.restoreGState()
        ring.lineWidth = 23
        UIColor(red: 0.61, green: 0.91, blue: 0.77, alpha: 1).setStroke(); ring.stroke()
        ring.lineWidth = 8
        UIColor(red: 1, green: 0.99, blue: 0.89, alpha: 1).setStroke(); ring.stroke()
        func sparkle(at p: CGPoint, r: CGFloat) {
            let s = UIBezierPath()
            s.move(to: CGPoint(x: p.x, y: p.y - r)); s.addLine(to: CGPoint(x: p.x + r * 0.28, y: p.y - r * 0.28))
            s.addLine(to: CGPoint(x: p.x + r, y: p.y)); s.addLine(to: CGPoint(x: p.x + r * 0.28, y: p.y + r * 0.28))
            s.addLine(to: CGPoint(x: p.x, y: p.y + r)); s.addLine(to: CGPoint(x: p.x - r * 0.28, y: p.y + r * 0.28))
            s.addLine(to: CGPoint(x: p.x - r, y: p.y)); s.addLine(to: CGPoint(x: p.x - r * 0.28, y: p.y - r * 0.28))
            s.close()
            UIColor.white.setFill(); s.fill()
        }
        sparkle(at: CGPoint(x: cx - 250, y: cy - 120), r: 34)
        sparkle(at: CGPoint(x: cx + 270, y: cy - 90), r: 26)
        sparkle(at: CGPoint(x: cx + 40, y: cy - 165), r: 22)
    }

    // MARK: Small CI helpers

    private func colorControls(_ image: CIImage, saturation: Double, brightness: Double, contrast: Double) -> CIImage {
        let f = CIFilter.colorControls()
        f.inputImage = image
        f.saturation = Float(saturation)
        f.brightness = Float(brightness)
        f.contrast = Float(contrast)
        return f.outputImage ?? image
    }

    private func alpha(_ image: CIImage, _ a: Double) -> CIImage {
        let f = CIFilter.colorMatrix()
        f.inputImage = image
        f.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(a))
        return f.outputImage ?? image
    }

    private func vignette(_ image: CIImage, intensity: Double, radius: Double) -> CIImage {
        let f = CIFilter.vignette()
        f.inputImage = image
        f.intensity = Float(intensity)
        f.radius = Float(radius)
        return (f.outputImage ?? image).cropped(to: image.extent)
    }
}

// MARK: - Live frame tap

/// Receives camera frames from the session's video-data output and renders
/// the active AR effect for the viewfinder. Zero cost when no effect is on
/// (the delegate returns immediately); busy frames are dropped so the
/// preview never queues up behind Vision.
nonisolated final class WhisperARFrameTap: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _effect: WhisperAREffect = .none
    private var busy: Bool = false
    private let context = CIContext(options: [.cacheIntermediates: false, .priorityRequestLow: true])
    /// Delivered on the main thread with each rendered frame.
    var onFrame: (@Sendable (CGImage) -> Void)?
    private var _recordingOrigin: CMTime?
    var recordingOrigin: CMTime? {
        get { lock.lock(); defer { lock.unlock() }; return _recordingOrigin }
        set { lock.lock(); _recordingOrigin = newValue; lock.unlock() }
    }
    private var _sourceEpoch: UUID = UUID()
    var sourceEpoch: UUID { lock.lock(); defer { lock.unlock() }; return _sourceEpoch }
    func suspendSource() { lock.lock(); _sourceEpoch = UUID(); _waveOrientation = nil; lock.unlock() }
    private var _waveOrientation: WhisperCameraFrameOrientation?
    var waveOrientation: WhisperCameraFrameOrientation? {
        get { lock.lock(); defer { lock.unlock() }; return _waveOrientation }
        set { lock.lock(); if _waveOrientation != newValue { _sourceEpoch = UUID() }; _waveOrientation = newValue; lock.unlock() }
    }
    private var lastFrameDescription: String?
    private var waveHandlerOwner: UUID?
    private var _waveHandler: (@Sendable (CVPixelBuffer, CMTime, WhisperCameraFrameOrientation) -> Void)?
    func installWaveHandler(owner: UUID, handler: @escaping @Sendable (CVPixelBuffer, CMTime, WhisperCameraFrameOrientation) -> Void) {
        lock.lock(); defer { lock.unlock() }
        waveHandlerOwner = owner; _waveHandler = handler
    }
    func removeWaveHandler(owner: UUID) {
        lock.lock(); defer { lock.unlock() }
        guard waveHandlerOwner == owner else { return }
        _waveHandler = nil; waveHandlerOwner = nil
    }
    var waveHandler: (@Sendable (CVPixelBuffer, CMTime, WhisperCameraFrameOrientation) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _waveHandler }
        set { lock.lock(); waveHandlerOwner = nil; _waveHandler = newValue; lock.unlock() }
    }

    var effect: WhisperAREffect {
        get { lock.lock(); defer { lock.unlock() }; return _effect }
        set { lock.lock(); _effect = newValue; lock.unlock() }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if let handler = waveHandler, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            guard let orientation = waveOrientation else { return }
            let description = "\(CVPixelBufferGetWidth(buffer))x\(CVPixelBufferGetHeight(buffer)) angle=\(orientation.clockwiseDegrees) mirror=\(orientation.mirrored) connection=\(connection.videoRotationAngle)"
            if lastFrameDescription != description {
                lastFrameDescription = description
                print("[WaveCamera] raw frame \(description)")
            }
            handler(buffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer), orientation)
            return
        }
        let active = effect
        guard active != .none, let onFrame else { return }
        lock.lock()
        if busy { lock.unlock(); return }
        busy = true
        lock.unlock()
        defer { lock.lock(); busy = false; lock.unlock() }

        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var image = CIImage(cvPixelBuffer: buffer)
        // Half-size frames keep segmentation + landmarks comfortably real-time.
        let scale: CGFloat = image.extent.width > 720 ? 0.5 : 1
        if scale != 1 {
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        let seconds = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard let rendered = try? WhisperARProcessor.shared.render(image, effect: active, quality: .live, time: seconds) else { return }
        guard let cg = context.createCGImage(rendered, from: rendered.extent) else { return }
        DispatchQueue.main.async { onFrame(cg) }
    }
}

/// The processed-frame viewfinder shown over the raw camera preview while an
/// AR effect is on. Aspect-fill like the preview layer beneath it.
struct WhisperARPreview: UIViewRepresentable {
    let camera: SnapCameraSession
    let effect: WhisperAREffect

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.backgroundColor = .clear
        camera.setAREffect(effect) { cg in
            view.image = UIImage(cgImage: cg)
        }
        return view
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        camera.setAREffect(effect) { cg in
            uiView.image = UIImage(cgImage: cg)
        }
    }

    static func dismantleUIView(_ uiView: UIImageView, coordinator: ()) {
        // The camera owner clears the effect when the tray deselects it.
    }
}
