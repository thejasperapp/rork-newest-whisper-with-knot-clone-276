import SwiftUI

private struct WhisperJasperPressedKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var whisperJasperPressed: Bool {
        get { self[WhisperJasperPressedKey.self] }
        set { self[WhisperJasperPressedKey.self] = newValue }
    }
}

/// Passes the owning button's press into the decorative face without stealing taps.
struct WhisperJasperReactionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.whisperJasperPressed, configuration.isPressed)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: configuration.isPressed)
    }
}
