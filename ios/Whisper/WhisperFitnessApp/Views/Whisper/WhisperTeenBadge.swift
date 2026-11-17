import SwiftUI

/// Public green-seal chip rendered next to a username when their `age_band`
/// on `profiles` is `teen`. Surfaces the fact that the account belongs to
/// someone under 18 so adult users can self-regulate before Jasper has to.
///
/// Shares the seal silhouette with the verified / admin checkmarks so the
/// badge row reads as a single cohesive set — only the colour and the inner
/// glyph differ.
struct WhisperTeenBadge: View {
    var size: CGFloat = 14

    var body: some View {
        WhisperSealBadge(
            colors: [
                Color(red: 0.18, green: 0.78, blue: 0.45),
                Color(red: 0.10, green: 0.58, blue: 0.34)
            ],
            shadowColor: Color(red: 0.10, green: 0.58, blue: 0.34),
            size: size,
            accessibilityLabel: "Teen account, under 18"
        ) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: size * 0.52, weight: .black))
        }
    }
}

#Preview {
    HStack(spacing: 8) {
        WhisperTeenBadge(size: 12)
        WhisperTeenBadge(size: 16)
        WhisperTeenBadge(size: 22)
    }
    .padding()
}
