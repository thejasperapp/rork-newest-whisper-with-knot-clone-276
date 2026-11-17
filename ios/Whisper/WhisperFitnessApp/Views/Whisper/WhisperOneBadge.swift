import SwiftUI

/// The black "+" seal shown next to Whisper One members' usernames — the
/// signature perk promised on the paywall ("A black + badge on your
/// profile"). In dark mode the seal flips to white with a black glyph so it
/// stays legible on the dark surface.
struct WhisperOneBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    var size: CGFloat = 14

    var body: some View {
        WhisperSealBadge(
            colors: colorScheme == .dark
                ? [Color.white, Color(red: 0.85, green: 0.85, blue: 0.87)]
                : [Color(red: 0.16, green: 0.16, blue: 0.18), Color.black],
            shadowColor: colorScheme == .dark
                ? Color.white.opacity(0.5)
                : Color.black.opacity(0.6),
            size: size,
            accessibilityLabel: "Whisper One member"
        ) {
            Image(systemName: "plus")
                .font(.system(size: size * 0.52, weight: .black))
                .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
        }
    }
}

#Preview {
    HStack(spacing: 8) {
        WhisperOneBadge(size: 12)
        WhisperOneBadge(size: 16)
        WhisperOneBadge(size: 22)
    }
    .padding()
}
