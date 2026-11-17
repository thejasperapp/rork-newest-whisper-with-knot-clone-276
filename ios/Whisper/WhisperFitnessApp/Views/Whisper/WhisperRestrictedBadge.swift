import SwiftUI

/// Public amber seal rendered next to a username whose account has been
/// auto-restricted (DM throttle / cooldowns) after hitting the Safety Watch
/// threshold. Unlike the moderator-only Safety Watch chip, this one is
/// visible to everyone — it's the escalation step where the account loses
/// its quiet status and other users get a heads-up to be cautious.
///
/// Important: this is not a public accusation. The inner glyph is a neutral
/// hand-raised stop icon — the meaning is "automated rate-limit in place",
/// not any AI guess about the user's intent.
///
/// Shares the seal silhouette with verified / admin so the badge row reads
/// as a cohesive set.
struct WhisperRestrictedBadge: View {
    var size: CGFloat = 14

    var body: some View {
        WhisperSealBadge(
            colors: [
                Color(red: 0.98, green: 0.62, blue: 0.18),
                Color(red: 0.86, green: 0.40, blue: 0.10)
            ],
            shadowColor: Color(red: 0.86, green: 0.40, blue: 0.10),
            size: size,
            accessibilityLabel: "Limited account, automated DM restrictions in place"
        ) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: size * 0.5, weight: .black))
        }
    }
}

#Preview {
    HStack(spacing: 8) {
        WhisperRestrictedBadge(size: 12)
        WhisperRestrictedBadge(size: 16)
        WhisperRestrictedBadge(size: 22)
    }
    .padding()
}
