import SwiftUI

/// A native control, not a glass surface behind conversation content.
struct WhisperKnotLatestGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    // Sampled from the member's reference, rather than saturated Send blue.
    private let blue = Color(red: 0.7412, green: 0.8588, blue: 0.9882)

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.background(blue, in: Circle())
                .overlay { Circle().strokeBorder(.white.opacity(0.65), lineWidth: 1) }
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(blue).interactive(), in: Circle())
        } else {
            content.background(.regularMaterial, in: Circle())
                .background(blue, in: Circle())
                .overlay { Circle().strokeBorder(.white.opacity(0.65), lineWidth: 1) }
        }
    }
}
