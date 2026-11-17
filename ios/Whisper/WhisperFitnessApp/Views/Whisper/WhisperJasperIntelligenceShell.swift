import SwiftUI

/// Opt-in Jasper chrome. Does not change Meet's or ordinary messages' styling.
struct WhisperJasperIntelligenceShell<S: InsettableShape>: View {
    let shape: S
    var panel: Bool = false
    var onDark: Bool = false
    var ambientTint: Color? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        shape
            .fill(onDark ? Color(red: 0.09, green: 0.085, blue: 0.08) : (colorScheme == .dark ? WhisperTheme.card(colorScheme) : .white))
            .overlay {
                shape.strokeBorder((ambientTint.map { LinearGradient(colors: [$0.opacity(0.55), $0], startPoint: .topLeading, endPoint: .bottomTrailing) } ?? WhisperBrandGradient.linear).opacity(panel ? 0.42 : 0.72), lineWidth: contrast == .increased ? 2 : 1.25)
            }
            .background {
                if let ambientTint {
                    shape.fill(ambientTint.opacity(panel ? 0.12 : 0.25))
                        .blur(radius: panel ? 24 : 18).scaleEffect(x: 1.06, y: 1.30)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .shadow(color: (ambientTint ?? WhisperBrandGradient.amber).opacity(panel ? 0.08 : 0.13), radius: 16, x: 5, y: 6)
            .shadow(color: (ambientTint ?? WhisperBrandGradient.rose).opacity(panel ? 0.04 : 0.07), radius: 12, x: -5, y: 3)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.05), radius: 10, y: 5)
    }
}
