import SwiftUI
import PhotosUI

// MARK: - The group thread
//
// THE GROUP THREAD wears the 1:1 design language EXACTLY: the same header
// (chevron · avatar · bold name · quiet subtitle · phone · video · ⋯), the
// same runs with timestamp chips, the same ink/card bubbles, the same
// "Replied to you" quotes with mini cards, the same in-place long-press
// (blur + full-width reaction strip + the actions card), the Jasper peek
// pill for slash commands, and the same flat bar. Group-only extras stay:
// the sender name once per run, quiet system lines for roster events, the
// pinned bar, and the details sheet. Same wire as web — every one of these
// works across platforms.
struct WhisperGroupChatView: View {
    var onExternalClose: (() -> Void)? = nil
    private func closeThread() { if let onExternalClose { onExternalClose() } else { dismiss() } }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    let initialGroup: WhisperGroup
    @State private var editedGroup: WhisperGroup?
    private var group: WhisperGroup {
        get { groups.group(byID: initialGroup.id) ?? editedGroup ?? initialGroup }
        nonmutating set { editedGroup = newValue }
    }

    init(group: WhisperGroup, onExternalClose: (() -> Void)? = nil) {
        self.initialGroup = group
        self.onExternalClose = onExternalClose
    }

    @State private var groups = WhisperGroupChatService.shared
    @State private var reactions = WhisperDMReactionsStore()
    @State private var backend = WhisperBackendService.shared
    @State private var ember = WhisperEmberService.shared
    @State private var draft: String = ""
    @State private var backTransition: WhisperBackAction = WhisperBackAction()
    private var chatPalette: WhisperChatPalette { WhisperChatAppearance.classic.palette(colorScheme) }
    @State private var composerHeight: CGFloat = 64
    @State private var conversationHeaderHeight: CGFloat = 97
    @State private var followsLatest: Bool = true
    @State private var scrollingHistory: Bool = false
    @State private var historyNearTop = false
    @State private var historyPaginationInFlight = false
    @State private var historyPaginationTask: Task<Void, Never>?
    @State private var showJasperIntelligence: Bool = false
    @State private var jasperQuestion: String = ""
    @State private var jasperPendingAnswer: WhisperEmberAnswerEmbed.Payload?
    @State private var jasperFailure: String?
    @State private var jasperOperation: UUID?
    @State private var confirmBack: Bool = false
    @State private var loadedDraft: Bool = false
    @State private var sending: Bool = false
    @State private var failedMessages: [WhisperFailedChatMessage] = []
    @State private var recoveryGeneration: UUID?
    @State private var retryingMessage: UUID?
    @State private var emberWorking: Bool = false
    @State private var knotActivity = "Preparing request…"
    @State private var showKnotConsent = false
    private let knotEngine = WhisperEmberEngine()
    @FocusState private var focused: Bool
    @State private var initialScrollPending = true
    @State private var entryVisible = false
    @State private var entryID = UUID()
    @State private var initialScrollTask: Task<Void, Never>?
    /// Optimistic rows shown until the real fan-out row arrives.
    @State private var pending: [WhisperMessageRow] = []
    @State private var replyTo: WhisperMessageRow? = nil
    @State private var revealedTimestampID: String? = nil
    @State private var actionMenu: WhisperActionMenuModel? = nil
    @State private var showDetails: Bool = false
    @Namespace private var detailsTransition
    @State private var initialMessagesLoading = true
    @State private var memberProfile: WhisperUserRow?
    @State private var profileRequestID: String?
    @State private var profileError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showLibrary: Bool = false
    @State private var showAttachTray: Bool = false
    @State private var showGifPicker: Bool = false
    @State private var showMeetSchedule: Bool = false
    @State private var showNotes: Bool = false
    @State private var showStickerPicker: Bool = false
    /// Photos ride the same rail as DMs: pick up to ten, upload in one batch,
    /// each lands as its own message (a bare image URL every client renders
    /// as an image bubble).
    @State private var photoPickerPresented: Bool = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var uploadingPhotos: Bool = false
    @State private var showPhotoViewer: Bool = false
    @State private var viewerPhotos: [URL] = []
    @State private var viewerPhotoIndex: Int = 0
    /// THE LONG-PRESS MOMENT — the pressed message + its on-screen frame.
    @State private var pressed: PressedMessage?
    /// Arms the one-shot frame capture on the bubble that was just pressed.
    @State private var pressCaptureID: String?
    @State private var showGroupPhoto: Bool = false
    @State private var forwardPayload: ForwardPayload?
    @State private var scrollTargetID: String?
    @State private var infoToast: String?

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

    /// The reaction strip — the reference order: ❤️ 😂 😮 😢 😡 👍.
    private static let reactionEmojis: [String] = ["❤️", "😂", "😮", "😢", "😡", "👍"]

    private var currentUID: String { AccountStorage.currentUserID.lowercased() }
    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }
    private var myUsernameLower: String {
        (WhisperUserService.shared.me?.username
            ?? LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "").lowercased()
    }

    /// Real rows plus optimistic ones that haven't been confirmed yet.
    private var msgs: [WhisperMessageRow] {
        let real = groups.messages(forGroup: group)
        guard !pending.isEmpty else { return real }
        let realBodies = Set(real.filter { $0.from_user_id.lowercased() == currentUID }.map(\.body))
        let unconfirmed = pending.filter { !realBodies.contains($0.body) }
        return real + unconfirmed
    }

    /// The render index — runs (same sender within five minutes), timestamp
    /// chips, system lines — built once per data change, served from memory.
    private var threadIndex: WhisperChatThreadIndex.Index {
        WhisperChatThreadIndex.shared.index(
            key: "group:\(group.id.uuidString.lowercased())",
            rows: msgs,
            currentUIDLower: currentUID,
            runWindow: 300,
            systemLine: { WhisperGroupChatService.isSystemLine($0) },
            dropThoughtReplies: false
        )
    }

    private var isMuted: Bool { groups.isMuted(group) }
    private var pinnedMessage: WhisperMessageRow? {
        guard let id = groups.pinnedMessageID(for: group) else { return nil }
        return msgs.first { $0.id == id }
    }

    /// Reserve space at the bottom of the scroll so the last bubble is never
    /// hidden under the bar (the bar floats over the list like the DM).
    private var composerBottomInset: CGFloat {
        composerHeight + 8
    }

    var body: some View {
        themedConversation.environment(\.whisperChatAppearance, .classic)
            .environment(\.whisperChatDesign, nil)
    }

    private var themedConversation: some View {
        NavigationStack { groupPresentation.whisperEdgeBack(isEnabled: !sending && !uploadingPhotos && pressed == nil && pressCaptureID == nil && !showDetails, requiresDecision: !draft.isEmpty, controller: backTransition) { requestBack() } }
            .fullScreenCover(item: $sharedPostDetail) { payload in
                WhisperReferencedPostView(postID: payload.postID, focusedCommentID: payload.commentID)
            }
            .fullScreenCover(isPresented: $showGroupPhoto) { WhisperGroupPhotoViewer(group: group) }
            .fullScreenCover(isPresented: $showJasperIntelligence) { WhisperEmberChatView() }
            .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in showJasperIntelligence = false; sharedPostDetail = nil }
            .fullScreenCover(isPresented: $showPhotoViewer) {
                WhisperPostPhotoViewer(urls: viewerPhotos, startIndex: viewerPhotoIndex)
            }
            .confirmationDialog("Keep your message?", isPresented: $confirmBack, titleVisibility: .visible) {
                Button("Save draft") { AccountStorage.set(draft, forKey: messageDraftKey); backTransition.perform { closeThread() } }
                Button("Discard", role: .destructive) { AccountStorage.removeObject(forKey: messageDraftKey); draft = ""; backTransition.perform { closeThread() } }
                Button("Keep editing", role: .cancel) {}
            }
            .onAppear { if !loadedDraft { loadedDraft = true; if draft.isEmpty { draft = AccountStorage.string(forKey: messageDraftKey) ?? "" } } }
            .onChange(of: draft) { _, value in
                guard recoveryGeneration == AccountStorage.generation else { return }
                if value.isEmpty { AccountStorage.removeObject(forKey: messageDraftKey) }
                else { AccountStorage.set(value, forKey: messageDraftKey) }
            }
            .onAppear {
                WhisperNotificationService.shared.activeGroupID = group.id
                recoveryGeneration = AccountStorage.generation
                if let data = AccountStorage.data(forKey: messageDraftKey + ".failed") {
                    failedMessages = (try? JSONDecoder().decode([WhisperFailedChatMessage].self, from: data)) ?? []
                }
            }
            .onChange(of: failedMessages) { _, value in
                guard recoveryGeneration == AccountStorage.generation, let data = try? JSONEncoder().encode(value) else { return }
                AccountStorage.set(data, forKey: messageDraftKey + ".failed")
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in entryVisible = false; cancelInitialPositioning(); recoveryGeneration = nil; failedMessages = []; retryingMessage = nil; jasperOperation = nil; emberWorking = false; jasperPendingAnswer = nil; jasperQuestion = ""; jasperFailure = nil }
            .onDisappear {
                entryVisible = false; cancelInitialPositioning()
                jasperOperation = nil; emberWorking = false
                historyPaginationTask?.cancel(); historyPaginationTask = nil
                if recoveryGeneration == AccountStorage.generation { backend.closeGroupConversation(group.id) }
                if WhisperNotificationService.shared.activeGroupID == group.id { WhisperNotificationService.shared.activeGroupID = nil }
            }
    }

    private var conversationContent: AnyView {
        AnyView(ZStack(alignment: .bottom) {
                chatPalette.canvas.ignoresSafeArea()
                ZStack(alignment: .top) {
                    messagesList
                        .whisperRefreshable {
                            await backend.fetchGroupConversation(group.id)
                            await groups.syncRegistry(force: true)
                            await reactions.refresh()
                        }
                        .contentMargins(.top, conversationHeaderHeight, for: .scrollContent)
                    VStack(spacing: 0) {
                        customHeader
                        if let pinnedMessage {
                            pinnedBar(pinnedMessage)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { conversationHeaderHeight = $0 }
                }
                // The press blur lives in the overlay as a GPU material — the
                // live thread stays untouched, so the press answers instantly.

                VStack(spacing: 0) {
                    jasperPill
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
            })
    }

    private var groupNavigation: AnyView {
        AnyView(conversationContent
            .toolbar(.hidden, for: .navigationBar)
            .task { await reactions.watch() }
            .alert("Reaction not saved", isPresented: Binding(get: { reactions.failure != nil }, set: { if !$0 { reactions.failure = nil } })) {
                Button("OK") { reactions.failure = nil }
            } message: { Text(reactions.failure ?? "Please try again.") }
            .task(id: groups.unreadIDs(in: group)) {
                guard historyVisible else { return }
                await groups.markRead(group)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                guard historyVisible else { return }
                Task {
                    let generation = AccountStorage.generation
                    await backend.fetchGroupConversation(group.id)
                    guard generation == AccountStorage.generation, historyVisible else { return }
                    await groups.syncRegistry(force: true); await groups.markRead(group); await reactions.refresh()
                }
            }
            .whisperActionMenu($actionMenu)
            .sheet(isPresented: $showLibrary) {
                WhisperChatLibraryView(messages: msgs) { scrollTargetID = $0 }
            }
            .navigationDestination(item: $memberProfile) { user in
                WhisperDMDetailsView(user: user, messages: msgs, conversationKey: group.id.uuidString) { id in
                    memberProfile = nil; scrollTargetID = id
                }
            }
            .task(id: profileRequestID) {
                guard let id = profileRequestID else { return }
                let generation = AccountStorage.generation
                let found = await WhisperUserService.shared.fetchByUserID(id)
                guard !Task.isCancelled, generation == AccountStorage.generation, profileRequestID == id else { return }
                profileRequestID = nil
                if let found { memberProfile = found }
                else { profileError = "This profile couldn’t load. Tap the person to try again." }
            }
            .alert("Profile unavailable", isPresented: Binding(get: { profileError != nil }, set: { if !$0 { profileError = nil } })) {
                Button("OK") { profileError = nil }
            } message: { Text(profileError ?? "Please try again.") }
            .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in
                profileRequestID = nil; memberProfile = nil; profileError = nil
                reactions.reset()
            }
            .navigationDestination(isPresented: $showDetails) {
                WhisperGroupDetailsSheet(group: Binding(get: { group }, set: { group = $0 }), messages: msgs, onSearch: { showDetails = false; showLibrary = true }) {
                    closeThread()
                }
                .modifier(WhisperPortraitDestination(sourceID: "group-portrait", namespace: detailsTransition))
            }
            .sheet(isPresented: $showKnotConsent) {
                NavigationStack { WhisperKnotConsentView(onChange: {}, onContinue: {}, sharedConversation: true) }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showNotes) { WhisperNotesEntryView() }
            .sheet(isPresented: $showMeetSchedule) {
                WhisperChatMeetScheduleView(conversationKind: "group", groupID: group.id,
                    conversationTitle: group.name,
                    inviteeNames: group.members.filter { $0.user_id.lowercased() != currentUID }.map { "@\($0.username)" },
                    onScheduled: { infoToast = "Meeting scheduled for this chat" })
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in showMeetSchedule = false }
            .sheet(isPresented: $showGifPicker) {
                WhisperGifPickerSheet { url in
                    Task { await sendBody(url.absoluteString) }
                }
            }
            .sheet(isPresented: $showStickerPicker) {
                WhisperStickerPickerSheet(includesWhisperPack: true) { url in
                    Task { await sendBody(url.absoluteString) }
                }
            }
        )
    }

    private var groupPresentation: AnyView {
        AnyView(groupNavigation
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
            .sheet(item: $forwardPayload) { payload in
                WhisperPickRecipientSheet(payload: payload.body) {
                    forwardPayload = nil
                    showToast("Forwarded")
                }
                .presentationDragIndicator(.visible)
            }
            .overlay(alignment: .top) {
                if let toast = infoToast {
                    Text(toast)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(ink, in: Capsule())
                        .padding(.top, 60)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .task {
                let generation = AccountStorage.generation
                async let registry: Void = groups.syncRegistry()
                await backend.fetchGroupConversation(group.id)
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                initialMessagesLoading = false
                backend.startMessagesRealtime()
                await registry
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                if let fresh = groups.group(byID: group.id) { group = fresh }
            }
            .onChange(of: groups.groups) { _, _ in
                if let fresh = groups.group(byID: group.id), fresh != group { group = fresh }
            })
    }

    private func showToast(_ message: String) {
        withAnimation(.spring(response: 0.3)) { infoToast = message }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { infoToast = nil }
        }
    }

    // MARK: - Header (the DM header, group identity)

    private var messageDraftKey: String { "whisper.groupDraft.\(group.id.uuidString.lowercased())" }
    private func requestBack() {
        guard !sending, !uploadingPhotos else { return }
        if draft.isEmpty { backTransition.perform { closeThread() } } else { confirmBack = true }
    }

    private var customHeader: some View {
        WhisperConversationHeader(name: group.name,
            activity: emberWorking ? "Knot · \(knotActivity)" : nil,
            onBack: { Haptics.tap(); requestBack() },
            onDetails: { focused = false; showDetails = true }
        ) {
            WhisperGroupAvatarView(group: group, size: WhisperConversationPortraitSize.header)
                .matchedTransitionSource(id: "group-portrait", in: detailsTransition)
        } actions: {
            WhisperConversationCallMenu(
                audio: { Haptics.tap(); Task { await WhisperCallService.shared.startGroupCall(group: group, mode: .audio) } },
                video: { Haptics.tap(); Task { await WhisperCallService.shared.startGroupCall(group: group, mode: .video) } })
        }
        .whisperChatContent()
        .background { WhisperConversationHeaderBackdrop() }
    }

    /// Two overlapping member avatars — the group's face at any size.
    private func facepile(size: CGFloat) -> some View {
        let shown = Array(group.members.prefix(2))
        return ZStack {
            if shown.count >= 2 {
                memberAvatar(shown[1], size: size * 0.68)
                    .offset(x: size * 0.18, y: size * 0.18)
                memberAvatar(shown[0], size: size * 0.68)
                    .overlay { Circle().strokeBorder(WhisperTheme.surface(colorScheme), lineWidth: max(1.5, size * 0.05)) }
                    .offset(x: -size * 0.16, y: -size * 0.16)
            } else if let one = shown.first {
                memberAvatar(one, size: size)
            } else {
                Image(systemName: "person.3.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(muted)
                    .frame(width: size, height: size)
                    .background(WhisperTheme.card(colorScheme), in: Circle())
            }
        }
        .frame(width: size, height: size)
    }

    private func memberAvatar(_ m: WhisperGroupMember, size: CGFloat) -> some View {
        WhisperAvatar(
            username: m.username,
            size: size,
            imageURL: m.profile_image_url.flatMap(URL.init(string:)),
            ring: false
        )
    }

    /// Thread ⋯ — details, mute, and the video call.
    private func buildThreadMenu() -> WhisperActionMenuModel {
        WhisperActionMenuModel(
            title: group.name,
            actions: [
                WhisperMenuAction(icon: "magnifyingglass", title: "Search & shared media") {
                    showLibrary = true
                },
                WhisperMenuAction(icon: "info.circle", title: "Group details") {
                    showDetails = true
                },
                WhisperMenuAction(icon: isMuted ? "bell" : "bell.slash", title: isMuted ? "Unmute group" : "Mute group") {
                    groups.toggleMute(group)
                },
                WhisperMenuAction(icon: "video", title: "Start a video call") {
                    Task { await WhisperCallService.shared.startGroupCall(group: group) }
                },
            ]
        )
    }

    // MARK: - Pinned

    private func pinnedBar(_ msg: WhisperMessageRow) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "pin.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ink)
                .rotationEffect(.degrees(45))
            VStack(alignment: .leading, spacing: 1) {
                Text("Pinned · @\(msg.from_username)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(muted)
                Text(WhisperChatReply.quoteText(for: msg.body))
                    .font(.system(size: 13))
                    .foregroundStyle(ink)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                Haptics.tap()
                withAnimation(WhisperChatStyle.spring) { groups.pin(nil, in: group) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(muted)
                    .frame(width: 26, height: 26)
                    .background(WhisperTheme.surface(colorScheme), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Unpin")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(WhisperTheme.card(colorScheme))
        .overlay(alignment: .bottom) {
            Rectangle().fill(WhisperTheme.hairline(colorScheme)).frame(height: 0.5)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Messages

    private var historyVisible: Bool {
        scenePhase == .active && !showDetails && memberProfile == nil && !showJasperIntelligence && !showNotes && !showMeetSchedule && !showLibrary && !showPhotoViewer
    }

    private func loadOlderMessages(using proxy: ScrollViewProxy, retrying: Bool = false) {
        let state = backend.groupHistoryState(group.id)
        guard historyVisible, state.next != nil, !state.isLoading, !historyPaginationInFlight,
              retrying || state.error == nil else { return }
        cancelInitialPositioning()
        historyPaginationInFlight = true; followsLatest = false
        let anchor = msgs.first?.id
        let generation = AccountStorage.generation
        historyPaginationTask = Task {
            defer { historyPaginationInFlight = false }
            await backend.fetchGroupConversation(group.id, older: true)
            guard !Task.isCancelled, generation == AccountStorage.generation, historyVisible else { return }
            if let anchor { proxy.scrollTo(anchor, anchor: .top) }
        }
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    headerCard
                        .padding(.top, 24)
                        .padding(.bottom, 16)

                    let history = backend.groupHistoryState(group.id)
                    if history.isLoading && !msgs.isEmpty {
                        ProgressView().controlSize(.small)
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .accessibilityLabel("Loading messages")
                    }
                    if let error = history.error {
                        VStack(spacing: 4) {
                            Text(error).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button("Try again") {
                                if history.retryOlder { loadOlderMessages(using: proxy, retrying: true) }
                                else { Task { await backend.fetchGroupConversation(group.id) } }
                            }
                            .font(.footnote.weight(.semibold)).frame(minHeight: 44)
                            .disabled(history.isLoading || !historyVisible)
                        }.frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    let index = threadIndex
                    ForEach(index.groups) { run in
                        if let stamp = run.timestamp {
                            Text(stamp)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(muted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        if run.isSystem, let msg = run.messages.first {
                            systemLine(msg)
                                .id(msg.id)
                        } else {
                            let mine = run.messages.first?.from_user_id.lowercased() == currentUID
                            if !mine, let first = run.messages.first {
                                Button {
                                    focused = false
                                    profileRequestID = first.from_user_id
                                } label: {
                                    Text(WhisperChatNicknamesView.nickname(thread: group.id.uuidString, userID: first.from_user_id) ?? "@\(first.from_username)")
                                        .frame(minWidth: 44, alignment: .leading)
                                        .contentShape(.interaction, Rectangle().inset(by: -14))
                                }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(muted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 64)
                                    .padding(.top, 8)
                            }
                            ForEach(Array(run.messages.enumerated()), id: \.element.id) { idx, msg in
                                VStack(spacing: 4) {
                                    bubble(
                                        msg,
                                        mine: mine,
                                        isFirstInRun: idx == 0,
                                        isLastInRun: idx == run.messages.count - 1
                                    )
                                    if revealedTimestampID == msg.id,
                                       let d = WhisperBackendService.parseISO(msg.created_at) {
                                        Text(msg.id.hasPrefix("pending-") ? "Sending…" : WhisperChatFormatters.exactStamp(d))
                                            .font(.caption2)
                                            .foregroundStyle(muted)
                                            .transition(.opacity.combined(with: .move(edge: .top)))
                                    }
                                }
                                .id(msg.id)
                                .padding(.top, idx == 0 && mine ? 4 : 1)
                                .transition(.identity)
                            }
                        }
                    }

                    if msgs.isEmpty && (initialMessagesLoading || history.isLoading) {
                        WhisperMessageThreadSkeleton()
                    } else if msgs.isEmpty && history.error == nil {
                        VStack(spacing: 8) {
                            WhisperMeetDoodle(height: 120, illustration: .groups)
                            Text("Say hi to the group")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(muted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    }

                    ForEach(failedMessages) { failed in
                        VStack(alignment: .trailing, spacing: 6) {
                            WhisperChatTextBubble(text: WhisperChatReply.quoteText(for: failed.body), mine: true)
                            Button(retryingMessage == failed.id ? "Retrying…" : "Not sent · Tap to retry") {
                                guard retryingMessage == nil else { return }
                                retryingMessage = failed.id
                                let epoch = AccountStorage.generation
                                Task {
                                    let sent = await sendBody(failed.body)
                                    guard epoch == AccountStorage.generation else { return }
                                    retryingMessage = nil
                                    if sent { failedMessages.removeAll { $0.id == failed.id } }
                                }
                            }.font(.caption).foregroundStyle(.red).frame(minHeight: 44).disabled(retryingMessage != nil)
                        }.frame(maxWidth: .infinity, alignment: .trailing).padding(.vertical, 6)
                    }
                    if jasperFailure != nil {
                        WhisperJasperConversationReply(question: jasperQuestion, answer: jasperPendingAnswer?.answer, isPrivate: false, error: jasperFailure, onRetry: { Task { await retryJasperAnswer() } }) { EmptyView() }
                            .id("jasper-pending")
                    }
                    Color.clear
                        .frame(height: composerBottomInset)
                        .id("bottom-anchor")
                }
                .padding(.horizontal, 12)
                .whisperChatContent()
            }
            .scrollDisabled(pressed != nil || pressCaptureID != nil)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .onScrollGeometryChange(for: Bool.self) { geo in geo.contentSize.height - geo.contentOffset.y - geo.containerSize.height < 100 } action: { _, nearBottom in
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
                if scrollingHistory && historyNearTop { loadOlderMessages(using: proxy) }
            }
            .onChange(of: composerHeight) { _, _ in if canFollowLatest { proxy.scrollTo("bottom-anchor", anchor: .bottom) } }
            .onChange(of: emberWorking) { _, _ in if canFollowLatest { withAnimation(.smooth(duration: 0.24)) { proxy.scrollTo("bottom-anchor", anchor: .bottom) } } }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                entryVisible = true; entryID = UUID()
                followsLatest = true; scrollingHistory = false
                initialScrollPending = scrollTargetID == nil
                snapToBottom(proxy: proxy)
            }
            .onChange(of: msgs.last?.id) { _, newID in
                if newID != nil { snapToBottom(proxy: proxy) }
            }
            .onScrollGeometryChange(for: CGSize.self) { $0.contentSize } action: { _, _ in
                if initialScrollPending { snapToBottom(proxy: proxy) }
            }
            .onChange(of: msgs.count) { oldCount, _ in
                if initialScrollPending { snapToBottom(proxy: proxy) }
                else if canFollowLatest {
                    withAnimation(oldCount == 0 || reduceMotion ? nil : .smooth(duration: 0.22)) {
                        proxy.scrollTo("bottom-anchor", anchor: .bottom)
                    }
                }
            }
            .onChange(of: scrollTargetID) { _, target in
                guard let target else { return }
                cancelInitialPositioning()
                followsLatest = false
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                    proxy.scrollTo(target, anchor: .center)
                    revealedTimestampID = target
                }
                scrollTargetID = nil
            }
        }
    }

    private var canFollowLatest: Bool {
        followsLatest && !scrollingHistory && pressed == nil && pressCaptureID == nil
    }

    private func snapToBottom(proxy: ScrollViewProxy) {
        guard entryVisible, initialScrollPending, initialScrollTask == nil,
              !msgs.isEmpty, canFollowLatest, scrollTargetID == nil else { return }
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

    /// The identity card at the top of the thread — the DM's header card,
    /// wearing the group's facepile.
    private var headerCard: some View {
        VStack(spacing: 12) {
            Button { showGroupPhoto = true } label: { WhisperGroupAvatarView(group: group, size: 92) }
                .buttonStyle(.plain).accessibilityLabel("Enlarge group picture")
            VStack(spacing: 3) {
                Text(group.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.center)
                Text(group.members.map { "@\($0.username)" }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            Button {
                Haptics.tap()
                showDetails = true
            } label: {
                Text("Group details")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(WhisperTheme.card(colorScheme), in: Capsule())
                    .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private func systemLine(_ msg: WhisperMessageRow) -> some View {
        Text("@\(msg.from_username) \(msg.body.trimmingCharacters(in: .whitespacesAndNewlines))")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(muted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(WhisperTheme.card(colorScheme).opacity(0.65), in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }

    // MARK: - Bubble

    private func bubble(_ msg: WhisperMessageRow, mine: Bool, isFirstInRun: Bool, isLastInRun: Bool) -> some View {
        let reaction = reactions.reactions(for: msg.id)
        let isPending = msg.id.hasPrefix("pending-")
        return VStack(alignment: .trailing, spacing: 4) {
        HStack(alignment: .bottom, spacing: 6) {
            if !mine {
                if isLastInRun {
                    Button {
                        focused = false
                        profileRequestID = msg.from_user_id
                    } label: {
                        WhisperAvatar(
                            username: msg.from_username, size: WhisperConversationPortraitSize.message,
                            imageURL: group.members.first(where: { $0.user_id.lowercased() == msg.from_user_id.lowercased() })?.profile_image_url.flatMap(URL.init(string:)),
                            ring: false
                        )
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(WhisperPortraitPressStyle())
                    .accessibilityLabel("\(msg.from_username), conversation details")
                } else {
                    Color.clear.frame(width: 44, height: 26)
                }
            }
            if mine { Spacer(minLength: 44) }

            ZStack(alignment: mine ? .bottomTrailing : .bottomLeading) {
                bubbleBody(msg: msg, mine: mine, isFirstInRun: isFirstInRun, isLastInRun: isLastInRun)
                    .opacity(isPending ? 0.72 : 1)
                WhisperMessageReactionsBar(reactions: reaction, landingIDs: reactions.landingIDs(for: msg.id)) { reactions.toggle($0, on: msg.id, legacyGroup: msg.logical_group_message_id == nil) }
                    .offset(x: mine ? -7 : 7, y: 10)
            }

            if !mine { Spacer(minLength: 44) }
        }
        .padding(.bottom, reaction.isEmpty ? 0 : 16)
        if mine && !isPending {
            WhisperParticipantStack(people: groups.readers(of: msg, in: group), label: "Seen by", compact: true)
        }
        }
        .onAppear { reactions.show(msg.id) }
        .onDisappear { reactions.hide(msg.id) }
        .onChange(of: msg.id) { old, new in reactions.hide(old); reactions.show(new) }
    }

    /// The reply parts of a body, or nil when it isn't a reply.
    @State private var sharedPostDetail: WhisperSharedPostEmbed.Payload?

    private func replyParts(_ body: String) -> (quote: WhisperGroupReplyQuote, text: String)? {
        let split = WhisperChatReply.split(body)
        guard let quote = split.quote else { return nil }
        return (quote, split.text)
    }

    /// The label above a reply — the reference grammar, with names for a room.
    private func replyLabel(mine: Bool, quote: WhisperGroupReplyQuote) -> String {
        let quotedMine = quote.username.lowercased() == myUsernameLower
        switch (mine, quotedMine) {
        case (true, true): return "You replied to yourself"
        case (true, false): return "You replied to @\(quote.username)"
        case (false, true): return "Replied to you"
        case (false, false): return "Replied to @\(quote.username)"
        }
    }

    /// Renders the right content for a group message: a reply (checked FIRST
    /// so a quoted card never decodes as the card), Jasper cards, stickers,
    /// GIFs, photos, link previews — never a raw payload.
    @ViewBuilder
    private func bubbleBody(msg: WhisperMessageRow, mine: Bool, isFirstInRun: Bool, isLastInRun: Bool) -> some View {
        let isPending = msg.id.hasPrefix("pending-")
        Group {
            if let reply = replyParts(msg.body) {
                let quotedMine = reply.quote.username.lowercased() == myUsernameLower
                let original = WhisperChatReply.original(for: reply.quote, in: msgs)
                VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
                    Text(replyLabel(mine: mine, quote: reply.quote))
                        .font(.system(size: 12.5))
                        .foregroundStyle(muted)
                        .padding(.horizontal, 12)
                    WhisperChatReplyQuoteView(quote: reply.quote, mine: mine, quotedMine: quotedMine, original: original) {
                        Haptics.tap()
                        if let original { scrollTargetID = original.id }
                    }
                    Group {
                        if let video = WhisperDMThreadView.videoURL(in: reply.text) {
                            WhisperChatVideoView(url: video)
                        } else if let image = WhisperDMThreadView.imageURL(in: reply.text) {
                            mediaBubble(image)
                        } else {
                            textBubble(text: reply.text, mine: mine, isFirstInRun: isFirstInRun, isLastInRun: isLastInRun)
                        }
                    }.padding(.top, 4)
                }
            } else if let invitation = WhisperMeetingInvitation.fromText(msg.body) {
                if msg.body.contains("Started a group") == true {
                    WhisperGroupCallBubble(roomID: invitation.idOrCode, group: group, mode: msg.body.contains("audio") == true ? .audio : .video, mine: mine)
                } else {
                    WhisperMeetingDMBubble(invitation: invitation, mine: mine)
                }
            } else if let calendar = WhisperCalendarEmbed.decode(msg.body) {
                WhisperCalendarInlineCard(payload: calendar, mine: mine)
            } else if let storyID = WhisperSharedStoryEmbed.decode(msg.body) {
                WhisperSharedStoryCard(storyID: storyID)
            } else if msg.body.hasPrefix(WhisperSharedCommunityEmbed.prefix) {
                if let community = WhisperSharedCommunityEmbed.decode(msg.body) {
                    WhisperSharedCommunityInlineCard(payload: community, mine: mine)
                } else { Text("This community is unavailable").font(.subheadline).foregroundStyle(.secondary) }
            } else if let sharedPost = WhisperSharedPostEmbed.decode(msg.body) {
                WhisperSharedPostInlineCard(payload: sharedPost, mine: mine) { sharedPostDetail = sharedPost }
            } else if let answer = WhisperEmberAnswerEmbed.decode(msg.body) {
                WhisperEmberAnswerInlineCard(payload: answer, mine: mine)
            } else if let chart = WhisperChartEmbed.decode(msg.body) {
                WhisperChartInlineCard(payload: chart, mine: mine)
            } else if let fact = WhisperFactCheckEmbed.decode(msg.body) {
                WhisperFactCheckInlineCard(payload: fact, mine: mine)
            } else if let film = WhisperFilmEmbed.decode(msg.body) {
                WhisperFilmEmbedInlineCard(payload: film)
            } else if let article = WhisperArticleEmbed.decode(msg.body) {
                WhisperArticleEmbedInlineCard(payload: article)
            } else if let grocery = WhisperGroceryListEmbed.decode(msg.body) {
                WhisperGroceryInlineCard(payload: grocery, mine: mine)
            } else if let stickerName = WhisperStickerPack.stickerName(from: msg.body) {
                Image(WhisperStickerPack.assetName(for: stickerName))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
            } else if let videoURL = WhisperDMThreadView.videoURL(in: msg.body) {
                WhisperChatVideoView(url: videoURL)
            } else if let imageURL = WhisperDMThreadView.imageURL(in: msg.body) {
                mediaBubble(imageURL)
            } else {
                textBubble(text: msg.body, mine: mine, isFirstInRun: isFirstInRun, isLastInRun: isLastInRun)
            }
        }
        // Inert children while a press lands / the overlay is up — see the
        // DM thread for the why (a lifted photo must never also open).
        .disabled(pressCaptureID == msg.id || pressed != nil)
        .whisperCaptureFrame(armed: pressCaptureID == msg.id) { frame in
            pressCaptureID = nil
            guard frame.width > 0, frame.height > 0 else { return }
            pressed = PressedMessage(msg: msg, frame: frame, isFirstInRun: isFirstInRun, isLastInRun: isLastInRun)
            focused = false
        }
        .onTapGesture(count: 2) {
            Haptics.success()
            reactions.toggle("❤️", on: msg.id, legacyGroup: msg.logical_group_message_id == nil)
        }
        .onTapGesture(count: 1) {
            Haptics.tap()
            withAnimation(.spring(response: 0.32)) {
                revealedTimestampID = (revealedTimestampID == msg.id) ? nil : msg.id
            }
        }
        // Simultaneous so the press lands on photos, links and cards too
        // (child Buttons swallow a plain onLongPressGesture).
        .simultaneousGesture(
            // Let scrolling win as soon as the finger moves.
            LongPressGesture(minimumDuration: 0.32, maximumDistance: 10)
                .onEnded { _ in
                    guard !isPending, pressed == nil, pressCaptureID == nil else { return }
                    WhisperMeetChime.playPress()
                    pressCaptureID = msg.id
                }
        )
    }

    @ViewBuilder
    private func mediaBubble(_ imageURL: URL) -> some View {
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
            Button {
                let photos = msgs.compactMap { WhisperDMThreadView.imageURL(in: WhisperChatReply.split($0.body).text) }
                viewerPhotos = photos.contains(imageURL) ? photos : [imageURL]
                viewerPhotoIndex = viewerPhotos.firstIndex(of: imageURL) ?? 0
                focused = false
                showPhotoViewer = true
            } label: {
            Color(.secondarySystemBackground)
                .frame(width: 220, height: 220)
                .overlay {
                    WhisperCachedAsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        case .failure:
                            Image(systemName: "photo")
                                .foregroundStyle(muted)
                        default:
                            ProgressView()
                        }
                    }
                    .allowsHitTesting(false)
                }
                .clipShape(.rect(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open photo")
        }
    }

    /// The Whisper chat look: yours ink with surface text, theirs a quiet card
    /// fill with ink text; a URL renders live and unfurls a preview beneath.
    private func textBubble(text: String, mine: Bool, isFirstInRun: Bool, isLastInRun: Bool) -> some View {
        let linkURL = WhisperLinkDetector.firstLinkURL(in: text)
        return VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
            Group {
                if linkURL != nil {
                    WhisperLinkedText(text: text, mine: mine)
                } else if mine {
                    Text(text)
                        .font(WhisperChatStyle.bodyFont)
                        .foregroundStyle(chatPalette.outgoingText)
                } else {
                    WhisperMentionText(text: text, font: WhisperChatStyle.bodyFont, inkColor: chatPalette.incomingText, linkColor: chatPalette.incomingText)
                }
            }
            .padding(.horizontal, WhisperChatStyle.bubbleHorizontal)
            .padding(.vertical, WhisperChatStyle.bubbleVertical)
            .background {
                WhisperChatStyle.shape(mine: mine, isFirstInRun: isFirstInRun, isLastInRun: isLastInRun)
                    .fill(chatPalette.fill(mine: mine))
                    .modifier(WhisperChatScrollTint(mine: mine))
            }
            if let linkURL {
                WhisperLinkPreviewCard(url: linkURL, mine: mine)
            }
        }
    }

    // MARK: - The press overlay

    private func pressOverlay(_ p: PressedMessage) -> some View {
        let mine = p.msg.from_user_id.lowercased() == currentUID
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
                reactions.toggle(emoji, on: p.msg.id, legacyGroup: p.msg.logical_group_message_id == nil)
            },
            onDismiss: {
                pressed = nil
            }
        ) {
            bubbleBody(msg: p.msg, mine: mine, isFirstInRun: p.isFirstInRun, isLastInRun: p.isLastInRun)
        }
    }

    /// The actions card rows — Reply · Forward · Copy · Pin · Delete for you ·
    /// Unsend (yours, red).
    private func pressActions(for msg: WhisperMessageRow, mine: Bool) -> [WhisperMessagePressAction] {
        let isPinned = groups.pinnedMessageID(for: group) == msg.id
        var rows: [WhisperMessagePressAction] = [
            WhisperMessagePressAction(id: "reply", icon: "arrowshape.turn.up.left", title: "Reply") {
                withAnimation(WhisperChatStyle.spring) { replyTo = msg }
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
            WhisperMessagePressAction(id: "pin", icon: isPinned ? "pin.slash" : "pin", title: isPinned ? "Unpin" : "Pin to top") {
                withAnimation(WhisperChatStyle.spring) { groups.pin(isPinned ? nil : msg.id, in: group) }
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
        return rows
    }

    private func confirmUnsend(_ m: WhisperMessageRow) {
        actionMenu = WhisperActionMenuModel(
            title: "Unsend message?",
            subtitle: "This message will be removed from everyone's copy of \(group.name). This can't be undone.",
            actions: [
                WhisperMenuAction(icon: "arrow.uturn.backward", title: "Unsend for everyone", isDestructive: true) {
                    Haptics.success()
                    Task { await groups.unsend(m, in: group) }
                }
            ],
            isConfirmStyle: true
        )
    }

    private func confirmDeleteForMe(_ m: WhisperMessageRow) {
        actionMenu = WhisperActionMenuModel(
            title: "Delete for me?",
            subtitle: "This message will be hidden on your device only. The group will still see it.",
            actions: [
                WhisperMenuAction(icon: "trash", title: "Delete for me", isDestructive: true) {
                    Haptics.success()
                    withAnimation(.spring(response: 0.3)) {
                        groups.hideLocally(m, in: group)
                    }
                }
            ],
            isConfirmStyle: true
        )
    }

    // MARK: - Jasper peek pill

    private enum JasperPillMode: Equatable {
        case commands(query: String)
        case ask
        case working
    }

    private struct SlashCommand {
        let name: String
        let hint: String
        let icon: String
        let fill: String
        let runImmediate: Bool
    }

    private static let slashCommands: [SlashCommand] = [
        .init(name: "knot",  hint: "Ask Knot in the group",   icon: "sparkles",             fill: "/knot ", runImmediate: false),
        .init(name: "catchup", hint: "Recap what you missed",      icon: "text.badge.checkmark", fill: "/catchup", runImmediate: true),
        .init(name: "recap",   hint: "Knot summarizes the chat", icon: "text.alignleft",       fill: "/recap",   runImmediate: true),
    ]

    private var jasperPillMode: JasperPillMode? {
        if emberWorking { return nil }
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        guard trimmed.hasPrefix("/") else { return nil }
        if WhisperKnotCommand.prompt(in: trimmed) != nil { return .ask }
        let q = String(trimmed.dropFirst()).lowercased()
        let matches = Self.slashCommands.filter { q.isEmpty || $0.name.contains(q) }
        return matches.isEmpty ? nil : .commands(query: q)
    }

    @ViewBuilder
    private var jasperPill: some View {
        if let mode = jasperPillMode {
            HStack {
                WhisperJasperPeekPill(small: true, onOpenIntelligence: { focused = false; showJasperIntelligence = true }) {
                    switch mode {
                    case .commands(let q):
                        let matches = Self.slashCommands.filter { q.isEmpty || $0.name.contains(q) }
                        HStack(spacing: 6) {
                            ForEach(Array(matches.enumerated()), id: \.offset) { _, cmd in
                                WhisperJasperCommandChip(icon: cmd.icon, title: "/\(cmd.name)", subtitle: cmd.hint) {
                                    draft = cmd.fill
                                    focused = true
                                    if cmd.runImmediate {
                                        Task { await send() }
                                    }
                                }
                            }
                        }
                    case .ask:
                        WhisperJasperPillLine(text: "Ask Knot · everyone sees the answer")
                    case .working:
                        WhisperJasperPillLine(text: "Knot is writing", thinking: true)
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

    private func pillIdentity(for mode: JasperPillMode) -> String {
        switch mode {
        case .commands: return "commands"
        case .ask: return "ask"
        case .working: return "working"
        }
    }

    // MARK: - Composer (the DM bar)

    private var composer: some View {
        VStack(spacing: 0) {
            WhisperMentionSuggestionsBar(text: $draft)
            if let replyTo {
                WhisperChatReplyStrip(
                    name: replyTo.from_user_id.lowercased() == currentUID ? "yourself" : "@\(replyTo.from_username)",
                    preview: WhisperChatReply.quoteText(for: replyTo.body),
                    onCancel: {
                        withAnimation(WhisperChatStyle.spring) { self.replyTo = nil }
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
                        .lineLimit(1...5)
                        .focused($focused)
                        .font(.body)
                        .foregroundStyle(ink)
                        .tint(ink)
                        .submitLabel(.send)
                        .onSubmit { Task { await send() } }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    Group {
                        if uploadingPhotos { ProgressView().controlSize(.small) }
                        else if canSend || sending {
                            WhisperChatSendButton(enabled: canSend, sending: sending) { Task { await send() } }
                        } else {
                            WhisperChatToolButton(systemImage: "photo", accessibility: "Send a photo") { photoPickerPresented = true }
                        }
                    }.frame(width: 44, height: 44).padding(.trailing, 2)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    private var attachItems: [WhisperChatAttachItem] {
        [
            WhisperChatAttachItem(id: "photo", title: "Photo", systemImage: "photo") {
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
            WhisperChatAttachItem(id: "link", title: "Link", systemImage: "link") {
                draft = draft.isEmpty ? "https://" : draft + " https://"
                focused = true
            },
            WhisperChatAttachItem(id: "call", title: "Video call", systemImage: "video") {
                Task { await WhisperCallService.shared.startGroupCall(group: group) }
            },
            WhisperChatAttachItem(id: "recap", title: "Recap", systemImage: "text.badge.checkmark", jasper: true) {
                draft = "/catchup"
                Task { await send() }
            },
            WhisperChatAttachItem(id: "ask", title: "Ask Knot", systemImage: "sparkles", jasper: true) {
                draft = "/knot "
                focused = true
            },
            WhisperChatAttachItem(id: "mute", title: isMuted ? "Unmute" : "Mute", systemImage: isMuted ? "bell" : "bell.slash") {
                groups.toggleMute(group)
            },
            WhisperChatAttachItem(id: "info", title: "Details", systemImage: "info.circle") {
                showDetails = true
            },
        ]
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Sending

    /// Uploads the picked photos in one batch and sends each as its own
    /// message — the same rail the DM thread uses, so web and iOS members
    /// both render them as image bubbles (and fanned stacks for a run).
    private func attachPhotos(_ items: [PhotosPickerItem]) async {
        guard !uploadingPhotos else { return }
        uploadingPhotos = true
        let account = AccountStorage.currentUserID
        let generation = AccountStorage.generation
        let quote = replyTo
        defer { if generation == AccountStorage.generation { photoItems = []; uploadingPhotos = false } }
        for item in items {
            do {
                let url = try await WhisperChatMediaService.upload(item, accountID: account)
                try WhisperChatMediaService.checkAccount(account, generation: generation)
                let body = quote.map { WhisperChatReply.body(quoting: $0, with: url) } ?? url
                guard await sendBody(body) else { return }
                try WhisperChatMediaService.checkAccount(account, generation: generation)
                if replyTo?.id == quote?.id { replyTo = nil }
            } catch {
                guard generation == AccountStorage.generation else { return }
                showToast((error as? WhisperChatMediaService.Failure)?.errorDescription ?? "Couldn't prepare the attachment. Please try again.")
                return
            }
        }
    }

    /// Sends any body on the wire with an optimistic bubble.
    @discardableResult
    private func sendBody(_ body: String) async -> Bool {
        let generation = AccountStorage.generation
        let optimistic = WhisperMessageRow(
            id: "pending-\(UUID().uuidString)",
            from_user_id: AccountStorage.currentUserID,
            from_username: LeaderboardService.shared.savedUsername ?? AuthenticationService.shared.currentUser.username ?? "you",
            to_user_id: "",
            to_username: "",
            body: body,
            created_at: ISO8601DateFormatter().string(from: Date())
        )
        withAnimation(WhisperChatStyle.spring) { pending.append(optimistic) }
        let ok = await groups.sendMessage(toGroup: group, body: body)
        guard generation == AccountStorage.generation else { return false }
        if !ok {
            withAnimation(WhisperChatStyle.spring) { pending.removeAll { $0.id == optimistic.id } }
            showToast("Message wasn't sent. Please try again.")
        }
        // The real row lands via realtime; drop the ghost after it should have.
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            pending.removeAll { $0.id == optimistic.id }
        }
        if ok && !isMuted { Haptics.tap() }
        return ok
    }

    private func send() async {
        guard canSend, !sending else { return }
        if emberWorking && (draft.hasPrefix("/") || WhisperEmberMention.shouldRespond(to: draft)) { return }
        followsLatest = true
        var body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = body.lowercased()
        let isKnotRequest = lower.hasPrefix("/catchup") || lower == "/recap" || WhisperKnotCommand.prompt(in: body) != nil || WhisperEmberMention.shouldRespond(to: body)
        if isKnotRequest, !WhisperKnotContextPermission.allowed {
            focused = false; showKnotConsent = true; return
        }
        let consentRevision = WhisperKnotContextPermission.revision
        draft = ""
        let quoted = replyTo
        withAnimation(WhisperChatStyle.spring) { replyTo = nil }
        let generation = AccountStorage.generation
        let ownsMessageSend = !(lower.hasPrefix("/catchup") || lower == "/recap" || WhisperKnotCommand.prompt(in: body) != nil || WhisperEmberMention.shouldRespond(to: body))
        sending = ownsMessageSend
        defer { if ownsMessageSend && generation == AccountStorage.generation { sending = false } }

        // /catchup → Jasper summarizes the thread and posts the recap.
        if lower.hasPrefix("/catchup") || lower == "/recap" {
            sending = false
            let operation = UUID(); jasperOperation = operation
            jasperQuestion = "Catch me up on this chat"
            jasperPendingAnswer = nil; jasperFailure = nil
            emberWorking = true; knotActivity = "Reading shared chat…"
            let summary = await ember.summarizeThread(messages: msgs, mineID: currentUID)
            guard generation == AccountStorage.generation, jasperOperation == operation, !Task.isCancelled else { return }
            emberWorking = false
            guard WhisperKnotContextPermission.allowed, consentRevision == WhisperKnotContextPermission.revision else { return }
            let text = summary.isEmpty ? "Nothing major to recap yet — keep the convo going." : summary
            jasperPendingAnswer = .init(id: operation.uuidString, question: jasperQuestion, answer: text, sources: [], tldr: nil)
            await retryJasperAnswer()
            return
        }
        // /knot and legacy aliases share the existing group answer/delivery path.
        if WhisperKnotCommand.prompt(in: body) != nil || WhisperEmberMention.shouldRespond(to: body) {
            let stripped = WhisperKnotCommand.prompt(in: body) ?? body.replacingOccurrences(of: #"(?i)@(?:knot|jasper|ember)\b"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            let q = stripped.isEmpty ? "What should I help with in this chat?" : stripped
            sending = false
            let operation = UUID(); jasperOperation = operation
            jasperQuestion = q; jasperFailure = nil; jasperPendingAnswer = nil
            emberWorking = true
            knotActivity = "Preparing request…"
            let answer = await knotEngine.respond(message: q,
                context: .init(text: "This answer is shared with a Whisper group. Answer only the addressed question. Do not include personal data, action proposals, execution claims or technical envelopes. Ask the person to continue in private Knot chat for approval-based actions.", series: .init(), hasWhisperData: false),
                history: [], knotBot: .main,
                onActivity: { label in
                    guard generation == AccountStorage.generation, jasperOperation == operation else { return }
                    knotActivity = label
                }, sharedConversation: true)
            guard generation == AccountStorage.generation, jasperOperation == operation, !Task.isCancelled else { return }
            emberWorking = false
            guard WhisperKnotContextPermission.allowed, consentRevision == WhisperKnotContextPermission.revision else { return }
            guard !answer.text.isEmpty else { jasperFailure = "Couldn't reach Knot. Send your question again to retry."; draft = "/knot " + q; return }
            let payload = WhisperEmberAnswerEmbed.Payload(
                id: UUID().uuidString,
                question: q,
                answer: answer.text,
                sources: [],
                tldr: nil
            )
            jasperPendingAnswer = payload
            await retryJasperAnswer()
            return
        }
        if let quoted {
            body = WhisperChatReply.body(quoting: quoted, with: body)
        }
        let sent = await sendBody(body)
        guard generation == AccountStorage.generation else { return }
        if !sent { failedMessages.append(.init(id: UUID(), body: body)) }
    }

    private func retryJasperAnswer() async {
        guard let payload = jasperPendingAnswer, !emberWorking else { return }
        let generation = AccountStorage.generation
        emberWorking = true; jasperFailure = nil; knotActivity = "Sending answer…"
        let sent = await sendBody(WhisperEmberAnswerEmbed.encode(payload))
        guard generation == AccountStorage.generation else { return }
        emberWorking = false
        if sent { jasperPendingAnswer = nil; jasperQuestion = ""; jasperFailure = nil }
        else { jasperFailure = "Couldn't share Knot's answer with the group. Try again." }
    }
}
