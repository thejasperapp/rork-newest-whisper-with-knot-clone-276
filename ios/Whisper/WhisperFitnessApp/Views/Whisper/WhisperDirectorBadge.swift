import SwiftUI

/// The Whisper Director badge — a black film-aperture seal with a white
/// clapperboard glyph. Worn by the Whisper media team (directors who produce
/// Featured Film Friday and run the studio workspace). The seal is ink-black
/// in light mode (with a subtle ring) and flips to white-on-black in dark
/// mode so it stays legible on Pitch Black surfaces.
struct WhisperDirectorBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    var size: CGFloat = 14

    var body: some View {
        ZStack {
            Image(systemName: "seal.fill")
                .font(.system(size: size, weight: .black))
                .foregroundStyle(
                    colorScheme == .dark
                        ? Color.white
                        : Color(red: 0.10, green: 0.10, blue: 0.12)
                )
            Image(systemName: "film.stack.fill")
                .font(.system(size: size * 0.42, weight: .black))
                .foregroundStyle(
                    colorScheme == .dark ? Color.black : Color.white
                )
        }
        .accessibilityLabel("Whisper Director")
        .shadow(
            color: colorScheme == .dark
                ? Color.white.opacity(0.35)
                : Color.black.opacity(0.5),
            radius: 2.5,
            x: 0,
            y: 1
        )
    }
}

#Preview {
    HStack(spacing: 8) {
        WhisperDirectorBadge(size: 12)
        WhisperDirectorBadge(size: 16)
        WhisperDirectorBadge(size: 22)
    }
    .padding()
}
