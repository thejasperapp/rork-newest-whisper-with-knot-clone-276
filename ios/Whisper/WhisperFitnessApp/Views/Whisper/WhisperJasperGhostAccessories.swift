import SwiftUI

/// Personality details shared by the pearl mascot and its compact pill peek.
struct WhisperJasperGhostAccessories: View {
    let mode: WhisperEmberCoachMode
    var isPeek: Bool = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            if mode.resolved == .guardian {
                Ellipse()
                    .strokeBorder(
                        LinearGradient(colors: [.white, WhisperBrandGradient.amber.opacity(0.8), .white],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: max(1.3, width * 0.023))
                    .frame(width: width * 0.48, height: width * 0.12)
                    .shadow(color: WhisperBrandGradient.amber.opacity(0.18), radius: width * 0.04)
                    .position(x: width * 0.5, y: -width * 0.07)
            } else if mode.resolved == .scientist {
                Canvas { context, size in
                    let w = size.width
                    let y = size.height * (isPeek ? 0.40 : 0.324)
                    let diameter = w * (isPeek ? 0.29 : 0.215)
                    let leftX = w * (isPeek ? 0.33 : 0.382)
                    let rightX = w * (isPeek ? 0.68 : 0.607)
                    let lineWidth = max(1.1, w * 0.018)
                    var frame = Path()
                    frame.addEllipse(in: CGRect(x: leftX - diameter / 2, y: y - diameter / 2,
                        width: diameter, height: diameter))
                    frame.addEllipse(in: CGRect(x: rightX - diameter / 2, y: y - diameter / 2,
                        width: diameter, height: diameter))
                    frame.move(to: CGPoint(x: leftX + diameter / 2, y: y))
                    frame.addQuadCurve(to: CGPoint(x: rightX - diameter / 2, y: y),
                        control: CGPoint(x: (leftX + rightX) / 2, y: y - w * 0.035))
                    frame.move(to: CGPoint(x: leftX - diameter / 2, y: y))
                    frame.addLine(to: CGPoint(x: leftX - diameter / 2 - w * 0.05, y: y - w * 0.025))
                    frame.move(to: CGPoint(x: rightX + diameter / 2, y: y))
                    frame.addLine(to: CGPoint(x: rightX + diameter / 2 + w * 0.05, y: y - w * 0.025))
                    context.stroke(frame, with: .color(Color(white: 0.14)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
                .frame(width: width, height: height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
