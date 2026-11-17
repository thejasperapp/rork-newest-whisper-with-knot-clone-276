import SwiftUI

/// Small "verified coach" badge — a filled seal with a tiny dumbbell glyph.
/// Place inline next to a username (`Text("@user") + Text(" ") + ...` won't
/// render the seal mark, so always compose via HStack).
struct WhisperCoachBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    var size: CGFloat = 14

    var body: some View {
        ZStack {
            Image(systemName: "seal.fill")
                .font(.system(size: size, weight: .black))
                .foregroundStyle(WhisperTheme.coachAccent)
            Image(systemName: "dumbbell.fill")
                .font(.system(size: size * 0.45, weight: .black))
                .foregroundStyle(.white)
        }
        .accessibilityLabel("Verified Whisper coach")
        .shadow(color: WhisperTheme.coachAccent.opacity(0.35), radius: 3, x: 0, y: 1)
    }
}

/// Inline "@username + badge" helper so callers don't have to repeat the
/// HStack everywhere. Pass `isCoach: false` to render plain text.
struct WhisperUsernameLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    let username: String
    var isCoach: Bool = false
    var bold: Bool = true
    var badgeSize: CGFloat = 13

    var body: some View {
        HStack(spacing: 4) {
            Text("@\(username)")
                .font(.subheadline.weight(bold ? .bold : .semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .lineLimit(1)
            if isCoach {
                WhisperCoachBadge(size: badgeSize)
            }
        }
    }
}

extension WhisperTheme {
    /// Warm orange shared with the rest of the Whisper brand — used as the
    /// coach badge fill so it pops against both light & dark themes.
    static let coachAccent: Color = Color(red: 0.98, green: 0.45, blue: 0.13)
}
