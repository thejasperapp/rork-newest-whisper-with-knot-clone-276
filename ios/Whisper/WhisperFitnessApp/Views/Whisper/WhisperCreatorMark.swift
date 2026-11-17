import SwiftUI

/// The CREATOR mark — a cursive "C" wearing the Whisper brand gradient that
/// never sits still: the sweep glides through the glyph on a slow loop with
/// a soft bloom behind it, so the creator-post entry catches a creator's eye
/// next to the quiet ink glyphs around it. One mark for every creator-post
/// door (the feed composer row, the profile's grid-post button, menus).
struct WhisperCreatorMark: View {
    var size: CGFloat = 22
    /// Whether the gradient animates (turn off inside static lists).
    var animated: Bool = true
    /// Adds the soft glow bloom behind the glyph.
    var glows: Bool = true

    @State private var phase: CGFloat = 0

    private var glyphFont: Font {
        // Snell Roundhand ships on every iPhone; serif-italic is the fallback.
        if UIFont(name: "SnellRoundhand-Bold", size: size) != nil {
            return .custom("SnellRoundhand-Bold", size: size * 1.35)
        }
        return .system(size: size * 1.1, weight: .bold, design: .serif).italic()
    }

    var body: some View {
        ZStack {
            if glows {
                Text("C")
                    .font(glyphFont)
                    .foregroundStyle(WhisperBrandGradient.accent)
                    .blur(radius: size * 0.28)
                    .opacity(0.55)
            }
            Text("C")
                .font(glyphFont)
                .foregroundStyle(sweep)
        }
        .frame(width: size * 1.25, height: size * 1.25)
        .onAppear {
            guard animated else { return }
            withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
        .accessibilityLabel("Creator post")
    }

    /// The brand sweep sliding across the glyph — the stops travel with
    /// `phase` so the highlight glides from bottom-left to top-right and
    /// wraps seamlessly.
    private var sweep: LinearGradient {
        let c = WhisperBrandGradient.colors
        let p: CGFloat = phase
        return LinearGradient(
            stops: [
                .init(color: c[2], location: 0),
                .init(color: c[0], location: max(0, min(1, p - 0.35))),
                .init(color: c[1], location: max(0, min(1, p))),
                .init(color: c[2], location: max(0, min(1, p + 0.35))),
                .init(color: c[0], location: 1)
            ],
            startPoint: .bottomLeading,
            endPoint: .topTrailing
        )
    }
}
