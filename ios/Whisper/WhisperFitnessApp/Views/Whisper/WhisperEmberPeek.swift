import SwiftUI

/// Little Jasper ghost that peeks up over the composer when the user is
/// composing an `/ember …` slash command — the living mascot itself, tinted
/// to the active personality (the old candle art is gone).
struct WhisperEmberPeek: View {
    @State private var bob: CGFloat = 0
    var caption: String? = nil

    private var mode: WhisperEmberCoachMode { WhisperEmberCoachMode.load() }

    var body: some View {
        WhisperEmberMascot(
            size: 50,
            isActive: true,
            expression: mode.signatureExpression,
            coachMode: mode,
            usesIntelligenceStyle: true
        )
        .frame(width: 56, height: 60)
        .offset(y: -bob)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                bob = 3
            }
        }
        .accessibilityHidden(true)
    }
}

/// Tiny Jasper ghost badge — the living mascot at glyph size, tinted to the
/// active personality. Used anywhere an inline Jasper mark is needed
/// (chips, cards, toolbars) instead of the old candle image.
struct WhisperEmberBadge: View {
    var size: CGFloat = 22
    /// Set true where Jasper is actively working so the ghost glows.
    var isActive: Bool = false

    private var mode: WhisperEmberCoachMode { WhisperEmberCoachMode.load() }

    var body: some View {
        WhisperEmberMascot(
            size: size,
            isActive: isActive,
            expression: mode.signatureExpression,
            coachMode: mode,
            usesIntelligenceStyle: true
        )
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Three softly pulsing dots in the personality accent — Jasper Intelligence's
/// compact "thinking" mark for tight spots (DM chips, working rails).
struct WhisperJasperMiniDots: View {
    var tint: Color = WhisperEmberCoachMode.load().accent
    var dotSize: CGFloat = 5
    @State private var phase = false

    var body: some View {
        HStack(spacing: dotSize * 0.62) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(tint)
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(phase ? 1 : 0.55)
                    .opacity(phase ? 1 : 0.35)
                    .animation(
                        .easeInOut(duration: 0.65)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.18),
                        value: phase
                    )
            }
        }
        .onAppear { phase = true }
        .accessibilityHidden(true)
    }
}
