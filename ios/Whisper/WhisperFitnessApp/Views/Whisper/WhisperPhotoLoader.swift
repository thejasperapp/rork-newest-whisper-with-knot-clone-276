import SwiftUI

/// Skeleton placeholder used in place of `AsyncImage`'s default empty state.
/// Renders a subtle Whisper-branded shimmer (faint W glyph + sliding sheen)
/// so loading photos read as "loading" instead of "broken / empty".
struct WhisperPhotoLoader: View {
    @Environment(\.colorScheme) private var colorScheme
    /// When `true`, hides the W glyph and only shows the gray box + sheen.
    /// Used for very small thumbnails (avatars, chip art) where the logo
    /// would feel overbearing.
    var compact: Bool = false
    var cornerRadius: CGFloat = 0
    var quiet: Bool = false

    @State private var phase: CGFloat = -1

    var body: some View {
        ZStack {
            base
            if !compact && !quiet {
                WhisperTraceLogo(size: 44, lineWidth: 3, tint: WhisperTheme.muted(colorScheme).opacity(0.7))
            }
            if !quiet { sheen }
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
        .onAppear {
            guard !quiet else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
        .accessibilityHidden(true)
    }

    private var base: some View {
        Rectangle()
            .fill(colorScheme == .dark
                  ? Color.white.opacity(0.06)
                  : Color.black.opacity(0.05))
    }

    /// Diagonal highlight that sweeps from leading to trailing on a loop —
    /// the classic shimmer look used by Instagram / iMessage.
    private var sheen: some View {
        GeometryReader { geo in
            let w = geo.size.width
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0), location: 0),
                    .init(color: .white.opacity(colorScheme == .dark ? 0.10 : 0.55), location: 0.5),
                    .init(color: .white.opacity(0), location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: w * 0.7, height: geo.size.height * 1.6)
            .rotationEffect(.degrees(20))
            .offset(x: phase * (w + w * 0.7) - w * 0.7)
            .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    VStack(spacing: 12) {
        WhisperPhotoLoader(cornerRadius: 14)
            .frame(width: 300, height: 200)
        WhisperPhotoLoader(compact: true, cornerRadius: 22)
            .frame(width: 44, height: 44)
    }
    .padding(24)
    .background(Color.black)
}
