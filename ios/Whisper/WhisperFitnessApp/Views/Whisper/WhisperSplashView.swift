import SwiftUI

/// Quiet session-restoration cover; no decorative animation or artificial delay.
struct WhisperSplashView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            WhisperTheme.surface(colorScheme).ignoresSafeArea()
            Image("WhisperLogo")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 76, height: 58)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Opening Whisper")
        .transition(.opacity)
    }
}

#Preview { WhisperSplashView() }
