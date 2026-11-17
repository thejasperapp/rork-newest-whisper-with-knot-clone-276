import SwiftUI

/// Soft folded-plane outline, matching Whisper's rounded tab and sharing vocabulary.
struct WhisperRoundedGlyph: View {
    enum Kind { case plane, home, search, heart, comment, share, repost }
    var kind: Kind = .plane
    var size: CGFloat = 24
    var selected: Bool = false
    var body: some View {
        ZStack {
            if selected {
                glyph.fill(style: FillStyle(eoFill: true))
                glyph.stroke(style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            } else {
                glyph.stroke(style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
            if selected && kind == .plane {
                Path { path in
                    // Extend past the outside edge so the wings remain separated.
                    path.move(to: CGPoint(x: size * 0.25, y: size * 0.57))
                    path.addLine(to: CGPoint(x: size * 0.66, y: size * 0.34))
                }
                .stroke(.black, style: StrokeStyle(lineWidth: size * 0.095, lineCap: .round, lineJoin: .round))
                .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
    private var glyph: Path {
        Path { p in
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
            switch kind {
            case .plane:
                p.move(to: point(0.23, 0.12))
                p.addLine(to: point(0.78, 0.12))
                p.addCurve(to: point(0.88, 0.30), control1: point(0.94, 0.12), control2: point(0.97, 0.19))
                p.addLine(to: point(0.54, 0.87))
                p.addCurve(to: point(0.39, 0.84), control1: point(0.49, 0.96), control2: point(0.41, 0.94))
                p.addLine(to: point(0.30, 0.54))
                p.addLine(to: point(0.12, 0.35))
                p.addCurve(to: point(0.23, 0.12), control1: point(0.02, 0.24), control2: point(0.08, 0.12))
                p.closeSubpath()
                p.move(to: point(0.30, 0.54)); p.addLine(to: point(0.66, 0.34))
            case .repost:
                p.move(to: point(0.87, 0.39))
                p.addCurve(to: point(0.14, 0.29), control1: point(0.78, 0.05), control2: point(0.36, 0.04))
                p.move(to: point(0.14, 0.08))
                p.addLine(to: point(0.14, 0.31))
                p.addLine(to: point(0.37, 0.31))
                p.move(to: point(0.13, 0.61))
                p.addCurve(to: point(0.86, 0.71), control1: point(0.22, 0.95), control2: point(0.64, 0.96))
                p.move(to: point(0.86, 0.92))
                p.addLine(to: point(0.86, 0.69))
                p.addLine(to: point(0.63, 0.69))
            case .heart:
                p.move(to: point(0.50, 0.86))
                p.addCurve(to: point(0.10, 0.35), control1: point(0.32, 0.74), control2: point(0.10, 0.58))
                p.addCurve(to: point(0.50, 0.24), control1: point(0.10, 0.09), control2: point(0.38, 0.06))
                p.addCurve(to: point(0.90, 0.35), control1: point(0.62, 0.06), control2: point(0.90, 0.09))
                p.addCurve(to: point(0.50, 0.86), control1: point(0.90, 0.58), control2: point(0.68, 0.74))
                p.closeSubpath()
            case .comment:
                p.move(to: point(0.28, 0.12))
                p.addLine(to: point(0.72, 0.12))
                p.addCurve(to: point(0.90, 0.32), control1: point(0.85, 0.12), control2: point(0.90, 0.20))
                p.addLine(to: point(0.90, 0.60))
                p.addQuadCurve(to: point(0.70, 0.78), control: point(0.90, 0.78))
                p.addLine(to: point(0.44, 0.78)); p.addLine(to: point(0.19, 0.91))
                p.addQuadCurve(to: point(0.16, 0.85), control: point(0.13, 0.94))
                p.addLine(to: point(0.20, 0.74))
                p.addQuadCurve(to: point(0.10, 0.57), control: point(0.10, 0.70))
                p.addLine(to: point(0.10, 0.32))
                p.addQuadCurve(to: point(0.28, 0.12), control: point(0.10, 0.12))
                p.closeSubpath()
            case .share:
                p.move(to: point(0.13, 0.39))
                p.addLine(to: point(0.82, 0.11))
                p.addQuadCurve(to: point(0.90, 0.19), control: point(0.94, 0.06))
                p.addLine(to: point(0.63, 0.87))
                p.addQuadCurve(to: point(0.52, 0.87), control: point(0.58, 0.99))
                p.addLine(to: point(0.39, 0.61)); p.addLine(to: point(0.13, 0.49))
                p.addQuadCurve(to: point(0.13, 0.39), control: point(0.02, 0.44))
                p.closeSubpath()
                p.move(to: point(0.39, 0.61)); p.addLine(to: point(0.66, 0.35))
            case .home:
                p.move(to: point(0.13, 0.48))
                p.addQuadCurve(to: point(0.16, 0.34), control: point(0.06, 0.42))
                p.addLine(to: point(0.42, 0.12))
                p.addQuadCurve(to: point(0.58, 0.12), control: point(0.5, 0.05))
                p.addLine(to: point(0.84, 0.34))
                p.addQuadCurve(to: point(0.87, 0.48), control: point(0.94, 0.42))
                p.addLine(to: point(0.84, 0.49)); p.addLine(to: point(0.84, 0.79))
                p.addQuadCurve(to: point(0.74, 0.88), control: point(0.84, 0.88))
                p.addLine(to: point(0.61, 0.88)); p.addLine(to: point(0.61, 0.65))
                p.addQuadCurve(to: point(0.39, 0.65), control: point(0.5, 0.51))
                p.addLine(to: point(0.39, 0.88)); p.addLine(to: point(0.26, 0.88))
                p.addQuadCurve(to: point(0.16, 0.79), control: point(0.16, 0.88))
                p.addLine(to: point(0.16, 0.49)); p.closeSubpath()
            case .search:
                p.addEllipse(in: CGRect(x: size * 0.10, y: size * 0.09, width: size * 0.62, height: size * 0.62))
                p.move(to: point(0.64, 0.64)); p.addLine(to: point(0.88, 0.88))
            }
        }
    }
}
