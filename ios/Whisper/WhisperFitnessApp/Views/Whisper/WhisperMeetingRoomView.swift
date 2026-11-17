import SwiftUI
import Speech
import AVFoundation
import Supabase
import Auth

/// Private video meeting room — reuses the live-room WebRTC engine on the
/// shared `meeting:{id}` signaling channel so iOS and web join the same
/// rooms. Everyone publishes audio + video. Local speech is transcribed with
/// SFSpeechRecognizer; when the host ends the call, AI notes (summary, key
/// points, decisions, action items) are generated for everyone.
struct WhisperMeetingRoomView: View {
    @Environment(\.dismiss) private var dismiss

    let meeting: WhisperMeetingRow

    /// True when hosted inside the floating meeting window — shows the gray
    /// minimize chevron that collapses the call into the draggable tile.
    var supportsMinimize: Bool = false
    /// Close routing for the window manager; falls back to `dismiss()` when
    /// the room is presented as a plain cover.
    var onRequestClose: (() -> Void)? = nil

    @State private var joined: Bool = false
    @State private var joiningRoom: Bool = false
    @State private var roomVisible: Bool = true
    @State private var isLeaving: Bool = false
    @State private var joinOperation: UUID = UUID()
    @State private var micOn: Bool = true
    @State private var cameraOn: Bool = true
    @State private var isSharing: Bool = false
    @State private var ending: Bool = false
    // Lobby device choices — applied the moment the call connects.
    @State private var joinPrefMicOn: Bool = UserDefaults.standard.object(forKey: "whisper_meet_default_mic") as? Bool ?? true
    @State private var joinPrefCamOn: Bool = UserDefaults.standard.object(forKey: "whisper_meet_default_camera") as? Bool ?? true
    @State private var joinedAt: Date?
    @State private var startingScheduled: Bool = false
    /// Reopening an ENDED meeting from its link — Meet's rule that a link is never dead.
    @State private var reopening: Bool = false
    /// Fresher copy of the meeting row (scheduled → live transitions).
    @State private var liveMeeting: WhisperMeetingRow?
    @State private var showRenameMeeting: Bool = false
    @State private var meetingNameDraft: String = ""
    @State private var isRenamingMeeting: Bool = false
    @State private var renameMeetingFailed: Bool = false
    @State private var notes: String?
    @State private var generating: Bool = false
    /// Recap screen state — the transcript surfaces the moment the meeting
    /// ends (like web) while notes generate on top of it.
    @State private var showRecap: Bool = false
    @State private var recapTranscript: String = ""
    @State private var transcriptExpanded: Bool = false
    /// Backgrounds & effects picker (blur / AI backdrops).
    @State private var showEffectsSheet: Bool = false
    /// Effect label on the lobby preview card, refreshed when the sheet closes.
    @State private var lobbyEffectMode: WhisperVideoEffectMode = WhisperVideoEffects.shared.mode
    /// userID (lowercased) → avatar URL for camera-off tile backdrops.
    @State private var tileAvatars: [String: URL] = [:]
    @State private var trackNonce: Int = 0
    @State private var participants: [WhisperLiveRTCService.ParticipantInfo] = []
    @State private var permissionDenied: Bool = false
    // ── Meet's grammar on the same wire as web ──
    /// In-call messages (`call-chat`) — ephemeral, gone when the call ends.
    @State private var roomChat: [MeetRoomChatMessage] = []
    @State private var chatUnread: Int = 0
    @State private var showRoomChat: Bool = false
    /// What the host lets everyone do (`call-policy`); hosts are exempt.
    @State private var roomPolicy = MeetRoomPolicy()
    @State private var showHostControls: Bool = false
    @State private var showPersonalNotebook: Bool = false
    @State private var meetingSidekick: WhisperMeetingSidekickViewModel = WhisperMeetingSidekickViewModel()
    /// People knocking on the room (`meeting-knock`) — only the doorkeeper acts.
    @State private var pendingKnocks: [MeetKnock] = []
    /// Floating emoji reactions (`call-react`) + the strip that sends them.
    @State private var floatingReactions: [MeetFloatingReaction] = []
    @State private var showReactionStrip: Bool = false
    /// userID (lowercased) → name for raised hands (`call-hand`).
    @State private var raisedHands: [String: String] = [:]
    /// The room's acting host once the owner left without ending (`call-host`).
    @State private var actingHostUserID: String? = nil
    /// The owner was seen in the room — an election only REPLACES a host who left.
    @State private var hostSeen: Bool = false
    @State private var hostElectionTask: Task<Void, Never>? = nil
    /// Meet's leave menu — a host with people still in the room chooses.
    @State private var showLeaveMenu: Bool = false
    /// Remote peerIds seen so far — drives the join / leave chimes.
    @State private var seenRemotePeerIDs: Set<String> = []
    @State private var heartRates: [String: Int] = [:]
    @State private var transcriber = WhisperMeetingTranscriber()
    @State private var showInviteSheet: Bool = false
    @State private var showRecruiterTools: Bool = false
    @State private var showCoachTools: Bool = false
    @State private var showTranscript: Bool = true
    @State private var badgeCache: [String: UserBadge] = [:]
    /// Output route for the control-bar menu (speaker / iPhone / Bluetooth).
    @State private var audioRoute: WhisperAudioRoute = .speaker

    // Live application capture — Jasper fills the recruiter's standard
    // application questions from the conversation (mirrors web's appCap).
    @State private var appCaptureOn: Bool = false
    @State private var appCaptureBusy: Bool = false
    @State private var appCaptureSaving: Bool = false
    @State private var appCaptureSavedAt: Date?
    @State private var appCaptureName: String = ""
    @State private var appCaptureQuestions: [WhisperApplicantQuestion] = []
    @State private var appCaptureAnswers: [String: WhisperCapturedApplicationAnswer] = [:]
    @State private var appCaptureTask: Task<Void, Never>?
    @State private var appCaptureChars: Int = 0
    // Jasper chime-in — a proactive thought about a person on the call.
    @State private var emberChime: String?
    /// Keeps the always-on meeting listener alive (auto-restarts if it dies).
    @State private var listenGuardTask: Task<Void, Never>?
    @State private var chimeTask: Task<Void, Never>?
    @State private var lastChimeChars: Int = 0
    @State private var lastChimeAt: Date?

    // Jasper deck walkthrough — synced with web via `deck-tour` app events.
    @State private var deckTour = WhisperDeckTourEngine()
    @State private var tourHidden: Bool = false
    // Jasper's interactive pitch tools (native WPP calculator + brand cards).
    @State private var showWppCalculator: Bool = false
    @State private var showBrandCards: Bool = false
    // Branded notes email through the backend — replaces the bare mailto.
    @State private var showNotesEmail: Bool = false

    // Jasper companion — private in-call assistant with personality modes.
    @State private var emberPanelOpen: Bool = false
    @State private var emberPeekedIn: Bool = false
    @Namespace private var emberNS
    @State private var emberDraft: String = ""
    @State private var emberBusy: Bool = false
    @State private var emberError: Bool = false
    @State private var emberReply: String?
    @State private var emberMode: WhisperEmberCoachMode = WhisperEmberCoachMode.load()
    @State private var emberPitchOffer: Bool = false
    /// Executable actions parsed from the last Jasper answer (open, message,
    /// schedule, plan) — rendered as tappable buttons in the box.
    @State private var emberActions: [WhisperEmberAction] = []
    @State private var emberCapturing: Bool = false
    @State private var emberVoiceBuffer: String = ""
    /// Whether the in-flight ask began as a voice capture — keeps the
    /// Listening row visible (checked) inside the single working rail.
    @State private var emberAskVoiced: Bool = false
    @State private var emberDebounceTask: Task<Void, Never>?
    @State private var lastEmberQuestion: String = ""
    /// Height of the software keyboard overlapping the screen — lifts the
    /// Jasper box so it always sits right above the keyboard, never under it.
    @State private var keyboardLift: CGFloat = 0

    // Present-to-everyone — the phone-shaped client card pinned to the call.
    @State private var presentation: WhisperPresentedClient?
    /// A creator's live analytics card on stage (ring, momentum, top posts) —
    /// same heartbeat/late-joiner mechanics as the client presentation.
    @State private var analyticsCard: WhisperCreatorAnalyticsCard?
    @State private var analyticsExpanded: Bool = false
    @State private var analyticsBeat: Date = .distantPast
    @State private var analyticsHeartbeatTask: Task<Void, Never>?
    /// Whisper Business+ — the live company card (mine or someone's), the
    /// same camelCase wire web meetings speak ("business-card" events).
    @State private var bizCard: WhisperBusinessCardWire?
    @State private var bizContext: WhisperBusinessMeetingKit.Context?
    @State private var bizInterested: [String] = []
    @State private var bizHandRaised: Bool = false
    @State private var bizSeenRevKey: String = ""
    @State private var bizLeadSent: Set<String> = []
    @State private var bizBuilding: Bool = false
    @State private var showCreatorTools: Bool = false
    @State private var presentationExpanded: Bool = false
    @State private var presentHeartbeatTask: Task<Void, Never>?
    @State private var presentWatchTask: Task<Void, Never>?
    @State private var presentBeat: Date = .distantPast
    @State private var vitalsPublishTask: Task<Void, Never>?

    // Jasper's TRUE speech-to-speech line (echo voice) — same as web meetings.
    @State private var emberVoiceLine = WhisperEmberRealtimeVoice()
    @State private var emberVoiceOn: Bool = false
    @State private var emberVoiceStartTask: Task<Void, Never>?
    @State private var emberVoiceOperation: UUID = UUID()
    @State private var captureOwner: String?
    @State private var captureGeneration: UUID?

    // Shared Jasper answers + the recruiter's live prospect read.
    @State private var sharedEmber: WhisperSharedEmberAnswer?
    @State private var sharedEmberTask: Task<Void, Never>?
    @State private var liveEval: WhisperProspectEval?
    @State private var liveEvalCollapsed: Bool = false
    /// Dismissed for THIS meeting — the read disappears from the stage and
    /// only comes back from the ⋯ menu.
    @State private var liveEvalDismissed: Bool = false
    /// Whether the live read card's application-questions checklist is open.
    @State private var evalQuestionsExpanded: Bool = false
    /// listening → evaluating → ready — mirrors the web recruiter tool.
    @State private var evalPhase: LiveEvalPhase = .listening
    @State private var evalUpdatedAt: Date?

    enum LiveEvalPhase { case listening, evaluating, ready }
    @State private var showNotesRetry: Bool = false
    @State private var evalTask: Task<Void, Never>?
    @State private var lastEvalChars: Int = 0
    @State private var finalEvalBusy: Bool = false

    // Jasper's pitch deck — drafted quietly mid-meeting from the transcript,
    // finalized when the notes generate. Recruiter-only, same wire shape as web.
    @State private var pitchDeck: WhisperPitchDeck?
    @State private var deckPopup: Bool = false
    @State private var deckDrafting: Bool = false
    @State private var deckBuilding: Bool = false

    // Voice auto-schedule — a date spoken in the call becomes a one-tap
    // shared-calendar event with every participant tagged. Detection runs on
    // each client's own transcription and is broadcast so the whole room
    // sees (and can agree to) the same prompt.
    @State private var scheduleSuggestion: WhisperChatScheduleDetector.Suggestion?
    @State private var showScheduleSheet: Bool = false
    @State private var handledScheduleBuckets: Set<Int> = []
    @State private var scheduleToast: String?
    /// Tap-to-focus: the participant the user pinned by tapping their tile.
    /// A pinned tile rides the spotlight layout until tapped again.
    @State private var pinnedPeerID: String? = nil

    private var myUserID: String {
        SupabaseService.shared.client.auth.currentUser?.id.uuidString.lowercased() ?? ""
    }
    /// The room's current host — the owner, or whoever holds the room after
    /// the owner left without ending the call (Meet's handoff rule).
    private var hostUserID: String { (actingHostUserID ?? meeting.host_id).lowercased() }
    private var isHost: Bool { hostUserID == myUserID }
    /// The DOORKEEPER answers knocks: the acting host while they're in the
    /// room; when no host is present, the lowest signed-in userId — the same
    /// deterministic rule as web, so a guest is never left waiting at a door
    /// nobody can open.
    private var isDoorkeeper: Bool {
        if isHost { return true }
        let hostPresent = participants.contains { $0.userId.lowercased() == hostUserID }
        if hostPresent { return false }
        let lowest = participants
            .map { $0.userId.lowercased() }
            .filter { !$0.isEmpty && !$0.hasPrefix("guest_") && !$0.hasPrefix("local_") }
            .sorted()
            .first
        return !myUserID.isEmpty && lowest == myUserID
    }
    private var myDisplayName: String {
        LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "guest"
    }
    private var myHandRaised: Bool { raisedHands[myUserID] != nil }
    private var isCoach: Bool { WhisperCoachService.shared.isMeCoach }
    private var isRecruiter: Bool { WhisperRecruiterService.shared.isMeRecruiter }
    /// Verified creators (and mods/admins/owner — the same gate as Creator
    /// Studio) get creator tools inside meetings.
    private var isCreatorRole: Bool {
        let name = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? ""
        guard !name.isEmpty else { return false }
        return UserVerificationService.shared.badge(forUsername: name) != .none
    }

    /// The freshest meeting row we know about.
    private var currentMeeting: WhisperMeetingRow { liveMeeting ?? meeting }
    /// Scheduled meetings stay in the lobby until the host begins them.
    private var isAwaitingStart: Bool { currentMeeting.status == "scheduled" }
    private var scheduledDate: Date? {
        currentMeeting.scheduled_at.flatMap { WhisperBackendService.parseISO($0) }
    }

    /// Real device safe-area insets read from the key window. The call stage
    /// ignores the container safe area (full-bleed video), which zeroes
    /// `geo.safeAreaInsets` — so all floating chrome anchors off these.
    private var screenInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    }

    var body: some View {
        AnyView(roomWithParticipantUpdates)
    }

    // Actual type erasure bounds Release runtime metadata expansion. Opaque
    // helpers alone still expose their nested generic types to SwiftUI.
    // Keep boundaries stable so updates never remount the active room.
    private var roomStage: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let wrap = blindWrap {
                // A blind date ends on the WRAP — decision + Jasper's recap —
                // never the meeting recap.
                WhisperBlindDateWrapView(
                    roomCode: meeting.id.lowercased(),
                    meetingTitle: currentMeeting.title,
                    myUserID: myUserID,
                    myName: presenterDisplayName,
                    myAvatarURL: tileAvatars[myUserID],
                    partnerUserID: wrap.partnerUserID,
                    partnerName: wrap.partnerName,
                    partnerAvatarURL: wrap.partnerAvatarURL,
                    transcript: wrap.transcript,
                    theirCard: wrap.theirCard,
                    revealed: wrap.revealed,
                    partnerLeft: wrap.partnerLeft,
                    elapsedSec: wrap.elapsedSec,
                    onClose: { requestClose() }
                )
                .transition(.opacity)
            } else if notes != nil || generating || showRecap {
                AnyView(recapView)
            } else if joined {
                AnyView(callView)
            } else if isSpeedDateRoom {
                // A blind date never shows the generic meeting lobby.
                AnyView(speedDateLobbyView)
            } else {
                AnyView(lobbyView)
            }

            // Jasper's synced deck walkthrough — covers the call while open.
            if joined, notes == nil, !generating, !showRecap, let tour = deckTour.view, !tourHidden {
                WhisperDeckTourOverlay(
                    tour: tour,
                    isDriver: deckTour.isDriver,
                    narration: deckTour.narration,
                    safeInsets: screenInsets,
                    onClose: {
                        if deckTour.isDriver {
                            deckTour.stopDriving()
                        } else {
                            tourHidden = true
                        }
                    },
                    onPrev: { deckTour.previousSlide() },
                    onNext: { deckTour.nextSlide() },
                    onTogglePlay: { deckTour.togglePlay() }
                )
                .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if joined, !isSpeedDateRoom {
                WhisperRecordingConsentView()
                    .padding(.horizontal, 16)
                    .padding(.top, 62)
            }
        }
    }

    private var roomWithLifecycle: some View {
        AnyView(roomStage)
        .whisperEdgeBack(isEnabled: supportsMinimize && joined && !ending && !showPersonalNotebook && !emberPanelOpen && notes == nil && !generating && !showRecap && (deckTour.view == nil || tourHidden)) { WhisperMeetingWindow.shared.minimize() }
        .onChange(of: WhisperLiveRTCService.shared.micOn) { _, enabled in
            guard joined, !ending else { return }
            micOn = enabled
            if !enabled { transcriber.stop(flush: false) }
            else { if emberVoiceOn { stopEmberVoice() }; startMeetingTranscription() }
        }
        .onChange(of: emberPanelOpen) { _, open in if !open, emberVoiceOn { stopEmberVoice() } }
        .onChange(of: showPersonalNotebook) { _, open in
            if open { closeEmberPanel(); showReactionStrip = false }
            else { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        }
        .onChange(of: showRecruiterTools) { _, open in if open { emberPanelOpen = false; showPersonalNotebook = false } }
        .onChange(of: showCoachTools) { _, open in if open { emberPanelOpen = false; showPersonalNotebook = false } }
        .onChange(of: showCreatorTools) { _, open in if open { emberPanelOpen = false; showPersonalNotebook = false } }
        .onChange(of: hostUserID) { _, host in WhisperRecordingConsentService.shared.reconcile(hostID: host) }
        .animation(.easeInOut(duration: 0.2), value: deckTour.view != nil)
        .preferredColorScheme(.dark)
        .overlay {
            if joiningRoom || startingScheduled {
                WhisperMeetingStartingView(title: "Joining meeting…", detail: "Connecting your audio and video. Your lobby choices stay in effect.")
            }
        }
        .onAppear { roomVisible = true }
        .onDisappear {
            roomVisible = false
            WhisperLobbyCameraSession.shared.stop()
            joinOperation = UUID()
            meetingSidekick.cancel()
            meetingSidekick.notebook.closeEditor()
            UIApplication.shared.isIdleTimerDisabled = false
            if joined {
                // Leave hygiene — take my company card off everyone's screen.
                if let mine = bizCard, mine.presenterUserId.lowercased() == myUserID {
                    WhisperLiveRTCService.shared.sendAppEvent("business-card-end", data: ["presenterUserId": myUserID])
                }
                Task { await leave() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            roomVisible = false; joinOperation = UUID()
            WhisperLobbyCameraSession.shared.stop()
            guard joined else { requestClose(); return }
            transcriber.stop(flush: false)
            emberVoiceOperation = UUID(); emberVoiceStartTask?.cancel(); emberVoiceLine.shutdown()
            WhisperLiveRTCService.shared.suspendMediaForExit()
            Task { await leave(); requestClose() }
        }
    }

    private var roomWithMeetingTasks: some View {
        AnyView(roomWithLifecycle)
        .alert("Rename meeting", isPresented: $showRenameMeeting) {
            TextField("Meeting name", text: $meetingNameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save name") {
                isRenamingMeeting = true
                Task {
                    do { liveMeeting = try await WhisperMeetingService.shared.rename(currentMeeting, title: meetingNameDraft) }
                    catch { renameMeetingFailed = true }
                    isRenamingMeeting = false
                }
            }.disabled(meetingNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || meetingNameDraft.count > 160)
        } message: { Text("Everyone sees the new name. Notes, recordings and the meeting link stay connected.") }
        .alert("Couldn’t rename meeting", isPresented: $renameMeetingFailed) { Button("OK", role: .cancel) {} } message: { Text("Refresh the meeting and try again. Only its original host can change the shared name.") }
        .onReceive(NotificationCenter.default.publisher(for: .whisperCallKitEndedExternally)) { note in
            // The user ended the meeting from the system call UI (lock
            // screen / Dynamic Island) — the room is already left; close
            // the meeting screen to match.
            guard joined, (note.userInfo?["callID"] as? String) == "meeting:\(meeting.id)" else { return }
            Task {
                await leave()
                requestClose()
            }
        }
        .task(id: tileAvatarKey) { await hydrateTileAvatars() }
        .task(id: joined) { await watchForRemoteMeetingEnd() }
        .task {
            // Business+ members (owner or team seat) get the Present-company
            // menu — resolved once per room, quietly.
            bizContext = await WhisperBusinessMeetingKit.myBusinessPlus()
        }
        .task { await loadArchivedRecap() }
        .alert("Camera & microphone needed", isPresented: $permissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not now", role: .cancel) { requestClose() }
        } message: {
            Text("Meetings need camera and microphone access. Allow both in Settings, then rejoin.")
        }
        .alert("Couldn't generate notes", isPresented: $showNotesRetry) {
            Button("Try again") { Task { await produceNotes() } }
            Button("Close", role: .cancel) { requestClose() }
        } message: {
            Text("Your transcript is saved \u{2014} check your connection and try again.")
        }
    }

    private var roomWithCallControls: some View {
        AnyView(roomWithMeetingTasks)
        .overlay(alignment: .bottom) {
            // "Jasper drafted your pitch deck" — mid-call invite, recruiter only.
            if deckPopup, let deck = pitchDeck, notes == nil, !showRecap {
                deckPopupCapsule(deck)
                    .padding(.horizontal, 16)
                    .padding(.bottom, screenInsets.bottom + 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showInviteSheet) {
            WhisperMeetingInviteSheet(meetingID: meeting.id, socialLink: isSpeedDateRoom ? "https://www.mydailywhisper.com/meet/\(meeting.id)?sd=1" : nil)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showRoomChat, onDismiss: { chatUnread = 0 }) {
            WhisperMeetRoomChatSheet(
                messages: roomChat,
                locked: !roomPolicy.chat && !isHost
            ) { text in
                sendRoomChat(text)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showHostControls) {
            WhisperMeetHostControlsSheet(
                policy: $roomPolicy,
                participantCount: participants.count,
                onPolicyChange: { next in
                    WhisperLiveRTCService.shared.sendAppEvent("call-policy", data: [
                        "chat": next.chat,
                        "reactions": next.reactions,
                        "present": next.present,
                        "quickAccess": next.quickAccess
                    ])
                },
                onMuteAll: {
                    WhisperLiveRTCService.shared.sendAppEvent("call-mute-all", data: ["byName": myDisplayName])
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Leave or end the call?", isPresented: $showLeaveMenu, titleVisibility: .visible) {
            Button("Leave the call") {
                Task { await endCall(everyone: false) }
            }
            Button("End the call for everyone", role: .destructive) {
                Task { await endCall(everyone: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let successor = participants.first { $0.peerId != WhisperLiveRTCService.shared.localPeerId }
            Text(
                successor.map { "Leaving hands the room to \($0.name) and the meeting keeps going. Ending removes everyone and Jasper writes the notes." }
                    ?? "Leaving keeps the meeting going. Ending removes everyone and Jasper writes the notes."
            )
        }
    }

    private var roomWithRoleSheets: some View {
        AnyView(roomWithCallControls)
        .sheet(isPresented: $showRecruiterTools) {
            // The sheet only opens from the in-call top bar, so presenting is
            // always available here.
            WhisperMeetingRecruiterToolsSheet(
                liveDeck: pitchDeck,
                onPresent: { prospect in
                    startPresenting(prospect)
                },
                capture: WhisperMeetingRecruiterToolsSheet.ApplicationCapture(
                    isOn: $appCaptureOn,
                    prospectName: $appCaptureName,
                    answers: sortedCapturedAnswers,
                    busy: appCaptureBusy,
                    saving: appCaptureSaving,
                    savedAt: appCaptureSavedAt,
                    onFile: { fileCapturedApplication() }
                )
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCoachTools) {
            WhisperMeetingCoachToolsSheet(onPresent: { request in
                startPresentingClient(request)
            })
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCreatorTools) {
            WhisperMeetingCreatorToolsSheet(
                onShare: { card in startPresentingAnalytics(card) },
                onAsk: { question in Task { await askEmber(question) } }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $analyticsExpanded) {
            if let analyticsCard {
                WhisperCreatorAnalyticsSheet(
                    card: analyticsCard,
                    isMine: analyticsCard.presenterUserId.lowercased() == myUserID,
                    onStop: { stopPresentingAnalytics() }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var roomWithUtilitySheets: some View {
        AnyView(roomWithRoleSheets)
        .sheet(isPresented: $showWppCalculator) {
            WhisperMeetingWppSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showBrandCards) {
            WhisperMeetingBrandsSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showNotesEmail) {
            if let notes {
                WhisperMeetingNotesEmailSheet(meeting: currentMeeting, notes: notes)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showEffectsSheet) {
            WhisperVideoEffectsSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showScheduleSheet) {
            if let suggestion = scheduleSuggestion {
                WhisperChatScheduleSheet(
                    taggedIDs: taggableParticipants.map { $0.id },
                    taggedNames: taggableParticipants.map { $0.name },
                    contextNote: "Planned live in \u{201C}\(currentMeeting.title)\u{201D}",
                    initial: suggestion,
                    onScheduled: { message in
                        withAnimation { scheduleSuggestion = nil }
                        showScheduleToast(message)
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $presentationExpanded) {
            presentedClientSheetContent
        }
    }

    private var roomWithParticipantUpdates: some View {
        AnyView(roomWithUtilitySheets)
        .onChange(of: trackNonce) { _, _ in
            // Presenter-left hygiene — the Business+ card clears when its
            // presenter's tile is gone (web does the same).
            if let card = bizCard, card.presenterUserId.lowercased() != myUserID {
                let ids = Set(participants.map { $0.userId.lowercased() })
                if !ids.isEmpty, !ids.contains(card.presenterUserId.lowercased()) {
                    withAnimation(.spring(duration: 0.35)) { bizCard = nil }
                    bizInterested = []
                    bizHandRaised = false
                }
            }
            // Batch-fetch verification badges for all participant usernames.
            let usernames = participants.map { $0.name }.filter { $0 != "You" && $0 != "Guest" }
            guard !usernames.isEmpty else { return }
            Task {
                var map: [String: UserBadge] = [:]
                for name in usernames {
                    map[name.lowercased()] = UserVerificationService.shared.badge(forUsername: name)
                }
                await MainActor.run { badgeCache = map }
            }
        }
        .onChange(of: appCaptureOn) { _, on in
            if on { startApplicationCapture() } else { stopApplicationCapture() }
        }
        .onChange(of: isRecruiter) { _, isNowRecruiter in
            // The recruiter role loads asynchronously — when it resolves
            // mid-call, start the auto-analyze suite that join missed.
            guard isNowRecruiter, joined else { return }
            if evalTask == nil { startRecruiterIntelligence() }
        }
    }

    /// Keeps the participant recap transition in the task tied to `joined`.
    private func watchForRemoteMeetingEnd() async {
        guard joined, !isHost else { return }
        while !Task.isCancelled && joined && !showRecap {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, joined, !showRecap else { return }
            if let fresh = await WhisperMeetingService.shared.fetch(id: meeting.id) {
                liveMeeting = fresh
                if fresh.isEnded {
                    await handleRemoteEnd()
                    return
                }
            }
        }
    }

    /// Ended meetings open their existing recap instead of the lobby.
    private func loadArchivedRecap() async {
        guard currentMeeting.isEnded, !joined, notes == nil, !showRecap else { return }
        if let summary = currentMeeting.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            notes = summary
        }
        let transcript = await WhisperMeetingService.shared.fetchTranscriptPlain(meetingID: meeting.id)
        recapTranscript = transcript
        showRecap = true
    }

    /// Closes the room through the window manager when hosted there,
    /// otherwise through the SwiftUI presentation.
    private func requestClose() {
        if let onRequestClose {
            onRequestClose()
        } else {
            dismiss()
        }
    }

    /// Content for the expanded presented-client sheet — extracted so the
    /// root body stays simple enough for the type checker.
    @ViewBuilder
    private var presentedClientSheetContent: some View {
        if let presentation {
            WhisperPresentedClientSheet(
                client: presentation,
                isMine: presentation.presenterUserId.lowercased() == myUserID,
                onStop: { stopPresenting() },
                onSwitch: {
                    presentationExpanded = false
                    showRecruiterTools = true
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Blind-date lobby (the rose pre-join — never the generic lobby)

    /// Rooms known to be blind dates BEFORE joining: primed by the Dating
    /// hub's lobby or the finder (`pendingRooms`), or opened from an ?sd=1
    /// invite link (`knownRooms`).
    private var isSpeedDateRoom: Bool {
        let roomID = meeting.id.lowercased()
        return speedDateActive
            || WhisperSpeedDating.pendingRooms.contains(roomID)
            || WhisperSpeedDating.knownRooms.contains(roomID)
    }

    private var speedDateLobbyView: some View {
        let inset = screenInsets
        let rose = Color(red: 0.91, green: 0.28, blue: 0.49)
        let roomID = meeting.id.lowercased()
        let hasCard = WhisperSpeedDating.hasCard
        let paired = WhisperBlindDate.pairedPartners[roomID]
        let title: String = {
            if let paired { return "It's a date with\n@\(paired) \u{1F498}" }
            return isHost ? "Your blind date\nis set up \u{1F498}" : "You've been invited\nto a blind date \u{1F498}"
        }()
        let inviteURL = URL(string: "https://mydailywhisper.com/meet/\(meeting.id)?sd=1")
            ?? URL(string: "https://mydailywhisper.com")!
        return ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.03, blue: 0.09),
                    Color(red: 0.30, green: 0.06, blue: 0.15),
                    Color(red: 0.14, green: 0.03, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack {
                        Button {
                            Haptics.tap()
                            requestClose()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(Color.white.opacity(0.12), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back to Dating")
                        Spacer()
                        ShareLink(item: inviteURL) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Share invite")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.12), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 18)

                    WhisperEmberMascot(size: 92, expression: .delighted, palette: .cupidPink, smitten: true)
                        .padding(.top, 22)
                    Text("BLIND DATE")
                        .font(.system(size: 11, weight: .black))
                        .tracking(2.4)
                        .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.75))
                        .padding(.top, 14)
                    Text(title)
                        .font(.system(size: 27, weight: .black))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.top, 4)
                        .padding(.horizontal, 24)
                    Text("Five minutes, face to face. You'll hear each other first — cameras stay behind the curtain until you both reveal (or at the two-minute mark). Jasper hosts with prompts built from both your cards.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 34)
                        .padding(.top, 8)

                    HStack(spacing: 8) {
                        speedDateLobbyTile(glyph: "\u{1F3A7}", title: "Voices first", sub: "Cameras stay hidden")
                        speedDateLobbyTile(glyph: "\u{23F1}", title: "5 minutes", sub: "One shared clock")
                        speedDateLobbyTile(glyph: "\u{1F498}", title: "Reveal together", sub: "Or at 2:00")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hasCard ? "\u{2713} Your dating card is ready" : "No dating card yet")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text("Jasper builds the prompts from both cards.")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Button {
                            Haptics.tap()
                            showRoomDatingCardEditor = true
                        } label: {
                            Text(hasCard ? "Edit card" : "Fill my card")
                                .font(.system(size: 12.5, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(.white.opacity(0.14)))
                                .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.10)))
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    // Pre-join device choices — the camera only matters at the reveal.
                    HStack(spacing: 26) {
                        lobbyDeviceToggle(
                            isOn: $joinPrefMicOn,
                            onIcon: "mic.fill",
                            offIcon: "mic.slash.fill",
                            label: "Mic"
                        )
                        lobbyDeviceToggle(
                            isOn: $joinPrefCamOn,
                            onIcon: "video.fill",
                            offIcon: "video.slash.fill",
                            label: "Camera for reveal"
                        )
                    }
                    .padding(.top, 18)

                    Button {
                        Haptics.tap()
                        // Entering IS saying "I'm ready" — the room skips the
                        // welcome takeover and opens straight on the curtain.
                        WhisperSpeedDating.pendingRooms.insert(roomID)
                        WhisperBlindDate.readyRooms.insert(roomID)
                        Task { await join() }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text("Enter the date \u{1F498}")
                                .font(.system(size: 16, weight: .black))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            Capsule().fill(
                                LinearGradient(
                                    colors: [rose, Color(red: 0.98, green: 0.45, blue: 0.62)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        )
                        .shadow(color: rose.opacity(0.4), radius: 14, y: 6)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 28)
                    .padding(.top, 20)

                    Text("Your side of the conversation is transcribed so Jasper can write the recap. Only the two of you ever see it.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 44)
                        .padding(.top, 12)
                        .padding(.bottom, inset.bottom + 16)
                }
                .padding(.top, inset.top + 8)
            }
        }
        .sheet(isPresented: $showRoomDatingCardEditor) {
            WhisperDatingCardEditorSheet()
        }
    }

    private func speedDateLobbyTile(glyph: String, title: String, sub: String) -> some View {
        VStack(spacing: 4) {
            Text(glyph)
                .font(.system(size: 18))
            Text(title)
                .font(.system(size: 11.5, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(sub)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08)))
    }

    // MARK: - Lobby

    // The historical TestFlight stack overflow occurred while resolving
    // lobbyView's deeply nested generic metadata. Bound the outer type and its largest sections
    // independently, rather than only erasing after evaluating the whole lobby.
    private var lobbyView: AnyView {
        let inset = screenInsets
        let username = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"
        return AnyView(VStack(spacing: 0) {
            AnyView(HStack {
                Button {
                    Haptics.tap()
                    requestClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                Spacer()
                ShareLink(item: URL(string: isSpeedDateRoom ? "https://www.mydailywhisper.com/meet/\(meeting.id)?sd=1" : WhisperMeetingService.link(for: meeting.id)) ?? URL(string: "https://mydailywhisper.com")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Share link")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.12), in: Capsule())
                }
            }
            .padding(.horizontal, 18))

            AnyView(VStack(spacing: 5) {
                Text(currentMeeting.isEnded ? "This meeting has ended" : "Ready when you are")
                    .font(.system(size: 11, weight: .black))
                    .textCase(.uppercase)
                    .tracking(2.2)
                    .foregroundStyle(.white.opacity(0.45))
                Text(currentMeeting.title)
                    .font(.title.weight(.black))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 28)
                Text("Hosted by @\(currentMeeting.host_username)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
                if isAwaitingStart, let scheduledDate {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(Self.scheduleFormatter.string(from: scheduledDate))
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(Color(red: 0.53, green: 0.72, blue: 1.0))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.23, green: 0.51, blue: 0.96).opacity(0.16), in: Capsule())
                    .padding(.top, 3)
                }
            }
            .padding(.top, 14))

            AnyView(lobbyPreviewCard(username: username))
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .frame(maxHeight: .infinity)

            Text("Tap the wand to blur your background or have Jasper paint you a new one.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
                .padding(.top, 12)

            // Pre-join device choices — walk in muted or camera-off.
            AnyView(HStack(spacing: 26) {
                lobbyDeviceToggle(
                    isOn: $joinPrefMicOn,
                    onIcon: "mic.fill",
                    offIcon: "mic.slash.fill",
                    label: "Mic"
                )
                lobbyDeviceToggle(
                    isOn: $joinPrefCamOn,
                    onIcon: "video.fill",
                    offIcon: "video.slash.fill",
                    label: "Camera"
                )
            }
            .padding(.top, 16))

            lobbyPrimaryAction
                .padding(.top, 16)

            Text("Your speech is transcribed during the call so AI notes can be generated when the meeting ends.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
                .padding(.top, 12)
                .padding(.bottom, inset.bottom + 12)
        }
        .padding(.top, inset.top + 8)
        .task(id: currentMeeting.status) {
            // Guests wait for the host — poll until the meeting flips live.
            guard isAwaitingStart, !isHost else { return }
            while !Task.isCancelled && !joined {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                if let fresh = await WhisperMeetingService.shared.fetch(id: meeting.id) {
                    liveMeeting = fresh
                    if fresh.isLive { return }
                }
            }
        }
        .task(id: joinPrefCamOn) {
            lobbyEffectMode = WhisperVideoEffects.shared.mode
            if joinPrefCamOn && !joined {
                WhisperLobbyCameraSession.shared.start()
            } else {
                WhisperLobbyCameraSession.shared.stop()
            }
        }
        .onChange(of: showEffectsSheet) { _, open in
            if !open { lobbyEffectMode = WhisperVideoEffects.shared.mode }
        }
        .onDisappear {
            WhisperLobbyCameraSession.shared.stop()
        })
    }

    /// The lobby's live self-view card — camera preview with the active
    /// effect applied, plus the effect chip and the wand that opens the
    /// Backgrounds & effects sheet.
    @ViewBuilder
    private func lobbyPreviewCard(username: String) -> some View {
        let session = WhisperLobbyCameraSession.shared
        ZStack {
            if joinPrefCamOn {
                switch session.status {
                case .running, .starting:
                    WhisperLobbyCameraPreview(session: session)
                case .denied:
                    lobbyPreviewPlaceholder(
                        icon: "video.slash.fill",
                        title: "Camera access needed",
                        detail: "Allow camera access in Settings to preview and share video."
                    ) {
                        Button {
                            Haptics.tap()
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Open Settings")
                                .font(.caption.weight(.black))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.white, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                case .unavailable:
                    lobbyPreviewPlaceholder(
                        icon: "web.camera",
                        title: "No camera found",
                        detail: "You can still join — others will see your avatar."
                    ) { EmptyView() }
                case .idle:
                    Color(white: 0.07)
                }
            } else {
                lobbyPreviewPlaceholder(
                    icon: "video.slash.fill",
                    title: "Camera off",
                    detail: "You'll join without video — flip it back on anytime."
                ) { EmptyView() }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 210)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        }
        .overlay(alignment: .top) {
            Text("@\(username)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.55), in: Capsule())
                .padding(.top, 12)
        }
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 5) {
                Image(systemName: lobbyEffectMode == .off
                      ? "person.fill"
                      : (lobbyEffectMode == .blur ? "person.and.background.dotted" : "photo.fill"))
                    .font(.system(size: 10, weight: .bold))
                Text(lobbyEffectLabel)
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.55), in: Capsule())
            .padding(12)
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                Haptics.tap()
                showEffectsSheet = true
            } label: {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .padding(10)
            .accessibilityLabel("Backgrounds & effects")
        }
    }

    private var lobbyEffectLabel: String {
        switch lobbyEffectMode {
        case .off: return "NO EFFECT"
        case .blur: return "BLUR"
        case .backdrop: return "BACKDROP"
        }
    }

    @ViewBuilder
    private func lobbyPreviewPlaceholder<Action: View>(
        icon: String,
        title: String,
        detail: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        ZStack {
            Color(white: 0.07)
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                action()
            }
        }
    }

    private static let scheduleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d \u{00B7} h:mm a"
        return f
    }()

    @ViewBuilder
    private var lobbyPrimaryAction: some View {
        if currentMeeting.isEnded {
            // The link is still good — start the same room again so everyone
            // holding it can come back in (mirrors web's "Start it again").
            Button {
                Haptics.tap()
                Task { await startAgain() }
            } label: {
                HStack(spacing: 8) {
                    if reopening {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    Text("Start it again")
                }
                .font(.headline.weight(.black))
                .foregroundStyle(.black)
                .padding(.horizontal, 34)
                .padding(.vertical, 16)
                .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(reopening)
        } else if isAwaitingStart && isHost {
            Button {
                Haptics.tap()
                Task { await startScheduledAndJoin() }
            } label: {
                HStack(spacing: 8) {
                    if startingScheduled {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text("Start meeting")
                }
                .font(.headline.weight(.black))
                .foregroundStyle(.black)
                .padding(.horizontal, 34)
                .padding(.vertical, 16)
                .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(startingScheduled)
        } else if isAwaitingStart {
            HStack(spacing: 8) {
                ProgressView().tint(.white.opacity(0.6))
                Text("Waiting for the host to start\u{2026}")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 15)
            .background(Color.white.opacity(0.08), in: Capsule())
        } else {
            Button {
                Haptics.tap()
                Task { await join() }
            } label: {
                Label("Join meeting", systemImage: "video.fill")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 34)
                    .padding(.vertical, 16)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func lobbyDeviceToggle(
        isOn: Binding<Bool>,
        onIcon: String,
        offIcon: String,
        label: String
    ) -> some View {
        Button {
            Haptics.tap()
            isOn.wrappedValue.toggle()
        } label: {
            VStack(spacing: 7) {
                Image(systemName: isOn.wrappedValue ? onIcon : offIcon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isOn.wrappedValue ? .black : .white)
                    .frame(width: 58, height: 58)
                    .background(
                        isOn.wrappedValue ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.red.opacity(0.85)),
                        in: Circle()
                    )
                    .contentTransition(.symbolEffect(.replace))
                Text(isOn.wrappedValue ? "\(label) on" : "\(label) off")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) \(isOn.wrappedValue ? "on" : "off") when joining")
    }

    /// Host taps Start on a scheduled meeting — flip it live, then join.
    /// Flip an ended meeting back to live (RPC for any member, host-direct
    /// fallback) and refresh the lobby so Join is offered again.
    private func startAgain() async {
        guard !reopening else { return }
        reopening = true
        defer { reopening = false }
        if let fresh = await WhisperMeetingService.shared.reopen(meetingID: meeting.id) {
            liveMeeting = fresh
            showRecap = false
            Haptics.soft()
            showScheduleToast("The meeting is open again — everyone with the link can join.")
        } else {
            showScheduleToast("Only the host can start this meeting again right now — ask them to open the link.")
        }
    }

    private func startScheduledAndJoin() async {
        guard roomVisible, !startingScheduled, !joiningRoom, !joined, !isLeaving else { return }
        let generation = AccountStorage.generation
        let operation = joinOperation
        startingScheduled = true
        defer { startingScheduled = false }
        await WhisperMeetingService.shared.start(meetingID: meeting.id)
        guard roomVisible, generation == AccountStorage.generation, operation == joinOperation, !Task.isCancelled else { return }
        let fresh = await WhisperMeetingService.shared.fetch(id: meeting.id)
        guard roomVisible, generation == AccountStorage.generation, operation == joinOperation, !Task.isCancelled else { return }
        if let fresh { liveMeeting = fresh }
        guard currentMeeting.isLive else {
            showScheduleToast("The meeting couldn’t start. Check your connection and try again.")
            return
        }
        await join()
    }

    // MARK: - In call

    private var callView: some View {
        GeometryReader { geometry in
            VStack(spacing: showPersonalNotebook ? 10 : 0) {
                if showPersonalNotebook {
                    floatingTopBar(compact: geometry.size.width < 400)
                        .padding(.horizontal, 12).padding(.top, screenInsets.top + 6)
                }
                WhisperMeetingDrawerLayout(isOpen: showPersonalNotebook) {
                    AnyView(callStage)
                } drawer: {
                    WhisperMeetingSidekickView(model: meetingSidekick, meetingID: meeting.id, title: currentMeeting.title,
                        captureStatus: !micOn ? "Your microphone is muted" : transcriber.state.label,
                        interim: micOn ? transcriber.liveCaption : "",
                        onRetryCapture: { guard micOn, !emberVoiceOn else { return }; transcriber.stop(); startMeetingTranscription() },
                        isVisible: showPersonalNotebook, onHide: { showPersonalNotebook = false })
                        .tint(.primary)
                }
                .padding(.horizontal, showPersonalNotebook ? 10 : 0)
                if showPersonalNotebook {
                    controls(width: geometry.size.width)
                        .padding(.bottom, max(12, geometry.safeAreaInsets.bottom))
                }
            }
        }
        .background(.black)
        .ignoresSafeArea(.container)
    }

    private var callStage: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            let localId = WhisperLiveRTCService.shared.localPeerId
            let others = participants.filter { $0.peerId != localId }
            let selfParticipant = participants.first { $0.peerId == localId }
            let sharer = others.first { $0.isScreenSharing }
            let pinned = others.first { $0.peerId == pinnedPeerID }
            let activeSpeaker = others.first { $0.isSpeaking }
            let focusedParticipant = sharer ?? pinned ?? activeSpeaker ?? others.first
            let pip = pipSize(for: geo)
            // The stage ignores the container safe area, which zeroes
            // `geo.safeAreaInsets` — chrome anchors off the real window
            // insets instead: top bar just under the status bar, controls
            // floating a touch above the home indicator like FaceTime.
            let inset = screenInsets
            let controlsBottom = inset.bottom + 14

            ZStack {
                Color.black.ignoresSafeArea()

                mainStage(
                    geo: geo,
                    others: others,
                    // A pinned participant rides the spotlight layout —
                    // tap a tile to zoom them, tap again to release.
                    sharer: sharer ?? pinned,
                    selfParticipant: selfParticipant,
                    focusedPeerID: focusedParticipant?.peerId,
                    isLandscape: isLandscape
                )

                // Blind date — the curtain over the video until the reveal,
                // a slim HUD after; chrome (top bar, self-view, controls)
                // stays above it.
                if speedDateActive {
                    blindDateStage(inset: inset, controlsBottom: controlsBottom)
                        .transition(.opacity)
                }

                if !showPersonalNotebook { floatingTopBar(compact: geo.size.width < 400)
                    .padding(.top, inset.top + 6)
                    .padding(.horizontal, geo.size.width < 400 ? 12 : 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) }

                // The stacked portrait cards carry their own name labels —
                // the floating pill only backs up the full-bleed hero stage.
                if let spotlight = focusedParticipant, isLandscape, sharer == nil, others.count == 1, !showPersonalNotebook {
                    namePill(spotlight)
                        .padding(.leading, 18)
                        .padding(.bottom, controlsBottom + 72)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }

                if let selfParticipant, !others.isEmpty, !showPersonalNotebook {
                    pipView(selfParticipant, size: pip)
                        .padding(.trailing, 18)
                        .padding(.bottom, controlsBottom + 72)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 4)
                }

                if !showPersonalNotebook { controls(width: geo.size.width)
                    .padding(.bottom, controlsBottom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom) }

                // Meet's reaction strip — floats above the controls while open.
                if showReactionStrip {
                    WhisperMeetReactionStrip { emoji in
                        sendReaction(emoji)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showReactionStrip = false }
                    }
                    .padding(.bottom, controlsBottom + 78)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
                }

                // Emojis drifting up the stage with the sender's name.
                WhisperMeetFloatingReactionsLayer(items: floatingReactions) { id in
                    floatingReactions.removeAll { $0.id == id }
                }

                // "name raised a hand" — under the top bar.
                if !raisedHands.isEmpty {
                    WhisperMeetRaisedHandsChip(names: Array(raisedHands.values).sorted())
                        .padding(.top, inset.top + 56)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .allowsHitTesting(false)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Someone's at the door — Meet's "wants to join this call" for
                // the doorkeeper (same wire + answers as web).
                if isDoorkeeper && !pendingKnocks.isEmpty {
                    WhisperMeetKnockBanner(
                        knocks: pendingKnocks,
                        onAdmit: { answerKnock($0, admit: true) },
                        onDeny: { answerKnock($0, admit: false) },
                        onAdmitAll: admitAllKnocks
                    )
                    .padding(.top, inset.top + (raisedHands.isEmpty ? 56 : 100))
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if showTranscript && !showPersonalNotebook {
                    // Captions live top-center, under the top bar — the bottom
                    // band belongs to Jasper, the name pill and the self-view.
                    transcriptIndicator
                        .padding(.top, inset.top + 60)
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }

                // Speed-date primer — activates rooms started from the
                // Dating hub; tears the card heartbeat + clock down on exit.
                Color.clear
                    .frame(width: 1, height: 1)
                    .onAppear { primeSpeedDateIfPending() }
                    .onDisappear {
                        datingHeartbeatTask?.cancel()
                        blindClockTask?.cancel()
                        blindClockTask = nil
                    }

                if presentation != nil || analyticsCard != nil || bizCard != nil {
                    VStack(alignment: .trailing, spacing: 10) {
                        if let presentation {
                            WhisperMiniClientPhoneCard(
                                client: presentation,
                                isMine: presentation.presenterUserId.lowercased() == myUserID,
                                onExpand: {
                                    Haptics.tap()
                                    presentationExpanded = true
                                },
                                onStop: { stopPresenting() }
                            )
                        }
                        if let analyticsCard {
                            WhisperCreatorAnalyticsMiniCard(
                                card: analyticsCard,
                                isMine: analyticsCard.presenterUserId.lowercased() == myUserID,
                                onExpand: {
                                    Haptics.tap()
                                    analyticsExpanded = true
                                },
                                onStop: { stopPresentingAnalytics() }
                            )
                        }
                        businessCardRail
                    }
                    .padding(.top, inset.top + 64)
                    .padding(.trailing, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }

                if speedDateWelcomeVisible {
                    speedDateWelcomeOverlay
                        .transition(.opacity)
                        .zIndex(80)
                }

                // The live read never rides a blind date, and it stays gone
                // once dismissed for the meeting (⋯ menu brings it back).
                if isRecruiter && !speedDateActive && !liveEvalDismissed {
                    Group {
                        if let liveEval {
                            liveEvalOverlay(liveEval)
                        } else {
                            liveEvalListeningPill
                        }
                    }
                    .padding(.top, inset.top + 64)
                    .padding(.leading, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }

                if let sharedEmber {
                    sharedEmberCard(sharedEmber)
                        .padding(.horizontal, 24)
                        .padding(.bottom, controlsBottom + 180)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }

                if let scheduleSuggestion, !showScheduleSheet {
                    WhisperChatSchedulePrompt(
                        suggestion: scheduleSuggestion,
                        onAdd: { showScheduleSheet = true },
                        onDismiss: {
                            withAnimation(.easeOut(duration: 0.2)) { self.scheduleSuggestion = nil }
                        }
                    )
                    .padding(.horizontal, 8)
                    .padding(.bottom, controlsBottom + 176)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }

                if let scheduleToast {
                    Text(scheduleToast)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.78), in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
                        }
                        .padding(.bottom, controlsBottom + 244)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if deckTour.view != nil, tourHidden {
                    Button {
                        Haptics.tap()
                        tourHidden = false
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 11, weight: .bold))
                                .symbolEffect(.pulse)
                            Text("Jasper is presenting — tap to reopen")
                                .font(.footnote.weight(.bold))
                        }
                        .foregroundStyle(Color(red: 0.99, green: 0.73, blue: 0.45))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.black.opacity(0.8), in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(Color.orange.opacity(0.4), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, controlsBottom + 158)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }

                WhisperMeetingJasperLauncher(size: geo.size,
                    insets: EdgeInsets(top: inset.top, leading: inset.left, bottom: inset.bottom, trailing: inset.right),
                    bottomClearance: max(controlsBottom + 82, keyboardLift > 0 ? keyboardLift + 12 : 0),
                    isVisible: AuthenticationService.shared.isSignedIn && !showPersonalNotebook && !emberPanelOpen && !showReactionStrip,
                    mode: emberMode, onOpen: {
                        showPersonalNotebook = false
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { emberPanelOpen = true }
                    })

                // Jasper — the living mascot peeking from behind a glass pill
                // docked above the action bar (the classic auto-analysis
                // look). Tapping floats it upward into the assistant box,
                // with the pill becoming the box header.
                if emberPanelOpen {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture { closeEmberPanel() }
                        .transition(.opacity)
                }

                ZStack(alignment: .bottom) {
                    if emberPanelOpen {
                        emberBox
                    }
                }
                .padding(.bottom, keyboardLift > 0 ? keyboardLift + 10 : controlsBottom + 76)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .ignoresSafeArea(.container)
        .ignoresSafeArea(.keyboard)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let overlap = max(0, UIScreen.main.bounds.height - end.origin.y)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { keyboardLift = overlap }
        }
        .onReceive(NotificationCenter.default.publisher(for: .whisperEmberModeChanged)) { _ in
            emberMode = WhisperEmberCoachMode.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { keyboardLift = 0 }
        }
        .onChange(of: emberVoiceLine.phase) { _, phase in
            // A dropped voice line mid-call: surface the reason, fall back
            // to text mode, and rearm the meeting transcriber so captions
            // and pill listening keep working.
            guard emberVoiceOn, phase == .unavailable else { return }
            emberReply = emberVoiceLine.statusMessage ?? "Jasper's live voice dropped — tap the mic to reconnect."
            stopEmberVoice()
        }
        .emberActionModals()
    }

    @ViewBuilder
    private func mainStage(
        geo: GeometryProxy,
        others: [WhisperLiveRTCService.ParticipantInfo],
        sharer: WhisperLiveRTCService.ParticipantInfo?,
        selfParticipant: WhisperLiveRTCService.ParticipantInfo?,
        focusedPeerID: String?,
        isLandscape: Bool
    ) -> some View {
        if showPersonalNotebook {
            let compactParticipants = (others + (selfParticipant.map { [$0] } ?? [])).sorted { lhs, rhs in
                if lhs.peerId == sharer?.peerId { return rhs.peerId != sharer?.peerId }
                if rhs.peerId == sharer?.peerId { return false }
                return lhs.peerId < rhs.peerId
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(compactParticipants, id: \.peerId) { participant in
                        participantTile(participant, style: .spotlight, isFocused: participant.peerId == focusedPeerID)
                            .frame(width: compactParticipants.count > 1 ? max(100, geo.size.width * 0.7) : geo.size.width, height: geo.size.height)
                    }
                }
            }.scrollIndicators(.hidden).id(sharer?.peerId ?? "participants")
        } else if others.isEmpty {
            if let selfParticipant {
                ZStack {
                    participantTile(selfParticipant, style: .hero)
                        .ignoresSafeArea()
                    VStack {
                        Text("Waiting for others to join\u{2026}")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.42), in: Capsule())
                            .padding(.top, screenInsets.top + 112)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }
            }
        } else if let sharer {
            let top = screenInsets.top + 58
            let bottom = screenInsets.bottom + 146
            let available = max(1, geo.size.height - top - bottom)
            let stripHeight: CGFloat = others.count > 1 ? min(120, available * 0.28) : 0
            VStack(spacing: 0) {
                participantTile(sharer, style: .spotlight, isFocused: true)
                    .frame(width: max(1, geo.size.width - 24), height: max(1, available - stripHeight))
                    .padding(.horizontal, 12)
                if others.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(others.filter { $0.peerId != sharer.peerId }, id: \.peerId) { p in
                                participantTile(p, style: .thumb, isFocused: p.peerId == focusedPeerID)
                                    .frame(width: max(60, (stripHeight - 20) * 0.75), height: max(1, stripHeight - 20))
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    .contentMargins(.horizontal, 16)
                    .frame(height: stripHeight)
                }
            }
            .frame(width: geo.size.width, height: available)
            .padding(.top, top)
            .padding(.bottom, bottom)
        } else if isLandscape && others.count == 1 {
            participantTile(others[0], style: .hero, isFocused: others[0].peerId == focusedPeerID)
                .ignoresSafeArea()
        } else if !isLandscape && others.count <= 2 {
            // Google Meet-style portrait stage: full-width rounded cards
            // stacked between the top bar and the control row.
            VStack(spacing: 10) {
                ForEach(others, id: \.peerId) { p in
                    participantTile(p, style: .stack, isFocused: p.peerId == focusedPeerID)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, screenInsets.top + 56)
            .padding(.bottom, screenInsets.bottom + 84)
        } else {
            let columns = gridColumns(count: others.count, isLandscape: isLandscape)
            ScrollView(showsIndicators: false) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns),
                    spacing: 10
                ) {
                    ForEach(others, id: \.peerId) { p in
                        participantTile(p, style: .grid, isFocused: p.peerId == focusedPeerID)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .padding(.top, 70)
                .padding(.bottom, 138)
            }
            .padding(.top, screenInsets.top)
            .padding(.bottom, screenInsets.bottom)
        }
    }

    private enum TileStyle: Equatable {
        case hero       // fills the entire stage
        case stack      // full-width rounded card in the portrait stack
        case spotlight  // large top tile (screen share / active speaker)
        case thumb      // small horizontal strip tile
        case grid       // flexible grid tile
        case pip        // small floating self-view
    }

    @ViewBuilder
    private func participantTile(
        _ p: WhisperLiveRTCService.ParticipantInfo,
        style: TileStyle,
        isFocused: Bool = false
    ) -> some View {
        let base = tileContent(p, style: style, isFocused: isFocused)
        let sized = Group {
            if let ratio = tileAspectRatio(style) {
                base.aspectRatio(ratio, contentMode: .fit)
            } else {
                base
            }
        }
        if style == .pip {
            sized
        } else {
            // Tap a tile to FOCUS that person (spotlight zoom); tap again
            // to release. Self tiles and the floating PiP are exempt.
            sized
                .contentShape(Rectangle())
                .onTapGesture {
                    guard p.peerId != WhisperLiveRTCService.shared.localPeerId else { return }
                    Haptics.tap()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        pinnedPeerID = (pinnedPeerID == p.peerId) ? nil : p.peerId
                    }
                }
        }
    }

    private func tileAspectRatio(_ style: TileStyle) -> CGFloat? {
        switch style {
        case .hero: return nil
        case .stack: return nil
        case .spotlight: return nil
        case .thumb: return 3.0 / 4.0
        case .grid: return 1.0
        case .pip: return 3.0 / 4.0
        }
    }

    private func tileContent(
        _ p: WhisperLiveRTCService.ParticipantInfo,
        style: TileStyle,
        isFocused: Bool
    ) -> some View {
        let isSelf = p.peerId == WhisperLiveRTCService.shared.localPeerId
        let isPIP = style == .pip
        let isHero = style == .hero
        let cornerRadius: CGFloat = isPIP ? 16 : (isHero ? 0 : 18)
        let avatarSize: CGFloat = isHero ? 150 : (style == .stack ? 110 : (isPIP ? 56 : 84))

        return ZStack {
            WhisperParticipantTileMedia(participant: p, isSelf: isSelf,
                avatarURL: tileAvatars[p.userId.lowercased()], avatarSize: avatarSize,
                trackNonce: trackNonce, fit: style == .spotlight)

            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Spacer()
                    if p.isScreenSharing {
                        statusChip(icon: "rectangle.on.rectangle", color: .green)
                    }
                    if p.isSpeaking {
                        statusChip(icon: "waveform", color: .cyan)
                    }
                    if !p.micOn {
                        statusChip(icon: "mic.slash.fill", color: .red)
                    }
                    if isCoach, let bpm = heartRates[p.userId.lowercased()] {
                        heartRateChip(bpm: bpm)
                    }
                }
                .padding(8)
                Spacer()
            }

            if isPIP {
                // Meet-style effects button pinned to the self-view — camera
                // flip lives in the top bar now.
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            Haptics.tap()
                            showEffectsSheet = true
                        } label: {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(7)
                                .background(Color.black.opacity(0.55), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        .accessibilityLabel("Backgrounds and effects")
                    }
                }
            }

            if !isHero && !isPIP {
                VStack {
                    Spacer()
                    HStack {
                        participantLabel(p)
                            .padding(8)
                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if isFocused {
                focusRing(cornerRadius: cornerRadius, isHero: isHero)
            }
        }
    }

    /// Active-speaker ring. Small tiles trace their own rounded corners; the
    /// full-screen hero tile gets a concentric ring that hugs the display's
    /// rounded corners instead of drawing square corners across them.
    @ViewBuilder
    private func focusRing(cornerRadius: CGFloat, isHero: Bool) -> some View {
        let focusBlue = Color(red: 0.53, green: 0.72, blue: 1.0)
        if isHero {
            Group {
                if #available(iOS 26.0, *) {
                    ConcentricRectangle()
                        .stroke(focusBlue, lineWidth: 3)
                } else {
                    RoundedRectangle(cornerRadius: 50, style: .continuous)
                        .strokeBorder(focusBlue, lineWidth: 3)
                }
            }
            .padding(5)
            .shadow(color: focusBlue.opacity(0.35), radius: 10)
            .allowsHitTesting(false)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(focusBlue, lineWidth: 3)
                .shadow(color: focusBlue.opacity(0.35), radius: 8)
                .allowsHitTesting(false)
        }
    }

    private func avatarPlaceholder(name: String, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(avatarGradient(for: name))
                .frame(width: size, height: size)
            Text(initials(for: name))
                .font(.system(size: size * 0.36, weight: .black))
                .foregroundStyle(.white)
            Image(systemName: "flame.fill")
                .font(.system(size: max(10, size * 0.12), weight: .semibold))
                .foregroundStyle(.white)
                .offset(y: size * 0.5 - 12)
        }
    }

    private func participantLabel(_ p: WhisperLiveRTCService.ParticipantInfo) -> some View {
        HStack(spacing: 5) {
            if p.isScreenSharing {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 9))
                    .foregroundStyle(.green)
            }
            if !p.micOn {
                Image(systemName: "mic.slash.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
            }
            Text(p.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            if let badge = badgeCache[p.name.lowercased()], badge != .none {
                VerifiedBadge(badge: badge, size: 10, username: p.name)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.55), in: Capsule())
    }

    private func statusChip(icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(7)
            .background(Color.black.opacity(0.55), in: Circle())
    }

    private func heartRateChip(bpm: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "heart.fill")
                .font(.system(size: 9))
                .foregroundStyle(.red)
            Text("\(bpm)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
            Text("bpm")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.55), in: Capsule())
    }

    private func namePill(_ p: WhisperLiveRTCService.ParticipantInfo) -> some View {
        HStack(spacing: 6) {
            if p.isScreenSharing {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
            }
            if !p.micOn {
                Image(systemName: "mic.slash.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            } else if p.isSpeaking {
                Image(systemName: "waveform")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.cyan)
            }
            Text(p.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            if let badge = badgeCache[p.name.lowercased()], badge != .none {
                VerifiedBadge(badge: badge, size: 12, username: p.name)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.14), in: Capsule())
    }

    private func pipView(_ p: WhisperLiveRTCService.ParticipantInfo, size: CGSize) -> some View {
        participantTile(p, style: .pip)
            .frame(width: size.width, height: size.height)
    }

    private func pipSize(for geo: GeometryProxy) -> CGSize {
        let minDimension = min(geo.size.width, geo.size.height)
        let width = max(96, min(152, minDimension * 0.3))
        let height = width * 4.0 / 3.0
        return CGSize(width: width, height: height)
    }

    private func gridColumns(count: Int, isLandscape: Bool) -> Int {
        if isLandscape {
            return count <= 2 ? 2 : (count <= 4 ? 2 : 3)
        }
        return count <= 2 ? 2 : (count <= 4 ? 2 : 2)
    }

    private func avatarGradient(for name: String) -> LinearGradient {
        let colors: [Color] = [
            Color(red: 0.98, green: 0.55, blue: 0.25),
            Color(red: 0.95, green: 0.30, blue: 0.40),
            Color(red: 0.35, green: 0.55, blue: 0.95),
            Color(red: 0.45, green: 0.75, blue: 0.35),
            Color(red: 0.75, green: 0.40, blue: 0.85),
        ]
        let h = abs(name.hashValue)
        let c1 = colors[h % colors.count]
        let c2 = colors[(h / 7) % colors.count]
        return LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func initials(for name: String) -> String {
        let parts = name.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let letters = parts.prefix(2).compactMap { $0.first?.uppercased() }
        return letters.joined()
    }

    private func floatingTopBar(compact: Bool) -> some View {
        let size: CGFloat = compact ? 36 : 40
        // Google Meet-style header: back arrow, tappable meeting pill (add
        // people), then speaker route + camera flip on the right.
        return HStack(alignment: .center, spacing: compact ? 6 : 8) {
            if supportsMinimize {
                Button {
                    Haptics.tap()
                    WhisperMeetingWindow.shared.minimize()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 44, height: max(44, size))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Minimize meeting")
            }
            // Title · elapsed · headcount — one glass chip; tap to invite.
            Button {
                Haptics.tap()
                showInviteSheet = true
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                    Text(currentMeeting.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let joinedAt {
                        TimelineView(.periodic(from: joinedAt, by: 1)) { context in
                            Text(Self.elapsedString(from: joinedAt, to: context.date))
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    HStack(spacing: 3) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text("\(participants.count)")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.black.opacity(0.55), in: Capsule())
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add people")
            .layoutPriority(-1)

            Spacer(minLength: 6)

            WhisperAudioRouteMenu(current: audioRoute, onSelect: { route in
                audioRoute = route
                WhisperLiveRTCService.shared.setAudioRoute(route)
            }) {
                Image(systemName: audioRoute.controlIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Color.black.opacity(0.55), in: Circle())
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
                    .contentTransition(.symbolEffect(.replace))
            }
            topButton("arrow.triangle.2.circlepath.camera", size: size) {
                WhisperLiveRTCService.shared.switchCamera()
            }
            .accessibilityLabel("Flip camera")
        }
    }

    /// Everything else lives in one tidy menu so the call chrome stays
    /// clean: people, effects, Jasper's deck walkthrough, the pitch tools,
    /// screen share, role tools, and the shareable link.
    private func meetingToolsMenu(size: CGFloat, iconSize: CGFloat) -> some View {
        Menu {
            if currentMeeting.host_id.lowercased() == myUserID {
                Button { meetingNameDraft = currentMeeting.title; showRenameMeeting = true } label: { Label(isRenamingMeeting ? "Saving name…" : "Rename meeting", systemImage: "pencil") }.disabled(isRenamingMeeting)
            }
            if AuthenticationService.shared.isSignedIn {
                Button { showPersonalNotebook = true } label: {
                    Label("Jasper Sidekick · private", systemImage: "sparkles")
                }
            }
            Button {
                showInviteSheet = true
            } label: {
                Label("Add people", systemImage: "person.badge.plus")
            }
            Button { showPersonalNotebook = false; emberPanelOpen = true } label: { Label("Ask Jasper", systemImage: "bubble.left.and.text.bubble.right") }
            // Meet's in-room grammar — reactions, raise hand, host controls.
            if roomPolicy.reactions || isHost {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showReactionStrip.toggle() }
                } label: {
                    Label(showReactionStrip ? "Hide reactions" : "Send a reaction", systemImage: "face.smiling")
                }
            }
            Button {
                toggleHand()
            } label: {
                Label(myHandRaised ? "Lower hand" : "Raise hand", systemImage: "hand.raised.fill")
            }
            if isHost {
                Button {
                    showHostControls = true
                } label: {
                    Label("Host controls", systemImage: "lock.fill")
                }
            }
            if isHost {
                let kickables = participants.filter {
                    $0.peerId != WhisperLiveRTCService.shared.localPeerId
                }
                if !kickables.isEmpty {
                    Menu {
                        ForEach(kickables, id: \.peerId) { p in
                            Button(role: .destructive) {
                                kickParticipant(p)
                            } label: {
                                Label(p.name, systemImage: "person.fill.xmark")
                            }
                        }
                    } label: {
                        Label("Remove from meeting", systemImage: "person.fill.xmark")
                    }
                }
            }
            Button {
                showEffectsSheet = true
            } label: {
                Label("Backgrounds & effects", systemImage: "wand.and.stars")
            }
            Divider()
            Button {
                startDeckWalkthrough()
            } label: {
                Label("Walk the deck with Jasper", systemImage: "play.rectangle.fill")
            }
            Button {
                showWppCalculator = true
            } label: {
                Label("WPP calculator", systemImage: "slider.horizontal.3")
            }
            Button {
                showBrandCards = true
            } label: {
                Label("Brand cards", systemImage: "briefcase.fill")
            }
            Divider()
            Button {
                Task {
                    if isSharing {
                        await WhisperLiveRTCService.shared.stopScreenShare()
                        isSharing = false
                    } else {
                        isSharing = await WhisperLiveRTCService.shared.startScreenShare()
                    }
                }
            } label: {
                Label(
                    isSharing ? "Stop sharing screen" : "Share screen",
                    systemImage: isSharing ? "rectangle.on.rectangle.slash" : "rectangle.on.rectangle"
                )
            }
            // The host's present lock (`call-policy`) — hosts are exempt.
            .disabled(!roomPolicy.present && !isHost && !isSharing)
            // Role tools never show on a blind date — the room's only
            // intelligence is Jasper's prompts + the compatibility read.
            if isRecruiter && !speedDateActive {
                Button {
                    showRecruiterTools = true
                } label: {
                    Label("Recruiter tools", systemImage: "person.text.rectangle")
                }
                if liveEvalDismissed {
                    Button {
                        liveEvalDismissed = false
                        liveEvalCollapsed = false
                    } label: {
                        Label("Show Jasper's live read", systemImage: "chart.line.uptrend.xyaxis")
                    }
                } else {
                    Button {
                        liveEvalDismissed = true
                    } label: {
                        Label("Hide Jasper's live read", systemImage: "eye.slash")
                    }
                }
            }
            if isCoach && !speedDateActive {
                Button {
                    showCoachTools = true
                } label: {
                    Label("Coach tools", systemImage: "figure.strengthtraining.traditional")
                }
            }
            if isCreatorRole && !speedDateActive {
                Button {
                    showCreatorTools = true
                } label: {
                    Label("Creator tools", systemImage: "chart.line.uptrend.xyaxis")
                }
            }
            if !speedDateActive {
                businessPresentMenu
            }
            Divider()
            ShareLink(item: URL(string: isSpeedDateRoom ? "https://www.mydailywhisper.com/meet/\(meeting.id)?sd=1" : WhisperMeetingService.link(for: meeting.id)) ?? URL(string: "https://mydailywhisper.com")!) {
                Label("Share meeting link", systemImage: "square.and.arrow.up")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Color(white: 0.17), in: Circle())
        }
        .accessibilityLabel("Meeting tools")
    }

    private static func elapsedString(from start: Date, to now: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(start)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    private var transcriptIndicator: some View {
        Group {
            if !transcriber.liveCaption.isEmpty {
                Text(transcriber.liveCaption)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.74), in: .rect(cornerRadius: 16))
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "doc.waveform")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Text(transcriber.state.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.55), in: Capsule())
            }
        }
        .frame(maxWidth: 330)
    }

    private func topButton(_ icon: String, size: CGFloat = 40, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? .black : .white)
                .frame(width: size, height: size)
                .background(
                    active ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.black.opacity(0.55)),
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(active ? 0 : 0.12), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func controls(width: CGFloat) -> some View {
        // Google Meet-style row: the red end pill leads, then five round
        // buttons sitting directly on the stage — no bar chrome. Sized so
        // the row ALWAYS fits, scaling down on narrow phones instead of
        // spilling past the edge.
        let gap: CGFloat = width < 390 ? 10 : 14
        let available = width - 32 - gap * 5
        let btn = min(58, max(44, ((available - 20) / 6).rounded(.down)))
        let endWidth = btn + 20
        let iconSize: CGFloat = btn < 50 ? 17 : 19
        return HStack(spacing: gap) {
            Button {
                Haptics.tap()
                Task { await endTapped() }
            } label: {
                Group {
                    if ending {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: iconSize, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: endWidth, height: btn)
                .background(Color.red, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isHost ? "End meeting" : "Leave meeting")
            .disabled(ending)

            controlButton(icon: cameraOn ? "video.fill" : "video.slash.fill", size: btn, iconSize: iconSize, danger: !cameraOn) {
                cameraOn.toggle()
                WhisperLiveRTCService.shared.setCameraEnabled(cameraOn)
            }
            controlButton(icon: micOn ? "mic.fill" : "mic.slash.fill", size: btn, iconSize: iconSize, danger: !micOn) {
                if emberVoiceOn { stopEmberVoice() }
                if micOn { transcriber.stop() }
                micOn.toggle()
                WhisperLiveRTCService.shared.setMuted(!micOn)
                if !micOn {
                    transcriber.stop()
                    if emberVoiceOn { stopEmberVoice() }
                }
            }
            controlButton(icon: showTranscript ? "captions.bubble.fill" : "captions.bubble", size: btn, iconSize: iconSize, active: showTranscript) {
                switch transcriber.state {
                case .failed, .unavailable:
                    showTranscript = true
                    startMeetingTranscription()
                default:
                    showTranscript.toggle()
                }
            }
            // In-call messages — Meet's chat door with the unread badge
            // (backgrounds & effects live in the ⋯ menu, like Meet).
            ZStack(alignment: .topTrailing) {
                controlButton(icon: "bubble.left.and.bubble.right.fill", size: btn, iconSize: iconSize, active: showRoomChat) {
                    chatUnread = 0
                    showRoomChat = true
                }
                if chatUnread > 0 {
                    Text("\(min(chatUnread, 99))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Color(red: 0.66, green: 0.78, blue: 0.98), in: Capsule())
                        .offset(x: 3, y: -3)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: chatUnread)
            meetingToolsMenu(size: btn, iconSize: iconSize)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Meet grammar helpers (reactions · hands · chat · lifecycle)

    private func sendReaction(_ emoji: String) {
        guard roomPolicy.reactions || isHost else {
            showScheduleToast("The host turned off reactions")
            return
        }
        WhisperLiveRTCService.shared.sendAppEvent("call-react", data: ["emoji": emoji, "byName": myDisplayName])
        pushFloatingReaction(emoji: emoji, name: myDisplayName)
    }

    private func pushFloatingReaction(emoji: String, name: String) {
        floatingReactions.append(
            MeetFloatingReaction(id: UUID(), emoji: emoji, name: name, lane: CGFloat.random(in: 0.05...0.95))
        )
        if floatingReactions.count > 24 {
            floatingReactions.removeFirst(floatingReactions.count - 24)
        }
    }

    private func toggleHand() {
        let up = !myHandRaised
        WhisperLiveRTCService.shared.sendAppEvent(
            "call-hand",
            data: ["up": up, "userId": myUserID, "byName": myDisplayName]
        )
        if up { raisedHands[myUserID] = myDisplayName } else { raisedHands.removeValue(forKey: myUserID) }
        Haptics.tap()
    }

    private func sendRoomChat(_ text: String) {
        let id = UUID().uuidString.lowercased()
        let at = Date()
        WhisperLiveRTCService.shared.sendAppEvent(
            "call-chat",
            data: ["id": id, "text": text, "byName": myDisplayName, "at": at.timeIntervalSince1970 * 1000]
        )
        roomChat.append(MeetRoomChatMessage(id: id, name: myDisplayName, text: text, at: at, isSelf: true))
    }

    /// Join / leave chimes for OTHER people (my own landing chime plays in
    /// join()) — keyed on roster presence so an ICE blip can never re-chime.
    /// Also runs the HOST LIFECYCLE watch: the owner is the host while present;
    /// if the room's current host vanishes and no `call-host` handoff arrives,
    /// every client elects the SAME person after a short grace (the lowest
    /// userId still in the room), and the owner reclaims the room on return.
    // MARK: - Answering the door (host side)

    private func answerKnock(_ knock: MeetKnock, admit: Bool) {
        WhisperLiveRTCService.shared.sendAppEvent(admit ? "meeting-admit" : "meeting-deny", data: [
            "knockId": knock.knockId,
            "byName": myDisplayName
        ])
        withAnimation(.easeOut(duration: 0.2)) {
            pendingKnocks.removeAll { $0.knockId == knock.knockId }
        }
        if admit { showScheduleToast("\(knock.name) is joining") }
    }

    private func admitAllKnocks() {
        let knocks = pendingKnocks
        for knock in knocks {
            WhisperLiveRTCService.shared.sendAppEvent("meeting-admit", data: [
                "knockId": knock.knockId,
                "byName": myDisplayName
            ])
        }
        withAnimation(.easeOut(duration: 0.2)) { pendingKnocks.removeAll() }
        if !knocks.isEmpty {
            showScheduleToast("Admitted \(knocks.count) \(knocks.count == 1 ? "person" : "people")")
        }
    }

    private func noteRosterChange(_ roster: [WhisperLiveRTCService.ParticipantInfo]) {
        guard joined else { return }
        let mine = WhisperLiveRTCService.shared.localPeerId
        let remotes = Set(roster.filter { $0.peerId != mine }.map { $0.peerId })
        if !seenRemotePeerIDs.isEmpty || !remotes.isEmpty {
            let arrived = !remotes.subtracting(seenRemotePeerIDs).isEmpty
            let departed = !seenRemotePeerIDs.subtracting(remotes).isEmpty
            if arrived && !seenRemotePeerIDs.isEmpty {
                WhisperMeetChime.playJoin()
            } else if departed {
                WhisperMeetChime.playLeave()
            }
        }
        seenRemotePeerIDs = remotes

        let owner = meeting.host_id.lowercased()
        let ids = Set(roster.map { $0.userId.lowercased() })
        hostElectionTask?.cancel()
        hostElectionTask = nil
        if ids.contains(owner) {
            hostSeen = true
            if let acting = actingHostUserID, acting != owner { actingHostUserID = nil }
            return
        }
        guard hostSeen, !ids.contains(hostUserID) else { return }
        let candidates = ids.filter { !$0.isEmpty }.sorted()
        guard let elected = candidates.first else { return }
        hostElectionTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            actingHostUserID = elected
            if elected == myUserID {
                showScheduleToast("You're the host now — the previous host left")
            }
        }
    }

    private func controlButton(
        icon: String,
        size: CGFloat = 52,
        iconSize: CGFloat = 17,
        danger: Bool = false,
        active: Bool = false,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let bgColor: Color = {
            if let tint { return tint.opacity(0.2) }
            if danger { return Color.red }
            if active { return Color.white }
            return Color(white: 0.17)
        }()
        return Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(active ? Color.black : (tint ?? .white))
                .frame(width: size, height: size)
                .background(bgColor, in: Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Notes / generating

    /// Post-meeting recap — appears the moment the meeting ends. This is the
    /// EXACT same Jasper-canvas notes screen the Meetings list and DM notes
    /// cards open (web twin: MeetingNotesScreen) — the transcript shows right
    /// away and the structured notes slot in when Jasper finishes writing.
    private var recapView: some View {
        sharedRecapView
    }

    private var sharedRecapView: some View {
        WhisperMeetingNotesView(
            title: currentMeeting.title,
            liveNotes: notes,
            writing: generating,
            notebookMeetingID: meeting.id,
            subtitle: recapSubtitle,
            transcript: recapTranscript.isEmpty ? nil : recapTranscript,
            footnote: "Sending a copy requires your review. Private recordings are not included.",
            emptyMessage: "No summary is available yet. Saved speech and available recordings appear below.",
            onEmail: notes == nil ? nil : { showNotesEmail = true },
            extraContent: recruiterExtras,
            onClose: { requestClose() }
        )
    }

    /// Recruiter-only console (prospect eval + application auto-match) —
    /// keeps its dark styling inside a near-black card on the light canvas.
    private var recruiterExtras: AnyView? {
        guard isRecruiter, notes != nil else { return nil }
        return AnyView(
            VStack(spacing: 12) {
                pitchDeckRecapCard
                notesEvalSection(liveEval ?? loadStoredEval())
                    .onAppear { restoreCaptureDraft() }
                notesAutoMatchCard
            }
            .padding(8)
            .background(Color(red: 0.05, green: 0.06, blue: 0.09), in: .rect(cornerRadius: 24))
        )
    }

    /// Regenerate the deck from the FULL transcript when the meeting ends —
    /// replaces the mid-meeting draft and persists it. Never blocks the recap.
    private func finalizePitchDeck() {
        guard !deckBuilding else { return }
        deckBuilding = true
        let hint = presentation?.displayName ?? presentation?.username
        Task {
            if let deck = await WhisperPitchDeckService.shared.generate(
                meetingID: meeting.id,
                meetingTitle: currentMeeting.title,
                prospectHint: hint,
                isDraft: false
            ) {
                pitchDeck = deck
            } else if pitchDeck == nil {
                pitchDeck = await WhisperPitchDeckService.shared.load(meetingID: meeting.id)
            }
            deckBuilding = false
        }
    }

    /// Jasper's pitch deck living IN the notes — the inline flip-through
    /// notebook once the deck exists, or the cream build card until then.
    private var pitchDeckRecapCard: some View {
        let deckInk = Color(red: 0.125, green: 0.141, blue: 0.169)
        let deckInkSoft = Color(red: 0.361, green: 0.353, blue: 0.314)
        let deckMint = Color(red: 0.055, green: 0.624, blue: 0.463)
        return VStack(alignment: .leading, spacing: 10) {
            if let deck = pitchDeck {
                HStack(spacing: 6) {
                    Image(systemName: "book.pages")
                        .font(.system(size: 11, weight: .bold))
                    Text("JASPER'S PITCH DECK")
                        .font(.system(size: 10, weight: .black))
                        .tracking(1.8)
                }
                .foregroundStyle(Color(red: 0.553, green: 0.941, blue: 0.788))
                .padding(.leading, 2)
                WhisperMeetingDeckView(deck: deck)
            } else {
                Button {
                    Haptics.tap()
                    if !deckBuilding { finalizePitchDeck() }
                } label: {
                    HStack(spacing: 12) {
                        WhisperEmberMascot(size: 42, isActive: deckBuilding, coachMode: WhisperEmberCoachMode.load())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(deckBuilding ? "Jasper is building your pitch deck…" : "Build the close plan")
                                .font(.subheadline.weight(.heavy))
                                .foregroundStyle(deckInk)
                                .lineLimit(2)
                            Text("Jasper turns this meeting into a flip-through deck — what they care about, your close odds, and the plan. It appears right here with the notes.")
                                .font(.caption2)
                                .foregroundStyle(deckInkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if deckBuilding {
                            ProgressView().tint(deckMint)
                        } else {
                            Text("Build")
                                .font(.caption.weight(.black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(deckMint, in: Capsule())
                        }
                    }
                    .padding(14)
                    .background(Color(red: 0.984, green: 0.968, blue: 0.925), in: .rect(cornerRadius: 20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(deckMint.opacity(0.35), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .task {
            // Reopened recaps: surface the stored deck without regenerating.
            if pitchDeck == nil, !deckBuilding {
                pitchDeck = await WhisperPitchDeckService.shared.load(meetingID: meeting.id)
            }
        }
    }

    /// The mid-call popup — a slim capsule inviting a flip through the draft.
    private func deckPopupCapsule(_ deck: WhisperPitchDeck) -> some View {
        let popMint = Color(red: 0.553, green: 0.941, blue: 0.788)
        return HStack(spacing: 10) {
            WhisperEmberMascot(size: 30, isActive: true, coachMode: WhisperEmberCoachMode.load())
            VStack(alignment: .leading, spacing: 1) {
                Text("Jasper drafted your pitch deck")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                Text("\(deck.prospectName) · \(deck.closeRate.withPlan)% with the plan")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
            Button {
                Haptics.tap()
                deckPopup = false
                // The draft lives inline in Recruiter Tools mid-call; the final
                // deck lands right in the notes when the meeting ends.
                showRecruiterTools = true
            } label: {
                Text("View")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(popMint, in: Capsule())
            }
            .buttonStyle(.plain)
            Button {
                withAnimation(.easeOut(duration: 0.2)) { deckPopup = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 30, height: 30)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.82), in: Capsule())
        .overlay { Capsule().strokeBorder(popMint.opacity(0.4), lineWidth: 1) }
        .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
    }

    private var recapSubtitle: String {
        if notes != nil { return "Meeting ended \u{00B7} AI notes" }
        if generating { return "Meeting ended \u{00B7} Jasper is writing notes\u{2026}" }
        return "Meeting ended \u{00B7} Transcript saved"
    }

    private var notesGeneratingCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .symbolEffect(.pulse)
            VStack(alignment: .leading, spacing: 3) {
                Text("Jasper is writing your notes")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text("Summary, key points, decisions and action items. Your transcript below is already saved.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            ProgressView().tint(.white)
        }
        .padding(16)
        .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 20))
    }

    private var recapNotesPendingCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
            Text("Notes are on the way — the host's copy lands in your DMs automatically.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 20))
    }

    /// Collapsible "who said what" transcript — first lines visible
    /// immediately, expandable to the full conversation.
    private var transcriptCard: some View {
        let lines = recapTranscript
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let visible = transcriptExpanded ? lines : Array(lines.prefix(6))
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    transcriptExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 26, height: 26)
                        .background(.white, in: Circle())
                    Text("FULL TRANSCRIPT")
                        .font(.system(size: 10, weight: .black))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.55))
                    Text("\(lines.count) lines")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                        .rotationEffect(.degrees(transcriptExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, line in
                    transcriptLine(line)
                }
            }

            if !transcriptExpanded && lines.count > visible.count {
                Text("+\(lines.count - visible.count) more — tap to expand")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 20))
    }

    private func transcriptLine(_ line: String) -> some View {
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        return HStack(alignment: .top, spacing: 6) {
            if parts.count == 2 {
                Text(String(parts[0]))
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.white.opacity(0.92))
                Text(String(parts[1]).trimmingCharacters(in: .whitespaces))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func notesSectionCard(_ section: WhisperMeetingNotesSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: WhisperMeetingCompanion.sectionIcon(section.title))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 26, height: 26)
                    .background(.white, in: Circle())
                Text(section.title.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.55))
            }
            ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.92))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(section.bullets.enumerated()), id: \.offset) { _, bullet in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 5, height: 5)
                        .padding(.top, 6)
                    Text(bullet)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.88))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 20))
    }

    private func notesShareRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            ShareLink(item: WhisperMeetingCompanion.notesDmText(title: currentMeeting.title, notes: text, transcript: recapTranscript.isEmpty ? nil : recapTranscript)) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.white, in: Capsule())
            }
            Button {
                Haptics.tap()
                showNotesEmail = true
            } label: {
                Label("Email", systemImage: "envelope.fill")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func notesEvalSection(_ eval: WhisperProspectEval?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.cyan)
                Text("PROSPECT EVALUATION")
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Button {
                    Haptics.tap()
                    regenerateEval()
                } label: {
                    if finalEvalBusy {
                        ProgressView().tint(.white).scaleEffect(0.7)
                    } else {
                        Text(eval == nil ? "Generate" : "Re-run")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.12), in: Capsule())
                    }
                }
                .buttonStyle(.plain)
                .disabled(finalEvalBusy)
            }
            if let eval {
                HStack(alignment: .center, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(eval.score)")
                            .font(.system(size: 38, weight: .black))
                            .foregroundStyle(.white)
                        Text("/100")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.12))
                                Capsule()
                                    .fill(scoreTint(eval.score))
                                    .frame(width: g.size.width * min(1, max(0.04, Double(eval.score) / 100)))
                            }
                        }
                        .frame(height: 6)
                        Text("\(eval.confidence)% CONFIDENCE \u{00B7} RECRUITING POTENTIAL")
                            .font(.system(size: 8, weight: .black))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("RECOMMENDED PLACEMENT")
                        .font(.system(size: 8, weight: .black))
                        .tracking(1.0)
                        .foregroundStyle(.white.opacity(0.4))
                    placementChips(eval.placement)
                }
                Text(eval.summary)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !eval.strengths.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("STRENGTHS")
                            .font(.system(size: 8, weight: .black))
                            .tracking(1.0)
                            .foregroundStyle(.green.opacity(0.8))
                        ForEach(Array(eval.strengths.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.green)
                                    .padding(.top, 2)
                                Text(item)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                if !eval.concerns.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WATCH-OUTS")
                            .font(.system(size: 8, weight: .black))
                            .tracking(1.0)
                            .foregroundStyle(.yellow.opacity(0.8))
                        ForEach(Array(eval.concerns.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.yellow)
                                    .padding(.top, 2)
                                Text(item)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                Text("ONLY VISIBLE TO YOU")
                    .font(.system(size: 8, weight: .black))
                    .tracking(1.0)
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity)
            } else {
                Text("No live read was captured during this call. Generate one from the transcript to score this prospect and get a placement recommendation.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.cyan.opacity(0.08), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.cyan.opacity(0.25), lineWidth: 1)
        }
    }

    // MARK: - Jasper companion (private, in-call)

    private var emberPillText: String {
        if emberVoiceOn { return emberVoiceLine.phase == .speaking ? "Jasper speaking" : "Live voice" }
        if emberCapturing { return "Listening…" }
        if emberBusy { return "Thinking…" }
        if emberChime != nil { return "Jasper has a thought" }
        if emberReply != nil { return "\(emberMode.shortTitle) mode" }
        return "Ask Jasper"
    }

    /// The living mascot — halo while busy, bobbing gently — that peeks
    /// from behind the pill (and the box header) top edge.
    private var emberFace: some View {
        emberFaceCore.allowsHitTesting(false)
    }

    /// Tappable mascot for the open box — tapping Jasper himself starts
    /// hands-free listening, exactly like tapping the pill or the mic.
    private var emberFaceTappable: some View {
        Button {
            Haptics.tap()
            guard !emberBusy, !emberCapturing else { return }
            beginEmberVoiceCapture()
        } label: {
            emberFaceCore
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Talk to Jasper")
    }

    private var emberFaceCore: some View {
        ZStack {
            if emberChime != nil, !emberPanelOpen {
                // Chime-in glow — Jasper lights up when he has a thought.
                Circle()
                    .fill(emberMode.accent)
                    .frame(width: 44, height: 44)
                    .blur(radius: 14)
                    .phaseAnimator([0.35, 0.8]) { view, glow in
                        view.opacity(glow)
                    } animation: { _ in
                        .easeInOut(duration: 0.9)
                    }
            }
            if emberBusy || emberCapturing {
                WhisperRainbowHalo()
            }
            WhisperEmberMascot(
                size: 50,
                isActive: emberBusy || emberCapturing,
                expression: emberBusy
                    ? .thinking
                    : (emberCapturing
                        ? .attentive
                        : (emberError ? .concerned : (emberReply != nil ? emberMode.signatureExpression : .calm))),
                coachMode: emberMode,
                cyclesExpressions: !emberBusy && !emberCapturing && emberReply == nil
            )
        }
        .phaseAnimator([false, true]) { view, phase in
            view.offset(y: phase ? 2 : -2)
        } animation: { _ in
            .easeInOut(duration: 1.7)
        }
    }

    /// Shared glass shell for the pill and the box — dark material with a
    /// soft mode-tinted glow, like the profile auto-analysis pill.
    private func emberShell(_ shape: some InsettableShape, compact: Bool = false) -> some View {
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(Color.black.opacity(0.45))
            shape.fill(
                LinearGradient(
                    colors: [emberMode.accent.opacity(compact ? 0.16 : 0.20), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            shape.strokeBorder(emberMode.accent.opacity(compact ? 0.40 : 0.32), lineWidth: 1)
        }
        .compositingGroup()
        .shadow(color: emberMode.accent.opacity(compact ? 0.32 : 0.25), radius: compact ? 11 : 16, y: compact ? 4 : 5)
        .shadow(color: .black.opacity(compact ? 0.35 : 0.45), radius: compact ? 13 : 22, y: compact ? 6 : 10)
    }

    /// Arms hands-free capture — the shared path for the pill, the mascot,
    /// and the wake word: Jasper listens the moment you tap him.
    private func beginEmberVoiceCapture() {
        guard joined, !ending, emberPanelOpen else { return }
        // All private voice uses the same mute-first, cancellable session.
        if !emberVoiceOn { toggleEmberVoice() }
    }

    /// Delivers a pending chime-in as a normal Jasper reply inside the box.
    private func deliverChime(_ comment: String) {
        withAnimation(.easeOut(duration: 0.25)) { emberChime = nil }
        emberCapturing = false
        emberAskVoiced = false
        emberBusy = false
        emberError = false
        emberActions = []
        emberPitchOffer = false
        emberReply = comment
    }

    /// The "wants to chime in" thought cloud — dressed in Jasper's own
    /// meeting language: dark personality-tinted glass, a JASPER header
    /// with the mode name, and tail circles stepping down toward his head.
    private func emberChimeCloud(_ text: String) -> some View {
        Button {
            Haptics.tap()
            deliverChime(text)
            withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
                emberPanelOpen = true
            }
        } label: {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(emberMode.accent)
                            .frame(width: 5, height: 5)
                        Text("JASPER \u{00B7} \(emberMode.shortTitle.uppercased())")
                            .font(.system(size: 8, weight: .black))
                            .tracking(1.1)
                            .foregroundStyle(emberMode.accent)
                        Spacer(minLength: 0)
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    Text(text)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)
                        .lineLimit(3)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background { emberShell(RoundedRectangle(cornerRadius: 18), compact: true) }
                Circle()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: 9, height: 9)
                    .overlay { Circle().strokeBorder(emberMode.accent.opacity(0.45), lineWidth: 1) }
                    .offset(x: -12, y: -1)
                Circle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 5, height: 5)
                    .overlay { Circle().strokeBorder(emberMode.accent.opacity(0.45), lineWidth: 1) }
                    .offset(x: -18, y: 2)
            }
            .frame(maxWidth: 240)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .phaseAnimator([false, true]) { view, phase in
            view.offset(y: phase ? 3 : -3)
        } animation: { _ in
            .easeInOut(duration: 1.6)
        }
        .accessibilityLabel("Jasper wants to chime in: \(text)")
    }

    // MARK: - Jasper chime-in (proactive thoughts about people)

    /// Every ~40s Jasper re-reads the room; when he has one genuinely
    /// useful thought about a person being discussed he glows and floats a
    /// thought cloud above his head — tap to hear him out.
    private func startChimeLoop() {
        chimeTask?.cancel()
        chimeTask = Task {
            try? await Task.sleep(for: .seconds(60))
            while !Task.isCancelled {
                await chimeTick()
                // 90s between checks (was 40s) — chimes stay occasional
                // and the transcript gate below skips quiet stretches.
                try? await Task.sleep(for: .seconds(90))
            }
        }
    }

    private func chimeTick() async {
        guard emberChime == nil, !emberPanelOpen, !emberBusy,
              !emberCapturing, !emberVoiceOn else { return }
        if let last = lastChimeAt, Date().timeIntervalSince(last) < 130 { return }
        let full = await WhisperMeetingService.shared.fetchTranscriptPlain(meetingID: meeting.id)
        guard !Task.isCancelled else { return }
        guard full.count >= 220, full.count - lastChimeChars >= 400 else { return }
        lastChimeChars = full.count
        let names = participants.map { $0.name }
        guard let comment = await WhisperMeetingCompanion.chimeThought(
            transcript: full,
            participants: names,
            meetingTitle: currentMeeting.title
        ) else { return }
        guard !Task.isCancelled, emberChime == nil, !emberPanelOpen, !emberVoiceOn else { return }
        lastChimeAt = Date()
        Haptics.tap()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { emberChime = comment }
        // The cloud politely dissolves if ignored.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(50))
            if emberChime == comment {
                withAnimation(.easeOut(duration: 0.35)) { emberChime = nil }
            }
        }
    }

    /// Clears any in-flight Jasper state so the pill returns to "Ask Jasper".
    private func resetEmberState() {
        if emberVoiceOn { stopEmberVoice() }
        emberCapturing = false
        emberAskVoiced = false
        emberReply = nil
        emberPitchOffer = false
        emberError = false
        emberActions = []
    }

    /// Collapsed Jasper — the mascot peeking from behind the mint pill
    /// (reference-matched #DAFAEB, glowing, no dismiss X) docked above the
    /// call controls. Tapping floats it upward into the box.
    private var emberPill: some View {
        Button {
            Haptics.tap()
            if let chime = emberChime {
                deliverChime(chime)
            } else {
                beginEmberVoiceCapture()
            }
            withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
                emberPanelOpen = true
            }
        } label: {
            Text(emberPillText)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(WhisperEmberPillPalette.ink(for: emberMode))
                .lineLimit(1)
                .padding(.horizontal, 20)
                .frame(height: 34)
                .background { WhisperEmberMintShell(shape: Capsule(), mode: emberMode) }
                .background(alignment: .top) { emberFace.offset(y: -26) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask Jasper")
        .overlay(alignment: .top) {
            if let chime = emberChime {
                emberChimeCloud(chime)
                    .offset(y: -118)
                    .transition(.scale(scale: 0.5, anchor: .bottom).combined(with: .opacity))
            }
        }
        .matchedGeometryEffect(id: "emberHeader", in: emberNS, isSource: !emberPanelOpen)
        .opacity(emberPeekedIn ? 1 : 0)
        .offset(y: emberPeekedIn ? 0 : 150)
        .onAppear {
            guard !emberPeekedIn else { return }
            withAnimation(.spring(response: 0.75, dampingFraction: 0.68).delay(0.5)) {
                emberPeekedIn = true
            }
        }
    }

    private func closeEmberPanel() {
        Haptics.tap()
        if emberVoiceOn { stopEmberVoice() }
        emberDebounceTask?.cancel(); emberDebounceTask = nil
        emberVoiceBuffer = ""
        emberCapturing = false
        withAnimation(.spring(duration: 0.36, bounce: 0.12)) {
            emberPanelOpen = false
        }
    }

    /// Expanded Jasper — the mint pill floats upward and becomes the box
    /// header (matched geometry), with the mascot still peeking over the
    /// top edge of the dark glass box.
    private var emberBox: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(emberPillText)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(WhisperEmberPillPalette.ink(for: emberMode))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    closeEmberPanel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WhisperEmberPillPalette.ink(for: emberMode).opacity(0.55))
                        .frame(width: 22, height: 22)
                        .background(WhisperEmberPillPalette.ink(for: emberMode).opacity(0.08), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Jasper")
            }
            .padding(.leading, 16)
            .padding(.trailing, 7)
            .frame(height: 36)
            .background { WhisperEmberMintShell(shape: Capsule(), mode: emberMode) }
            .matchedGeometryEffect(id: "emberHeader", in: emberNS, isSource: emberPanelOpen)
            .padding(.horizontal, 10)
            .padding(.top, 10)

            ViewThatFits(in: .vertical) {
                emberConversationBlock
                ScrollView(showsIndicators: false) { emberConversationBlock }
            }
            .frame(maxHeight: keyboardLift > 0 ? 148 : 224, alignment: .top)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    emberToolChip("Walk the deck", icon: "play.rectangle.fill", prominent: true) {
                        startDeckWalkthrough()
                    }
                    emberToolChip("WPP calc", icon: "slider.horizontal.3") {
                        showWppCalculator = true
                    }
                    emberToolChip("Brands", icon: "briefcase.fill") {
                        showBrandCards = true
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.bottom, 10)

            emberAskBar
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .frame(width: min(UIScreen.main.bounds.width - 24, 380))
        .background { emberShell(RoundedRectangle(cornerRadius: 24)) }
        .background(alignment: .top) { emberFaceTappable.offset(y: -24) }
    }

    private var emberConversationBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            emberConversation
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var emberConversation: some View {
        if !emberVoiceOn && !emberBusy && !emberCapturing && emberReply == nil {
            Text("Ask about this meeting, Whisper, or anything mid-call — replies stay private to you.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
                .lineSpacing(3)
        }
        if emberVoiceOn {
            emberStatusChip(
                emberVoiceStatusLine,
                icon: emberVoiceLine.phase == .speaking ? "speaker.wave.2.fill" : "waveform",
                tint: emberMode.accent,
                showsSpinner: emberVoiceLine.phase == .connecting || emberVoiceLine.phase == .thinking,
                animatesIcon: emberVoiceLine.phase == .listening || emberVoiceLine.phase == .speaking
            )
            if !emberVoiceLine.transcript.isEmpty {
                Text("\u{201C}\(emberVoiceLine.transcript)\u{201D}")
                    .font(.system(size: 13))
                    .italic()
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
            }
            if !emberVoiceLine.replyText.isEmpty {
                Text(emberVoiceLine.replyText)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .lineSpacing(3)
                    .lineLimit(8)
            }
        }
        // ONE working box — the listening phase, thinking phases, and
        // checkmark chipping all live on the same rail.
        if emberCapturing {
            switch transcriber.state {
            case .unavailable(let message), .failed(let message):
                emberStatusChip(message, icon: "exclamationmark.triangle.fill", tint: Color(red: 1.0, green: 0.72, blue: 0.35))
            default:
                EmptyView()
            }
        }
        if emberBusy || emberCapturing {
            WhisperEmberThinkingSteps(
                coachMode: emberMode,
                resolvedLabel: nil,
                isAnalytical: false,
                onDark: true,
                flavor: .meeting,
                listenState: emberCapturing ? .listening : (emberAskVoiced ? .done : .hidden),
                queryHint: lastEmberQuestion.isEmpty ? nil : lastEmberQuestion
            )
            if emberCapturing {
                let heard = [emberVoiceBuffer, transcriber.liveCaption]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                if !heard.isEmpty {
                    Text("\u{201C}\(heard)\u{201D}")
                        .font(.system(size: 14))
                        .italic()
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        if let reply = emberReply, !emberCapturing,
           !emberVoiceOn || emberVoiceLine.replyText.isEmpty {
            emberReplyCard(reply)
        }
        if !emberActions.isEmpty, !emberCapturing, !emberBusy {
            WhisperEmberActionRow(actions: emberActions, forceDark: true)
        }
        if emberPitchOffer, !emberCapturing,
           let pitchURL = URL(string: "https://mydailywhisper.com/pitch") {
            Link(destination: pitchURL) {
                Label("Open the full pitch deck", systemImage: "book.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(emberMode.accent, in: Capsule())
            }
        }
        if emberReply != nil, !emberBusy, !emberCapturing {
            if emberError {
                Button {
                    Haptics.tap()
                    Task { await askEmber(lastEmberQuestion) }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .black))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(emberMode.softAccent)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Haptics.tap()
                    shareEmberAnswer()
                } label: {
                    Label("Share with meeting", systemImage: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .black))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(emberMode.softAccent)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Jasper's answer, dressed — a JASPER header row with the personality
    /// chip, a tinted accent bar, and rich left-aligned text. Every reply
    /// (even one word) wears this card; nothing ever floats bare.
    private func emberReplyCard(_ reply: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(emberMode.softAccent)
                Text("JASPER")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.4)
                    .foregroundStyle(emberMode.softAccent)
                Spacer(minLength: 6)
                Text(emberMode.shortTitle.uppercased())
                    .font(.system(size: 8, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
            WhisperEmberRichText(text: reply, onDark: true, baseSize: 15)
        }
        .padding(.vertical, 11)
        .padding(.leading, 14)
        .padding(.trailing, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 16))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(emberMode.accent.opacity(0.7))
                .frame(width: 3)
                .padding(.vertical, 10)
                .padding(.leading, 5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(emberMode.accent.opacity(0.2), lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.35), value: emberMode)
    }

    private var emberAskBar: some View {
        HStack(spacing: 8) {
            TextField("Ask Jasper anything…", text: $emberDraft)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .tint(emberMode.accent)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.white.opacity(0.1), in: Capsule())
                .submitLabel(.send)
                .onSubmit { submitEmberDraft() }
            Button {
                Haptics.tap()
                toggleEmberVoice()
            } label: {
                WhisperJasperVoiceGlyph(
                    tint: emberVoiceOn ? .black : emberMode.accent,
                    size: 20,
                    active: emberVoiceOn || emberCapturing
                )
                .frame(width: 44, height: 44)
                .background(emberVoiceOn ? AnyShapeStyle(emberMode.accent) : AnyShapeStyle(Color.white.opacity(0.1)), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(emberVoiceOn ? "Stop Jasper live voice" : "Talk to Jasper live")
            Button {
                Haptics.tap()
                submitEmberDraft()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(emberMode.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(emberDraft.trimmingCharacters(in: .whitespaces).isEmpty || emberBusy)
            .opacity(emberDraft.trimmingCharacters(in: .whitespaces).isEmpty || emberBusy ? 0.4 : 1)
        }
    }

    private func submitEmberDraft() {
        let question = emberDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !emberBusy else { return }
        emberCapturing = false
        emberAskVoiced = false
        emberDraft = ""
        Task { await askEmber(question) }
    }

    private func askEmber(_ question: String) async {
        lastEmberQuestion = question
        if !emberPanelOpen {
            withAnimation(.spring(duration: 0.4, bounce: 0.22)) { emberPanelOpen = true }
        }
        emberBusy = true
        emberError = false
        emberReply = nil
        emberActions = []
        emberPitchOffer = false
        let names = participants.map { $0.name }
        // Creators get their LIVE analytics riding along with every meeting
        // question, so Jasper grounds content/growth answers in real numbers.
        let creatorContext: String? = isCreatorRole
            ? await WhisperCreatorMeetingKit.jasperContext()
            : nil
        let reply = await WhisperMeetingCompanion.meetingAnswer(
            question: question,
            meetingTitle: currentMeeting.title,
            participants: names,
            preferredMode: WhisperEmberCoachMode.load(),
            extraContext: creatorContext
        )
        emberBusy = false
        if let reply {
            emberMode = reply.mode
            let parsed = WhisperEmberActionParser.parse(reply.text)
            emberActions = parsed.actions
            emberReply = parsed.text.isEmpty
                ? (parsed.actions.isEmpty ? "Done." : "Here you go:")
                : parsed.text
            emberPitchOffer = reply.showPitch
        } else {
            emberError = true
            emberReply = "Jasper couldn't answer that right now — try again."
        }
    }

    private func shareEmberAnswer() {
        guard let reply = emberReply, !reply.isEmpty else { return }
        let name = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "someone"
        WhisperLiveRTCService.shared.sendAppEvent("ember-share", data: ["name": name, "text": reply])
    }

    /// Compact glass status chip for Jasper's transient states (listening,
    /// speaking, warnings) inside the box.
    private func emberStatusChip(
        _ text: String,
        icon: String? = nil,
        tint: Color,
        showsSpinner: Bool = false,
        animatesIcon: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            if showsSpinner {
                ProgressView()
                    .controlSize(.mini)
                    .tint(tint)
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: animatesIcon)
            }
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.leading)
                .lineLimit(3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.07), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        }
    }

    private func emberToolChip(
        _ title: String,
        icon: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(prominent ? Color(red: 1.0, green: 0.78, blue: 0.50) : emberMode.softAccent)
                    .frame(width: 22, height: 22)
                    .background(
                        prominent ? AnyShapeStyle(Color.orange.opacity(0.22)) : AnyShapeStyle(emberMode.accent.opacity(0.16)),
                        in: Circle()
                    )
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .padding(.leading, 7)
            .padding(.trailing, 13)
            .frame(height: 36)
            .background(Color.white.opacity(0.07), in: Capsule())
            .overlay {
                Capsule().strokeBorder(
                    prominent ? Color.orange.opacity(0.35) : Color.white.opacity(0.10),
                    lineWidth: 1
                )
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Jasper reads the pitch deck to the whole room — the iOS twin of the
    /// web's "Walk the deck". Every device (web viewers included) plays the
    /// same fixed narration line locally, kept in sync by `deck-tour` events.
    private func startDeckWalkthrough() {
        if let tour = deckTour.view, !deckTour.isDriver {
            showScheduleToast("@\(tour.driverName) is already presenting")
            return
        }
        if emberVoiceOn { stopEmberVoice() }
        emberCapturing = false
        emberPanelOpen = false
        tourHidden = false
        let name = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "someone"
        deckTour.startDriving(selfName: name)
    }

    // MARK: - App events (presenting + shared answers)

    private func handleAppEvent(_ event: String, data: [String: Any], fromPeerId: String) {
        if !isSpeedDateRoom, WhisperRecordingConsentService.shared.receive(event, data: data, from: fromPeerId, hostID: hostUserID) { return }
        // Room signaling is cooperative, not a server-authenticated moderation rail.
        // Only accept host controls from the currently known host session.
        if ["meeting-kick", "call-end", "call-host", "call-policy", "call-mute", "call-mute-all"].contains(event) {
            guard WhisperLiveRTCService.shared.participants.contains(where: {
                $0.peerId == fromPeerId && $0.userId.lowercased() == hostUserID
            }) else { return }
        }
        switch event {
        case "deck-tour":
            let hadTour = deckTour.view != nil
            deckTour.handleRemote(data, fromPeerId: fromPeerId)
            if !hadTour, deckTour.view != nil { tourHidden = false }
        case "present-sync-request":
            // A late joiner asked "is anything running?" — answer instantly
            // instead of making them wait for the next heartbeat.
            if let current = presentation,
               current.presenterUserId.lowercased() == myUserID {
                WhisperLiveRTCService.shared.sendAppEvent("present-client", data: current.encodeToDict())
            }
            if let card = analyticsCard,
               card.presenterUserId.lowercased() == myUserID {
                WhisperLiveRTCService.shared.sendAppEvent("creator-analytics", data: card.encodeToDict())
            }
            if let biz = bizCard,
               biz.presenterUserId.lowercased() == myUserID {
                WhisperLiveRTCService.shared.sendAppEvent("business-card", data: biz.encodeToDict())
            }
            deckTour.answerSyncRequest()
        case "present-client":
            guard let payload = WhisperPresentedClient.decode(fromAny: data),
                  !payload.presenterUserId.isEmpty, !payload.id.isEmpty else { return }
            presentBeat = Date()
            let key = "\(payload.presenterUserId):\(payload.id)"
            let currentKey = presentation.map { "\($0.presenterUserId):\($0.id)" }
            if currentKey != key {
                presentationExpanded = false
                presentation = payload
            } else if presentation?.rev != payload.rev {
                // Same presentation, richer payload (photos/snapshot/answers).
                presentation = payload
            }
        case "present-client-end":
            let presenter = (data["presenterUserId"] as? String)?.lowercased() ?? ""
            if let current = presentation,
               presenter.isEmpty || current.presenterUserId.lowercased() == presenter {
                presentation = nil
                presentationExpanded = false
            }
        case "creator-analytics":
            guard let card = WhisperCreatorAnalyticsCard.decode(fromAny: data),
                  !card.presenterUserId.isEmpty else { return }
            analyticsBeat = Date()
            if analyticsCard?.id != card.id {
                analyticsExpanded = false
                withAnimation(.spring(duration: 0.4, bounce: 0.2)) { analyticsCard = card }
            } else if analyticsCard?.rev != card.rev {
                analyticsCard = card
            }
        case "creator-analytics-end":
            let analyticsPresenter = (data["presenterUserId"] as? String)?.lowercased() ?? ""
            if let current = analyticsCard,
               analyticsPresenter.isEmpty || current.presenterUserId.lowercased() == analyticsPresenter {
                withAnimation(.spring(duration: 0.35)) { analyticsCard = nil }
                analyticsExpanded = false
            }
        case "business-card":
            // A Business+ member is presenting their company — web or iOS,
            // same camelCase wire. A fresh rev re-arms the hand-raise button.
            guard let card = WhisperBusinessCardWire.decode(fromAny: data),
                  !card.presenterUserId.isEmpty, !card.company.isEmpty else { return }
            let bizRevKey = "\(card.presenterUserId.lowercased()):\(card.rev ?? 0)"
            if bizSeenRevKey != bizRevKey {
                bizSeenRevKey = bizRevKey
                if card.presenterUserId.lowercased() != myUserID { bizHandRaised = false }
            }
            if bizCard != card {
                withAnimation(.spring(duration: 0.4, bounce: 0.2)) { bizCard = card }
            }
        case "business-card-end":
            let bizPresenter = (data["presenterUserId"] as? String)?.lowercased() ?? ""
            if let current = bizCard,
               bizPresenter.isEmpty || current.presenterUserId.lowercased() == bizPresenter {
                withAnimation(.spring(duration: 0.35)) { bizCard = nil }
                bizInterested = []
                bizHandRaised = false
            }
        case "business-interest":
            // A viewer raised a hand on MY card — only the presenter counts hands.
            guard let raiser = data["username"] as? String, !raiser.isEmpty,
                  let mine = bizCard, mine.presenterUserId.lowercased() == myUserID else { return }
            if !bizInterested.contains(raiser) {
                bizInterested.append(raiser)
                showScheduleToast("\u{1F44B} @\(raiser) is interested in \(mine.company)")
            }
        case "ember-share":
            guard let text = data["text"] as? String,
                  !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            let name = (data["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "someone"
            sharedEmber = WhisperSharedEmberAnswer(name: name, text: text)
            sharedEmberTask?.cancel()
            sharedEmberTask = Task {
                try? await Task.sleep(for: .seconds(25))
                guard !Task.isCancelled else { return }
                sharedEmber = nil
            }
        case "client-vitals":
            // A participant's Whisper app is streaming live heart rate.
            let uid = ((data["userId"] as? String) ?? "").lowercased()
            let bpm: Int
            if let value = data["bpm"] as? Double {
                bpm = Int(value.rounded())
            } else if let value = data["bpm"] as? Int {
                bpm = value
            } else {
                bpm = 0
            }
            guard !uid.isEmpty, uid != myUserID, bpm > 0, bpm <= 250 else { return }
            heartRates[uid] = bpm
        case "schedule-suggest":
            // Someone else's voice mentioned a concrete date — mirror the
            // same "add to shared calendar?" prompt so the room stays in sync.
            let uid = ((data["byUserId"] as? String) ?? "").lowercased()
            guard !uid.isEmpty, uid != myUserID else { return }
            let ms: Double
            if let value = data["dateMs"] as? Double {
                ms = value
            } else if let value = data["dateMs"] as? Int {
                ms = Double(value)
            } else {
                return
            }
            let date = Date(timeIntervalSince1970: ms / 1000)
            guard date > Date().addingTimeInterval(5 * 60) else { return }
            let bucket = Int(date.timeIntervalSince1970 / 600)
            guard !handledScheduleBuckets.contains(bucket) else { return }
            handledScheduleBuckets.insert(bucket)
            presentScheduleSuggestion(
                date: date,
                snippet: (data["snippet"] as? String) ?? "",
                eventType: (data["eventType"] as? String) ?? "meet",
                bucket: bucket
            )
        case "dating-card":
            // Blind dating — someone announced their dating card; the first
            // card in the room lights date mode for everyone, and everyone
            // answers with their own (an empty card still announces you).
            guard let card = WhisperSpeedDating.WireCard.decode(data),
                  card.userId.lowercased() != myUserID else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                datingCards[card.userId.lowercased()] = card
                speedDateActive = true
            }
            if blind.partnerUserID.isEmpty {
                blind.partnerUserID = card.userId.lowercased()
                blind.partnerName = card.username
            }
            broadcastMyDatingCard()
            startBlindClockLoopIfNeeded()
            // The invited side gets the custom welcome takeover — the
            // starter already said "I'm ready" in the Dating hub's lobby.
            if !WhisperSpeedDating.pendingRooms.contains(meeting.id.lowercased()), !speedDateWelcomeSeen {
                speedDateWelcomeSeen = true
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { speedDateWelcomeVisible = true }
            }
        case "dating-verdict":
            // Legacy in-room verdict — Jasper's read lives on the wrap now.
            break
        case WhisperBlindDate.Wire.ready:
            guard ((data["userId"] as? String) ?? "").lowercased() != myUserID else { return }
            blind.theirReady = true
            maybeStartBlindClock()
        case WhisperBlindDate.Wire.state:
            // Their clock is running → they're ready by definition; converge
            // on the earliest start / longest duration / any reveal.
            let wasRevealed = blind.revealed
            blind.theirReady = true
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { blind.adoptState(data) }
            if blind.revealed, !wasRevealed { Haptics.success() }
        case WhisperBlindDate.Wire.reveal:
            guard ((data["userId"] as? String) ?? "").lowercased() != myUserID else { return }
            blind.theirRevealTapped = true
            if blind.myRevealTapped { revealNow(broadcast: true) }
        case WhisperBlindDate.Wire.extend:
            guard ((data["userId"] as? String) ?? "").lowercased() != myUserID else { return }
            let round = (data["round"] as? Int) ?? Int((data["round"] as? Double) ?? 0)
            blind.theirExtendRound = max(blind.theirExtendRound, round)
            resolveExtension()
        case WhisperBlindDate.Wire.prompts:
            guard let lines = data["prompts"] as? [String] else { return }
            let stamp = (data["at"] as? Double) ?? 0
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { blind.adoptDeck(lines: lines, at: stamp) }
        case WhisperBlindDate.Wire.promptIndex:
            guard ((data["byUserId"] as? String) ?? "").lowercased() != myUserID else { return }
            let idx = (data["index"] as? Int) ?? Int((data["index"] as? Double) ?? 0)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                blind.promptIndex = max(0, min(idx, max(0, blind.deck.count - 1)))
            }
        case WhisperBlindDate.Wire.left:
            guard ((data["userId"] as? String) ?? "").lowercased() != myUserID else { return }
            blind.partnerLeft = true
            Task { await finishBlindDate(partnerLeft: true) }
        // ── Meeting lifecycle (Meet's rules, shared wire with web) ──
        case "call-end":
            // The host ended the call for everyone.
            let byName = (data["byName"] as? String) ?? "The host"
            showScheduleToast("\(byName) ended the meeting")
            WhisperMeetChime.playEnd()
            Task { await handleRemoteEnd() }
        case "call-host":
            // The host left without ending — the room was handed to someone.
            let uid = ((data["userId"] as? String) ?? "").lowercased()
            guard !uid.isEmpty else { return }
            actingHostUserID = uid
            if uid == myUserID {
                showScheduleToast("You're the host now — the previous host left")
            } else if let name = data["name"] as? String, !name.isEmpty {
                showScheduleToast("\(name) is the host now")
            }
        // ── Meet's in-room grammar (WhisperCallService speaks the same names) ──
        case "call-chat":
            let text = ((data["text"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let rawID = (data["id"] as? String) ?? ""
            let id = rawID.isEmpty ? "\(Int(Date().timeIntervalSince1970 * 1000))-\(fromPeerId)" : rawID
            guard !roomChat.contains(where: { $0.id == id }) else { return }
            let name = (data["byName"] as? String) ?? "someone"
            let at: Date = (data["at"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
            roomChat.append(MeetRoomChatMessage(id: id, name: name, text: text, at: at, isSelf: false))
            if roomChat.count > 200 { roomChat.removeFirst(roomChat.count - 200) }
            if !showRoomChat { chatUnread += 1 }
        case "call-policy":
            if let chat = data["chat"] as? Bool { roomPolicy.chat = chat }
            if let reactions = data["reactions"] as? Bool { roomPolicy.reactions = reactions }
            if let present = data["present"] as? Bool { roomPolicy.present = present }
            if let quickAccess = data["quickAccess"] as? Bool { roomPolicy.quickAccess = quickAccess }
        // ── Knocking (Meet's "wants to join this call") — the doorkeeper answers ──
        case "meeting-knock":
            guard isDoorkeeper else { return }
            let knockId = (data["knockId"] as? String) ?? ""
            guard !knockId.isEmpty else { return }
            let rawName = ((data["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let knock = MeetKnock(
                knockId: knockId,
                name: rawName.isEmpty ? "Someone" : rawName,
                avatarURL: data["avatarUrl"] as? String,
                isGuest: (data["isGuest"] as? Bool) ?? true,
                at: (data["at"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
            )
            // "Asking to join…" on their side the moment a host is reached.
            WhisperLiveRTCService.shared.sendAppEvent("meeting-knock-ack", data: ["knockId": knockId, "byName": myDisplayName])
            // Quick access: signed-in members walk straight in. Guests always wait.
            if roomPolicy.quickAccess && !knock.isGuest {
                WhisperLiveRTCService.shared.sendAppEvent("meeting-admit", data: ["knockId": knockId, "byName": myDisplayName])
                return
            }
            let alreadyKnown = pendingKnocks.contains { $0.knockId == knockId }
            pendingKnocks.removeAll { $0.knockId == knockId || Date().timeIntervalSince($0.at) > 200 }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                pendingKnocks.append(knock)
            }
            // The doorkeeper hears the SAME tiny tick web plays for a knock —
            // the join chime is reserved for someone actually landing.
            if !alreadyKnown { WhisperMeetChime.playTick() }
        case "meeting-knock-cancel", "meeting-admit", "meeting-deny":
            // The knocker left, or another host already answered — drop the row.
            let knockId = (data["knockId"] as? String) ?? ""
            guard !knockId.isEmpty else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                pendingKnocks.removeAll { $0.knockId == knockId }
            }
        case "call-react":
            let emoji = (data["emoji"] as? String) ?? "\u{1F496}"
            let name = (data["byName"] as? String) ?? "someone"
            pushFloatingReaction(emoji: emoji, name: name)
        case "call-hand":
            let up = (data["up"] as? Bool) ?? false
            let uid = ((data["userId"] as? String) ?? "").lowercased()
            guard !uid.isEmpty else { return }
            let name = (data["byName"] as? String) ?? "Someone"
            if up {
                raisedHands[uid] = name
                if uid != myUserID { showScheduleToast("\u{270B} \(name) raised a hand") }
            } else {
                raisedHands.removeValue(forKey: uid)
            }
        case "call-mute":
            let target = ((data["targetUserId"] as? String) ?? "").lowercased()
            guard !target.isEmpty, target == myUserID, !isHost else { return }
            micOn = false
            WhisperLiveRTCService.shared.setMuted(true)
            showScheduleToast("The host muted your microphone")
        case "call-mute-all":
            guard !isHost else { return }
            micOn = false
            WhisperLiveRTCService.shared.setMuted(true)
            let name = (data["byName"] as? String) ?? "The host"
            showScheduleToast("\(name) muted everyone")
        case "meeting-kick":
            // The host removed someone — if it's ME, say so and leave
            // gracefully (same wire + payload shape as web).
            let targetUser = ((data["targetUserId"] as? String) ?? "").lowercased()
            let targetPeer = (data["targetPeerId"] as? String) ?? ""
            let myPeer = WhisperLiveRTCService.shared.localPeerId
            if (!targetUser.isEmpty && targetUser == myUserID)
                || (!targetPeer.isEmpty && targetPeer == myPeer) {
                showScheduleToast("You were removed from the meeting")
                Task {
                    await leave()
                    requestClose()
                }
            } else {
                let service = WhisperLiveRTCService.shared
                let targets = service.participants.filter {
                    !targetPeer.isEmpty ? $0.peerId == targetPeer : (!targetUser.isEmpty && $0.userId.lowercased() == targetUser)
                }
                for participant in targets { service.forgetParticipant(participant.peerId) }
            }
        default:
            break
        }
    }

    // MARK: - Speed dating (cupid Jasper judges the match)

    @State private var speedDateActive: Bool = false
    @State private var datingCards: [String: WhisperSpeedDating.WireCard] = [:]
    @State private var datingCardShared: Bool = false
    @State private var datingHeartbeatTask: Task<Void, Never>? = nil
    /// Guest welcome takeover — the custom speed-date JOIN screen for the
    /// invited side; the starter saw the lobby in the Dating hub instead.
    @State private var speedDateWelcomeVisible: Bool = false
    @State private var speedDateWelcomeSeen: Bool = false
    @State private var showRoomDatingCardEditor: Bool = false
    /// The blind-date session — shared clock, curtain/reveal, extensions, deck.
    @State private var blind = WhisperBlindDateSession()
    @State private var blindClockTask: Task<Void, Never>? = nil
    @State private var blindDeckRequested: Bool = false
    @State private var blindLeaving: Bool = false
    /// Set when the date ends (time's up, END, or they left) — shows the wrap.
    @State private var blindWrap: BlindWrapContext? = nil

    private struct BlindWrapContext {
        let partnerUserID: String
        let partnerName: String
        let partnerAvatarURL: URL?
        let transcript: String
        let theirCard: WhisperSpeedDating.WireCard?
        let revealed: Bool
        let partnerLeft: Bool
        let elapsedSec: Int
    }

    /// The starter (or a queue-paired dater) primed this room from the
    /// Dating hub — light up, announce my card, and start the readiness
    /// handshake; link guests light up when the first card arrives.
    private func primeSpeedDateIfPending() {
        let roomID = meeting.id.lowercased()
        guard WhisperSpeedDating.pendingRooms.contains(roomID) else { return }
        speedDateActive = true
        if let partner = WhisperBlindDate.pairedPartners[roomID] { blind.partnerName = partner }
        // The lobby's "Enter the date" already marked me ready; queue-paired
        // dates show the welcome takeover to both people first.
        if WhisperBlindDate.readyRooms.contains(roomID) {
            blind.myReady = true
            speedDateWelcomeSeen = true
        } else if !speedDateWelcomeSeen {
            speedDateWelcomeSeen = true
            speedDateWelcomeVisible = true
        }
        let source = WhisperBlindDate.pairedPartners[roomID] != nil ? "queue" : "invite"
        Task { await WhisperBlindDate.openRecord(roomCode: roomID, source: source) }
        broadcastMyDatingCard()
        startBlindClockLoopIfNeeded()
    }

    // MARK: - Blind date — the stage, the clock, the wire

    /// The curtain over the video before the reveal, a slim HUD after —
    /// mounted above the stage, below the chrome.
    private func blindDateStage(inset: UIEdgeInsets, controlsBottom: CGFloat) -> some View {
        let localId = WhisperLiveRTCService.shared.localPeerId
        let partner = participants.first { $0.peerId != localId }
        let fallbackName = blind.partnerName.isEmpty ? (datingCards.values.first?.username ?? "your date") : blind.partnerName
        return WhisperBlindDateStageView(
            session: blind,
            myName: presenterDisplayName,
            myAvatarURL: tileAvatars[myUserID],
            partnerName: partner?.name ?? fallbackName,
            partnerAvatarURL: partner.flatMap { tileAvatars[$0.userId.lowercased()] },
            topInset: inset.top,
            bottomInset: controlsBottom,
            onReveal: { blindTapReveal() },
            onExtend: { blindTapExtend() },
            onPrompt: { delta in blindStepPrompt(delta) }
        )
    }

    /// The half-second heartbeat that runs the date: readiness handshake,
    /// shared-clock convergence, auto-reveal at the mark, the deck, time's up.
    private func startBlindClockLoopIfNeeded() {
        guard blindClockTask == nil else { return }
        blindClockTask = Task {
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                guard speedDateActive, blindWrap == nil, !blindLeaving else { continue }
                tick += 1
                if blind.startedAt == nil {
                    if blind.myReady, tick % 4 == 0 {
                        WhisperLiveRTCService.shared.sendAppEvent(WhisperBlindDate.Wire.ready, data: ["userId": myUserID])
                    }
                    maybeStartBlindClock()
                    continue
                }
                if tick % 10 == 0 {
                    WhisperLiveRTCService.shared.sendAppEvent(WhisperBlindDate.Wire.state, data: blind.statePayload())
                }
                if tick % 20 == 0, !blind.deck.isEmpty, blind.deckAt > 0 {
                    WhisperLiveRTCService.shared.sendAppEvent(WhisperBlindDate.Wire.prompts, data: [
                        "prompts": WhisperBlindDate.encodeDeck(blind.deck),
                        "byUserId": myUserID,
                        "at": blind.deckAt
                    ])
                }
                if !blind.revealed, blind.elapsed >= Double(blind.revealAtSec) {
                    revealNow(broadcast: false)
                }
                if !blindDeckRequested {
                    blindDeckRequested = true
                    Task { await buildBlindDeck() }
                }
                if !blind.timeUp, blind.remaining <= 0 {
                    blind.timeUp = true
                    Haptics.success()
                    try? await Task.sleep(for: .milliseconds(1400))
                    await finishBlindDate(partnerLeft: false)
                    return
                }
            }
        }
    }

    /// Both ready + no clock yet → start it and publish (the other side
    /// adopts the earliest start, so two starts converge).
    private func maybeStartBlindClock() {
        guard speedDateActive, blind.startedAt == nil, blind.myReady, blind.theirReady else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { blind.start() }
        WhisperLiveRTCService.shared.sendAppEvent(WhisperBlindDate.Wire.state, data: blind.statePayload())
        Haptics.tap()
    }

    /// ONE AI call for the deck — the lexicographically smaller user id
    /// generates and broadcasts; the other side waits, then falls back to
    /// the static deck so nobody stares at an empty card.
    private func buildBlindDeck() async {
        let partnerID = blind.partnerUserID
        let iGenerate = partnerID.isEmpty || myUserID < partnerID
        if iGenerate {
            let deck = await WhisperBlindDate.generateDeck(
                myName: presenterDisplayName,
                myCard: WhisperSpeedDating.loadCard(),
                theirCard: datingCards.values.first,
                meetingTitle: currentMeeting.title
            )
            guard blind.deck.isEmpty else { return }
            let stamp = Date().timeIntervalSince1970 * 1000
            let lines = WhisperBlindDate.encodeDeck(deck)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { blind.adoptDeck(lines: lines, at: stamp) }
            WhisperLiveRTCService.shared.sendAppEvent(WhisperBlindDate.Wire.prompts, data: [
                "prompts": lines, "byUserId": myUserID, "at": stamp
            ])
        } else {
            try? await Task.sleep(for: .seconds(12))
            guard blind.deck.isEmpty else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                blind.adoptDeck(lines: WhisperBlindDate.encodeDeck(WhisperBlindDate.fallbackDeck), at: Date().timeIntervalSince1970 * 1000)
            }
        }
    }

    private func blindTapReveal() {
        guard !blind.myRevealTapped, blind.startedAt != nil else { return }
        blind.myRevealTapped = true
        WhisperLiveRTCService.shared.sendAppEvent(WhisperBlindDate.Wire.reveal, data: ["userId": myUserID])
        if blind.theirRevealTapped { revealNow(broadcast: true) }
    }

    private func revealNow(broadcast: Bool) {
        guard !blind.revealed else { return }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { blind.revealed = true }
        if broadcast {
            WhisperLiveRTCService.shared.sendAppEvent(WhisperBlindDate.Wire.state, data: blind.statePayload())
        }
    }

    private func blindTapExtend() {
        guard blind.canExtend else { return }
        let round = blind.extensions + 1
        guard blind.myExtendRound < round else { return }
        blind.myExtendRound = round
        WhisperLiveRTCService.shared.sendAppEvent(WhisperBlindDate.Wire.extend, data: ["userId": myUserID, "round": round])
        resolveExtension()
    }

    /// An extension lands only when BOTH asked for the same round.
    private func resolveExtension() {
        let round = blind.extensions + 1
        guard blind.myExtendRound >= round, blind.theirExtendRound >= round else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { blind.applyExtension() }
        Haptics.success()
        WhisperLiveRTCService.shared.sendAppEvent(WhisperBlindDate.Wire.state, data: blind.statePayload())
    }

    private func blindStepPrompt(_ delta: Int) {
        guard !blind.deck.isEmpty else { return }
        let next = max(0, min(blind.promptIndex + delta, blind.deck.count - 1))
        guard next != blind.promptIndex else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { blind.promptIndex = next }
        WhisperLiveRTCService.shared.sendAppEvent(WhisperBlindDate.Wire.promptIndex, data: ["index": next, "byUserId": myUserID])
    }

    /// Ends the date on this side — announces it, leaves the call, pulls the
    /// transcript, and lands on the WRAP (decision + Jasper's recap).
    private func finishBlindDate(partnerLeft: Bool) async {
        guard !blindLeaving, blindWrap == nil else { return }
        blindLeaving = true
        let localId = WhisperLiveRTCService.shared.localPeerId
        let partner = participants.first { $0.peerId != localId }
        var partnerID = (partner?.userId ?? "").lowercased()
        if partnerID.isEmpty { partnerID = blind.partnerUserID }
        if partnerID.isEmpty { partnerID = datingCards.keys.first ?? "" }
        let partnerName = partner?.name
            ?? (blind.partnerName.isEmpty ? (datingCards.values.first?.username ?? "your date") : blind.partnerName)
        let context = BlindWrapContext(
            partnerUserID: partnerID,
            partnerName: partnerName,
            partnerAvatarURL: tileAvatars[partnerID],
            transcript: "",
            theirCard: datingCards[partnerID] ?? datingCards.values.first,
            revealed: blind.revealed,
            partnerLeft: partnerLeft,
            elapsedSec: Int(blind.elapsed)
        )
        if !partnerLeft {
            WhisperLiveRTCService.shared.sendAppEvent(WhisperBlindDate.Wire.left, data: ["userId": myUserID])
            try? await Task.sleep(for: .milliseconds(250))
        }
        blindClockTask?.cancel()
        blindClockTask = nil
        datingHeartbeatTask?.cancel()
        await leave()
        let transcript = await WhisperMeetingService.shared.fetchTranscriptPlain(meetingID: meeting.id)
        withAnimation(.easeInOut(duration: 0.3)) {
            blindWrap = BlindWrapContext(
                partnerUserID: context.partnerUserID,
                partnerName: context.partnerName,
                partnerAvatarURL: context.partnerAvatarURL,
                transcript: transcript,
                theirCard: context.theirCard,
                revealed: context.revealed,
                partnerLeft: context.partnerLeft,
                elapsedSec: context.elapsedSec
            )
        }
        blindLeaving = false
    }

    /// Sends my saved dating card onto the wire (once + a 12s heartbeat so
    /// late joiners always catch it). No saved card → nothing to send.
    private func broadcastMyDatingCard() {
        guard speedDateActive, !datingCardShared else { return }
        guard let payload = WhisperSpeedDating.myWirePayload(userId: myUserID, username: presenterDisplayName) else { return }
        datingCardShared = true
        WhisperLiveRTCService.shared.sendAppEvent("dating-card", data: payload)
        datingHeartbeatTask?.cancel()
        datingHeartbeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled else { break }
                WhisperLiveRTCService.shared.sendAppEvent("dating-card", data: payload)
            }
        }
    }

    /// The rose full-screen WELCOME — the invited side's custom join
    /// screen for a speed date: cupid Jasper, what's about to happen,
    /// the dating-card status, and I'm-ready.
    private var speedDateWelcomeOverlay: some View {
        let rose = Color(red: 0.91, green: 0.28, blue: 0.49)
        let hasCard = WhisperSpeedDating.hasCard
        return ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.03, blue: 0.09),
                    Color(red: 0.30, green: 0.06, blue: 0.15),
                    Color(red: 0.14, green: 0.03, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            VStack(spacing: 13) {
                Spacer()
                WhisperEmberMascot(size: 88, expression: .delighted, palette: .cupidPink, smitten: true)
                Text("BLIND DATE")
                    .font(.system(size: 11, weight: .black))
                    .tracking(2.4)
                    .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.75))
                Text(WhisperBlindDate.pairedPartners[meeting.id.lowercased()].map { "It's a date with\n@\($0) 💘" }
                     ?? "You've been invited\nto a blind date 💘")
                    .font(.system(size: 27, weight: .black))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                Text("Five minutes. You'll hear each other first — cameras stay behind the curtain until you both reveal (or at the two-minute mark). Jasper hosts with prompts built from both your cards.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 34)
                HStack(spacing: 6) {
                    Image(systemName: hasCard ? "checkmark.seal.fill" : "pencil.and.outline")
                        .font(.system(size: 11, weight: .bold))
                    Text(hasCard ? "Your dating card is ready" : "No dating card yet")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(hasCard ? Color(red: 0.64, green: 0.98, blue: 0.80) : .white.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(.white.opacity(0.10)))
                Button {
                    Haptics.tap()
                    showRoomDatingCardEditor = true
                } label: {
                    Text(hasCard ? "Edit my card" : "Fill my card")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(.white.opacity(0.14)))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    Haptics.tap()
                    blind.myReady = true
                    WhisperLiveRTCService.shared.sendAppEvent(WhisperBlindDate.Wire.ready, data: ["userId": myUserID])
                    maybeStartBlindClock()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        speedDateWelcomeVisible = false
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text("I'm ready 💘")
                            .font(.system(size: 16, weight: .black))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [rose, Color(red: 0.98, green: 0.45, blue: 0.62)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    )
                    .shadow(color: rose.opacity(0.4), radius: 14, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 36)
                .padding(.bottom, 34)
            }
        }
        .sheet(isPresented: $showRoomDatingCardEditor, onDismiss: {
            // The card may be brand new — put it on the wire for the
            // other side of the date.
            datingCardShared = false
            broadcastMyDatingCard()
        }) {
            WhisperDatingCardEditorSheet()
        }
    }

    /// Host-only: broadcast a kick for a participant, with a local toast.
    private func kickParticipant(_ p: WhisperLiveRTCService.ParticipantInfo) {
        guard isHost, p.peerId != WhisperLiveRTCService.shared.localPeerId else { return }
        Haptics.tap()
        WhisperLiveRTCService.shared.sendAppEvent("meeting-kick", data: [
            "targetUserId": p.userId,
            "targetPeerId": p.peerId
        ])
        WhisperLiveRTCService.shared.forgetParticipant(p.peerId)
        showScheduleToast("Removed \(p.name) from the meeting")
    }

    /// Broadcasts a presented-client payload and (re)starts the heartbeat
    /// re-broadcast so late joiners see it too. Shared by the recruiter's
    /// prospect presenting and the coach's client presenting.
    private func beginPresentation(_ payload: WhisperPresentedClient) {
        presentation = payload
        presentationExpanded = false
        presentBeat = Date()
        let dict = payload.encodeToDict()
        WhisperLiveRTCService.shared.sendAppEvent("present-client", data: dict)
        presentHeartbeatTask?.cancel()
        presentHeartbeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { break }
                WhisperLiveRTCService.shared.sendAppEvent("present-client", data: dict)
            }
        }
    }

    private var presenterDisplayName: String {
        LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "presenter"
    }

    /// Recruiter: pin a prospect's phone-shaped card into everyone's call.
    private func startPresenting(_ prospect: WhisperRecruiterService.ProspectRow) {
        var payload = WhisperMeetingCompanion.presentedClient(
            from: prospect,
            presenterUserId: myUserID,
            presenterName: presenterDisplayName
        )
        payload.rev = Date().timeIntervalSince1970 * 1000
        beginPresentation(payload)
        showRecruiterTools = false
    }

    /// Coach: pin one of their active clients into everyone's call, then
    /// enrich the card with the client's live fitness snapshot, progress
    /// photos and profile picture — the iOS twin of web's presentCoachClient.
    private func startPresentingClient(_ request: WhisperCoachRequestRow) {
        var payload = WhisperMeetingCompanion.presentedCoachClient(
            from: request,
            presenterUserId: myUserID,
            presenterName: presenterDisplayName
        )
        payload.rev = Date().timeIntervalSince1970 * 1000
        beginPresentation(payload)
        showCoachTools = false
        Task {
            var enriched = payload
            if let row = await WhisperClientSnapshotService.shared.fetchSnapshot(forClient: request.client_user_id) {
                if let snap = row.payload {
                    enriched.snapshot = WhisperMeetingCompanion.presentationSnapshot(from: snap)
                }
                enriched.photos = [row.photo_front_url, row.photo_side_url, row.photo_back_url]
                    .compactMap { $0 }
            }
            let profiles = await WhisperBackendService.shared.fetchPublicProfiles(userIDs: [request.client_user_id])
            if let profile = profiles[request.client_user_id.lowercased()] ?? profiles[request.client_user_id] {
                enriched.imageUrl = profile.profile_image_url
            }
            // Only re-broadcast if this presentation is still on stage.
            guard presentation?.id == enriched.id else { return }
            enriched.rev = Date().timeIntervalSince1970 * 1000
            beginPresentation(enriched)
        }
    }

    private func stopPresenting() {
        presentHeartbeatTask?.cancel()
        presentHeartbeatTask = nil
        WhisperLiveRTCService.shared.sendAppEvent("present-client-end", data: ["presenterUserId": myUserID])
        presentation = nil
        presentationExpanded = false
    }

    /// Creator: pin YOUR live analytics card into everyone's call — same
    /// heartbeat re-broadcast as presenting a client, so late joiners see it.
    private func startPresentingAnalytics(_ card: WhisperCreatorAnalyticsCard) {
        // Stamp identity with the SAME uid receivers verify (the tools sheet
        // builds with a legacy local id that can drift from the auth uid) and
        // clamp non-finite numbers — either one used to make every receiver
        // silently drop the share while the presenter still saw their card.
        var payload = card.wireSafe(presenterUserId: myUserID, presenterName: presenterDisplayName)
        payload.rev = Date().timeIntervalSince1970 * 1000
        withAnimation(.spring(duration: 0.4, bounce: 0.2)) { analyticsCard = payload }
        analyticsExpanded = false
        analyticsBeat = Date()
        showCreatorTools = false
        let dict = payload.encodeToDict()
        WhisperLiveRTCService.shared.sendAppEvent("creator-analytics", data: dict)
        analyticsHeartbeatTask?.cancel()
        analyticsHeartbeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { break }
                WhisperLiveRTCService.shared.sendAppEvent("creator-analytics", data: dict)
            }
        }
    }

    private func stopPresentingAnalytics() {
        analyticsHeartbeatTask?.cancel()
        analyticsHeartbeatTask = nil
        WhisperLiveRTCService.shared.sendAppEvent("creator-analytics-end", data: ["presenterUserId": myUserID])
        withAnimation(.spring(duration: 0.35)) { analyticsCard = nil }
        analyticsExpanded = false
    }

    /// The Business+ entry in the ⋯ tools menu — present the company card,
    /// the open roles, or the team roster; End when mine is live.
    @ViewBuilder
    private var businessPresentMenu: some View {
        if bizContext != nil {
            Menu {
                Button {
                    presentBusinessCard(mode: "company")
                } label: {
                    Label("Company card", systemImage: "building.2.fill")
                }
                Button {
                    presentBusinessCard(mode: "roles")
                } label: {
                    Label("We're hiring", systemImage: "briefcase.fill")
                }
                Button {
                    presentBusinessCard(mode: "team")
                } label: {
                    Label("Meet the team", systemImage: "person.3.fill")
                }
                if let mine = bizCard, mine.presenterUserId.lowercased() == myUserID {
                    Divider()
                    Button(role: .destructive) {
                        stopBusinessCard()
                    } label: {
                        Label("End company card", systemImage: "xmark.circle")
                    }
                }
            } label: {
                Label("Present company", systemImage: "plus.app.fill")
            }
        }
    }

    /// The pinned Business+ card in the top-trailing rail (mine or theirs).
    @ViewBuilder
    private var businessCardRail: some View {
        if let bizCard {
            WhisperBusinessCardOverlay(
                card: bizCard,
                isMine: bizCard.presenterUserId.lowercased() == myUserID,
                interested: bizInterested,
                handRaised: bizHandRaised,
                onInterested: { raiseBusinessHand() },
                onEnd: { stopBusinessCard() }
            )
        }
    }

    // MARK: - Business+ present (same wire as web meetings)

    /// Business+ — put the live company card on everyone's screen. Modes:
    /// "company" (identity), "roles" (open positions + apply), "team" (roster).
    private func presentBusinessCard(mode: String) {
        guard let context = bizContext, !bizBuilding else { return }
        bizBuilding = true
        Task {
            defer { bizBuilding = false }
            let card = await WhisperBusinessMeetingKit.buildCard(
                mode: mode,
                context: context,
                presenterUserId: myUserID,
                presenterName: presenterDisplayName
            )
            bizInterested = []
            bizHandRaised = false
            bizSeenRevKey = "\(card.presenterUserId.lowercased()):\(card.rev ?? 0)"
            withAnimation(.spring(duration: 0.4, bounce: 0.2)) { bizCard = card }
            WhisperLiveRTCService.shared.sendAppEvent("business-card", data: card.encodeToDict())
            showScheduleToast(
                mode == "roles"
                    ? "Presenting your open roles"
                    : mode == "team" ? "Introducing the team" : "Presenting your company"
            )
        }
    }

    /// Presenter takes the company card down for everyone.
    private func stopBusinessCard() {
        guard let mine = bizCard, mine.presenterUserId.lowercased() == myUserID else { return }
        WhisperLiveRTCService.shared.sendAppEvent("business-card-end", data: ["presenterUserId": myUserID])
        withAnimation(.spring(duration: 0.35)) { bizCard = nil }
        bizInterested = []
    }

    /// Viewer — raise a hand on the presented card: pings the presenter live
    /// and files me as a lead in their Business+ hiring pipeline (deduped).
    private func raiseBusinessHand() {
        guard let card = bizCard, !bizHandRaised else { return }
        let username = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "someone"
        WhisperLiveRTCService.shared.sendAppEvent(
            "business-interest",
            data: ["presenterUserId": card.presenterUserId, "username": username]
        )
        bizHandRaised = true
        Haptics.tap()
        if let businessId = card.businessId, !businessId.isEmpty, !bizLeadSent.contains(businessId) {
            bizLeadSent.insert(businessId)
            let uid = myUserID
            let company = card.company
            Task {
                await WhisperBusinessMeetingKit.recordMeetingInterest(
                    businessId: businessId,
                    userId: uid,
                    username: username,
                    company: company
                )
            }
        }
        showScheduleToast("\u{1F44B} Sent — @\(card.presenterName) sees your hand")
    }

    /// Viewer hygiene — clear the card when the presenter's heartbeat stops.
    private func startPresentWatch() {
        presentWatchTask?.cancel()
        presentWatchTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }
                if let current = presentation,
                   current.presenterUserId.lowercased() != myUserID,
                   Date().timeIntervalSince(presentBeat) > 13 {
                    presentation = nil
                    presentationExpanded = false
                }
                if let card = analyticsCard,
                   card.presenterUserId.lowercased() != myUserID,
                   Date().timeIntervalSince(analyticsBeat) > 13 {
                    withAnimation(.spring(duration: 0.35)) { analyticsCard = nil }
                    analyticsExpanded = false
                }
            }
        }
    }

    // MARK: - Live prospect read (recruiter only)

    private func startLiveEvalLoop() {
        evalTask?.cancel()
        lastEvalChars = 0
        // Surface the last stored read instantly on re-entry so the pill
        // never starts blank for a prospect we've already scored.
        if liveEval == nil { liveEval = loadStoredEval() }
        evalPhase = liveEval == nil ? .listening : .ready
        evalTask = Task {
            while !Task.isCancelled {
                let full = await WhisperMeetingService.shared.fetchTranscriptPlain(meetingID: meeting.id)
                guard !Task.isCancelled else { break }
                // Score ONLY the prospect's own words — the host/recruiter's
                // pitch lines must never move the read.
                let transcript = prospectOnlyTranscript(full)
                // Credit guard: re-score only after a real chunk of NEW
                // prospect speech (300+ chars), not every few words.
                if transcript.count >= 40, transcript.count - lastEvalChars >= 300 || (liveEval == nil && transcript.count - lastEvalChars >= 60) {
                    evalPhase = .evaluating
                    let hint = presentation?.displayName ?? presentation?.username
                    if let eval = await WhisperMeetingCompanion.prospectEvaluation(transcript: transcript, hint: hint) {
                        guard !Task.isCancelled else { break }
                        lastEvalChars = transcript.count
                        liveEval = eval
                        evalUpdatedAt = Date()
                        evalPhase = .ready
                        persistEval(eval)
                    } else {
                        evalPhase = liveEval == nil ? .listening : .ready
                    }
                }
                // Jasper drafts the pitch deck once the room has said enough —
                // ONE quiet AI call; a popup invites a flip-through. The final
                // deck regenerates from the full transcript when the call ends.
                if isRecruiter, pitchDeck == nil, !deckDrafting, full.count >= 700 {
                    deckDrafting = true
                    let hint = presentation?.displayName ?? presentation?.username
                    Task {
                        let draft = await WhisperPitchDeckService.shared.generate(
                            meetingID: meeting.id,
                            meetingTitle: currentMeeting.title,
                            prospectHint: hint,
                            isDraft: true
                        )
                        deckDrafting = false
                        guard let draft else { return }
                        pitchDeck = draft
                        guard notes == nil, !showRecap else { return }
                        Haptics.tap()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { deckPopup = true }
                        try? await Task.sleep(for: .seconds(16))
                        withAnimation(.easeOut(duration: 0.25)) { deckPopup = false }
                    }
                }
                // Web parity — 30s cadence (was 10s): the read still tracks
                // the conversation but spends a third of the credits.
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    /// Shown to recruiters before the first confidence read lands — makes
    /// it obvious the live scorer is on and listening.
    private var liveEvalListeningPill: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: "waveform")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.cyan)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                Text(evalPhase == .evaluating ? "Reading the room…" : "Listening to the room…")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
                Spacer(minLength: 0)
                Button {
                    Haptics.tap()
                    liveEvalDismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss the live read for this meeting")
            }
            Text("A live prospect read — score, best placement, and confidence — appears automatically as the conversation gets going.")
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
            Text("ONLY YOU CAN SEE THIS")
                .font(.system(size: 7.5, weight: .black))
                .tracking(0.9)
                .foregroundStyle(.white.opacity(0.28))
        }
        .padding(12)
        .frame(width: 232, alignment: .leading)
        .background(Color.black.opacity(0.55), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
    }

    // MARK: - Live application capture (recruiter only)

    /// Captured answers ordered by the recruiter's question order.
    private var sortedCapturedAnswers: [WhisperCapturedApplicationAnswer] {
        appCaptureQuestions.compactMap { appCaptureAnswers[$0.id] }
    }

    private var captureDraftKey: String { "whisper_meeting_appcap:\(meeting.id)" }

    /// While ON, Jasper re-reads the transcript every ~25s and fills in any
    /// application questions the prospect answered aloud — mirrors web.
    private func startApplicationCapture() {
        guard isRecruiter else { return }
        appCaptureTask?.cancel()
        appCaptureTask = Task {
            if appCaptureQuestions.isEmpty {
                appCaptureQuestions = await loadApplicantQuestions()
            }
            restoreCaptureDraft()
            while !Task.isCancelled && appCaptureOn {
                await captureTick()
                try? await Task.sleep(for: .seconds(25))
            }
        }
    }

    private func stopApplicationCapture() {
        appCaptureTask?.cancel()
        appCaptureTask = nil
        appCaptureBusy = false
    }

    private func captureTick() async {
        guard !appCaptureBusy, !appCaptureQuestions.isEmpty else { return }
        let transcript = await WhisperMeetingService.shared.fetchTranscriptPlain(meetingID: meeting.id)
        guard !Task.isCancelled, appCaptureOn else { return }
        guard transcript.count >= 80, transcript.count - appCaptureChars >= 60 else { return }
        appCaptureBusy = true
        let found = await WhisperMeetingCompanion.extractApplicationAnswers(
            questions: appCaptureQuestions.map { ($0.id, $0.question) },
            transcript: transcript
        )
        appCaptureBusy = false
        guard !Task.isCancelled else { return }
        appCaptureChars = transcript.count
        guard !found.isEmpty else { return }
        for (qid, answer) in found {
            guard let question = appCaptureQuestions.first(where: { $0.id == qid }) else { continue }
            appCaptureAnswers[qid] = WhisperCapturedApplicationAnswer(
                id: qid,
                question: question.question,
                answer: answer
            )
        }
        persistCaptureDraft()
    }

    /// Draft survives leaving the meeting — same behavior as web's
    /// localStorage draft, keyed per meeting.
    private func persistCaptureDraft() {
        var answers: [String: [String: String]] = [:]
        for (qid, pair) in appCaptureAnswers {
            answers[qid] = ["question": pair.question, "answer": pair.answer]
        }
        let payload: [String: Any] = ["name": appCaptureName, "answers": answers]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            UserDefaults.standard.set(data, forKey: captureDraftKey)
        }
    }

    private func restoreCaptureDraft() {
        guard appCaptureAnswers.isEmpty,
              let data = UserDefaults.standard.data(forKey: captureDraftKey),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let name = json["name"] as? String, appCaptureName.isEmpty {
            appCaptureName = name
        }
        if let answers = json["answers"] as? [String: [String: String]] {
            for (qid, pair) in answers {
                guard let question = pair["question"], let answer = pair["answer"] else { continue }
                appCaptureAnswers[qid] = WhisperCapturedApplicationAnswer(
                    id: qid,
                    question: question,
                    answer: answer
                )
            }
        }
    }

    private func loadApplicantQuestions() async -> [WhisperApplicantQuestion] {
        do {
            let data = try await SupabaseService.shared.client
                .from("whisper_applicant_questions")
                .select("*")
                .eq("is_active", value: true)
                .order("display_order", ascending: true)
                .execute()
                .data
            return (try? JSONDecoder().decode([WhisperApplicantQuestion].self, from: data)) ?? []
        } catch {
            print("[WhisperMeeting] questions load error: \(error)")
            return []
        }
    }

    /// Files the captured answers as a real applicant response — scored with
    /// the same position-match engine as the QR questionnaire.
    private func fileCapturedApplication() {
        guard !appCaptureSaving, !appCaptureAnswers.isEmpty else { return }
        appCaptureSaving = true
        Task {
            defer { appCaptureSaving = false }
            let recruiter = WhisperRecruiterService.shared
            if recruiter.referralCode == nil {
                await recruiter.refreshReferralCode()
            }
            guard let code = recruiter.referralCode?.code else {
                Haptics.warning()
                return
            }
            var answerMap: [String: [String: String]] = [:]
            for (qid, pair) in appCaptureAnswers {
                answerMap[qid] = ["question": pair.question, "answer": pair.answer]
            }
            let match = WhisperApplicantScoring.computePositionMatch(answerMap)
            let trimmedName = appCaptureName.trimmingCharacters(in: .whitespacesAndNewlines)
            let payload: [String: AnyJSON] = [
                "recruiter_code": .string(code.uppercased()),
                "applicant_name": .string(trimmedName.isEmpty ? "\(currentMeeting.title) prospect" : trimmedName),
                "answers": AnyJSON.object(answerMap.mapValues { val in
                    AnyJSON.object(val.mapValues { AnyJSON.string($0) })
                }),
                "status": .string("submitted"),
                "best_position": .string(match.bestPosition),
                "position_scores": AnyJSON.object(match.positionScores.mapValues { AnyJSON.double($0) }),
                "potential_score": .double(Double(match.potentialScore)),
                "confidence_score": .double(Double(match.confidenceScore)),
            ]
            do {
                _ = try await SupabaseService.shared.client
                    .from("whisper_applicant_responses")
                    .insert(payload)
                    .execute()
                Haptics.success()
                appCaptureSavedAt = Date()
                persistCaptureDraft()
            } catch {
                Haptics.warning()
                print("[WhisperMeeting] file application error: \(error)")
            }
        }
    }

    private func persistEval(_ eval: WhisperProspectEval) {
        if let data = try? JSONEncoder().encode(eval) {
            UserDefaults.standard.set(data, forKey: "whisper_meeting_eval:\(meeting.id)")
        }
    }

    private func loadStoredEval() -> WhisperProspectEval? {
        guard let data = UserDefaults.standard.data(forKey: "whisper_meeting_eval:\(meeting.id)") else { return nil }
        return try? JSONDecoder().decode(WhisperProspectEval.self, from: data)
    }

    /// Position match computed live from Jasper's captured application
    /// answers — the same scoring engine as the QR questionnaire, so the
    /// potential score in-meeting equals the filed applicant's score.
    private var liveApplicationMatch: WhisperApplicantScoring.PositionMatch? {
        guard !appCaptureAnswers.isEmpty else { return nil }
        var map: [String: [String: String]] = [:]
        for (qid, pair) in appCaptureAnswers {
            map[qid] = ["question": pair.question, "answer": pair.answer]
        }
        return WhisperApplicantScoring.computePositionMatch(map)
    }

    /// Compact auto-match strip inside the live read card — the potential
    /// score + best position from the live-captured application answers.
    private func autoMatchStrip(_ match: WhisperApplicantScoring.PositionMatch) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "person.text.rectangle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 1) {
                Text("AUTO-MATCH \(match.potentialScore)/100")
                    .font(.system(size: 10.5, weight: .black))
                    .foregroundStyle(.white)
                Text("\(match.bestPosition.uppercased()) \u{00B7} \(sortedCapturedAnswers.count) ANSWER\(sortedCapturedAnswers.count == 1 ? "" : "S") CAPTURED")
                    .font(.system(size: 7.5, weight: .black))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 0)
            if appCaptureBusy {
                ProgressView().controlSize(.mini).tint(.cyan)
            }
        }
        .padding(8)
        .background(Color.cyan.opacity(0.10), in: .rect(cornerRadius: 10))
    }

    /// Post-meeting application auto-match card — the potential score,
    /// confidence, and best-position match Jasper computed from the answers
    /// it captured live during the call.
    @ViewBuilder
    private var notesAutoMatchCard: some View {
        if let match = liveApplicationMatch {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "person.text.rectangle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.cyan)
                    Text("APPLICATION AUTO-MATCH")
                        .font(.system(size: 10, weight: .black))
                        .tracking(1.2)
                        .foregroundStyle(.cyan)
                    Spacer(minLength: 0)
                    if appCaptureSavedAt != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("FILED")
                                .font(.system(size: 8, weight: .black))
                                .tracking(0.8)
                        }
                        .foregroundStyle(.green)
                    }
                }
                HStack(alignment: .center, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(match.potentialScore)")
                            .font(.system(size: 38, weight: .black))
                            .foregroundStyle(.white)
                        Text("/100")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.12))
                                Capsule()
                                    .fill(scoreTint(match.potentialScore))
                                    .frame(width: g.size.width * min(1, max(0.04, Double(match.potentialScore) / 100)))
                            }
                        }
                        .frame(height: 6)
                        Text("POTENTIAL SCORE \u{00B7} \(match.confidenceScore)% ANSWER CONFIDENCE")
                            .font(.system(size: 8, weight: .black))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("BEST POSITION MATCH")
                        .font(.system(size: 8, weight: .black))
                        .tracking(1.0)
                        .foregroundStyle(.white.opacity(0.4))
                    placementChips(match.bestPosition)
                }
                Text("\(sortedCapturedAnswers.count) answer\(sortedCapturedAnswers.count == 1 ? "" : "s") captured live by Jasper during the call.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                if !appCaptureQuestions.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("APPLICATION QUESTIONS")
                            .font(.system(size: 8, weight: .black))
                            .tracking(1.0)
                            .foregroundStyle(.white.opacity(0.4))
                        ForEach(appCaptureQuestions, id: \.id) { q in
                            let captured = appCaptureAnswers[q.id]
                            HStack(alignment: .top, spacing: 7) {
                                Image(systemName: captured != nil ? "checkmark.circle.fill" : "circle.dotted")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(captured != nil ? Color(red: 0.20, green: 0.83, blue: 0.60) : .white.opacity(0.30))
                                    .padding(.top, 1)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(q.question)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white.opacity(captured != nil ? 0.9 : 0.55))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(captured?.answer ?? "Not captured yet")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(captured != nil ? .cyan.opacity(0.9) : .white.opacity(0.35))
                                        .lineLimit(3)
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 12))
                }
                if appCaptureSavedAt == nil {
                    Button {
                        Haptics.tap()
                        fileCapturedApplication()
                    } label: {
                        HStack(spacing: 6) {
                            if appCaptureSaving {
                                ProgressView().controlSize(.small).tint(.black)
                            } else {
                                Image(systemName: "tray.and.arrow.down.fill")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            Text("File to my applicants")
                                .font(.system(size: 13, weight: .heavy))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.cyan, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(appCaptureSaving)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.cyan.opacity(0.08), in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.cyan.opacity(0.25), lineWidth: 1)
            }
        }
    }

    /// Drops the host's and my own lines from a "username: text" transcript
    /// so confidence scoring reads ONLY the prospect's answers — never the
    /// recruiter's pitch.
    private func prospectOnlyTranscript(_ transcript: String) -> String {
        var excluded: Set<String> = [currentMeeting.host_username.lowercased()]
        let mine = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? ""
        if !mine.isEmpty { excluded.insert(mine.lowercased()) }
        return transcript
            .components(separatedBy: "\n")
            .filter { line in
                guard let colon = line.firstIndex(of: ":") else { return true }
                let speaker = line[line.startIndex..<colon]
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                return !excluded.contains(speaker)
            }
            .joined(separator: "\n")
    }

    private func regenerateEval() {
        guard !finalEvalBusy else { return }
        finalEvalBusy = true
        Task {
            let full = await WhisperMeetingService.shared.fetchTranscriptPlain(meetingID: meeting.id)
            let result = await WhisperMeetingCompanion.prospectEvaluation(
                transcript: prospectOnlyTranscript(full),
                hint: presentation?.displayName ?? presentation?.username
            )
            if let result {
                liveEval = result
                persistEval(result)
            }
            finalEvalBusy = false
        }
    }

    /// "RE-READING THE ROOM…" while an evaluation is in flight, otherwise
    /// a truthful freshness stamp — mirrors the web recruiter card.
    private func evalStatusLine(now: Date) -> String {
        if evalPhase == .evaluating { return "RE-READING THE ROOM…" }
        guard let at = evalUpdatedAt else { return "LIVE" }
        let seconds = max(0, Int(now.timeIntervalSince(at)))
        return seconds < 12 ? "UPDATED JUST NOW" : "UPDATED \(seconds)S AGO"
    }

    private func scoreTint(_ score: Int) -> Color {
        if score >= 70 { return Color(red: 0.20, green: 0.83, blue: 0.60) }
        if score >= 45 { return Color(red: 0.98, green: 0.75, blue: 0.14) }
        return Color(red: 0.97, green: 0.44, blue: 0.44)
    }

    private func placementChips(_ placement: String) -> some View {
        HStack(spacing: 5) {
            ForEach(["coach", "creator", "athlete"], id: \.self) { role in
                Text(role.uppercased())
                    .font(.system(size: 8, weight: .black))
                    .tracking(0.6)
                    .foregroundStyle(role == placement ? Color.black : Color.white.opacity(0.4))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        role == placement ? Color.cyan : Color.white.opacity(0.08),
                        in: Capsule()
                    )
            }
        }
    }

    @ViewBuilder
    private func liveEvalOverlay(_ eval: WhisperProspectEval) -> some View {
        if liveEvalCollapsed {
            HStack(spacing: 2) {
                Button {
                    Haptics.tap()
                    liveEvalCollapsed = false
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.cyan)
                        Text("\(eval.score)")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(scoreTint(eval.score))
                        Text("LIVE READ")
                            .font(.system(size: 8, weight: .black))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.leading, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                Button {
                    Haptics.tap()
                    liveEvalDismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss the live read for this meeting")
                .padding(.trailing, 2)
            }
            .background(Color.black.opacity(0.7), in: Capsule())
            .overlay { Capsule().strokeBorder(Color.cyan.opacity(0.3), lineWidth: 1) }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.cyan).frame(width: 5, height: 5)
                        Text("JASPER")
                            .font(.system(size: 8, weight: .black))
                            .tracking(1.1)
                    }
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.cyan.opacity(0.14), in: Capsule())
                    Text("LIVE READ")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer(minLength: 0)
                    Button {
                        Haptics.tap()
                        liveEvalCollapsed = true
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Collapse the live read")
                    Button {
                        Haptics.tap()
                        liveEvalDismissed = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss the live read for this meeting")
                }
                HStack(alignment: .center, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(eval.score)")
                            .font(.system(size: 28, weight: .black))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: eval.score)
                        Text("/100")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule()
                                .fill(scoreTint(eval.score))
                                .frame(width: g.size.width * min(1, max(0.04, Double(eval.score) / 100)))
                                .opacity(evalPhase == .evaluating ? 0.55 : 1)
                                .animation(
                                    evalPhase == .evaluating
                                        ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                                        : .easeOut(duration: 0.3),
                                    value: evalPhase
                                )
                        }
                    }
                    .frame(height: 5)
                }
                placementChips(eval.placement)
                if let match = liveApplicationMatch {
                    autoMatchStrip(match)
                }
                if !appCaptureQuestions.isEmpty {
                    questionsChecklist
                }
                Text(eval.summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(3)
                TimelineView(.periodic(from: .now, by: 5)) { context in
                    Text("\(eval.confidence)% CONFIDENCE \u{00B7} \(evalStatusLine(now: context.date))")
                        .font(.system(size: 7.5, weight: .black))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.35))
                }
                Text("ONLY YOU CAN SEE THIS")
                    .font(.system(size: 7.5, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(12)
            .frame(width: 232, alignment: .leading)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 20))
            .background(
                LinearGradient(
                    colors: [Color.cyan.opacity(0.22), Color.black.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: .rect(cornerRadius: 20)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.cyan.opacity(0.3), lineWidth: 1)
            }
        }
    }

    /// Which application questions exist and which Jasper has already
    /// captured from the conversation — the same question set the recruiter
    /// dashboard manages. Tap to expand the full checklist.
    private var questionsChecklist: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.3)) { evalQuestionsExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checklist")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.cyan)
                    Text("APPLICATION QUESTIONS \(appCaptureAnswers.count)/\(appCaptureQuestions.count)")
                        .font(.system(size: 8, weight: .black))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer(minLength: 0)
                    Image(systemName: evalQuestionsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if evalQuestionsExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(appCaptureQuestions, id: \.id) { q in
                        let captured = appCaptureAnswers[q.id]
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: captured != nil ? "checkmark.circle.fill" : "circle.dotted")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(captured != nil ? Color(red: 0.20, green: 0.83, blue: 0.60) : .white.opacity(0.30))
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(q.question)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.white.opacity(captured != nil ? 0.85 : 0.55))
                                    .lineLimit(2)
                                if let captured {
                                    Text(captured.answer)
                                        .font(.system(size: 8.5))
                                        .foregroundStyle(.cyan.opacity(0.85))
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 10))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// The same peeking-mascot Jasper card web renders for shared answers —
    /// the living mascot bobs over the top edge of a personality-tinted
    /// shell, with the presenter line and the current Jasper mode chip.
    private func sharedEmberCard(_ shared: WhisperSharedEmberAnswer) -> some View {
        let mode = WhisperEmberCoachMode.load()
        return ZStack(alignment: .topTrailing) {
            // Mascot peeking from BEHIND the card's top edge (drawn first,
            // card second — its lower half hides behind the shell).
            WhisperEmberMascot(
                size: 52,
                isActive: false,
                expression: mode.signatureExpression,
                coachMode: mode
            )
            .phaseAnimator([false, true]) { view, phase in
                view.offset(y: phase ? 3 : -3)
            } animation: { _ in
                .easeInOut(duration: 1.7)
            }
            .padding(.trailing, 26)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(mode.accent)
                    Text("@\(shared.name) SHARED JASPER'S ANSWER")
                        .font(.system(size: 8.5, weight: .black))
                        .tracking(1.0)
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(mode.shortTitle.uppercased())
                        .font(.system(size: 7.5, weight: .black))
                        .tracking(0.6)
                        .foregroundStyle(mode.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(mode.accent.opacity(0.18), in: Capsule())
                        .lineLimit(1)
                        .fixedSize()
                    Spacer(minLength: 0)
                    Button {
                        sharedEmberTask?.cancel()
                        sharedEmber = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                Text(shared.text)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .lineSpacing(3)
                    .lineLimit(6)
            }
            .padding(12)
            .frame(maxWidth: 330, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 22).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.45))
                    RoundedRectangle(cornerRadius: 22).fill(
                        LinearGradient(
                            colors: [mode.accent.opacity(0.22), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(mode.accent.opacity(0.32), lineWidth: 1)
                }
                .compositingGroup()
                .shadow(color: mode.accent.opacity(0.25), radius: 16, y: 5)
                .shadow(color: .black.opacity(0.4), radius: 20, y: 9)
            }
            .padding(.top, 30)
        }
        .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
    }

    // MARK: - Lifecycle

    private func join() async {
        guard roomVisible, !joiningRoom, !joined, !ending, !isLeaving,
              WhisperCallService.shared.active == nil, !WhisperCallService.shared.isStarting,
              !WhisperLiveRTCService.shared.isInUse else { return }
        joiningRoom = true
        if supportsMinimize { WhisperMeetingWindow.shared.mediaInUse = true }
        let operation = UUID(); joinOperation = operation
        let generation = AccountStorage.generation
        defer {
            joiningRoom = false
            if supportsMinimize, !joined { WhisperMeetingWindow.shared.mediaInUse = false }
        }
        // Release the lobby preview camera BEFORE the RTC capturer starts —
        // two capture sessions can't own the device at once.
        WhisperLobbyCameraSession.shared.stop()
        let service = WhisperLiveRTCService.shared
        WhisperRecordingConsentService.shared.reset()
        // A fresh room: the Meet layer starts clean (chat is ephemeral).
        roomChat = []
        chatUnread = 0
        roomPolicy = MeetRoomPolicy()
        raisedHands = [:]
        floatingReactions = []
        actingHostUserID = nil
        hostSeen = false
        seenRemotePeerIDs = []
        service.onParticipantsChanged = {
            trackNonce += 1
            participants = service.participants
            deckTour.noteParticipants(service.participants.map { $0.peerId })
            noteRosterChange(service.participants)
            WhisperRecordingConsentService.shared.reconcile(hostID: hostUserID)
        }
        service.onRemoteVideoTrackForPeer = { _, _ in
            trackNonce += 1
            participants = service.participants
        }
        service.onPermissionDenied = { permissionDenied = true }
        // App-level events — client presenting + shared Jasper answers — ride
        // the same signaling channel as the web client.
        service.onAppEvent = { event, data, fromPeerId in
            handleAppEvent(event, data: data, fromPeerId: fromPeerId)
        }

        let name = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "guest"
        await service.join(
            roomId: "meeting:\(meeting.id)",
            userId: myUserID,
            name: name,
            asListener: false,
            withVideo: joinPrefCamOn,
            initiallyMuted: !joinPrefMicOn,
            shouldContinue: { roomVisible && joinOperation == operation && generation == AccountStorage.generation }
        )
        guard joinOperation == operation, generation == AccountStorage.generation, !Task.isCancelled else {
            service.suspendMediaForExit()
            service.onParticipantsChanged = nil; service.onRemoteVideoTrackForPeer = nil
            service.onPermissionDenied = nil; service.onAppEvent = nil
            await service.leave()
            return
        }
        joined = true
        joinedAt = Date()
        // Meet's landing chime — you're in. Seed the roster so people already
        // here don't re-chime as "joined".
        seenRemotePeerIDs = Set(
            service.participants.filter { $0.peerId != service.localPeerId }.map { $0.peerId }
        )
        WhisperMeetChime.playJoin()
        // Meetings keep the screen awake — no autolock mid-call.
        UIApplication.shared.isIdleTimerDisabled = true
        // Register the live meeting with CallKit so iOS keeps the mic,
        // audio, and networking running when the app is backgrounded
        // mid-meeting — without this the system suspends the app within
        // seconds and the meeting goes silent for everyone else.
        WhisperVoIPService.shared.startOutgoingCall(
            callID: "meeting:\(meeting.id)",
            displayName: currentMeeting.title.isEmpty ? "Whisper meeting" : currentMeeting.title,
            video: true,
            connectedImmediately: true
        )
        // Apply the lobby device choices (walk in muted / camera off).
        if !joinPrefMicOn {
            micOn = false
            service.setMuted(true)
        }
        if !joinPrefCamOn {
            cameraOn = false
            service.setCameraEnabled(false)
        }
        participants = service.participants
        await WhisperMeetingService.shared.recordJoin(meetingID: meeting.id)
        guard roomVisible, joined, !isLeaving, joinOperation == operation, generation == AccountStorage.generation, !Task.isCancelled else { return }
        // Ask the room whether a presentation or walkthrough is running so
        // late joiners land in sync immediately.
        service.sendAppEvent("present-sync-request", data: [:])
        startMeetingTranscription()
        startPresentWatch()
        startVitalsPublishing()
        if isCoach {
            startHeartRatePolling()
        }
        if isRecruiter {
            startRecruiterIntelligence()
        } else {
            // The recruiter flag loads lazily (only recruiter screens used to
            // refresh it) — resolve it NOW so the live prospect read + score
            // card reliably appear in-meeting without ever visiting one.
            Task {
                await WhisperRecruiterService.shared.refreshMyStatus()
                if roomVisible, joined, !isLeaving, joinOperation == operation, generation == AccountStorage.generation, WhisperRecruiterService.shared.isMeRecruiter, evalTask == nil {
                    startRecruiterIntelligence()
                }
            }
        }
        startChimeLoop()
        startListenGuard()
    }

    /// The recruiter auto-analyze suite — the live prospect read AND live
    /// application capture (potential score + best-position auto-match) —
    /// both on automatically, no toggles to find.
    private func startRecruiterIntelligence() {
        startLiveEvalLoop()
        if !appCaptureOn {
            appCaptureOn = true   // onChange starts the capture loop
        } else {
            startApplicationCapture()
        }
    }

    private func startMeetingTranscription() {
        guard joined, micOn, !emberVoiceOn, WhisperLiveRTCService.shared.micOn else { return }
        let owner = myUserID
        let generation = AccountStorage.generation
        if let captureOwner, captureOwner != owner || captureGeneration != generation { transcriber.stop(flush: false); return }
        captureOwner = owner; captureGeneration = generation
        transcriber.start { text in
            guard AccountStorage.generation == generation, myUserID == owner else { return }
            routeUtterance(text)
        }
    }

    /// The pill's hands-free capture rides the meeting transcriber — make
    /// sure it is genuinely running (permission granted, engine alive)
    /// before the box claims to be listening.
    private func ensureEmberListening() {
        guard !emberVoiceOn else { return }
        switch transcriber.state {
        case .listening:
            if !transcriber.isHealthy { transcriber.stop(); startMeetingTranscription() }
        case .requestingPermission:
            break
        case .idle:
            startMeetingTranscription()
        case .failed, .unavailable:
            break // Permission and terminal failures need an explicit retry.
        }
    }

    /// Local microphone capture is supervised during the meeting — if the
    /// recognizer ever dies (late permission grant, route change, voice
    /// mode hand-back), this quietly restarts it. No waveform tap needed.
    private func startListenGuard() {
        listenGuardTask?.cancel()
        listenGuardTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled else { break }
                if let captureOwner, captureOwner != myUserID || captureGeneration != AccountStorage.generation {
                    transcriber.stop(flush: false)
                    await leave()
                    requestClose()
                    return
                }
                ensureEmberListening()
                await WhisperTranscriptOutbox.shared.flush()
            }
        }
    }

    /// This recognizer only owns shared meeting speech. Private voice has its own muted session.
    private func routeUtterance(_ text: String) {
        guard joined, micOn, !emberVoiceOn, !emberCapturing else { return }
        // Meeting speech stays meeting speech. Private voice is explicitly opened from Tools.
        WhisperMeetingService.shared.queueTranscript(meetingID: meeting.id, text: text, spokenAt: transcriber.lastSpokenAt)
        if !ending { detectSpokenSchedule(in: text) }
    }

    /// Detects a spoken wake phrase ("hey jasper", "ok jasper", legacy
    /// "hey ember") and returns whatever question followed it — empty when
    /// the phrase stood alone.
    private func wakeWordQuestion(in text: String) -> String? {
        let lower = text.lowercased()
        for phrase in ["hey jasper", "hey, jasper", "ok jasper", "okay jasper", "hey ember", "hey, ember"] {
            if let range = lower.range(of: phrase) {
                return String(lower[range.upperBound...])
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ,.?!"))
            }
        }
        return nil
    }

    // MARK: - Voice auto-schedule

    /// Everyone on the call except me — tagged on the calendar event so each
    /// person gets the invite card in DMs (group meetings included).
    private var taggableParticipants: [(id: String, name: String)] {
        var seen = Set<String>()
        var out: [(String, String)] = []
        for p in participants {
            let uid = p.userId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !uid.isEmpty, uid != myUserID, uid != "guest",
                  !uid.hasPrefix("local_"), !seen.contains(uid) else { continue }
            seen.insert(uid)
            out.append((uid, p.name))
        }
        return out
    }

    /// Scans my finalized utterance for a spoken future date ("let's film
    /// Friday at 3"). On a hit the suggestion shows locally AND broadcasts to
    /// every participant so the whole room can agree on the same prompt.
    private func detectSpokenSchedule(in text: String) {
        guard let hit = WhisperChatScheduleDetector.detectSpoken(text: text) else { return }
        let bucket = Int(hit.date.timeIntervalSince1970 / 600)
        guard !handledScheduleBuckets.contains(bucket) else { return }
        handledScheduleBuckets.insert(bucket)
        presentScheduleSuggestion(date: hit.date, snippet: hit.snippet, eventType: hit.eventType, bucket: bucket)
        let myName = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "someone"
        WhisperLiveRTCService.shared.sendAppEvent("schedule-suggest", data: [
            "byUserId": myUserID,
            "byName": myName,
            "dateMs": hit.date.timeIntervalSince1970 * 1000,
            "snippet": hit.snippet,
            "eventType": hit.eventType
        ])
    }

    private func presentScheduleSuggestion(date: Date, snippet: String, eventType: String, bucket: Int) {
        let names = taggableParticipants.map { $0.name }
        let suggestion = WhisperChatScheduleDetector.Suggestion(
            messageID: "voice-\(bucket)",
            date: date,
            snippet: snippet,
            suggestedTitle: WhisperChatScheduleDetector.groupTitle(for: eventType, names: names),
            eventType: eventType
        )
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            scheduleSuggestion = suggestion
        }
    }

    private func showScheduleToast(_ message: String) {
        withAnimation(.spring(response: 0.3)) { scheduleToast = message }
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation { scheduleToast = nil }
        }
    }

    private func startHeartRatePolling() {
        Task {
            while joined && !Task.isCancelled {
                let ids = participants.map { $0.userId.lowercased() }.filter { $0 != myUserID }
                if !ids.isEmpty {
                    let polled = await WhisperMeetingService.shared.fetchHeartRates(userIDs: ids)
                    // Live-streamed vitals (client-vitals app events) win over
                    // the 15s snapshot poll — merge instead of overwrite.
                    heartRates.merge(polled) { live, _ in live }
                }
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    /// Streams my live heart rate into the call every few seconds so a
    /// coach's overlays (web + iOS) update in real time. Publishes only when
    /// HealthKit has a fresh reading — silent otherwise.
    private func startVitalsPublishing() {
        vitalsPublishTask?.cancel()
        vitalsPublishTask = Task {
            let health = HealthKitService()
            while !Task.isCancelled && joined {
                let bpm = await health.latestHeartRate()
                if bpm > 0, !myUserID.isEmpty {
                    WhisperLiveRTCService.shared.sendAppEvent(
                        "client-vitals",
                        data: ["userId": myUserID, "bpm": Int(bpm.rounded())]
                    )
                }
                try? await Task.sleep(for: .seconds(7))
            }
        }
    }

    // MARK: - Jasper live voice (realtime echo)

    private var emberVoiceStatusLine: String {
        switch emberVoiceLine.phase {
        case .connecting: return "Warming up Jasper's voice…"
        case .listening: return "Live voice — just talk to me…"
        case .thinking: return "Thinking…"
        case .speaking: return "Jasper is talking…"
        case .idle: return "Voice line muted"
        case .unavailable: return "Voice isn't available here — type below."
        }
    }

    /// Toggles Jasper's TRUE speech-to-speech line (echo voice) inside the
    /// meeting — the same realtime brain as the web client. While the line
    /// is live the SFSpeech caption engine pauses (one microphone owner) and
    /// the meeting microphone is muted first. Private questions never enter
    /// the shared meeting transcript.
    private func toggleEmberVoice() {
        if emberVoiceOn {
            stopEmberVoice()
            return
        }
        emberVoiceOn = true
        WhisperLiveRTCService.shared.setMuted(true)
        micOn = false
        let operation = UUID(); emberVoiceOperation = operation
        let generation = AccountStorage.generation
        emberCapturing = false
        emberVoiceBuffer = ""
        transcriber.stop()
        // The meeting's WebRTC engine owns the audio session — Jasper's line
        // must never reconfigure or deactivate it (that muted whole calls).
        emberVoiceLine.managesAudioSession = false
        emberVoiceStartTask?.cancel()
        emberVoiceStartTask = Task {
            let ok = await emberVoiceLine.requestAuthorization()
            guard !Task.isCancelled, joined, emberVoiceOn, emberVoiceOperation == operation, AccountStorage.generation == generation else { return }
            guard ok else {
                emberReply = emberVoiceLine.statusMessage ?? "Enable Microphone access in Settings to talk to Jasper."
                stopEmberVoice()
                return
            }
            await emberVoiceLine.connect(
                instructions: WhisperMeetingCompanion.meetingVoiceInstructions(
                    title: currentMeeting.title,
                    participants: participants.map { $0.name }
                )
            ) { userText, replyText in
                guard joined, emberVoiceOperation == operation, AccountStorage.generation == generation else { return }
                emberReply = replyText
                lastEmberQuestion = userText
                emberError = false
                // Private voice questions must not enter the shared meeting transcript.
            }
            // A connect that ends unavailable must not strand Jasper deaf:
            // surface the reason, fall back to text mode, and rearm the
            // meeting transcriber so captions + pill listening still work.
            if emberVoiceOn && emberVoiceLine.phase == .unavailable {
                emberReply = emberVoiceLine.statusMessage ?? "Jasper's live voice couldn't connect — tap the mic to retry."
                stopEmberVoice()
            }
        }
    }

    private func stopEmberVoice() {
        emberVoiceOperation = UUID(); emberVoiceStartTask?.cancel(); emberVoiceStartTask = nil
        emberVoiceLine.shutdown()
        emberVoiceOn = false
        if joined {
            startMeetingTranscription()
        }
    }

    private func leave() async {
        guard !isLeaving else { return }
        isLeaving = true; joinOperation = UUID()
        defer { isLeaving = false }
        emberVoiceOperation = UUID(); emberVoiceStartTask?.cancel(); emberVoiceStartTask = nil
        WhisperRecordingConsentService.shared.reset()
        WhisperLiveRTCService.shared.suspendMediaForExit()
        UIApplication.shared.isIdleTimerDisabled = false
        appCaptureTask?.cancel()
        appCaptureTask = nil
        vitalsPublishTask?.cancel()
        vitalsPublishTask = nil
        emberVoiceLine.shutdown()
        emberVoiceOn = false
        deckTour.shutdown()
        tourHidden = false
        presentHeartbeatTask?.cancel()
        presentHeartbeatTask = nil
        presentWatchTask?.cancel()
        presentWatchTask = nil
        analyticsHeartbeatTask?.cancel()
        analyticsHeartbeatTask = nil
        evalTask?.cancel()
        evalTask = nil
        chimeTask?.cancel()
        chimeTask = nil
        listenGuardTask?.cancel()
        listenGuardTask = nil
        emberDebounceTask?.cancel()
        sharedEmberTask?.cancel()
        WhisperLiveRTCService.shared.onAppEvent = nil
        await transcriber.finishAndStop()
        await WhisperLiveRTCService.shared.leave()
        await WhisperMeetingService.shared.flushTranscriptQueue()
        WhisperVoIPService.shared.reportEnded(callID: "meeting:\(meeting.id)")
        joined = false
        if supportsMinimize { WhisperMeetingWindow.shared.mediaInUse = false }
    }

    private func endTapped() async {
        if speedDateActive {
            // Dating rooms end on the wrap, never the meeting recap.
            await finishBlindDate(partnerLeft: false)
            return
        }
        // Meet's rule: a host alone ends the meeting; a host with people in
        // the room chooses — leave (and hand the room over) or end for all.
        let others = participants.filter { $0.peerId != WhisperLiveRTCService.shared.localPeerId }
        if isHost && !others.isEmpty {
            showLeaveMenu = true
            return
        }
        await endCall(everyone: isHost)
    }

    /// `everyone` = the host ends the meeting for the whole room (the
    /// `call-end` wire + notes). Otherwise I simply leave — a host hands the
    /// room to the longest-present participant first (`call-host`).
    private func endCall(everyone: Bool) async {
        showLeaveMenu = false
        ending = true
        if everyone {
            WhisperLiveRTCService.shared.sendAppEvent("call-end", data: ["byName": myDisplayName])
            // Let the broadcast leave the socket before the channel drops.
            try? await Task.sleep(for: .milliseconds(280))
        } else if isHost {
            let others = participants.filter { $0.peerId != WhisperLiveRTCService.shared.localPeerId }
            if let successor = others.first, !successor.userId.isEmpty {
                WhisperLiveRTCService.shared.sendAppEvent("call-host", data: [
                    "userId": successor.userId.lowercased(),
                    "name": successor.name,
                    "byName": myDisplayName
                ])
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        WhisperMeetChime.playEnd()
        await leave()
        // Pull the transcript FIRST so the recap shows it the moment the
        // meeting ends — notes generate on top of it, exactly like web.
        recapTranscript = await WhisperMeetingService.shared.fetchTranscriptPlain(meetingID: meeting.id)
        let hasTranscript = !recapTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        showRecap = true
        ending = false
        if everyone {
            await WhisperMeetingService.shared.end(meetingID: meeting.id)
            if hasTranscript { await produceNotes() }
        } else if hasTranscript {
            await pollNotesAsParticipant()
        }
        ending = false
    }

    /// Participants can't write notes to the meeting row — the host's
    /// device generates them. Poll the row so the recap upgrades from
    /// transcript-only to full AI notes as soon as they land.
    private func pollNotesAsParticipant() async {
        generating = true
        for _ in 0..<10 {
            if let fresh = await WhisperMeetingService.shared.fetch(id: meeting.id) {
                liveMeeting = fresh
                if let summary = fresh.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !summary.isEmpty {
                    notes = summary
                    generating = false
                    return
                }
            }
            try? await Task.sleep(for: .seconds(3))
        }
        generating = false
    }

    /// The host ended the meeting while we were still in the room — land
    /// on the recap with the transcript instead of getting stranded.
    private func handleRemoteEnd() async {
        guard !showRecap else { return }
        if speedDateActive {
            await finishBlindDate(partnerLeft: true)
            return
        }
        await leave()
        recapTranscript = await WhisperMeetingService.shared.fetchTranscriptPlain(meetingID: meeting.id)
        showRecap = true
        if !recapTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { await pollNotesAsParticipant() }
    }

    private var tileAvatarKey: String {
        participants.map { $0.userId.lowercased() }.sorted().joined(separator: ",")
    }

    /// Resolve avatar URLs for everyone on the call so camera-off tiles
    /// show their blurred profile photo instead of a flat dark box.
    private func hydrateTileAvatars() async {
        let ids = participants
            .map { $0.userId }
            .filter { !$0.isEmpty && $0.lowercased() != "guest" && !$0.hasPrefix("local_") }
        guard !ids.isEmpty else { return }
        let profiles = await WhisperBackendService.shared.fetchPublicProfiles(userIDs: ids)
        var merged = tileAvatars
        for (key, profile) in profiles {
            if let raw = profile.profile_image_url, let url = URL(string: raw) {
                merged[key.lowercased()] = url
            }
        }
        tileAvatars = merged
    }

    /// Generate the AI notes with retries so one flaky request never
    /// swallows a meeting's notes. Missing shared text never closes the private
    /// meeting workspace; a generation failure with sources offers Try Again.
    private func produceNotes() async {
        generating = true
        var generated: String? = nil
        for attempt in 0..<3 {
            generated = await WhisperMeetingService.shared.generateNotes(meetingID: meeting.id)
            if generated != nil { break }
            if attempt < 2 { try? await Task.sleep(for: .seconds(1.2)) }
        }
        notes = generated
        if generated != nil {
            if isRecruiter { finalizePitchDeck() }
            generating = false
            return
        }
        generating = false
        let transcript = await WhisperMeetingService.shared.fetchTranscriptPlain(meetingID: meeting.id)
        if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { showNotesRetry = true }
    }

}

// MARK: - Companion overlay pieces

/// An Jasper answer somebody shared with the whole meeting.
private struct WhisperSharedEmberAnswer: Equatable {
    let name: String
    let text: String
}

/// Faint rotating RGB halo shown behind the mascot while Jasper thinks.
private struct WhisperRainbowHalo: View {
    @State private var spin: Bool = false

    var body: some View {
        Circle()
            .fill(
                AngularGradient(
                    colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                    center: .center
                )
            )
            .frame(width: 66, height: 66)
            .blur(radius: 10)
            .opacity(0.55)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                    spin = true
                }
            }
            .allowsHitTesting(false)
    }
}

/// The little phone-shaped presenting segment pinned over the call — tap to
/// expand into the full profile sheet. The presenter's copy has a stop button.
private struct WhisperMiniClientPhoneCard: View {
    let client: WhisperPresentedClient
    let isMine: Bool
    var onExpand: () -> Void
    var onStop: () -> Void

    private var score: Double? {
        guard client.application?.taken == true else { return nil }
        return client.application?.potentialScore
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onExpand) {
                VStack(spacing: 4) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 26, height: 4)
                        .padding(.top, 7)
                    WhisperAvatar(
                        username: client.username ?? client.displayName ?? "?",
                        size: 34,
                        imageURL: client.imageUrl.flatMap(URL.init(string:))
                    )
                    Text(client.displayName ?? client.username ?? "Client")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 3) {
                        Circle().fill(Color.cyan).frame(width: 4, height: 4)
                        Text("PRESENTING")
                            .font(.system(size: 6, weight: .black))
                            .tracking(0.8)
                            .foregroundStyle(.cyan)
                    }
                    if let score {
                        VStack(spacing: 2) {
                            HStack {
                                Text("\(Int(score.rounded()))")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundStyle(.white)
                                Spacer(minLength: 0)
                                Text("/100")
                                    .font(.system(size: 6, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.12))
                                    Capsule()
                                        .fill(WhisperMeetingScorePalette.tint(Int(score.rounded())))
                                        .frame(width: g.size.width * min(1, max(0.04, score / 100)))
                                }
                            }
                            .frame(height: 3)
                        }
                        .padding(.horizontal, 3)
                    }
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 6, weight: .bold))
                        Text("EXPAND")
                            .font(.system(size: 6, weight: .black))
                            .tracking(0.6)
                    }
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 2)
                    .padding(.bottom, 8)
                }
                .padding(.horizontal, 7)
                .frame(width: 96)
                .background(Color.black.opacity(0.92), in: .rect(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color.cyan.opacity(0.35), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Expand presented client profile")

            if isMine {
                Button {
                    Haptics.tap()
                    onStop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Color.red, in: Circle())
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .accessibilityLabel("Stop presenting")
            }
        }
    }
}

/// Shared score → color mapping for the presenting cards.
private enum WhisperMeetingScorePalette {
    static func tint(_ score: Int) -> Color {
        if score >= 70 { return Color(red: 0.20, green: 0.83, blue: 0.60) }
        if score >= 45 { return Color(red: 0.98, green: 0.75, blue: 0.14) }
        return Color(red: 0.97, green: 0.44, blue: 0.44)
    }
}

/// Plain data models for the snapshot card — explicit structs instead of
/// tuple-literal arrays keep the release-mode type checker fast (the App
/// Store build previously timed out type-checking this section).
private struct WhisperSnapshotMacro: Identifiable {
    let name: String
    let value: Double
    let goal: Double
    let tint: Color
    var id: String { name }
}

private struct WhisperSnapshotTile: Identifiable {
    let name: String
    let value: String
    var id: String { name }
}

/// Coach-client live snapshot — macros with progress bars, activity tiles,
/// and recent workouts. Same data the coach dashboard tracks.
private struct WhisperClientSnapshotSection: View {
    let snap: WhisperPresentedClient.Snapshot

    private var macros: [WhisperSnapshotMacro] {
        let all: [WhisperSnapshotMacro] = [
            WhisperSnapshotMacro(name: "Calories", value: snap.caloriesToday ?? 0, goal: snap.caloriesGoal ?? 0, tint: Color.orange),
            WhisperSnapshotMacro(name: "Protein", value: snap.proteinToday ?? 0, goal: snap.proteinGoal ?? 0, tint: Color.green),
            WhisperSnapshotMacro(name: "Carbs", value: snap.carbsToday ?? 0, goal: snap.carbsGoal ?? 0, tint: Color.blue),
            WhisperSnapshotMacro(name: "Fat", value: snap.fatToday ?? 0, goal: snap.fatGoal ?? 0, tint: Color.yellow),
        ]
        return all.filter { $0.value > 0 || $0.goal > 0 }
    }

    private var tiles: [WhisperSnapshotTile] {
        var out: [WhisperSnapshotTile] = []
        let steps: Double = snap.steps ?? 0
        if steps > 0 {
            out.append(WhisperSnapshotTile(name: "Steps", value: "\(Int(steps))"))
        }
        let sleep: Double = snap.sleepHours ?? 0
        if sleep > 0 {
            out.append(WhisperSnapshotTile(name: "Sleep", value: String(format: "%.1fh", sleep)))
        }
        let water: Double = snap.waterCups ?? 0
        if water > 0 {
            out.append(WhisperSnapshotTile(name: "Water", value: "\(Int(water)) cups"))
        }
        let weight: Double = snap.weightLbs ?? 0
        if weight > 0 {
            out.append(WhisperSnapshotTile(name: "Weight", value: "\(Int(weight)) lb"))
        }
        let bodyFat: Double = snap.bodyFatPct ?? 0
        if bodyFat > 0 {
            out.append(WhisperSnapshotTile(name: "Body fat", value: String(format: "%.1f%%", bodyFat)))
        }
        let restingHR: Double = snap.restingHeartRate ?? 0
        if restingHR > 0 {
            out.append(WhisperSnapshotTile(name: "Resting HR", value: "\(Int(restingHR)) bpm"))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TODAY IN JASPER")
                .font(.system(size: 9, weight: .black))
                .tracking(1.2)
                .foregroundStyle(.orange.opacity(0.9))
            ForEach(macros) { macro in
                macroRow(macro)
            }
            if !tiles.isEmpty {
                tileGrid
            }
            if let workouts = snap.workouts, !workouts.isEmpty {
                workoutList(workouts)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.06), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
        }
    }

    private func macroLabel(_ macro: WhisperSnapshotMacro) -> String {
        let current = Int(macro.value)
        if macro.goal > 0 {
            return "\(current) / \(Int(macro.goal))"
        }
        return "\(current)"
    }

    private func macroFraction(_ macro: WhisperSnapshotMacro) -> Double {
        guard macro.goal > 0 else { return 0 }
        return min(1, max(0.03, macro.value / macro.goal))
    }

    private func macroRow(_ macro: WhisperSnapshotMacro) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(macro.name.uppercased())
                    .font(.system(size: 8, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                Text(macroLabel(macro))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(macro.tint)
                        .frame(width: g.size.width * macroFraction(macro))
                }
            }
            .frame(height: 4)
        }
    }

    private var tileGrid: some View {
        let columns: [GridItem] = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
        ]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(tiles) { tile in
                tileCell(tile)
            }
        }
    }

    private func tileCell(_ tile: WhisperSnapshotTile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tile.name.uppercased())
                .font(.system(size: 7, weight: .black))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.4))
            Text(tile.value)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 10))
    }

    private func workoutLabel(_ workout: WhisperPresentedClient.SnapshotWorkout) -> String {
        let minutes = Int(workout.durationMinutes ?? 0)
        let calories = Int(workout.calories ?? 0)
        return "\(minutes)m · \(calories) cal"
    }

    private func workoutList(_ workouts: [WhisperPresentedClient.SnapshotWorkout]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RECENT WORKOUTS")
                .font(.system(size: 8, weight: .black))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.4))
            ForEach(Array(workouts.prefix(3).enumerated()), id: \.offset) { _, workout in
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text(workout.type ?? "Workout")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(workoutLabel(workout))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
    }
}

/// The expanded full client profile — shown when someone taps the mini card.
private struct WhisperPresentedClientSheet: View {
    let client: WhisperPresentedClient
    let isMine: Bool
    var onStop: () -> Void
    var onSwitch: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var score: Double? {
        guard client.application?.taken == true else { return nil }
        return client.application?.potentialScore
    }

    private var facts: [(String, String)] {
        var out: [(String, String)] = []
        if let niche = client.niche, !niche.isEmpty { out.append(("Niche", niche)) }
        if let location = client.location, !location.isEmpty { out.append(("Location", location)) }
        if let source = client.source, !source.isEmpty { out.append(("Source", source)) }
        if let role = client.suggestedRole, !role.isEmpty { out.append(("Future role", role)) }
        return out
    }

    /// Coach-client live snapshot — extracted into its own small view so the
    /// release-build type checker never re-solves this section as one giant
    /// expression (previous inline version timed out in App Store builds).
    private func snapshotSection(_ snap: WhisperPresentedClient.Snapshot) -> some View {
        WhisperClientSnapshotSection(snap: snap)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        WhisperAvatar(
                            username: client.username ?? client.displayName ?? "?",
                            size: 72,
                            imageURL: client.imageUrl.flatMap(URL.init(string:))
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(client.displayName ?? client.username ?? "Unknown client")
                                .font(.title3.weight(.black))
                                .foregroundStyle(.white)
                            if let username = client.username {
                                Text("@\(username)")
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            HStack(spacing: 4) {
                                Circle().fill(Color.cyan).frame(width: 5, height: 5)
                                Text("PRESENTING LIVE")
                                    .font(.system(size: 8, weight: .black))
                                    .tracking(1.0)
                                    .foregroundStyle(.cyan)
                            }
                        }
                        Spacer()
                    }

                    if let status = client.status, !status.isEmpty {
                        Text(status.uppercased())
                            .font(.system(size: 9, weight: .black))
                            .tracking(0.8)
                            .foregroundStyle(.cyan)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.cyan.opacity(0.14), in: Capsule())
                    }

                    if let score {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PROSPECT APPLICATION")
                                .font(.system(size: 9, weight: .black))
                                .tracking(1.2)
                                .foregroundStyle(.green.opacity(0.9))
                            HStack(alignment: .center, spacing: 12) {
                                HStack(alignment: .firstTextBaseline, spacing: 2) {
                                    Text("\(Int(score.rounded()))")
                                        .font(.system(size: 34, weight: .black))
                                        .foregroundStyle(.white)
                                    Text("/100")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.white.opacity(0.12))
                                        Capsule()
                                            .fill(WhisperMeetingScorePalette.tint(Int(score.rounded())))
                                            .frame(width: g.size.width * min(1, max(0.04, score / 100)))
                                    }
                                }
                                .frame(height: 6)
                            }
                            HStack(spacing: 6) {
                                if let position = client.application?.bestPosition, !position.isEmpty {
                                    Text("BEST FIT \u{00B7} \(position.uppercased())")
                                        .font(.system(size: 8, weight: .black))
                                        .tracking(0.6)
                                        .foregroundStyle(.green)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.14), in: Capsule())
                                }
                                if let confidence = client.application?.confidenceScore {
                                    Text("\(Int(confidence.rounded()))% CONFIDENCE")
                                        .font(.system(size: 8, weight: .black))
                                        .tracking(0.6)
                                        .foregroundStyle(.white.opacity(0.6))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.white.opacity(0.08), in: Capsule())
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.06), in: .rect(cornerRadius: 16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.green.opacity(0.2), lineWidth: 1)
                        }
                    } else {
                        HStack(spacing: 10) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.35))
                            Text("Hasn't taken the prospect application yet — share your QR code to get their potential score.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 16))
                    }

                    if let answers = client.applicationAnswers, !answers.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("APPLICATION ANSWERS")
                                .font(.system(size: 9, weight: .black))
                                .tracking(1.2)
                                .foregroundStyle(.green.opacity(0.9))
                            ForEach(Array(answers.prefix(8).enumerated()), id: \.offset) { _, pair in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(pair.q ?? "")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.45))
                                    Text(pair.a ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.9))
                                        .lineSpacing(2)
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 16))
                    }

                    if let snap = client.snapshot {
                        snapshotSection(snap)
                    }

                    if let photos = client.photos, !photos.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(client.kind == "coach-client" ? "PROGRESS PHOTOS" : "FROM INSTAGRAM")
                                .font(.system(size: 9, weight: .black))
                                .tracking(1.2)
                                .foregroundStyle(.white.opacity(0.45))
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(photos.prefix(9), id: \.self) { photo in
                                        Color(.secondarySystemBackground)
                                            .frame(width: 96, height: 120)
                                            .overlay {
                                                WhisperCachedAsyncImage(url: URL(string: photo)) { image in
                                                    image.resizable().aspectRatio(contentMode: .fill)
                                                } placeholder: {
                                                    Color.white.opacity(0.06)
                                                }
                                                .allowsHitTesting(false)
                                            }
                                            .clipShape(.rect(cornerRadius: 12))
                                    }
                                }
                            }
                        }
                    }

                    if !facts.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(facts, id: \.0) { fact in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fact.0.uppercased())
                                        .font(.system(size: 8, weight: .black))
                                        .tracking(0.8)
                                        .foregroundStyle(.white.opacity(0.4))
                                    Text(fact.1)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 12))
                            }
                        }
                    }

                    HStack(spacing: 6) {
                        if let instagram = client.instagram, !instagram.isEmpty {
                            Label(instagram.replacingOccurrences(of: "@", with: ""), systemImage: "camera.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.06), in: Capsule())
                        }
                        if let tiktok = client.tiktok, !tiktok.isEmpty {
                            Label(tiktok.replacingOccurrences(of: "@", with: ""), systemImage: "music.note")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.06), in: Capsule())
                        }
                    }

                    if let notes = client.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("RECRUITER NOTES")
                                .font(.system(size: 8, weight: .black))
                                .tracking(1.0)
                                .foregroundStyle(.white.opacity(0.4))
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                                .lineSpacing(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 14))
                    }

                    Text("Presented by @\(client.presenterName)")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(maxWidth: .infinity)

                    if isMine {
                        HStack(spacing: 8) {
                            Button {
                                Haptics.tap()
                                onStop()
                                dismiss()
                            } label: {
                                Label("Stop presenting", systemImage: "xmark")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(Color.red, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            Button {
                                Haptics.tap()
                                onSwitch()
                            } label: {
                                Label("Switch", systemImage: "arrow.left.arrow.right")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 13)
                                    .background(Color.white.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Presented client")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Local speech transcription

/// Streams the local user's speech into ordered finished utterances using
/// SFSpeechRecognizer. Each completed Speech task rolls into a fresh task, so
/// long calls keep transcribing instead of silently ending after one phrase.
@MainActor
@Observable
final class WhisperMeetingTranscriber {
    enum State: Equatable {
        case idle
        case requestingPermission
        case listening
        case unavailable(String)
        case failed(String)

        var label: String {
            switch self {
            case .idle: return "Captions paused"
            case .requestingPermission: return "Preparing captions"
            case .listening: return "Live transcription on"
            case .unavailable(let message), .failed(let message): return message
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var liveCaption: String = ""
    private(set) var lastSpokenAt: Date = Date()
    private var recognitionStartedAt: Date = Date()
    private var pendingStartedAt: Date = Date()
    private var receivedTerminal: Bool = false

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var engine = AVAudioEngine()
    private var audioObservers: [NSObjectProtocol] = []
    private var sessionID: UUID?
    private var recognitionID: UUID?
    private var isFinishing: Bool = false
    private var committedThrough: TimeInterval = 0
    private var pendingThrough: TimeInterval = 0
    var isHealthy: Bool { state == .listening && engine.isRunning && task != nil }
    private var restartTask: Task<Void, Never>?
    private var retryCount: Int = 0
    private var onUtterance: ((String) -> Void)?
    private var hasInputTap: Bool = false
    /// Watches for a pause in speech — Apple's long-running dictation rarely
    /// flags `isFinal` mid-meeting, so utterances are finalized after a short
    /// silence window instead (this is what feeds captions AND Jasper asks).
    private var utteranceTimer: Task<Void, Never>?
    private var pendingUtterance: String = ""

    func start(onUtterance: @escaping (String) -> Void) {
        guard !isHealthy, state != .requestingPermission, restartTask == nil else { return }
        stop(flush: false)
        let identifier = UUID()
        sessionID = identifier
        self.onUtterance = onUtterance
        observeAudioChanges(sessionID: identifier)
        state = .requestingPermission

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self, self.sessionID == identifier else { return }
                guard status == .authorized else {
                    self.state = .unavailable("Speech Recognition is off. Enable it in Settings to create captions.")
                    return
                }
                self.begin(sessionID: identifier)
            }
        }
    }

    /// Gives Speech a brief chance to return the final buffered phrase before
    /// teardown, then prevents any late authorization/result callback from
    /// restarting capture after the person left the meeting.
    func finishAndStop() async {
        guard sessionID != nil else {
            stop()
            return
        }
        isFinishing = true
        restartTask?.cancel(); restartTask = nil
        utteranceTimer?.cancel()
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        for _ in 0..<30 {
            if receivedTerminal { break }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
        }
        emitPendingUtterance()
        stop(flush: false)
    }

    func stop(flush: Bool = true) {
        if flush { emitPendingUtterance() }
        sessionID = nil
        audioObservers.forEach { NotificationCenter.default.removeObserver($0) }
        audioObservers = []
        recognitionID = nil
        isFinishing = false
        committedThrough = 0; pendingThrough = 0
        restartTask?.cancel()
        restartTask = nil
        teardownCurrentRecognition()
        recognizer = nil
        onUtterance = nil
        retryCount = 0
        liveCaption = ""
        pendingUtterance = ""
        state = .idle
    }

    private func begin(sessionID identifier: UUID) {
        guard sessionID == identifier else { return }
        guard !isFinishing else { return }
        // A fresh graph prevents old tap/format state surviving Speech restarts.
        // AVAudioEngine tap assertions are Objective-C exceptions, not Swift errors.
        teardownCurrentRecognition()
        engine = AVAudioEngine()
        let recognition = UUID(); recognitionID = recognition; committedThrough = 0; pendingThrough = 0
        receivedTerminal = false; recognitionStartedAt = Date()
        recognizer = SFSpeechRecognizer(locale: Locale.current)
        guard let recognizer, recognizer.isAvailable else {
            state = .unavailable("Speech Recognition isn't available right now.")
            return
        }
        guard AVAudioSession.sharedInstance().isInputAvailable else {
            state = .unavailable("No microphone input is available for captions.")
            return
        }

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        let output = input.outputFormat(forBus: 0)
        guard format.sampleRate.isFinite, format.sampleRate > 0, format.channelCount > 0,
              output.sampleRate.isFinite, output.sampleRate > 0, output.channelCount > 0,
              AVAudioApplication.shared.recordPermission == .granted else {
            state = .unavailable("No microphone input is available for captions.")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request

        // Do not force a cached hardware format when Bluetooth/CallKit can
        // change the route. Nil uses the input node's current native format.
        input.installTap(onBus: 0, bufferSize: 2048, format: nil) { buffer, _ in
            request.append(buffer)
        }
        hasInputTap = true

        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            hasInputTap = false
            self.request = nil
            state = .failed("Captions couldn't start with this audio route.")
            return
        }

        state = .listening
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString ?? ""
            let isFinal = result?.isFinal ?? false
            let segments = result?.bestTranscription.segments.map { (location: $0.substringRange.location, start: $0.timestamp, end: $0.timestamp + $0.duration) } ?? []
            let errorMessage = error?.localizedDescription
            if let failure = error as NSError? { print("[MeetingSpeech] recognition failed domain=\(failure.domain) code=\(failure.code)") }
            Task { @MainActor [weak self] in
                self?.receive(
                    text: text,
                    isFinal: isFinal,
                    errorMessage: errorMessage,
                    sessionID: identifier,
                    recognitionID: recognition,
                    segments: segments
                )
            }
        }
    }

    private func receive(text: String, isFinal: Bool, errorMessage: String?, sessionID identifier: UUID, recognitionID recognition: UUID, segments: [(location: Int, start: TimeInterval, end: TimeInterval)]) {
        guard sessionID == identifier, recognitionID == recognition, task != nil else { return }
        let first = segments.first { $0.end > committedThrough + 0.001 }
        let utf16 = text as NSString
        let clean = first.map { utf16.substring(from: min($0.location, utf16.length)) }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        pendingThrough = segments.last?.end ?? committedThrough
        if !clean.isEmpty {
            pendingStartedAt = recognitionStartedAt.addingTimeInterval(first?.start ?? committedThrough)
            liveCaption = clean
            pendingUtterance = clean
        }

        if isFinal {
            receivedTerminal = true
            utteranceTimer?.cancel()
            emitPendingUtterance()
            retryCount = 0
            if !isFinishing { restart(sessionID: identifier) }
        } else if errorMessage != nil {
            receivedTerminal = true
            utteranceTimer?.cancel()
            emitPendingUtterance()
            retryCount += 1
            if isFinishing { return }
            if retryCount <= 2 {
                restart(sessionID: identifier)
            } else {
                teardownCurrentRecognition()
                state = .failed("Captions paused. Tap the transcript button to try again.")
            }
        } else if !clean.isEmpty {
            // Partial result while speech continues — (re)arm the silence
            // window. When no new words arrive for 850ms, the utterance is
            // final for our purposes.
            utteranceTimer?.cancel()
            utteranceTimer = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(850))
                guard !Task.isCancelled else { return }
                guard self?.recognitionID == recognition, self?.isFinishing == false else { return }
                self?.finalizeAfterSilence(sessionID: identifier)
            }
        }
    }

    /// Emits the buffered utterance after a natural pause and restarts the
    /// recognition task so the next phrase starts from a clean buffer.
    private func finalizeAfterSilence(sessionID identifier: UUID) {
        guard sessionID == identifier, task != nil else { return }
        emitPendingUtterance()
        retryCount = 0
        // Keep the input tap running across pauses; restart only at Speech's task boundary.
    }

    private func emitPendingUtterance() {
        let text = pendingUtterance.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingUtterance = ""
        liveCaption = ""
        guard !text.isEmpty else { return }
        committedThrough = max(committedThrough, pendingThrough)
        lastSpokenAt = pendingStartedAt
        onUtterance?(text)
    }

    private func restart(sessionID identifier: UUID) {
        teardownCurrentRecognition()
        state = .requestingPermission
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled, let self, self.sessionID == identifier else { return }
            self.restartTask = nil
            self.begin(sessionID: identifier)
        }
    }

    private func observeAudioChanges(sessionID identifier: UUID) {
        for name in [AVAudioSession.routeChangeNotification, AVAudioSession.interruptionNotification, AVAudioSession.mediaServicesWereResetNotification] {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.sessionID == identifier, !self.isFinishing else { return }
                    self.sessionID = nil
                    self.restartTask?.cancel(); self.restartTask = nil
                    self.teardownCurrentRecognition()
                    self.state = .unavailable("Audio route changed. Tap Retry in the transcript panel to resume captions.")
                }
            }
            audioObservers.append(token)
        }
    }

    private func teardownCurrentRecognition() {
        recognitionID = nil
        utteranceTimer?.cancel()
        utteranceTimer = nil
        if engine.isRunning { engine.stop() }
        if hasInputTap {
            engine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
    }
}
