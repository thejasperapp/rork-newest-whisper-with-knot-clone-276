import SwiftUI

/// Whisper's paper-and-pastel illustration language, drawn locally at any size.
struct WhisperMembershipIllustration: View {
    enum Kind { case one, coach, badge }
    let kind: Kind
    @Environment(\.colorScheme) private var colorScheme

    private let ink = Color(red: 0.22, green: 0.20, blue: 0.19)
    private let paper = Color(red: 1, green: 0.96, blue: 0.87)
    private let peach = Color(red: 1, green: 0.78, blue: 0.61)
    private let pink = Color(red: 0.98, green: 0.76, blue: 0.81)
    private let butter = Color(red: 1, green: 0.89, blue: 0.58)
    private let sage = Color(red: 0.76, green: 0.85, blue: 0.76)

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 340, size.height / 206)
            var canvas = context
            canvas.translateBy(x: (size.width - 340 * scale) / 2, y: (size.height - 206 * scale) / 2)
            canvas.scaleBy(x: scale, y: scale)
            let outerInk = colorScheme == .dark ? Color(white: 0.72) : ink
            func draw(_ path: Path, _ fill: Color? = nil, _ line: Color? = nil) {
                if let fill { canvas.fill(path, with: .color(fill)) }
                canvas.stroke(path, with: .color(line ?? ink), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            func line(_ points: [CGPoint], _ color: Color? = nil) {
                var path = Path(); path.addLines(points); draw(path, nil, color)
            }
            func card(_ rect: CGRect, _ color: Color, radius: CGFloat = 12) {
                draw(Path(roundedRect: rect, cornerRadius: radius), color)
            }
            func spark(_ x: CGFloat, _ y: CGFloat) {
                line([.init(x: x - 5, y: y), .init(x: x + 5, y: y)], outerInk)
                line([.init(x: x, y: y - 5), .init(x: x, y: y + 5)], outerInk)
            }
            canvas.fill(Path(ellipseIn: CGRect(x: 48, y: 184, width: 244, height: 10)), with: .color(peach.opacity(0.17)))
            var ribbon = Path()
            ribbon.move(to: CGPoint(x: 28, y: 130))
            ribbon.addCurve(to: CGPoint(x: 310, y: 75), control1: CGPoint(x: 17, y: 3), control2: CGPoint(x: 288, y: 204))
            canvas.stroke(ribbon, with: .color(outerInk.opacity(0.4)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [3, 5]))
            spark(53, 59); spark(287, 147); spark(273, 34)

            if kind == .one {
                var envelope = Path()
                envelope.addLines([.init(x: 62, y: 104), .init(x: 151, y: 38), .init(x: 247, y: 104), .init(x: 247, y: 179), .init(x: 62, y: 179)])
                envelope.closeSubpath(); draw(envelope, pink)
                card(CGRect(x: 87, y: 48, width: 139, height: 112), paper)
                if let logo = canvas.resolveSymbol(id: "mark") { canvas.draw(logo, at: CGPoint(x: 156, y: 81)) }
                line([.init(x: 113, y: 110), .init(x: 196, y: 110)])
                line([.init(x: 129, y: 122), .init(x: 180, y: 122)])
                var front = Path()
                front.addLines([.init(x: 62, y: 104), .init(x: 151, y: 152), .init(x: 247, y: 104), .init(x: 247, y: 179), .init(x: 62, y: 179)])
                front.closeSubpath(); draw(front, peach)
                line([.init(x: 62, y: 179), .init(x: 122, y: 136)])
                line([.init(x: 247, y: 179), .init(x: 182, y: 136)])
                draw(Path(ellipseIn: CGRect(x: 221, y: 43, width: 53, height: 53)), butter)
                line([.init(x: 247.5, y: 58), .init(x: 247.5, y: 81)])
                line([.init(x: 236, y: 69.5), .init(x: 259, y: 69.5)])
                var plane = Path()
                plane.addLines([.init(x: 19, y: 103), .init(x: 72, y: 89), .init(x: 54, y: 128), .init(x: 44, y: 112)])
                plane.closeSubpath(); draw(plane, sage)
                line([.init(x: 44, y: 112), .init(x: 72, y: 89)])
            } else {
                card(CGRect(x: 90, y: 41, width: 139, height: 140), kind == .coach ? sage : pink)
                card(CGRect(x: 102, y: 51, width: 115, height: 117), paper, radius: 8)
                card(CGRect(x: 132, y: 29, width: 57, height: 21), peach, radius: 7)
                if let logo = canvas.resolveSymbol(id: "mark") { canvas.draw(logo, at: CGPoint(x: 160, y: 81)) }
                for y: CGFloat in [113, 136] {
                    draw(Path(ellipseIn: CGRect(x: 115, y: y - 7, width: 14, height: 14)), butter)
                    line([.init(x: 118, y: y), .init(x: 121, y: y + 3), .init(x: 127, y: y - 4)])
                    line([.init(x: 140, y: y), .init(x: 196, y: y)])
                }
                var tails = Path()
                tails.addLines([.init(x: 238, y: 131), .init(x: 222, y: 183), .init(x: 243, y: 175), .init(x: 255, y: 189), .init(x: 268, y: 131)])
                tails.closeSubpath(); draw(tails, pink)
                draw(Path(ellipseIn: CGRect(x: 222, y: 101, width: 65, height: 65)), butter)
                draw(Path(ellipseIn: CGRect(x: 230, y: 109, width: 49, height: 49)), paper)
                line([.init(x: 242, y: 133), .init(x: 251, y: 143), .init(x: 269, y: 123)])
                card(CGRect(x: 45, y: 129, width: 40, height: 8), peach, radius: 4)
                card(CGRect(x: 40, y: 119, width: 10, height: 28), pink, radius: 4)
                card(CGRect(x: 80, y: 119, width: 10, height: 28), pink, radius: 4)
            }
        } symbols: {
            Image("WhisperLogo").resizable().renderingMode(.template).scaledToFit()
                .foregroundStyle(ink).frame(width: 59, height: 31).tag("mark")
        }
        .frame(height: 206)
        .accessibilityHidden(true)
    }
}
