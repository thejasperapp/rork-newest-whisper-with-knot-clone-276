import SwiftUI

/// Shared contact-menu surfaces, with opaque accessibility fallbacks.
struct WhisperConversationFrost: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content.padding(.horizontal, 18)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 28).fill(Color(uiColor: .secondarySystemBackground))
                } else {
                    RoundedRectangle(cornerRadius: 28).fill(.regularMaterial)
                }
            }
            .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(.primary.opacity(0.07), lineWidth: 0.5) }
    }
}

struct WhisperConversationDetailsBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            WhisperTheme.surface(scheme)
            if !reduceTransparency && scheme != .dark {
                Ellipse().fill(Color(red: 0.55, green: 0.82, blue: 0.96).opacity(0.24))
                    .frame(width: 340, height: 390).blur(radius: 85).offset(x: 110, y: -220)
                Ellipse().fill(Color.blue.opacity(0.09))
                    .frame(width: 320, height: 260).blur(radius: 80).offset(x: -120, y: 200)
            }
        }.ignoresSafeArea()
    }
}

struct WhisperPortraitPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 1.12 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

struct WhisperPortraitDestination: ViewModifier {
    let sourceID: String
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder func body(content: Content) -> some View {
        if reduceMotion { content } else {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        }
    }
}

struct WhisperConversationMenuRow: View {
    let title: String
    let icon: String
    var destructive = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).frame(width: 24)
                Text(title).font(.body)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .foregroundStyle(destructive ? Color.red : Color.primary)
            .frame(minHeight: 58).contentShape(.rect)
        }.buttonStyle(.plain)
    }
}
