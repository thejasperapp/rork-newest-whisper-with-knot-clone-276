import SwiftUI

/// The Whisper Blogger badge — a deep teal-green seal with a white pen
/// glyph. Worn by dedicated writers (articles & film reviews). Colour
/// mirrors the web chip (#0d8a6f) exactly.
struct WhisperBloggerBadge: View {
    var size: CGFloat = 14

    private var ink: Color { Color(red: 0.05, green: 0.54, blue: 0.44) }

    var body: some View {
        ZStack {
            Image(systemName: "seal.fill")
                .font(.system(size: size, weight: .black))
                .foregroundStyle(ink)
            Image(systemName: "pencil.line")
                .font(.system(size: size * 0.42, weight: .black))
                .foregroundStyle(.white)
        }
        .accessibilityLabel("Whisper Blogger")
        .shadow(color: ink.opacity(0.5), radius: 2.5, x: 0, y: 1)
    }
}

#Preview {
    HStack(spacing: 8) {
        WhisperBloggerBadge(size: 12)
        WhisperBloggerBadge(size: 16)
        WhisperBloggerBadge(size: 22)
    }
    .padding()
}
