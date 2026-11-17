import CoreImage
import UIKit

/// One caption phrase rasterized once — the whole phrase in its resting look
/// plus every word in its spoken look — and composited per frame from the
/// composition clock, so preview, cover and export agree to the frame.
nonisolated struct WhisperWaveCaptionFrame: @unchecked Sendable {
    nonisolated struct Word: @unchecked Sendable {
        let start: Double
        let end: Double
        /// The word in its spoken look; nil for styles without a highlight.
        let active: CIImage?
        /// Word center inside the phrase artwork, Core Image (bottom-left) coordinates.
        let center: CGPoint
    }

    let start: Double
    let end: Double
    /// The resting phrase; nil for Solo, which shows one word at a time.
    let base: CIImage?
    let words: [Word]
    let style: WhisperWaveCaptionStyle
    /// Size multiplier the artwork was rasterized at.
    let bakedScale: Double

    // MARK: Preparation

    @MainActor private static var cache: [String: CGImage] = [:]

    /// Rasterizes every phrase of `captions` for the given clips and canvas.
    @MainActor static func prepare(_ captions: WhisperWaveCaptions, clips: [WhisperWaveClip], canvas: CGSize) -> [WhisperWaveCaptionFrame] {
        let phrases = WhisperWaveCaptionPhrase.phrases(captions.placed(in: clips))
        guard !phrases.isEmpty else { return [] }
        if cache.count > 600 { cache.removeAll(keepingCapacity: true) }
        let style = captions.style
        let scale = captions.clampedScale
        let fontSize = canvas.width * 0.058 * CGFloat(scale) * (style == .solo ? 1.55 : (style == .box ? 0.92 : 1))
        let font = style.font.uiFont(size: fontSize)
        let highlight = captions.highlightColor
        let maxWidth = canvas.width * 0.86
        return phrases.compactMap { phrase in
            build(phrase, style: style, font: font, fontSize: fontSize, highlight: highlight, maxWidth: maxWidth, bakedScale: scale)
        }
    }

    @MainActor private static func build(_ phrase: WhisperWaveCaptionPhrase, style: WhisperWaveCaptionStyle, font: UIFont, fontSize: CGFloat, highlight: UIColor, maxWidth: CGFloat, bakedScale: Double) -> WhisperWaveCaptionFrame? {
        let texts = phrase.words.map { style.font.uppercase ? $0.text.uppercased() : $0.text }
        let restingAttributes = attributes(style: style, font: font, fontSize: fontSize, highlight: highlight, spoken: false)
        let sizes = texts.map { ($0 as NSString).size(withAttributes: restingAttributes) }
        let gap = fontSize * 0.3
        let lineHeight = ceil(font.lineHeight * 1.12)

        // Greedy rows, each centered.
        var rows: [[Int]] = [[]]
        var rowWidth: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            let width = ceil(size.width)
            if !rows[rows.count - 1].isEmpty, rowWidth + gap + width > maxWidth {
                rows.append([index])
                rowWidth = width
            } else {
                rowWidth += (rows[rows.count - 1].isEmpty ? 0 : gap) + width
                rows[rows.count - 1].append(index)
            }
        }
        let rowWidths: [CGFloat] = rows.map { row in
            row.reduce(CGFloat(0)) { $0 + ceil(sizes[$1].width) } + gap * CGFloat(max(0, row.count - 1))
        }
        let blockWidth = rowWidths.max() ?? 0
        let padX: CGFloat = style == .classic ? fontSize * 0.5 : fontSize * 0.3
        let padY: CGFloat = style == .classic ? fontSize * 0.28 : fontSize * 0.22
        let imageSize = CGSize(width: ceil(blockWidth + padX * 2), height: ceil(lineHeight * CGFloat(rows.count) + padY * 2))
        guard imageSize.width > 1, imageSize.height > 1 else { return nil }

        // Word rectangles in UIKit (top-left) coordinates.
        var rects = [CGRect](repeating: .zero, count: texts.count)
        for (rowIndex, row) in rows.enumerated() {
            var x = (imageSize.width - rowWidths[rowIndex]) / 2
            let y = padY + lineHeight * CGFloat(rowIndex) + (lineHeight - ceil(sizes[row.first ?? 0].height)) / 2
            for index in row {
                let width = ceil(sizes[index].width)
                rects[index] = CGRect(x: x, y: y, width: width, height: ceil(sizes[index].height))
                x += width + gap
            }
        }

        var base: CIImage? = nil
        if style != .solo {
            let key = "base|\(style.rawValue)|\(Int(fontSize))|\(texts.joined(separator: "\u{1F}"))"
            let image = cached(key, size: imageSize) { context in
                if style == .classic {
                    let plate = UIBezierPath(roundedRect: CGRect(origin: .zero, size: imageSize), cornerRadius: fontSize * 0.36)
                    UIColor.black.withAlphaComponent(0.62).setFill()
                    plate.fill()
                }
                for (index, text) in texts.enumerated() {
                    (text as NSString).draw(at: rects[index].origin, withAttributes: restingAttributes)
                }
            }
            base = image.map { CIImage(cgImage: $0) }
        }

        let spokenAttributes = attributes(style: style, font: font, fontSize: fontSize, highlight: highlight, spoken: true)
        let words: [Word] = phrase.words.enumerated().map { index, word in
            var active: CIImage? = nil
            if style.highlightsWords {
                let rect = rects[index]
                let inset = style == .box ? CGSize(width: fontSize * 0.26, height: fontSize * 0.1) : CGSize(width: fontSize * 0.2, height: fontSize * 0.14)
                let wordSize = CGSize(width: ceil(rect.width + inset.width * 2), height: ceil(rect.height + inset.height * 2))
                let key = "word|\(style.rawValue)|\(Int(fontSize))|\(highlight.description)|\(texts[index])"
                let image = cached(key, size: wordSize) { context in
                    if style == .box {
                        let plate = UIBezierPath(roundedRect: CGRect(origin: .zero, size: wordSize), cornerRadius: fontSize * 0.24)
                        highlight.setFill()
                        plate.fill()
                    }
                    (texts[index] as NSString).draw(at: CGPoint(x: inset.width, y: inset.height), withAttributes: spokenAttributes)
                }
                active = image.map { CIImage(cgImage: $0) }
            }
            let rect = rects[index]
            return Word(start: word.start, end: word.end, active: active, center: CGPoint(x: rect.midX, y: imageSize.height - rect.midY))
        }
        return WhisperWaveCaptionFrame(start: phrase.start, end: phrase.displayEnd, base: base, words: words, style: style, bakedScale: bakedScale)
    }

    private static func attributes(style: WhisperWaveCaptionStyle, font: UIFont, fontSize: CGFloat, highlight: UIColor, spoken: Bool) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = fontSize * 0.1
        shadow.shadowOffset = CGSize(width: 0, height: fontSize * 0.04)
        switch style {
        case .pop:
            attributes[.foregroundColor] = spoken ? highlight : UIColor.white
            attributes[.shadow] = shadow
        case .box:
            attributes[.foregroundColor] = spoken ? (isLight(highlight) ? UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1) : UIColor.white) : UIColor.white
            if !spoken { attributes[.shadow] = shadow }
        case .solo:
            attributes[.foregroundColor] = highlight
            attributes[.shadow] = shadow
        case .classic:
            attributes[.foregroundColor] = UIColor.white
        case .outline:
            attributes[.foregroundColor] = spoken ? highlight : UIColor.white
            attributes[.strokeColor] = UIColor.black
            attributes[.strokeWidth] = -6.5
            attributes[.shadow] = shadow
        }
        return attributes
    }

    private static func isLight(_ color: UIColor) -> Bool {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return false }
        return 0.299 * red + 0.587 * green + 0.114 * blue > 0.6
    }

    @MainActor private static func cached(_ key: String, size: CGSize, draw: (CGContext) -> Void) -> CGImage? {
        if let hit = cache[key] { return hit }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in draw(context.cgContext) }
        guard let cgImage = image.cgImage else { return nil }
        cache[key] = cgImage
        return cgImage
    }

    // MARK: Drawing

    /// The phrase at `time`, or nil when it is off screen. `y` is the
    /// normalized center (0 = top); `scale` is the size multiplier requested
    /// now, applied relative to the size the artwork was baked at.
    func frame(at time: Double, canvas: CGSize, y: Double, scale: Double) -> CIImage? {
        guard time >= start, time < end else { return nil }
        let age = time - start
        let zoom = CGFloat(max(0.3, scale / max(0.1, bakedScale)))
        let center = CGPoint(x: canvas.width / 2, y: canvas.height * (1 - CGFloat(min(0.95, max(0.05, y)))))
        let activeIndex = words.lastIndex { $0.start <= time }

        var result: CIImage? = nil
        if let base {
            var entrance: CGFloat = 1
            var opacity: Double = 1
            switch style {
            case .classic: opacity = min(1, age / 0.16)
            default:
                let p = min(1, age / 0.14)
                entrance = 0.92 + 0.08 * CGFloat(p)
                opacity = min(1, age / 0.08)
            }
            let extent = base.extent
            var art = base.transformed(by: CGAffineTransform(translationX: -extent.midX, y: -extent.midY))
                .transformed(by: CGAffineTransform(scaleX: zoom * entrance, y: zoom * entrance))
                .transformed(by: CGAffineTransform(translationX: center.x, y: center.y))
            if opacity < 1 { art = art.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)]) }
            result = art
        }

        if let activeIndex, let active = words[activeIndex].active {
            let word = words[activeIndex]
            let next = activeIndex + 1 < words.count ? words[activeIndex + 1].start : end
            let visible = style == .solo ? time < min(next, word.end + 0.45) : true
            if visible {
                let wordAge = time - word.start
                let bump: CGFloat
                if wordAge < 0.09 { bump = 1 + 0.16 * CGFloat(wordAge / 0.09) }
                else if wordAge < 0.24 { bump = 1.16 - 0.1 * CGFloat((wordAge - 0.09) / 0.15) }
                else { bump = 1.06 }
                let pop = style == .solo ? (wordAge < 0.1 ? 0.85 + 0.15 * CGFloat(wordAge / 0.1) : 1) : bump
                let anchor: CGPoint
                if style == .solo || base == nil {
                    anchor = center
                } else {
                    let extent = base?.extent ?? .zero
                    anchor = CGPoint(x: center.x + (word.center.x - extent.midX) * zoom, y: center.y + (word.center.y - extent.midY) * zoom)
                }
                let extent = active.extent
                let art = active.transformed(by: CGAffineTransform(translationX: -extent.midX, y: -extent.midY))
                    .transformed(by: CGAffineTransform(scaleX: zoom * pop, y: zoom * pop))
                    .transformed(by: CGAffineTransform(translationX: anchor.x, y: anchor.y))
                result = result.map { art.composited(over: $0) } ?? art
            }
        }
        return result
    }
}
