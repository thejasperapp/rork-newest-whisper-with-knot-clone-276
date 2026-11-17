import SwiftUI

/// iPad-width tuning: on regular-width size classes (iPad, big split views)
/// the main content column centres at a readable width instead of
/// stretching edge-to-edge. On iPhone this is a no-op.
private struct WhisperPadContentModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: sizeClass == .regular ? maxWidth : .infinity)
            .frame(maxWidth: .infinity)
    }
}

/// Chat chrome and messages share one readable column. The surrounding scroll
/// viewport/backdrop stays full width, and narrower detail panes shrink naturally.
private struct WhisperChatContentModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: sizeClass == .regular ? 760 : .infinity)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    func whisperChatContent() -> some View {
        modifier(WhisperChatContentModifier())
    }

    /// Centre this content column at a readable width on iPad.
    func whisperPadContent(_ maxWidth: CGFloat = 720) -> some View {
        modifier(WhisperPadContentModifier(maxWidth: maxWidth))
    }
}
