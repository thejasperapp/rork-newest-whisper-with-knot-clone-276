import SwiftUI

/// Adds a subtle gray hairline outline around the top edges of a sheet's
/// content so the boundary between the sheet and the dimmed background is
/// readable in dark mode (where the system blur leaves no visible edge).
///
/// Light mode keeps the system look untouched — the contrast between white
/// content and the dimmed background is already strong enough there.
extension View {
    func whisperSheetOutline(cornerRadius: CGFloat = 22) -> some View {
        modifier(WhisperSheetOutlineModifier(cornerRadius: cornerRadius))
    }
}

private struct WhisperSheetOutlineModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.overlay {
            if colorScheme == .dark {
                UnevenRoundedRectangle(
                    topLeadingRadius: cornerRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: cornerRadius,
                    style: .continuous
                )
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
    }
}
