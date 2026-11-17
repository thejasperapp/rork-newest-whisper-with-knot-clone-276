import SwiftUI

/// Compact 18+ seal rendered next to a username when the account holder has
/// self-attested adulthood via the safety sheet (`profiles.is_adult_attested`).
///
/// This is *not* an ID-verified mark — it's a self-declaration, and it does
/// not unlock anything destructive. The point is to let teens see at a glance
/// that the other side actively claimed to be over 18, so any inappropriate
/// behavior afterwards is unambiguous.
///
/// Matches the seal silhouette of the verified / admin checkmarks so the row
/// reads as a single cohesive set.
struct WhisperAdultBadge: View {
    var size: CGFloat = 14

    var body: some View {
        WhisperSealBadge(
            colors: [
                Color(red: 0.13, green: 0.55, blue: 0.96),
                Color(red: 0.08, green: 0.40, blue: 0.86)
            ],
            shadowColor: Color(red: 0.13, green: 0.55, blue: 0.96),
            size: size,
            accessibilityLabel: "Adult account, self-attested 18 or older"
        ) {
            Text("18+")
                .font(.system(size: size * 0.42, weight: .black, design: .rounded))
                .tracking(-0.3)
        }
    }
}

#Preview {
    HStack(spacing: 8) {
        WhisperAdultBadge(size: 12)
        WhisperAdultBadge(size: 16)
        WhisperAdultBadge(size: 22)
    }
    .padding()
}
