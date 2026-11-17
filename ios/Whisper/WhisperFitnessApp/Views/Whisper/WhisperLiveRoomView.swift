import SwiftUI
import WebRTC
import Supabase

/// Full-screen Instagram-style live broadcast. Video fills the entire screen
/// edge-to-edge with smart split layouts for group lives (1 full / 2 stacked /
/// 3 one-big-two-small / 4 grid), floating chat over the bottom third,
/// floating hearts, a pulsing LIVE badge, share links, screen sharing, and
/// mid-live co-host invites — capped at 4 broadcasters.
struct WhisperLiveRoomView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var active = false
    @State private var lifecycle = UUID()
    @State private var accountGeneration = AccountStorage.generation
    @State private var initializationTask: Task<Void, Never>?
    @State private var refreshTask: Task<Void, Never>?
    @State private var refreshPending = false
    let room: WhisperLiveRoom
    let isHost: Bool

    @State private var service = WhisperLiveRoomService.shared
    @State private var currentRoom: WhisperLiveRoom
    @State private var speakers: [WhisperLiveSpeaker] = []
    @State private var requests: [WhisperLiveSpeakerRequest] = []
    @State private var profiles: [String: WhisperBackendService.WhisperPublicProfile] = [:]
    @State private var micOn: Bool = true
    @State private var cameraOn: Bool = false
    @State private var connected: Bool = false
    @State private var ownsRTC: Bool = false
    @State private var connectOperation: UUID?
    @State private var connecting: Bool = false
    @State private var screenSharing: Bool = false
    @State private var showRequestForm: Bool = false
    @State private var showRequestsPanel: Bool = false
    @State private var showInviteSheet: Bool = false
    @State private var confirmEnd: Bool = false
    @State private var connectionFailed: Bool = false
    @State private var permissionDenied: Bool = false
    @State private var userID: String = ""
    @State private var username: String = ""
    @State private var wasSpeaker: Bool = false
    // Chat state
    @State private var chatMessages: [WhisperLiveChatMessage] = []
    @State private var chatDraft: String = ""
    @State private var chatService = WhisperLiveChatService.shared
    // Moderation — channel mods/bans, room timeouts, banned words (live-v2/v3).
    @State private var moderation = WhisperLiveModerationService.shared
    /// Friendly reason a send was blocked — shows briefly above the input.
    @State private var moderationNotice: String?
    /// Bumped whenever RTC participants/tracks change, forcing tiles to re-render.
    @State private var trackNonce: Int = 0
    @State private var roomEnded: Bool = false
    // Floating hearts
    @State private var hearts: [WhisperLiveHeart] = []
    // Pulsing LIVE dot
    @State private var livePulse: Bool = false
    // Role tool sheets
    @State private var showCoachTools: Bool = false
    @State private var showCreatorTools: Bool = false
    @State private var showRecruiterTools: Bool = false
    /// Virtual backdrop / blur picker — same engine as meetings and calls.
    @State private var showEffectsSheet: Bool = false
    // Live polls — shared tables with web so both audiences vote together.
    @State private var pollService = WhisperLivePollService.shared
    @State private var showPollCreator: Bool = false
    /// Speaker / iPhone / Bluetooth output for this live.
    @State private var audioRoute: WhisperAudioRoute = .speaker
    @FocusState private var chatFocused: Bool

    private let liveRed = Color(red: 0.95, green: 0.15, blue: 0.35)

    init(room: WhisperLiveRoom, isHost: Bool) {
        self.room = room
        self.isHost = isHost
        _currentRoom = State(initialValue: room)
    }

    // MARK: - Derived

    private var isSpeaker: Bool {
        speakers.contains { $0.user_id.lowercased() == userID.lowercased() }
    }

    private var isBroadcaster: Bool { isHost || isSpeaker }

    /// Host plus the host's channel mods — who gets chat mod tools.
    private var canModerate: Bool {
        isHost || moderation.isMod(userID)
    }

    /// Up to 4 on-camera participants — screen sharer first (gets the big
    /// tile), then host, then stable ordering.
    private var broadcasters: [WhisperLiveRTCService.ParticipantInfo] {
        _ = trackNonce
        let parts = ownsRTC ? WhisperLiveRTCService.shared.participants.filter { $0.isSpeaker } : []
        let hostIDs = Set(speakers.filter { $0.is_host }.map { $0.user_id.lowercased() })
        let sorted = parts.sorted { a, b in
            if a.isScreenSharing != b.isScreenSharing { return a.isScreenSharing }
            let aHost = hostIDs.contains(a.userId.lowercased())
            let bHost = hostIDs.contains(b.userId.lowercased())
            if aHost != bHost { return aHost }
            return a.peerId < b.peerId
        }
        return Array(sorted.prefix(WhisperLiveRoomService.maxBroadcasters))
    }

    private var pendingRequests: [WhisperLiveSpeakerRequest] {
        requests.filter { $0.status == "pending" }
    }

    private var hostUsername: String {
        profiles[room.host_id]?.username ?? "live"
    }

    private func displayName(for participant: WhisperLiveRTCService.ParticipantInfo) -> String {
        if participant.userId.lowercased() == userID.lowercased() { return "You" }
        return profiles[participant.userId]?.username ?? participant.name
    }

    private func avatarURL(for userId: String) -> URL? {
        profiles[userId]?.profile_image_url.flatMap { URL(string: $0) }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // ─── Stage — full-screen split video ───
            GeometryReader { geo in
                stage(in: geo.size)
            }
            .ignoresSafeArea()
            .onTapGesture(count: 2) {
                Haptics.tap()
                WhisperLiveRTCService.shared.sendReaction("❤️")
            }

            // Scrims so overlays stay legible over video.
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 140)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 300)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // ─── Overlay chrome ───
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                bottomOverlay.disabled(!ownsRTC)
            }

            // Floating hearts (bottom-right).
            WhisperLiveHeartsOverlay(hearts: hearts)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 30)
                .padding(.bottom, 140)

            if connecting && !connected {
                joiningOverlay
            }

            if roomEnded {
                endedOverlay
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !WhisperLiveRTCService.shared.isInUse, WhisperCallService.shared.active == nil,
                  !WhisperCallService.shared.isStarting, !WhisperMeetingWindow.shared.isPresenting else {
                dismiss()
                return
            }
            active = true
            lifecycle = UUID()
            accountGeneration = AccountStorage.generation
            userID = SupabaseService.shared.client.auth.currentUser?.id.uuidString ?? ""
            username = LeaderboardService.shared.savedUsername
                ?? AuthenticationService.shared.currentUser.username
                ?? userID
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                livePulse = true
            }
            let token = lifecycle
            initializationTask?.cancel()
            initializationTask = Task {
                await loadData()
                guard isCurrent(token) else { return }
                await connect()
            }
        }
        .onChange(of: speakers) { _, newSpeakers in
            // Auto-promote only within the RTC room this screen owns.
            guard ownsRTC, connected else { return }
            let isNowSpeaker = newSpeakers.contains { $0.user_id.lowercased() == userID.lowercased() }
            if isNowSpeaker && !wasSpeaker && !isHost {
                wasSpeaker = true
                Task {
                    await WhisperLiveRTCService.shared.becomeSpeaker()
                    micOn = true
                    cameraOn = true
                }
            } else if !isNowSpeaker {
                wasSpeaker = false
            }
            // Auto-end: if all speakers leave, show ended state and dismiss.
            if newSpeakers.isEmpty && connected {
                endLocally()
            }
        }
        .onDisappear { stopDataWork() }
        .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in
            stopDataWork()
            chatDraft = ""; chatMessages = []; profiles = [:]
            dismiss()
        }
        .sheet(isPresented: $showRequestForm) {
            SpeakerRequestSheet(roomID: room.id, service: service, onSent: {
                showRequestForm = false
            })
        }
        .sheet(isPresented: $showRequestsPanel) {
            SpeakerRequestsPanel(roomID: room.id, service: service, requests: requests, onUpdated: {
                Task { await refreshRoomData() }
            })
        }
        .sheet(isPresented: $showInviteSheet) {
            WhisperLiveInviteSheet(
                maxSelectable: max(0, WhisperLiveRoomService.maxBroadcasters - speakers.count),
                alreadyIn: Set(speakers.map { $0.user_id.lowercased() }),
                onInvite: { chosen in
                    Task {
                        await service.invite(roomID: room.id, inviteeIDs: chosen.map { $0.user_id })
                    }
                }
            )
        }
        .alert("Connection lost", isPresented: $connectionFailed) {
            Button("Retry") {
                Task {
                    await disconnect()
                    connected = false
                    connecting = false
                    await connect()
                }
            }
            Button("Leave", role: .cancel) { dismiss() }
        } message: {
            Text("The connection to the live room dropped. Retry to reconnect.")
        }
        .alert("Camera & microphone needed", isPresented: $permissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("To go live, allow camera and microphone access in Settings. Viewers can still watch without them.")
        }
        .confirmationDialog("End your live?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End live", role: .destructive) {
                Task { await endRoom() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your live will end for everyone and be removed.")
        }
        .sheet(isPresented: $showCoachTools) {
            CoachToolsSheet(roomID: room.id, userID: userID, username: username, chatService: chatService, onClose: { showCoachTools = false })
        }
        .sheet(isPresented: $showCreatorTools) {
            CreatorToolsSheet(onClose: { showCreatorTools = false })
        }
        .sheet(isPresented: $showRecruiterTools) {
            RecruiterToolsSheet(roomID: room.id, speakers: speakers, listenerCount: currentRoom.listener_count, onClose: { showRecruiterTools = false })
        }
        .sheet(isPresented: $showEffectsSheet) {
            WhisperVideoEffectsSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPollCreator) {
            WhisperLivePollCreatorSheet(roomID: room.id)
        }
        .task(id: "\(room.id)|\(scenePhase)|\(active)") {
            guard scenePhase == .active, isCurrent(lifecycle) else { return }
            // Poll sync — web creates/votes via realtime; an 8s cadence (plus
            // instant refresh after local actions) keeps iOS in lockstep.
            pollService.reset()
            await pollService.refresh(roomID: room.id)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { break }
                await pollService.refresh(roomID: room.id)
            }
        }
    }

    // MARK: - Stage layouts

    @ViewBuilder
    private func stage(in size: CGSize) -> some View {
        let list = broadcasters
        let ids = list.map { $0.peerId }
        Group {
            switch list.count {
            case 0:
                emptyStage
            case 1:
                tile(list[0], width: size.width, height: size.height)
            case 2:
                VStack(spacing: 2) {
                    tile(list[0], width: size.width, height: (size.height - 2) / 2)
                    tile(list[1], width: size.width, height: (size.height - 2) / 2)
                }
            case 3:
                VStack(spacing: 2) {
                    tile(list[0], width: size.width, height: size.height * 0.5)
                    HStack(spacing: 2) {
                        tile(list[1], width: (size.width - 2) / 2, height: size.height * 0.5 - 2)
                        tile(list[2], width: (size.width - 2) / 2, height: size.height * 0.5 - 2)
                    }
                }
            default:
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        tile(list[0], width: (size.width - 2) / 2, height: (size.height - 2) / 2)
                        tile(list[1], width: (size.width - 2) / 2, height: (size.height - 2) / 2)
                    }
                    HStack(spacing: 2) {
                        tile(list[2], width: (size.width - 2) / 2, height: (size.height - 2) / 2)
                        tile(list[3], width: (size.width - 2) / 2, height: (size.height - 2) / 2)
                    }
                }
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: ids)
    }

    private func tile(_ participant: WhisperLiveRTCService.ParticipantInfo, width: CGFloat, height: CGFloat) -> some View {
        LiveStageTile(
            participant: participant,
            isLocal: participant.userId.lowercased() == userID.lowercased(),
            isHostTile: speakers.contains { $0.user_id.lowercased() == participant.userId.lowercased() && $0.is_host },
            displayName: displayName(for: participant),
            avatarImageURL: avatarURL(for: participant.userId),
            trackNonce: trackNonce
        )
        .frame(width: width, height: height)
        .clipped()
        .transition(.asymmetric(
            insertion: .scale(scale: 0.8).combined(with: .opacity),
            removal: .opacity
        ))
    }

    private var emptyStage: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.05, blue: 0.12), Color.black],
                startPoint: .top, endPoint: .bottom
            )
            VStack(spacing: 14) {
                WhisperAvatar(username: hostUsername, size: 84, imageURL: avatarURL(for: room.host_id))
                Text("Waiting for the host…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            // Interlocked broadcaster avatars + live name.
            HStack(spacing: 8) {
                WhisperLiveAvatarCluster(
                    userIDs: speakers.map { $0.user_id },
                    profiles: profiles,
                    size: 38,
                    ringColor: .black
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(currentRoom.name)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("@\(hostUsername)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .padding(.trailing, 4)
            .frame(maxWidth: 190, alignment: .leading)

            // LIVE badge with pulsing dot.
            HStack(spacing: 4) {
                Circle()
                    .fill(.white)
                    .frame(width: 6, height: 6)
                    .scaleEffect(livePulse ? 1.25 : 0.8)
                    .opacity(livePulse ? 1 : 0.6)
                Text("LIVE")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(liveRed, in: Capsule())

            // Viewer count.
            HStack(spacing: 4) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 10))
                Text("\(max(currentRoom.listener_count, 0))")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.white.opacity(0.18), in: Capsule())

            Spacer()

            // Share link.
            ShareLink(item: currentRoom.shareURL, message: Text("Join my live on Whisper")) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.18), in: Circle())
            }

            // Close / end.
            Button {
                Haptics.tap()
                if isHost {
                    confirmEnd = true
                } else {
                    Task {
                        if isSpeaker {
                            try? await service.removeSpeaker(roomID: room.id, userID: userID)
                        }
                        await disconnect()
                        dismiss()
                    }
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    // MARK: - Bottom overlay (chat + controls)

    private var bottomOverlay: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let pinned = chatMessages.first(where: { $0.is_pinned }) {
                pinnedPill(pinned)
            }

            // Live polls — created on either platform, voted on both.
            ForEach(Array(pollService.polls.prefix(2))) { poll in
                WhisperLivePollCard(
                    poll: poll,
                    counts: pollService.voteCounts[poll.id] ?? [],
                    myVote: pollService.myVotes[poll.id],
                    canClose: poll.closed_at == nil
                        && poll.creator_id.lowercased() == userID.lowercased(),
                    onVote: { idx in
                        Task { await pollService.vote(pollID: poll.id, optionIndex: idx, roomID: room.id) }
                    },
                    onClose: {
                        Task { await pollService.close(pollID: poll.id, roomID: room.id) }
                    }
                )
            }

            chatList

            if let moderationNotice {
                HStack(spacing: 6) {
                    Image(systemName: "hand.raised.fill")
                        .font(.caption2.weight(.bold))
                    Text(moderationNotice)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.55), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 10) {
                chatInput

                // Heart button — floats a reaction to everyone.
                Button {
                    Haptics.tap()
                    WhisperLiveRTCService.shared.sendReaction(["❤️", "🔥", "👏", "😂", "💯"].randomElement() ?? "❤️")
                } label: {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(liveRed)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.15), in: Circle())
                }
                .buttonStyle(.plain)

                if !isBroadcaster {
                    Button {
                        Haptics.tap()
                        showRequestForm = true
                    } label: {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.15), in: Circle())
                    }
                    .buttonStyle(.plain)

                    // Listeners pick where live audio plays too.
                    WhisperAudioRouteMenu(current: audioRoute, onSelect: { route in
                        audioRoute = route
                        WhisperLiveRTCService.shared.setAudioRoute(route)
                    }) {
                        Image(systemName: audioRoute.controlIcon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.15), in: Circle())
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
            }

            if isBroadcaster {
                broadcasterControls
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func pinnedPill(_ pinned: WhisperLiveChatMessage) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "pin.fill")
                .font(.caption2)
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 1) {
                Text(pinned.username)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(chatBody(pinned))
                    .font(.caption)
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if isHost {
                Button {
                    Task {
                        try? await chatService.togglePin(messageID: pinned.id, pinned: false)
                        chatMessages = await chatService.fetchMessages(roomID: room.id)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 320, alignment: .leading)
    }

    private var chatList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(chatMessages.suffix(8)) { msg in
                moderatedChatRow(msg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: 300, alignment: .leading)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: chatMessages.count)
        .mask(
            LinearGradient(
                colors: [.clear, .black, .black],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.35)
            )
        )
    }

    /// Chat row wearing the mod tools — hosts and channel mods long-press
    /// any message for delete / timeout / channel ban (their own messages
    /// only offer delete). The live-v3 policies enforce all of it server-side.
    @ViewBuilder
    private func moderatedChatRow(_ msg: WhisperLiveChatMessage) -> some View {
        if canModerate {
            chatRow(msg)
                .contextMenu {
                    Button(role: .destructive) {
                        modDelete(msg)
                    } label: {
                        Label("Delete message", systemImage: "trash")
                    }
                    if msg.user_id.lowercased() != userID.lowercased(),
                       msg.user_id.lowercased() != room.host_id.lowercased() {
                        Button {
                            modTimeout(msg)
                        } label: {
                            Label("Time out 5 min", systemImage: "clock.badge.exclamationmark")
                        }
                        Button(role: .destructive) {
                            modBan(msg)
                        } label: {
                            Label("Ban @\(msg.username)", systemImage: "nosign")
                        }
                    }
                }
        } else {
            chatRow(msg)
        }
    }

    private func chatRow(_ msg: WhisperLiveChatMessage) -> some View {
        // Workout embeds render as a tappable interactive card.
        if let workout = WhisperWorkoutEmbed.decode(msg.body) {
            return AnyView(
                HStack(alignment: .top, spacing: 8) {
                    WhisperAvatar(username: msg.username, size: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(msg.username)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.85))
                            if msg.is_host {
                                Text("Host")
                                    .font(.system(size: 8, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(liveRed.opacity(0.85), in: Capsule())
                            }
                        }
                        WhisperLiveWorkoutChatCard(payload: workout)
                    }
                }
                .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
            )
        }
        return AnyView(
            HStack(alignment: .top, spacing: 8) {
                WhisperAvatar(username: msg.username, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(msg.username)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.85))
                        if msg.is_host {
                            Text("Host")
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(liveRed.opacity(0.85), in: Capsule())
                        }
                        if isHost {
                            Button {
                                Task {
                                    try? await chatService.togglePin(messageID: msg.id, pinned: !msg.is_pinned)
                                    chatMessages = await chatService.fetchMessages(roomID: room.id)
                                }
                            } label: {
                                Image(systemName: msg.is_pinned ? "pin.fill" : "pin")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text(chatBody(msg))
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
        )
    }

    /// Friendly rendering for embed messages in the compact overlay chat.
    /// Any `::whisper-...::` structured embed gets a human-readable summary
    /// instead of leaking raw JSON into the chat overlay.
    private func chatBody(_ msg: WhisperLiveChatMessage) -> String {
        let body = msg.body
        if body.hasPrefix("::whisper-workout-v1::") { return "📋 shared a training plan" }
        if body.hasPrefix("::whisper-recipe-v1::") { return "🥘 shared a recipe" }
        if body.hasPrefix("::whisper-grocery-v1::") { return "🛒 shared a grocery list" }
        if body.hasPrefix("::whisper-checkin-v1::") { return "✅ checked in" }
        if body.hasPrefix("::whisper-chart-v1::") { return "📈 shared a chart" }
        if body.hasPrefix("::whisper-calendar-v1::") { return "📅 shared a calendar event" }
        if body.hasPrefix("::whisper-program-v1::") { return "📋 shared a training program" }
        if body.hasPrefix("::whisper-coach-macros-v1::") { return "🔥 shared nutrition goals" }
        if body.hasPrefix("::whisper-coach-diet-plan-v1::") { return "🍽️ shared a diet plan" }
        if body.hasPrefix("::whisper-coach-targets-v1::") { return "🎯 shared daily targets" }
        if body.hasPrefix("::whisper-coach-proposal-v1::") { return "📋 new coach suggestion" }
        if body.hasPrefix("::whisper-healthshare-v1::") { return "❤️ shared health stats" }
        if body.hasPrefix("::whisper-map-v1::") { return "🗺️ shared a map" }
        if body.hasPrefix("::whisper-sharedpost-v1::") { return "📎 shared a post" }
        if body.hasPrefix("::whisper-factcheck-v1::") { return "🔍 fact check result" }
        if body.hasPrefix("::whisper-ember-answer-v1::") { return "✨ Jasper answered" }
        if body.hasPrefix("::whisper-profileshare-v1::") { return "👤 shared a profile" }
        if body.hasPrefix("::whisper-call-v1::") { return "📞 call" }
        if body.hasPrefix("::whisper-callsummary-v1::") { return "📞 call ended" }
        if body.hasPrefix("::whisper-macros-v1::") { return "🔥 shared macros" }
        if body.hasPrefix("::whisper-thought-reply-v1::") { return "💬 replied" }
        if body.hasPrefix("::whisper-workoutproposal-v1::") { return "🏋️ proposed a workout" }
        if body.hasPrefix("::whisper-postmeta-v1::") { return "📊 shared poll data" }
        if body.hasPrefix("::whisper-") { return "📎 shared an attachment" }
        return body
    }

    private var chatInput: some View {
        HStack(spacing: 8) {
            TextField("", text: $chatDraft, prompt: Text("Comment…").foregroundStyle(.white.opacity(0.55)))
                .textFieldStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.white)
                .tint(.white)
                .focused($chatFocused)
                .onSubmit { Task { await sendChat() } }

            if !chatDraft.trimmingCharacters(in: .whitespaces).isEmpty {
                Button {
                    Task { await sendChat() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.white.opacity(0.15), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: chatDraft.isEmpty)
    }

    // MARK: - Broadcaster controls

    private var broadcasterControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 10) {
            controlButton(
                icon: micOn ? "mic.fill" : "mic.slash.fill",
                active: micOn,
                tint: micOn ? .white : liveRed
            ) {
                micOn.toggle()
                WhisperLiveRTCService.shared.setMuted(!micOn)
            }

            controlButton(
                icon: cameraOn ? "video.fill" : "video.slash.fill",
                active: cameraOn,
                tint: cameraOn ? .white : liveRed
            ) {
                cameraOn.toggle()
                WhisperLiveRTCService.shared.setCameraEnabled(cameraOn)
            }

            controlButton(icon: "arrow.triangle.2.circlepath.camera", active: false, tint: .white) {
                WhisperLiveRTCService.shared.switchCamera()
                trackNonce += 1
            }

            // Virtual backdrop / blur — applies live to the outgoing camera
            // (shared engine with meetings and 1:1 calls).
            controlButton(icon: "wand.and.stars", active: false, tint: .white) {
                showEffectsSheet = true
            }

            // Screen share toggle.
            controlButton(
                icon: screenSharing ? "rectangle.on.rectangle.slash" : "rectangle.on.rectangle",
                active: screenSharing,
                tint: screenSharing ? .green : .white
            ) {
                Task {
                    if screenSharing {
                        await WhisperLiveRTCService.shared.stopScreenShare()
                    } else {
                        _ = await WhisperLiveRTCService.shared.startScreenShare()
                    }
                    screenSharing = WhisperLiveRTCService.shared.isScreenSharing
                }
            }

            // Audio output — Bluetooth device / iPhone / speaker.
            WhisperAudioRouteMenu(current: audioRoute, onSelect: { route in
                audioRoute = route
                WhisperLiveRTCService.shared.setAudioRoute(route)
            }) {
                Image(systemName: audioRoute.controlIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.15), in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }

            if canCreatePolls {
                // Spin up a live poll — renders for iOS and web instantly.
                controlButton(icon: "chart.bar.fill", active: false, tint: .white) {
                    showPollCreator = true
                }
            }

            if isHost {
                // Invite friends mid-live.
                controlButton(icon: "person.badge.plus", active: false, tint: .white) {
                    showInviteSheet = true
                }

                // Join requests with badge.
                ZStack(alignment: .topTrailing) {
                    controlButton(icon: "hand.raised.fill", active: !pendingRequests.isEmpty, tint: .white) {
                        showRequestsPanel = true
                    }
                    if !pendingRequests.isEmpty {
                        Text("\(pendingRequests.count)")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(liveRed, in: Capsule())
                            .offset(x: 5, y: -4)
                    }
                }
            }

            Spacer(minLength: 0)

            if isCoach || isCreator || isRecruiter {
                Menu {
                    if isCoach {
                        Button { showCoachTools = true } label: {
                            Label("Coach tools", systemImage: "dumbbell.fill")
                        }
                    }
                    if isCreator {
                        Button { showCreatorTools = true } label: {
                            Label("Creator tools", systemImage: "sparkles")
                        }
                    }
                    if isRecruiter {
                        Button { showRecruiterTools = true } label: {
                            Label("Recruiting tools", systemImage: "target")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.15), in: Circle())
                }
            }
        }
        .padding(.vertical, 5)
        }
        .contentMargins(.horizontal, 4)
        .frame(height: 54)
    }

    private func controlButton(icon: String, active: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(.white.opacity(active ? 0.22 : 0.15), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(controlLabel(icon))
    }

    private func controlLabel(_ icon: String) -> String {
        switch icon {
        case "mic.fill": "Mute microphone"
        case "mic.slash.fill": "Unmute microphone"
        case "video.fill": "Turn camera off"
        case "video.slash.fill": "Turn camera on"
        case "arrow.triangle.2.circlepath.camera": "Switch camera"
        case "wand.and.stars": "Camera effects"
        case "rectangle.on.rectangle.slash": "Stop screen sharing"
        case "rectangle.on.rectangle": "Share screen"
        case "chart.bar.fill": "Create poll"
        case "person.badge.plus": "Invite people"
        case "hand.raised.fill": "Join requests"
        default: "Live controls"
        }
    }

    // MARK: - Overlays

    private var joiningOverlay: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 18) {
                ZStack {
                    WhisperLiveRing(size: 108, lineWidth: 3)
                        .scaleEffect(livePulse ? 1.06 : 0.96)
                    WhisperAvatar(username: hostUsername, size: 88, imageURL: avatarURL(for: room.host_id))
                }
                Text("Joining live…")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .opacity(livePulse ? 1 : 0.5)
            }
        }
        .transition(.opacity)
    }

    private var endedOverlay: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 14) {
                WhisperLiveAvatarCluster(
                    userIDs: speakers.isEmpty ? [room.host_id] : speakers.map { $0.user_id },
                    profiles: profiles,
                    size: 84,
                    ringColor: .black
                )
                Text("This live has ended")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text("Thanks for watching")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                Button {
                    dismiss()
                } label: {
                    Text("Close")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 11)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 1.05)))
    }

    // MARK: - Roles

    private var isCoach: Bool {
        WhisperCoachService.shared.isMeCoach
    }

    private var isRecruiter: Bool {
        WhisperRecruiterService.shared.isMeRecruiter
    }

    private var isCreator: Bool {
        // Mirrors the web gate exactly (verified && !coach && !recruiter) so
        // the same person sees the same tools on both platforms.
        let user = AuthenticationService.shared.currentUser
        return user.isVerified
            && !WhisperCoachService.shared.isMeCoach
            && !WhisperRecruiterService.shared.isMeRecruiter
    }

    /// Who can start polls — host plus every verified role (web parity).
    private var canCreatePolls: Bool {
        isBroadcaster && (isHost || isCoach || isRecruiter || isCreator)
    }

    // MARK: - Hearts

    private func addHeart(_ emoji: String) {
        let heart = WhisperLiveHeart(emoji: emoji)
        hearts.append(heart)
        // Prune after the animation completes.
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            hearts.removeAll { $0.id == heart.id }
        }
    }

    // MARK: - Data

    private func stopDataWork() {
        // A rejected entry never owns these shared subscriptions or RTC callbacks.
        guard active else { return }
        active = false
        lifecycle = UUID()
        connectOperation = nil
        initializationTask?.cancel(); initializationTask = nil
        refreshTask?.cancel(); refreshTask = nil; refreshPending = false
        service.unsubscribe()
        chatService.unsubscribe()
        Task { await disconnect() }
    }

    private func isCurrent(_ token: UUID) -> Bool {
        active && lifecycle == token && accountGeneration == AccountStorage.generation && !Task.isCancelled
    }

    private func loadData() async {
        let token = lifecycle
        await refreshRoomData()
        guard isCurrent(token), !roomEnded else { return }
        // Subscribe to room changes (speakers, requests, room status) — this
        // triggers `refreshRoomData` on every change, NOT a full reload.
        service.subscribeToRoom(roomID: room.id) {
            guard isCurrent(token) else { return }
            Task { await refreshRoomData() }
        }
        // Load chat history + subscribe to realtime ONCE. Re-subscribing on
        // every realtime tick tears down the channel before messages arrive.
        let history = await chatService.fetchMessages(roomID: room.id)
        guard isCurrent(token) else { return }
        chatMessages = history
        await moderation.refresh(hostID: room.host_id, roomID: room.id)
        guard isCurrent(token) else { return }
        chatService.subscribe(
            roomID: room.id,
            onInsert: { msg in
                guard isCurrent(token) else { return }
                if !chatMessages.contains(where: { $0.id == msg.id }) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        chatMessages.append(msg)
                        if chatMessages.count > 200 { chatMessages.removeFirst(chatMessages.count - 200) }
                    }
                }
            },
            onDelete: { id in
                guard isCurrent(token) else { return }
                chatMessages.removeAll { $0.id == id }
            }
        )
    }

    /// Refresh speakers, requests, room status, and profile hydration.
    /// Called on initial load AND on every realtime tick. Does NOT
    /// re-subscribe to chat (that's done once in `loadData`).
    private func refreshRoomData() async {
        guard isCurrent(lifecycle) else { return }
        refreshPending = true
        if let refreshTask { await refreshTask.value; return }
        let token = lifecycle
        let worker = Task { @MainActor in
            while refreshPending && isCurrent(token) {
                refreshPending = false
                do {
                    let nextSpeakers = try await service.fetchSpeakers(roomID: room.id)
                    let nextRequests = try await service.fetchSpeakerRequests(roomID: room.id)
                    let fresh = try? await service.fetchRoom(id: room.id)
                    guard isCurrent(token) else { return }
                    let ids = nextSpeakers.map { $0.user_id } + [room.host_id]
                    let nextProfiles = await service.hydrateProfiles(userIDs: ids)
                    guard isCurrent(token) else { return }
                    speakers = nextSpeakers
                    requests = nextRequests
                    profiles = nextProfiles
                    if let fresh {
                        currentRoom = fresh
                        if !fresh.is_live && !fresh.isUpcoming { endLocally() }
                    }
                    trackNonce += 1
                } catch {
                    guard isCurrent(token) else { return }
                    print("[WhisperLiveRoom] refreshRoomData failed")
                }
            }
        }
        refreshTask = worker
        await worker.value
        if refreshTask == worker { refreshTask = nil }
    }

    private func connect() async {
        guard isCurrent(lifecycle), !roomEnded, !connecting, !connected else { return }
        guard !WhisperLiveRTCService.shared.isInUse, WhisperCallService.shared.active == nil,
              !WhisperCallService.shared.isStarting, !WhisperMeetingWindow.shared.isPresenting else {
            showModerationNotice("Leave your current call or meeting before joining this live.")
            return
        }
        connecting = true
        let operation = UUID(); connectOperation = operation
        let generation = AccountStorage.generation
        defer { connecting = false }

        let name = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? userID

        // Invited co-hosts auto-join the broadcast grid, Instagram-style.
        var joinAsBroadcaster = isHost
        if !isHost, await service.hasInvite(roomID: room.id) {
            guard isCurrent(lifecycle), !roomEnded, connectOperation == operation,
                  generation == AccountStorage.generation else { return }
            if (try? await service.addSpeaker(roomID: room.id, userID: userID, isCohost: true)) != nil {
                guard isCurrent(lifecycle), !roomEnded, connectOperation == operation,
                      generation == AccountStorage.generation else { return }
                joinAsBroadcaster = true
                wasSpeaker = true
                await service.acceptInvite(roomID: room.id)
            }
        }

        guard connectOperation == operation, !Task.isCancelled, generation == AccountStorage.generation,
              !WhisperLiveRTCService.shared.isInUse, WhisperCallService.shared.active == nil,
              !WhisperCallService.shared.isStarting, !WhisperMeetingWindow.shared.isPresenting else { return }
        ownsRTC = true
        WhisperLiveRTCService.shared.onParticipantsChanged = {
            trackNonce += 1
            screenSharing = WhisperLiveRTCService.shared.isScreenSharing
        }
        WhisperLiveRTCService.shared.onRemoteVideoTrackForPeer = { _, _ in trackNonce += 1 }
        WhisperLiveRTCService.shared.onReaction = { emoji in addHeart(emoji) }
        WhisperLiveRTCService.shared.onPermissionDenied = { permissionDenied = true }
        WhisperLiveRTCService.shared.onConnectionFailed = { connectionFailed = true }
        await WhisperLiveRTCService.shared.join(
            roomId: room.id,
            userId: userID,
            name: name,
            asListener: !joinAsBroadcaster,
            shouldContinue: { active && !roomEnded && connectOperation == operation && generation == AccountStorage.generation }
        )
        guard ownsRTC, connectOperation == operation, !Task.isCancelled, generation == AccountStorage.generation,
              WhisperLiveRTCService.shared.connected else { return }
        try? await service.joinListener(roomID: room.id, userID: userID)
        guard active, !roomEnded, ownsRTC, connectOperation == operation,
              !Task.isCancelled, generation == AccountStorage.generation else { return }
        if joinAsBroadcaster {
            micOn = true
            cameraOn = true
        }
        withAnimation(.easeOut(duration: 0.4)) {
            connected = true
            connecting = false
        }
    }

    private func disconnect() async {
        connectOperation = nil
        guard ownsRTC else { return }
        ownsRTC = false
        connected = false
        WhisperLiveRTCService.shared.onConnectionFailed = nil
        WhisperLiveRTCService.shared.onParticipantsChanged = nil
        WhisperLiveRTCService.shared.onRemoteVideoTrackForPeer = nil
        WhisperLiveRTCService.shared.onReaction = nil
        WhisperLiveRTCService.shared.onPermissionDenied = nil
        await WhisperLiveRTCService.shared.leave()
        try? await service.leaveListener(roomID: room.id, userID: userID)
    }

    private func endRoom() async {
        await disconnect()
        try? await service.endRoom(id: room.id, scheduledDate: currentRoom.scheduledDate)
        dismiss()
    }

    private func endLocally() {
        guard !roomEnded else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            roomEnded = true
        }
        Task {
            await disconnect()
            try? await Task.sleep(for: .seconds(3))
            dismiss()
        }
    }

    private func sendChat() async {
        let body = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        // Client-side gate for instant, friendly feedback — the live-v3
        // database policies are the real wall behind it.
        if !isHost, let reason = moderation.blockReason(body: body, userID: userID) {
            showModerationNotice(reason)
            return
        }
        chatDraft = ""
        do {
            try await chatService.sendMessage(
                roomID: room.id,
                userID: userID,
                username: username,
                body: body,
                isHost: isHost
            )
            chatMessages = await chatService.fetchMessages(roomID: room.id)
        } catch {
            print("[WhisperLiveRoom] chat send error: \(error)")
            // A database rejection usually means a ban/timeout landed after
            // our last refresh — re-pull so the client gate catches up.
            await moderation.refresh(hostID: room.host_id, roomID: room.id)
            if let reason = moderation.blockReason(body: body, userID: userID) {
                showModerationNotice(reason)
            } else {
                chatDraft = body
            }
        }
    }

    private func showModerationNotice(_ text: String) {
        Haptics.warning()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            moderationNotice = text
        }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeOut(duration: 0.25)) {
                if moderationNotice == text { moderationNotice = nil }
            }
        }
    }

    // MARK: - Mod actions (host + channel mods; RLS enforces server-side)

    private func modDelete(_ msg: WhisperLiveChatMessage) {
        Haptics.tap()
        Task {
            try? await chatService.deleteMessage(messageID: msg.id)
            chatMessages.removeAll { $0.id == msg.id }
        }
    }

    private func modTimeout(_ msg: WhisperLiveChatMessage) {
        Haptics.warning()
        Task {
            let ok = await moderation.timeout(
                roomID: room.id,
                userID: msg.user_id,
                username: msg.username,
                minutes: 5
            )
            if ok { showModerationNotice("@\(msg.username) timed out for 5 minutes.") }
        }
    }

    private func modBan(_ msg: WhisperLiveChatMessage) {
        Haptics.warning()
        Task {
            let ok = await moderation.ban(
                hostID: room.host_id,
                userID: msg.user_id,
                username: msg.username
            )
            if ok { showModerationNotice("@\(msg.username) banned from this channel.") }
        }
    }
}

// MARK: - Stage tile

/// One broadcaster tile in the split-screen stage. Shows live video when the
/// camera (or screen share) is on, otherwise a gradient derived from the
/// user's name with their profile photo centered — like Instagram Live's
/// cam-off state.
private struct LiveStageTile: View {
    let participant: WhisperLiveRTCService.ParticipantInfo
    let isLocal: Bool
    let isHostTile: Bool
    let displayName: String
    let avatarImageURL: URL?
    var trackNonce: Int = 0

    private var hasVideo: Bool {
        if isLocal {
            return WhisperLiveRTCService.shared.cameraOn || WhisperLiveRTCService.shared.isScreenSharing
        }
        return participant.hasVideo
    }

    var body: some View {
        ZStack {
            if hasVideo {
                WhisperLiveVideoView(
                    source: isLocal ? .local : .remote(peerId: participant.peerId),
                    mirror: isLocal && WhisperLiveRTCService.shared.isFrontCamera && !WhisperLiveRTCService.shared.isScreenSharing,
                    fit: isLocal ? WhisperLiveRTCService.shared.isScreenSharing : participant.isScreenSharing,
                    trackNonce: trackNonce
                )
            } else {
                let colors = gradientColors(for: displayName)
                LinearGradient(
                    colors: [Color(hex: colors.0) ?? .gray, Color(hex: colors.1) ?? .gray],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.14))
                            .frame(width: 92, height: 92)
                        WhisperAvatar(username: displayName, size: 80, imageURL: avatarImageURL)
                    }
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 5) {
                if participant.isScreenSharing {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(displayName + (isHostTile ? " · Host" : ""))
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                if !participant.micOn {
                    Image(systemName: "mic.slash.fill")
                        .font(.system(size: 10))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.black.opacity(0.5), in: Capsule())
            .padding(10)
        }
    }

    private func gradientColors(for name: String) -> (String, String) {
        let hash = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let hue1 = (hash * 37) % 360
        let hue2 = (hue1 + 40) % 360
        let (r1, g1, b1) = hslToRgb(h: hue1, s: 0.65, l: 0.50)
        let (r2, g2, b2) = hslToRgb(h: hue2, s: 0.65, l: 0.35)
        return (String(format: "%02X%02X%02X", r1, g1, b1),
                String(format: "%02X%02X%02X", r2, g2, b2))
    }

    private func hslToRgb(h: Int, s: Double, l: Double) -> (Int, Int, Int) {
        let hDouble = Double(h) / 360.0
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((hDouble * 6).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r1, g1, b1): (Double, Double, Double)
        switch hDouble * 6 {
        case 0..<1: (r1, g1, b1) = (c, x, 0)
        case 1..<2: (r1, g1, b1) = (x, c, 0)
        case 2..<3: (r1, g1, b1) = (0, c, x)
        case 3..<4: (r1, g1, b1) = (0, x, c)
        case 4..<5: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        return (Int((r1 + m) * 255), Int((g1 + m) * 255), Int((b1 + m) * 255))
    }
}

// MARK: - Interactive workout card in live chat

/// Tappable interactive training-plan card that renders inline in the live
/// chat overlay. Viewers can tap "Save to Whisper" to persist the workout.
private struct WhisperLiveWorkoutChatCard: View {
    let payload: WhisperWorkoutEmbed.Payload
    @State private var saved: Bool = false
    @State private var showDetail: Bool = false

    private static let emerald: Color = Color(red: 0.06, green: 0.72, blue: 0.51)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow
            if showDetail {
                exerciseList
            }
            statsRow
            saveButton
        }
        .padding(10)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Self.emerald.opacity(0.4), lineWidth: 1))
        .frame(maxWidth: 260)
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                showDetail.toggle()
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Self.emerald, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text(payload.displayName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(payload.focus)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
    }

    private var exerciseList: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(payload.exerciseNames.prefix(6)), id: \.self) { name in
                exerciseRow(name)
            }
            if payload.exerciseNames.count > 6 {
                Text("+\(payload.exerciseNames.count - 6) more")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.top, 2)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func exerciseRow(_ name: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "circle.fill")
                .font(.system(size: 3))
                .foregroundStyle(.white.opacity(0.4))
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 8) {
            Label("\(payload.exerciseNames.count) exercises", systemImage: "list.bullet")
            Spacer(minLength: 0)
            Text("\(payload.totalSets) sets")
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.white.opacity(0.5))
    }

    private var saveButton: some View {
        Button {
            Haptics.tap()
            if !saved {
                let result = WhisperWorkoutImport.saveToWhisper(payload)
                if result != .failed { saved = true }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: saved ? "checkmark.circle.fill" : "plus.circle.fill")
                Text(saved ? "Saved to Whisper" : "Save to Whisper")
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(saved ? .white : Self.emerald)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                saved ? Self.emerald.opacity(0.9) : Self.emerald.opacity(0.18),
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
    }
}
