import SwiftUI
import PhotosUI
import AuthenticationServices

/// Instagram-style DM thread.
///
/// - Header: avatar + name + presence subtitle, phone & video icons trailing.
/// - Bubbles: grouped by sender (corner radius adapts to position in a run),
///   timestamp separator inserted on 15+ min gaps.
/// - Double-tap to add a ❤️ reaction; long-press opens a 6-emoji picker.
/// - Composer mirrors IG: camera capsule, rounded input with photo/mic
///   buttons inside, send button replaced by a heart quick-react when empty.
/// - Inline workout cards rendered when the message body is an encoded
///   `WhisperWorkoutEmbed` payload.
struct WhisperDMThreadView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let otherUserID: String
    let otherUsername: String
    var conversationKind: WhisperConversationKind = .direct
    var onExternalClose: (() -> Void)? = nil
    private func closeThread() { if let onExternalClose { onExternalClose() } else { dismiss() } }
    private var conversationKey: String { conversationKind.localKey(peer: otherUserID) }
    @State private var matchSending: Bool = false

    @State private var backend = WhisperBackendService.shared
    @State private var presence = WhisperPresenceService.shared
    /// Mirror of the app-wide call service. The root view's `fullScreenCover`
    /// can't surface over this screen because this screen is itself a
    /// `fullScreenCover` from the Inbox — so we attach our own cover bound
    /// to the same shared `active` state. SwiftUI presents whichever cover
    /// is currently on top, so the incoming-call sheet pops immediately
    /// while the user is reading messages.
    @State private var draft: String = ""
    @State private var backTransition: WhisperBackAction = WhisperBackAction()
    @State private var confirmBack: Bool = false
    @State private var loadedDraft: Bool = false
    @State private var draftGeneration = AccountStorage.generation
    /// Marked 💘 — shows cupid Jasper's date tools above the composer.
    @State private var isDatingChat: Bool = false
    /// 💘 mutual match — the full-screen linking celebration.
    @State private var showMatchCelebration: Bool = false
    /// My public profile — the celebration needs my avatar + handle.
    @State private var myProfile: WhisperBackendService.WhisperPublicProfile?
    @State private var sending: Bool = false
    @State private var revealedTimestampID: String?
    @State private var showFixSheet: Bool = false
    @State private var copyConfirmed: Bool = false
    /// Shared server-confirmed reactions, scoped to rendered messages.
    @State private var reactions = WhisperDMReactionsStore()
    @State private var savedWorkoutIDs: Set<String> = []
    @State private var otherProfile: WhisperBackendService.WhisperPublicProfile?
    /// Drives the navigation push to the other user's full profile page.
    /// Set when the user taps the header avatar/name; cleared by the back
    /// chevron.
    @State private var pushedProfile: WhisperUserRow?
    @Namespace private var detailsTransition
    @State private var initialMessagesLoading = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showDMDetails: Bool = false
    private var chatPalette: WhisperChatPalette { WhisperChatAppearance.classic.palette(colorScheme) }
    @State private var pendingDetailsMessage: String?
    @State private var coach = WhisperCoachService.shared
    @State private var savedProgramIDs: Set<String> = []
    /// Paid-program ids this user may open (owner, buyer, or free fallback).
    @State private var unlockedProgramIDs: Set<String> = []
    /// Program id currently mid-checkout — shows a spinner on that card.
    @State private var buyingProgramID: String?
    @State private var savedCoachMacrosIDs: Set<String> = []
    @State private var savedCoachDietPlanIDs: Set<String> = []
    /// Up to ten photos picked at once — each sends as its own message and
    /// the thread renders the run as one fanned stack.
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var photoPickerPresented: Bool = false
    /// The full-screen photo moment (lives in the thread's own layer).
    @State private var photoViewer: WhisperChatPhotoViewerContext?
    @State private var infoToast: String?
    @State private var smartReplies: [String] = []
    @State private var loadingSmartReplies: Bool = false
    @State private var followsLatest: Bool = true
    @State private var scrollingHistory: Bool = false
    @State private var historyNearTop: Bool = false
    @State private var historyPaginationInFlight: Bool = false
    @State private var composerHeight: CGFloat = 64
    @State private var conversationHeaderHeight: CGFloat = 113
    @State private var showJasperIntelligence: Bool = false
    @State private var jasperTurnID: UUID = UUID()
    @State private var jasperGeneration: UUID?
    @State private var jasperSharing: Bool = false
    @State private var jasperQuestionWasSent: Bool = false
    @State private var jasperError: String?
    @State private var emberAnswer: String?
    @State private var emberAnswerQuestion: String?
    @State private var emberAnswerSources: [String] = []
    /// Whether the inline (pre-send) Jasper answer preview is expanded.
    /// Defaults to compact so long answers never take over the thread
    /// before the user has decided to share.
    @State private var emberAnswerExpanded: Bool = false
    /// The native card (chart/goalplan/schedule) Jasper produced for the
    /// inline DM answer — same fenced-block grammar the full-screen Jasper
    /// renders, because both go through the SAME shared engine.
    @State private var emberBlock: WhisperEmberBlocks.Block?
    /// The real `/interpret` trace behind the inline DM answer, surfaced as a
    /// tappable thinking chip exactly like the full-screen chat.
    @State private var emberInterpret: WhisperInterpretResult?
    /// The interpreter result presented in the detail sheet (chip tapped).
    @State private var presentedDMInterpret: IdentifiedDMInterpret?
    @State private var factCheckPreview: WhisperFactCheckEmbed.Payload?
    @State private var factCheckTarget: String?
    @State private var factCheckSharing: Bool = false
    @State private var factCheckShareError: String?
    @State private var factCheckWorking: Bool = false
    @State private var factCheckOperation: UUID?
    @State private var showSlashPalette: Bool = false
    @State private var emberThinking: Bool = false
    @State private var knotActivity = "Preparing request…"
    @State private var showKnotConsent = false
    /// Meeting-notes payload open in the full notes modal (tapped a notes card).
    @State private var meetingNotesDetail: WhisperMeetingNotesMessage.Payload?
    @State private var emberAboutUser: String?
    @State private var showEmberAboutUserSheet: Bool = false
    @State private var ember = WhisperEmberService.shared
    /// The SHARED Jasper turn engine — the exact same one the full-screen
    /// `WhisperEmberChatView` uses. Routing the in-DM `@ember` path through it
    /// means DM answers run the real `/interpret` Python analysis and render
    /// real chart cards, byte-for-byte identical to full-screen Jasper.
    private let emberEngine = WhisperEmberEngine()
    @State private var mapDetail: WhisperMapEmbed.Payload?
    @State private var recipeDetail: WhisperRecipeEmbed.Payload?
    @State private var sharedPostDetail: WhisperSharedPostEmbed.Payload?
    /// A shared WAVE opens in the full-screen Waves player — never the post
    /// detail — with the rest of the loaded waves queued behind it.
    @State private var sharedWave: WhisperPost?
    @State private var sharedProfileDetail: WhisperProfileShareEmbed.Payload?
    /// True while a slash-command send (chart / recipe / grocery / check-in
    /// / photo-log…) is building its card — drives the visible progress
    /// chip above the composer.
    @State private var emberWorking: Bool = false
    @State private var imaginePrompt: String = ""
    @State private var showImagineSheet: Bool = false
    @State private var showAttachTray: Bool = false
    @State private var imagineLoading: Bool = false
    @State private var pendingImagines: [PendingImagine] = []
    @State private var showDrawSheet: Bool = false
    @State private var showGifPicker: Bool = false
    @State private var showStickerPicker: Bool = false
    @State private var blocks = WhisperBlockService.shared
    @State private var dmMeeting: WhisperMeetingRow?
    @State private var presentReport: Bool = false
    @State private var presentBlockConfirm: Bool = false
    @State private var initialScrollPending = true
    @State private var entryVisible = false
    @State private var entryID = UUID()
    @State private var initialScrollTask: Task<Void, Never>?
    // Auto-schedule: a future date spotted in the conversation → one-tap
    // shared-calendar event with an attached Whisper meeting.
    @State private var scheduleSuggestion: WhisperChatScheduleDetector.Suggestion?
    @State private var showScheduleSheet: Bool = false
    @State private var showMeetSchedule: Bool = false
    @State private var showNotes: Bool = false
    @State private var dismissedScheduleIDs: Set<String> = []
    /// Whether the recipient has flipped Private on AND I'm not already
    /// following them. Surfaces a soft banner above the composer letting
    /// me know the message will arrive in their Requests folder until
    /// they approve.
    @State private var recipientIsPrivate: Bool = false
    @State private var iFollowRecipient: Bool = false
    /// Branded Whisper action sheet — drives the thread 3-dots menu, the
    /// message long-press menu (with the emoji reaction strip), and the
    /// Unsend / Delete / Block confirmations. One state because only one
    /// menu is ever open at a time.
    @State private var actionMenu: WhisperActionMenuModel?
    /// THE LONG-PRESS MOMENT — the pressed message + its on-screen frame.
    /// While non-nil the thread blurs in place and the overlay renders the
    /// lifted bubble, the reaction strip, and the actions card.
    @State private var pressed: PressedMessage?
    /// Arms the one-shot frame capture on the bubble that was just pressed.
    @State private var pressCaptureID: String?
    /// The message a reply is being composed to — shows the strip above the
    /// field and wraps the outgoing body in the shared reply grammar.
    @State private var replyingTo: WhisperMessageRow?
    /// Forward — the recipient picker's payload.
    @State private var forwardPayload: ForwardPayload?
    /// Set to scroll the thread to a message (tapping a reply quote).
    @State private var scrollTargetID: String?

    struct PressedMessage: Identifiable {
        var id: String { msg.id }
        let msg: WhisperMessageRow
        let frame: CGRect
        let isFirstInRun: Bool
        let isLastInRun: Bool
    }

    struct ForwardPayload: Identifiable {
        let id = UUID()
        let body: String
    }

    /// Debounced smart-reply fetch — one in flight, cancelled by the next arrival.
    @State private var smartReplyTask: Task<Void, Never>?

    /// Identifiable wrapper so the interpreter detail sheet can use
    /// `.sheet(item:)` even though `WhisperInterpretResult` isn't Identifiable.
    struct IdentifiedDMInterpret: Identifiable {
        let id = UUID()
        let result: WhisperInterpretResult
    }

    /// Auto fact-check results keyed by message id. When verdict is
    /// `.falseClaim` or `.misleading`, a small gray disclaimer is rendered
    /// underneath the incoming bubble.
    @State private var autoFactFlags: [String: WhisperEmberService.FactCheck] = [:]
    @State private var autoFactCheckedIDs: Set<String> = []
    @FocusState private var focused: Bool

    /// One in-flight Imagine generation rendered as a ghost bubble in the
    /// scroll while the model works. The user can keep messaging while these
    /// are running.
    struct PendingImagine: Identifiable, Equatable {
        let id: UUID
        let prompt: String
        init(prompt: String) { self.id = UUID(); self.prompt = prompt }
    }

    /// The reaction strip — the reference order: ❤️ 😂 😮 😢 😡 👍.
    private static let reactionEmojis: [String] = ["❤️", "😂", "😮", "😢", "😡", "👍"]
    private var currentUID: String { AccountStorage.currentUserID }
    private var currentUIDLower: String { currentUID.lowercased() }
    /// THE RENDER INDEX — the 1:1 rows (group fan-out excluded), thought-reply
    /// embeds dropped, grouped into runs with their timestamp chips, plus the
    /// "Seen" marker — built once per data change and served from memory.
    /// The body reads this a dozen times per render (every keystroke); it
    /// used to re-filter and re-sort every time.
    private var threadIndex: WhisperChatThreadIndex.Index {
        WhisperChatThreadIndex.shared.index(
            key: "dm:\(conversationKey)",
            rows: backend.directMessages(with: otherUserID, kind: conversationKind),
            currentUIDLower: currentUIDLower,
            revision: backend.messageRevision
        )
    }

    private var messages: [WhisperMessageRow] { threadIndex.messages }

    /// Mutual-match state read straight off the thread's wire tokens —
    /// matched when a matched token exists OR both sides asked.
    private enum DatingMatchState { case none, requestedByMe, requestedByThem, matched }

    private var datingMatchState: DatingMatchState {
        var mine = false
        var theirs = false
        for msg in messages {
            guard !msg.id.hasPrefix("local-"), let token = WhisperMatchWire.decode(msg.body),
                  token.fromUserID.lowercased() == msg.from_user_id.lowercased() else { continue }
            if token.isMatched { return .matched }
            if msg.from_user_id.lowercased() == currentUIDLower { mine = true } else { theirs = true }
        }
        if mine && theirs { return .matched }
        if mine { return .requestedByMe }
        if theirs { return .requestedByThem }
        return .none
    }

    /// True when this thread already carries answers for the given plan
    /// questionnaire — collapses the quiz card into its answered state.
    private func hasQuizAnswers(quizID: String) -> Bool {
        messages.contains { WhisperPlanQuizAnswersEmbed.decode($0.body)?.quizId == quizID }
    }

    /// A shared WAVE opens in the Waves player (the real wave, full screen,
    /// swipeable); everything else keeps opening the post detail. Prefers
    /// the live cached row so counts and media are current; falls back to
    /// the embed when the row isn't loaded.
    private func openSharedPost(_ payload: WhisperSharedPostEmbed.Payload) {
        let id = payload.postID.lowercased()
        if payload.commentID == nil, let row = backend.posts.first(where: { $0.id.lowercased() == id }) {
            let live = WhisperRootView.mapRowToPost(
                row,
                fallbackUsername: backend.postAuthorProfiles[row.user_id]?.username
            )
            if live.isReel {
                sharedWave = live
                return
            }
        }
        sharedPostDetail = payload
    }

    /// The shared wave first, then every other loaded wave ranked by the
    /// Waves algorithm — so swiping on from a DM keeps going.
    private func wavesPool(leadingWith wave: WhisperPost) -> [WhisperPost] {
        let others = backend.posts
            .map { row in
                WhisperRootView.mapRowToPost(row, fallbackUsername: backend.postAuthorProfiles[row.user_id]?.username)
            }
            .filter { $0.id != wave.id && ($0.isReel || $0.mediaURLs.contains(where: { WhisperVideo.isVideo($0) })) }
        return [wave] + WhisperAlgorithmService.wavesRank(others)
    }

    var body: some View {
        themedConversation.environment(\.whisperChatAppearance, .classic)
            .environment(\.whisperChatDesign, nil)
    }

    private var themedConversation: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                chatPalette.canvas.ignoresSafeArea()
                ZStack(alignment: .top) {
                    messagesList
                        .contentMargins(.top, conversationHeaderHeight, for: .scrollContent)
                    VStack(spacing: 0) {
                        customHeader
                        if let err = backend.lastError { errorBanner(err) }
                        WhisperTeenSafetyBanner(
                            viewerUserID: currentUID,
                            otherUserID: otherUserID,
                            otherUsername: displayUsername
                        )
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { conversationHeaderHeight = $0 }
                }
                // The press blur lives in the overlay as a GPU material — the
                // live thread stays untouched, so the press answers instantly.
                VStack(spacing: 0) {
                    jasperPill
                    emberChips
                    if let suggestion = scheduleSuggestion, !showScheduleSheet {
                        WhisperChatSchedulePrompt(
                            suggestion: suggestion,
                            onAdd: { showScheduleSheet = true },
                            onDismiss: { dismissScheduleSuggestion() }
                        )
                    }
                    if recipientIsPrivate && !iFollowRecipient {
                        privateAccountHint
                    }
                    if isDatingChat {
                        cupidToolsRow
                    }
                    composer
                }
                .whisperChatContent()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { composerHeight = $0 }
                .animation(.smooth(duration: 0.22), value: emberWorking)
                // The press blur lives in the overlay as a GPU material — the
                // live thread stays untouched, so the press answers instantly.

                if let pressed {
                    pressOverlay(pressed)
                        .zIndex(50)
                        .transition(.opacity)
                }

                if let photoViewer {
                    WhisperChatPhotoViewer(
                        context: photoViewer,
                        onReply: { quoted, text in
                            Task {
                                let body = WhisperChatReply.body(quoting: quoted, with: text)
                                _ = await sendConversationMessage(toUserID: otherUserID, toUsername: otherUsername, body: body)
                            }
                        },
                        onForward: { msg in forwardPayload = ForwardPayload(body: msg.body) },
                        onPickPhoto: { photoPickerPresented = true },
                        onClose: { withAnimation(.easeOut(duration: 0.18)) { self.photoViewer = nil } }
                    )
                    .zIndex(60)
                    .transition(.opacity)
                }

                if showMatchCelebration {
                    WhisperMatchCelebrationView(
                        myName: myProfile?.username ?? "you",
                        myAvatarURL: (myProfile?.profile_image_url).flatMap { URL(string: $0) },
                        otherName: displayUsername,
                        otherAvatarURL: otherImageURL,
                        onDismiss: {
                            withAnimation(.easeOut(duration: 0.25)) { showMatchCelebration = false }
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 1.05)))
                    .zIndex(60)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .whisperEdgeBack(isEnabled: photoViewer == nil && pressed == nil && pressCaptureID == nil && !showMatchCelebration && !sending && !showDMDetails, requiresDecision: !draft.isEmpty, controller: backTransition) { requestBack() }
            .confirmationDialog("Keep your message?", isPresented: $confirmBack, titleVisibility: .visible) {
                Button("Save draft") { AccountStorage.set(draft, forKey: messageDraftKey); backTransition.perform { closeThread() } }
                Button("Discard", role: .destructive) { AccountStorage.removeObject(forKey: messageDraftKey); draft = ""; backTransition.perform { closeThread() } }
                Button("Keep editing", role: .cancel) {}
            }
            .onAppear { if !loadedDraft { loadedDraft = true; if draft.isEmpty { draft = AccountStorage.string(forKey: messageDraftKey) ?? "" } } }
            .onChange(of: draft) { _, value in
                guard draftGeneration == AccountStorage.generation else { return }
                if value.isEmpty { AccountStorage.removeObject(forKey: messageDraftKey) }
                else { AccountStorage.set(value, forKey: messageDraftKey) }
            }
            .task { await reactions.watch() }
            .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in reactions.reset() }
            .alert("Reaction not saved", isPresented: Binding(get: { reactions.failure != nil }, set: { if !$0 { reactions.failure = nil } })) {
                Button("OK") { reactions.failure = nil }
            } message: { Text(reactions.failure ?? "Please try again.") }
            .task(id: WhisperMessageReadScope.unreadIDs(rows: messages, recipient: currentUIDLower, sender: otherUserID)) {
                guard UIApplication.shared.applicationState == .active else { return }
                await backend.markRead(otherUserID: otherUserID, kind: conversationKind)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                Task { await backend.fetchConversation(peer: otherUserID, kind: conversationKind); await backend.markRead(otherUserID: otherUserID, kind: conversationKind); await reactions.refresh() }
            }
            .task(id: entryID) { await loadEntry() }
            .task {
                // Keep the header's "Active …" label fresh while the thread
                // stays open — the single fetch on entry goes stale within
                // minutes. Cancelled automatically with the view.
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                    guard UIApplication.shared.applicationState == .active else { continue }
                    await presence.refresh(userID: otherUserID)
                }
            }
            .onChange(of: messages.count) { _, _ in
                refreshScheduleSuggestion()
                maybeCelebrateMatch()
            }
            .sheet(isPresented: $showKnotConsent) {
                NavigationStack { WhisperKnotConsentView(onChange: {}, onContinue: {}, sharedConversation: true) }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showNotes) { WhisperNotesEntryView() }
            .sheet(isPresented: $showMeetSchedule) {
                WhisperChatMeetScheduleView(conversationKind: conversationKind.rawValue, peerID: otherUserID,
                    conversationTitle: "@\(displayUsername)", inviteeNames: ["@\(displayUsername)"],
                    onScheduled: { showToast("Meeting scheduled for this chat") })
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in showMeetSchedule = false }
            .sheet(isPresented: $showScheduleSheet) {
                if let suggestion = scheduleSuggestion {
                    WhisperChatScheduleSheet(
                        taggedIDs: [otherUserID],
                        taggedNames: [displayUsername],
                        contextNote: "Planned in chat with @\(displayUsername)",
                        initial: suggestion,
                        onScheduled: { message in
                            dismissScheduleSuggestion()
                            showToast(message)
                        }
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(item: $presentedDMInterpret) { item in WhisperEmberInterpretSheet(result: item.result) }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
                entryVisible = false; cancelInitialPositioning()
                jasperGeneration = nil
                jasperSharing = false; jasperError = nil
                emberThinking = false
                dismissEmberAnswer()
            }
            .onDisappear {
                entryVisible = false; cancelInitialPositioning()
                backend.closeConversation(peer: otherUserID, kind: conversationKind)
                smartReplyTask?.cancel(); smartReplyTask = nil
                factCheckOperation = nil; factCheckWorking = false
                jasperGeneration = nil
                if emberThinking { jasperError = "This request was paused. Tap Try again to continue." }
                emberThinking = false
                if WhisperNotificationService.shared.activeThreadOtherUID == otherUserID {
                    WhisperNotificationService.shared.activeThreadOtherUID = nil
                }
            }
            .whisperActionMenu($actionMenu)
            .sheet(item: $forwardPayload) { payload in
                WhisperPickRecipientSheet(payload: payload.body) {
                    forwardPayload = nil
                    showToast("Forwarded")
                }
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showFixSheet) { fixSheet }
            .sheet(isPresented: $presentReport) {
                WhisperReportSheet(
                    kind: .dm,
                    targetID: nil,
                    targetUserID: otherUserID,
                    targetUsername: displayUsername
                )
            }
            .onAppear {
                if let target = pendingDetailsMessage { scrollTargetID = target; pendingDetailsMessage = nil }
            }
            .navigationDestination(isPresented: $showDMDetails) {
                WhisperDMDetailsView(user: makePushProfileRow(), messages: messages, conversationKey: conversationKey,
                    onAudioCall: { Task { await startAudioCall() } },
                    onVideoCall: { Task { await startVideoCall() } }) { id in
                    pendingDetailsMessage = id
                    showDMDetails = false
                }
                .modifier(WhisperPortraitDestination(sourceID: "conversation-portrait", namespace: detailsTransition))
            }
            .navigationDestination(item: $pushedProfile) { user in
                WhisperUserProfileView(user: user)
            }
            .sheet(isPresented: $showEmberAboutUserSheet) { emberAboutUserSheet }
            .fullScreenCover(isPresented: $showJasperIntelligence) { WhisperEmberChatView() }
            .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in showJasperIntelligence = false }
            // FULL SCREEN — notes are a whole-page experience, matching the
            // Meetings list and the web's ended-meeting screen.
            .fullScreenCover(item: $meetingNotesDetail) { payload in
                WhisperMeetingNotesView(title: payload.title, notes: payload.notes, transcript: payload.transcript, meetingID: payload.meetingID)
            }
            .sheet(isPresented: $showImagineSheet) { imagineSheet }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperOpenImagineSheet"))) { _ in
                showImagineSheet = true
            }
            .sheet(isPresented: $showDrawSheet) {
                WhisperDrawSheet { image in
                    Task { await sendDrawing(image) }
                }
            }
            .sheet(isPresented: $showGifPicker) {
                WhisperGifPickerSheet { url in
                    Task { await sendMediaURL(url) }
                }
            }
            .sheet(isPresented: $showStickerPicker) {
                WhisperStickerPickerSheet(includesWhisperPack: true) { url in
                    Task { await sendMediaURL(url) }
                }
            }
            .onChange(of: dmMeeting?.id) { _, _ in
                // Meetings live in their own floating window now (supports
                // in-app PiP), so present through the manager instead of a
                // full-screen cover.
                if let meeting = dmMeeting {
                    WhisperMeetingWindow.shared.present(meeting)
                    dmMeeting = nil
                }
            }
            .sheet(item: $mapDetail) { payload in
                WhisperMapDetailSheet(payload: payload)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $recipeDetail) { payload in
                WhisperRecipeDetailSheet(payload: payload) { ingredients in
                    recipeDetail = nil
                    Task { await sendGroceryFromIngredients(payload.title, items: ingredients) }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(item: $sharedPostDetail) { payload in
                WhisperReferencedPostView(postID: payload.postID, focusedCommentID: payload.commentID)
            }
            .fullScreenCover(item: $sharedWave) { wave in
                WhisperReelsPlayerView(reels: wavesPool(leadingWith: wave), start: wave)
            }
            .sheet(item: $sharedProfileDetail) { payload in
                NavigationStack {
                    WhisperUserProfileView(
                        user: WhisperUserRow(
                            user_id: payload.userID,
                            username: payload.username,
                            display_name: payload.displayName,
                            bio: payload.bio,
                            interests: nil,
                            profile_image_url: payload.avatarURL,
                            onboarded_at: nil,
                            is_private: nil
                        )
                    )
                }
            }
            .photosPicker(
                isPresented: $photoPickerPresented,
                selection: $photoItems,
                maxSelectionCount: 10,
                selectionBehavior: .ordered,
                matching: .any(of: [.images, .videos]),
                photoLibrary: .shared()
            )
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await attachPhotos(items) }
            }
            .overlay(alignment: .top) {
                if let toast = infoToast {
                    Text(toast)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(WhisperTheme.ink(colorScheme), in: Capsule())
                        .padding(.top, 60)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    private func sendConversationMessage(toUserID: String, toUsername: String, body: String) async -> Bool {
        await backend.sendMessage(toUserID: toUserID, toUsername: toUsername, body: body, conversationKind: conversationKind)
    }

    // MARK: - Custom header

    /// Stable, scroll-independent header that mirrors the reference
    /// screenshot: standalone back chevron, then the avatar (separate, not
    /// glued to the chevron), then name + role pill stacked beside it,
    /// then phone / video icons trailing. Never collapses or truncates.
    private var messageDraftKey: String { "whisper.dmDraft.\(conversationKey)" }
    private func requestBack() {
        guard !sending else { return }
        NSLog("[WhisperNavigation] DM back requested")
        if draft.isEmpty { backTransition.perform { closeThread() } } else { confirmBack = true }
    }

    private var customHeader: some View {
        WhisperConversationHeader(
            name: WhisperChatNicknamesView.nickname(thread: conversationKey, userID: otherUserID) ?? displayUsername,
            activity: emberThinking ? "Knot · \(knotActivity)" : (jasperSharing ? "Knot · sending answer…" : nil),
            onBack: { Haptics.tap(); requestBack() },
            onDetails: { focused = false; showDMDetails = true }
        ) {
            WhisperAvatar(username: displayUsername, size: WhisperConversationPortraitSize.header, imageURL: otherImageURL, ring: false)
                .matchedTransitionSource(id: "conversation-portrait", in: detailsTransition)
        } actions: {
            WhisperConversationCallMenu(
                audio: { Haptics.tap(); Task { await startAudioCall() } },
                video: { Haptics.tap(); Task { await startVideoCall() } })
        }
        .whisperChatContent()
        .background { WhisperConversationHeaderBackdrop() }
    }

    /// Subtitle under the username: shows the role pill (Coach / Verified /
    /// Moderator / Admin / Founder) when applicable, otherwise the presence
    /// label, otherwise a quiet "Whisper chat".
    @ViewBuilder
    private var headerSubtitle: some View {
        if let role = WhisperRoleResolver.descriptor(userID: otherUserID, username: displayUsername) {
            HStack(spacing: 5) {
                Image(systemName: role.systemImage)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(role.tint)
                Text(role.text)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(role.tint)
                if let label = presence.activeLabel(forUserID: otherUserID) {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(1)
                }
            }
        } else if let label = presence.activeLabel(forUserID: otherUserID) {
            HStack(spacing: 4) {
                if label == "Active now" {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                }
                Text(label)
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(1)
            }
        } else {
            Text("Whisper chat")
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
    }

    private func loadEntry() async {
        let generation = AccountStorage.generation, owner = currentUID, entry = entryID
        func isCurrentEntry() -> Bool {
            !Task.isCancelled && entryVisible && entryID == entry && generation == AccountStorage.generation && currentUID == owner
        }
        guard isCurrentEntry() else { return }
        WhisperNotificationService.shared.activeThreadOtherUID = otherUserID
        WhisperNotificationService.shared.activeThreadKind = conversationKind
        isDatingChat = conversationKind == .dating
        backend.startMessagesRealtime()
        await backend.fetchConversation(peer: otherUserID, kind: conversationKind)
        guard isCurrentEntry() else { return }
        initialMessagesLoading = false
        await backend.markRead(otherUserID: otherUserID, kind: conversationKind)
        guard isCurrentEntry() else { return }
        let recipient: WhisperBackendService.WhisperPublicProfile?
        if let cached = backend.threadProfiles[otherUserID] { recipient = cached }
        else { recipient = await backend.fetchPublicProfile(userID: otherUserID) }
        guard isCurrentEntry() else { return }
        otherProfile = recipient
        let ownProfile = await backend.fetchPublicProfile(userID: owner)
        guard isCurrentEntry() else { return }
        myProfile = ownProfile
        maybeCelebrateMatch()
        await coach.ensureCoachStatus(userID: otherUserID)
        guard isCurrentEntry() else { return }
        presence.startHeartbeat()
        await presence.refresh(userID: otherUserID)
        guard isCurrentEntry() else { return }
        let priv = await WhisperUserService.shared.isPrivate(userID: otherUserID)
        guard isCurrentEntry() else { return }
        recipientIsPrivate = priv
        iFollowRecipient = WhisperFollowService.shared.isFollowing(userID: otherUserID)
        await WhisperSafetyService.shared.preloadAgeBands(userIDs: [owner, otherUserID])
        guard isCurrentEntry() else { return }
        await WhisperSafetyService.shared.preloadWatchFlags(userIDs: [otherUserID], usernames: [displayUsername])
        guard isCurrentEntry() else { return }
        dismissedScheduleIDs = Set(UserDefaults.standard.stringArray(forKey: scheduleDismissKey) ?? [])
        refreshScheduleSuggestion()
    }

    // MARK: - Messages list

    private func loadOlderMessages(using proxy: ScrollViewProxy, retrying: Bool = false) {
        let history = backend.historyState(peer: otherUserID, kind: conversationKind)
        guard history.next != nil, !history.isLoading, !historyPaginationInFlight, retrying || history.error == nil else { return }
        historyPaginationInFlight = true
        cancelInitialPositioning()
        followsLatest = false
        let anchor = messages.first?.id
        let generation = AccountStorage.generation
        Task {
            defer { historyPaginationInFlight = false }
            await backend.fetchConversation(peer: otherUserID, kind: conversationKind, older: true)
            guard generation == AccountStorage.generation, !Task.isCancelled else { return }
            if let anchor { proxy.scrollTo(anchor, anchor: .top) }
        }
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 1).id("top-anchor")
                LazyVStack(spacing: 2) {
                    headerCard
                        .padding(.top, 24)
                        .padding(.bottom, 16)

                    let history = backend.historyState(peer: otherUserID, kind: conversationKind)
                    if history.isLoading && !messages.isEmpty {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .accessibilityLabel("Loading messages")
                    }
                    if history.error != nil {
                        VStack(spacing: 4) {
                            Text(history.retryOlder ? "Earlier messages are unavailable for a moment." : "Messages couldn’t refresh just now.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button {
                                if history.retryOlder {
                                    loadOlderMessages(using: proxy, retrying: true)
                                } else {
                                    Task { await backend.fetchConversation(peer: otherUserID, kind: conversationKind) }
                                }
                            } label: {
                                Text("Try again")
                                    .font(.footnote.weight(.semibold))
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(.borderless)
                            .disabled(history.isLoading)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .accessibilityElement(children: .contain)
                    }
                    let index = threadIndex
                    let groups = index.groups
                    ForEach(groups) { group in
                        if let stamp = group.timestamp {
                            Text(stamp)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        ForEach(Array(group.messages.enumerated()), id: \.element.id) { idx, msg in
                            if let run = photoRun(in: group.messages, startingAt: idx) {
                                // Photos sent together fan into ONE stack.
                                photoStackBubble(run)
                                    .id(msg.id)
                                    .padding(.top, idx == 0 ? 6 : 1)
                                    .transition(WhisperChatStyle.arrive(mine: msg.from_user_id.lowercased() == currentUIDLower))
                            } else if isPhotoContinuation(in: group.messages, at: idx) {
                                // Rides inside the stack above — keep its anchor
                                // for scroll-to, draw nothing.
                                Color.clear.frame(height: 0).id(msg.id)
                            } else {
                            VStack(spacing: 4) {
                                bubble(
                                    msg,
                                    isFirstInRun: idx == 0,
                                    isLastInRun: idx == group.messages.count - 1
                                )
                                if revealedTimestampID == msg.id,
                                   let d = WhisperBackendService.parseISO(msg.created_at) {
                                    Text(WhisperChatFormatters.exactStamp(d))
                                        .font(.caption2)
                                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                            .id(msg.id)
                            .padding(.top, idx == 0 ? 6 : 1)
                            .transition(WhisperChatStyle.arrive(mine: msg.from_user_id.lowercased() == currentUIDLower))
                            }
                        }
                    }

                    if messages.isEmpty {
                        if initialMessagesLoading || history.isLoading {
                            WhisperMessageThreadSkeleton()
                        } else if history.error == nil {
                            // The shared status above owns all refresh errors
                            // and retries, including an initially empty thread.
                            emptyState.padding(.top, 40)
                        }
                    }

                    // Inline Imagine loading bubbles — render as your own
                    // outgoing message until the real image is uploaded.
                    ForEach(pendingImagines) { pending in
                        HStack(alignment: .bottom, spacing: 6) {
                            Spacer(minLength: 60)
                            EmberImagineLoadingCard(
                                aspectRatio: 1,
                                title: "Imagining…",
                                subtitle: pending.prompt
                            )
                            .frame(width: 240)
                        }
                        .padding(.top, 6)
                        .id("pending-\(pending.id)")
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }

                    if factCheckWorking {
                        WhisperJasperConversationReply(question: "", answer: nil) { EmptyView() }
                            .id("fact-check-result")
                    } else if let fact = factCheckPreview {
                        factCheckPreviewCard(fact).id("fact-check-result")
                    }

                    if !emberThinking && !jasperSharing && (emberAnswer != nil || jasperError != nil) {
                        WhisperJasperConversationReply(
                            question: jasperQuestionWasSent ? "" : (emberAnswerQuestion ?? ""),
                            answer: emberAnswer,
                            isSharing: jasperSharing,
                            error: jasperError,
                            sources: emberAnswerSources,
                            onDismiss: { dismissEmberAnswer(); jasperError = nil },
                            onShare: { Task { await shareEmberAnswer() } },
                            onRetry: {
                                if emberAnswer != nil { Task { await shareEmberAnswer() } }
                                else { let prompt = emberAnswerQuestion ?? ""; Task { await askEmberInline(prompt: prompt) } }
                            }
                        ) {
                            EmptyView()
                        }
                        .contextMenu { Button("Dismiss private answer") { dismissEmberAnswer(); jasperError = nil } }
                        .id(jasperTurnID)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                    }

                    // Stable bottom anchor — sized to the composer inset so
                    // scrolling it to `.bottom` of the viewport lands the
                    // newest message in its natural position right above the
                    // composer / keyboard, not hidden under the input box.
                    Color.clear
                        .frame(height: composerBottomInset)
                        .id("bottom-anchor")
                }
                .padding(.horizontal, 12)
                .whisperChatContent()
            }
            .whisperRefreshable { await backend.fetchConversation(peer: otherUserID, kind: conversationKind) }
            .scrollDisabled(pressed != nil || pressCaptureID != nil)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentSize.height - geo.contentOffset.y - geo.containerSize.height < 100
            } action: { _, nearBottom in
                if scrollingHistory || nearBottom { followsLatest = nearBottom }
            }
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top < 80
            } action: { _, nearTop in
                historyNearTop = nearTop
                if nearTop && scrollingHistory { loadOlderMessages(using: proxy) }
            }
            .onScrollPhaseChange { _, phase in
                if phase == .tracking || phase == .interacting { cancelInitialPositioning() }
                scrollingHistory = phase == .interacting || phase == .decelerating
                // A fresh gesture at an already-reached edge must work too;
                // the geometry's near-top Bool need not change in that case.
                if scrollingHistory && historyNearTop { loadOlderMessages(using: proxy) }
            }
            .onChange(of: factCheckPreview?.id) { _, id in
                if id != nil, canFollowLatest { withAnimation(.smooth(duration: 0.24)) { proxy.scrollTo("fact-check-result", anchor: .center) } }
            }
            .onChange(of: factCheckWorking) { _, working in
                if working, canFollowLatest { withAnimation(.smooth(duration: 0.24)) { proxy.scrollTo("fact-check-result", anchor: .center) } }
            }
            .onChange(of: emberAnswer) { _, _ in
                if canFollowLatest { withAnimation(.smooth(duration: 0.24)) { proxy.scrollTo(jasperTurnID, anchor: .bottom) } }
            }
            .onChange(of: jasperTurnID) { _, _ in
                if canFollowLatest { proxy.scrollTo("bottom-anchor", anchor: .bottom) }
            }
            .onChange(of: composerHeight) { _, _ in
                if canFollowLatest { proxy.scrollTo("bottom-anchor", anchor: .bottom) }
            }
            .onChange(of: messages.count) { oldCount, _ in
                // Scroll to the trailing anchor (sits AFTER the composer
                // inset padding) so the newest bubble lands in its natural
                // resting position — flush above the composer / keyboard,
                // not hidden underneath it.
                if initialScrollPending { snapToBottom(proxy: proxy) }
                else if canFollowLatest {
                    withAnimation(oldCount == 0 || reduceMotion ? nil : .smooth(duration: 0.22)) {
                        proxy.scrollTo("bottom-anchor", anchor: .bottom)
                    }
                }
                // Live mark-read: messages arriving while the thread is OPEN
                // flip to read immediately (sender sees "Seen", inbox dot
                // never lights). Previously only the entry `.task` marked
                // read, so mid-conversation arrivals stayed unread until the
                // thread was reopened.
                scheduleSmartReplies()
            }
            .onChange(of: draft) { old, new in
                handleDraftChange(old: old, new: new)
            }
            .onChange(of: scrollTargetID) { _, target in
                guard let target else { return }
                cancelInitialPositioning()
                followsLatest = false
                withAnimation(.smooth(duration: 0.3)) {
                    proxy.scrollTo(target, anchor: .center)
                    revealedTimestampID = target
                }
                scrollTargetID = nil
            }
            .onAppear {
                entryVisible = true; entryID = UUID()
                followsLatest = true; scrollingHistory = false
                initialScrollPending = scrollTargetID == nil && pendingDetailsMessage == nil
                snapToBottom(proxy: proxy)
            }
            .onChange(of: messages.last?.id) { _, newID in
                if newID != nil { snapToBottom(proxy: proxy) }
            }
            .onScrollGeometryChange(for: CGSize.self) { $0.contentSize } action: { _, _ in
                if initialScrollPending { snapToBottom(proxy: proxy) }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: pendingImagines.count) { _, _ in
                if let last = pendingImagines.last, canFollowLatest {
                    withAnimation(.spring(response: 0.32)) {
                        proxy.scrollTo("pending-\(last.id)", anchor: .bottom)
                    }
                }
            }
        }
    }

    /// Entry-only retries wait for lazy rows to lay out. Gestures, an explicit
    /// history target, account changes and disappearance invalidate every retry.
    private func snapToBottom(proxy: ScrollViewProxy) {
        guard entryVisible, initialScrollPending, initialScrollTask == nil,
              !messages.isEmpty, canFollowLatest, scrollTargetID == nil else { return }
        let entry = entryID, generation = AccountStorage.generation
        initialScrollTask = Task { @MainActor in
            defer { if entryID == entry { initialScrollTask = nil } }
            for delay in [0, 60, 140] {
                do { try await Task.sleep(for: .milliseconds(delay)) } catch { return }
                guard !Task.isCancelled, entryVisible, entryID == entry,
                      generation == AccountStorage.generation, initialScrollPending,
                      canFollowLatest, scrollTargetID == nil else { return }
                var transaction = Transaction(animation: nil); transaction.disablesAnimations = true
                withTransaction(transaction) { proxy.scrollTo("bottom-anchor", anchor: .bottom) }
            }
            initialScrollPending = false
        }
    }

    private func cancelInitialPositioning() {
        initialScrollPending = false
        initialScrollTask?.cancel(); initialScrollTask = nil
    }

    /// Reserve space at the bottom of the scroll so the last bubble is never
    /// hidden under the floating composer. Bumped so the most-recent message
    /// sits cleanly *above* the composer instead of overlapping with it.
    private var canFollowLatest: Bool {
        followsLatest && !scrollingHistory && pressed == nil && pressCaptureID == nil
    }

    private var composerBottomInset: CGFloat {
        composerHeight + 8
    }

    private var headerCard: some View {
        VStack(spacing: 12) {
            WhisperAvatar(
                username: displayUsername,
                size: 92,
                imageURL: otherImageURL,
                ring: false
            )
            .overlay {
                Circle()
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                    .padding(-5)
            }
            VStack(spacing: 3) {
                Text(displayUsername)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("Whisper")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Button {
                Haptics.tap()
                focused = false
                pushedProfile = makePushProfileRow()
            } label: {
                Text("View profile")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(WhisperTheme.card(colorScheme), in: Capsule())
                    .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private var displayUsername: String {
        // Prefer the hydrated public profile, then a non-placeholder value
        // passed by the presenting screen, then the backend's cached
        // profile lookup (which self-heals by fetching the row once).
        if let u = otherProfile?.username, !u.isEmpty { return u }
        let placeholders: Set<String> = ["", "user", "you", "unknown"]
        if !placeholders.contains(otherUsername.trimmingCharacters(in: .whitespaces).lowercased()) {
            return otherUsername
        }
        return backend.cachedUsername(forUserID: otherUserID) ?? otherUsername
    }

    private var otherImageURL: URL? {
        otherProfile?.profile_image_url.flatMap(URL.init(string:))
    }

    private func showToast(_ message: String) {
        withAnimation(.spring(response: 0.3)) { infoToast = message }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { infoToast = nil }
        }
    }

    // MARK: - Auto-schedule from chat

    private var scheduleDismissKey: String {
        "whisper_sched_dismissed:\(otherUserID.lowercased())"
    }

    /// Re-scan the visible conversation for a future date worth scheduling.
    /// Runs on thread load and whenever a message arrives or is sent.
    private func refreshScheduleSuggestion() {
        // Only the recent tail can carry a date worth scheduling — scanning
        // the whole history on every arrival was pure waste.
        guard let found = WhisperChatScheduleDetector.detect(
            messages: Array(messages.suffix(40)),
            otherUsername: displayUsername
        ) else {
            scheduleSuggestion = nil
            return
        }
        if dismissedScheduleIDs.contains(found.messageID) {
            scheduleSuggestion = nil
        } else if scheduleSuggestion != found {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                scheduleSuggestion = found
            }
        }
    }

    /// Hide the current suggestion and remember the source message so the
    /// same date never re-prompts in this thread.
    private func dismissScheduleSuggestion() {
        guard let suggestion = scheduleSuggestion else { return }
        dismissedScheduleIDs.insert(suggestion.messageID)
        UserDefaults.standard.set(
            Array(dismissedScheduleIDs).suffix(60).map { String($0) },
            forKey: scheduleDismissKey
        )
        withAnimation(.easeOut(duration: 0.2)) {
            scheduleSuggestion = nil
        }
    }

    /// Uploads every picked photo in one go, then sends them IN ORDER as
    /// separate messages — the same wire as a single photo (web renders each
    /// one), while this thread gathers the run into a fanned stack.
    private func attachPhotos(_ items: [PhotosPickerItem]) async {
        guard !sending else { return }
        sending = true
        let account = AccountStorage.currentUserID
        let generation = AccountStorage.generation
        let quote = replyingTo
        defer { if generation == AccountStorage.generation { photoItems = []; sending = false } }
        for item in items {
            do {
                let url = try await WhisperChatMediaService.upload(item, accountID: account)
                try WhisperChatMediaService.checkAccount(account, generation: generation)
                let body = quote.map { WhisperChatReply.body(quoting: $0, with: url) } ?? url
                let ok = await sendConversationMessage(toUserID: otherUserID, toUsername: otherUsername, body: body)
                try WhisperChatMediaService.checkAccount(account, generation: generation)
                if ok, replyingTo?.id == quote?.id { replyingTo = nil }
                guard ok else { showToast("Attachment uploaded, but the message wasn't sent. Please try again."); return }
            } catch {
                guard generation == AccountStorage.generation else { return }
                showToast((error as? WhisperChatMediaService.Failure)?.errorDescription ?? "Couldn't prepare the attachment. Please try again.")
                return
            }
        }
        Haptics.soft()
    }

    // MARK: - Photo runs

    /// A message that is ONLY a still photo (a bare image URL that isn't a
    /// GIF / animated sticker).
    private func plainPhotoURL(_ msg: WhisperMessageRow) -> URL? {
        guard let url = Self.imageURL(in: msg.body) else { return nil }
        let s = url.absoluteString.lowercased()
        if s.contains(".gif") || url.host?.lowercased().contains("giphy.com") == true { return nil }
        return url
    }

    /// The run of two or more consecutive plain photos that STARTS at `idx`
    /// — nil when this message isn't the first of such a run.
    private func photoRun(in messages: [WhisperMessageRow], startingAt idx: Int) -> [WhisperMessageRow]? {
        guard messages.indices.contains(idx), plainPhotoURL(messages[idx]) != nil else { return nil }
        if idx > 0, plainPhotoURL(messages[idx - 1]) != nil { return nil }
        var end = idx + 1
        while end < messages.count, plainPhotoURL(messages[end]) != nil { end += 1 }
        guard end - idx >= 2 else { return nil }
        return Array(messages[idx..<end])
    }

    /// True for a plain photo that rides inside an earlier message's stack.
    private func isPhotoContinuation(in messages: [WhisperMessageRow], at idx: Int) -> Bool {
        guard idx > 0, messages.indices.contains(idx) else { return false }
        return plainPhotoURL(messages[idx]) != nil && plainPhotoURL(messages[idx - 1]) != nil
    }

    /// Opens the full-screen photo moment on `startIndex` of the given run.
    private func openPhotoViewer(_ run: [WhisperMessageRow], startIndex: Int) {
        let items: [WhisperChatPhotoItem] = run.compactMap { m in
            plainPhotoURL(m).map { WhisperChatPhotoItem(message: m, url: $0) }
        }
        guard !items.isEmpty, let first = run.first else { return }
        let mine = first.from_user_id.lowercased() == currentUIDLower
        focused = false
        Haptics.tap()
        withAnimation(.easeOut(duration: 0.16)) {
            photoViewer = WhisperChatPhotoViewerContext(
                items: items,
                startIndex: startIndex,
                senderLabel: mine ? "You" : "@\(displayUsername)",
                senderUsername: mine ? (myProfile?.username ?? first.from_username) : otherUsername,
                senderAvatarURL: mine ? (myProfile?.profile_image_url).flatMap { URL(string: $0) } : otherImageURL,
                isMine: mine
            )
        }
    }

    /// Several photos from one sender, sent together — the fanned stack.
    private func photoStackBubble(_ run: [WhisperMessageRow]) -> some View {
        let mine = run.first.map { $0.from_user_id.lowercased() == currentUIDLower } ?? false
        let urls = run.compactMap { plainPhotoURL($0) }
        return HStack(spacing: 0) {
            if mine { Spacer(minLength: 24) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                WhisperChatPhotoStack(urls: urls, mine: mine) { i in
                    openPhotoViewer(run, startIndex: i)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                ForEach(Array(run.enumerated()), id: \.element.id) { index, photo in
                    VStack(alignment: .leading, spacing: 0) {
                        Menu {
                            ForEach(Self.reactionEmojis, id: \.self) { emoji in
                                Button("\(emoji)\(reactions.selected(for: photo.id) == emoji ? " · Remove yours" : "")") { reactions.toggle(emoji, on: photo.id) }
                            }
                        } label: {
                            Text("Photo \(index + 1) · React").font(.caption2).foregroundStyle(.secondary)
                                .frame(minHeight: 32).contentShape(Rectangle())
                        }
                        WhisperMessageReactionsBar(reactions: reactions.reactions(for: photo.id), landingIDs: reactions.landingIDs(for: photo.id)) { reactions.toggle($0, on: photo.id) }
                    }
                    .onAppear { reactions.show(photo.id) }
                    .onDisappear { reactions.hide(photo.id) }
                    .onChange(of: photo.id) { old, new in reactions.hide(old); reactions.show(new) }
                }
                }
                }
                .frame(maxWidth: 260)
            }
            if !mine { Spacer(minLength: 24) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// Sends a public media URL (GIF / sticker) as a plain message body so
    /// the existing `imageURL(in:)` detection path can render it as an
    /// inline animated bubble on both sides of the thread.
    private func sendMediaURL(_ url: URL) async {
        _ = await sendConversationMessage(toUserID: otherUserID, toUsername: otherUsername, body: url.absoluteString)
    }

    /// Start a real ringing video call with this DM partner — presents
    /// Whisper's dedicated call screen (not the meeting room), rings their
    /// device (and the web client), and connects over the same mesh engine
    /// meetings use so everything just works across platforms.
    private func startVideoCall() async {
        await WhisperCallService.shared.startOutgoing(
            otherUserID: otherUserID,
            otherUsername: otherUsername,
            avatarURL: otherImageURL,
            mode: .video
        )
    }

    /// Same ringing flow as video, minus the camera — both sides see the
    /// avatar-over-blurred-photo stage while audio rides the mesh through
    /// the loudspeaker.
    private func startAudioCall() async {
        await WhisperCallService.shared.startOutgoing(
            otherUserID: otherUserID,
            otherUsername: otherUsername,
            avatarURL: otherImageURL,
            mode: .audio
        )
    }

    /// Builds the `WhisperUserRow` used by the navigation push to the
    /// other user's full profile page. Prefers the cached public profile
    /// when available so the destination renders with avatar + display
    /// name right away.
    private func makePushProfileRow() -> WhisperUserRow {
        if let p = otherProfile {
            return WhisperUserRow(
                user_id: p.id,
                username: p.username ?? otherUsername,
                display_name: p.display_name,
                bio: nil,
                interests: nil,
                profile_image_url: p.profile_image_url,
                onboarded_at: nil,
                is_private: nil
            )
        }
        return WhisperUserRow(
            user_id: otherUserID,
            username: otherUsername,
            display_name: nil,
            bio: nil,
            interests: nil,
            profile_image_url: nil,
            onboarded_at: nil,
            is_private: nil
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            WhisperMeetDoodle(symbol: "paperplane", height: 120)
            Text("Say hi to \(otherUsername)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
    }

    // MARK: - Bubble

    private func bubble(_ msg: WhisperMessageRow, isFirstInRun: Bool, isLastInRun: Bool) -> some View {
        let mine = msg.from_user_id.lowercased() == currentUIDLower
        let reaction = reactions.reactions(for: msg.id)
        let workout = WhisperWorkoutEmbed.decode(msg.body)

        return VStack(alignment: .trailing, spacing: 4) {
        HStack(alignment: .bottom, spacing: 6) {
            if !mine {
                if isLastInRun {
                    Button {
                        focused = false
                        Haptics.tap()
                        showDMDetails = true
                    } label: {
                        WhisperAvatar(username: displayUsername, size: WhisperConversationPortraitSize.message, imageURL: otherImageURL, ring: false)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(WhisperPortraitPressStyle())
                    .accessibilityLabel("\(displayUsername), conversation details")
                } else {
                    Color.clear.frame(width: 44, height: 26)
                }
            }
            if mine { Spacer(minLength: 44) }

            ZStack(alignment: mine ? .bottomTrailing : .bottomLeading) {
                bubbleBody(msg: msg, mine: mine, workout: workout, isFirstInRun: isFirstInRun, isLastInRun: isLastInRun)
                WhisperMessageReactionsBar(reactions: reaction, landingIDs: reactions.landingIDs(for: msg.id)) { reactions.toggle($0, on: msg.id) }
                    .offset(x: mine ? -7 : 7, y: 10)
            }

            if !mine { Spacer(minLength: 44) }
        }
        .padding(.bottom, reaction.isEmpty ? 0 : 16)
        if mine, msg.id == threadIndex.lastSeenMineID {
            WhisperAvatar(username: displayUsername, size: 24, imageURL: otherImageURL, ring: false)
                .accessibilityLabel("Seen by \(displayUsername)")
        }
        }
        .onAppear { reactions.show(msg.id) }
        .onDisappear { reactions.hide(msg.id) }
        .onChange(of: msg.id) { old, new in reactions.hide(old); reactions.show(new) }
    }

    @ViewBuilder
    private func bubbleBody(msg: WhisperMessageRow, mine: Bool, workout: WhisperWorkoutEmbed.Payload?, isFirstInRun: Bool, isLastInRun: Bool) -> some View {
        let program = WhisperProgramEmbed.decode(msg.body)
        let mapPayload = WhisperMapEmbed.decode(msg.body)
        let chartPayload = WhisperChartEmbed.decode(msg.body)
        let imageURL = Self.imageURL(in: msg.body)
        let jasperStickerName = WhisperStickerPack.stickerName(from: msg.body)
        Group {
            if let reply = replyParts(msg.body) {
                // A REPLY — checked FIRST so a reply that quotes a card never
                // decodes as the card. The reference look: "Replied to you"
                // above, the quoted message as a lighter bubble with a bar on
                // its outer edge (a MINI card when the original is a card or
                // photo), then the reply itself.
                let quotedMine = reply.quote.username.lowercased() == myUsernameLower
                let original = WhisperChatReply.original(for: reply.quote, in: messages)
                VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
                    Text(WhisperChatReply.label(mine: mine, quotedMine: quotedMine, otherName: displayUsername))
                        .font(.system(size: 12.5))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .padding(.horizontal, 12)
                    WhisperChatReplyQuoteView(quote: reply.quote, mine: mine, quotedMine: quotedMine, original: original) {
                        Haptics.tap()
                        if let original {
                            scrollTargetID = original.id
                        }
                    }
                    if let video = Self.videoURL(in: reply.text) {
                        WhisperChatVideoView(url: video)
                    } else if let image = Self.imageURL(in: reply.text) {
                        Color(.secondarySystemBackground).frame(width: 220, height: 220)
                            .overlay { WhisperCachedAsyncImage(url: image) { phase in
                                if case .success(let picture) = phase { picture.resizable().scaledToFit() }
                            }.allowsHitTesting(false) }
                            .clipShape(.rect(cornerRadius: 18))
                    } else {
                    Group {
                        if mine {
                            Text(reply.text)
                                .font(WhisperChatStyle.bodyFont)
                                .foregroundStyle(chatPalette.outgoingText)
                        } else {
                            WhisperMentionText(text: reply.text, font: WhisperChatStyle.bodyFont, inkColor: chatPalette.incomingText, linkColor: chatPalette.incomingText)
                        }
                    }
                    .padding(.horizontal, WhisperChatStyle.bubbleHorizontal)
                    .padding(.vertical, WhisperChatStyle.bubbleVertical)
                    .background {
                        bubbleShape(mine: mine, isFirstInRun: isFirstInRun, isLastInRun: isLastInRun)
                            .fill(chatPalette.fill(mine: mine))
                            .modifier(WhisperChatScrollTint(mine: mine))
                    }
                    .padding(.top, 4)
                    }
                }
            } else if msg.conversationKind == .direct, let artifactID = WhisperKnotArtifactWire.messageID(msg.body), artifactID.uuidString.lowercased() == msg.id.lowercased() {
                WhisperKnotDMArtifactCard(messageID: artifactID, mine: mine).id(msg.id + AccountStorage.generation.uuidString)
            } else if msg.conversationKind == .direct, WhisperTeamsInvitationCard.isCandidate(body: msg.body, messageID: msg.id) {
                WhisperTeamsInvitationCardView(message: msg).id(msg.id + AccountStorage.generation.uuidString)
            } else if let mapPayload {
                WhisperMapInlineCard(payload: mapPayload, mine: mine) {
                    Haptics.tap()
                    mapDetail = mapPayload
                }
            } else if let chartPayload {
                WhisperChartInlineCard(payload: chartPayload, mine: mine)
            } else if let healthShare = WhisperHealthShareEmbed.decode(msg.body) {
                WhisperHealthShareInlineCard(payload: healthShare, mine: mine) {
                    let ok = await WhisperHealthShareWriter.apply(healthShare)
                    if !ok { showToast("Couldn't sync to your Whisper charts. Try again.") }
                }
            } else if let answerPayload = WhisperEmberAnswerEmbed.decode(msg.body) {
                WhisperEmberAnswerInlineCard(payload: answerPayload, mine: mine)
            } else if WhisperThoughtReplyEmbed.decode(msg.body) != nil {
                // Filtered out at the messages source above; render nothing
                // defensively in case a row slips through.
                EmptyView()
            } else if let factPayload = WhisperFactCheckEmbed.decode(msg.body) {
                WhisperFactCheckInlineCard(payload: factPayload, mine: mine)
            } else if let recipePayload = WhisperRecipeEmbed.decode(msg.body) {
                WhisperRecipeInlineCard(payload: recipePayload, mine: mine) {
                    Haptics.tap()
                    recipeDetail = recipePayload
                }
            } else if let storyID = WhisperSharedStoryEmbed.decode(msg.body) {
                WhisperSharedStoryCard(storyID: storyID)
            } else if msg.body.hasPrefix(WhisperSharedCommunityEmbed.prefix) {
                if let community = WhisperSharedCommunityEmbed.decode(msg.body) {
                    WhisperSharedCommunityInlineCard(payload: community, mine: mine)
                } else { Text("This community is unavailable").font(.subheadline).foregroundStyle(.secondary) }
            } else if let sharedPost = WhisperSharedPostEmbed.decode(msg.body) {
                WhisperSharedPostInlineCard(payload: sharedPost, mine: mine) {
                    Haptics.tap()
                    openSharedPost(sharedPost)
                }
            } else if let filmEmbed = WhisperFilmEmbed.decode(msg.body) {
                // Shared Whisper film — a tappable cinema card that opens the
                // full theater (hydrates the real film row on tap).
                WhisperFilmEmbedInlineCard(payload: filmEmbed)
            } else if let articleEmbed = WhisperArticleEmbed.decode(msg.body) {
                // Shared journal article — opens the native reader on tap.
                WhisperArticleEmbedInlineCard(payload: articleEmbed)
            } else if let quiz = WhisperPlanQuizEmbed.decode(msg.body) {
                // Coach plan questionnaire — fully tappable for the client
                // (one tap per question), a compact "sent" card for the coach.
                WhisperPlanQuizInlineCard(
                    payload: quiz,
                    mine: mine,
                    answered: hasQuizAnswers(quizID: quiz.id)
                ) { answers in
                    let me = WhisperUserService.shared.me?.username
                        ?? LeaderboardService.shared.savedUsername
                        ?? AuthenticationService.shared.currentUser.username
                        ?? "client"
                    let payload = WhisperPlanQuizAnswersEmbed.Payload(
                        quizId: quiz.id, client: me, answers: answers)
                    _ = await sendConversationMessage(
                        toUserID: otherUserID,
                        toUsername: otherUsername,
                        body: WhisperPlanQuizAnswersEmbed.encode(payload)
                    )
                }
            } else if let quizAnswers = WhisperPlanQuizAnswersEmbed.decode(msg.body) {
                // The client's questionnaire answers — chip summary card.
                WhisperPlanQuizAnswersInlineCard(payload: quizAnswers, mine: mine)
            } else if let profileShare = WhisperProfileShareEmbed.decode(msg.body) {
                WhisperProfileShareInlineCard(payload: profileShare, mine: mine) {
                    Haptics.tap()
                    sharedProfileDetail = profileShare
                }
            } else if let macrosShare = WhisperMacrosShareEmbed.decode(msg.body) {
                WhisperMacrosShareInlineCard(payload: macrosShare, mine: mine) {
                    Task { await sendMacrosShare(isAccountability: true) }
                }
            } else if let checkin = WhisperCheckinEmbed.decode(msg.body) {
                WhisperCheckinInlineCard(payload: checkin, mine: mine) { sticker in
                    Task {
                        _ = await sendConversationMessage(toUserID: otherUserID, toUsername: otherUsername, body: sticker)
                    }
                }
            } else if let proposal = WhisperWorkoutProposalEmbed.decode(msg.body) {
                WhisperWorkoutProposalInlineCard(payload: proposal, mine: mine) {
                    Task { await acceptWorkoutProposal(proposal) }
                }
            } else if let grocery = WhisperGroceryListEmbed.decode(msg.body) {
                WhisperGroceryInlineCard(payload: grocery, mine: mine)
            } else if let macrosPayload = WhisperCoachMacrosEmbed.decode(msg.body) {
                coachMacrosBubble(macrosPayload, mine: mine)
            } else if let dietPayload = WhisperCoachDietPlanEmbed.decode(msg.body) {
                coachDietPlanBubble(dietPayload, mine: mine)
            } else if let proposalPayload = WhisperCoachProposalEmbed.decode(msg.body) {
                WhisperCoachProposalInlineCard(payload: proposalPayload, mine: mine)
            } else if let callSummary = WhisperCallSummaryEmbed.decode(msg.body) {
                WhisperCallSummaryInlineCard(payload: callSummary, mine: mine) {
                    // Calls are disabled.
                }
            } else if msg.notesCard != nil {
                // No official branding/actions based on a broadly writable embed.
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: msg.body).font(.callout).textSelection(.enabled)
                    Text("Status not checked").font(.caption).foregroundStyle(.secondary)
                }.padding(14).frame(maxWidth: 280, alignment: .leading)
                    .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
            } else if let notesPayload = WhisperMeetingNotesMessage.parse(msg.body) {
                // AI meeting notes arrive as a tappable Jasper card that opens
                // the formatted notes modal — never a wall of plain text.
                WhisperMeetingNotesDMCard(payload: notesPayload, mine: mine) {
                    Haptics.tap()
                    meetingNotesDetail = notesPayload
                }
            } else if let invitation = WhisperMeetingInvitation.fromText(msg.body) {
                WhisperMeetingDMBubble(invitation: invitation, mine: mine)
            } else if let calInvite = WhisperCalendarEmbed.decode(msg.body) {
                WhisperCalendarInlineCard(payload: calInvite, mine: mine) {
                    // Close the DM thread FIRST — while it's presented it
                    // blocks the root's calendar cover, which used to leave
                    // the tap doing nothing until you exited Messages. Once
                    // the dismissal settles, ask the root to open the
                    // calendar as usual.
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        NotificationCenter.default.post(
                            name: Notification.Name("WhisperOpenCalendar"),
                            object: nil
                        )
                    }
                }
            } else if let program {
                programBubble(program, mine: mine)
            } else if let workout {
                workoutBubble(workout, mine: mine)
            } else if let jasperStickerName {
                Image(WhisperStickerPack.assetName(for: jasperStickerName))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
            } else if let videoURL = Self.videoURL(in: msg.body) {
                WhisperChatVideoView(url: videoURL)
            } else if let imageURL {
                // Animated GIF / sticker URLs (Giphy) need a real WKWebView
                // host so the frames actually play; static images stay on
                // AsyncImage so they decode efficiently.
                let isAnimated = imageURL.absoluteString.lowercased().contains(".gif") ||
                    imageURL.host?.lowercased().contains("giphy.com") == true
                if isAnimated {
                    Color.clear
                        .frame(width: 200, height: 200)
                        .overlay {
                            WhisperAnimatedGIFView(url: imageURL, contentMode: .fit)
                                .allowsHitTesting(false)
                        }
                        .clipShape(.rect(cornerRadius: 18))
                } else {
                    // A still photo — tap opens the full photo moment.
                    Button {
                        openPhotoViewer([msg], startIndex: 0)
                    } label: {
                        WhisperCachedAsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            case .failure:
                                Color(.secondarySystemBackground)
                                    .overlay {
                                        Image(systemName: "photo")
                                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                                    }
                            default:
                                Color(.secondarySystemBackground)
                                    .overlay { ProgressView() }
                            }
                        }
                        .frame(width: 220, height: 220)
                        .clipShape(.rect(cornerRadius: 18))
                    }
                    .buttonStyle(WhisperMenuPressStyle())
                    .accessibilityLabel("Photo")
                }
            } else if let (dateInvite, isConfirm) = WhisperSecondDate.decode(msg.body) {
                // 📅 second-date wire — the rose scheduler card (Accept / Join),
                // never the raw token.
                WhisperSecondDateCard(
                    invite: dateInvite,
                    isConfirm: isConfirm,
                    isMine: mine,
                    partnerUserID: otherUserID,
                    partnerName: displayUsername,
                    onOpenMeet: { code in
                        Task {
                            // Same recipe as Join-with-a-code: hash the code to
                            // the shared room id, create it if we're first.
                            let id = WhisperMeetingService.resolveRoomID(WhisperMeetingService.meetingID(fromText: code) ?? code)
                            var row = await WhisperMeetingService.shared.fetch(id: id)
                            if row == nil {
                                await WhisperMeetingService.shared.ensureRoom(id: id, title: "Second date 💘")
                                row = await WhisperMeetingService.shared.fetch(id: id)
                            }
                            if let row {
                                await MainActor.run { WhisperMeetingWindow.shared.present(row) }
                            }
                        }
                    }
                )
            } else if let match = WhisperMatchWire.decode(msg.body) {
                // 💘 match wire — quiet rose system line, never the raw token.
                HStack(spacing: 6) {
                    Image(systemName: match.isMatched ? "heart.fill" : "heart")
                        .font(.caption2.weight(.bold))
                    Text(
                        match.isMatched
                            ? "It's a match! You and @\(displayUsername) 💘"
                            : (mine ? "You asked to match 💘" : "@\(displayUsername) wants to match 💘")
                    )
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                }
                .foregroundStyle(Color(red: 0.91, green: 0.28, blue: 0.49))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(red: 0.91, green: 0.28, blue: 0.49).opacity(0.10), in: Capsule())

            } else if msg.body.hasPrefix(WhisperGroupChatService.headerPrefix) {
                // Group-chat wire row (web-created groups fan out as 1:1
                // rows) — render a quiet system line, never the raw wire.
                HStack(spacing: 6) {
                    Image(systemName: "person.3.fill")
                        .font(.caption2.weight(.bold))
                    Text(
                        WhisperGroupChatService.parse(msg.body)
                            .map { "\($0.name) · \($0.body)" } ?? "Group message"
                    )
                    .font(.footnote)
                    .lineLimit(2)
                }
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(WhisperTheme.card(colorScheme).opacity(0.65), in: Capsule())
            } else {
                // THE WHISPER CHAT LOOK: your bubbles are solid ink with
                // surface text, theirs quiet card fills with ink text. A
                // message carrying a URL renders it as a live link and
                // unfurls a preview card beneath the bubble.
                let linkURL = WhisperLinkDetector.firstLinkURL(in: msg.body)
                VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                    Group {
                        if linkURL != nil {
                            WhisperLinkedText(text: msg.body, mine: mine)
                        } else if mine {
                            Text(msg.body)
                                .font(WhisperChatStyle.bodyFont)
                                .foregroundStyle(chatPalette.outgoingText)
                        } else {
                            WhisperMentionText(text: msg.body, font: WhisperChatStyle.bodyFont, inkColor: chatPalette.incomingText, linkColor: chatPalette.incomingText)
                        }
                    }
                    .padding(.horizontal, WhisperChatStyle.bubbleHorizontal)
                    .padding(.vertical, WhisperChatStyle.bubbleVertical)
                    .background {
                        bubbleShape(mine: mine, isFirstInRun: isFirstInRun, isLastInRun: isLastInRun)
                            .fill(chatPalette.fill(mine: mine))
                            .modifier(WhisperChatScrollTint(mine: mine))
                    }
                    if let linkURL {
                        WhisperLinkPreviewCard(url: linkURL, mine: mine)
                    }
                }
            }
        }
        // While a press is landing (or the overlay is up) every control
        // inside the bubble — the photo button, a link preview, a shared
        // card — goes inert, so the finger lifting off a long-pressed photo
        // can never ALSO open the photo viewer under the overlay.
        .disabled(pressCaptureID == msg.id || pressed != nil)
        .whisperCaptureFrame(armed: pressCaptureID == msg.id) { frame in
            pressCaptureID = nil
            guard frame.width > 0, frame.height > 0 else { return }
            pressed = PressedMessage(msg: msg, frame: frame, isFirstInRun: isFirstInRun, isLastInRun: isLastInRun)
            focused = false
        }
        .onTapGesture(count: 2) {
            Haptics.success()
            reactions.toggle("❤️", on: msg.id)
        }
        .onTapGesture(count: 1) {
            Haptics.tap()
            withAnimation(.spring(response: 0.32)) {
                revealedTimestampID = (revealedTimestampID == msg.id) ? nil : msg.id
            }
        }
        // SIMULTANEOUS on purpose: photos, fanned stacks, link previews and
        // shared cards are Buttons, and a plain onLongPressGesture never
        // fires over a child Button — which is exactly why attachments and
        // links couldn't be long-pressed. Riding alongside, the press lands
        // on EVERY message type; the .disabled above keeps the child quiet.
        .simultaneousGesture(
            // No continuous gesture-state updates: these can prevent the
            // enclosing ScrollView's pan from winning on iOS 26.
            LongPressGesture(minimumDuration: 0.32, maximumDistance: 10)
                .onEnded { _ in
                    // Lift in place — the frame capture mounts for this one
                    // bubble, reads its on-screen rect once, and the overlay
                    // springs from it.
                    guard pressed == nil, pressCaptureID == nil else { return }
                    WhisperMeetChime.playPress()
                    pressCaptureID = msg.id
                }
        )
    }

    /// My own username, lowercased — used to tell whose message a quote
    /// points at.
    private var myUsernameLower: String {
        (myProfile?.username
            ?? WhisperUserService.shared.me?.username
            ?? LeaderboardService.shared.savedUsername
            ?? "").lowercased()
    }

    /// The reply parts of a body, or nil when it isn't a reply.
    private func replyParts(_ body: String) -> (quote: WhisperGroupReplyQuote, text: String)? {
        let split = WhisperChatReply.split(body)
        guard let quote = split.quote else { return nil }
        return (quote, split.text)
    }

    // MARK: - The press overlay

    /// The lifted bubble + reaction strip + actions card for a pressed message.
    private func pressOverlay(_ p: PressedMessage) -> some View {
        let mine = p.msg.from_user_id.lowercased() == currentUIDLower
        let time = WhisperBackendService.parseISO(p.msg.created_at).map { WhisperChatFormatters.clockStamp($0) } ?? ""
        return WhisperMessagePressOverlay(
            context: WhisperMessagePressContext(
                messageID: p.msg.id,
                mine: mine,
                frame: p.frame,
                timeLabel: time,
                selectedReaction: reactions.selected(for: p.msg.id)
            ),
            reactions: Self.reactionEmojis,
            actions: pressActions(for: p.msg, mine: mine),
            onReaction: { emoji in
                reactions.toggle(emoji, on: p.msg.id)
            },
            onDismiss: {
                pressed = nil
            }
        ) {
            bubbleBody(
                msg: p.msg,
                mine: mine,
                workout: WhisperWorkoutEmbed.decode(p.msg.body),
                isFirstInRun: p.isFirstInRun,
                isLastInRun: p.isLastInRun
            )
        }
    }

    /// The actions card rows — the reference set: Reply · Forward · Copy ·
    /// Delete for you · Unsend (yours) · More › (everything Jasper-flavored).
    private func pressActions(for msg: WhisperMessageRow, mine: Bool) -> [WhisperMessagePressAction] {
        var rows: [WhisperMessagePressAction] = [
            WhisperMessagePressAction(id: "reply", icon: "arrowshape.turn.up.left", title: "Reply") {
                withAnimation(WhisperChatStyle.spring) { replyingTo = msg }
                focused = true
            },
            WhisperMessagePressAction(id: "forward", icon: "paperplane", title: "Forward") {
                forwardPayload = ForwardPayload(body: msg.body)
            },
            WhisperMessagePressAction(id: "copy", icon: "square.on.square", title: "Copy") {
                UIPasteboard.general.string = WhisperChatReply.quoteText(for: msg.body)
                Haptics.success()
                showToast("Copied")
            },
            WhisperMessagePressAction(id: "delete", icon: "trash", title: "Delete for you") {
                confirmDeleteForMe(msg)
            }
        ]
        if mine {
            rows.append(WhisperMessagePressAction(id: "unsend", icon: "arrow.uturn.backward.circle", title: "Unsend", isDestructive: true) {
                confirmUnsend(msg)
            })
        }
        rows.append(WhisperMessagePressAction(id: "more", icon: "ellipsis", title: "More", hasChevron: true) {
            actionMenu = buildMoreMenu(msg)
        })
        return rows
    }

    // MARK: - Branded menus

    /// "More ›" from the press card — everything Jasper-flavored plus Report,
    /// in Whisper's own action sheet.
    private func buildMoreMenu(_ msg: WhisperMessageRow) -> WhisperActionMenuModel {
        var actions: [WhisperMenuAction] = []
        if let imageURL = Self.imageURL(in: msg.body),
           !Self.isImagineImage(msg.body),
           WhisperMapEmbed.decode(msg.body) == nil,
           WhisperRecipeEmbed.decode(msg.body) == nil,
           WhisperMacrosShareEmbed.decode(msg.body) == nil {
            actions.append(WhisperMenuAction(icon: "fork.knife.circle.fill", title: "Log this meal with Jasper") {
                Task { await logPhotoMeal(at: imageURL) }
            })
        }
        if let imageURL = Self.imageURL(in: msg.body) {
            actions.append(WhisperMenuAction(
                icon: "square.and.arrow.down",
                title: Self.isImagineImage(msg.body) ? "Save Imagine to Photos" : "Save to Photos"
            ) {
                Task { await saveImageToPhotos(at: imageURL) }
            })
        }
        if msg.from_user_id.lowercased() != currentUIDLower,
           WhisperMapEmbed.decode(msg.body) == nil,
           WhisperChartEmbed.decode(msg.body) == nil,
           WhisperEmberAnswerEmbed.decode(msg.body) == nil,
           WhisperFactCheckEmbed.decode(msg.body) == nil,
           WhisperCoachProposalEmbed.decode(msg.body) == nil,
           WhisperCoachMacrosEmbed.decode(msg.body) == nil,
           WhisperCoachDietPlanEmbed.decode(msg.body) == nil,
           WhisperRecipeEmbed.decode(msg.body) == nil,
           WhisperMacrosShareEmbed.decode(msg.body) == nil,
           Self.imageURL(in: msg.body) == nil,
           !WhisperStickerPack.isWhisperSticker(msg.body) {
            actions.append(WhisperMenuAction(icon: "checkmark.seal.fill", title: "Fact-check with Knot") {
                Task { await runFactCheck(on: msg.body) }
            })
        }
        actions.append(WhisperMenuAction(icon: "clock", title: "Show time sent") {
            withAnimation(.spring(response: 0.32)) { revealedTimestampID = msg.id }
        })
        if msg.from_user_id.lowercased() != currentUIDLower {
            actions.append(WhisperMenuAction(icon: "flag", title: "Report", isDestructive: true) {
                presentReport = true
            })
        }
        return WhisperActionMenuModel(title: "Message", actions: actions)
    }

    /// Thread 3-dots menu — Report + Block/Unblock.
    private func buildThreadMenu() -> WhisperActionMenuModel {
        var actions: [WhisperMenuAction] = [
            WhisperMenuAction(icon: "flag", title: "Report", isDestructive: true) {
                presentReport = true
            }
        ]
        if blocks.isBlocked(userID: otherUserID) {
            actions.append(WhisperMenuAction(icon: "person.crop.circle.badge.checkmark", title: "Unblock") {
                Task { await blocks.unblock(userID: otherUserID, username: displayUsername) }
            })
        } else {
            actions.append(WhisperMenuAction(icon: "hand.raised.slash", title: "Block", isDestructive: true) {
                actionMenu = WhisperActionMenuModel(
                    title: "Block @\(displayUsername)?",
                    subtitle: "You won't see their messages or stories. You can unblock anytime from Settings.",
                    actions: [
                        WhisperMenuAction(icon: "hand.raised.slash", title: "Block", isDestructive: true) {
                            Task {
                                await blocks.block(userID: otherUserID, username: displayUsername)
                                dismiss()
                            }
                        }
                    ],
                    isConfirmStyle: true
                )
            })
        }
        return WhisperActionMenuModel(title: "@\(displayUsername)", actions: actions)
    }

    /// Branded Unsend confirmation.
    private func confirmUnsend(_ m: WhisperMessageRow) {
        actionMenu = WhisperActionMenuModel(
            title: "Unsend message?",
            subtitle: "This message will be removed from both your chat and \(displayUsername)'s chat. This can't be undone.",
            actions: [
                WhisperMenuAction(icon: "arrow.uturn.backward", title: "Unsend for everyone", isDestructive: true) {
                    Haptics.success()
                    Task { await backend.unsendMessage(m) }
                }
            ],
            isConfirmStyle: true
        )
    }

    /// Branded delete-for-me confirmation.
    private func confirmDeleteForMe(_ m: WhisperMessageRow) {
        actionMenu = WhisperActionMenuModel(
            title: "Delete for me?",
            subtitle: "This message will be hidden on your device only. \(displayUsername) will still see it.",
            actions: [
                WhisperMenuAction(icon: "trash", title: "Delete for me", isDestructive: true) {
                    Haptics.success()
                    withAnimation(.spring(response: 0.3)) {
                        backend.hideMessageLocally(m.id)
                    }
                }
            ],
            isConfirmStyle: true
        )
    }

    @ViewBuilder
    private func programBubble(_ payload: WhisperProgramEmbed.Payload, mine: Bool) -> some View {
        let saved = savedProgramIDs.contains(payload.id)
        let locked = payload.isPaid && !mine && !saved && !unlockedProgramIDs.contains(payload.id)
        Button {
            Haptics.tap()
            if locked {
                Task { await buyProgram(payload) }
            } else {
                WhisperProgramImport.saveToWhisper(payload)
                withAnimation(.spring(response: 0.3)) { savedProgramIDs.insert(payload.id) }
            }
        } label: {
            WhisperProgramInlineCard(
                payload: payload,
                mine: mine,
                saved: saved,
                locked: locked,
                buying: buyingProgramID == payload.id
            )
        }
        .buttonStyle(.plain)
        .disabled(saved || mine || buyingProgramID == payload.id)
        .task(id: payload.id) {
            // Past buyers (and free/owner cases) unlock without paying again.
            guard payload.isPaid, !mine, !unlockedProgramIDs.contains(payload.id) else { return }
            if let access = try? await WhisperBillingService.shared.fetchProgramAccess(programID: payload.id),
               access.purchased {
                withAnimation(.spring(response: 0.3)) { _ = unlockedProgramIDs.insert(payload.id) }
            }
        }
    }

    /// One-time in-app purchase for a paid coach program. Opens Stripe
    /// Checkout in an in-app browser sheet; when it closes, access is
    /// re-checked a few times (webhook fulfillment can lag a beat) and the
    /// card unlocks the moment the purchase lands.
    private func buyProgram(_ payload: WhisperProgramEmbed.Payload) async {
        guard buyingProgramID == nil else { return }
        buyingProgramID = payload.id
        do {
            guard let url = try await WhisperBillingService.shared.startProgramCheckout(programID: payload.id) else {
                // Backend says this user already owns it.
                withAnimation(.spring(response: 0.3)) { _ = unlockedProgramIDs.insert(payload.id) }
                buyingProgramID = nil
                Haptics.success()
                return
            }
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "whisper") { _, _ in
                Task { @MainActor in
                    await confirmProgramPurchase(payload.id)
                }
            }
            session.presentationContextProvider = WebAuthPresenter.shared
            if !session.start() {
                buyingProgramID = nil
            }
        } catch {
            buyingProgramID = nil
            backend.lastError = error.localizedDescription
        }
    }

    /// Post-checkout: poll program access briefly so the card unlocks as
    /// soon as Stripe's webhook (or the web success page) records the sale.
    private func confirmProgramPurchase(_ programID: String) async {
        defer { buyingProgramID = nil }
        for attempt in 0..<4 {
            if let access = try? await WhisperBillingService.shared.fetchProgramAccess(programID: programID),
               access.purchased {
                withAnimation(.spring(response: 0.3)) { _ = unlockedProgramIDs.insert(programID) }
                Haptics.success()
                return
            }
            try? await Task.sleep(for: .seconds(attempt == 0 ? 1.2 : 2.5))
        }
    }

    @ViewBuilder
    private func coachMacrosBubble(_ payload: WhisperCoachMacrosEmbed.Payload, mine: Bool) -> some View {
        let saved = savedCoachMacrosIDs.contains(payload.id)
        Button {
            Haptics.tap()
            WhisperCoachMacrosImport.apply(payload)
            withAnimation(.spring(response: 0.3)) { savedCoachMacrosIDs.insert(payload.id) }
        } label: {
            WhisperCoachMacrosInlineCard(payload: payload, mine: mine, saved: saved)
        }
        .buttonStyle(.plain)
        .disabled(saved || mine)
    }

    @ViewBuilder
    private func coachDietPlanBubble(_ payload: WhisperCoachDietPlanEmbed.Payload, mine: Bool) -> some View {
        let saved = savedCoachDietPlanIDs.contains(payload.id)
        Button {
            Haptics.tap()
            WhisperCoachDietPlanImport.apply(payload)
            withAnimation(.spring(response: 0.3)) { savedCoachDietPlanIDs.insert(payload.id) }
        } label: {
            WhisperCoachDietPlanInlineCard(payload: payload, mine: mine, saved: saved)
        }
        .buttonStyle(.plain)
        .disabled(saved || mine)
    }

    @ViewBuilder
    private func workoutBubble(_ payload: WhisperWorkoutEmbed.Payload, mine: Bool) -> some View {
        let saved = savedWorkoutIDs.contains(payload.id)
        Button {
            Haptics.tap()
            let result = WhisperWorkoutImport.saveToWhisper(payload)
            if result != .failed {
                withAnimation(.spring(response: 0.3)) {
                    savedWorkoutIDs.insert(payload.id)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                WhisperWorkoutInlineCard(payload: payload, mine: mine)
                if saved {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Saved to your Whisper")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(.green)
                    .padding(.top, 6)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(saved)
    }

    private func bubbleShape(mine: Bool, isFirstInRun: Bool, isLastInRun: Bool) -> UnevenRoundedRectangle {
        // One shared grammar for every chat surface (see WhisperChatStyle).
        WhisperChatStyle.shape(mine: mine, isFirstInRun: isFirstInRun, isLastInRun: isLastInRun)
    }

    // MARK: - Auto fact-check (incoming claims)

    /// Heuristic that detects whether a body looks like a factual claim
    /// worth verifying. Avoids running Jasper on every casual chat line.
    nonisolated private static func looksLikeClaim(_ body: String) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20, trimmed.count <= 400 else { return false }
        let lower = trimmed.lowercased()
        // Skip questions — they're not assertions.
        if lower.hasSuffix("?") { return false }
        // Skip satire / jokes — handled by the shared satire heuristic.
        if WhisperLiarLiarService.looksLikeSatire(body) { return false }
        let hasDigit = trimmed.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
        let keywords = [
            "calor", "protein", "carb", "fat", "sugar", "fiber",
            "bmi", "kg", "lbs", "pound", "gram", "oz",
            "mile", "km ", "kilometer", "step",
            "heart rate", "bpm", "vo2", "hrv",
            "creatine", "caffeine", "vitamin", "supplement", "steroid",
            "keto", "vegan", "carnivore", "fasting", "intermittent",
            "cardio", "strength", "hypertrophy", "deload",
            "sleep", "recover", "injury", "tendon", "ligament",
            "hormone", "testosteron", "insulin", "cortisol",
            "\u{00B0}c", "\u{00B0}f", " \u{00B1}", "percent", "%"
        ]
        let hasKeyword = keywords.contains { lower.contains($0) }
        // "X is Y" assertion shape (very loose).
        let hasAssertion = lower.contains(" is ") || lower.contains(" are ") ||
            lower.contains(" causes ") || lower.contains(" prevent") ||
            lower.contains(" burns ") || lower.contains(" builds ") ||
            lower.contains(" needs ")
        return (hasDigit && hasKeyword) || (hasKeyword && hasAssertion)
    }

    /// Manual fact-check for a single incoming message — invoked from the
    /// message long-press actions. Background auto-checking was removed on
    /// purpose: Jasper never spends AI credits unless the user asks.
    /// (Liar Liar strikes are intentionally NOT recorded from DMs — the
    /// badge is a public signal and only reacts to public posts.)
    func factCheckMessage(_ msg: WhisperMessageRow) async {
        guard autoFactFlags[msg.id] == nil else { return }
        autoFactCheckedIDs.insert(msg.id)
        let result = await ember.factCheck(msg.body)
        await MainActor.run {
            withAnimation(.spring(response: 0.32)) {
                autoFactFlags[msg.id] = result
            }
        }
    }

    /// Small gray italic flag rendered under an incoming bubble when Jasper
    /// has determined the claim is false / misleading. Tapping it opens a
    /// full fact-check card via the existing private-preview flow.
    @ViewBuilder
    private func autoFactFlagView(for msg: WhisperMessageRow, mine: Bool) -> some View {
        if !mine, let fact = autoFactFlags[msg.id] {
            Button {
                guard !factCheckSharing, !factCheckWorking else { return }
                Haptics.tap()
                withAnimation(.spring(response: 0.32)) {
                    factCheckPreview = WhisperFactCheckEmbed.Payload(
                        id: UUID().uuidString,
                        claim: msg.body,
                        verdictRaw: fact.verdict.rawValue,
                        summary: fact.summary,
                        explanation: fact.explanation,
                        sources: fact.sources
                    )
                    factCheckTarget = msg.body
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: fact.verdict.symbol)
                        .font(.caption2.weight(.bold))
                    Text(autoFactShortLine(fact))
                        .font(.caption2.italic())
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    nonisolated private func autoFactShortLine(_ fact: WhisperEmberService.FactCheck) -> String {
        let label = fact.verdict == .falseClaim ? "Knot: this isn\u{2019}t accurate"
                                                : "Knot: this is misleading"
        let s = fact.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "\(label) \u{2014} tap to see check" }
        return "\(label) \u{2014} \(s)"
    }

    // MARK: - Composer return-key handler

    /// Detects when the user typed a bare return on an empty/whitespace
    /// draft and dismisses the keyboard instead of inserting a newline.
    /// Also collapses any open Jasper preview cards so the chat is clean.
    private func handleDraftChange(old: String, new: String) {
        // A bare return on an empty draft → dismiss keyboard.
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        let onlyWhitespace = trimmed.isEmpty && new.contains("\n")
        if onlyWhitespace {
            draft = ""
            focused = false

        }
    }

    // MARK: - Jasper surfaces

    /// Cupid Jasper's date tools — rose chips that prefill /jasper with
    /// dating-tuned asks (date ideas, planning, reply coaching, vibe
    /// checks). Shown only in chats marked 💘 Dating.
    private var cupidToolsRow: some View {
        let rose = Color(red: 0.91, green: 0.28, blue: 0.49)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                WhisperEmberMascot(
                    size: 24,
                    expression: .happy,
                    palette: .cupidPink,
                    smitten: true
                )
                matchChip
                if let expiry = matchExpiryState, let chip = expiry.chip {
                    // Round 77 — matches fade after 7 quiet days; the chip
                    // nudges before it's gone.
                    Text(chip)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(expiry.faded ? .white.opacity(0.85) : rose)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(expiry.faded ? Color.gray.opacity(0.5) : rose.opacity(0.12)))
                        .overlay(Capsule().strokeBorder(rose.opacity(expiry.faded ? 0 : 0.35), lineWidth: 1))
                }
                cupidChip("💡 Date ideas", fill: "/knot give us 3 date ideas based on this chat — specific and fun, one line each")
                cupidChip("🗓 Plan a date", fill: "/knot help us plan our next date — read this chat and suggest a day, a time, and the kind of place")
                cupidChip("✍️ Reply coach", fill: "/knot coach my next reply in this chat — 2 options, warm and specific, no cringe")
                cupidChip("🚩 Vibe check", fill: "/knot vibe check this chat — how's it going, any green or red flags? be honest and kind")
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { isDatingChat = false }
                } label: {
                    Image(systemName: "heart.slash")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(rose.opacity(0.7))
                        .padding(7)
                        .background(Circle().fill(rose.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(rose.opacity(colorScheme == .dark ? 0.10 : 0.05))
    }

    private func cupidChip(_ label: String, fill: String) -> some View {
        let rose = Color(red: 0.91, green: 0.28, blue: 0.49)
        return Button {
            Haptics.tap()
            draft = fill
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(rose)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Capsule().fill(rose.opacity(0.12)))
                .overlay(Capsule().strokeBorder(rose.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// The 💘 Match button — when BOTH people tap it, the thread links
    /// their profiles with the full-screen celebration. States: match →
    /// requested → match back → matched.
    private var matchChip: some View {
        let rose = Color(red: 0.91, green: 0.28, blue: 0.49)
        let state = datingMatchState
        let filled = state == .none || state == .requestedByThem
        return Button {
            Haptics.tap()
            switch state {
            case .none:
                sendMatchToken(matched: false)
            case .requestedByThem:
                sendMatchToken(matched: true)
            case .matched:
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { showMatchCelebration = true }
            case .requestedByMe:
                showToast("Waiting for them to match back 💘")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: state == .matched ? "heart.fill" : "heart")
                    .font(.system(size: 11, weight: .bold))
                Text(matchChipLabel(for: state))
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(filled ? .white : rose)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(
                    filled
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [rose, Color(red: 0.98, green: 0.45, blue: 0.62)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        : AnyShapeStyle(rose.opacity(0.12))
                )
            )
            .overlay(Capsule().strokeBorder(rose.opacity(filled ? 0 : 0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Match expiry — anchored on the matched token, reset by any real
    /// message from either side (tokens don't count). Same rule as web.
    private var matchExpiryState: WhisperMatchExpiry.State? {
        func date(_ s: String?) -> Date? { WhisperBackendService.parseISO(s) }
        guard let matchedRow = messages.last(where: { WhisperMatchWire.decode($0.body)?.isMatched == true }),
              let matchedAt = date(matchedRow.created_at) else { return nil }
        let lastHuman = messages.reversed().first { m in
            let body = m.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty, WhisperMatchWire.decode(body) == nil, !WhisperSecondDate.isToken(body) else { return false }
            return (date(m.created_at) ?? .distantPast) > matchedAt
        }
        return WhisperMatchExpiry.state(matchedAt: matchedAt, lastMessageAt: date(lastHuman?.created_at))
    }

    private func matchChipLabel(for state: DatingMatchState) -> String {
        switch state {
        case .none: return "Match 💘"
        case .requestedByMe: return "Requested 💘"
        case .requestedByThem: return "Match back 💘"
        case .matched: return "Matched"
        }
    }

    /// Sends the match wire — a request, or the matched confirmation that
    /// links both profiles (the DM push fanout notifies them for free).
    private func sendMatchToken(matched: Bool) {
        guard !matchSending else { return }
        matchSending = true
        let generation = AccountStorage.generation
        let myName = myProfile?.username
            ?? messages.first(where: { $0.from_user_id.lowercased() == currentUIDLower })?.from_username
            ?? "someone"
        let body = matched
            ? WhisperMatchWire.matchedBody(from: currentUID, name: myName)
            : WhisperMatchWire.requestBody(from: currentUID, name: myName)
        Task {
            let sent = await sendConversationMessage(toUserID: otherUserID, toUsername: otherUsername, body: body)
            guard generation == AccountStorage.generation, !Task.isCancelled else { return }
            matchSending = false
            guard sent else { showToast("Couldn't send the match response. Please retry."); return }
            if matched {
                WhisperMatchWire.markCelebrationSeen(threadWith: conversationKey)
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { showMatchCelebration = true }
            } else { showToast("Match request sent") }
        }
    }

    /// Fires the one-time linking celebration when the thread turns matched.
    private func maybeCelebrateMatch() {
        guard datingMatchState == .matched,
              !WhisperMatchWire.celebrationSeen(threadWith: conversationKey) else { return }
        WhisperMatchWire.markCelebrationSeen(threadWith: conversationKey)
        WhisperDatingContacts.mark(otherUserID)
        if !isDatingChat { isDatingChat = true }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { showMatchCelebration = true }
    }

    /// What the Jasper peek pill is showing right now — nil when it's hidden.
    private enum JasperPillMode: Equatable {
        /// The draft starts with "/" — command chips filtered by what's typed.
        case commands(query: String)
        /// A formed "/jasper …" ask — the send hint.
        case ask
        /// Jasper is answering an ask.
        case thinking
        /// A slash-command card (chart · recipe · grocery…) is being built.
        case working
    }

    private var jasperPillMode: JasperPillMode? {
        if emberThinking { return nil }
        if emberWorking { return .working }
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        guard trimmed.hasPrefix("/") else { return nil }
        if WhisperKnotCommand.prompt(in: trimmed) != nil { return .ask }
        let q = String(trimmed.dropFirst()).lowercased()
        let matches = Self.slashCommands.filter { q.isEmpty || $0.name.contains(q) }
        return matches.isEmpty ? nil : .commands(query: q)
    }

    /// THE JASPER PEEK PILL — Jasper's whole presence above the bar is one
    /// clean pill with the mascot peeking over its top edge. It carries the
    /// slash commands as chips while you type "/", the send hint once the
    /// ask is formed, and the thinking dots while he answers — never a menu
    /// docked to the keyboard.
    @ViewBuilder
    private var jasperPill: some View {
        if let mode = jasperPillMode {
            HStack {
                WhisperJasperPeekPill(small: true, onOpenIntelligence: { focused = false; showJasperIntelligence = true }) {
                    switch mode {
                    case .commands(let q):
                        let matches = Self.slashCommands.filter { q.isEmpty || $0.name.contains(q) }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(matches.prefix(8).enumerated()), id: \.offset) { _, cmd in
                                    WhisperJasperCommandChip(icon: cmd.icon, title: "/\(cmd.name)", subtitle: cmd.hint) {
                                        draft = cmd.fill
                                        focused = true
                                        if cmd.runImmediate {
                                            Task { await send() }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                    case .ask:
                        WhisperJasperPillLine(text: "Ask Knot · tap ↑ to send")
                    case .thinking:
                        WhisperJasperPillLine(text: "Knot is thinking", thinking: true)
                    case .working:
                        WhisperJasperPillLine(text: "Knot is putting that together", thinking: true)
                    }
                }
                .id(pillIdentity(for: mode))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 2)
            .transition(.opacity.combined(with: .offset(y: 8)))
        }
    }

    /// One identity per pill FAMILY so the load-in choreography plays when
    /// the pill first appears (and when it changes job), not on every key.
    private func pillIdentity(for mode: JasperPillMode) -> String {
        switch mode {
        case .commands: return "commands"
        case .ask: return "ask"
        case .thinking: return "thinking"
        case .working: return "working"
        }
    }

    private struct SlashCommand {
        let name: String
        let hint: String
        let icon: String
        let fill: String
        let runImmediate: Bool
    }

    private static let slashCommands: [SlashCommand] = [
        .init(name: "knot",    hint: "Ask Knot anything",            icon: "sparkles",             fill: "/knot ",           runImmediate: false),
        .init(name: "factcheck", hint: "Verify a claim with sources",   icon: "checkmark.seal",       fill: "/knot factcheck ", runImmediate: false),
        .init(name: "chart",     hint: "Send a 7-day chart",            icon: "chart.bar.fill",       fill: "/knot chart workouts", runImmediate: true),
        .init(name: "nearby",    hint: "Send a map of nearby food",     icon: "mappin.and.ellipse",   fill: "/knot nearby",     runImmediate: true),
        .init(name: "recipe",    hint: "Knot finds a recipe",          icon: "fork.knife",           fill: "/knot recipe ",    runImmediate: false),
        .init(name: "macros",    hint: "Lookup macros for a food",      icon: "leaf.fill",            fill: "/knot macros for ",runImmediate: false),
        .init(name: "explain",   hint: "Explain a workout or term",     icon: "text.bubble.fill",     fill: "/knot explain ",   runImmediate: false),
        .init(name: "summarize", hint: "Summarize this chat",           icon: "text.alignleft",       fill: "/knot summarize this thread", runImmediate: false),
        .init(name: "recipe",    hint: "Send a full recipe card",       icon: "book.fill",            fill: "/recipe ",          runImmediate: false),
        .init(name: "log",       hint: "Log a food to your macros",     icon: "plus.circle.fill",     fill: "/log ",             runImmediate: false),
        .init(name: "macros",    hint: "Share today's macros",          icon: "chart.pie.fill",       fill: "/macros",           runImmediate: true),
        .init(name: "accountability", hint: "Challenge a friend to match macros", icon: "figure.2.arms.open", fill: "/accountability", runImmediate: true),
        .init(name: "workout",   hint: "Knot picks a workout for today", icon: "figure.run",         fill: "/workout ",         runImmediate: false),
        .init(name: "grocery",   hint: "Build a shared grocery list",   icon: "cart.fill",            fill: "/grocery ",         runImmediate: false),
        .init(name: "checkin",   hint: "Weekly mutual check-in card",    icon: "calendar.badge.checkmark", fill: "/checkin",        runImmediate: true),
        .init(name: "factcheck", hint: "Verify a claim with sources",    icon: "checkmark.seal",       fill: "/factcheck ",       runImmediate: false)
    ]

    @ViewBuilder
    private var emberChips: some View {
        if !smartReplies.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    WhisperJasperSpark(size: 7)
                        .padding(.leading, 4)

                    ForEach(smartReplies, id: \.self) { reply in
                        Button {
                            Haptics.tap()
                            draft = reply
                            focused = true
                        } label: {
                            Text(reply)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(WhisperTheme.card(colorScheme), in: Capsule())
                                .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }
            .frame(height: 36)
            .padding(.bottom, 4)
            .transition(.opacity)
        }
    }

    // MARK: - AI image (Imagine) sheet

    private var imagineSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    WhisperEmberBadge(size: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Imagine")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        Text("Knot will generate an image and send it.")
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.horizontal, 4)

                TextField("Describe the image…", text: $imaginePrompt, axis: .vertical)
                    .lineLimit(2...5)
                    .font(.body)
                    .padding(14)
                    .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                    }
                    .disabled(imagineLoading)

                Button {
                    startInlineImagine()
                } label: {
                    let ready = !imaginePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("Imagine")
                            .font(.subheadline.weight(.bold))
                    }
                    // Surface-on-ink when ready — the old fixed white text
                    // vanished on the white ink capsule in dark mode.
                    .foregroundStyle(ready ? WhisperTheme.surface(colorScheme) : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        ready ? WhisperTheme.ink(colorScheme) : Color.gray.opacity(0.45),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .disabled(imaginePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()
            }
            .padding(.horizontal, 18)
            .navigationTitle("AI image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { showImagineSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
        .whisperSheetBorder()
    }

    /// Kicks off Imagine in the background. Closes the sheet immediately,
    /// drops a loading card into the chat as your own outgoing message, and
    /// lets you keep typing. When the image is ready, the placeholder is
    /// replaced with the actual sent message.
    private func startInlineImagine() {
        let prompt = imaginePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        let pending = PendingImagine(prompt: prompt)
        withAnimation(.spring(response: 0.32)) {
            pendingImagines.append(pending)
        }
        imaginePrompt = ""
        showImagineSheet = false
        // Safety net: never let a ghost bubble live forever. If the
        // generation hasn't resolved in 60s (network died mid-call, etc.)
        // sweep it so the user can try again.
        Task {
            try? await Task.sleep(for: .seconds(60))
            if pendingImagines.contains(where: { $0.id == pending.id }) {
                withAnimation { pendingImagines.removeAll { $0.id == pending.id } }
                showToast("Imagine timed out")
            }
        }
        Task {
            do {
                let data = try await OpenAIService().generateImage(prompt: prompt)
                let urls = await backend.uploadMedia(datas: [data], postID: UUID().uuidString)
                guard let url = urls.first else {
                    withAnimation { pendingImagines.removeAll { $0.id == pending.id } }
                    showToast("Couldn't upload image")
                    return
                }
                // Tag the URL so the bubble context menu can hide "Log this
                // meal" (it's not real food) and show "Save to Photos" for
                // these AI-generated images.
                let taggedURL = Self.tagImagine(url)
                _ = await sendConversationMessage(toUserID: otherUserID, toUsername: otherUsername, body: taggedURL)
                withAnimation(.spring(response: 0.3)) {
                    pendingImagines.removeAll { $0.id == pending.id }
                }
                Haptics.success()
            } catch {
                withAnimation { pendingImagines.removeAll { $0.id == pending.id } }
                showToast("Couldn't generate image")
            }
        }
    }

    @ViewBuilder
    private var emberAnswerCard: some View {
        if let fact = factCheckPreview {
            factCheckPreviewCard(fact)
        } else if let answer = emberAnswer {
            emberSharePreviewCard(answer)
        }
    }

    /// Clears the private Jasper answer card.
    private func dismissEmberAnswer() {
        withAnimation(WhisperChatStyle.spring) {
            emberAnswer = nil
            emberAnswerQuestion = nil
            emberAnswerSources = []
            emberAnswerExpanded = false
            emberBlock = nil
            emberInterpret = nil
        }
    }

    /// JASPER'S PRIVATE ANSWER — a clean card in the chat grammar (no orange,
    /// no dashes): the Jasper icon + "only you see this", the answer
    /// streaming in so it reads as generated live, the thinking chip and any
    /// native card underneath, then Share / Keep private.
    private func emberSharePreviewCard(_ answer: String) -> some View {
        let isLong = answer.count > 260
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                WhisperJasperSpark(size: 8)
                WhisperKnotWordmark()
                Text("· only you see this")
                    .font(.system(size: 12.5))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                Spacer(minLength: 0)
                Button {
                    Haptics.tap()
                    dismissEmberAnswer()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .frame(width: 28, height: 28)
                        .background(WhisperTheme.card(colorScheme), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            if let q = emberAnswerQuestion, !q.isEmpty {
                Text(q)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(1)
            }
            WhisperEmberStreamingText(
                text: isLong ? String(answer.prefix(260)).trimmingCharacters(in: .whitespacesAndNewlines) + "…" : answer,
                font: .system(size: 15),
                color: WhisperTheme.ink(colorScheme),
                charsPerSecond: 160
            )
            if isLong {
                Button {
                    Haptics.tap()
                    emberAnswerExpanded = true
                } label: {
                    Text("Read the whole answer")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .underline()
                }
                .buttonStyle(.plain)
            }
            if let interpret = emberInterpret, interpret.didCompute {
                WhisperEmberThinkingChip(result: interpret) {
                    Haptics.tap()
                    presentedDMInterpret = IdentifiedDMInterpret(result: interpret)
                }
            }
            if let block = emberBlock {
                WhisperEmberBlockCard(block: block)
            }
            if !emberAnswerSources.isEmpty {
                Text(emberAnswerSources.prefix(2).compactMap { URL(string: $0)?.host?.replacingOccurrences(of: "www.", with: "") }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            HStack(spacing: 8) {
                Button {
                    Haptics.success()
                    Task { await shareEmberAnswer() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .bold))
                        Text("Share with @\(displayUsername)")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .padding(.horizontal, 13).padding(.vertical, 8)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
                }
                .buttonStyle(WhisperMenuPressStyle())
                Button {
                    Haptics.tap()
                    dismissEmberAnswer()
                } label: {
                    Text("Keep private")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(WhisperTheme.surface(colorScheme), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.10), radius: 16, y: 6)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .transition(.scale(scale: 0.96, anchor: .bottom).combined(with: .opacity))
        .sheet(isPresented: $emberAnswerExpanded) {
            WhisperEmberPreviewFullSheet(
                question: emberAnswerQuestion ?? "",
                answer: answer,
                sources: emberAnswerSources
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
            .whisperSheetBorder()
        }
        .sheet(item: $presentedDMInterpret) { item in
            WhisperEmberInterpretSheet(result: item.result)
        }
    }

    private func factCheckPreviewCard(_ fact: WhisperFactCheckEmbed.Payload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: fact.verdict.symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(fact.verdict.tint, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Fact-check (only you see this) · \(fact.verdict.label)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                    Text("\u{201C}\(fact.claim)\u{201D}")
                        .font(.caption.italic())
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(2)
                    Text(fact.summary.isEmpty ? fact.explanation : fact.summary)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.3)) {
                        factCheckPreview = nil
                        factCheckTarget = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                Button {
                    Haptics.success()
                    Task { await shareFactCheck() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane.fill")
                        Text("Share with @\(displayUsername)")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
                }
                .buttonStyle(.plain)
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.3)) {
                        factCheckPreview = nil
                        factCheckTarget = nil
                    }
                } label: {
                    Text("Keep private")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: WhisperChatStyle.bigRadius))
        .disabled(factCheckSharing)
        .overlay(alignment: .bottom) {
            if factCheckSharing { ProgressView().padding(8) }
        }
        .safeAreaInset(edge: .bottom) {
            if let factCheckShareError { Text(factCheckShareError).font(.caption).foregroundStyle(.secondary).padding(8) }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func shareEmberAnswer() async {
        guard !jasperSharing, let answer = emberAnswer, let question = emberAnswerQuestion else { return }
        let turn = jasperTurnID
        let generation = AccountStorage.generation
        jasperSharing = true
        jasperError = nil
        defer { if generation == AccountStorage.generation && turn == jasperTurnID { jasperSharing = false } }
        let payload = WhisperEmberAnswerEmbed.Payload(
            id: turn.uuidString,
            question: question,
            answer: answer,
            sources: emberAnswerSources,
            tldr: nil
        )
        let body = WhisperEmberAnswerEmbed.encode(payload)
        guard !body.isEmpty else { return }
        let sent = await sendConversationMessage(toUserID: otherUserID, toUsername: otherUsername, body: body)
        guard generation == AccountStorage.generation, turn == jasperTurnID else { return }
        if sent { dismissEmberAnswer(); Haptics.success() }
        else { jasperError = "Couldn't share this answer. It's still private; tap Share to retry." }
    }

    private func shareFactCheck() async {
        guard !factCheckSharing, !factCheckWorking, let fact = factCheckPreview else { return }
        let epoch = AccountStorage.generation
        factCheckSharing = true; factCheckShareError = nil
        defer { if epoch == AccountStorage.generation { factCheckSharing = false } }
        let body = WhisperFactCheckEmbed.encode(fact)
        guard !body.isEmpty else { return }
        let sent = await sendConversationMessage(toUserID: otherUserID, toUsername: otherUsername, body: body)
        guard epoch == AccountStorage.generation, factCheckPreview?.id == fact.id else { return }
        if sent {
            factCheckPreview = nil; factCheckTarget = nil; Haptics.success()
        } else {
            factCheckShareError = "Couldn't share. Your fact-check is still private. Tap Share to retry."
        }
    }

    private func runFactCheck(on claim: String) async {
        guard !emberThinking, !factCheckSharing, !factCheckWorking else { return }
        let epoch = AccountStorage.generation
        let token = UUID(); factCheckOperation = token
        factCheckShareError = nil; factCheckPreview = nil
        factCheckWorking = true; factCheckTarget = claim
        defer { if factCheckOperation == token { factCheckWorking = false; factCheckOperation = nil } }
        let result = await ember.factCheck(claim)
        guard epoch == AccountStorage.generation, factCheckOperation == token, !Task.isCancelled, factCheckTarget == claim else { return }
        let payload = WhisperFactCheckEmbed.Payload(
            id: UUID().uuidString,
            claim: claim,
            verdictRaw: result.verdict.rawValue,
            summary: result.summary,
            explanation: result.explanation,
            sources: result.sources
        )
        withAnimation(.spring(response: 0.32)) {
            factCheckPreview = payload
        }
        // Intentionally no Liar Liar strike here — DMs are private and
        // never feed the public reputation badge. Strikes are only earned
        // from public posts.
    }

    /// Smart replies are a QUIET background suggestion — never the thinking
    /// pill, never one model call per arriving message. Arrivals debounce
    /// 1.4s (a burst becomes one call), nothing runs while you're typing or
    /// when the last message is a card/media, and the previous fetch is
    /// cancelled by the next.
    private func scheduleSmartReplies() {
        smartReplyTask?.cancel()
        guard let last = messages.last else {
            smartReplies = []
            return
        }
        let lastFromOther = last.from_user_id.lowercased() != currentUIDLower
        guard lastFromOther else {
            smartReplies = []
            return
        }
        let body = last.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !body.hasPrefix("::"), !body.hasPrefix("{"),
              Self.imageURL(in: body) == nil, !WhisperStickerPack.isWhisperSticker(body) else {
            smartReplies = []
            return
        }
        smartReplyTask = Task {
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            await refreshSmartReplies()
        }
    }

    private func refreshSmartReplies(force: Bool = false) async {
        // Re-entrancy guard — a burst of arrivals fired one model call per
        // message and let the racing results overwrite each other.
        if loadingSmartReplies { return }
        guard !messages.isEmpty else {
            smartReplies = []
            return
        }
        guard let last = messages.last else { return }
        let lastFromOther = last.from_user_id.lowercased() != currentUIDLower
        if !force && !lastFromOther {
            smartReplies = []
            return
        }
        // Don't interrupt someone mid-sentence with suggestions.
        if !force && !draft.trimmingCharacters(in: .whitespaces).isEmpty { return }
        loadingSmartReplies = true
        if force { withAnimation { emberThinking = true } }
        let suggestions = await ember.smartReplies(thread: Array(messages.suffix(12)), mineID: currentUID)
        loadingSmartReplies = false
        guard !Task.isCancelled else {
            if force { withAnimation { emberThinking = false } }
            return
        }
        withAnimation(.spring(response: 0.3)) {
            smartReplies = suggestions
            if force { emberThinking = false }
        }
    }

    private func loadEmberAboutUser() async {
        emberThinking = true
        showEmberAboutUserSheet = true
        let posts: [WhisperPost] = []
        let text = await ember.summarizeUser(username: displayUsername, recentPosts: posts)
        emberAboutUser = text.isEmpty ? "I couldn't pull up anything fresh on @\(displayUsername) yet. Their feed might be quiet — try a wave." : text
        emberThinking = false
    }

    /// Soft banner above the composer when the recipient is private and
    /// I'm not already following them — makes it obvious the DM will
    /// land in their Requests until they approve me.
    private var privateAccountHint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(displayUsername) is a private account")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("Your message will arrive as a request until they approve you.")
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.card(colorScheme))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WhisperTheme.hairline(colorScheme))
                .frame(height: 0.5)
        }
    }

    // MARK: - Composer (Jasper-assistant style)

    /// Same square / glass / rounded composer that Jasper uses. Top: text
    /// field. Bottom row: plus menu, photo, AI images, spacer, send pill.
    private var composer: some View {
        // THE WHISPER BAR — flat and quiet: a bare ink "+" leads (it opens
        // the attach tray), the field is a rounded card, and the quick tools
        // (photo · stickers) sit OUTSIDE the field as bare glyphs. The moment
        // you type they fold into a single ink send disc.
        VStack(spacing: 0) {
            WhisperMentionSuggestionsBar(text: $draft)
            if let replyingTo {
                WhisperChatReplyStrip(
                    name: replyingTo.from_user_id.lowercased() == currentUIDLower ? "yourself" : "@\(replyingTo.from_username)",
                    preview: WhisperChatReply.quoteText(for: replyingTo.body),
                    onCancel: {
                        withAnimation(WhisperChatStyle.spring) { self.replyingTo = nil }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(alignment: .bottom, spacing: 4) {
                WhisperChatAttachmentButton(isPresented: $showAttachTray, items: attachItems) { focused = false }
                .padding(.bottom, 1)

                WhisperChatField(focused: focused) {
                    HStack(alignment: .bottom, spacing: 0) {
                    TextField("Message…", text: $draft, axis: .vertical)
                        .font(.body)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .tint(WhisperTheme.ink(colorScheme))
                        .focused($focused)
                        .lineLimit(1...5)
                        .submitLabel(.send)
                        .onSubmit { Task { await send() } }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    Group {
                        if canSend || sending {
                            WhisperChatSendButton(enabled: canSend, sending: sending) { Task { await send() } }
                        } else {
                            WhisperChatToolButton(systemImage: "photo", accessibility: "Photos and videos") { photoPickerPresented = true }
                        }
                    }.frame(width: 44, height: 44).padding(.trailing, 2)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .gesture(
            DragGesture(minimumDistance: 18)
                .onEnded { value in
                    guard value.translation.height > 40,
                          abs(value.translation.height) > abs(value.translation.width) else { return }
                    Haptics.tap()
                    focused = false

                }
        )
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    /// The attach tray's tiles — everything the old system menu held, as a
    /// grid: Photo · GIF · Stickers · Draw · Imagine · Location · Jasper.
    private var attachItems: [WhisperChatAttachItem] {
        [
            WhisperChatAttachItem(id: "photo", title: "Media", systemImage: "photo.on.rectangle") {
                photoPickerPresented = true
            },
            WhisperChatAttachItem(id: "meet", title: "Meet", systemImage: "video") {
                focused = false; showMeetSchedule = true
            },
            WhisperChatAttachItem(id: "notes", title: "Notes", systemImage: "doc.text") {
                focused = false; showNotes = true
            },
            WhisperChatAttachItem(id: "gif", title: "GIF", systemImage: "rectangle.stack") {
                showGifPicker = true
            },
            WhisperChatAttachItem(id: "sticker", title: "Stickers", systemImage: "face.smiling") {
                showStickerPicker = true
            },
            WhisperChatAttachItem(id: "draw", title: "Draw", systemImage: "scribble.variable") {
                showDrawSheet = true
            },
            WhisperChatAttachItem(id: "imagine", title: "Imagine", systemImage: "wand.and.sparkles") {
                imaginePrompt = ""
                showImagineSheet = true
            },
            WhisperChatAttachItem(id: "location", title: "Nearby", systemImage: "mappin.and.ellipse") {
                Task { await sendNearbyMapMessage(prompt: "nearby food") }
            },
            WhisperChatAttachItem(id: "link", title: "Link", systemImage: "link") {
                draft = draft.isEmpty ? "https://" : draft + " https://"
                focused = true
            },
            WhisperChatAttachItem(
                id: "jasper",
                title: "Knot",
                systemImage: "sparkles",
                jasper: true,
                children: [
                    WhisperChatAttachItem(id: "jasper-about", title: "Ask Knot about @\(displayUsername)", systemImage: "person.text.rectangle") {
                        Task { await loadEmberAboutUser() }
                    },
                    WhisperChatAttachItem(id: "jasper-slash", title: "/knot · answer shared in this chat", systemImage: "text.bubble") {
                        draft = "/knot "
                        focused = true
                    },
                    WhisperChatAttachItem(id: "jasper-replies", title: "Suggest replies", systemImage: "wand.and.stars") {
                        Task { await refreshSmartReplies(force: true) }
                    },
                    WhisperChatAttachItem(id: "chart-workouts", title: "Send a chart · Workouts", systemImage: "chart.bar") { sendChartCommand("workouts") },
                    WhisperChatAttachItem(id: "chart-calories", title: "Send a chart · Calories", systemImage: "flame") { sendChartCommand("calories") },
                    WhisperChatAttachItem(id: "chart-protein", title: "Send a chart · Protein", systemImage: "leaf") { sendChartCommand("protein") },
                    WhisperChatAttachItem(id: "chart-sleep", title: "Send a chart · Sleep", systemImage: "moon.zzz") { sendChartCommand("sleep") },
                    WhisperChatAttachItem(id: "chart-weight", title: "Send a chart · Weight", systemImage: "scalemass") { sendChartCommand("weight") },
                    WhisperChatAttachItem(id: "chart-steps", title: "Send a chart · Steps", systemImage: "figure.walk") { sendChartCommand("steps") },
                ]
            ),
        ]
    }

    /// Detects a plain image URL pasted as a message body (the path the
    /// PhotosPicker upload currently writes into Supabase storage) so we
    /// render it as an inline image bubble instead of a giant URL string.
    nonisolated static func videoURL(in body: String) -> URL? {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.contains(where: { $0.isWhitespace }), let url = URL(string: text),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, WhisperVideo.isVideo(url) else { return nil }
        return url
    }

    nonisolated static func imageURL(in body: String) -> URL? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        let exts: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif"]
        let pathExt = url.pathExtension.lowercased()
        if exts.contains(pathExt) { return url }
        // Supabase storage signed URLs frequently keep the extension in the
        // path component before the query string, so this covers them.
        let lower = trimmed.lowercased()
        if exts.contains(where: { lower.contains(".\($0)?") || lower.contains(".\($0)/") }) {
            return url
        }
        return nil
    }

    /// Sentinel query item added to AI-generated (`/imagine`) image URLs so
    /// the DM bubble menu can detect them later. Round-trips cleanly because
    /// Supabase signed URLs already carry query parameters.
    nonisolated static let imagineMarker: String = "wim"

    nonisolated static func tagImagine(_ raw: String) -> String {
        guard var comps = URLComponents(string: raw) else { return raw }
        var items = comps.queryItems ?? []
        if items.contains(where: { $0.name == imagineMarker }) { return raw }
        items.append(URLQueryItem(name: imagineMarker, value: "1"))
        comps.queryItems = items
        return comps.url?.absoluteString ?? raw
    }

    nonisolated static func isImagineImage(_ body: String) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed) else { return false }
        return (comps.queryItems ?? []).contains(where: { $0.name == imagineMarker })
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() async {
        guard canSend, !sending else { return }
        if (emberThinking || jasperSharing) && WhisperKnotCommand.prompt(in: draft) != nil { return }
        followsLatest = true
        let generation = AccountStorage.generation
        var body = draft
        if let prompt = parseEmberCommand(body) {
            draft = ""
            sending = false
            // Try special commands first (chart, nearby). Fall back to a
            // plain ask if it isn't one we recognize.
            if await handleSpecialEmberCommand(prompt) { return }
            await askEmberInline(prompt: prompt)
            return
        }
        // Top-level (non-`/ember`) slash commands.
        if await handleTopLevelSlashCommand(body) {
            draft = ""
            sending = false
            return
        }
        // Sponsorship scam protection: a brand that denied this creator's
        // application is permanently blocked from DMing them.
        let myID = AccountStorage.currentUserID.lowercased()
        if await WhisperBrandService.shared.isDMBlocked(senderID: myID, recipientID: otherUserID.lowercased()) {
            backend.lastError = "Messaging @\(otherUsername) is unavailable — your brand declined their sponsorship application."
            return
        }
        // A reply wraps the text in the shared quote grammar so every client
        // (web included) reads the quoted line.
        guard generation == AccountStorage.generation, !Task.isCancelled else { return }
        let typed = draft
        let submittedReply = replyingTo
        if let quoted = submittedReply {
            body = WhisperChatReply.body(quoting: quoted, with: body)
        }
        sending = true
        Haptics.tap()
        let ok = await sendConversationMessage(toUserID: otherUserID, toUsername: otherUsername, body: body)
        guard generation == AccountStorage.generation else { return }
        sending = false
        if !ok {
            WhisperFeedback.failed()
            if backend.lastError == nil {
                backend.lastError = "Couldn't send message. Try again."
            }
        } else {
            if draft == typed { draft = "" }
            if replyingTo?.id == submittedReply?.id { replyingTo = nil }
            WhisperFeedback.sent()
            smartReplies = []
            // Any time the user mentioned @ember in a DM, fire Jasper's
            // private answer card so the AI jumps in here too — mirrors
            // the comment-thread behavior.
            if WhisperEmberMention.shouldRespond(to: body) {
                let cleaned = body
                    .replacingOccurrences(of: "@ember", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "@jasper", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "@knot", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let prompt = cleaned.isEmpty
                    ? "What should I help with in this chat?"
                    : cleaned
                Task { await askEmberInline(prompt: prompt, questionWasSent: true) }
            }
        }
    }

    /// Returns the trimmed prompt if the user typed `/ember …`.
    private func parseEmberCommand(_ body: String) -> String? {
        guard let prompt = WhisperKnotCommand.prompt(in: body) else { return nil }
        return prompt.isEmpty ? "What should I help with in this chat?" : prompt
    }

    /// Routes a `/ember …` command. Returns true if it was a special command
    /// (chart / nearby) so the regular ask path is skipped.
    private func handleSpecialEmberCommand(_ prompt: String) async -> Bool {
        let lower = prompt.lowercased()
        // `/ember recipe <dish>` → route to the same recipe card builder that
        // top-level `/recipe` uses. Without this, the dish text falls through
        // to the nearby-restaurants branch when it happens to contain a token
        // like "food" (e.g. "seafood") or "eat" (e.g. "steak", "wheat").
        if lower.hasPrefix("recipe") {
            let dish = String(prompt.dropFirst("recipe".count)).trimmingCharacters(in: .whitespaces)
            if dish.isEmpty {
                showToast("Type a dish after recipe (e.g. /knot recipe chicken stir fry).")
                return true
            }
            await sendRecipeCard(for: dish)
            return true
        }
        // `/ember chart <metric>`  → send a 7-day chart of that metric
        // `/ember factcheck <claim>` — opens the verdict preview card
        if lower.hasPrefix("factcheck") || lower.hasPrefix("fact check") || lower.hasPrefix("verify") {
            let claim = prompt
                .replacingOccurrences(of: "factcheck", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "fact check", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "verify", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
            if !claim.isEmpty {
                await runFactCheck(on: claim)
                return true
            }
        }
        // `/ember share <metric>` or natural "send my sleep" — send a
        // real health-data snapshot the recipient can save to their own
        // Whisper charts.
        if lower.hasPrefix("share") || lower.hasPrefix("send my") || lower.hasPrefix("send") {
            let tail = lower
                .replacingOccurrences(of: "share", with: "")
                .replacingOccurrences(of: "send my", with: "")
                .replacingOccurrences(of: "send", with: "")
                .replacingOccurrences(of: "my", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let kind = WhisperHealthShareEmbed.Kind.parse(tail) {
                await sendHealthShareMessage(kind)
                return true
            }
        }
        if lower.hasPrefix("chart") || lower.contains("graph") {
            let tail = lower.replacingOccurrences(of: "chart", with: "")
                .replacingOccurrences(of: "graph", with: "")
                .replacingOccurrences(of: "my", with: "")
                .replacingOccurrences(of: "send", with: "")
                .trimmingCharacters(in: .whitespaces)
            let metric = WhisperChartEmbed.Metric.parse(tail) ?? .workouts
            await sendChartMessage(metric)
            return true
        }
        // `/ember nearby` / "food near me" / "restaurants". Match on whole
        // words so dish names like "seafood" or "steak" don't trigger the
        // map — `\b` boundaries keep "food"/"eat" from matching substrings.
        if matchesNearbyIntent(lower) {
            await sendNearbyMapMessage(prompt: prompt)
            return true
        }
        return false
    }

    private func sendChartCommand(_ metric: String) {
        Haptics.tap()
        Task { await sendChartMessage(WhisperChartEmbed.Metric.parse(metric) ?? .workouts) }
    }

    private func sendChartMessage(_ metric: WhisperChartEmbed.Metric) async {
        emberWorking = true
        let payload = WhisperChartDataSource.build(metric: metric)
        let body = WhisperChartEmbed.encode(payload)
        emberWorking = false
        if !body.isEmpty {
            _ = await sendConversationMessage(toUserID: otherUserID, toUsername: otherUsername, body: body)
        }
    }

    /// Builds a `WhisperHealthShareEmbed` from the sender's local
    /// HealthKit + Whisper data and posts it as a DM card. The recipient
    /// can tap "Add to my Whisper" to upsert the row into their own
    /// `jasper_*` tables — Whisper's charts then light up in realtime.
    private func sendHealthShareMessage(_ kind: WhisperHealthShareEmbed.Kind) async {
        emberWorking = true
        defer { emberWorking = false }
        let username = WhisperUserService.shared.me?.username ?? "you"
        let payload = await WhisperHealthShareSource.build(kind: kind, senderUsername: username)
        let body = WhisperHealthShareEmbed.encode(payload)
        guard !body.isEmpty else { return }
        _ = await sendConversationMessage(toUserID: otherUserID, toUsername: otherUsername, body: body)
    }

    /// True only when the prompt looks like a nearby-food intent — uses
    /// word boundaries so "steak"/"seafood"/"breakfast" don't false-trigger.
    private func matchesNearbyIntent(_ lower: String) -> Bool {
        if lower.hasPrefix("nearby") { return true }
        let patterns = [
            #"\bnear me\b"#,
            #"\bnearby\b"#,
            #"\brestaurants?\b"#,
            #"\bfood near\b"#,
            #"\bplaces to eat\b"#,
            #"\bwhere to eat\b"#,
            #"\bsomewhere to eat\b"#,
            #"\beat out\b"#
        ]
        return patterns.contains { lower.range(of: $0, options: .regularExpression) != nil }
    }

    private func sendNearbyMapMessage(prompt: String) async {
        emberWorking = true
        defer { emberWorking = false }
        let payload = await ember.nearbyRestaurantsPayload(searchHint: prompt)
        let body = WhisperMapEmbed.encode(payload)
        if !body.isEmpty {
            _ = await sendConversationMessage(toUserID: otherUserID, toUsername: otherUsername, body: body)
        }
    }

    // MARK: - Top-level slash commands (/recipe /macros /log /workout /grocery /accountability)

    /// Returns true if the draft was a top-level slash command and has been
    /// handled. The caller clears the draft and skips the normal send path.
    private func handleTopLevelSlashCommand(_ body: String) async -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard lower.hasPrefix("/"), !lower.hasPrefix("/ember") else { return false }

        if lower.hasPrefix("/macros") {
            await sendMacrosShare(isAccountability: false)
            return true
        }
        if lower.hasPrefix("/accountability") {
            await sendMacrosShare(isAccountability: true)
            return true
        }
        if lower.hasPrefix("/recipe") {
            let dish = String(trimmed.dropFirst("/recipe".count)).trimmingCharacters(in: .whitespaces)
            if dish.isEmpty {
                showToast("Type a dish after /recipe (e.g. /recipe chicken stir fry).")
                return true
            }
            await sendRecipeCard(for: dish)
            return true
        }
        if lower.hasPrefix("/log") {
            let food = String(trimmed.dropFirst("/log".count)).trimmingCharacters(in: .whitespaces)
            if food.isEmpty {
                showToast("Type a food after /log (e.g. /log two eggs and toast).")
                return true
            }
            await logFoodFromText(food)
            return true
        }
        if lower.hasPrefix("/workout") {
            let focus = String(trimmed.dropFirst("/workout".count)).trimmingCharacters(in: .whitespaces)
            await sendWorkoutSuggestion(focus: focus)
            return true
        }
        if lower.hasPrefix("/grocery") {
            let theme = String(trimmed.dropFirst("/grocery".count)).trimmingCharacters(in: .whitespaces)
            await sendGroceryList(theme: theme)
            return true
        }
        if lower.hasPrefix("/checkin") {
            await sendCheckinCard()
            return true
        }
        // Top-level `/share <metric>` — send a sleep / readiness / steps /
        // hr / energy snapshot that the recipient can save to their own
        // Whisper charts.
        if lower.hasPrefix("/share") {
            let tail = String(trimmed.dropFirst("/share".count)).trimmingCharacters(in: .whitespaces)
            guard let kind = WhisperHealthShareEmbed.Kind.parse(tail) else {
                showToast("Type a metric after /share — sleep, readiness, steps, hr, or energy.")
                return true
            }
            await sendHealthShareMessage(kind)
            return true
        }
        if lower.hasPrefix("/factcheck") {
            let claim = String(trimmed.dropFirst("/factcheck".count)).trimmingCharacters(in: .whitespaces)
            if claim.isEmpty {
                showToast("Type a claim after /factcheck.")
                return true
            }
            await runFactCheck(on: claim)
            return true
        }
        return false
    }

    /// Builds a `WhisperCheckinEmbed` snapshot, asks Jasper for short
    /// "top win" + "hardest day" lines, then sends it as an inline card.
    private func sendCheckinCard() async {
        emberWorking = true
        defer { emberWorking = false }
        let username = WhisperUserService.shared.me?.username ?? "you"
        let prompt = """
        Write a weekly fitness check-in in this exact format (no preamble, no markdown):
        WIN: <one sentence about a real-feeling win in training or nutrition>
        HARD: <one sentence about what was probably hardest>
        Keep each line under 90 chars. Be specific, warm, no hype words.
        """
        let raw = await ember.ask(prompt)
        var win = "Stayed consistent on the days that counted."
        var hard = "Late nights made fueling tricky a couple of times."
        for line in raw.split(whereSeparator: \.isNewline) {
            let l = String(line).trimmingCharacters(in: .whitespaces)
            if let r = l.range(of: "WIN:", options: .caseInsensitive) {
                win = String(l[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else if let r = l.range(of: "HARD:", options: .caseInsensitive) {
                hard = String(l[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        let payload = WhisperCheckinEmbed.currentSnapshot(username: username, topWin: win, hardestDay: hard)
        let body = WhisperCheckinEmbed.encode(payload)
        if !body.isEmpty {
            _ = await sendConversationMessage(toUserID: otherUserID, toUsername: otherUsername, body: body)
        }
    }

    /// Accept-side of a workout proposal: schedules the EventKit event,
    /// flips local state, and posts a confirmation message back so both
    /// users see "@me is in".
    private func acceptWorkoutProposal(_ payload: WhisperWorkoutProposalEmbed.Payload) async {
        await WhisperWorkoutCalendar.schedule(payload)
        let username = WhisperUserService.shared.me?.username ?? "I"
        _ = await sendConversationMessage(
            toUserID: otherUserID,
            toUsername: otherUsername,
            body: "@\(username) is in on \(payload.title) \u{2014} calendar updated."
        )
    }

    private func sendMacrosShare(isAccountability: Bool) async {
        emberWorking = true
        defer { emberWorking = false }
        let username = WhisperUserService.shared.me?.username ?? "you"
        let payload = WhisperMacrosShareEmbed.currentSnapshot(
            username: username,
            isAccountability: isAccountability
        )
        let body = WhisperMacrosShareEmbed.encode(payload)
        if !body.isEmpty {
            _ = await sendConversationMessage(toUserID: otherUserID, toUsername: otherUsername, body: body)
        }
    }

    private func sendRecipeCard(for dish: String) async {
        emberWorking = true
        defer { emberWorking = false }
        let payload = await ember.recipePayload(for: dish)
        let body = WhisperRecipeEmbed.encode(payload)
        if !body.isEmpty {
            _ = await sendConversationMessage(toUserID: otherUserID, toUsername: otherUsername, body: body)
        }
    }

    private func logFoodFromText(_ food: String) async {
        emberWorking = true
        defer { emberWorking = false }
        let est = await WhisperEmberService.estimateMacros(for: food)
        let item = FoodItem(
            name: food,
            brand: "Logged via Whisper",
            calories: est.calories,
            protein: est.protein,
            carbs: est.carbs,
            fat: est.fat,
            mealType: defaultMealForNow(),
            timestamp: Date(),
            icon: "fork.knife"
        )
        NutritionStore.shared.addMeal(item)
        Haptics.success()
        showToast("Logged \(food) — \(est.calories) cal")
    }

    private func sendWorkoutSuggestion(focus: String) async {
        emberWorking = true
        defer { emberWorking = false }
        let username = WhisperUserService.shared.me?.username ?? "you"
        let focusTrim = focus.trimmingCharacters(in: .whitespaces)
        let prompt = """
        Design a 45-minute workout proposal as a JSON object only \
        (no markdown, no commentary):
        {\"title\":\"<title 3-5 words>\",\"focus\":\"<one tag>\",\"blocks\":[\"...\"]}
        Blocks: 4-6 short lines (e.g. \"5 rounds: 8 squats, 10 pushups\").
        Bias toward: \(focusTrim.isEmpty ? "general strength + conditioning" : focusTrim).
        """
        let raw = await ember.ask(prompt)
        var cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let s = cleaned.firstIndex(of: "{"), let e = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[s...e])
        }
        struct Wrap: Codable { let title: String?; let focus: String?; let blocks: [String]? }
        var title = focusTrim.isEmpty ? "Today's workout" : focusTrim.capitalized
        var resolvedFocus = focusTrim
        var blocks: [String] = []
        if let json = cleaned.data(using: .utf8),
           let w = try? JSONDecoder().decode(Wrap.self, from: json) {
            if let t = w.title, !t.isEmpty { title = t }
            if let f = w.focus, !f.isEmpty { resolvedFocus = f }
            blocks = w.blocks ?? []
        }
        if blocks.isEmpty {
            blocks = [
                "5 min warmup: easy bike + arm swings",
                "4x5 back squat",
                "3x8 bench press",
                "3x10 dumbbell row",
                "Finisher: 5 min row, hard pace"
            ]
        }
        let payload = WhisperWorkoutProposalEmbed.Payload(
            id: UUID().uuidString,
            proposerUsername: username,
            title: title,
            focus: resolvedFocus,
            durationMinutes: 45,
            blocks: blocks,
            when: nil
        )
        let body = WhisperWorkoutProposalEmbed.encode(payload)
        if !body.isEmpty {
            _ = await sendConversationMessage(toUserID: otherUserID, toUsername: otherUsername, body: body)
        }
    }

    /// Sends a grocery embed pre-populated with a recipe's ingredients.
    private func sendGroceryFromIngredients(_ recipeTitle: String, items: [String]) async {
        let username = WhisperUserService.shared.me?.username ?? "you"
        let cleaned = items
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " -•*\"'1234567890.")) }
            .filter { !$0.isEmpty }
        let payload = WhisperGroceryListEmbed.Payload(
            id: UUID().uuidString,
            title: "Grocery: \(recipeTitle)",
            items: Array(cleaned.prefix(20)),
            authorUsername: username
        )
        let body = WhisperGroceryListEmbed.encode(payload)
        if !body.isEmpty {
            _ = await sendConversationMessage(toUserID: otherUserID, toUsername: otherUsername, body: body)
        }
    }

    private func sendGroceryList(theme: String) async {
        emberWorking = true
        defer { emberWorking = false }
        let username = WhisperUserService.shared.me?.username ?? "you"
        let prompt = theme.isEmpty
            ? "List 12-15 grocery items for a balanced healthy week. Reply with ONLY one item per line, no numbers, no bullets, no preamble."
            : "List 12-15 grocery items for: \(theme). Reply with ONLY one item per line, no numbers, no bullets, no preamble."
        let raw = await ember.ask(prompt)
        let items = raw
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: " -•*\"'1234567890.")) }
            .filter { !$0.isEmpty && $0.count <= 60 }
        let final: [String] = items.isEmpty
            ? ["Eggs", "Greek yogurt", "Chicken breast", "Brown rice", "Sweet potato", "Spinach", "Berries", "Olive oil", "Oats", "Almonds", "Cottage cheese", "Salmon"]
            : Array(items.prefix(16))
        let title = theme.isEmpty ? "Shared grocery list" : "Grocery: \(theme.capitalized)"
        let payload = WhisperGroceryListEmbed.Payload(
            id: UUID().uuidString,
            title: title,
            items: final,
            authorUsername: username
        )
        let body = WhisperGroceryListEmbed.encode(payload)
        if !body.isEmpty {
            _ = await sendConversationMessage(toUserID: otherUserID, toUsername: otherUsername, body: body)
        }
    }

    private func defaultMealForNow() -> MealType {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 4..<10:  return .breakfast
        case 10..<15: return .lunch
        case 15..<21: return .dinner
        default:      return .snack
        }
    }

    // MARK: - Photo-to-log (vision)

    /// Runs Jasper's vision macro estimator on a meal photo shared in this
    /// thread and pushes the result straight into `NutritionStore`.
    private func logPhotoMeal(at url: URL) async {
        emberWorking = true
        defer { emberWorking = false }
        guard let result = await WhisperEmberService.estimateMacros(forImageURL: url) else {
            showToast("Knot couldn't read this photo.")
            return
        }
        let food = FoodItem(
            name: result.label,
            brand: "Photo via Knot",
            calories: result.macros.calories,
            protein: result.macros.protein,
            carbs: result.macros.carbs,
            fat: result.macros.fat,
            mealType: defaultMealForNow(),
            timestamp: Date(),
            icon: "fork.knife"
        )
        NutritionStore.shared.addMeal(food)
        Haptics.success()
        showToast("Logged \(result.label) — \(result.macros.calories) cal")
    }

    // MARK: - Save inline image

    /// Downloads an inline image bubble's URL and writes the image into the
    /// user's Photos library. Triggered from the bubble context menu.
    private func saveImageToPhotos(at url: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else {
                showToast("Couldn't read image")
                return
            }
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            Haptics.success()
            showToast("Saved to Photos")
        } catch {
            showToast("Couldn't save image")
        }
    }

    // MARK: - Draw send

    private func sendDrawing(_ image: UIImage) async {
        guard let data = image.pngData() else {
            showToast("Couldn't read drawing")
            return
        }
        sending = true
        let urls = await backend.uploadMedia(datas: [data], postID: UUID().uuidString)
        sending = false
        guard let url = urls.first else {
            showToast("Couldn't upload drawing")
            return
        }
        _ = await sendConversationMessage(toUserID: otherUserID, toUsername: otherUsername, body: url)
        Haptics.success()
    }


    private func askEmberInline(prompt: String, questionWasSent: Bool = false) async {
        guard !emberThinking, !jasperSharing else { return }
        guard WhisperKnotContextPermission.allowed else {
            if draft.isEmpty { draft = "/knot " + prompt }
            focused = false; showKnotConsent = true; return
        }
        let consentRevision = WhisperKnotContextPermission.revision
        let generation = AccountStorage.generation
        let turn = UUID()
        jasperGeneration = generation
        jasperTurnID = turn
        emberAnswerQuestion = prompt
        jasperQuestionWasSent = questionWasSent
        emberAnswer = nil
        jasperError = nil
        Haptics.tap()
        withAnimation(.smooth(duration: 0.22)) {
            emberThinking = true
            emberBlock = nil
            emberInterpret = nil
        }

        // Shared answers use only the explicitly addressed question. Never
        // silently include either friend's history, private health or profile.
        let full = prompt
        let context = WhisperEmberHealthContext(
            text: "This answer will be shared with a friend in Whisper. Answer the addressed question only. Use clean prose and lists. No action proposals, private data, execution claims or technical envelopes. For actions, ask the person to open their private Knot chat.",
            series: .init(), hasWhisperData: false)
        knotActivity = "Preparing request…"

        guard generation == AccountStorage.generation, jasperTurnID == turn, jasperGeneration == generation, !Task.isCancelled else { return }
        // SAME shared engine as the full-screen Jasper: runs `/interpret`
        // (real Python stats) for analytical questions, calls the shared brain,
        // parses fenced chart/goalplan/schedule blocks, and degrades gracefully
        // to a local reply if the brain is briefly unreachable.
        let reply = await emberEngine.respond(
            message: full,
            context: context,
            history: [], knotBot: .main,
            onActivity: { label in
                guard generation == AccountStorage.generation, jasperTurnID == turn, jasperGeneration == generation else { return }
                knotActivity = label
            }, sharedConversation: true
        )

        guard generation == AccountStorage.generation, jasperTurnID == turn, jasperGeneration == generation, !Task.isCancelled else { return }
        guard WhisperKnotContextPermission.allowed, consentRevision == WhisperKnotContextPermission.revision else {
            emberThinking = false; return
        }
        withAnimation(.smooth(duration: 0.24)) {
            emberAnswerQuestion = prompt
            emberAnswerSources = []
            emberBlock = reply.block
            if let result = reply.interpret, result.didCompute {
                emberInterpret = result
            } else {
                emberInterpret = nil
            }
            // The engine only returns empty text when BOTH the brain and the
            // local fallback failed — rare. Show a soft retry then.
            if reply.isEmpty {
                jasperError = "Couldn't reach Knot. Your question is ready to retry."
                emberAnswer = nil
            } else if reply.text.isEmpty, reply.block != nil {
                // A pure chart/goal reply with no prose — give the card a header.
                emberAnswer = "Here's what I found."
            } else {
                emberAnswer = reply.text
            }
            emberThinking = false
        }
        if emberAnswer != nil { await shareEmberAnswer() }
    }



    // MARK: - Error banner & fix sheet

    private func errorBanner(_ message: String) -> some View {
        let hasFix = backend.pendingFixSQL != nil
        return HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(message).font(.caption).lineLimit(3)
                if hasFix {
                    Text("Tap to view & copy fix SQL ›")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            Button {
                Haptics.tap()
                backend.lastError = nil
            } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.red)
        .padding(10)
        .background(Color.red.opacity(0.08))
        .contentShape(Rectangle())
        .onTapGesture {
            if hasFix {
                Haptics.tap()
                showFixSheet = true
            }
        }
    }

    private var emberAboutUserSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        WhisperEmberBadge(size: 28)
                        Text("About @\(displayUsername)")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                    if emberThinking, emberAboutUser == nil {
                        ProgressView("Knot is reading their last posts…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if let text = emberAboutUser {
                        Text(text)
                            .font(.body)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Only you see this. Knot based it on their public Whisper activity.")
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                }
                .padding(20)
            }
            .background(WhisperTheme.surface(colorScheme))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showEmberAboutUserSheet = false }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
        .presentationDetents([.medium])
        .whisperSheetBorder()
    }

    private var fixSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(backend.pendingFixTitle ?? "One-time Supabase fix")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("Open Supabase → SQL editor → paste this → Run. After that, messages will send to any Whisper user.")
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                    Text(backend.pendingFixSQL ?? "")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                        }
                    Button {
                        UIPasteboard.general.string = backend.pendingFixSQL ?? ""
                        Haptics.tap()
                        withAnimation(.spring(response: 0.3)) { copyConfirmed = true }
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation { copyConfirmed = false }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: copyConfirmed ? "checkmark" : "doc.on.doc.fill")
                            Text(copyConfirmed ? "Copied" : "Copy SQL")
                                .font(.subheadline.weight(.bold))
                        }
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(WhisperTheme.ink(colorScheme), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .background(WhisperTheme.surface(colorScheme))
            .navigationTitle("Supabase fix")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showFixSheet = false }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }
}
