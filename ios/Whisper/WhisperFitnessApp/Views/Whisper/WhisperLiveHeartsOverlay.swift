import SwiftUI

/// One floating reaction in the live overlay.
struct WhisperLiveHeart: Identifiable, Equatable {
    let id: UUID
    let emoji: String
    /// Horizontal jitter from the emit point.
    let xJitter: CGFloat
    /// Sway amplitude while rising.
    let drift: CGFloat
    let scale: CGFloat

    init(emoji: String) {
        self.id = UUID()
        self.emoji = emoji
        self.xJitter = CGFloat.random(in: -36...12)
        self.drift = CGFloat.random(in: 8...26) * (Bool.random() ? 1 : -1)
        self.scale = CGFloat.random(in: 0.8...1.35)
    }
}

/// Instagram-style floating hearts — emojis pop from the bottom-right corner,
/// rise with a gentle sway, and fade out. Purely decorative; never absorbs
/// touches. Parent owns the `hearts` array and prunes it after ~2.6s.
struct WhisperLiveHeartsOverlay: View {
    let hearts: [WhisperLiveHeart]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ForEach(hearts) { heart in
                FloatingHeartView(heart: heart)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct FloatingHeartView: View {
    let heart: WhisperLiveHeart

    @State private var rise: CGFloat = 0
    @State private var sway: CGFloat = 0
    @State private var opacity: Double = 0
    @State private var popScale: CGFloat = 0.3

    var body: some View {
        Text(heart.emoji)
            .font(.system(size: 30 * heart.scale))
            .scaleEffect(popScale)
            .opacity(opacity)
            .offset(x: heart.xJitter + sway, y: rise)
            .onAppear {
                // Pop in.
                withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                    popScale = 1
                    opacity = 1
                }
                // Rise + fade.
                withAnimation(.easeOut(duration: 2.3)) {
                    rise = -CGFloat.random(in: 360...480)
                }
                withAnimation(.easeIn(duration: 0.9).delay(1.4)) {
                    opacity = 0
                }
                // Sway back and forth while rising.
                withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
                    sway = heart.drift
                }
            }
    }
}
