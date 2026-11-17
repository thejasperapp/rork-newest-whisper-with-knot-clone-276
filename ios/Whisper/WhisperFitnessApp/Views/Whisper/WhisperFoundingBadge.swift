import SwiftUI

/// Public purple "Founding Member" seal rendered next to users whose account
/// was created during the launch window (before `foundingCutoff`). Pure
/// recognition — no privileges attached — so we can shower the earliest
/// supporters without committing to anything we can't sustain.
///
/// Shares the seal silhouette with verified / admin so the badge row reads
/// as a cohesive set — only the colour and the inner glyph differ.
struct WhisperFoundingBadge: View {
    var size: CGFloat = 14

    var body: some View {
        WhisperSealBadge(
            colors: [
                Color(red: 0.80, green: 0.55, blue: 1.00),
                Color(red: 0.47, green: 0.30, blue: 0.92),
                Color(red: 0.28, green: 0.18, blue: 0.78)
            ],
            shadowColor: Color(red: 0.47, green: 0.30, blue: 0.92),
            size: size,
            accessibilityLabel: "Founding member"
        ) {
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.52, weight: .black))
        }
    }
}

#Preview {
    HStack(spacing: 8) {
        WhisperFoundingBadge(size: 12)
        WhisperFoundingBadge(size: 16)
        WhisperFoundingBadge(size: 22)
    }
    .padding()
}
