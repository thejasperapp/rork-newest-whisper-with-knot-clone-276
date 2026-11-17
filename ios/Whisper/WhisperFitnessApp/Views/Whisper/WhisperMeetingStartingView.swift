import SwiftUI

/// Indeterminate activity only: displayed while the actual room request is pending.
struct WhisperMeetingStartingView: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    var detail: String = "Getting your room ready. You’ll choose your camera and microphone before joining."

    var body: some View {
        ZStack {
            WhisperTheme.surface(colorScheme).ignoresSafeArea()
            VStack(spacing: 20) {
                WhisperMeetDoodle().frame(maxWidth: 300)
                Text(title).font(.title2.bold()).foregroundStyle(WhisperTheme.ink(colorScheme))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 300)
                ProgressView().tint(WhisperBrandGradient.accent).controlSize(.large)
            }.padding(24)
        }
        .accessibilityElement(children: .combine)
    }
}
