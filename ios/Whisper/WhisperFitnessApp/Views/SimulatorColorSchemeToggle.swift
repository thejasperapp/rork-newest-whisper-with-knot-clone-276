import SwiftUI

/// Floating debug button \u2014 compiled into simulator builds only \u2014 that
/// flips the app between light, dark, and "follow system" without leaving
/// the app. Lives bottom-right above the home indicator so it never
/// blocks tabs, the composer, or any real UI.
struct SimulatorColorSchemeToggle: View {
    @Environment(\.colorScheme) private var systemScheme
    @Binding var override: ColorScheme?

    private var resolvedScheme: ColorScheme { override ?? systemScheme }

    private var icon: String {
        switch override {
        case .some(.dark): return "moon.fill"
        case .some(.light): return "sun.max.fill"
        default: return "circle.lefthalf.filled"
        }
    }

    private var label: String {
        switch override {
        case .some(.dark): return "Dark"
        case .some(.light): return "Light"
        default: return "Auto"
        }
    }

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    cycle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .bold))
                        Text(label)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(resolvedScheme == .dark ? Color.white : Color.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: .capsule)
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75)
                    }
                    .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .padding(.bottom, 90) // sit above the tab bar
            }
        }
        .allowsHitTesting(true)
    }

    private func cycle() {
        Haptics.tap()
        switch override {
        case .none:
            override = .dark
        case .some(.dark):
            override = .light
        case .some(.light):
            override = nil
        @unknown default:
            override = nil
        }
    }
}
