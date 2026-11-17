import UIKit

/// Original, cached accessory paintings. Coordinates use the shared 720 × 480 art canvas.
nonisolated enum WhisperCameraAccessoryArtwork {
    private static func shade(_ path: UIBezierPath, colors: [UIColor], context: CGContext, from: CGPoint, to: CGPoint) {
        context.saveGState(); path.addClip()
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: nil) {
            context.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        context.restoreGState()
    }
    private static func ellipse(_ rect: CGRect, _ color: UIColor) {
        color.setFill(); UIBezierPath(ovalIn: rect).fill()
    }
    private static func line(_ points: [CGPoint], color: UIColor, width: CGFloat) {
        guard let first = points.first else { return }
        let path = UIBezierPath(); path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        color.setStroke(); path.lineWidth = width; path.lineCapStyle = .round; path.lineJoinStyle = .round; path.stroke()
    }

    static func puppyEars(_ c: CGContext, _ size: CGSize) {
        for side: CGFloat in [-1, 1] {
            c.saveGState(); c.translateBy(x: side < 0 ? 154 : 566, y: 56); c.scaleBy(x: side < 0 ? 1 : -1, y: 1)
            let ear = UIBezierPath()
            ear.move(to: CGPoint(x: -16, y: 0))
            ear.addCurve(to: CGPoint(x: -100, y: 120), controlPoint1: CGPoint(x: -75, y: -32), controlPoint2: CGPoint(x: -126, y: 55))
            ear.addCurve(to: CGPoint(x: -64, y: 338), controlPoint1: CGPoint(x: -137, y: 242), controlPoint2: CGPoint(x: -109, y: 328))
            ear.addCurve(to: CGPoint(x: 64, y: 290), controlPoint1: CGPoint(x: -30, y: 376), controlPoint2: CGPoint(x: 68, y: 359))
            ear.addCurve(to: CGPoint(x: 86, y: 68), controlPoint1: CGPoint(x: 38, y: 205), controlPoint2: CGPoint(x: 135, y: 94))
            ear.addQuadCurve(to: CGPoint(x: -16, y: 0), controlPoint: CGPoint(x: 66, y: -14)); ear.close()
            c.setShadow(offset: CGSize(width: 4, height: 9), blur: 15, color: UIColor.black.withAlphaComponent(0.3).cgColor)
            UIColor(red: 0.44, green: 0.22, blue: 0.10, alpha: 1).setFill(); ear.fill()
            c.setShadow(offset: .zero, blur: 0, color: nil)
            shade(ear, colors: [UIColor(red: 0.96, green: 0.72, blue: 0.42, alpha: 1), UIColor(red: 0.60, green: 0.33, blue: 0.15, alpha: 1), UIColor(red: 0.26, green: 0.12, blue: 0.06, alpha: 1)], context: c, from: CGPoint(x: -90, y: 30), to: CGPoint(x: 80, y: 300))
            let fold = UIBezierPath()
            fold.move(to: CGPoint(x: -7, y: 45)); fold.addCurve(to: CGPoint(x: -62, y: 272), controlPoint1: CGPoint(x: -65, y: 65), controlPoint2: CGPoint(x: -87, y: 195))
            fold.addCurve(to: CGPoint(x: 20, y: 280), controlPoint1: CGPoint(x: -45, y: 335), controlPoint2: CGPoint(x: 23, y: 327))
            fold.addQuadCurve(to: CGPoint(x: -7, y: 45), controlPoint: CGPoint(x: 57, y: 75)); fold.close()
            shade(fold, colors: [UIColor(red: 0.43, green: 0.18, blue: 0.12, alpha: 1), UIColor(red: 0.91, green: 0.58, blue: 0.46, alpha: 1)], context: c, from: CGPoint(x: -55, y: 80), to: CGPoint(x: 25, y: 280))
            c.saveGState(); ear.addClip()
            for i in 0..<85 {
                let x = CGFloat((i * 47) % 207) - 120
                let y = CGFloat((i * 71) % 350)
                line([CGPoint(x: x, y: y), CGPoint(x: x + 4, y: y + 12)], color: UIColor(red: 1, green: 0.83, blue: 0.59, alpha: 0.15), width: 2)
            }
            c.restoreGState(); c.restoreGState()
        }
    }

    static func puppyNose(_ c: CGContext, _ size: CGSize) {
        for x: CGFloat in [238, 362] {
            let muzzle = UIBezierPath(ovalIn: CGRect(x: x, y: 204, width: 126, height: 100))
            shade(muzzle, colors: [UIColor(red: 1, green: 0.94, blue: 0.80, alpha: 0.96), UIColor(red: 0.74, green: 0.48, blue: 0.26, alpha: 0.94)], context: c, from: CGPoint(x: x, y: 200), to: CGPoint(x: x, y: 310))
            for d in 0..<3 { ellipse(CGRect(x: x + 28 + CGFloat(d) * 25, y: 248 + CGFloat(d % 2) * 12, width: 6, height: 6), UIColor(white: 0.20, alpha: 0.8)) }
        }
        let nose = UIBezierPath()
        nose.move(to: CGPoint(x: 270, y: 170))
        nose.addCurve(to: CGPoint(x: 450, y: 170), controlPoint1: CGPoint(x: 288, y: 127), controlPoint2: CGPoint(x: 430, y: 127))
        nose.addCurve(to: CGPoint(x: 360, y: 262), controlPoint1: CGPoint(x: 488, y: 225), controlPoint2: CGPoint(x: 389, y: 250))
        nose.addCurve(to: CGPoint(x: 270, y: 170), controlPoint1: CGPoint(x: 338, y: 254), controlPoint2: CGPoint(x: 238, y: 220)); nose.close()
        c.setShadow(offset: CGSize(width: 0, height: 6), blur: 10, color: UIColor.black.withAlphaComponent(0.32).cgColor)
        UIColor.black.setFill(); nose.fill(); c.setShadow(offset: .zero, blur: 0, color: nil)
        shade(nose, colors: [UIColor(white: 0.38, alpha: 1), UIColor(white: 0.10, alpha: 1), .black], context: c, from: CGPoint(x: 290, y: 140), to: CGPoint(x: 402, y: 262))
        ellipse(CGRect(x: 295, y: 157, width: 58, height: 22), UIColor.white.withAlphaComponent(0.6))
        line([CGPoint(x: 360, y: 260), CGPoint(x: 360, y: 285)], color: UIColor(white: 0.12, alpha: 0.85), width: 7)
    }

    static func puppyTongue(_ c: CGContext, _ size: CGSize) {
        let tongue = UIBezierPath()
        tongue.move(to: CGPoint(x: 251, y: 40)); tongue.addLine(to: CGPoint(x: 469, y: 40))
        tongue.addCurve(to: CGPoint(x: 458, y: 344), controlPoint1: CGPoint(x: 436, y: 170), controlPoint2: CGPoint(x: 500, y: 271))
        tongue.addCurve(to: CGPoint(x: 262, y: 344), controlPoint1: CGPoint(x: 432, y: 445), controlPoint2: CGPoint(x: 290, y: 444))
        tongue.addCurve(to: CGPoint(x: 251, y: 40), controlPoint1: CGPoint(x: 222, y: 280), controlPoint2: CGPoint(x: 280, y: 166)); tongue.close()
        shade(tongue, colors: [UIColor(red: 0.67, green: 0.12, blue: 0.26, alpha: 1), UIColor(red: 1, green: 0.38, blue: 0.55, alpha: 1), UIColor(red: 1, green: 0.66, blue: 0.72, alpha: 1)], context: c, from: CGPoint(x: 360, y: 45), to: CGPoint(x: 360, y: 405))
        line([CGPoint(x: 360, y: 58), CGPoint(x: 360, y: 310)], color: UIColor(red: 0.74, green: 0.20, blue: 0.36, alpha: 0.75), width: 6)
        ellipse(CGRect(x: 285, y: 254, width: 24, height: 100), UIColor.white.withAlphaComponent(0.20))
    }

    static func bunnyEars(_ c: CGContext, _ size: CGSize) {
        for side: CGFloat in [-1, 1] {
            c.saveGState(); c.translateBy(x: side < 0 ? 258 : 462, y: 454); c.scaleBy(x: side, y: 1)
            let ear = UIBezierPath()
            ear.move(to: CGPoint(x: -61, y: 0))
            ear.addCurve(to: CGPoint(x: -103, y: -339), controlPoint1: CGPoint(x: -118, y: -113), controlPoint2: CGPoint(x: -150, y: -260))
            ear.addCurve(to: CGPoint(x: 18, y: -406), controlPoint1: CGPoint(x: -89, y: -443), controlPoint2: CGPoint(x: 9, y: -470))
            ear.addCurve(to: CGPoint(x: 61, y: 0), controlPoint1: CGPoint(x: 39, y: -348), controlPoint2: CGPoint(x: 114, y: -107)); ear.close()
            c.setShadow(offset: CGSize(width: 0, height: 5), blur: 15, color: UIColor.black.withAlphaComponent(0.22).cgColor)
            UIColor.white.setFill(); ear.fill(); c.setShadow(offset: .zero, blur: 0, color: nil)
            shade(ear, colors: [UIColor(red: 0.73, green: 0.73, blue: 0.80, alpha: 1), .white, UIColor(red: 0.96, green: 0.90, blue: 0.91, alpha: 1)], context: c, from: CGPoint(x: -100, y: -220), to: CGPoint(x: 90, y: -220))
            let inside = UIBezierPath()
            inside.move(to: CGPoint(x: -27, y: -30)); inside.addCurve(to: CGPoint(x: -66, y: -337), controlPoint1: CGPoint(x: -60, y: -150), controlPoint2: CGPoint(x: -94, y: -285))
            inside.addQuadCurve(to: CGPoint(x: -9, y: -373), controlPoint: CGPoint(x: -40, y: -417))
            inside.addQuadCurve(to: CGPoint(x: 27, y: -30), controlPoint: CGPoint(x: 65, y: -159)); inside.close()
            shade(inside, colors: [UIColor(red: 0.93, green: 0.35, blue: 0.52, alpha: 1), UIColor(red: 1, green: 0.78, blue: 0.83, alpha: 1)], context: c, from: CGPoint(x: -64, y: -360), to: CGPoint(x: 28, y: -55))
            for i in 0..<12 {
                let x = CGFloat(i) * 10 - 58
                line([CGPoint(x: x, y: -8), CGPoint(x: x - 9, y: -31)], color: .white.withAlphaComponent(0.8), width: 5)
            }
            c.restoreGState()
        }
    }

    static func bunnyNose(_ c: CGContext, _ size: CGSize) {
        for side: CGFloat in [-1, 1] {
            let cheek = UIBezierPath(ovalIn: CGRect(x: side < 0 ? 166 : 416, y: 218, width: 138, height: 70))
            shade(cheek, colors: [UIColor(red: 1, green: 0.57, blue: 0.68, alpha: 0.42), UIColor(red: 1, green: 0.80, blue: 0.84, alpha: 0)], context: c, from: CGPoint(x: 360, y: 233), to: CGPoint(x: 360, y: 288))
            for row in 0..<3 {
                let y = CGFloat(row - 1) * 28 + 242
                let path = UIBezierPath(); path.move(to: CGPoint(x: 360 + side * 65, y: y))
                path.addQuadCurve(to: CGPoint(x: 360 + side * 294, y: y + CGFloat(row - 1) * 22), controlPoint: CGPoint(x: 360 + side * 173, y: y - 18))
                UIColor(white: 0.24, alpha: 0.55).setStroke(); path.lineWidth = 8; path.lineCapStyle = .round; path.stroke()
                UIColor.white.withAlphaComponent(0.92).setStroke(); path.lineWidth = 4; path.stroke()
            }
        }
        let nose = UIBezierPath()
        nose.move(to: CGPoint(x: 304, y: 217)); nose.addCurve(to: CGPoint(x: 360, y: 214), controlPoint1: CGPoint(x: 310, y: 190), controlPoint2: CGPoint(x: 347, y: 197))
        nose.addCurve(to: CGPoint(x: 416, y: 217), controlPoint1: CGPoint(x: 379, y: 192), controlPoint2: CGPoint(x: 411, y: 195))
        nose.addQuadCurve(to: CGPoint(x: 360, y: 271), controlPoint: CGPoint(x: 425, y: 240))
        nose.addQuadCurve(to: CGPoint(x: 304, y: 217), controlPoint: CGPoint(x: 298, y: 247)); nose.close()
        shade(nose, colors: [UIColor(red: 1, green: 0.70, blue: 0.79, alpha: 1), UIColor(red: 0.83, green: 0.25, blue: 0.43, alpha: 1)], context: c, from: CGPoint(x: 330, y: 195), to: CGPoint(x: 388, y: 270))
        ellipse(CGRect(x: 319, y: 207, width: 24, height: 9), UIColor.white.withAlphaComponent(0.7))
        line([CGPoint(x: 360, y: 269), CGPoint(x: 360, y: 291)], color: UIColor(red: 0.42, green: 0.18, blue: 0.23, alpha: 0.7), width: 5)
    }

    static func sunnies(_ c: CGContext, _ size: CGSize) {
        for x: CGFloat in [190, 530] {
            let frame = UIBezierPath(roundedRect: CGRect(x: x - 150, y: 155, width: 300, height: 198), cornerRadius: 76)
            shade(frame, colors: [UIColor(red: 0.42, green: 0.26, blue: 0.15, alpha: 1), UIColor(white: 0.06, alpha: 1)], context: c, from: CGPoint(x: x, y: 154), to: CGPoint(x: x, y: 352))
            let lens = UIBezierPath(roundedRect: CGRect(x: x - 130, y: 176, width: 260, height: 155), cornerRadius: 60)
            shade(lens, colors: [UIColor(red: 0.17, green: 0.31, blue: 0.38, alpha: 1), UIColor(red: 0.05, green: 0.09, blue: 0.14, alpha: 1)], context: c, from: CGPoint(x: x, y: 176), to: CGPoint(x: x, y: 332))
            c.saveGState(); lens.addClip()
            line([CGPoint(x: x - 110, y: 320), CGPoint(x: x - 14, y: 173)], color: UIColor.white.withAlphaComponent(0.24), width: 28)
            line([CGPoint(x: x - 66, y: 335), CGPoint(x: x + 37, y: 174)], color: UIColor.white.withAlphaComponent(0.10), width: 12)
            c.restoreGState()
        }
        let bridge = UIBezierPath(); bridge.move(to: CGPoint(x: 335, y: 218)); bridge.addQuadCurve(to: CGPoint(x: 385, y: 218), controlPoint: CGPoint(x: 360, y: 202))
        UIColor(white: 0.08, alpha: 1).setStroke(); bridge.lineWidth = 25; bridge.stroke()
    }

    static func halo(_ c: CGContext, _ size: CGSize) {
        let ring = UIBezierPath(ovalIn: CGRect(x: 66, y: 188, width: 588, height: 116))
        c.setShadow(offset: .zero, blur: 35, color: UIColor(red: 1, green: 0.79, blue: 0.22, alpha: 0.85).cgColor)
        UIColor(red: 0.83, green: 0.48, blue: 0.06, alpha: 1).setStroke(); ring.lineWidth = 44; ring.stroke()
        c.setShadow(offset: .zero, blur: 0, color: nil)
        UIColor(red: 1, green: 0.87, blue: 0.33, alpha: 1).setStroke(); ring.lineWidth = 28; ring.stroke()
        UIColor(red: 1, green: 0.98, blue: 0.83, alpha: 1).setStroke(); ring.lineWidth = 8; ring.stroke()
        for point in [CGPoint(x: 100, y: 145), CGPoint(x: 614, y: 330), CGPoint(x: 491, y: 138)] {
            line([CGPoint(x: point.x - 17, y: point.y), CGPoint(x: point.x + 17, y: point.y)], color: .white, width: 6)
            line([CGPoint(x: point.x, y: point.y - 25), CGPoint(x: point.x, y: point.y + 25)], color: .white, width: 6)
        }
    }
}
