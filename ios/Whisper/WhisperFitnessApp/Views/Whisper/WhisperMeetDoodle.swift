import SwiftUI

/// Native vector counterpart of MeetLanding's mug, pencil and video-card drawing.
struct WhisperMeetDoodle: View {
    var symbol: String? = nil
    var height: CGFloat = 164
    var illustration: WhisperIllustrationKind? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let kind = illustration ?? symbol.map(WhisperIllustrationKind.forSymbol) {
            WhisperEmptyIllustration(kind: kind, height: height)
        } else {
            meetingScene
        }
    }

    private var meetingScene: some View {
        Canvas { context, size in
            let scale = min(size.width / 300, size.height / 164)
            context.translateBy(x: (size.width - 300 * scale) / 2, y: 0)
            context.scaleBy(x: scale, y: scale)
            let ink = WhisperTheme.ink(colorScheme).opacity(0.7)
            let stroke = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            func line(_ draw: (inout Path) -> Void) {
                var path = Path(); draw(&path)
                context.stroke(path, with: .color(ink), style: stroke)
            }
            line { p in p.move(to: CGPoint(x: 22, y: 146)); p.addLine(to: CGPoint(x: 278, y: 146)) }
            var blob = Path()
            blob.move(to: CGPoint(x: 44, y: 146))
            blob.addCurve(to: CGPoint(x: 74, y: 88), control1: CGPoint(x: 36, y: 118), control2: CGPoint(x: 48, y: 92))
            blob.addCurve(to: CGPoint(x: 104, y: 128), control1: CGPoint(x: 96, y: 85), control2: CGPoint(x: 108, y: 106))
            blob.addCurve(to: CGPoint(x: 78, y: 146), control1: CGPoint(x: 101, y: 142), control2: CGPoint(x: 90, y: 146)); blob.closeSubpath()
            context.fill(blob, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.76, blue: 0.82), Color(red: 0.98, green: 0.66, blue: 0.75)]), startPoint: CGPoint(x: 44, y: 88), endPoint: CGPoint(x: 104, y: 146)))
            var mug = Path()
            mug.addLines([CGPoint(x: 112, y: 146), CGPoint(x: 118, y: 96), CGPoint(x: 174, y: 96), CGPoint(x: 180, y: 146)]); mug.closeSubpath()
            context.fill(mug, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.84, blue: 0.60), WhisperBrandGradient.accent]), startPoint: CGPoint(x: 118, y: 96), endPoint: CGPoint(x: 180, y: 146)))
            context.stroke(mug, with: .color(ink), style: stroke)
            line { p in p.move(to: CGPoint(x: 176, y: 106)); p.addCurve(to: CGPoint(x: 178, y: 132), control1: CGPoint(x: 196, y: 104), control2: CGPoint(x: 200, y: 130)) }
            line { p in p.move(to: CGPoint(x: 134, y: 84)); p.addCurve(to: CGPoint(x: 134, y: 58), control1: CGPoint(x: 128, y: 74), control2: CGPoint(x: 140, y: 68)) }
            line { p in p.move(to: CGPoint(x: 152, y: 84)); p.addCurve(to: CGPoint(x: 152, y: 54), control1: CGPoint(x: 146, y: 72), control2: CGPoint(x: 160, y: 66)) }
            var pencilContext = context
            pencilContext.translateBy(x: 200, y: 110); pencilContext.rotate(by: .degrees(-62)); pencilContext.translateBy(x: -200, y: -110)
            let pencil = Path(roundedRect: CGRect(x: 192, y: 52, width: 16, height: 96), cornerRadius: 2)
            pencilContext.fill(pencil, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.89, blue: 0.54), WhisperBrandGradient.amber]), startPoint: CGPoint(x: 192, y: 52), endPoint: CGPoint(x: 208, y: 148)))
            pencilContext.stroke(pencil, with: .color(ink), style: stroke)
            var tip = Path(); tip.addLines([CGPoint(x: 192, y: 148), CGPoint(x: 200, y: 164), CGPoint(x: 208, y: 148)]); tip.closeSubpath()
            pencilContext.fill(tip, with: .color(Color(red: 1, green: 0.91, blue: 0.81))); pencilContext.stroke(tip, with: .color(ink), style: stroke)
            pencilContext.fill(Path(roundedRect: CGRect(x: 192, y: 52, width: 16, height: 10), cornerRadius: 2), with: .color(WhisperBrandGradient.rose.opacity(0.7)))
            var cardContext = context
            cardContext.translateBy(x: 236, y: 112); cardContext.rotate(by: .degrees(-8)); cardContext.translateBy(x: -236, y: -112)
            let card = Path(roundedRect: CGRect(x: 204, y: 84, width: 72, height: 56), cornerRadius: 8)
            cardContext.fill(card, with: .color(Color(red: 1, green: 0.94, blue: 0.95))); cardContext.stroke(card, with: .color(ink), style: stroke)
            cardContext.stroke(Path(roundedRect: CGRect(x: 218, y: 100, width: 28, height: 24), cornerRadius: 5), with: .color(ink), style: stroke)
            var lens = Path(); lens.addLines([CGPoint(x: 246, y: 108), CGPoint(x: 260, y: 100), CGPoint(x: 260, y: 124), CGPoint(x: 246, y: 116)]); lens.closeSubpath()
            cardContext.stroke(lens, with: .color(ink), style: stroke)
            context.fill(Path(ellipseIn: CGRect(x: 253, y: 21, width: 18, height: 18)), with: .color(Color(red: 1, green: 0.89, blue: 0.54)))
            line { p in p.move(to: CGPoint(x: 186, y: 38)); p.addCurve(to: CGPoint(x: 246, y: 22), control1: CGPoint(x: 200, y: 18), control2: CGPoint(x: 224, y: 40)) }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
