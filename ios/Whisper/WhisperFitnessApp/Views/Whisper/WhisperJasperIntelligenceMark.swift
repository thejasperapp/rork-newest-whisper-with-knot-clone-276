import SwiftUI

/// Shared Knot artwork. Legacy type and argument names preserve host integration.
struct WhisperJasperIntelligenceMark: View {
    var working: Bool = false
    var coachMode: WhisperEmberCoachMode = .regular
    var palette: WhisperEmberMascotPalette? = nil
    var smitten: Bool = false
    var expression: WhisperEmberMascotExpression? = nil
    @Environment(\.whisperJasperPressed) private var pressed

    var body: some View {
        GeometryReader { geometry in
            let size = max(0, min(geometry.size.width, geometry.size.height))
            WhisperKnotMascot(
                size: size,
                isActive: working,
                expression: pressed ? .curious : (working ? .thinking : (expression ?? (smitten ? .happy : .calm)))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
