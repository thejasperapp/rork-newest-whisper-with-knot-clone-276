import SwiftUI

/// Keeps the call's view identity and live session intact while the app is usable.
struct WhisperCallWindowRoot: View {
    private var manager: WhisperCallWindowManager { .shared }
    private var calls: WhisperCallService { .shared }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            WhisperVideoCallView()
                .opacity(manager.minimized ? 0 : 1)
                .allowsHitTesting(!manager.minimized)
                .accessibilityHidden(manager.minimized)
            if manager.minimized, let call = calls.active {
                Button { manager.restore() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: call.mode == .video ? "video.fill" : "phone.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(call.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(call.state == .connected ? "Tap to return to call" : "Call in progress")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption)
                    }
                    .foregroundStyle(.white)
                    .padding(14)
                    .frame(maxWidth: 270, minHeight: 64)
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: 22))
                    .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.16)) }
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
                    .background(GeometryReader { geo in
                        Color.clear
                            .onAppear { manager.tileFrame = geo.frame(in: .global) }
                            .onChange(of: geo.frame(in: .global)) { _, frame in manager.tileFrame = frame }
                    })
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Return to call with \(call.title)")
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
        }
        .preferredColorScheme(.dark)
    }
}
