import SwiftUI

struct WhisperFlatProfileButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .foregroundStyle(WhisperTheme.ink(scheme))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .modifier(WhisperControlGlass(shape: Capsule()))
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
