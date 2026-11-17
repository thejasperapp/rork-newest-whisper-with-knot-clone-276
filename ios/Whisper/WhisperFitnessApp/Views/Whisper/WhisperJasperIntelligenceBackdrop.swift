import SwiftUI

/// Whisper's warm colors, with the original chat's drifting bloom composition.
struct WhisperJasperIntelligenceBackdrop: View {
    var blooming: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        WhisperTheme.surface(colorScheme)
            .overlay {
                if blooming {
                    blooms
                } else {
                    LinearGradient(colors: [WhisperBrandGradient.rose.opacity(0.035), .clear, WhisperBrandGradient.amber.opacity(0.055)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .clipped()
            .allowsHitTesting(false)
    }

    private var bloomPhases: [Bool] { reduceMotion ? [false] : [false, true] }

    private var blooms: some View {
        Color.clear
            .phaseAnimator(bloomPhases) { view, drift in
                view.overlay { bloomLayers(drift: drift) }
            } animation: { _ in .easeInOut(duration: 9) }
    }

    private func bloomLayers(drift: Bool) -> some View {
        ZStack {
            Circle()
                .fill(WhisperBrandGradient.rose.opacity(colorScheme == .dark ? 0.20 : 0.13))
                .frame(width: 560, height: 560)
                .blur(radius: 90)
                .opacity(0.85)
                .offset(x: drift ? -44 : 38, y: drift ? -310 : -262)
            Circle()
                .fill(WhisperBrandGradient.accent.opacity(colorScheme == .dark ? 0.20 : 0.13))
                .frame(width: 360, height: 360)
                .blur(radius: 90)
                .opacity(0.36)
                .offset(x: drift ? -152 : -108, y: drift ? 46 : 128)
            Circle()
                .fill(WhisperBrandGradient.amber.opacity(colorScheme == .dark ? 0.22 : 0.18))
                .frame(width: 470, height: 470)
                .blur(radius: 100)
                .opacity(0.32)
                .offset(x: drift ? 172 : 128, y: drift ? 322 : 392)
        }
    }
}
