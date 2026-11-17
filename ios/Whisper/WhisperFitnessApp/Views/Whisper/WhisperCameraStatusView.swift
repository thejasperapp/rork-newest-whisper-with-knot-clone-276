import SwiftUI

/// A call owns its microphone; the camera can still capture photos and silent video.
struct WhisperCameraStatusView: View {
    let interruption: String?
    let silent: Bool

    var body: some View {
        if interruption != nil || silent {
            Label(interruption ?? "Video records without sound while the call uses your microphone", systemImage: interruption == nil ? "mic.slash.fill" : "camera.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.black.opacity(0.7), in: .rect(cornerRadius: 16))
                .padding(.horizontal, 24)
                .allowsHitTesting(false)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}
