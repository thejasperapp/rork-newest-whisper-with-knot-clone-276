import SwiftUI

/// A theme-tinted floating control surface; never paints a full-width bottom shelf.
struct WhisperChatComposerGlass: View {
    var radius: CGFloat = 26
    @Environment(\.colorScheme) private var scheme
    @Environment(\.whisperChatAppearance) private var appearance
    @Environment(\.whisperChatDesign) private var design
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let palette = design?.palette(scheme) ?? appearance.palette(scheme)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if reduceTransparency || contrast == .increased {
                shape.fill(palette.incoming)
            } else {
                shape.fill(.regularMaterial)
                    .overlay { shape.fill(palette.canvas.opacity(0.16)) }
            }
        }
        .overlay { shape.strokeBorder(palette.incomingText.opacity(contrast == .increased ? 0.5 : 0.06), lineWidth: 0.75) }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
