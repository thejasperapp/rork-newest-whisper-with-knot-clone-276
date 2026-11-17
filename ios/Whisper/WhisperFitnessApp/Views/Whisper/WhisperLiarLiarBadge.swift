import SwiftUI

/// Compact "Liar Liar" chip rendered next to a username when they've earned
/// 3+ false / misleading fact-checks in the last 30 days. Designed to sit
/// alongside `VerifiedBadge` so callers don't need to know which one is
/// active — both render inline.
struct WhisperLiarLiarBadge: View {
    var size: CGFloat = 14
    /// When true the chip renders in a subdued "appeal pending" state.
    var muted: Bool = false

    var body: some View {
        Text("\u{1F921}") // 🤡
            .font(.system(size: size))
            .opacity(muted ? 0.5 : 1)
            .accessibilityLabel("Liar Liar badge")
    }
}

#Preview {
    HStack(spacing: 8) {
        WhisperLiarLiarBadge(size: 12)
        WhisperLiarLiarBadge(size: 16)
        WhisperLiarLiarBadge(size: 18, muted: true)
    }
    .padding()
}
