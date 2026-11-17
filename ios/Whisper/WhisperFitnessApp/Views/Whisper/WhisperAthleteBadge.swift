import SwiftUI

/// The Verified Athlete badge — a crimson seal with a white medal glyph.
/// Worn by athletes who passed team review and hold the annual athlete
/// badge. Colour mirrors the web chip (#ed3b52) exactly.
struct WhisperAthleteBadge: View {
    var size: CGFloat = 14

    private var crimson: Color { Color(red: 0.93, green: 0.23, blue: 0.32) }

    var body: some View {
        ZStack {
            Image(systemName: "seal.fill")
                .font(.system(size: size, weight: .black))
                .foregroundStyle(crimson)
            Image(systemName: "medal.fill")
                .font(.system(size: size * 0.44, weight: .black))
                .foregroundStyle(.white)
        }
        .accessibilityLabel("Verified Athlete")
        .shadow(color: crimson.opacity(0.5), radius: 2.5, x: 0, y: 1)
    }
}

#Preview {
    HStack(spacing: 8) {
        WhisperAthleteBadge(size: 12)
        WhisperAthleteBadge(size: 16)
        WhisperAthleteBadge(size: 22)
    }
    .padding()
}
