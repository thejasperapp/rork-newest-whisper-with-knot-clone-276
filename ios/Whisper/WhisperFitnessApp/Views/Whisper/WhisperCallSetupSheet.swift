import SwiftUI

/// In-app voice / video call — Instagram-style. Driven entirely by
/// `WhisperCallService.shared.active`. The caller sees a "Calling…" UI
/// with only an End button; the recipient sees an incoming UI with
/// Answer + Decline. State transitions (ringing → connected → ended)
/// come from the call service so both sides stay in sync over
/// realtime signaling.
struct WhisperCallSetupSheet: View {
    // Kept as nested types so existing call sites (`WhisperCallSetupSheet.Mode`)
    // keep compiling. They now alias the canonical signal types.
    typealias Mode = WhisperCallSignal.Mode

    @Environment(\.dismiss) private var dismiss
    @State private var calls = WhisperCallService.shared
    @State private var elapsed: TimeInterval = 0
    @State private var pulse: CGFloat = 1
    @State private var muted: Bool = false
    @State private var cameraOff: Bool = false
    @State private var audioRoute: WhisperAudioRoute = .speaker
    @State private var tickerTask: Task<Void, Never>?

    private var call: WhisperCallService.ActiveCall? { calls.active }

    private var title: String {
        guard let call else { return "" }
        switch call.state {
        case .ringing:
            if call.direction == .incoming {
                return call.mode == .audio ? "Whisper audio call" : "Whisper video call"
            } else {
                return call.mode == .audio ? "Whisper audio" : "Whisper video"
            }
        case .connected: return formattedElapsed
        case .ended:     return "Call ended"
        }
    }

    private var subtitle: String {
        guard let call else { return "" }
        switch call.state {
        case .ringing:
            return call.direction == .incoming ? "is calling you\u{2026}" : "Ringing\u{2026}"
        case .connected: return "On call"
        case .ended:     return "Hung up"
        }
    }

    var body: some View {
        ZStack {
            backgroundLayer
            if let call {
                VStack(spacing: 24) {
                    Spacer(minLength: 40)
                    avatar(for: call)
                    VStack(spacing: 6) {
                        Text(call.otherUsername)
                            .font(.title.weight(.bold))
                            .foregroundStyle(.white)
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    Group {
                        switch (call.direction, call.state) {
                        case (.incoming, .ringing):
                            incomingRingingControls
                        case (.outgoing, .ringing):
                            outgoingRingingControls
                        case (_, .connected):
                            connectedControls
                        case (_, .ended):
                            EmptyView()
                        }
                    }
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 24)
            }
        }
        .preferredColorScheme(.dark)
        .colorScheme(.dark)
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            pulse = 1.6
            startTicker()
        }
        .onDisappear {
            tickerTask?.cancel()
            tickerTask = nil
        }
        .onChange(of: call?.state) { _, newState in
            if newState == .connected {
                Haptics.success()
                elapsed = 0
                calls.setAudioRoute(audioRoute)
                calls.setMuted(muted)
            }
        }
    }

    // MARK: - Layers

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.06, blue: 0.14)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [Color.purple.opacity(0.35), .clear],
                center: .top, startRadius: 0, endRadius: 360
            )
            .ignoresSafeArea()
            if let call, call.mode == .video, call.state == .connected {
                // Remote feed fills the entire background.
                WhisperCallVideoView(source: .remote)
                    .ignoresSafeArea()
                    .overlay {
                        LinearGradient(
                            colors: [.black.opacity(0.55), .clear, .black.opacity(0.45)],
                            startPoint: .top, endPoint: .bottom
                        )
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                    }
                VStack {
                    HStack {
                        Spacer()
                        selfPreviewTile(cameraOff: cameraOff)
                            .frame(width: 110, height: 150)
                            .clipShape(.rect(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
                            }
                            .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
                            .padding(.top, 70)
                            .padding(.trailing, 18)
                            .onTapGesture {
                                Haptics.tap()
                                calls.switchCamera()
                            }
                    }
                    Spacer()
                }
            }
        }
    }

    private func selfPreviewTile(cameraOff: Bool) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.2, green: 0.2, blue: 0.32), Color(red: 0.1, green: 0.1, blue: 0.2)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            if cameraOff {
                Image(systemName: "video.slash.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                WhisperCallVideoView(source: .local, mirror: true)
            }
        }
    }

    private func avatar(for call: WhisperCallService.ActiveCall) -> some View {
        ZStack {
            if call.state == .ringing {
                Circle()
                    .strokeBorder(.white.opacity(0.18), lineWidth: 2)
                    .frame(width: 200, height: 200)
                    .scaleEffect(pulse)
                    .opacity(2 - pulse)
                    .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulse)
            }
            WhisperAvatar(
                username: call.otherUsername,
                size: 140,
                imageURL: call.avatarURL,
                ring: false
            )
            .overlay {
                Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.4), radius: 18, y: 6)
        }
    }

    // MARK: - Control sets

    /// Outgoing ringing — only an End/Cancel button. The other side has
    /// not picked up yet, so Answer/Decline must NOT appear here.
    private var outgoingRingingControls: some View {
        HStack(spacing: 28) {
            controlButton(
                icon: muted ? "mic.slash.fill" : "mic.fill",
                active: muted,
                label: muted ? "Unmute" : "Mute"
            ) {
                Haptics.tap(); muted.toggle(); calls.setMuted(muted)
            }
            endButton(label: "Cancel") {
                Haptics.warning()
                calls.cancelOutgoing()
            }
        }
    }

    /// Incoming ringing — Answer (green) + Decline (red).
    private var incomingRingingControls: some View {
        HStack(spacing: 28) {
            Button {
                Haptics.warning()
                calls.declineIncoming()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "phone.down.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Color.red, in: Circle())
                        .shadow(color: .red.opacity(0.4), radius: 10, y: 3)
                    Text("Decline")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .buttonStyle(.plain)
            Button {
                Haptics.success()
                calls.answerIncoming()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: call?.mode == .video ? "video.fill" : "phone.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Color.green, in: Circle())
                        .shadow(color: Color.green.opacity(0.4), radius: 10, y: 3)
                    Text("Answer")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// In-call — mute / camera-or-speaker / end.
    private var connectedControls: some View {
        HStack(spacing: 28) {
            controlButton(
                icon: muted ? "mic.slash.fill" : "mic.fill",
                active: muted,
                label: muted ? "Unmute" : "Mute"
            ) {
                Haptics.tap(); muted.toggle(); calls.setMuted(muted)
            }
            if call?.mode == .video {
                controlButton(
                    icon: cameraOff ? "video.slash.fill" : "video.fill",
                    active: cameraOff,
                    label: cameraOff ? "Camera off" : "Camera on"
                ) {
                    Haptics.tap()
                    cameraOff.toggle()
                    calls.setCameraEnabled(!cameraOff)
                }
                controlButton(
                    icon: "arrow.triangle.2.circlepath.camera.fill",
                    active: false,
                    label: "Flip"
                ) {
                    Haptics.tap(); calls.switchCamera()
                }
            } else {
                WhisperAudioRouteMenu(current: audioRoute, onSelect: { route in
                    audioRoute = route
                    calls.setAudioRoute(route)
                }) {
                    VStack(spacing: 6) {
                        Image(systemName: audioRoute.controlIcon)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(audioRoute == .speaker ? Color.black : .white)
                            .frame(width: 60, height: 60)
                            .background(audioRoute == .speaker ? Color.white : .white.opacity(0.15), in: Circle())
                            .overlay { Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5) }
                        Text("Audio")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            endButton(label: "End") {
                Haptics.warning()
                calls.endCall()
            }
        }
    }

    private func controlButton(icon: String, active: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(active ? Color.black : .white)
                    .frame(width: 60, height: 60)
                    .background(active ? Color.white : .white.opacity(0.15), in: Circle())
                    .overlay { Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5) }
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .buttonStyle(.plain)
    }

    private func endButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "phone.down.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.red, in: Circle())
                    .shadow(color: .red.opacity(0.4), radius: 10, y: 3)
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Ticker

    /// Drives the connected-state elapsed-time display. Stops once the
    /// call ends or the view disappears.
    private func startTicker() {
        tickerTask?.cancel()
        tickerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if let c = calls.active, c.state == .connected, let started = c.startedAt {
                    elapsed = Date().timeIntervalSince(started)
                }
            }
        }
    }

    private var formattedElapsed: String {
        let total = Int(elapsed)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
