import SwiftUI

/// Public indigo-seal chip rendered when a user has been around long enough
/// AND has earned meaningful positive social signal — minimum account age,
/// zero medium+ strikes, and a follower count past the trust threshold.
///
/// Sits one tier above Established: Established says "stuck around without
/// burning anyone," Trusted says "stuck around AND people actually rely on
/// them." Auto-derived; never handed out manually.
struct WhisperTrustedBadge: View {
    var size: CGFloat = 14

    var body: some View {
        WhisperSealBadge(
            colors: [
                Color(red: 0.50, green: 0.55, blue: 0.98),
                Color(red: 0.27, green: 0.30, blue: 0.78)
            ],
            shadowColor: Color(red: 0.27, green: 0.30, blue: 0.78),
            size: size,
            accessibilityLabel: "Trusted member — long-standing account with positive standing"
        ) {
            Image(systemName: "hand.thumbsup.fill")
                .font(.system(size: size * 0.5, weight: .black))
        }
    }
}

#Preview {
    HStack(spacing: 8) {
        WhisperTrustedBadge(size: 12)
        WhisperTrustedBadge(size: 16)
        WhisperTrustedBadge(size: 22)
    }
    .padding()
}
