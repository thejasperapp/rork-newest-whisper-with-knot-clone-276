import SwiftUI

/// A dim brand reflection confined to the black eye, never a body-wide glow.
struct WhisperJasperEyeGlow: View {
    var body: some View {
        GeometryReader { geometry in
            WhisperBrandGradient.linear
                .mask {
                    RadialGradient(colors: [.white.opacity(0.32), .clear],
                        center: UnitPoint(x: 0.5, y: 0.65), startRadius: 0,
                        endRadius: max(geometry.size.width, geometry.size.height) * 0.7)
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
