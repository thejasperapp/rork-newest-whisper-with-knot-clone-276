import SwiftUI

/// No material shelf. Scrolling content receives only a canvas-matched fade.
struct WhisperScrollingHeaderBackdrop: View {
    @Environment(\.whisperHeaderShelf) private var shelf
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if reduceTransparency {
                WhisperTheme.surface(colorScheme)
            } else {
                LinearGradient(stops: [
                    .init(color: WhisperTheme.surface(colorScheme).opacity(0.8), location: 0),
                    .init(color: WhisperTheme.surface(colorScheme).opacity(0.35), location: 0.4),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
        }
        .opacity(reduceTransparency ? ((shelf?.blurProgress ?? 0) > 0 ? 1 : 0) : Double(shelf?.blurProgress ?? 0))
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
