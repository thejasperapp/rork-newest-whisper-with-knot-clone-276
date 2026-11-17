import SwiftUI

/// App-wide background.
/// Light mode: signature warm orange gradient (the established brand look).
/// Dark mode: deep black gradient accented with subtle orange & white glows
/// so the overall theme stays cohesive with light mode rather than feeling like
/// a separate app.
struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                // Simple black → lighter black gradient. No glows.
                LinearGradient(
                    colors: [
                        Color.black,
                        Color(white: 0.13)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.953, green: 0.565, blue: 0.341),
                        Color(red: 0.965, green: 0.725, blue: 0.541)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }
}

struct NeonGlowModifier: ViewModifier {
    let color: Color
    @State private var glowPulse: CGFloat = 0.6

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.35 * glowPulse), radius: 6, x: 0, y: 0)
            .shadow(color: color.opacity(0.15 * glowPulse), radius: 14, x: 0, y: 0)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 2.5)
                    .repeatForever(autoreverses: true)
                ) {
                    glowPulse = 1.0
                }
            }
    }
}

extension View {
    func headerGlow(_ color: Color = .primary) -> some View {
        modifier(NeonGlowModifier(color: color))
    }
}

/// Shared cream/charcoal palette so the new bookmark/chat/research surfaces
/// stay consistent in light + dark.
enum EmberPalette {
    /// Warm cream used as the primary surface in light mode. Switches to
    /// a near-black charcoal in dark mode so text + icons keep contrast.
    static func creamSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.10, green: 0.09, blue: 0.10)
            : Color(red: 0.984, green: 0.956, blue: 0.894)
    }

    /// Slightly deeper cream/charcoal for cards layered on top of `creamSurface`.
    static func creamCard(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.15, green: 0.14, blue: 0.15)
            : Color(red: 0.972, green: 0.937, blue: 0.866)
    }

    /// Pill background used for icon-only chips in headers (chats / bookmarks).
    static func creamPill(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.10)
            : Color(red: 0.984, green: 0.956, blue: 0.894)
    }

    /// Foreground that always reads against the cream / charcoal surface.
    static func inkText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : Color(red: 0.13, green: 0.11, blue: 0.10)
    }
}
