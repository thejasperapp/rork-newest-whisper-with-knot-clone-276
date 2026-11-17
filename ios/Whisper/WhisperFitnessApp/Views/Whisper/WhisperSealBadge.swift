import SwiftUI

/// Shared seal-shaped chip used by every Whisper trust & safety badge except
/// Liar Liar (which intentionally breaks the pattern as a clown chip).
///
/// Renders the same `seal.fill` silhouette as `VerifiedBadge` so the whole
/// badge row reads as a cohesive set — only the colour and the inner glyph
/// change. The inner content is masked to the seal so icons never bleed past
/// the edge.
struct WhisperSealBadge<Inner: View>: View {
    let colors: [Color]
    let shadowColor: Color
    let size: CGFloat
    let accessibilityLabel: String
    @ViewBuilder var inner: () -> Inner

    var body: some View {
        Image(systemName: "seal.fill")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(
                LinearGradient(
                    colors: colors,
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                inner()
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.18), radius: 0.4, y: 0.3)
            }
            .shadow(color: shadowColor.opacity(0.4), radius: 2, y: 0.5)
            .accessibilityLabel(Text(accessibilityLabel))
    }
}

#Preview {
    HStack(spacing: 8) {
        WhisperSealBadge(
            colors: [Color(red: 0.18, green: 0.78, blue: 0.45), Color(red: 0.10, green: 0.58, blue: 0.34)],
            shadowColor: Color(red: 0.10, green: 0.58, blue: 0.34),
            size: 18,
            accessibilityLabel: "Sample"
        ) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 9, weight: .black))
        }
        WhisperSealBadge(
            colors: [Color(red: 0.80, green: 0.55, blue: 1.00), Color(red: 0.47, green: 0.30, blue: 0.92)],
            shadowColor: Color(red: 0.47, green: 0.30, blue: 0.92),
            size: 18,
            accessibilityLabel: "Sample"
        ) {
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .black))
        }
    }
    .padding()
}
