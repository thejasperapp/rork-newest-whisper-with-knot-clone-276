import SwiftUI

/// The original layered, gently morphing blob, reused as the Jasper tuning control.
struct WhisperEmberPersonalityBlob: View {
    let mode: WhisperEmberCoachMode
    let size: CGFloat
    var seed: Double = 0
    var showsIcon: Bool = true
    var usesWhisperColors: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let layers: [(CGFloat, Double, Double, Double)] = [
        (0.98, 0.0, 0.40, 0.7),
        (0.86, 1.7, 0.60, 1.05),
        (0.72, 3.3, 1.00, 1.45),
    ]

    private var glyphColor: Color {
        if usesWhisperColors { return .black.opacity(0.78) }
        switch mode.resolved {
        case .auto, .regular, .guardian: return Color.black.opacity(0.78)
        case .drillSergeant, .scientist: return .white
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 1.7 : timeline.date.timeIntervalSinceReferenceDate + seed * 17.9
            ZStack {
                Canvas { context, canvasSize in
                    let cx = canvasSize.width / 2
                    let cy = canvasSize.height / 2
                    let R = size / 2
                    let gradient = SwiftUI.Gradient(colors: usesWhisperColors
                        ? [WhisperBrandGradient.amber, WhisperBrandGradient.accent, WhisperBrandGradient.rose]
                        : [mode.softAccent, mode.accent, mode.deepAccent])
                    for (scale, phase, opacity, speed) in Self.layers {
                        let path = Self.blobPath(cx: cx, cy: cy, R: R * scale, t: t * speed + phase)
                        context.opacity = opacity
                        context.fill(path, with: .linearGradient(gradient,
                            startPoint: CGPoint(x: cx - R, y: cy - R),
                            endPoint: CGPoint(x: cx + R, y: cy + R)))
                    }
                    let highlight = Self.blobPath(cx: cx - R * 0.16, cy: cy - R * 0.18,
                        R: R * 0.42, t: t * 1.6 + 0.6)
                    context.opacity = 1
                    context.fill(highlight, with: .color(.white.opacity(0.28)))
                }
                .frame(width: size * 1.5, height: size * 1.5)
                if showsIcon {
                    Image(systemName: mode.icon)
                        .font(.system(size: size * 0.42, weight: .heavy))
                        .foregroundStyle(glyphColor)
                        .shadow(color: (usesWhisperColors ? WhisperBrandGradient.rose : mode.deepAccent).opacity(0.5), radius: 4, y: 1)
                }
            }
        }
        .frame(width: size * 1.5, height: size * 1.5)
        .shadow(color: (usesWhisperColors ? WhisperBrandGradient.rose : mode.accent).opacity(0.38), radius: 10, y: 4)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func blobPath(cx: CGFloat, cy: CGFloat, R: CGFloat, t: Double) -> Path {
        var path = Path()
        for i in 0...64 {
            let a = (Double(i) / 64.0) * 2 * .pi
            let wob = 0.11 * sin(3 * a + t) + 0.07 * sin(5 * a - 1.3 * t) + 0.05 * sin(2 * a + 0.7 * t)
            let r = R * (1 + CGFloat(wob))
            let point = CGPoint(x: cx + CoreGraphics.cos(a) * r, y: cy + CoreGraphics.sin(a) * r)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

struct WhisperEmberBlobPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.88 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.55), value: configuration.isPressed)
    }
}
