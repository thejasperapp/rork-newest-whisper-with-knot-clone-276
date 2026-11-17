import SwiftUI

/// Knot's single-emoji treatment. The moat subtracts alpha from the bubble;
/// neither a theme-colored stroke nor an opaque background can imitate it.
/// Shared DM/group reaction layouts deliberately keep their existing treatment.
struct WhisperKnotReactionCutout: ViewModifier {
    let emoji: String?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .mask {
                Rectangle()
                    .overlay(alignment: .bottomTrailing) {
                        if emoji != nil {
                            Capsule()
                                .frame(width: 30, height: 23)
                                .offset(x: -2.3, y: 13.5)
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
            }
            // Outside the mask, so the emoji is never subtracted with the moat.
            .overlay(alignment: .bottomTrailing) {
                if let emoji {
                    Text(emoji)
                        .font(.system(size: 11.5))
                        .frame(width: 24, height: 16.5)
                        .background(scheme == .dark ? Color(white: 0.14) : Color(white: 0.92), in: Capsule())
                        .overlay { Capsule().strokeBorder(.primary.opacity(0.10), lineWidth: 0.45) }
                        .offset(x: -5.3, y: 10.5)
                        .id(emoji)
                        .transition(WhisperMessageReactionMotion.transition(reduceMotion: reduceMotion))
                        .accessibilityLabel("Knot reacted \(emoji)")
                        .allowsHitTesting(false)
                }
            }
            .animation(reduceMotion ? nil : WhisperMessageReactionMotion.landing, value: emoji)
    }
}
