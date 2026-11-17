import SwiftUI

/// Animated icon overlays played on Whisper's action row.
///
/// - `WhisperSpinningRepostIcon` does a full 360° rotation any time the
///   `trigger` value changes — used after an actual repost commits so the
///   refresh arrows literally spin.
/// - `WhisperFlyingPaperplane` is an overlay that briefly flies a duplicate
///   paperplane glyph up and to the right, fading out — used when the
///   viewer taps share so the icon "sends" the post.
///
/// Both views are pure overlays. They never absorb touches — the underlying
/// `Button` continues to receive the original tap.

struct WhisperSpinningRepostIcon: View {
    let tint: Color
    let trigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Double = 0
    @State private var lastPlayed: Int = 0

    var body: some View {
        WhisperRoundedGlyph(kind: .repost, size: 22)
            .foregroundStyle(tint)
            .rotationEffect(.degrees(rotation))
            .onChange(of: trigger) { _, newValue in
                guard newValue != lastPlayed else { return }
                lastPlayed = newValue
                guard !reduceMotion else { return }
                // Reset to current angle, then spin a full turn so repeated
                // triggers keep advancing instead of snapping back.
                withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) {
                    rotation += 360
                }
            }
    }
}

/// Static paperplane that launches a duplicate glyph up-and-right when
/// `trigger` changes. The static icon stays put so the underlying Button
/// always has a tap target; the overlay only plays during the animation.
struct WhisperFlyingPaperplane: View {
    let tint: Color
    let trigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastPlayed: Int = 0
    @State private var flying: Bool = false
    @State private var planeOffset: CGSize = .zero
    @State private var planeRotation: Double = 0
    @State private var planeOpacity: Double = 0
    @State private var planeScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            WhisperRoundedGlyph(kind: .plane, size: 22)
                .foregroundStyle(tint)
                .opacity(flying ? 0.25 : 1.0)
            if flying {
                WhisperRoundedGlyph(kind: .plane, size: 22, selected: true)
                    .foregroundStyle(tint)
                    .rotationEffect(.degrees(planeRotation))
                    .scaleEffect(planeScale)
                    .offset(planeOffset)
                    .opacity(planeOpacity)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: trigger) { _, newValue in
            guard newValue != lastPlayed else { return }
            lastPlayed = newValue
            if !reduceMotion { launch() }
        }
    }

    private func launch() {
        // Reset
        planeOffset = .zero
        planeRotation = 0
        planeOpacity = 1
        planeScale = 1.0
        flying = true
        // Tilt up a touch as it takes off.
        withAnimation(.easeOut(duration: 0.18)) {
            planeRotation = -18
            planeScale = 1.1
        }
        // Fly up & to the right.
        withAnimation(.easeIn(duration: 0.55).delay(0.05)) {
            planeOffset = CGSize(width: 90, height: -70)
            planeOpacity = 0
            planeScale = 0.6
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            flying = false
        }
    }
}
