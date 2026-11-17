import SwiftUI

struct WhisperEmptyIllustration: View {
    let kind: WhisperIllustrationKind
    let height: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { context, size in
            var canvas = context
            let scale = min(size.width / 300, size.height / 164)
            canvas.translateBy(x: (size.width - 300 * scale) / 2, y: (size.height - 164 * scale) / 2)
            canvas.scaleBy(x: scale, y: scale)
            WhisperIllustrationDrawing(context: canvas, ink: WhisperTheme.ink(scheme).opacity(0.72)).draw(kind)
        }
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
