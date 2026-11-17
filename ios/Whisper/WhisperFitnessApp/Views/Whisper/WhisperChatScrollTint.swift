import SwiftUI

/// Changes only the painted bubble, never text, photos, layout or scroll state.
struct WhisperChatScrollTint: ViewModifier {
    let mine: Bool
    @Environment(\.whisperChatAppearance) private var appearance
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.whisperChatDesign) private var design
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let enabled = appearance != .classic && !reduceMotion && contrast != .increased
        let direction: Double = mine || scheme == .dark ? -1 : 1
        if enabled {
            content
                .overlay {
                    if !reduceTransparency {
                        LinearGradient(colors: [.white.opacity(mine ? 0.12 : 0.3), .clear, .black.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            .mask(content).allowsHitTesting(false)
                    }
                }
                .shadow(color: (design?.palette(scheme) ?? appearance.palette(scheme)).accent.opacity(0.12), radius: 7, x: 0, y: 3)
                .visualEffect { effect, proxy in
                    effect.brightness(direction * min(1, max(0, proxy.frame(in: .global).midY / 900)) * 0.045)
                }
        } else {
            content
        }
    }
}
