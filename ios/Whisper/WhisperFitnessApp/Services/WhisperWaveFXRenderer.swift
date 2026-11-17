import CoreImage
import CoreGraphics
import Foundation

/// Core Image renderer for `WhisperWaveFX`. One frame in, one frame out;
/// every animated treatment is a pure function of the composition clock so
/// the live preview, the cover picker and the final encode draw the exact
/// same pixels. Thread-safe: the compositor calls in from its render queue
/// while the cover generator and the tile previews call from elsewhere.
nonisolated final class WhisperWaveFXRenderer: @unchecked Sendable {
    static let shared = WhisperWaveFXRenderer()

    private let spriteLock = NSLock()
    private var sprites: [String: CIImage] = [:]

    private init() {}

    /// A clock reading where the effect is visibly "on" — for picker tiles.
    /// Intermittent effects (glitch bursts, the flash decay) are sampled
    /// mid-burst so a still frame shows what they do.
    func previewTime(for kind: WhisperWaveFX) -> Double {
        switch kind {
        case .glitch:
            for i in 0..<40 where noise(Double(i)) > 0.45 { return (Double(i) + 0.5) / 5 }
            return 0.35
        case .flash: return 0.12
        case .zoomPulse: return 0.05
        case .vhs:
            for i in 0..<40 where noise(Double(i)) > 0.6 { return (Double(i) + 0.5) / 6 }
            return 0.35
        default: return 0.35
        }
    }

    /// Renders `fx` onto `input` at `time` seconds. Returns the input
    /// untouched when there is nothing to draw (zero strength, or an AI
    /// effect with nobody in frame).
    func render(_ input: CIImage, fx: WhisperWaveFXSetting, time: Double, quality: WhisperWaveRenderQuality) -> CIImage {
        let extent = input.extent
        guard extent.width > 8, extent.height > 8 else { return input }
        let k = fx.clampedIntensity
        guard k > 0.001 || !fx.kind.usesIntensity else { return input }
        let s = fx.clampedSpeed
        let t = time.isFinite ? max(0, time) : 0
        let q: Double = quality == .preview ? 0.5 : 1
        let out: CIImage
        switch fx.kind {
        case .slowPush:
            let phase = (1 - cos(t * s * .pi / 6)) / 2
            out = about(input.clampedToExtent(), extent, scale: 1 + 0.22 * k * phase)
        case .handheld:
            let x = extent.width * k * (0.009 * sin(t * s * 2.4) + 0.004 * sin(t * s * 5.3))
            let y = extent.height * k * 0.006 * cos(t * s * 3.1)
            out = about(input.clampedToExtent(), extent, scale: 1 + 0.05 * k, rotation: 0.012 * k * sin(t * s * 1.7), translation: CGPoint(x: x, y: y))
        case .zoomRush:
            let pulse = exp(-frac(t * s / 2) * 8)
            let zoomed = about(input.clampedToExtent(), extent, scale: 1 + 0.3 * k * pulse)
            out = zoomed.applyingFilter("CIZoomBlur", parameters: ["inputCenter": CIVector(x: extent.midX, y: extent.midY), "inputAmount": 28 * k * pulse])
        case .tiltFocus:
            out = input.clampedToExtent().applyingFilter("CIMaskedVariableBlur", parameters: ["inputMask": tiltMask(extent), "inputRadius": extent.width * 0.024 * k])
        case .shake: out = shake(input, extent, k, t, s)
        case .zoomPulse: out = zoomPulse(input, extent, k, t, s)
        case .wobble: out = wobble(input, extent, k, t, s)
        case .vhs: out = vhs(input, extent, k, t, s)
        case .oldFilm: out = oldFilm(input, extent, k, t, s)
        case .glitch: out = glitch(input, extent, k, t, s)
        case .chromatic: out = chromatic(input, extent, k)
        case .fisheye: out = fisheye(input, extent, k)
        case .mirror: out = mirror(input, extent)
        case .kaleido: out = kaleido(input, extent, k, t, s)
        case .pixelate: out = pixelate(input, extent, k)
        case .triple: out = triple(input, extent)
        case .quad: out = quad(input, extent)
        case .comic: out = mix(input, input.applyingFilter("CIComicEffect"), k, extent)
        case .halftone: out = halftone(input, extent, k)
        case .duotone: out = mix(input, duotone(input, shadow: (0.07, 0.05, 0.25), highlight: (1.0, 0.45, 0.25)), k, extent)
        case .popArt: out = popArt(input, extent, k)
        case .sketch: out = sketch(input, extent, k)
        case .negative: out = mix(input, input.applyingFilter("CIColorInvert"), k, extent)
        case .thermal: out = mix(input, input.applyingFilter("CIThermal"), k, extent)
        case .xray: out = mix(input, input.applyingFilter("CIXRay"), k, extent)
        case .flash: out = flash(input, extent, k, t, s)
        case .lightLeak: out = lightLeak(input, extent, k, t, s)
        case .dreamy: out = dreamy(input, extent, k, q)
        case .softFocus: out = softFocus(input, extent, k, q)
        case .neon: out = neon(input, extent, k, t, s, q)
        case .sparkles: out = particles(input, extent, k, t, s, sprite: starSprite(), count: 28, sizeRange: 0.45...1.1, tinted: false)
        case .bokeh: out = particles(input, extent, k, t, s, sprite: bokehSprite(), count: 16, sizeRange: 1.2...3.2, tinted: true)
        case .rainbow: out = mix(input, input.applyingFilter("CIHueAdjust", parameters: ["inputAngle": t * 1.3 * s]), k, extent)
        case .neonOutline: out = neonOutline(input, extent, k, t, s, quality)
        case .aura: out = aura(input, extent, k, t, s, quality)
        case .spotlight: out = spotlight(input, extent, k, quality)
        case .echo: out = echo(input, extent, k, t, s, quality)
        case .popOut: out = popOut(input, extent, k, quality)
        }
        return out.cropped(to: extent)
    }

    private func tiltMask(_ extent: CGRect) -> CIImage {
        let band = CIImage(color: .black).cropped(to: CGRect(x: extent.minX, y: extent.minY + extent.height * 0.35, width: extent.width, height: extent.height * 0.3))
        return band.composited(over: CIImage(color: .white).cropped(to: extent)).clampedToExtent().applyingGaussianBlur(sigma: extent.height * 0.08).cropped(to: extent)
    }

    // MARK: Motion

    private func shake(_ image: CIImage, _ extent: CGRect, _ k: Double, _ t: Double, _ s: Double) -> CIImage {
        let step = floor(t * 14 * s)
        let dx = (noise(step) * 2 - 1) * extent.width * 0.035 * k
        let dy = (noise(step + 31) * 2 - 1) * extent.height * 0.02 * k
        let rot = (noise(step + 77) * 2 - 1) * 0.012 * k
        return about(image.clampedToExtent(), extent, scale: 1 + 0.06 * k, rotation: rot, translation: CGPoint(x: dx, y: dy)).cropped(to: extent)
    }

    private func zoomPulse(_ image: CIImage, _ extent: CGRect, _ k: Double, _ t: Double, _ s: Double) -> CIImage {
        // A heartbeat: sharp attack, exponential release, ~96 bpm at 1×.
        let beat = exp(-frac(t * 1.6 * s) * 6)
        return about(image.clampedToExtent(), extent, scale: 1 + 0.14 * k * beat).cropped(to: extent)
    }

    private func wobble(_ image: CIImage, _ extent: CGRect, _ k: Double, _ t: Double, _ s: Double) -> CIImage {
        let rot = 0.04 * k * sin(2 * .pi * t * s * 0.8)
        let sx = 1.06 + 0.05 * k * sin(2 * .pi * t * s * 1.1)
        let sy = 1.06 + 0.05 * k * cos(2 * .pi * t * s * 1.1)
        return about(image.clampedToExtent(), extent, scale: sx, scaleY: sy, rotation: rot).cropped(to: extent)
    }

    // MARK: Retro

    private func vhs(_ image: CIImage, _ extent: CGRect, _ k: Double, _ t: Double, _ s: Double) -> CIImage {
        let shift = extent.width * 0.006 * k * (1 + 0.5 * noise(floor(t * 10 * s)))
        var img = rgbSplit(image, extent, red: CGPoint(x: shift, y: 0), blue: CGPoint(x: -shift, y: 0))
        let seed = floor(t * 6 * s)
        if noise(seed) > 0.6 {
            // A tracking glitch: one band slides sideways for a few frames.
            let bandY = extent.minY + noise(seed + 3) * extent.height
            let bandH = extent.height * (0.03 + 0.08 * noise(seed + 9))
            let band = img.cropped(to: CGRect(x: extent.minX, y: bandY, width: extent.width, height: bandH))
            let offset = (noise(seed + 5) * 2 - 1) * extent.width * 0.05 * k
            img = band.transformed(by: CGAffineTransform(translationX: offset, y: 0)).composited(over: img).cropped(to: extent)
        }
        img = colorControls(img, saturation: 1 - 0.25 * k, brightness: 0.02 * k, contrast: 1 + 0.08 * k)
        img = scanlines(extent, darkness: 0.35 * k).applyingFilter("CIMultiplyBlendMode", parameters: ["inputBackgroundImage": img])
        img = grain(extent, t: t, size: 2, amount: 0.12 * k).applyingFilter("CISoftLightBlendMode", parameters: ["inputBackgroundImage": img])
        return vignette(img, intensity: 0.7 * k, radius: 1.6)
    }

    private func oldFilm(_ image: CIImage, _ extent: CGRect, _ k: Double, _ t: Double, _ s: Double) -> CIImage {
        var img = image.applyingFilter("CISepiaTone", parameters: ["inputIntensity": 0.45 * k])
        let flicker = (noise(floor(t * 24 * s)) * 2 - 1) * 0.12 * k
        img = img.applyingFilter("CIExposureAdjust", parameters: ["inputEV": flicker])
        img = colorControls(img, saturation: 1 - 0.3 * k, brightness: 0, contrast: 1 + 0.1 * k)
        // Gate weave.
        let weave = (noise(floor(t * 12 * s)) * 2 - 1) * 4 * k
        img = about(img.clampedToExtent(), extent, scale: 1.01, translation: CGPoint(x: 0, y: weave)).cropped(to: extent)
        img = grain(extent, t: t, size: 3, amount: 0.16 * k).applyingFilter("CISoftLightBlendMode", parameters: ["inputBackgroundImage": img])
        let seed = floor(t * 8 * s)
        if noise(seed) > 0.7 {
            let x = extent.minX + noise(seed + 2) * extent.width
            let scratch = CIImage(color: CIColor(red: 1, green: 1, blue: 0.95, alpha: 0.5 * k)).cropped(to: CGRect(x: x, y: extent.minY, width: 2, height: extent.height))
            img = scratch.composited(over: img)
        }
        return vignette(img, intensity: 1.0 * k, radius: 1.4)
    }

    private func glitch(_ image: CIImage, _ extent: CGRect, _ k: Double, _ t: Double, _ s: Double) -> CIImage {
        let burst = floor(t * 5 * s)
        guard noise(burst) > 0.45 else { return image }
        let frame = floor(t * 30)
        let shift = extent.width * 0.03 * k * (noise(frame) * 2 - 1)
        var img = rgbSplit(image, extent, red: CGPoint(x: shift, y: 0), blue: CGPoint(x: -shift, y: 0))
        for j in 0..<3 {
            let seed = frame * 7 + Double(j) * 13
            let y = extent.minY + noise(seed) * extent.height
            let h = extent.height * (0.02 + 0.1 * noise(seed + 1))
            let dx = (noise(seed + 2) * 2 - 1) * extent.width * 0.12 * k
            let slice = img.cropped(to: CGRect(x: extent.minX, y: y, width: extent.width, height: h))
            img = slice.transformed(by: CGAffineTransform(translationX: dx, y: 0)).composited(over: img).cropped(to: extent)
        }
        return img
    }

    private func chromatic(_ image: CIImage, _ extent: CGRect, _ k: Double) -> CIImage {
        let src = image.clampedToExtent()
        let r = about(channel(src, r: 1, g: 0, b: 0), extent, scale: 1 + 0.012 * k)
        let g = channel(src, r: 0, g: 1, b: 0)
        let b = about(channel(src, r: 0, g: 0, b: 1), extent, scale: 1 - 0.012 * k)
        return r.applyingFilter("CIMaximumCompositing", parameters: ["inputBackgroundImage": g])
            .applyingFilter("CIMaximumCompositing", parameters: ["inputBackgroundImage": b]).cropped(to: extent)
    }

    // MARK: Distort

    private func fisheye(_ image: CIImage, _ extent: CGRect, _ k: Double) -> CIImage {
        image.clampedToExtent().applyingFilter("CIBumpDistortion", parameters: [
            "inputCenter": CIVector(x: extent.midX, y: extent.midY),
            "inputRadius": max(extent.width, extent.height) * 0.72,
            "inputScale": 0.65 * k
        ]).cropped(to: extent)
    }

    private func mirror(_ image: CIImage, _ extent: CGRect) -> CIImage {
        let half = CGRect(x: extent.minX, y: extent.minY, width: extent.width / 2, height: extent.height)
        let left = image.cropped(to: half)
        let flipped = left.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: extent.minX * 2 + extent.width, ty: 0))
        return flipped.composited(over: image).cropped(to: extent)
    }

    private func kaleido(_ image: CIImage, _ extent: CGRect, _ k: Double, _ t: Double, _ s: Double) -> CIImage {
        image.clampedToExtent().applyingFilter("CIKaleidoscope", parameters: [
            "inputCount": 3 + Int((k * 9).rounded()),
            "inputCenter": CIVector(x: extent.midX, y: extent.midY),
            "inputAngle": t * 0.4 * s
        ]).cropped(to: extent)
    }

    private func pixelate(_ image: CIImage, _ extent: CGRect, _ k: Double) -> CIImage {
        image.clampedToExtent().applyingFilter("CIPixellate", parameters: [
            "inputCenter": CIVector(x: extent.midX, y: extent.midY),
            "inputScale": 4 + 44 * k
        ]).cropped(to: extent)
    }

    private func triple(_ image: CIImage, _ extent: CGRect) -> CIImage {
        let h = extent.height / 3
        let band = image.cropped(to: CGRect(x: extent.minX, y: extent.minY + h, width: extent.width, height: h))
        let top = band.transformed(by: CGAffineTransform(translationX: 0, y: h))
        let bottom = band.transformed(by: CGAffineTransform(translationX: 0, y: -h))
        return top.composited(over: band.composited(over: bottom.composited(over: CIImage(color: .black).cropped(to: extent)))).cropped(to: extent)
    }

    private func quad(_ image: CIImage, _ extent: CGRect) -> CIImage {
        let small = image.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
        let w: CGFloat = extent.width / 2
        let h: CGFloat = extent.height / 2
        let origin = CGPoint(x: extent.minX / 2, y: extent.minY / 2)
        var out = CIImage(color: .black).cropped(to: extent)
        let cells: [(dx: CGFloat, dy: CGFloat)] = [(0, 0), (w, 0), (0, h), (w, h)]
        for (dx, dy) in cells {
            out = small.transformed(by: CGAffineTransform(translationX: extent.minX - origin.x + dx, y: extent.minY - origin.y + dy)).composited(over: out)
        }
        return out.cropped(to: extent)
    }

    // MARK: Art

    private func halftone(_ image: CIImage, _ extent: CGRect, _ k: Double) -> CIImage {
        image.applyingFilter("CICMYKHalftone", parameters: [
            "inputCenter": CIVector(x: extent.midX, y: extent.midY),
            "inputWidth": 6 + 14 * k, "inputAngle": 0, "inputSharpness": 0.7, "inputGCR": 1, "inputUCR": 0.5
        ]).cropped(to: extent)
    }

    private func duotone(_ image: CIImage, shadow: (Double, Double, Double), highlight: (Double, Double, Double)) -> CIImage {
        let gray = image.applyingFilter("CIColorControls", parameters: ["inputSaturation": 0])
        return gray.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: highlight.0 - shadow.0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: highlight.1 - shadow.1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: highlight.2 - shadow.2, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: shadow.0, y: shadow.1, z: shadow.2, w: 0)
        ])
    }

    private func popArt(_ image: CIImage, _ extent: CGRect, _ k: Double) -> CIImage {
        let poster = colorControls(image, saturation: 1.8, brightness: 0, contrast: 1.15)
            .applyingFilter("CIColorPosterize", parameters: ["inputLevels": 4])
        return mix(image, poster, k, extent)
    }

    private func sketch(_ image: CIImage, _ extent: CGRect, _ k: Double) -> CIImage {
        let lines = image.applyingFilter("CILineOverlay", parameters: [
            "inputNRNoiseLevel": 0.07, "inputNRSharpness": 0.71, "inputEdgeIntensity": 1, "inputThreshold": 0.1, "inputContrast": 50
        ])
        let paper = CIImage(color: CIColor(red: 0.96, green: 0.95, blue: 0.92)).cropped(to: extent)
        return mix(image, lines.composited(over: paper), k, extent)
    }

    // MARK: Light

    private func flash(_ image: CIImage, _ extent: CGRect, _ k: Double, _ t: Double, _ s: Double) -> CIImage {
        let period = 1.2 / s
        let phase = frac(t / period)
        let alpha = k * 0.8 * max(0, 1 - phase / 0.18)
        guard alpha > 0.005 else { return image }
        return CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: alpha)).cropped(to: extent).composited(over: image)
    }

    private func lightLeak(_ image: CIImage, _ extent: CGRect, _ k: Double, _ t: Double, _ s: Double) -> CIImage {
        let w = extent.width, h = extent.height
        let warmX = extent.minX + w * (0.15 + 0.7 * (0.5 + 0.5 * sin(t * 0.6 * s)))
        let warm = radial(center: CGPoint(x: warmX, y: extent.minY + h * 0.95), radius: h * 0.6,
                          color: CIColor(red: 1.0, green: 0.55, blue: 0.2, alpha: 0.75 * k), extent: extent)
        let pinkX = extent.minX + w * (0.85 - 0.7 * (0.5 + 0.5 * sin(t * 0.45 * s + 1.3)))
        let pink = radial(center: CGPoint(x: pinkX, y: extent.minY + h * 0.08), radius: h * 0.5,
                          color: CIColor(red: 1.0, green: 0.3, blue: 0.55, alpha: 0.5 * k), extent: extent)
        let leaked = warm.applyingFilter("CIScreenBlendMode", parameters: ["inputBackgroundImage": image])
        return pink.applyingFilter("CIScreenBlendMode", parameters: ["inputBackgroundImage": leaked]).cropped(to: extent)
    }

    private func dreamy(_ image: CIImage, _ extent: CGRect, _ k: Double, _ q: Double) -> CIImage {
        let bloomed = image.clampedToExtent().applyingFilter("CIBloom", parameters: ["inputRadius": 24 * q, "inputIntensity": 0.9 * k]).cropped(to: extent)
        return colorControls(bloomed, saturation: 1 - 0.15 * k, brightness: 0.03 * k, contrast: 1)
    }

    private func softFocus(_ image: CIImage, _ extent: CGRect, _ k: Double, _ q: Double) -> CIImage {
        let blurred = image.clampedToExtent().applyingGaussianBlur(sigma: 10 * k * q).cropped(to: extent)
        return mix(image, blurred, 0.6 * k, extent)
    }

    private func neon(_ image: CIImage, _ extent: CGRect, _ k: Double, _ t: Double, _ s: Double, _ q: Double) -> CIImage {
        let edges = image.applyingFilter("CIEdges", parameters: ["inputIntensity": 4 + 4 * k])
            .applyingFilter("CIHueAdjust", parameters: ["inputAngle": t * 0.5 * s])
        let glow = edges.clampedToExtent().applyingFilter("CIBloom", parameters: ["inputRadius": 10 * q, "inputIntensity": 1.5]).cropped(to: extent)
        let dark = image.applyingFilter("CIExposureAdjust", parameters: ["inputEV": -1.4 * k])
        return glow.applyingFilter("CIScreenBlendMode", parameters: ["inputBackgroundImage": dark]).cropped(to: extent)
    }

    /// Drifting, twinkling sprites — stars for Sparkles, tinted soft discs
    /// for Bokeh. Positions come from the particle index and the clock, so
    /// every frame is reproducible.
    private func particles(_ image: CIImage, _ extent: CGRect, _ k: Double, _ t: Double, _ s: Double, sprite: CIImage, count: Int, sizeRange: ClosedRange<Double>, tinted: Bool) -> CIImage {
        // All sprites land on one transparent layer, then a single screen
        // blend lifts them onto the footage.
        var layer = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent)
        let unit = extent.width / 1080
        for i in 0..<count {
            let seed = Double(i)
            let rise = 0.04 * s * (0.5 + noise(seed * 1.7))
            let x = extent.minX + extent.width * frac(noise(seed * 3.1) + 0.02 * sin(t * s + seed))
            let y = extent.minY + extent.height * frac(noise(seed * 7.3) + t * rise)
            let twinkle = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * 4 * s + seed * 2.3))
            let size = (sizeRange.lowerBound + noise(seed * 9.9) * (sizeRange.upperBound - sizeRange.lowerBound)) * (0.6 + 0.6 * k) * unit
            var dot = sprite
            if tinted {
                let tint = hue(noise(seed * 4.4) * 0.5 + 0.05, saturation: 0.55)
                dot = dot.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: tint.red, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: tint.green, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: tint.blue, w: 0)
                ])
            }
            dot = alpha(dot, twinkle * k * (tinted ? 0.6 : 1))
            var transform = CGAffineTransform(translationX: x, y: y)
            transform = transform.rotated(by: t * 0.5 * s + seed)
            transform = transform.scaledBy(x: size, y: size)
            transform = transform.translatedBy(x: -64, y: -64)
            layer = dot.transformed(by: transform).composited(over: layer).cropped(to: extent)
        }
        return layer.applyingFilter("CIScreenBlendMode", parameters: ["inputBackgroundImage": image]).cropped(to: extent)
    }

    // MARK: AI — person segmentation

    /// The person matte. Live preview segments a half-size frame with the
    /// fast model (the matte is low-resolution regardless) and scales the
    /// result back, keeping 30 fps; the final encode segments the full frame.
    private func personMask(_ image: CIImage, _ quality: WhisperWaveRenderQuality) -> CIImage? {
        guard quality == .preview, image.extent.width > 600 else {
            return WhisperARProcessor.shared.personMask(image, quality: quality == .preview ? .live : .export)
        }
        let scale: CGFloat = 0.5
        let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let mask = WhisperARProcessor.shared.personMask(small, quality: .live) else { return nil }
        return mask.transformed(by: CGAffineTransform(scaleX: 1 / scale, y: 1 / scale)).cropped(to: image.extent)
    }

    private func neonOutline(_ image: CIImage, _ extent: CGRect, _ k: Double, _ t: Double, _ s: Double, _ quality: WhisperWaveRenderQuality) -> CIImage {
        guard let mask = personMask(image, quality) else { return image }
        let q: Double = quality == .preview ? 0.6 : 1
        let radius = (6 + 10 * k) * q * (extent.width / 1080)
        let dilated = mask.clampedToExtent().applyingFilter("CIMorphologyMaximum", parameters: ["inputRadius": radius]).cropped(to: extent)
        let band = dilated.applyingFilter("CIDifferenceBlendMode", parameters: ["inputBackgroundImage": mask])
        let color = hue(t * 0.15 * s, saturation: 0.9)
        let colored = band.applyingFilter("CIMaskToAlpha").applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: color.red, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: color.green, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: color.blue, w: 0)
        ])
        let glow = colored.clampedToExtent().applyingFilter("CIBloom", parameters: ["inputRadius": (8 + 8 * k) * q, "inputIntensity": 1.2]).cropped(to: extent)
        let dimmed = image.applyingFilter("CIExposureAdjust", parameters: ["inputEV": -0.6 * k])
        let base = image.applyingFilter("CIBlendWithMask", parameters: ["inputBackgroundImage": dimmed, "inputMaskImage": mask])
        return glow.composited(over: base).cropped(to: extent)
    }

    private func aura(_ image: CIImage, _ extent: CGRect, _ k: Double, _ t: Double, _ s: Double, _ quality: WhisperWaveRenderQuality) -> CIImage {
        guard let mask = personMask(image, quality) else { return image }
        let q: Double = quality == .preview ? 0.5 : 1
        let halo = mask.clampedToExtent().applyingGaussianBlur(sigma: 34 * q * (extent.width / 1080)).cropped(to: extent)
        // Warm brand sweep, drifting slowly between rose and amber.
        let color = hue(0.02 + 0.06 * (0.5 + 0.5 * sin(t * 0.4 * s)), saturation: 0.85)
        let colored = halo.applyingFilter("CIMaskToAlpha").applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: color.red, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: color.green, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: color.blue, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.9 * k)
        ])
        let glowing = colored.applyingFilter("CIScreenBlendMode", parameters: ["inputBackgroundImage": image])
        return image.applyingFilter("CIBlendWithMask", parameters: ["inputBackgroundImage": glowing, "inputMaskImage": mask]).cropped(to: extent)
    }

    private func spotlight(_ image: CIImage, _ extent: CGRect, _ k: Double, _ quality: WhisperWaveRenderQuality) -> CIImage {
        guard let mask = personMask(image, quality) else { return image }
        let dimmed = colorControls(image.applyingFilter("CIExposureAdjust", parameters: ["inputEV": -1.7 * k]), saturation: 1 - 0.5 * k, brightness: 0, contrast: 1)
        let lit = image.applyingFilter("CIBlendWithMask", parameters: ["inputBackgroundImage": dimmed, "inputMaskImage": mask])
        return vignette(lit, intensity: 0.8 * k, radius: 1.8)
    }

    private func echo(_ image: CIImage, _ extent: CGRect, _ k: Double, _ t: Double, _ s: Double, _ quality: WhisperWaveRenderQuality) -> CIImage {
        guard let mask = personMask(image, quality) else { return image }
        let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent)
        let cutout = image.applyingFilter("CIBlendWithMask", parameters: ["inputBackgroundImage": clear, "inputMaskImage": mask])
        let sway = sin(t * 2 * s)
        var out = image
        let tints: [(Double, Double, Double, Double)] = [(0.4, 1.0, 1.0, 0.55), (1.0, 0.4, 0.9, 0.4), (1.0, 0.9, 0.4, 0.28)]
        for (j, tint) in tints.enumerated().reversed() {
            let dx = extent.width * 0.045 * k * Double(j + 1) * (j % 2 == 0 ? 1 : -1) * (0.6 + 0.4 * sway)
            var ghost = cutout.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: tint.0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: tint.1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: tint.2, w: 0)
            ])
            ghost = alpha(ghost, tint.3 * k).transformed(by: CGAffineTransform(translationX: dx, y: 0))
            out = ghost.composited(over: out).cropped(to: extent)
        }
        return image.applyingFilter("CIBlendWithMask", parameters: ["inputBackgroundImage": out, "inputMaskImage": mask]).cropped(to: extent)
    }

    private func popOut(_ image: CIImage, _ extent: CGRect, _ k: Double, _ quality: WhisperWaveRenderQuality) -> CIImage {
        guard let mask = personMask(image, quality) else { return image }
        let poster = duotone(image, shadow: (0.05, 0.03, 0.2), highlight: (1.0, 0.66, 0.3))
            .applyingFilter("CIColorPosterize", parameters: ["inputLevels": 5])
        let background = mix(image, poster, k, extent)
        return image.applyingFilter("CIBlendWithMask", parameters: ["inputBackgroundImage": background, "inputMaskImage": mask]).cropped(to: extent)
    }

    // MARK: Sprites (built once)

    private func sprite(_ key: String, make: () -> CIImage) -> CIImage {
        spriteLock.lock()
        defer { spriteLock.unlock() }
        if let cached = sprites[key] { return cached }
        let made = make()
        sprites[key] = made
        return made
    }

    private func starSprite() -> CIImage {
        sprite("star") {
            let star = CIFilter(name: "CIStarShineGenerator", parameters: [
                "inputCenter": CIVector(x: 64, y: 64), "inputColor": CIColor(red: 1, green: 0.97, blue: 0.9),
                "inputRadius": 6, "inputCrossScale": 18, "inputCrossAngle": 0.6, "inputCrossOpacity": -2, "inputCrossWidth": 2.5, "inputEpsilon": -2
            ])?.outputImage
            return (star ?? CIImage(color: .white)).cropped(to: CGRect(x: 0, y: 0, width: 128, height: 128))
        }
    }

    private func bokehSprite() -> CIImage {
        sprite("bokeh") {
            radial(center: CGPoint(x: 64, y: 64), radius: 56, color: CIColor(red: 1, green: 1, blue: 1, alpha: 0.9), extent: CGRect(x: 0, y: 0, width: 128, height: 128))
        }
    }

    // MARK: Helpers

    /// Deterministic 0…1 hash of a seed — the same on every render.
    private func noise(_ seed: Double) -> Double {
        let x = sin(seed * 12.9898 + 78.233) * 43758.5453
        return x - floor(x)
    }

    private func frac(_ x: Double) -> Double { x - floor(x) }

    private func hue(_ h: Double, saturation: Double, value: Double = 1) -> CIColor {
        let hh = frac(h) * 6
        let i = Int(hh)
        let f = hh - Double(i)
        let p = value * (1 - saturation)
        let q = value * (1 - saturation * f)
        let u = value * (1 - saturation * (1 - f))
        let rgb: (Double, Double, Double)
        switch i % 6 {
        case 0: rgb = (value, u, p)
        case 1: rgb = (q, value, p)
        case 2: rgb = (p, value, u)
        case 3: rgb = (p, q, value)
        case 4: rgb = (u, p, value)
        default: rgb = (value, p, q)
        }
        return CIColor(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    /// Scale/rotate/translate about the frame's center.
    private func about(_ image: CIImage, _ extent: CGRect, scale: Double = 1, scaleY: Double? = nil, rotation: Double = 0, translation: CGPoint = .zero) -> CIImage {
        let c = CGPoint(x: extent.midX, y: extent.midY)
        var t = CGAffineTransform(translationX: c.x + translation.x, y: c.y + translation.y)
        t = t.rotated(by: rotation)
        t = t.scaledBy(x: scale, y: scaleY ?? scale)
        t = t.translatedBy(x: -c.x, y: -c.y)
        return image.transformed(by: t)
    }

    private func channel(_ image: CIImage, r: CGFloat, g: CGFloat, b: CGFloat) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ])
    }

    private func rgbSplit(_ image: CIImage, _ extent: CGRect, red: CGPoint, blue: CGPoint) -> CIImage {
        let src = image.clampedToExtent()
        let r = channel(src, r: 1, g: 0, b: 0).transformed(by: CGAffineTransform(translationX: red.x, y: red.y))
        let g = channel(src, r: 0, g: 1, b: 0)
        let b = channel(src, r: 0, g: 0, b: 1).transformed(by: CGAffineTransform(translationX: blue.x, y: blue.y))
        return r.applyingFilter("CIMaximumCompositing", parameters: ["inputBackgroundImage": g])
            .applyingFilter("CIMaximumCompositing", parameters: ["inputBackgroundImage": b]).cropped(to: extent)
    }

    private func mix(_ original: CIImage, _ effected: CIImage, _ k: Double, _ extent: CGRect) -> CIImage {
        if k >= 0.999 { return effected.cropped(to: extent) }
        if k <= 0.001 { return original }
        return original.applyingFilter("CIDissolveTransition", parameters: ["inputTargetImage": effected.cropped(to: extent), "inputTime": k]).cropped(to: extent)
    }

    private func alpha(_ image: CIImage, _ a: Double) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(min(1, max(0, a))))])
    }

    private func colorControls(_ image: CIImage, saturation: Double, brightness: Double, contrast: Double) -> CIImage {
        image.applyingFilter("CIColorControls", parameters: ["inputSaturation": saturation, "inputBrightness": brightness, "inputContrast": contrast])
    }

    private func vignette(_ image: CIImage, intensity: Double, radius: Double) -> CIImage {
        image.applyingFilter("CIVignette", parameters: ["inputIntensity": intensity, "inputRadius": radius]).cropped(to: image.extent)
    }

    private func radial(center: CGPoint, radius: CGFloat, color: CIColor, extent: CGRect) -> CIImage {
        let fade = CIColor(red: color.red, green: color.green, blue: color.blue, alpha: 0)
        let gradient = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: center.x, y: center.y), "inputRadius0": 0, "inputRadius1": radius, "inputColor0": color, "inputColor1": fade
        ])?.outputImage
        return (gradient ?? CIImage(color: fade)).cropped(to: extent)
    }

    /// Horizontal 2 px lines, `darkness` deep, for CRT scanlines (multiply).
    private func scanlines(_ extent: CGRect, darkness: Double) -> CIImage {
        let gray = CGFloat(1 - darkness)
        let stripes = CIFilter(name: "CIStripesGenerator", parameters: [
            "inputCenter": CIVector(x: 0, y: 0), "inputColor0": CIColor(red: 1, green: 1, blue: 1),
            "inputColor1": CIColor(red: gray, green: gray, blue: gray), "inputWidth": 2, "inputSharpness": 1
        ])?.outputImage ?? CIImage(color: .white)
        return stripes.transformed(by: CGAffineTransform(rotationAngle: .pi / 2)).cropped(to: extent)
    }

    /// Animated monochrome grain at `amount` opacity, ready for soft light.
    private func grain(_ extent: CGRect, t: Double, size: CGFloat, amount: Double) -> CIImage {
        let random = CIFilter(name: "CIRandomGenerator")?.outputImage ?? CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
        let frame = floor(t * 30)
        let shift = CGAffineTransform(translationX: CGFloat(noise(frame) * 700), y: CGFloat(noise(frame + 11) * 700))
        let gray = random.transformed(by: CGAffineTransform(scaleX: size, y: size)).transformed(by: shift)
            .applyingFilter("CIColorControls", parameters: ["inputSaturation": 0])
        return alpha(gray.cropped(to: extent), amount)
    }
}
