import SwiftUI

/// Subtle press feedback for profile grid tiles — a gentle scale-down plus a
/// dimming veil, mirroring Instagram's grid press state.
struct GridCellPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .overlay {
                if configuration.isPressed {
                    Color.black.opacity(0.18)
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}
