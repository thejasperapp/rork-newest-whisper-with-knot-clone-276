import SwiftUI

// MARK: - The wave like
//
// Liking a wave is a moment: the rail heart FILLS with the brand gradient
// from the bottom up and pops, while a big gradient heart blooms in the
// center of the wave (double-tap or the rail — same burst). Unliking drains
// the fill back to the white outline.

/// The rail's heart — outline when unliked; on like the gradient rises
/// through the glyph and the heart pops.
struct WhisperWaveHeartButton: View {
    let liked: Bool
    let count: Int
    let action: () -> Void

    @State private var fill: CGFloat = 0
    @State private var pop: Bool = false

    private let glyph: CGFloat = 22
    private let box: CGFloat = 34

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    // ONE animated value drives both layers: the outline fades as
                    // the gradient rises through the glyph, so there is never a
                    // frame where the heart is blank (the old version hid the
                    // outline the instant `liked` flipped, before the fill began).
                    WhisperRoundedGlyph(kind: .heart, size: glyph)
                        .foregroundStyle(.white)
                        .opacity(Double(1 - fill))
                    WhisperRoundedGlyph(kind: .heart, size: glyph, selected: true)
                        .foregroundStyle(WhisperBrandGradient.vertical)
                        .mask(alignment: .bottom) {
                            Rectangle().frame(height: max(0, box * fill))
                        }
                }
                .frame(width: box, height: box)
                .compositingGroup()
                .scaleEffect(pop ? 1.28 : 1)
                .shadow(color: .black.opacity(0.5), radius: 5, y: 1)
                if count > 0 {
                    Text(WhisperWaveHeartFormat.compact(count))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 4)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .frame(minWidth: 46)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onAppear { fill = liked ? 1 : 0 }
        .onChange(of: liked) { _, now in
            if now {
                // Commit the empty state WITHOUT animation first, then rise on
                // the next turn — writing 0 and 1 in the same transaction let
                // SwiftUI collapse them and the fill jumped instead of rising.
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) { fill = 0 }
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.38)) { fill = 1 }
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) { pop = true }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { pop = false }
                }
            } else {
                withAnimation(.easeIn(duration: 0.22)) { fill = 0 }
            }
        }
        .accessibilityLabel(liked ? "Unlike" : "Like")
        .accessibilityValue(count > 0 ? "\(count) likes" : "")
    }
}

/// The big heart that blooms in the center of the wave on like — brand
/// gradient with a soft white rim, a slight tilt, a breath of scale.
struct WhisperWaveHeartBurst: View {
    let tilt: Double
    @State private var breathe: Bool = false

    var body: some View {
        ZStack {
            Image(systemName: "heart.fill")
                .font(.system(size: 124, weight: .bold))
                .foregroundStyle(WhisperBrandGradient.diagonal)
            Image(systemName: "heart")
                .font(.system(size: 124, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
        }
        .rotationEffect(.degrees(tilt))
        .scaleEffect(breathe ? 1.06 : 1)
        .shadow(color: WhisperBrandGradient.accent.opacity(0.55), radius: 22)
        .shadow(color: .black.opacity(0.35), radius: 14)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) { breathe = true }
        }
        .accessibilityHidden(true)
    }
}

enum WhisperWaveHeartFormat {
    /// 12300 → "12.3K".
    static func compact(_ n: Int) -> String {
        switch n {
        case ..<1000: return "\(n)"
        case ..<1_000_000:
            let v = Double(n) / 1000
            return v >= 100 ? "\(Int(v))K" : String(format: "%.1fK", v).replacingOccurrences(of: ".0K", with: "K")
        default:
            let v = Double(n) / 1_000_000
            return String(format: "%.1fM", v).replacingOccurrences(of: ".0M", with: "M")
        }
    }
}
