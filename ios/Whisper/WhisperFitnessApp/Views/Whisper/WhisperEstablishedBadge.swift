import SwiftUI

/// Public green-seal chip rendered next to a username when the account is at
/// least 30 days old AND has never collected a medium+ safety strike.
///
/// The point isn't to celebrate the user — it's to make *brand-new* and
/// *throttled* accounts visibly stand out. A profile with no chip is either
/// fresh (deserves caution) or restricted (separate chip). A profile with
/// this chip has stuck around without burning anyone.
///
/// Shares the seal silhouette with verified / admin so the badge row reads as
/// a cohesive set — only the colour and the inner glyph differ.
struct WhisperEstablishedBadge: View {
    var size: CGFloat = 14

    var body: some View {
        WhisperSealBadge(
            colors: [
                Color(red: 0.36, green: 0.82, blue: 0.55),
                Color(red: 0.18, green: 0.62, blue: 0.40)
            ],
            shadowColor: Color(red: 0.18, green: 0.62, blue: 0.40),
            size: size,
            accessibilityLabel: "Established member, 30+ days with a clean safety record"
        ) {
            Image(systemName: "leaf.fill")
                .font(.system(size: size * 0.5, weight: .black))
        }
    }
}

#Preview {
    HStack(spacing: 8) {
        WhisperEstablishedBadge(size: 12)
        WhisperEstablishedBadge(size: 16)
        WhisperEstablishedBadge(size: 22)
    }
    .padding()
}
