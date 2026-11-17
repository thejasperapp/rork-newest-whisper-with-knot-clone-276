import SwiftUI

/// Moderator-only safety-watch seal. Rendered next to a username when:
///   1. the user has accumulated ≥3 medium+ Jasper chat-safety strikes in 30 days
///   2. AND the current viewer is a moderator / admin / owner.
///
/// Regular users *never* see this chip — `WhisperSafetyService.canSeeWatchBadge()`
/// gates every call site. This keeps the deterrent effect (mods can act fast)
/// without exposing the app to defamation risk from publicly labeling a user
/// based on an AI guess.
///
/// Shares the seal silhouette with verified / admin so the badge row reads as
/// a cohesive set.
struct WhisperSafetyWatchBadge: View {
    var size: CGFloat = 14

    var body: some View {
        WhisperSealBadge(
            colors: [
                Color(red: 1.00, green: 0.32, blue: 0.32),
                Color(red: 0.78, green: 0.10, blue: 0.10)
            ],
            shadowColor: Color(red: 0.78, green: 0.10, blue: 0.10),
            size: size,
            accessibilityLabel: "Safety watch — moderator only"
        ) {
            Image(systemName: "exclamationmark")
                .font(.system(size: size * 0.55, weight: .black))
        }
    }
}

#Preview {
    HStack(spacing: 8) {
        WhisperSafetyWatchBadge(size: 12)
        WhisperSafetyWatchBadge(size: 16)
        WhisperSafetyWatchBadge(size: 22)
    }
    .padding()
}
