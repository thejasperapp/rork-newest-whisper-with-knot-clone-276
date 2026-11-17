import UIKit

/// A quiet studio backdrop for the real Metal-rendered catalog bust and accessories.
nonisolated enum WhisperCameraEffectPortrait {
    static func draw(_ context: CGContext, size: CGSize, effect: WhisperAREffect) {
        let tint: UIColor
        switch effect {
        case .puppy: tint = UIColor(red: 0.43, green: 0.29, blue: 0.19, alpha: 1)
        case .bunny: tint = UIColor(red: 0.46, green: 0.29, blue: 0.36, alpha: 1)
        case .sunnies: tint = UIColor(red: 0.15, green: 0.33, blue: 0.34, alpha: 1)
        default: tint = UIColor(red: 0.31, green: 0.30, blue: 0.40, alpha: 1)
        }
        context.setFillColor(UIColor(white: 0.055, alpha: 1).cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        if let light = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [tint.cgColor, UIColor(white: 0.07, alpha: 1).cgColor] as CFArray, locations: [0, 1]) {
            let center = CGPoint(x: size.width * 0.36, y: size.height * 0.30)
            context.drawRadialGradient(light, startCenter: center, startRadius: 0, endCenter: center, endRadius: size.width * 0.85, options: [.drawsAfterEndLocation])
        }
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.09).cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: CGRect(x: size.width * 0.12, y: size.height * 0.10, width: size.width * 0.76, height: size.height * 0.76))
    }
}
