import SwiftUI

/// Blur belongs to the sheet's presentation surface, not another inset content card.
struct WhisperStoryTrayBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency

    var body: some View {
        if reducesTransparency {
            Color(white: 0.12)
        } else {
            Rectangle().fill(.ultraThinMaterial)
                .overlay {
                    LinearGradient(colors: [Color(white: 0.12).opacity(0.78), Color(white: 0.055).opacity(0.90)], startPoint: .top, endPoint: .bottom)
                }
                .environment(\.colorScheme, .dark)
        }
    }
}
