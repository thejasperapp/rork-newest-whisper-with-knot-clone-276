import SwiftUI

/// Whisper's dedicated video-call experience — FaceTime-style, distinct
/// from the meeting room. Driven entirely by `WhisperCallService.shared`:
///
/// - Ringing (both directions): the other person's profile photo blurred
///   full-bleed with their crisp avatar centered and pulsing rings —
///   the same treatment lives use.
/// - Connected 1:1: remote video fills the screen, your preview floats as
///   a PiP card, glass controls sit above the home indicator.
/// - Group calls: a clean tile grid for everyone in the room.
/// - Coaches on a call with their clients get Class controls: spotlight,
///   mute a member, mute everyone, and a room-wide "Class mode" banner.
/// - Backgrounds & effects (blur / AI backdrops) apply to the local camera.
///
/// Media rides the shared mesh room (`meeting:{roomID}`), so web users who
/// answer from their browser land in the same call.
struct WhisperVideoCallView: View {
    @State private var calls = WhisperCallService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var controlsVisible: Bool = false
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var muted: Bool = false
    @State private var cameraOff: Bool = false
    @State private var audioRoute: WhisperAudioRoute = .receiver
    @State private var elapsed: TimeInterval = 0
    @State private var tickerTask: Task<Void, Never>?
    @State private var pulse: CGFloat = 1
    @State private var showEffects: Bool = false
    @State private var showCoachMutedToast: Bool = false
    /// userID (lowercased) → avatar URL for camera-off tiles.
    @State private var avatars: [String: URL] = [:]

    // Fun layer & class tools
    @State private var showReactions: Bool = false
    @State private var exercisePromptOpen: Bool = false
    @State private var exerciseDraft: String = ""

    private let reactionEmojis: [String] = ["\u{2764}\u{FE0F}", "\u{1F525}", "\u{1F4AA}", "\u{1F44F}", "\u{1F602}", "\u{1F389}"]

    private var call: WhisperCallService.ActiveCall? { calls.active }

    private var participants: [WhisperLiveRTCService.ParticipantInfo] {
        _ = calls.rtcTick
        return WhisperLiveRTCService.shared.participants
    }

    private var localPeerID: String { WhisperLiveRTCService.shared.localPeerId }

    private var remoteParticipants: [WhisperLiveRTCService.ParticipantInfo] {
        participants.filter { $0.peerId != localPeerID }
    }

    private var selfParticipant: WhisperLiveRTCService.ParticipantInfo? {
        participants.first { $0.peerId == localPeerID }
    }

    /// Coach on a call with at least one of their clients → class host.
    private var isClassHost: Bool {
        guard let call, call.state == .connected else { return false }
        return remoteParticipants.contains { calls.isMyClient(userID: $0.userId) }
    }

    private var avatarKey: String {
        let ids = participants.map { $0.userId.lowercased() }.sorted().joined(separator: ",")
        return ids + "|" + (call?.otherUserID.lowercased() ?? "")
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let call {
                switch call.state {
                case .ringing:
                    ringScreen(call)
                case .connected:
                    connectedStage(call)
                case .ended:
                    endedScreen
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if call?.state != .ended {
                HStack {
                    Button { WhisperCallWindowManager.shared.minimize() } label: {
                        Label("Minimize", systemImage: "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Minimize call without hanging up")
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 4)
            }
        }
        .whisperEdgeBack(isEnabled: call?.state != .ended && !showEffects && !WhisperCallWindowManager.shared.minimized) {
            WhisperCallWindowManager.shared.minimize()
        }
        .preferredColorScheme(.dark)
        .onAppear {
            pulse = 1.55
            startTicker()
            // Calls keep the screen awake — FaceTime convention.
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            tickerTask?.cancel()
            hideControlsTask?.cancel()
            tickerTask = nil
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: call?.state) { _, newState in
            if newState == .connected {
                Haptics.success()
                elapsed = 0
                syncMediaControls()
                showReactions = false
                controlsVisible = false
                calls.resetCallExtras()

            }
        }
        .onChange(of: calls.rtcTick) { _, _ in syncMediaControls() }
        .onChange(of: calls.mutedByCoachAt) { _, stamp in
            guard stamp != nil else { return }
            muted = true
            Haptics.warning()
            withAnimation(.spring(response: 0.3)) { showCoachMutedToast = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                withAnimation { showCoachMutedToast = false }
            }
        }
        .sheet(isPresented: $showEffects) {
            WhisperVideoEffectsSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task(id: avatarKey) { await hydrateAvatars() }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if let message = calls.lastErrorMessage {
                    banner(message, icon: "wifi.exclamationmark", tint: .red)
                }
                if showCoachMutedToast {
                    banner("Your coach muted you", icon: "mic.slash.fill", tint: .orange)
                }
            }
            .padding(.top, 8)
        }
    }

    private func syncMediaControls() {
        let rtc = WhisperLiveRTCService.shared
        muted = !rtc.micOn
        cameraOff = !rtc.cameraOn
        audioRoute = rtc.connected ? rtc.actualAudioRoute : .receiver
    }

    // MARK: - Ringing

    private func ringScreen(_ call: WhisperCallService.ActiveCall) -> some View {
        ZStack {
            blurredBackdrop(call)
            VStack(spacing: 0) {
                Spacer(minLength: 60)

                ZStack {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .strokeBorder(.white.opacity(0.22), lineWidth: 1.5)
                            .frame(width: 160, height: 160)
                            .scaleEffect(pulse + CGFloat(index) * 0.22)
                            .opacity(Double(1.7 - pulse))
                            .animation(
                                .easeOut(duration: 1.6)
                                    .repeatForever(autoreverses: false)
                                    .delay(Double(index) * 0.35),
                                value: pulse
                            )
                    }
                    if call.isGroup {
                        groupRingCluster(call)
                    } else {
                        WhisperAvatar(
                            username: call.otherUsername,
                            size: 136,
                            imageURL: call.avatarURL,
                            ring: false
                        )
                        .overlay { Circle().strokeBorder(.white.opacity(0.32), lineWidth: 1.5) }
                        .shadow(color: .black.opacity(0.5), radius: 22, y: 8)
                    }
                }
                .frame(height: 220)

                VStack(spacing: 7) {
                    Text(call.title)
                        .font(.system(size: 27, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 28)
                    Text(ringSubtitle(call))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    HStack(spacing: 5) {
                        Image(systemName: call.mode == .video ? "video.fill" : "phone.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(call.mode == .video ? "Whisper Video" : "Whisper Audio")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(0.6)
                    }
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.12), in: Capsule())
                }
                .padding(.top, 18)

                Spacer()

                if call.direction == .incoming {
                    incomingRingControls
                } else {
                    outgoingRingControls
                }
            }
            .padding(.bottom, 46)
        }
    }

    private func ringSubtitle(_ call: WhisperCallService.ActiveCall) -> String {
        if calls.isStarting { return "Starting call…" }
        if call.direction == .incoming {
            return call.isGroup
                ? "@\(call.otherUsername) invited you\u{2026}"
                : "is calling you\u{2026}"
        }
        return call.isGroup ? "Ringing the group\u{2026}" : "Ringing\u{2026}"
    }

    /// Overlapping member avatars for group rings; falls back to a glyph
    /// when the local device doesn't know this group's roster.
    @ViewBuilder
    private func groupRingCluster(_ call: WhisperCallService.ActiveCall) -> some View {
        let members: [WhisperGroupMember] = {
            guard let gid = call.groupID.flatMap(UUID.init(uuidString:)),
                  let group = WhisperGroupChatService.shared.group(byID: gid) else { return [] }
            return Array(group.members.prefix(3))
        }()
        if members.isEmpty {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.14))
                    .frame(width: 136, height: 136)
                Image(systemName: "person.3.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
            }
            .overlay { Circle().strokeBorder(.white.opacity(0.32), lineWidth: 1.5) }
        } else {
            HStack(spacing: -34) {
                ForEach(members) { member in
                    WhisperAvatar(
                        username: member.username,
                        size: 92,
                        imageURL: member.profile_image_url.flatMap(URL.init(string:)),
                        ring: false
                    )
                    .overlay { Circle().strokeBorder(.black.opacity(0.6), lineWidth: 3) }
                }
            }
            .shadow(color: .black.opacity(0.5), radius: 22, y: 8)
        }
    }

    private var incomingRingControls: some View {
        HStack(spacing: 56) {
            VStack(spacing: 8) {
                Button {
                    Haptics.warning()
                    calls.declineIncoming()
                } label: {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(Color.red, in: Circle())
                        .shadow(color: .red.opacity(0.45), radius: 14, y: 4)
                }
                .buttonStyle(.plain)
                Text("Decline")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            VStack(spacing: 8) {
                Button {
                    Haptics.success()
                    calls.answerIncoming()
                } label: {
                    Image(systemName: call?.mode == .video ? "video.fill" : "phone.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(Color.green, in: Circle())
                        .shadow(color: .green.opacity(0.45), radius: 14, y: 4)
                }
                .buttonStyle(.plain)
                Text("Answer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private var outgoingRingControls: some View {
        HStack(spacing: 40) {
            VStack(spacing: 8) {
                Button {
                    Haptics.tap()
                    muted.toggle()
                    calls.setMuted(muted)
                } label: {
                    Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(muted ? .black : .white)
                        .frame(width: 62, height: 62)
                        .background(muted ? AnyShapeStyle(Color.white) : AnyShapeStyle(.white.opacity(0.16)), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(calls.isStarting || !WhisperLiveRTCService.shared.connected)
                Text(muted ? "Unmute" : "Mute")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            VStack(spacing: 8) {
                Button {
                    Haptics.warning()
                    calls.cancelOutgoing()
                } label: {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(Color.red, in: Circle())
                        .shadow(color: .red.opacity(0.45), radius: 14, y: 4)
                }
                .buttonStyle(.plain)
                Text("Cancel")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    // MARK: - Connected

    private func connectedStage(_ call: WhisperCallService.ActiveCall) -> some View {
        VStack(spacing: 0) {
          ZStack {
            Group {
            if call.isGroup {
                groupCallStage
            } else if call.mode == .audio {
                audioStage(call)
            } else {
                videoStage(call)
            }

            }
            .contentShape(.rect)
            .simultaneousGesture(TapGesture().onEnded { toggleControls() })
            .accessibilityAction(named: "Show call controls") { controlsVisible = true }
            reactionsOverlay.allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar(call)
                if let timer = calls.classTimer {
                    classTimerPill(timer)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
                if let exercise = calls.classExercise {
                    classExerciseCard(exercise)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if showReactions {
                    reactionBar
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .opacity(chromeVisible ? 1 : 0)
            .allowsHitTesting(chromeVisible)
            .accessibilityHidden(!chromeVisible)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: chromeVisible)
            .animation(.spring(response: 0.35), value: calls.classTimer)
            .animation(.spring(response: 0.35), value: calls.classExercise)
            .animation(.spring(response: 0.3), value: showReactions)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .clipShape(.rect(cornerRadius: 22))
          .padding(.horizontal, 6)
          // This is a separate layer below the media, never an overlay on faces.
          controlBar(call)
              .background(Color.black)
        }
        .alert("Set the exercise", isPresented: $exercisePromptOpen) {
            TextField("e.g. Squats × 12", text: $exerciseDraft)
            Button("Broadcast") {
                let text = exerciseDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                calls.classSetExercise(text.isEmpty ? nil : text)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everyone on the call sees the exercise card.")
        }
    }

    private func audioStage(_ call: WhisperCallService.ActiveCall) -> some View {
        ZStack {
            blurredBackdrop(call)
            VStack(spacing: 16) {
                WhisperAvatar(
                    username: call.otherUsername,
                    size: 128,
                    imageURL: call.avatarURL,
                    ring: false
                )
                .overlay { Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1.5) }
                .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
                Text(call.title)
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(.white)
                Text(formattedElapsed)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
    }

    @ViewBuilder
    private func videoStage(_ call: WhisperCallService.ActiveCall) -> some View {
        let remotes = remoteParticipants
        let spotlit = calls.spotlightPeerID.flatMap { id in participants.first { $0.peerId == id } }

        if let spotlit {
            spotlightLayout(spotlit)
        } else if remotes.isEmpty {
            waitingStage(call)
        } else if remotes.count == 1 && !call.isGroup {
            oneOnOneLayout(remote: remotes[0])
        } else {
            gridLayout(everyone: participants)
        }
    }

    /// Nobody else in the room yet (they answered but are still connecting,
    /// or a group ring is being picked up) — show my own preview. This is
    /// the "connecting" frame between ringing and in-call.
    private func waitingStage(_ call: WhisperCallService.ActiveCall) -> some View {
        ZStack {
            if let me = selfParticipant, me.hasVideo, !cameraOff {
                WhisperLiveVideoView(
                    source: .local,
                    mirror: WhisperLiveRTCService.shared.isFrontCamera && !WhisperLiveRTCService.shared.isScreenSharing,
                    fit: WhisperLiveRTCService.shared.isScreenSharing,
                    trackNonce: calls.rtcTick
                )
            } else {
                blurredBackdrop(call)
            }
            VStack(spacing: 8) {
                ProgressView().tint(.white)
                Text("Connecting\u{2026}")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(call.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func oneOnOneLayout(remote: WhisperLiveRTCService.ParticipantInfo) -> some View {
        ZStack {
            callTile(remote, style: .hero)

            // Soft scrims so chrome stays readable over video.
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 130)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 170)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack {
                HStack {
                    Spacer()
                    selfPiP
                        .padding(.top, 64)
                        .padding(.trailing, 16)
                }
                Spacer()
            }
        }
    }

    private var selfPiP: some View {
        Group {
            if let me = selfParticipant {
                callTile(me, style: .pip)
            } else {
                Color(white: 0.1)
            }
        }
        .frame(width: 108, height: 148)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.25), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.45), radius: 14, y: 5)
        .onTapGesture {
            Haptics.tap()
            calls.switchCamera()
        }
    }

    private var chromeVisible: Bool { controlsVisible || voiceOver || showEffects || showReactions || exercisePromptOpen || calls.isStarting || calls.lastErrorMessage != nil }

    private func toggleControls() {
        hideControlsTask?.cancel()
        controlsVisible.toggle()
        guard controlsVisible, !voiceOver else { return }
        hideControlsTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            guard !showEffects, !showReactions, !exercisePromptOpen else { return }
            controlsVisible = false
        }
    }

    private var groupCallStage: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            let remotes = remoteParticipants
            let focus = remotes.first(where: \.isScreenSharing)
                ?? calls.spotlightPeerID.flatMap { id in remotes.first { $0.peerId == id } }
            let usableHeight = max(120, geo.size.height - 20)
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 10) {
                    if let focus {
                        callTile(focus, style: .spotlight)
                            .frame(height: max(80, usableHeight - (remotes.count > 1 ? 106 : 0)))
                        if remotes.count > 1 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(remotes.filter { $0.peerId != focus.peerId }, id: \.peerId) { p in
                                        callTile(p, style: .thumb).frame(width: 72, height: 96)
                                    }
                                }
                            }.contentMargins(.horizontal, 2).frame(height: 96)
                        }
                    } else if remotes.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "person.2.fill").font(.largeTitle)
                            Text(calls.isStarting ? "Joining group call…" : "You're in the group call").font(.headline)
                            Text(calls.isStarting ? "Connecting securely" : "Waiting for others to join").font(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !landscape && remotes.count <= 2 {
                        ForEach(remotes, id: \.peerId) { p in
                            callTile(p, style: .stack).frame(maxHeight: .infinity)
                        }
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: landscape && remotes.count > 4 ? 3 : 2), spacing: 10) {
                                ForEach(remotes, id: \.peerId) { p in
                                    callTile(p, style: .grid).aspectRatio(1, contentMode: .fit)
                                }
                            }.padding(.horizontal, 2)
                        }
                    }
                }
                .frame(height: usableHeight)
                if let me = selfParticipant {
                    callTile(me, style: .pip)
                        .frame(width: min(120, geo.size.width * 0.28), height: min(160, usableHeight * 0.44))
                        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
                        .padding(8)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
        }
    }

    private func gridLayout(everyone: [WhisperLiveRTCService.ParticipantInfo]) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(everyone, id: \.peerId) { p in
                    callTile(p, style: .grid)
                        .aspectRatio(3.0 / 4.0, contentMode: .fill)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 108)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
    }

    private func spotlightLayout(_ spotlit: WhisperLiveRTCService.ParticipantInfo) -> some View {
        VStack(spacing: 10) {
            callTile(spotlit, style: .spotlight)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 12)
                .padding(.top, 104)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(participants.filter { $0.peerId != spotlit.peerId }, id: \.peerId) { p in
                        callTile(p, style: .thumb)
                            .frame(width: 92, height: 122)
                    }
                }
            }
            .contentMargins(.horizontal, 12)
            .frame(height: 122)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Tiles

    private enum CallTileStyle {
        case hero, stack, grid, thumb, pip, spotlight
    }

    private func callTile(_ p: WhisperLiveRTCService.ParticipantInfo, style: CallTileStyle) -> some View {
        let isSelf = p.peerId == localPeerID
        let corner: CGFloat = {
            switch style {
            case .hero: return 0
            case .pip: return 16
            default: return 18
            }
        }()
        let avatarSize: CGFloat = {
            switch style {
            case .hero: return 150
            case .stack: return 110
            case .spotlight, .grid: return 84
            case .thumb: return 40
            case .pip: return 56
            }
        }()
        let showLabel = style == .grid || style == .stack || style == .spotlight || style == .thumb

        return ZStack {
            WhisperParticipantTileMedia(participant: p, isSelf: isSelf,
                avatarURL: avatars[p.userId.lowercased()], avatarSize: avatarSize,
                trackNonce: calls.rtcTick, videoHidden: isSelf && cameraOff, fit: style == .spotlight)

            if showLabel {
                VStack {
                    Spacer()
                    HStack {
                        namePill(p, isSelf: isSelf)
                            .padding(8)
                        Spacer()
                    }
                }
            }

            if !p.micOn && style != .pip {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "mic.slash.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.red)
                            .padding(7)
                            .background(Color.black.opacity(0.55), in: Circle())
                            .padding(8)
                    }
                    Spacer()
                }
            }

            if style != .pip, calls.raisedHands[p.userId.lowercased()] != nil {
                VStack {
                    HStack {
                        Text("\u{270B}")
                            .font(.system(size: 12))
                            .padding(6)
                            .background(Color(red: 1.0, green: 0.78, blue: 0.25), in: Circle())
                            .padding(8)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .background(Color(white: 0.09))
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay {
            if p.isSpeaking && style != .hero {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color(red: 0.53, green: 0.72, blue: 1.0), lineWidth: 3)
                    .shadow(color: Color(red: 0.53, green: 0.72, blue: 1.0).opacity(0.4), radius: 8)
            }
        }
        .contextMenu {
            if isClassHost && !isSelf {
                Button {
                    calls.classSpotlight(peerID: p.peerId)
                } label: {
                    Label("Spotlight for everyone", systemImage: "person.fill.viewfinder")
                }
                Button {
                    calls.classMute(userID: p.userId)
                } label: {
                    Label("Mute \(p.name)", systemImage: "mic.slash.fill")
                }
            }
        }
    }

    private var selfDisplayName: String {
        LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"
    }

    private func namePill(_ p: WhisperLiveRTCService.ParticipantInfo, isSelf: Bool) -> some View {
        HStack(spacing: 5) {
            if !p.micOn {
                Image(systemName: "mic.slash.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
            } else if p.isSpeaking {
                Image(systemName: "waveform")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.cyan)
            }
            Text(isSelf ? "You" : p.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.55), in: Capsule())
    }

    // MARK: - Chrome

    private func topBar(_ call: WhisperCallService.ActiveCall) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text(call.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(formattedElapsed)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                if call.isGroup {
                    HStack(spacing: 3) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text("\(participants.count)")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.5), in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1) }

            if calls.classModeOn {
                HStack(spacing: 6) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("Class \u{00B7} hosted by @\(calls.classHostName ?? "coach")")
                        .font(.system(size: 11, weight: .heavy))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(red: 1.0, green: 0.78, blue: 0.25), in: Capsule())
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if !calls.raisedHands.isEmpty {
                HStack(spacing: 5) {
                    Text("\u{270B}")
                        .font(.system(size: 11))
                    Text(raisedHandsLine)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.55), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Color(red: 1.0, green: 0.78, blue: 0.25).opacity(0.7), lineWidth: 1)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 8)
        .animation(.spring(response: 0.35), value: calls.classModeOn)
        .animation(.spring(response: 0.35), value: calls.raisedHands)
    }

    private var raisedHandsLine: String {
        let names = Array(calls.raisedHands.values)
        guard let first = names.first else { return "" }
        return names.count == 1
            ? "\(first) raised a hand"
            : "\(first) +\(names.count - 1) raised hands"
    }

    private func controlBar(_ call: WhisperCallService.ActiveCall) -> some View {
        // Horizontal scroll keeps every control reachable on small phones
        // now that reactions (and class tools for coaches) joined the bar.
        HStack(spacing: 8) {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                roundControl(
                    icon: muted ? "mic.slash.fill" : "mic.fill",
                    danger: muted
                ) {
                    muted.toggle()
                    calls.setMuted(muted)
                }

                if call.mode == .video {
                    roundControl(
                        icon: cameraOff ? "video.slash.fill" : "video.fill",
                        danger: cameraOff
                    ) {
                        cameraOff.toggle()
                        calls.setCameraEnabled(!cameraOff)
                    }
                    roundControl(icon: "arrow.triangle.2.circlepath.camera") {
                        calls.switchCamera()
                    }
                    roundControl(icon: "wand.and.stars") {
                        showEffects = true
                    }
                    audioRouteControl
                } else {
                    audioRouteControl
                }

                roundControl(icon: "face.smiling", active: showReactions) {
                    withAnimation(.spring(response: 0.3)) { showReactions.toggle() }
                }

                if isClassHost {
                    classMenu
                }

            }
            .padding(.vertical, 10)
          }
          .contentMargins(.horizontal, 4)
          .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
          .frame(height: 72)
          .disabled(calls.isStarting || !WhisperLiveRTCService.shared.connected)
                Button {
                    Haptics.warning()
                    calls.endCall()
                } label: {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 66, height: 52)
                        .background(Color.red, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Leave call")
        }
        .frame(height: 72)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Reactions & class overlays

    /// Floating emoji rain — every reaction (mine and everyone else's)
    /// drifts up over the stage and fades.
    private var reactionsOverlay: some View {
        GeometryReader { geo in
            ForEach(calls.callReactions.suffix(14)) { reaction in
                FloatingCallReaction(reaction: reaction, stageSize: geo.size)
            }
        }
        .allowsHitTesting(false)
    }

    private var reactionBar: some View {
        HStack(spacing: 6) {
            ForEach(reactionEmojis, id: \.self) { emoji in
                Button {
                    Haptics.tap()
                    calls.sendReaction(emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: 24))
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("React \(emoji)")
            }
            Button {
                Haptics.tap()
                calls.setHandRaised(!calls.isMyHandRaised)
            } label: {
                Text("\u{270B}")
                    .font(.system(size: 24))
                    .frame(width: 42, height: 42)
                    .background(
                        calls.isMyHandRaised
                            ? AnyShapeStyle(Color(red: 1.0, green: 0.78, blue: 0.25))
                            : AnyShapeStyle(Color.white.opacity(0.12)),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(calls.isMyHandRaised ? "Lower hand" : "Raise hand")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.55), in: Capsule())
        .overlay { Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1) }
    }

    /// Coach-broadcast work/rest countdown — shown to everyone on the call.
    private func classTimerPill(_ timer: WhisperCallService.ClassTimer) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let remaining = max(0, timer.endsAt.timeIntervalSince(context.date))
            let fraction = min(1, max(0, 1 - remaining / Double(max(timer.totalSeconds, 1))))
            let tint: Color = timer.isRest
                ? Color(red: 0.45, green: 0.75, blue: 1.0)
                : Color(red: 0.35, green: 0.9, blue: 0.6)
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: timer.isRest ? "wind" : "flame.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tint)
                    Text(timer.label.uppercased())
                        .font(.system(size: 10, weight: .black))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer(minLength: 8)
                    Text(Self.mmss(remaining))
                        .font(.system(size: 16, weight: .black).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule()
                            .fill(tint)
                            .frame(width: max(6, g.size.width * fraction))
                    }
                }
                .frame(height: 5)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 260)
            .background(Color.black.opacity(0.6), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(tint.opacity(0.5), lineWidth: 1)
            }
        }
    }

    /// Coach-broadcast "now doing" exercise card — the live class whiteboard.
    private func classExerciseCard(_ exercise: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 34, height: 34)
                .background(Color(red: 1.0, green: 0.78, blue: 0.25), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("NOW")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.55))
                Text(exercise)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if isClassHost {
                Button {
                    Haptics.tap()
                    calls.classSetExercise(nil)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: 340)
        .background(Color.black.opacity(0.6), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    private static func mmss(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Speaker / iPhone / Bluetooth output menu, styled like the round
    /// controls. The Bluetooth row appears whenever a device is connected.
    private var audioRouteControl: some View {
        WhisperAudioRouteMenu(current: audioRoute, onSelect: { route in
            calls.setAudioRoute(route)
            syncMediaControls()
        }, primaryAction: {
            Haptics.tap()
            let route: WhisperAudioRoute = audioRoute == .speaker
                ? (WhisperAudioRoute.connectedBluetoothName() == nil ? .receiver : .bluetooth) : .speaker
            calls.setAudioRoute(route)
            syncMediaControls()
        }) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(audioRoute == .speaker ? Color.black : Color.white)
                .frame(width: 52, height: 52)
                .background(audioRoute == .speaker ? Color.white : Color.white.opacity(0.15), in: Circle())
                .accessibilityLabel("Speaker")
                .accessibilityValue(audioRoute == .speaker ? "On" : "Off")
                .accessibilityHint("Tap to toggle. Touch and hold to choose an audio output.")
        }
    }

    private var classMenu: some View {
        Menu {
            Button {
                Haptics.tap()
                calls.setClassMode(!calls.classModeOn)
            } label: {
                Label(
                    calls.classModeOn ? "End class mode" : "Start class mode",
                    systemImage: "graduationcap.fill"
                )
            }
            Button {
                Haptics.tap()
                calls.classSpotlight(peerID: localPeerID)
            } label: {
                Label("Spotlight me", systemImage: "person.fill.viewfinder")
            }
            if calls.spotlightPeerID != nil {
                Button {
                    Haptics.tap()
                    calls.classSpotlight(peerID: nil)
                } label: {
                    Label("Clear spotlight", systemImage: "rectangle.dashed")
                }
            }
            Divider()
            Button {
                Haptics.tap()
                exerciseDraft = calls.classExercise ?? ""
                exercisePromptOpen = true
            } label: {
                Label(
                    calls.classExercise == nil ? "Set exercise" : "Change exercise",
                    systemImage: "figure.strengthtraining.traditional"
                )
            }
            if calls.classExercise != nil {
                Button {
                    Haptics.tap()
                    calls.classSetExercise(nil)
                } label: {
                    Label("Clear exercise", systemImage: "xmark.circle")
                }
            }
            Menu {
                Button("Work · 30s") { calls.classStartTimer(seconds: 30, label: "Work", isRest: false) }
                Button("Work · 45s") { calls.classStartTimer(seconds: 45, label: "Work", isRest: false) }
                Button("Work · 60s") { calls.classStartTimer(seconds: 60, label: "Work", isRest: false) }
                Button("Rest · 15s") { calls.classStartTimer(seconds: 15, label: "Rest", isRest: true) }
                Button("Rest · 30s") { calls.classStartTimer(seconds: 30, label: "Rest", isRest: true) }
                if calls.classTimer != nil {
                    Button(role: .destructive) {
                        calls.classStopTimer()
                    } label: {
                        Label("Stop timer", systemImage: "stop.circle")
                    }
                }
            } label: {
                Label("Interval timer", systemImage: "timer")
            }
            Divider()
            Button(role: .destructive) {
                Haptics.tap()
                calls.classMuteAll()
            } label: {
                Label("Mute everyone", systemImage: "mic.slash.fill")
            }
        } label: {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 52, height: 52)
                .background(Color(red: 1.0, green: 0.78, blue: 0.25), in: Circle())
        }
    }

    private func roundControl(
        icon: String,
        danger: Bool = false,
        active: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(danger ? .white : (active ? .black : .white))
                .frame(width: 52, height: 52)
                .background(
                    danger
                        ? AnyShapeStyle(Color.red)
                        : (active ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.14))),
                    in: Circle()
                )
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared pieces

    /// Full-bleed blurred profile photo — the ring/audio-stage backdrop.
    private func blurredBackdrop(_ call: WhisperCallService.ActiveCall) -> some View {
        Color.black
            .overlay {
                if let url = call.avatarURL {
                    WhisperCachedAsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .blur(radius: 58, opaque: true)
                                .saturation(0.95)
                                .overlay(Color.black.opacity(0.55))
                        } else {
                            ringFallbackGradient
                        }
                    }
                    .allowsHitTesting(false)
                } else {
                    ringFallbackGradient
                }
            }
            .clipped()
            .ignoresSafeArea()
    }

    private var ringFallbackGradient: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.16), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Color.white.opacity(0.1), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 380
            )
        }
    }

    /// Closing frame — reads out exactly how the call ended so the flow is
    /// always ringing → connecting → in call, or ringing → missed/declined.
    private var endedScreen: some View {
        let reason = call?.endReason ?? .completed
        let outgoing = call?.direction == .outgoing
        let icon: String
        let title: String
        let subtitle: String?
        switch reason {
        case .missed:
            icon = outgoing ? "phone.badge.clock.fill" : "phone.arrow.down.left.fill"
            title = outgoing ? "No answer" : "Missed call"
            subtitle = outgoing ? "\(call?.title ?? "They") didn't pick up" : (call?.title).map { "\($0) tried to reach you" }
        case .declined:
            icon = "phone.down.fill"
            title = outgoing ? "Call declined" : "Declined"
            subtitle = nil
        case .cancelled:
            icon = "phone.down.fill"
            title = "Call cancelled"
            subtitle = nil
        case .completed:
            icon = "phone.down.fill"
            title = "Call ended"
            subtitle = nil
        }
        return ZStack {
            if let call { blurredBackdrop(call) }
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(reason == .missed ? Color.red.opacity(0.95) : .white.opacity(0.75))
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.9))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                if reason == .completed && elapsed > 1 {
                    Text(formattedElapsed)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.94)))
        }
    }

    private func banner(_ text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(tint.opacity(0.92), in: Capsule())
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Avatars & ticker

    private func hydrateAvatars() async {
        var ids = participants
            .map { $0.userId }
            .filter { !$0.isEmpty && $0.lowercased() != "guest" && !$0.hasPrefix("local_") }
        if let other = call?.otherUserID, !other.isEmpty { ids.append(other) }
        guard !ids.isEmpty else { return }
        let profiles = await WhisperBackendService.shared.fetchPublicProfiles(userIDs: ids)
        var merged = avatars
        for (key, profile) in profiles {
            if let raw = profile.profile_image_url, let url = URL(string: raw) {
                merged[key.lowercased()] = url
            }
        }
        avatars = merged
    }

    private func startTicker() {
        tickerTask?.cancel()
        tickerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if let c = calls.active, c.state == .connected, let started = c.startedAt {
                    elapsed = Date().timeIntervalSince(started)
                }
                // Prune reactions that finished floating.
                if !calls.callReactions.isEmpty {
                    calls.callReactions.removeAll { Date().timeIntervalSince($0.at) > 3 }
                }
            }
        }
    }

    private var formattedElapsed: String {
        let total = Int(elapsed)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

/// One floating emoji — drifts up from the lower stage with a light sway,
/// scales in, then fades near the top. Position is seeded off the reaction
/// id so simultaneous reactions spread across the width.
private struct FloatingCallReaction: View {
    let reaction: WhisperCallService.CallReaction
    let stageSize: CGSize
    @State private var progress: CGFloat = 0

    private var xAnchor: CGFloat {
        let h = CGFloat(abs(reaction.id.hashValue % 100)) / 100
        return 0.15 + h * 0.7
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(reaction.emoji)
                .font(.system(size: 34))
            Text(reaction.fromName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.4), in: Capsule())
        }
        .position(
            x: stageSize.width * xAnchor + sin(progress * .pi * 2.2) * 14,
            y: stageSize.height * (0.82 - 0.58 * progress)
        )
        .opacity(progress < 0.8 ? 1 : Double(1 - (progress - 0.8) / 0.2))
        .scaleEffect(0.7 + 0.3 * min(progress * 4, 1))
        .onAppear {
            withAnimation(.easeOut(duration: 2.4)) { progress = 1 }
        }
        .allowsHitTesting(false)
    }
}
