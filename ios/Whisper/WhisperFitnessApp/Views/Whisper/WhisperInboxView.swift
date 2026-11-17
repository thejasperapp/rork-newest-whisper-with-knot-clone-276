import SwiftUI
import PhotosUI
import UIKit
import Combine
import Supabase

/// Stories and notes sit on an underlayer above one rounded foreground
/// containing search, filters (All / Primary / General / Requests) and
/// conversations with right-aligned timestamps.
struct WhisperInboxView: View {
    @State private var availableWidth: CGFloat = 0
    @State private var conversationIsInline: Bool?
    private var hasOpenConversation: Bool { openKnot || openThread != nil || openGroup != nil }
    // Lock presentation for the lifetime of an open conversation. Resizing an
    // inline chat hides the list instead of destroying/cancelling that chat.
    private var usesInlinePresentation: Bool { conversationIsInline ?? tabletSplit }
    private var showsInlineDetail: Bool { hasOpenConversation ? usesInlinePresentation : tabletSplit }
    // Measure the Messages container, after the root navigation sidebar has
    // taken its space. A regular size class alone can leave the chat too narrow.
    private var usesTabletContainer: Bool { UIDevice.current.userInterfaceIdiom == .pad && !activityOnly }
    private var tabletSplit: Bool { usesTabletContainer && availableWidth >= 744 }
    private func conversationListWidth(in width: CGFloat) -> CGFloat {
        min(340, max(280, width * 0.32))
    }
    @State private var backTransition: WhisperBackAction = WhisperBackAction()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.whisperRootChromeActive) private var rootChromeActive
    @Environment(\.scenePhase) private var inboxScenePhase
    @State private var inboxEndVisible = false
    @State private var query: String = ""
    @State private var disappearingQuery = ""
    @State private var showsDisappearingInbox = false
    @State private var disappearingComposeRequest = 0
    private var inboxSearch: Binding<String> {
        Binding(get: { showsDisappearingInbox ? disappearingQuery : query }, set: { if showsDisappearingInbox { disappearingQuery = $0 } else { query = $0 } })
    }
    @State private var storyRailHeight: CGFloat = 140
    @State private var activity = WhisperActivityService.shared
    @State private var tab: Tab
    /// When true, the inbox renders as an Activity-only screen — the
    /// Messages/Activity segmented selector is hidden and a back chevron
    /// appears in the leading toolbar slot. Used by
    /// the bell button on the feed, which now opens a dedicated full-page
    /// Activity view rather than a sheet containing the whole inbox.
    private let activityOnly: Bool

    init(initialTab: InitialTab = .messages, activityOnly: Bool = false) {
        _tab = State(initialValue: (initialTab == .activity || activityOnly) ? .activity : .messages)
        self.activityOnly = activityOnly
    }

    /// External entry point — the bell button on the feed opens this view
    /// directly on the activity (notifications) tab.
    enum InitialTab { case messages, activity }
    @State private var filter: Filter = .all
    @State private var sort: SortMode = .recent
    @State private var backend = WhisperBackendService.shared
    @State private var presence = WhisperPresenceService.shared
    @State private var stories = WhisperStoryService.shared
    @State private var requests = FriendRequestsService.shared
    @State private var thoughts = WhisperThoughtService.shared
    @State private var follows = WhisperFollowService.shared
    @State private var dmPrivacy = WhisperDMPrivacyService.shared
    @State private var coach = WhisperCoachService.shared
    @State private var verification = WhisperVerificationService.shared
    @State private var brands = WhisperBrandService.shared
    @State private var recruiter = WhisperRecruiterService.shared
    /// Full-screen Coach Studio — opened from the coach welcome tour.
    @State private var presentCoachStudio: Bool = false

    /// One-at-a-time approval celebration. A user approved for multiple roles
    /// (coach + verified) must never present two sheets simultaneously —
    /// SwiftUI hard-crashes on that. Both funnel through a single
    /// `.sheet(item:)` so only one is ever on screen.
    private enum Celebration: Int, Identifiable {
        case coach, verified
        var id: Int { rawValue }
    }
    /// Explicit presentation state for the celebration sheet. The sheet is
    /// ONLY shown when the user taps the inline banner — we never auto-
    /// present it from `onAppear` or `shouldCelebrateApproval` onChange.
    /// The inbox stays alive in the TabView while the settings (hamburger)
    /// sheet is on top, so any auto-present here raced the settings sheet's
    /// own presentation and hard-crashed UIKit on release builds (the
    /// hamburger-menu crash). The banner is tap-to-present and safe.
    @State private var celebration: Celebration?
    /// True only while the inbox is the on-screen tab. We gate the banner
    /// on this so a celebration that fires while the user is elsewhere in
    /// the app doesn't pop a banner over the wrong surface.
    @State private var isInboxVisible: Bool = false
    @State private var lastSecondaryRefresh: Date?
    @State private var groupChat = WhisperGroupChatService.shared
    @State private var coachRequests = WhisperCoachRequestService.shared
    @State private var snapshots = WhisperClientSnapshotService.shared
    @State private var followingProfiles: [WhisperUserRow] = []
    /// Every simple boolean-driven modal this screen presents, funneled
    /// through a single `.sheet(item:)`. Stacking many `.sheet(isPresented:)`
    /// modifiers on one view works in the debug simulator but hard-crashes on
    /// launch in release/TestFlight builds — one enum-driven sheet avoids it.
    private enum InboxSheet: Int, Identifiable {
        case newGroup, newMessage, thought, lyrics, replies, messageTools
        var id: Int { rawValue }
    }
    @State private var inboxSheet: InboxSheet?
    /// Branded ellipsis menu for the inbox header (New group / Open Whisper).
    @State private var headerMenu: WhisperActionMenuModel?
    @State private var badgeAwards = WhisperBadgeAwardService.shared
    /// Unified role/badge status — ONE whisper_profiles read that seeds every
    /// role service, so the briefcase can't miss a promotion.
    @State private var accountStatus = WhisperAccountStatusService.shared
    @State private var businessWorkspace: WhisperBusinessWorkspaceService = .shared
    @State private var liarSvc = WhisperLiarLiarService.shared
    @State private var safetySvc = WhisperSafetyService.shared
    @State private var blocks = WhisperBlockService.shared
    @State private var storyPickerItem: PhotosPickerItem?
    @State private var storyPickerPresented: Bool = false
    @State private var openThread: WhisperConversationSummary?
    @State private var openKnot = false
    @State private var contactDetailsThread: WhisperConversationSummary?
    @State private var contactDetailsGroup: WhisperGroup?
    @State private var pendingContactThread: WhisperConversationSummary?
    @State private var pendingContactGroup: WhisperGroup?
    @Namespace private var inboxPortraitTransition
    @State private var knotHistory = WhisperEmberHistoryStore.shared
    @State private var knotBackground = WhisperKnotBackgroundService.shared
    @State private var openGroup: WhisperGroup?
    @State private var openStory: WhisperStoryRow?
    /// Friend's thought-bubble target when the user taps another user's
    /// "What's on your mind" bubble in the DM strip. Drives the IG-Notes
    /// reply sheet so the tap routes to a reply instead of opening stories.
    @State private var friendThoughtTarget: InboxFriendThoughtTarget?
    /// Drives the community-chat sheet for replies to the signed-in user's
    /// own thought — opened from the small replier-avatar badge on the
    /// "What's on your mind" bubble in the DM strip.
    @State private var thoughtReplies = WhisperThoughtRepliesService.shared
    /// Story whose responses sheet should be presented when the author
    /// taps the photo thumb on a question-response notification. Opens the
    /// same swipe-up viewers + responses sheet they get from their own
    /// story, so they can browse every answer in one place and tap the one
    /// they want to act on.
    @State private var openResponsesFor: WhisperStoryRow?

    /// Ticks every 60s so relative labels ("5 min ago", "Active now") refresh
    /// without a manual pull-to-reload.
    @State private var tickerNow: Date = Date()
    /// Inbox row whose absolute timestamp is currently revealed (Instagram-
    /// style tap-to-reveal).
    @State private var revealedThreadID: String?
    /// Group pending delete confirmation — set from the group row's
    /// context menu, cleared when the alert resolves.
    @State private var confirmDeleteGroup: WhisperGroup?
    @State private var deletingGroupID: UUID?
    @State private var groupDeletionError: String?
    @State private var groupDeletionTask: Task<Void, Never>?
    @State private var groupDeletionOperation: UUID = UUID()
    /// CRM-style conversation tags (lead / brand opp / collab / client /
    /// follow-up) + the currently active tag filter chip.
    @State private var threadTags = WhisperThreadTagsService.shared
    @State private var tagFilter: WhisperThreadTag?
    @State private var ember = WhisperEmberService.shared
    @State private var mentionsSvc = WhisperMentionsService.shared
    @State private var responsesSvc = WhisperStoryResponseService.shared
    @State private var followRequestsSvc = WhisperFollowRequestService.shared
    /// Requester profiles (avatar/display name) for the follow-request rows.
    @State private var followRequestProfiles: [String: WhisperBackendService.WhisperPublicProfile] = [:]
    /// Request IDs currently mid-approve/deny — dims + disables their row.
    @State private var followRequestWorking: Set<String> = []
    /// Lookup cache for mention rows: author_id -> username (display) and
    /// source post_id -> first media URL (preview thumb).
    @State private var mentionAuthors: [String: String] = [:]
    @State private var mentionThumbs: [String: URL?] = [:]
    /// Snapshot of `activity.lastReadAt` (and per-service unread cutoffs)
    /// taken the moment the user lands on the Activity tab. The on-row
    /// blue unread dots compare against this snapshot — *not* the live
    /// service value — so dots stay visible during the current viewing
    /// session even though `markAllRead()` advances the real cutoff to
    /// `now` for cross-device sync. Reset on every tab re-entry.
    @State private var activityUnreadCutoff: Date?
    /// Go-live alerts for accounts I follow (whisper_live_alerts, live-v2) —
    /// rendered as a "Live now" strip at the top of Activity.
    @State private var liveAlerts: [WhisperLiveModerationService.AlertRow] = []
    @State private var liveAlertRoom: WhisperLiveRoom?
    /// Sticky sets of row IDs that were unread the instant the user
    /// landed on the Activity tab. Used so the blue dot persists for
    /// this viewing session even after `markAllRead` stamps `read_at`.
    @State private var stickyUnreadMentionIDs: Set<String> = []
    @State private var stickyUnreadResponseIDs: Set<String> = []

    private enum Tab { case messages, activity }
    /// Union row for the merged conversation list — group chats and 1:1
    /// threads interleave chronologically instead of groups being pinned
    /// above every DM regardless of recency.
    private enum InboxListRow: Identifiable {
        case group(WhisperGroup, Date)
        case thread(WhisperConversationSummary)
        var id: String {
            switch self {
            case .group(let g, _): return "group-\(g.id.uuidString)"
            case .thread(let t): return "thread-\(t.id)"
            }
        }
        var sortDate: Date {
            switch self {
            case .group(_, let d): return d
            case .thread(let t): return t.lastDate
            }
        }
    }
    /// Inbox bucket selector. `primary` = mutuals (you follow them AND they
    /// follow you back), `general` = approved threads that aren't mutuals,
    /// `coaches` = anyone marked is_coach, `requests` = pending senders.
    private enum Filter: String, CaseIterable { case all = "All", primary = "Primary", general = "General", coaches = "Coaches", dating = "💘 Dating", requests = "Requests" }
    /// Inbox sort order. `recent` = newest first (default), `unread` = unread
    /// rows float to the top, `oldest` = oldest first.
    private enum SortMode: String, CaseIterable, Identifiable {
        case recent = "Most recent"
        case unread = "Unread first"
        case oldest = "Oldest first"
        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .recent: return "clock"
            case .unread: return "envelope.badge"
            case .oldest: return "arrow.down.to.line"
            }
        }
    }

    /// Asset URL for the Whisper ghost button (replaces the Instagram-style
    /// 3-dot menu in the top bar). Tapping it opens the Whisper app.
    private static let jasperGhostURL = URL(string: "https://rork.app/pa/ai4gjjpe5tuarhvseckfl/u5zjxvkrbu4m85ud6fsib")
    private static let jasperGhostFallbackURL = URL(string: "https://pub-e001eb4506b145aa938b5d3badbff6a5.r2.dev/attachments/e1mfcmyumbcsuh6jzq5gl.png")

    var body: some View {
        GeometryReader { viewport in
            HStack(spacing: 0) {
                if showsInlineDetail {
                    tabletDetail
                        .frame(width: max(0, viewport.size.width - (tabletSplit ? conversationListWidth(in: viewport.size.width) + 1 : 0)), height: viewport.size.height)
                        .clipped()
                    if tabletSplit { Divider().frame(width: 1) }
                }
                // Keep this subtree in the same structural position when the
                // window resizes, including its presentation/selection owner.
                inboxPane
                    .background(usesTabletContainer ? WhisperTheme.surface(colorScheme) : .clear)
                    .clipShape(.rect(cornerRadius: usesTabletContainer ? 16 : 0))
                    .overlay {
                        RoundedRectangle(cornerRadius: usesTabletContainer ? 16 : 0)
                            .strokeBorder(usesTabletContainer ? WhisperTheme.hairline(colorScheme) : .clear, lineWidth: 0.6)
                            .allowsHitTesting(false)
                    }
                    // Insets belong inside the reserved pane, so the active
                    // chat does not lose width and a hidden pane stays at zero.
                    .padding(.horizontal, usesTabletContainer && (!showsInlineDetail || tabletSplit) ? 10 : 0)
                    .padding(.vertical, usesTabletContainer ? 24 : 0)
                    .frame(width: showsInlineDetail ? (tabletSplit ? conversationListWidth(in: viewport.size.width) : 0) : viewport.size.width, height: viewport.size.height)
                    .clipped()
                    .opacity(showsInlineDetail && !tabletSplit ? 0 : 1)
                    .allowsHitTesting(!showsInlineDetail || tabletSplit)
                    .accessibilityHidden(showsInlineDetail && !tabletSplit)
            }
            .frame(width: viewport.size.width, height: viewport.size.height)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        .onChange(of: hasOpenConversation) { _, open in conversationIsInline = open ? tabletSplit : nil }
        .onChange(of: openThread?.id) { _, id in if id != nil { openKnot = false; openGroup = nil } }
        .onChange(of: openGroup?.id) { _, id in if id != nil { openKnot = false; openThread = nil } }
        .onChange(of: openKnot) { _, open in if open { openThread = nil; openGroup = nil } }
    }

    @ViewBuilder private var tabletDetail: some View {
        if openKnot {
            WhisperEmberChatView(resumesLatestConversation: true, onExternalClose: { openKnot = false }).id("knot")
        } else if let thread = openThread {
            WhisperDMThreadView(otherUserID: thread.otherUserID, otherUsername: thread.otherUsername, conversationKind: thread.kind, onExternalClose: { openThread = nil }).id(thread.id)
        } else if let group = openGroup {
            WhisperGroupChatView(group: group, onExternalClose: { openGroup = nil }).id(group.id)
        } else {
            ContentUnavailableView("Your conversations", systemImage: "bubble.left.and.bubble.right", description: Text("Choose a chat from the list on the right."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(WhisperChatAppearance.classic.palette(colorScheme).canvas)
        }
    }

    private var inboxPane: some View {
        NavigationStack { inboxPresentedContent }
    }

    private var inboxCanvas: some View {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                GeometryReader { viewport in
                ScrollView {
                    VStack(spacing: 0) {
                        if activityOnly {
                            activityList
                                .padding(.top, 4)
                                .padding(.bottom, 24)
                        } else {
                            storiesStrip
                                .padding(.bottom, 2)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { storyRailHeight = $0 }
                            VStack(spacing: 10) {
                                searchField
                                WhisperInboxCube(disappearing: $showsDisappearingInbox, active: rootChromeActive) {
                                    VStack(spacing: 10) {
                                        celebrationBanner
                                        if filter == .dating { datingInboxBanner }
                                        messagesList
                                    }
                                } back: {
                                    WhisperDisappearingInbox(query: disappearingQuery, active: showsDisappearingInbox && rootChromeActive, composeRequest: disappearingComposeRequest)
                                }
                                if !showsDisappearingInbox { suggestedFollowsSection }
                            }
                            .padding(.top, 8)
                            .padding(.bottom, 104)
                            .frame(minHeight: max(0, viewport.size.height - 52 - storyRailHeight), alignment: .top)
                            .modifier(WhisperStoriesForeground())
                        }
                    }
                    .whisperPadContent()
                }
                .whisperHidesTabBarOnScroll(scrollsUnderStatusBar: !activityOnly)
                // The floating dock and tabs overlay the same continuous canvas.
                // Existing bottom content padding keeps the last row reachable.
                .ignoresSafeArea(.container, edges: .bottom)
                .whisperRefreshable {
                    if activityOnly {
                        // Activity-only mode renders nothing that depends on
                        // threads / stories / follows / coach — only pull
                        // the services that actually back the rows on
                        // screen so a pull-to-refresh is fast and cheap.
                        async let m: Void = mentionsSvc.fetch()
                        async let a: Void = activity.fetch()
                        async let rs: Void = responsesSvc.fetch()
                        async let fr: Void = followRequestsSvc.refresh()
                        _ = await (m, a, rs, fr)
                        await hydrateFollowRequestProfiles()
                    } else if showsDisappearingInbox {
                        await WhisperDisappearingService.shared.refresh()
                    } else {
                        // Pull everything that backs both tabs so the inbox
                        // mirrors the latest Supabase state after a pull-down,
                        // not just the conversation list.
                        async let g: Void = groupChat.syncRegistry(force: true)
                        async let t: Void = backend.fetchThreads()
                        async let s: Void = stories.fetch()
                        async let r: Void = requests.refresh()
                        async let f: Void = follows.refresh()
                        async let m: Void = mentionsSvc.fetch()
                        async let a: Void = activity.fetch()
                        async let rs: Void = responsesSvc.fetch()
                        async let cs: Void = coach.refreshMyStatus()
                        async let kh: Void = knotHistory.sync()
                        async let kb: Void = knotBackground.refresh()
                        async let km: Void = knotBackground.syncMessages(force: true)
                        _ = await (g, t, s, r, f, m, a, rs, cs, kh, kb, km)
                        followingProfiles = await follows.followingProfiles()
                        await coach.ensureCoachStatuses(userIDs: backend.threads.map { $0.otherUserID })
                        await presence.refresh(userIDs: backend.threads.map { $0.otherUserID })
                    }
                }
                }
            }
            .overlay(alignment: .bottom) {
                if !activityOnly && !showsDisappearingInbox {
                    // The meeting-style Jasper dock — the mascot peeking from
                    // behind the pill; tapping runs a live read of the inbox
                    // right here instead of the old inline briefing card.
                    JasperAnalysisDock(
                        pillLabel: "Knot's read",
                        boxTitle: "Inbox analysis",
                        focus: """
                        You are analyzing the user's DM inbox. Each line below is one chat: the handle, whether it's waiting on my reply, and the last message. Write a tight read: lead with who is WAITING ON MY REPLY and what they actually need (topic-specific), flag anything time-sensitive (calendar invites, meetings, proposals, deadlines), then ONE suggested next move. Skip chats where I replied last unless something important is pending.
                        """,
                        buildContext: { inboxAnalysisContext() },
                        emptyText: "No chats yet — once you're talking to people I'll analyze the inbox here.",
                        conversationStyle: true,
                        small: true
                    )
                    // STEADY placement: measured anchoring — the dock sits
                    // right above the tab bar even though this NavigationStack
                    // swallows the bar's safe-area inset. Never under the bar.
                    .whisperPinnedAboveTabBar()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(activityOnly)
            // Flat Instagram-DM header — the system nav bar (and its
            // liquid-glass button chrome on iOS 26) is hidden; a plain
            // pinned row renders the header instead.
            .background(WhisperNavigationPreview())
            .toolbar(.hidden, for: .navigationBar)
            .whisperShelvingHeader(backdrop: WhisperTheme.surface(colorScheme), blurred: !activityOnly) {
                inboxHeaderBar
            }
            .whisperActionMenu($headerMenu)
    }

    private var inboxLifecycleContent: some View {
        inboxCanvas
            .alert(
                "Delete \(confirmDeleteGroup?.name ?? "this group")?",
                isPresented: Binding(
                    get: { confirmDeleteGroup != nil },
                    set: { if !$0 { confirmDeleteGroup = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let g = confirmDeleteGroup {
                        Haptics.warning()
                        beginGroupDeletion(g)
                    }
                    confirmDeleteGroup = nil
                }
            } message: {
                Text("This deletes the server group and permanently revokes its Meet invitations for everyone. The group stays visible here unless deletion is confirmed. Other delivered messages remain in each person's history.")
            }
            .alert("Couldn't confirm group deletion", isPresented: Binding(
                get: { groupDeletionError != nil },
                set: { if !$0 { groupDeletionError = nil } }
            )) { Button("OK", role: .cancel) { groupDeletionError = nil } }
            message: { Text(groupDeletionError ?? "Refresh your groups before retrying.") }
            .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in cancelGroupDeletion() }
            .onDisappear { cancelGroupDeletion() }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now in
                guard rootChromeActive else { return }
                tickerNow = now
                // Refresh presence for every visible thread so "Active …"
                // labels stay current without polling per-row.
                Task {
                    await presence.refresh(userIDs: backend.threads.map { $0.otherUserID })
                    if !activityOnly {
                        await groupChat.syncRegistry()
                        if canPageInbox { await groupChat.fetchInboxSummaries() }
                    }
                }
            }
            .task(id: rootChromeActive) {
                guard rootChromeActive else { return }
                let generation = AccountStorage.generation
                // Activity has one lifecycle-bound loading owner below.
                // Do not launch another copy of those reads from this container.
                if activityOnly { return }
                // Re-hydrate the active thought from local cache so the
                // IG-Notes bubble paints instantly; the server copy refreshes
                // in the parallel batch below.
                thoughts.reloadFromDefaults()
                // Conversation list FIRST — it's what the user opened the
                // inbox for. Everything else hydrates concurrently after.
                async let groupSync: Void = groupChat.syncRegistry()
                await backend.fetchThreadsIfStale()
                await groupSync
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                backend.startMessagesRealtime()
                presence.startHeartbeat()
                let threadUserIDs = backend.threads.map { $0.otherUserID }.filter { !$0.isEmpty }
                let threadUsernames = backend.threads.map { $0.otherUsername }.filter { !$0.isEmpty }
                let uname = myUsername
                if let lastSecondaryRefresh, Date().timeIntervalSince(lastSecondaryRefresh) < 60 { return }
                // Secondary hydration — role badges, safety chips, stories,
                // requests, presence — all independent of each other, so they
                // run in parallel instead of the old ~14-step serial chain.
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await WhisperAccountStatusService.shared.refresh() }
                    group.addTask { await WhisperThoughtService.shared.refreshFromServer() }
                    group.addTask { await WhisperCoachService.shared.refreshMyStatus() }
                    group.addTask { await WhisperVerificationService.shared.refreshMyStatus() }
                    group.addTask { await WhisperBrandService.shared.refreshMyBrand() }
                    group.addTask { await WhisperRecruiterService.shared.refreshMyStatus() }
                    group.addTask { await UserVerificationService.shared.preload(usernames: [uname]) }
                    group.addTask { await WhisperBlockService.shared.refresh() }
                    group.addTask { await WhisperCoachService.shared.ensureCoachStatuses(userIDs: threadUserIDs) }
                    group.addTask { await WhisperLiarLiarService.shared.preload(usernames: threadUsernames) }
                    group.addTask { await WhisperSafetyService.shared.preloadAgeBands(userIDs: threadUserIDs) }
                    group.addTask {
                        await WhisperSafetyService.shared.preloadWatchFlags(
                            userIDs: threadUserIDs,
                            usernames: threadUsernames
                        )
                    }
                    group.addTask { await WhisperStoryService.shared.fetchIfStale() }
                    group.addTask { await FriendRequestsService.shared.refresh() }
                    group.addTask { await WhisperFollowService.shared.refreshIfStale() }
                    group.addTask { await WhisperCoachRequestService.shared.refresh() }
                    group.addTask { await WhisperPresenceService.shared.beat() }
                    group.addTask { await WhisperPresenceService.shared.refresh(userIDs: threadUserIDs) }
                }
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                let profiles = await follows.followingProfiles()
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                followingProfiles = profiles
                lastSecondaryRefresh = Date()
            }
            .task(id: "\(rootChromeActive)-\(WhisperCoachRequestService.shared.myCoaches.count)") {
                guard rootChromeActive, !activityOnly,
                      !WhisperCoachRequestService.shared.myCoaches.isEmpty, !Task.isCancelled else { return }
                await snapshots.uploadIfNeeded()
            }
    }

    private var inboxPresentedContent: some View {
        inboxLifecycleContent
            .sheet(item: $inboxSheet) { sheet in
                switch sheet {
                case .messageTools:
                    WhisperMessagingToolsListView()
                case .newGroup:
                    WhisperNewGroupSheet { g in
                        inboxSheet = nil
                        openGroup = g
                    }
                case .newMessage:
                    WhisperNewMessageSheet { userID, username in
                        inboxSheet = nil
                        openThread = WhisperConversationSummary(
                            otherUserID: userID,
                            otherUsername: username,
                            lastMessage: "",
                            lastDate: Date()
                        )
                    }
                case .thought:
                    WhisperThoughtComposerView()
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .presentationContentInteraction(.scrolls)
                        .whisperSheetBorder()
                case .lyrics:
                    WhisperThoughtLyricsView(
                        text: thoughts.text,
                        accent: thoughts.accent,
                        emoji: thoughts.emoji,
                        colorHex: thoughts.colorHex,
                        style: thoughts.style,
                        posterUsername: LeaderboardService.shared.savedUsername
                            ?? AuthenticationService.shared.currentUser.username
                            ?? "you",
                        isOwner: true,
                        onEdit: {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                inboxSheet = .thought
                            }
                        }
                    )
                    .presentationDetents([.height(360)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(22)
                    .whisperSheetBorder()
                case .replies:
                    WhisperThoughtRepliesSheet()
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .presentationCornerRadius(22)
                        .whisperSheetBorder()
                }
            }
            .fullScreenCover(isPresented: $presentCoachStudio) {
                WhisperCoachClientsView()
            }
            // Groups open full screen exactly like a DM thread — the sheet
            // presentation clipped the header and lost the thread chrome.
            .whisperEdgeBack(isEnabled: activityOnly, controller: backTransition) { backTransition.perform { dismiss() } }
            .fullScreenCover(item: Binding(get: { usesInlinePresentation ? nil : openGroup }, set: { if !usesInlinePresentation { openGroup = $0 } })) { g in
                WhisperGroupChatView(group: g)
            }
            .task(id: AccountStorage.generation) { knotHistory.reloadForCurrentAccount() }
            .fullScreenCover(isPresented: Binding(get: { !usesInlinePresentation && openKnot }, set: { if !usesInlinePresentation { openKnot = $0 } })) { WhisperEmberChatView(resumesLatestConversation: true) }
            .sheet(item: $contactDetailsThread, onDismiss: {
                if let thread = pendingContactThread { pendingContactThread = nil; openThread = thread }
            }) { thread in
                NavigationStack {
                    let cached = backend.threadProfiles[thread.otherUserID]
                    let user = WhisperUserRow(user_id: thread.otherUserID, username: cached?.username ?? thread.otherUsername, display_name: cached?.display_name, bio: nil, interests: nil, profile_image_url: cached?.profile_image_url, onboarded_at: nil, is_private: nil)
                    WhisperDMDetailsView(user: user, messages: backend.directMessages(with: thread.otherUserID, kind: thread.kind), conversationKey: thread.kind.localKey(peer: thread.otherUserID)) { _ in
                        pendingContactThread = thread; contactDetailsThread = nil
                    }
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { contactDetailsThread = nil } } }
                }
                .presentationDetents([.large]).presentationDragIndicator(.visible)
                .modifier(WhisperPortraitDestination(sourceID: thread.id, namespace: inboxPortraitTransition))
            }
            .sheet(item: $contactDetailsGroup, onDismiss: {
                if let group = pendingContactGroup { pendingContactGroup = nil; openGroup = group }
            }) { selected in
                NavigationStack {
                    WhisperGroupDetailsSheet(group: Binding(get: { groupChat.group(byID: selected.id) ?? selected }, set: { _ in }), messages: groupChat.messages(forGroup: selected), onSearch: {
                        pendingContactGroup = selected; contactDetailsGroup = nil
                    }) { contactDetailsGroup = nil }
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { contactDetailsGroup = nil } } }
                }
                .presentationDetents([.large]).presentationDragIndicator(.visible)
                .modifier(WhisperPortraitDestination(sourceID: selected.id.uuidString, namespace: inboxPortraitTransition))
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("WhisperMeetingAccountWillChange"))) { _ in
                knotHistory.clearForAccountChange()
                openThread = nil; openGroup = nil; conversationIsInline = nil
                openKnot = false; pendingContactThread = nil; pendingContactGroup = nil; contactDetailsThread = nil; contactDetailsGroup = nil
            }
            .fullScreenCover(item: Binding(get: { usesInlinePresentation ? nil : openThread }, set: { if !usesInlinePresentation { openThread = $0 } })) { thread in
                WhisperDMThreadView(otherUserID: thread.otherUserID, otherUsername: thread.otherUsername, conversationKind: thread.kind)
            }
            // Widget deep links: open a DM by @username (and optionally
            // pop the Imagine sheet for the Jasper widget's Imagine tag).
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperOpenDMByUsername"))) { note in
                guard rootChromeActive, !activityOnly else { return }
                let epoch = AccountStorage.generation
                guard
                    let handle = (note.userInfo?["username"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                    !handle.isEmpty
                else { return }
                let lower = handle.lowercased()
                let openImagine = (note.userInfo?["imagine"] as? Bool) ?? false
                let routedThreadID = note.userInfo?["threadID"] as? String
                Task {
                    let existing: WhisperConversationSummary? = backend.threads.first { thread in
                        thread.kind == .resolve(threadID: routedThreadID, first: AccountStorage.currentUserID, second: thread.otherUserID) && thread.otherUsername.lowercased() == lower
                    }
                    if let existing {
                        guard rootChromeActive, epoch == AccountStorage.generation, !Task.isCancelled else { return }
                        openThread = existing
                    } else if let row = await WhisperUserService.shared.fetchByUsername(handle) {
                        guard rootChromeActive, epoch == AccountStorage.generation, !Task.isCancelled else { return }
                        await MainActor.run {
                            openThread = WhisperConversationSummary(
                                otherUserID: row.user_id,
                                otherUsername: row.username ?? handle,
                                lastMessage: "",
                                lastDate: Date(),
                                kind: .resolve(threadID: routedThreadID, first: AccountStorage.currentUserID, second: row.user_id)
                            )
                        }
                    } else if lower == "ember" {
                        guard rootChromeActive, epoch == AccountStorage.generation, !Task.isCancelled else { return }
                        await MainActor.run {
                            openThread = WhisperConversationSummary(
                                otherUserID: "ember",
                                otherUsername: "ember",
                                lastMessage: "",
                                lastDate: Date()
                            )
                        }
                    }
                    if openImagine {
                        try? await Task.sleep(for: .milliseconds(450))
                        guard epoch == AccountStorage.generation, !Task.isCancelled, openThread != nil else { return }
                        NotificationCenter.default.post(
                            name: Notification.Name("WhisperOpenImagineSheet"),
                            object: nil
                        )
                    }
                }
            }
            // Stories belong in a fullScreenCover — presenting them in a
            // half-sheet (the previous behavior) chopped off the bottom of
            // the photo and broke the swipe-down-to-dismiss gesture.
            .fullScreenCover(item: $openStory) { story in
                let group = stories.storiesByUser().first { $0.userID == story.user_id }
                let all = Array((group?.all ?? [story]).reversed())
                WhisperStoryViewer(
                    stories: all,
                    startIndex: stories.firstUnseenIndex(in: all)
                )
            }
            .sheet(item: $friendThoughtTarget) { target in
                // Tapping a friend's IG-Notes bubble in the DM stories
                // strip opens the same community group-chat the owner
                // sees — not a one-on-one reply sheet. Repliers see
                // every other reply on the same thought.
                WhisperThoughtRepliesSheet(
                    externalOwnerUID: target.note.user_id,
                    externalOwnerUsername: target.username
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(22)
                .whisperSheetBorder()
            }
            .sheet(item: $openResponsesFor) { story in
                WhisperStoryViewersSheet(story: story)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .whisperSheetBorder()
            }
            // Story composer lives at the root — when attached deeper inside
            // the stories strip (`yourNoteBubble`) the LazyVStack recycled
            // the row mid-presentation, which made the `+` button feel
            // broken (cover never showed or flashed dark and dismissed).
            .fullScreenCover(isPresented: $storyPickerPresented) {
                WhisperStoryComposerView()
                    .task { await stories.fetch() }
            }
            .sheet(item: $celebration) { celebration in
                switch celebration {
                case .coach:
                    WhisperCoachWelcomeView(onTakeTour: {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            presentCoachStudio = true
                        }
                    })
                    .whisperSheetBorder()
                case .verified:
                    WhisperVerifiedWelcomeView()
                        .whisperSheetBorder()
                }
            }
            .sheet(item: Binding(get: { rootChromeActive && !activityOnly && openThread == nil && openGroup == nil ? badgeAwards.pendingAward : nil }, set: { if $0 == nil && rootChromeActive { badgeAwards.pendingAward = nil } })) { award in
                WhisperBadgeAwardSheet(kind: award.kind) {
                    badgeAwards.pendingAward = nil
                }
            }
            .onChange(of: coach.isMeCoach) { _, _ in
                badgeAwards.evaluate()
            }
            .onChange(of: liarSvc.badgesByUsername.count) { _, _ in
                badgeAwards.evaluate()
            }
            .onChange(of: safetySvc.trustedByUserID.count) { _, _ in
                badgeAwards.evaluate()
            }
            .onAppear {
                badgeAwards.evaluate()
                isInboxVisible = true
            }
            .onDisappear {
                isInboxVisible = false
            }
    }

    // MARK: - Celebration presentation

    /// Highest-priority pending approval celebration, or nil when none is
    /// waiting. Drives the inline banner (never an auto-presented sheet).
    private var pendingCelebration: Celebration? {
        if coach.shouldCelebrateApproval { return .coach }
        if verification.shouldCelebrateApproval { return .verified }
        return nil
    }

    /// Inline banner the user taps to view the welcome — same pattern as
    /// the settings/hamburger menu. Never auto-presents, so it cannot race
    /// another sheet and crash release builds.
    @ViewBuilder
    private var celebrationBanner: some View {
        if isInboxVisible, let pending = pendingCelebration, celebration == nil {
            Button {
                Haptics.success()
                switch pending {
                case .coach: coach.markCelebrated()
                case .verified: verification.markCelebrated()
                }
                celebration = pending
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "party.popper")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 0.13, green: 0.55, blue: 0.96))
                        .frame(width: 32, height: 32)
                        .background(Color(red: 0.13, green: 0.55, blue: 0.96).opacity(colorScheme == .dark ? 0.16 : 0.08), in: .rect(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pending == .coach ? "You're approved as a coach!" : "You're verified!")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        Text("Tap to view your welcome")
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .background(Color(red: 0.13, green: 0.55, blue: 0.96).opacity(colorScheme == .dark ? 0.12 : 0.06), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color(red: 0.13, green: 0.55, blue: 0.96).opacity(0.3), lineWidth: 1)
            }
        }
    }

    // MARK: - IG-style header

    private var myUsername: String {
        LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"
    }

    /// The recessed top layer owns the Inbox heading and primary actions.
    private var inboxHeaderBar: some View {
        ZStack {
            if activityOnly {
                Text("Activity")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                    .frame(maxWidth: 200)
            }
            HStack(spacing: 2) {
                if activityOnly {
                    Button {
                        Haptics.tap()
                        backTransition.perform { dismiss() }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .frame(width: 40, height: 40)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                } else {
                    Menu {
                        Button("Messages", systemImage: "bubble.left.and.bubble.right") {
                            withAnimation(.whisperSmooth) { showsDisappearingInbox = false }
                        }
                        Button("Flicks", systemImage: "square.stack.3d.up") {
                            withAnimation(.whisperSmooth) { showsDisappearingInbox = true }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(showsDisappearingInbox ? "Flicks" : "Inbox")
                                .font(.largeTitle.weight(.bold))
                            Image(systemName: "chevron.down").font(.caption.weight(.bold))
                        }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .accessibilityLabel(showsDisappearingInbox ? "Flicks inbox" : "Messages inbox")
                    .accessibilityHint("Choose an inbox. You can also swipe across the message list.")
                }
                if !activityOnly && AccountStorage.currentUserID == "guest" {
                    Button {
                        Haptics.tap()
                        openWhisperApp()
                    } label: {
                        jasperGhostIcon
                            .frame(width: 30, height: 30)
                            .frame(width: 40, height: 40)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open Whisper")
                }
                Spacer()
                if activityOnly {
                    Button {
                        Haptics.tap()
                        activity.markAllRead()
                        // Advance the local session snapshot/sticky sets so
                        // the on-row blue dots clear immediately.
                        activityUnreadCutoff = Date()
                        stickyUnreadMentionIDs.removeAll()
                        stickyUnreadResponseIDs.removeAll()
                        Task {
                            await mentionsSvc.markAllRead()
                            await responsesSvc.markAllRead()
                        }
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .frame(width: 40, height: 40)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mark all as read")
                } else {
                    if !showsDisappearingInbox {
                    Button {
                        Haptics.tap()
                        headerMenu = WhisperActionMenuModel(
                            title: "Messages",
                            actions: [
                                WhisperMenuAction(icon: "person.3.fill", title: "New group", subtitle: "Start a group chat") {
                                    inboxSheet = .newGroup
                                },
                                WhisperMenuAction(icon: "text.bubble", title: "Quick replies", subtitle: "Your saved messaging templates") {
                                    inboxSheet = .messageTools
                                },
                                WhisperMenuAction(icon: "arrow.up.forward.app", title: "Open Whisper", subtitle: "Jump to your fitness app") {
                                    openWhisperApp()
                                },
                            ]
                        )
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .frame(width: 36, height: 40)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("More")
                    }
                    Button {
                        Haptics.tap()
                        if showsDisappearingInbox { disappearingComposeRequest += 1 }
                        else { inboxSheet = .newMessage }
                    } label: {
                        Image(systemName: showsDisappearingInbox ? "camera" : "square.and.pencil")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .frame(width: 40, height: 40)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showsDisappearingInbox ? "Send a Flick" : "New message")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background {
            if activityOnly { WhisperTheme.surface(colorScheme) }
            else { WhisperScrollingHeaderBackdrop() }
        }
        .background { Color.clear.contentShape(.rect).onTapGesture { } }
    }


    private var jasperGhostIcon: some View {
        // Bundled template ghost — auto-tints to ink color so the glyph
        // is black in light mode and white in dark mode.
        Image("WhisperGhostMono")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(WhisperTheme.ink(colorScheme))
    }

    /// Opens the standalone Whisper app via its custom URL scheme. Falls
    /// through silently if the scheme isn't registered on this device.
    private func openWhisperApp() {
        let candidates = ["jasper://", "thejasperapp://", "jasperapp://"]
        for raw in candidates {
            if let url = URL(string: raw), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }
        // Last resort — try opening the first candidate so iOS shows the
        // App Store install prompt if a universal link is registered.
        if let url = URL(string: candidates[0]) {
            UIApplication.shared.open(url)
        }
    }

    /// True when the signed-in user has at least one assigned role with a
    /// dedicated tool surface — drives the briefcase button in the header.
    /// The unified whisper_profiles status is the primary answer (every
    /// promotion lives there now); the per-role services stay as fallbacks
    /// for pre-migration schemas.
    private var hasRoleTools: Bool {
        let badge = UserVerificationService.shared.badge(forUsername: myUsername)
        return accountStatus.status.hasAnyRole
            || businessWorkspace.context != nil
            || coach.isMeCoach
            || recruiter.isMeRecruiter
            || brands.myBrand != nil
            || badge == .verified || badge == .moderator || badge == .admin || badge == .owner
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                TextField(showsDisappearingInbox ? "Search Flicks" : "Search messages", text: inboxSearch)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                if !inboxSearch.wrappedValue.isEmpty {
                    Button {
                        inboxSearch.wrappedValue = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(WhisperTheme.card(colorScheme), in: Capsule())
            if !showsDisappearingInbox {
            Menu {
                Section("Show") {
                    ForEach(Filter.allCases, id: \.self) { f in
                        Button {
                            Haptics.tap()
                            withAnimation(.whisperSnappy) { filter = f }
                        } label: {
                            if filter == f {
                                Label(f.rawValue, systemImage: "checkmark")
                            } else {
                                Text(f.rawValue)
                            }
                        }
                    }
                }
                if !threadTags.usedTags.isEmpty {
                    Section("Tags") {
                        Button { tagFilter = nil } label: {
                            if tagFilter == nil { Label("All tags", systemImage: "checkmark") }
                            else { Text("All tags") }
                        }
                        ForEach(threadTags.usedTags) { tag in
                            Button { tagFilter = tag } label: {
                                Label(tag.label, systemImage: tagFilter == tag ? "checkmark" : tag.icon)
                            }
                        }
                    }
                }
                Section("Sort by") {
                    ForEach(SortMode.allCases) { s in
                        Button {
                            Haptics.tap()
                            withAnimation(.whisperSnappy) { sort = s }
                        } label: {
                            if sort == s {
                                Label(s.rawValue, systemImage: "checkmark")
                            } else {
                                Label(s.rawValue, systemImage: s.systemImage)
                            }
                        }
                    }
                }
            } label: {
                Text(filter == .all && tagFilter == nil && sort == .recent ? "Filter" : "Filtered")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.36, green: 0.44, blue: 1.0))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Filter and sort")
            .accessibilityValue("\(filter.rawValue), \(tagFilter?.label ?? "all tags"), \(sort.rawValue)")
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Stories strip

    private var otherStoryGroups: [(username: String, userID: String, latest: WhisperStoryRow, all: [WhisperStoryRow])] {
        stories.storiesByUser().filter { $0.userID.lowercased() != AccountStorage.currentUserID.lowercased() }
    }

    /// Union of friend user IDs we care about surfacing thought bubbles for —
    /// every active DM thread partner plus every account I follow. This is
    /// the candidate pool for `refreshOthers`, so a friend's "What's on your
    /// mind?" bubble appears in the strip even when they have no story.
    private var friendCandidateIDs: [String] {
        let me = AccountStorage.currentUserID.lowercased()
        var ids = Set<String>()
        for t in backend.threads {
            let id = t.otherUserID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !id.isEmpty && id != me && id != "guest" && !id.hasPrefix("local_") {
                ids.insert(id)
            }
        }
        for p in followingProfiles {
            let id = p.user_id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !id.isEmpty && id != me && id != "guest" && !id.hasPrefix("local_") {
                ids.insert(id)
            }
        }
        // Story authors are already candidates too — covers anyone we haven't
        // followed yet but who showed up in stories.
        for g in otherStoryGroups {
            let id = g.userID.lowercased()
            if !id.isEmpty && id != me { ids.insert(id) }
        }
        return Array(ids)
    }

    /// Friends who have an active IG-Notes thought but no active story —
    /// rendered as standalone bubbles in the strip so their "What's on your
    /// mind?" updates surface even when they haven't posted a story.
    private var thoughtOnlyGroups: [(username: String, userID: String, note: WhisperThoughtRow)] {
        let storyIDs = Set(otherStoryGroups.map { $0.userID.lowercased() })
        var seen = Set<String>()
        var out: [(username: String, userID: String, note: WhisperThoughtRow)] = []
        for uid in friendCandidateIDs {
            let key = uid.lowercased()
            if storyIDs.contains(key) { continue }
            if seen.contains(key) { continue }
            guard let note = thoughts.activeThought(forUserID: key) else { continue }
            // Resolve a username from whichever source has it. Prefer the
            // public profile cache (matches what the thread row shows), then
            // any followed-profile row, then the thread's own username.
            let fromProfile = backend.threadProfiles[key]?.username
            let fromFollow = followingProfiles.first { $0.user_id.lowercased() == key }?.username
            let fromThread = backend.threads.first { $0.otherUserID.lowercased() == key }?.otherUsername
            // `cachedUsername` also self-heals: when no cache has this id it
            // fires a one-shot profile fetch so the handle fills in on the
            // next render instead of sticking as "user".
            let username = [fromProfile, fromFollow, fromThread]
                .compactMap { $0 }
                .first { !$0.isEmpty && $0.lowercased() != "user" }
                ?? backend.cachedUsername(forUserID: key)
                ?? "user"
            out.append((username: username, userID: key, note: note))
            seen.insert(key)
        }
        // Most-recent thought first so the freshest updates lead the strip
        // section, mirroring the story-ordering behavior.
        out.sort { lhs, rhs in
            let l = WhisperBackendService.parseISO(lhs.note.posted_at ?? "") ?? .distantPast
            let r = WhisperBackendService.parseISO(rhs.note.posted_at ?? "") ?? .distantPast
            return l > r
        }
        return out
    }

    private var storiesStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 14) {
                yourNoteBubble
                // Exclude my own group — my stories live inside the
                // "Your story" bubble's ring at the start of the strip,
                // not as a duplicate bubble alongside friends.
                ForEach(otherStoryGroups, id: \.userID) { item in
                    storyBubble(username: item.username, story: item.latest, all: item.all)
                }
                // Friends with an active thought but no story still get a
                // bubble here — without this, "What's on your mind?" only
                // surfaces for users who also posted a story today.
                ForEach(thoughtOnlyGroups, id: \.userID) { item in
                    thoughtOnlyBubble(username: item.username, userID: item.userID, note: item.note)
                }
            }
            .padding(.vertical, 4)
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        // Force observation of `others` so the strip re-renders the moment
        // the cache changes — belt-and-braces in case the helper-method
        // read inside `storyBubble` isn't tracked by SwiftUI.
        .id(thoughts.others.count)
        .task(id: friendCandidateIDs.joined(separator: ",")) {
            await thoughts.refreshOthers(userIDs: friendCandidateIDs)
        }
        // Poll every 15s while the strip is on-screen so other users'
        // thoughts surface without needing a manual refresh.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                await thoughts.refreshOthers(userIDs: friendCandidateIDs)
            }
        }
    }

    /// Friend bubble for the case where the friend has an IG-Notes thought
    /// but no active story. No story ring, no avatar from a story row —
    /// just the avatar + the thought bubble. Tapping the bubble opens the
    /// reply sheet; tapping the avatar/username opens their profile via
    /// the same `friendThoughtTarget` route (kept consistent with how the
    /// story version opens the IG-Notes reply sheet on bubble tap).
    private func thoughtOnlyBubble(username: String, userID: String, note: WhisperThoughtRow) -> some View {
        let bubbleAction: () -> Void = {
            friendThoughtTarget = InboxFriendThoughtTarget(
                note: note,
                username: username
            )
        }
        return VStack(spacing: 6) {
            WhisperAvatarChrome(
                username: username,
                size: 84,
                imageURL: URL(string: backend.threadProfiles[userID.lowercased()]?.profile_image_url ?? ""),
                // No story ring — but keep the neutral hairline ring so the
                // bubble visually balances the story-ring siblings.
                storyRing: false,
                ringTint: nil,
                plusButton: false,
                thoughtText: note.text,
                thoughtStyle: WhisperThoughtStyle(rawValue: note.style ?? "") ?? .plain,
                thoughtAccent: note.accent ?? "",
                thoughtEmoji: note.emoji ?? "",
                thoughtColorHex: note.color_hex ?? "",
                bubbleScale: 1.0,
                onBubbleTap: bubbleAction
            )
            .contentShape(Circle())
            .onTapGesture {
                Haptics.tap()
                bubbleAction()
            }
            Text(username)
                .font(.caption2)
                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.7))
                .lineLimit(1)
                .frame(maxWidth: 94)
        }
    }

    private var yourNoteBubble: some View {
        let me = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"
        // IG-Notes-style cloud bubble lives here too now — same component
        // as the profile screen, just at story-strip scale. Tapping the
        // bubble opens the same composer.
        let bubbleText = thoughts.isActive ? thoughts.displayText : "Note..."
        let hasStory = stories.meHasActiveStory
        let hasUnreadReplies = thoughtReplies.unreadCount > 0
        let latestReplier: WhisperThoughtReplyRow? = thoughtReplies.incoming.first
        return VStack(spacing: 6) {
            WhisperAvatarChrome(
                username: me,
                size: 84,
                storyRing: hasStory,
                ringTint: hasStory ? Color(red: 0.20, green: 0.55, blue: 1.0) : nil,
                plusButton: true,
                plusSymbol: "plus",
                thoughtText: bubbleText,
                thoughtStyle: thoughts.isActive ? thoughts.style : .plain,
                thoughtAccent: thoughts.isActive ? thoughts.accent : "",
                thoughtEmoji: thoughts.isActive ? thoughts.emoji : "",
                thoughtColorHex: thoughts.isActive ? thoughts.colorHex : "",
                bubbleScale: 1.0,
                bubblePulse: hasUnreadReplies,
                onPlusTap: { storyPickerPresented = true },
                onBubbleTap: {
                    if thoughts.isActive && thoughts.style == .music {
                        inboxSheet = .lyrics
                    } else {
                        inboxSheet = .thought
                    }
                }
            ) {
                EmptyView()
            }
            // The emoji corner badge now always lives on the bubble's
            // top-LEFT, so the replier avatar pins to the top-RIGHT at the
            // symmetric (10, -10) — the two badges sit at the same height on
            // opposite sides and can never overlap each other.
            .overlay(alignment: .topTrailing) {
                if let row = latestReplier {
                    replierBadge(row: row)
                }
            }
            .onTapGesture {
                if hasStory, let first = stories.myStories().first {
                    Haptics.tap()
                    openStory = first
                }
            }
            .task { await thoughtReplies.refreshForMe() }
            Text(thoughts.isActive ? "Your note" : "Your story")
                .font(.caption2)
                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.55))
                .lineLimit(1)
                .frame(maxWidth: 94)
        }
    }

    /// Small replier avatar pinned at the top-right of the user's IG-Notes
    /// bubble — mirrors the emoji-badge position so it reads as part of the
    /// bubble itself. Tapping it opens the community-chat sheet.
    @ViewBuilder
    private func replierBadge(row: WhisperThoughtReplyRow) -> some View {
        Button {
            Haptics.tap()
            inboxSheet = .replies
        } label: {
            let url = row.replier_avatar_url.flatMap { URL(string: $0) }
            WhisperCachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    Circle()
                        .fill(WhisperTheme.card(colorScheme))
                        .overlay {
                            Text(String(row.replier_username.prefix(1)).uppercased())
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                }
            }
            .frame(width: 22, height: 22)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(WhisperTheme.surface(colorScheme), lineWidth: 2)
            }
            .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        // Sits on the bubble's right edge, lower than the emoji on the
        // opposite side so the two badges never crowd each other. The
        // emoji is at the bubble's top-leading corner; this avatar pin
        // is nudged down 22pt so it perches near the bubble's right
        // side instead of floating above its top edge.
        .offset(x: 10, y: 8)
        .accessibilityLabel("\(row.replier_username) replied")
    }

    private func storyBubble(username: String, story: WhisperStoryRow, all: [WhisperStoryRow]) -> some View {
        let unseen = stories.hasUnseenStories(userID: story.user_id)
        let isFavorite = WhisperStoryFavorites.shared.isFavorite(story.user_id)
        let peekGroup: [WhisperStoryRow] = all.isEmpty ? [story] : Array(all.reversed())
        // Other user's IG-Notes thought (if any) surfaces above their
        // story avatar so updates are visible right in the DMs strip.
        let note = thoughts.activeThought(forUserID: story.user_id)
        // Provide an `onBubbleTap` so the chrome wraps the thought bubble
        // in its own Button — tapping the bubble routes to the IG-Notes
        // reply sheet, while tapping the avatar/username opens the story.
        let bubbleAction: (() -> Void)? = note.map { n in
            { [n] in
                friendThoughtTarget = InboxFriendThoughtTarget(
                    note: n,
                    username: username
                )
            }
        }
        return VStack(spacing: 6) {
            WhisperAvatarChrome(
                username: username,
                size: 84,
                imageURL: URL(string: story.image_url),
                // Always render the ring while a story is active — the
                // tint switches from brand blue (unseen) to neutral
                // gray (seen) instead of vanishing.
                storyRing: true,
                ringTint: unseen ? Color(red: 0.20, green: 0.55, blue: 1.0) : nil,
                plusButton: false,
                thoughtText: note?.text,
                thoughtStyle: WhisperThoughtStyle(rawValue: note?.style ?? "") ?? .plain,
                thoughtAccent: note?.accent ?? "",
                thoughtEmoji: note?.emoji ?? "",
                thoughtColorHex: note?.color_hex ?? "",
                bubbleScale: 1.0,
                onBubbleTap: bubbleAction
            )
            .overlay(alignment: .bottomTrailing) {
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(WhisperBrandGradient.diagonal, in: Circle())
                        .overlay { Circle().strokeBorder(WhisperTheme.surface(colorScheme), lineWidth: 2) }
                        .offset(x: 2, y: -2)
                }
            }
            .contentShape(Circle())
            .onTapGesture {
                Haptics.tap()
                openStory = story
            }
            // Press and hold to PEEK without recording a view.
            .onLongPressGesture(minimumDuration: 0.32, maximumDistance: 12) {
                WhisperPeekCenter.shared.present(.story(peekGroup))
            }
            Text(username)
                .font(.caption2)
                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.7))
                .lineLimit(1)
                .frame(maxWidth: 94)
        }
    }

    /// The 💘 filter's rose banner — cupid Jasper explains the space.
    private var datingInboxBanner: some View {
        let rose = Color(red: 0.91, green: 0.28, blue: 0.49)
        return HStack(spacing: 12) {
            WhisperJasperInteractiveMascot(size: 40, dating: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Dating chats")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(rose)
                Text("People you said hi to in the Dating hub land here — with Knot's date tools in every chat.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(rose.opacity(colorScheme == .dark ? 0.13 : 0.07), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(rose.opacity(0.25), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Filter pills

    /// Instagram-DM filter chips — the selected chip inverts (white pill
    /// in dark mode) with a blue unread dot + count; unselected chips are
    /// quiet raised pills with no border. Sorting lives in the Filter menu.
    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Filter.allCases, id: \.self) { f in
                    Button {
                        Haptics.tap()
                        withAnimation(.whisperSnappy) { filter = f }
                    } label: {
                        let count = badgeCount(for: f)
                        HStack(spacing: 6) {
                            if count > 0 {
                                Circle()
                                    .fill(Color(red: 0.36, green: 0.44, blue: 1.0))
                                    .frame(width: 6, height: 6)
                            }
                            Text(f.rawValue)
                                .font(.subheadline.weight(.semibold))
                            if count > 0 {
                                Text("\(count)\(backend.inboxHasMore ? "+" : "")")
                                    .accessibilityLabel(backend.inboxHasMore ? "At least \(count)" : "\(count)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                        }
                        .foregroundStyle(filter == f ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(filter == f ? WhisperTheme.ink(colorScheme) : WhisperTheme.card(colorScheme), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// Ranked thread lines for the bottom analysis dock — unread first,
    /// then most recent. Each line carries the reply-state so the model
    /// prioritizes what actually needs attention, and every last message is
    /// sanitized through the same preview renderer the inbox rows use so
    /// embed payloads never dump raw JSON into the prompt.
    private func inboxAnalysisContext() -> String? {
        let ranked = approvedThreads.sorted { a, b in
            let aWaiting = !a.lastFromMe && !a.lastReadByMe
            let bWaiting = !b.lastFromMe && !b.lastReadByMe
            if aWaiting != bWaiting { return aWaiting }
            return a.lastDate > b.lastDate
        }
        let source = ranked.prefix(10)
        guard !source.isEmpty else { return nil }
        let lines = source.map { thread in
            let p = Self.previewFor(body: thread.lastMessage, fallback: "No messages yet")
            let status = thread.lastFromMe
                ? "I replied last"
                : (thread.lastReadByMe ? "read, no reply needed yet" : "WAITING ON MY REPLY")
            return "@\(thread.otherUsername): (\(status)) \(p.text)"
        }
        return lines.joined(separator: "\n")
    }

    private func badgeCount(for f: Filter) -> Int {
        switch f {
        case .requests: return requests.incoming.count + requestThreads.count
        case .coaches: return approvedThreads.filter { $0.kind == .direct && coach.isCoach(userID: $0.otherUserID) }.count
        case .dating: return approvedThreads.filter { $0.kind == .dating && !$0.lastReadByMe }.count
        case .primary: return approvedThreads.filter { $0.kind == .direct && isMutual($0.otherUserID) && !$0.lastReadByMe }.count
        case .general: return approvedThreads.filter { $0.kind == .direct && !isMutual($0.otherUserID) && !$0.lastReadByMe }.count
        case .all: return approvedThreads.filter { !$0.lastReadByMe }.count
        }
    }

    // MARK: - Threads

    /// Threads that should land in the main inbox: either privacy is off, or
    /// the other user is a mutual / approved sender. Excludes denied users
    /// AND auto-detected spam (spam routes to the Requests bucket regardless
    /// of privacy setting).
    private var approvedThreads: [WhisperConversationSummary] {
        backend.threads.filter {
            !blocks.isBlocked(userID: $0.otherUserID)
                && isApproved($0.otherUserID)
                && !dmPrivacy.isDenied($0.otherUserID)
                && !isLikelySpam($0)
        }
    }

    /// Threads from users you don't follow and who don't follow you — plus
    /// auto-detected spam from non-mutuals.
    private var requestThreads: [WhisperConversationSummary] {
        backend.threads.filter {
            !blocks.isBlocked(userID: $0.otherUserID)
            && !dmPrivacy.isDenied($0.otherUserID)
            && (
                (dmPrivacy.isPrivate && !isApproved($0.otherUserID))
                || isLikelySpam($0)
            )
        }
    }

    /// Auto-spam routing: messages from users that don't follow you AND
    /// you don't follow back, where the body trips the spam scorer.
    /// Mutuals are never flagged so real friends never disappear from the
    /// inbox.
    private func isLikelySpam(_ thread: WhisperConversationSummary) -> Bool {
        if follows.isFollowing(userID: thread.otherUserID) { return false }
        if follows.isFollowedBy(userID: thread.otherUserID) { return false }
        if dmPrivacy.isApproved(thread.otherUserID) { return false }
        // Memoized — this predicate runs several times per thread per render
        // (every filter chip's badge count re-evaluates it), so the verdict
        // is cached per (sender, message) instead of re-scoring each time.
        return WhisperSpamFilter.cachedIsSpam(message: thread.lastMessage, senderUsername: thread.otherUsername)
    }

    private func isApproved(_ otherUserID: String) -> Bool {
        if !dmPrivacy.isPrivate { return true }
        if dmPrivacy.isApproved(otherUserID) { return true }
        if follows.isFollowing(userID: otherUserID) { return true }
        if follows.isFollowedBy(userID: otherUserID) { return true }
        return false
    }

    /// True when both directions of the follow graph match — friends, in
    /// IG-speak. Drives the Primary / General split so Primary stays scoped
    /// to actual mutuals instead of "every approved sender".
    private func isMutual(_ otherUserID: String) -> Bool {
        follows.isFollowing(userID: otherUserID) && follows.isFollowedBy(userID: otherUserID)
    }

    /// Horizontal chip row for tag filtering — only appears once at least
    /// one conversation is tagged. Tapping a chip narrows the inbox to
    /// that tag; tap again to clear.
    @ViewBuilder
    private var tagFilterRow: some View {
        let used = threadTags.usedTags
        if !used.isEmpty, filter != .requests {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(used) { t in
                        let active = tagFilter == t
                        Button {
                            Haptics.tap()
                            withAnimation(.whisperSnappy) {
                                tagFilter = active ? nil : t
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: t.icon)
                                    .font(.system(size: 10, weight: .heavy))
                                Text(t.label)
                                    .font(.caption.weight(.bold))
                            }
                            .foregroundStyle(active ? WhisperTheme.surface(colorScheme) : t.color)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(active ? AnyShapeStyle(t.color) : AnyShapeStyle(t.color.opacity(0.12)), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var filteredThreads: [WhisperConversationSummary] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let bucket: [WhisperConversationSummary] = {
            switch filter {
            case .all:
                return approvedThreads
            case .primary:
                return approvedThreads.filter { $0.kind == .direct && isMutual($0.otherUserID) }
            case .general:
                return approvedThreads.filter { $0.kind == .direct && !isMutual($0.otherUserID) }
            case .coaches:
                return approvedThreads.filter { $0.kind == .direct && coach.isCoach(userID: $0.otherUserID) }
            case .dating:
                // Chats marked 💘 — say-hi opens from the Dating hub land here.
                return approvedThreads.filter { $0.kind == .dating }
            case .requests:
                return []
            }
        }()
        let tagged: [WhisperConversationSummary]
        if let tagFilter {
            tagged = bucket.filter { threadTags.tag(for: $0.otherUserID) == tagFilter }
        } else {
            tagged = bucket
        }
        let searched: [WhisperConversationSummary]
        if q.isEmpty {
            searched = tagged
        } else {
            searched = tagged.filter { thread in
                // Also match the hydrated profile handle — the row displays
                // it when it differs from the (possibly stale) thread name,
                // so search must find what the user actually sees.
                let profileName = backend.threadProfiles[thread.otherUserID]?.username?.lowercased() ?? ""
                return thread.otherUsername.lowercased().contains(q)
                    || thread.lastMessage.lowercased().contains(q)
                    || WhisperUserSearch.matches(q, username: profileName, displayName: backend.threadProfiles[thread.otherUserID]?.display_name)
            }
        }
        switch sort {
        case .recent:
            return searched.sorted { $0.lastDate > $1.lastDate }
        case .oldest:
            return searched.sorted { $0.lastDate < $1.lastDate }
        case .unread:
            // Unread (lastReadByMe == false) floats up; ties broken by recency.
            return searched.sorted { a, b in
                if a.lastReadByMe != b.lastReadByMe { return !a.lastReadByMe }
                return a.lastDate > b.lastDate
            }
        }
    }

    /// Group chats visible for the current filter/search. Groups live in
    /// the All bucket (they aren't mutual/coach/request classifiable) and
    /// match the search query by group name.
    private var visibleGroups: [(group: WhisperGroup, date: Date)] {
        guard filter == .all, tagFilter == nil else { return [] }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return groupChat.visibleGroups.compactMap { g in
            if !q.isEmpty && !g.name.lowercased().contains(q) { return nil }
            let date = groupChat.lastMessage(forGroup: g)?.date ?? g.createdAt
            return (g, date)
        }
    }

    /// Merged, chronologically sorted inbox rows — groups interleave with
    /// 1:1 threads by recency instead of being pinned above everything.
    /// "Unread first" keeps the thread ordering and floats groups by date.
    private var inboxRows: [InboxListRow] {
        let groupRows: [InboxListRow] = visibleGroups.map { .group($0.group, $0.date) }
        let threadRows: [InboxListRow] = filteredThreads.map { .thread($0) }
        switch sort {
        case .oldest:
            return (groupRows + threadRows).sorted { $0.sortDate < $1.sortDate }
        case .unread:
            let unreadGroups = Set(visibleGroups.filter { groupChat.isUnread($0.group) }.map { $0.group.id })
            return (groupRows + threadRows).sorted { a, b in
                func unread(_ row: InboxListRow) -> Bool {
                    switch row {
                    case .group(let g, _): return unreadGroups.contains(g.id)
                    case .thread(let t): return !t.lastReadByMe
                    }
                }
                if unread(a) != unread(b) { return unread(a) }
                return a.sortDate > b.sortDate
            }
        case .recent:
            return (groupRows + threadRows).sorted { $0.sortDate > $1.sortDate }
        }
    }

    private var canPageInbox: Bool {
        rootChromeActive && inboxScenePhase == .active && tab == .messages
            && !showsDisappearingInbox && openThread == nil && openGroup == nil
    }

    private var messagesList: some View {
        LazyVStack(spacing: 0) {
            if showsKnotThread { knotConversationRow }
            messagesListContent
            if backend.inboxHasMore || backend.inboxPageError != nil || backend.isLoadingInboxPage || groupChat.inboxHasMore || groupChat.inboxError != nil || groupChat.inboxLoading {
                VStack(spacing: 10) {
                    if let error = backend.inboxPageError {
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                        Button("Try again") {
                            Task { await backend.fetchInboxSummaries(older: backend.inboxRetryOlder) }
                        }
                        .frame(minHeight: 44)
                        .disabled(backend.isLoadingInboxPage || !canPageInbox)
                    } else if backend.isLoadingInboxPage {
                        ProgressView().accessibilityLabel("Loading conversations")
                    }
                    if let error = groupChat.inboxError {
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                        Button("Retry groups") { Task { await groupChat.fetchInboxSummaries(older: groupChat.inboxRetryOlder) } }
                            .frame(minHeight: 44).disabled(groupChat.inboxLoading || !canPageInbox)
                    } else if groupChat.inboxLoading {
                        ProgressView().accessibilityLabel("Loading groups")
                    }
                    Color.clear.frame(height: 1)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .onScrollVisibilityChange(threshold: 0.1) { inboxEndVisible = $0 }
                .task(id: "\(inboxEndVisible)|\(canPageInbox)|\(backend.inboxContinuationID)|\(backend.isLoadingInboxPage)") {
                    guard inboxEndVisible, canPageInbox, !backend.isLoadingInboxPage,
                          backend.inboxPageError == nil, backend.inboxHasMore else { return }
                    await backend.fetchInboxSummaries(older: true)
                }
                .task(id: "\(inboxEndVisible)|\(canPageInbox)|\(groupChat.inboxContinuationID)|\(groupChat.inboxLoading)") {
                    guard inboxEndVisible, canPageInbox, !groupChat.inboxLoading,
                          groupChat.inboxError == nil, groupChat.inboxHasMore else { return }
                    await groupChat.fetchInboxSummaries(older: true)
                }
            }
        }
    }

    private var showsKnotThread: Bool {
        (filter == .all || filter == .primary) && tagFilter == nil &&
        (query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || "Knot assistant".localizedStandardContains(query))
    }

    private var knotConversationRow: some View {
            HStack(spacing: 14) {
                Button {
                    Haptics.tap(); knotHistory.reloadForCurrentAccount(); openKnot = true
                } label: { WhisperKnotProfilePortrait(size: WhisperConversationPortraitSize.inbox, expression: .calm) }
                    .buttonStyle(WhisperPortraitPressStyle()).accessibilityLabel("Open Knot conversation")
                Button {
                    Haptics.tap(); knotHistory.reloadForCurrentAccount(); openKnot = true
                } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Knot").font(.subheadline.weight(.semibold))
                        if knotBackground.unread > 0 {
                            Text(knotBackground.unread > 99 ? "99+" : String(knotBackground.unread))
                                .font(.caption2.weight(.bold)).monospacedDigit()
                                .foregroundStyle(Color.white).padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Color.blue, in: Capsule())
                                .accessibilityLabel("\(knotBackground.unread) unread Knot updates")
                        }
                        Spacer()
                        if let date = knotHistory.conversations.first?.updatedAt {
                            Text(date, style: .relative).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Text(knotHistory.conversations.first?.messages.last?.text ?? "Ask Knot anything")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity).contentShape(.rect)
                }.buttonStyle(.plain).accessibilityLabel(knotBackground.unread > 0 ? "Knot, conversation, \(knotBackground.unread) unread updates" : "Knot, conversation")
            }
            .foregroundStyle(WhisperTheme.ink(colorScheme))
            .padding(.horizontal, 20).padding(.vertical, 12).contentShape(.rect)
        .background { selectedConversationBackground(tabletSplit && openKnot) }
        .accessibilityAddTraits(tabletSplit && openKnot ? .isSelected : [])
        .onAppear { knotHistory.reloadForCurrentAccount() }
    }

    @ViewBuilder
    private var messagesListContent: some View {
        if filter == .requests {
            requestsList
        } else if approvedThreads.isEmpty && groupChat.visibleGroups.isEmpty && !backend.inboxHasMore && !groupChat.inboxHasMore {
            if let error = backend.threadsLoadError ?? groupChat.inboxError ?? groupChat.lastError {
                ContentUnavailableView {
                    Label("Messages couldn't load", systemImage: "wifi.exclamationmark")
                } description: { Text(error) } actions: {
                    Button("Try again") { Task {
                        async let threads: Void = backend.fetchThreads()
                        async let groups: Void = groupChat.syncRegistry(force: true)
                        _ = await (threads, groups)
                    } }
                        .buttonStyle(.bordered)
                        .disabled(backend.isLoadingThreads)
                }
            } else if !backend.hasLoadedThreads || !groupChat.registryChecked || !groupChat.hasLoadedInbox {
                VStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { index in
                        WhisperCommentSkeletonRow(index: index)
                    }
                }
                .padding(.vertical, 12)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Loading messages")
            } else if backend.inboxPageError == nil && groupChat.inboxError == nil && !showsKnotThread {
                emptyMessagesState
            }
        } else {
            let rows = inboxRows
            if rows.isEmpty && !backend.inboxHasMore && !groupChat.inboxHasMore && groupChat.inboxError == nil {
                if !showsKnotThread { noMatchesState }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        switch row {
                        case .group(let g, _):
                            groupButton(g)
                        case .thread(let thread):
                            threadButton(thread)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    /// Shown when the search / tag filter matches nothing — replaces the
    /// silent blank area the list used to collapse into.
    private var noMatchesState: some View {
        VStack(spacing: 6) {
            WhisperMeetDoodle(symbol: "magnifyingglass", height: 120)
            Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                 ? "Nothing here yet"
                 : "No results for \u{201C}\(query.trimmingCharacters(in: .whitespacesAndNewlines))\u{201D}")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Try a different search or filter.")
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .padding(.top, 40)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
    }

    private func beginGroupDeletion(_ group: WhisperGroup) {
        guard groupDeletionTask == nil else { return }
        let epoch = AccountStorage.generation
        let token = UUID(); groupDeletionOperation = token
        deletingGroupID = group.id; groupDeletionError = nil
        groupDeletionTask = Task {
            defer {
                if groupDeletionOperation == token { groupDeletionTask = nil; deletingGroupID = nil }
            }
            guard !Task.isCancelled, epoch == AccountStorage.generation else { return }
            let deleted = await groupChat.deleteGroup(group.id)
            guard !Task.isCancelled, epoch == AccountStorage.generation, groupDeletionOperation == token else { return }
            if !deleted {
                groupDeletionError = groupChat.lastError ?? "Deletion wasn't confirmed. Refresh your groups before retrying; Meet invitation revocation hasn't been confirmed here."
            }
        }
    }

    private func cancelGroupDeletion() {
        groupDeletionOperation = UUID()
        groupDeletionTask?.cancel(); groupDeletionTask = nil
        deletingGroupID = nil; groupDeletionError = nil; confirmDeleteGroup = nil
    }

    private func selectedConversationBackground(_ selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(WhisperTheme.ink(colorScheme).opacity(selected ? 0.07 : 0))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
    }

    private func groupButton(_ g: WhisperGroup) -> some View {
        groupRow(g)
        .background { selectedConversationBackground(tabletSplit && openGroup?.id == g.id) }
        .accessibilityAddTraits(tabletSplit && openGroup?.id == g.id ? .isSelected : [])
        .onTapGesture { Haptics.tap(); openGroup = g }
        .accessibilityAction { Haptics.tap(); openGroup = g }
        .contextMenu {
            if groupChat.isOwner(g) {
                Button(role: .destructive) { confirmDeleteGroup = g } label: {
                    Label(deletingGroupID == g.id ? "Deleting group…" : "Delete group", systemImage: "trash")
                }.disabled(deletingGroupID != nil)
            } else {
                Button { Task { await groupChat.leave(g) } } label: {
                    Label("Hide group on this device", systemImage: "eye.slash")
                }
            }
        }
    }

    private func threadButton(_ thread: WhisperConversationSummary) -> some View {
        threadRow(thread)
        .background { selectedConversationBackground(tabletSplit && openThread?.id == thread.id) }
        .accessibilityAddTraits(tabletSplit && openThread?.id == thread.id ? .isSelected : [])
        .onTapGesture { Haptics.tap(); openThread = thread }
        .accessibilityAction { Haptics.tap(); openThread = thread }
        // Long-press → iMessage-style peek of the last few messages, rendered
        // instantly from the already-loaded conversation cache.
        .contextMenu {
            Button {
                Haptics.tap()
                openThread = thread
            } label: {
                Label("Open conversation", systemImage: "arrow.up.right.square")
            }
            Menu {
                ForEach(WhisperThreadTag.allCases) { t in
                    Button {
                        Haptics.tap()
                        threadTags.setTag(t, for: thread.otherUserID)
                    } label: {
                        Label(t.label, systemImage: t.icon)
                    }
                }
                if threadTags.tag(for: thread.otherUserID) != nil {
                    Divider()
                    Button(role: .destructive) {
                        Haptics.tap()
                        threadTags.setTag(nil, for: thread.otherUserID)
                        if tagFilter != nil && threadTags.usedTags.isEmpty { tagFilter = nil }
                    } label: {
                        Label("Remove tag", systemImage: "tag.slash")
                    }
                }
            } label: {
                Label("Tag conversation", systemImage: "tag")
            }
        } preview: {
            WhisperConversationPeek(thread: thread)
        }
    }

    private func groupRow(_ g: WhisperGroup) -> some View {
        let last = groupChat.lastMessage(forGroup: g)
        let unread = groupChat.isUnread(g)
        return HStack(spacing: 12) {
            Button { Haptics.tap(); contactDetailsGroup = g } label: {
                WhisperGroupAvatarView(group: g, size: WhisperConversationPortraitSize.inbox)
                    .matchedTransitionSource(id: g.id.uuidString, in: inboxPortraitTransition)
            }.buttonStyle(WhisperPortraitPressStyle()).accessibilityLabel("\(g.name), conversation details")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(g.name)
                        .font(.subheadline.weight(unread ? .bold : .semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(1)
                    Text("· \(g.members.count + 1)")
                        .font(.caption2)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                let groupPreview = Self.previewFor(body: last?.body ?? "", fallback: "Tap to message the group")
                HStack(spacing: 5) {
                    if let icon = groupPreview.icon {
                        Image(systemName: icon)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    Text(groupPreview.text)
                        .font(.footnote)
                        .foregroundStyle(unread ? WhisperTheme.ink(colorScheme) : WhisperTheme.muted(colorScheme))
                        .fontWeight(unread ? .semibold : .regular)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(timeLabel(last?.date ?? g.createdAt))
                    .font(.caption2).foregroundStyle(WhisperTheme.muted(colorScheme))
                if unread { Circle().fill(.blue).frame(width: 8, height: 8) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(.rect)
    }

    private var emptyMessagesState: some View {
        VStack(spacing: 28) {
            WhisperEmptyState(icon: "bubble.left.and.bubble.right", title: "No messages yet",
                message: "Start a chat to break the silence.", isCard: false, illustration: .messages)

            Button {
                Haptics.tap()
                inboxSheet = .newMessage
            } label: {
                Text("New message")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 60)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var requestsList: some View {
        VStack(spacing: 14) {
            privacyToggleCard
            if !requestThreads.isEmpty {
                dmRequestsSection
            }
            friendRequestsSection
            hiddenRequestsSection
        }
    }

    /// Threads the user denied. Previously a deny was irreversible — the
    /// thread vanished from both the inbox and Requests with no way back.
    /// This section lists them with a one-tap Restore.
    private var deniedThreads: [WhisperConversationSummary] {
        backend.threads.filter {
            dmPrivacy.isDenied($0.otherUserID) && !blocks.isBlocked(userID: $0.otherUserID)
        }
    }

    @ViewBuilder
    private var hiddenRequestsSection: some View {
        let denied = deniedThreads
        if !denied.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Hidden")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .padding(.horizontal, 22)
                VStack(spacing: 0) {
                    ForEach(Array(denied.enumerated()), id: \.element.id) { idx, thread in
                        hiddenRequestRow(thread)
                        if idx < denied.count - 1 {
                            Divider().background(WhisperTheme.hairline(colorScheme)).padding(.leading, 70)
                        }
                    }
                }
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
                .padding(.horizontal, 16)
            }
        }
    }

    private func hiddenRequestRow(_ thread: WhisperConversationSummary) -> some View {
        let profile = backend.threadProfiles[thread.otherUserID]
        let name = profile?.username ?? thread.otherUsername
        let url = profile?.profile_image_url.flatMap(URL.init(string:))
        return HStack(spacing: 12) {
            WhisperAvatar(username: name, size: 44, imageURL: url, ring: false)
                .opacity(0.7)
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(name)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("Hidden from your inbox")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer()
            Button {
                Haptics.success()
                withAnimation(.whisperSnappy) {
                    dmPrivacy.reset(thread.otherUserID)
                }
            } label: {
                Text("Restore")
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(WhisperTheme.card(colorScheme), in: Capsule())
                    .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var privacyToggleCard: some View {
        HStack(spacing: 12) {
            Image(systemName: dmPrivacy.isPrivate ? "lock.fill" : "lock.open.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WhisperTheme.surface(colorScheme))
                .frame(width: 32, height: 32)
                .background(WhisperTheme.ink(colorScheme), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Private account")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text(dmPrivacy.isPrivate
                     ? "DMs from non-mutuals land here"
                     : "Anyone can message you directly")
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { dmPrivacy.isPrivate },
                set: { newValue in
                    Haptics.tap()
                    dmPrivacy.isPrivate = newValue
                }
            ))
            .labelsHidden()
            .tint(WhisperTheme.ink(colorScheme))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
        .padding(.horizontal, 16)
    }

    private var dmRequestsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Message requests")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 22)
            VStack(spacing: 0) {
                ForEach(Array(requestThreads.enumerated()), id: \.element.id) { idx, thread in
                    dmRequestRow(thread)
                    if idx < requestThreads.count - 1 {
                        Divider().background(WhisperTheme.hairline(colorScheme)).padding(.leading, 70)
                    }
                }
            }
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
            .padding(.horizontal, 16)
        }
    }

    private func dmRequestRow(_ thread: WhisperConversationSummary) -> some View {
        let profile = backend.threadProfiles[thread.otherUserID]
        let name = profile?.username ?? thread.otherUsername
        let url = profile?.profile_image_url.flatMap(URL.init(string:))
        let spam = isLikelySpam(thread)
        return HStack(spacing: 10) {
            Button {
                Haptics.tap()
                openThread = thread
            } label: {
                HStack(spacing: 12) {
                    WhisperAvatar(username: name, size: 44, imageURL: url, ring: false)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("@\(name)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                            if spam {
                                Text("SPAM")
                                    .font(.system(size: 9, weight: .heavy))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.red.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.red)
                            }
                        }
                        let p = Self.previewFor(
                    body: thread.lastMessage,
                    fallback: "Wants to chat",
                    senderLabel: thread.lastFromMe ? "You" : "@\(thread.otherUsername)"
                )
                        HStack(spacing: 4) {
                            if let icon = p.icon {
                                Image(systemName: icon)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(WhisperTheme.coachAccent)
                            }
                            Text(p.text)
                                .font(.caption)
                                .foregroundStyle(p.icon != nil ? WhisperTheme.ink(colorScheme) : WhisperTheme.muted(colorScheme))
                                .fontWeight(p.icon != nil ? .semibold : .regular)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Button {
                Haptics.success()
                withAnimation(.whisperSnappy) {
                    dmPrivacy.approve(thread.otherUserID)
                }
            } label: {
                Text("Accept")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
            }
            .buttonStyle(.plain)
            Button {
                Haptics.warning()
                withAnimation(.whisperSnappy) {
                    dmPrivacy.deny(thread.otherUserID)
                }
            } label: {
                Text("Deny")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(WhisperTheme.card(colorScheme), in: Capsule())
                    .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var friendRequestsSection: some View {
        if requests.incoming.isEmpty && requestThreads.isEmpty && deniedThreads.isEmpty {
            VStack(spacing: 6) {
                WhisperMeetDoodle(symbol: "tray", height: 120)
                Text("No requests")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            .padding(.top, 40)
            .frame(maxWidth: .infinity)
        } else if !requests.incoming.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Friend requests")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .padding(.horizontal, 22)
                VStack(spacing: 0) {
                    ForEach(requests.incoming) { req in
                        HStack(spacing: 12) {
                            WhisperAvatar(username: req.from_username, size: WhisperConversationPortraitSize.inbox, ring: false)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("@\(req.from_username)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                                Text("Sent you a friend request")
                                    .font(.caption)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                            Spacer()
                            Button("Accept") {
                                Haptics.success()
                                Task { await requests.accept(req) }
                            }
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(WhisperTheme.ink(colorScheme), in: Capsule())
                            .foregroundStyle(WhisperTheme.surface(colorScheme))
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                }
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
                .padding(.horizontal, 16)
            }
        }
    }

    private func threadRow(_ thread: WhisperConversationSummary) -> some View {
        let profile = backend.threadProfiles[thread.otherUserID]
        let name = profile?.username ?? thread.otherUsername
        let url = profile?.profile_image_url.flatMap(URL.init(string:))
        let isCoach = coach.isCoach(userID: thread.otherUserID)
        let preview = Self.previewFor(
            body: thread.lastMessage,
            fallback: "Tap to say hi",
            senderLabel: thread.lastFromMe ? "You" : "@\(name)"
        )
        _ = tickerNow // re-evaluate when the minute ticker fires
        let activeLabel = presence.activeLabel(forUserID: thread.otherUserID)
        let activeNow = activeLabel == "Active now"
        let revealed = revealedThreadID == thread.id
        let unread = !thread.lastReadByMe
        return HStack(alignment: .center, spacing: 12) {
            Button { Haptics.tap(); contactDetailsThread = thread } label: {
            ZStack(alignment: .bottomTrailing) {
                WhisperAvatar(username: name, size: WhisperConversationPortraitSize.inbox, imageURL: url, ring: false)
                    .matchedTransitionSource(id: thread.id, in: inboxPortraitTransition)
                if activeNow {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 14, height: 14)
                        .overlay { Circle().strokeBorder(WhisperTheme.surface(colorScheme), lineWidth: 2) }
                        .offset(x: 1, y: 1)
                }
            }
            }.buttonStyle(WhisperPortraitPressStyle()).accessibilityLabel("\(name), conversation details")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(name)
                        .font(.subheadline.weight(unread ? .bold : .semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(1).truncationMode(.tail)
                    Image(systemName: thread.kind == .dating ? "heart.fill" : (isCoach ? "figure.strengthtraining.traditional" : (isMutual(thread.otherUserID) ? "person.2.fill" : "bubble.left.fill")))
                        .font(.caption2).foregroundStyle(thread.kind == .dating ? Color.pink : WhisperTheme.muted(colorScheme))
                        .accessibilityLabel(thread.kind == .dating ? "Dating conversation" : (isCoach ? "Coach conversation" : (isMutual(thread.otherUserID) ? "Primary conversation" : "General conversation")))
                    if isCoach { WhisperCoachBadge(size: 12) }
                    if let tag = threadTags.tag(for: thread.otherUserID) {
                        WhisperThreadTagChip(tag: tag)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 5) {
                    if let icon = preview.icon {
                        Image(systemName: icon)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    Text(preview.text)
                        .font(.footnote)
                        .foregroundStyle(unread ? WhisperTheme.ink(colorScheme) : WhisperTheme.muted(colorScheme))
                        .fontWeight(unread ? .semibold : .regular)
                        .lineLimit(1)
                }
                if !activeNow, let label = activeLabel {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }
            Spacer()
            // Trailing meta column — timestamp with the unread dot below it,
            // Instagram-style. Tapping the timestamp toggles the exact
            // stamp (the old long-press fought the row's context menu —
            // both fired on the same press).
            VStack(alignment: .trailing, spacing: 6) {
                Button {
                    Haptics.tap()
                    withAnimation(.whisperSnappy) {
                        revealedThreadID = revealed ? nil : thread.id
                    }
                } label: {
                    Text(revealed ? exactStamp(thread.lastDate) : timeLabel(thread.lastDate))
                        .font(.caption2)
                        .foregroundStyle(revealed ? WhisperTheme.ink(colorScheme) : WhisperTheme.muted(colorScheme))
                        .fontWeight(revealed ? .semibold : .regular)
                        .padding(.vertical, 2)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if unread {
                    Circle()
                        .fill(Color(red: 0.0, green: 0.48, blue: 1.0))
                        .frame(width: 8, height: 8)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .contentShape(.rect)
    }

    /// Renders a friendly inbox preview for a DM body. Program and workout
    /// embeds otherwise dump their raw JSON blob into the last-message slot,
    /// which looks broken to the recipient.
    static func previewFor(
        body: String,
        fallback: String,
        senderLabel: String? = nil
    ) -> (text: String, icon: String?) {
        if body.isEmpty { return (fallback, nil) }
        // Group-chat wire rows (web-created groups fan out as 1:1 rows) —
        // translate to "GroupName: friendly line" instead of leaking the
        // raw ::wg-v1:: wire into previews.
        if body.hasPrefix(WhisperGroupChatService.headerPrefix) {
            if let parsed = WhisperGroupChatService.parse(body) {
                let inner = previewFor(body: parsed.body, fallback: fallback, senderLabel: nil)
                return ("\(parsed.name): \(inner.text)", "person.3.fill")
            }
            return ("Group message", "person.3.fill")
        }
        // 📅 second-date wire — friendly line, never the raw token.
        if let line = WhisperSecondDate.previewLine(body) {
            return (line, "calendar.badge.plus")
        }
        // 💘 mutual-match wire — friendly lines, never the raw token.
        if body.hasPrefix("::whisper-matchreq-v1::") {
            return ("Wants to match 💘", "heart.fill")
        }
        if body.hasPrefix("::whisper-matched-v1::") {
            return ("It's a match! 💘", "heart.fill")
        }
        let who = senderLabel ?? ""
        let prefix = who.isEmpty ? "" : "\(who) sent "
        if WhisperMapEmbed.decode(body) != nil {
            return ("\(prefix.isEmpty ? "Sent " : prefix)a map", "mappin.and.ellipse")
        }
        if WhisperChartEmbed.decode(body) != nil {
            return ("\(prefix.isEmpty ? "Sent " : prefix)a chart", "chart.bar.fill")
        }
        if let r = WhisperRecipeEmbed.decode(body) {
            let t = r.title.trimmingCharacters(in: .whitespaces)
            return ("\(prefix.isEmpty ? "Shared " : prefix)recipe\(t.isEmpty ? "" : " \u{00b7} \(t)")", "book.fill")
        }
        if let g = WhisperGroceryListEmbed.decode(body) {
            let t = g.title.trimmingCharacters(in: .whitespaces)
            return ("\(prefix.isEmpty ? "Sent " : prefix)grocery list\(t.isEmpty ? "" : " \u{00b7} \(t)")", "cart.fill")
        }
        if WhisperMacrosShareEmbed.decode(body) != nil {
            return ("\(prefix.isEmpty ? "Shared " : prefix)today's macros", "scalemass.fill")
        }
        if WhisperCheckinEmbed.decode(body) != nil {
            return ("\(prefix.isEmpty ? "Sent " : prefix)a check-in", "heart.text.square.fill")
        }
        if WhisperWorkoutProposalEmbed.decode(body) != nil {
            return ("\(prefix.isEmpty ? "Sent " : prefix)a workout proposal", "dumbbell.fill")
        }
        if let notes = WhisperMeetingNotesMessage.parse(body) {
            return ("\(prefix.isEmpty ? "Sent " : prefix)meeting notes \u{00b7} \(notes.title)", "doc.text.fill")
        }
        if WhisperEmberAnswerEmbed.decode(body) != nil {
            return ("\(prefix.isEmpty ? "Sent " : prefix)a Knot answer", "sparkles")
        }
        if WhisperThoughtReplyEmbed.decode(body) != nil {
            // Note replies no longer live in DMs — they surface in the
            // "What's on your mind" community bubble on the owner's
            // profile. Show a neutral, non-clickable-feeling snippet so
            // any legacy DM rows don't dump JSON into the inbox.
            return ("Note reply moved to profile bubble", "text.bubble.fill")
        }
        if WhisperFactCheckEmbed.decode(body) != nil {
            return ("\(prefix.isEmpty ? "Sent " : prefix)a fact-check", "checkmark.seal.fill")
        }
        if WhisperSharedStoryEmbed.decode(body) != nil {
            return ("\(prefix.isEmpty ? "Shared " : prefix)a story", "circle.dashed")
        }
        if body.hasPrefix(WhisperSharedCommunityEmbed.prefix) {
            let name = WhisperSharedCommunityEmbed.decode(body).flatMap { WhisperSharedCommunityEmbed.community(for: $0)?.name }
            return (name.map { "Shared \($0)" } ?? "Shared a community", "person.2")
        }
        if let p = WhisperSharedPostEmbed.decode(body) {
            return ("\(prefix.isEmpty ? "Shared " : prefix)@\(p.username)'s post", "square.on.square")
        }
        if let p = WhisperProfileShareEmbed.decode(body) {
            return ("\(prefix.isEmpty ? "Shared " : prefix)@\(p.username)'s profile", "person.crop.circle.badge.plus")
        }
        if let p = WhisperCoachProposalEmbed.decode(body) {
            return ("Coach suggestion · \(WhisperCoachProposalEmbed.title(for: p.kind))", "scalemass.fill")
        }
        if let p = WhisperCoachMacrosEmbed.decode(body) {
            let s = WhisperCoachMacrosEmbed.summary(p)
            return ("Macros · \(s.isEmpty ? "from coach" : s)", "scalemass.fill")
        }
        if let p = WhisperCoachDietPlanEmbed.decode(body) {
            return ("Diet plan · \(p.name.isEmpty ? "Coach plan" : p.name)", "fork.knife")
        }
        if WhisperDMThreadView.videoURL(in: body) != nil {
            return ("\(prefix.isEmpty ? "Sent " : prefix)a video", "play.rectangle.fill")
        }
        if WhisperDMThreadView.imageURL(in: body) != nil {
            return ("\(prefix.isEmpty ? "Sent " : prefix)a photo", "photo.fill")
        }
        if let cal = WhisperCalendarEmbed.decode(body) {
            let heading: String
            switch cal.kind {
            case "cancelled": heading = "Event cancelled"
            case "update": heading = "Event updated"
            default: heading = "Calendar invite"
            }
            let t = cal.title.trimmingCharacters(in: .whitespaces)
            return ("\(heading)\(t.isEmpty ? "" : " \u{00b7} \(t)")", "calendar")
        }
        if let c = WhisperCallSummaryEmbed.decode(body) {
            let icon = c.isVideo ? "video.fill" : "phone.fill"
            if c.connected {
                let kind = c.isVideo ? "Video call" : "Audio call"
                return ("\(kind) · \(c.durationLabel)", icon)
            } else {
                return (c.isVideo ? "Missed video call" : "Missed audio call", icon)
            }
        }
        if let p = WhisperProgramEmbed.decode(body) {
            let title = p.title.isEmpty ? "Coach program" : p.title
            return ("Program · \(title)", "list.clipboard.fill")
        }
        if let w = WhisperWorkoutEmbed.decode(body) {
            let title = w.displayName.isEmpty ? "Workout" : w.displayName
            return ("Workout · \(title)", "dumbbell.fill")
        }
        if let f = WhisperFilmEmbed.decode(body) {
            let t = f.title.trimmingCharacters(in: .whitespaces)
            return ("\(prefix.isEmpty ? "Shared " : prefix)a film\(t.isEmpty ? "" : " \u{00b7} \(t)")", "film.fill")
        }
        if let a = WhisperArticleEmbed.decode(body) {
            let t = a.title.trimmingCharacters(in: .whitespaces)
            return ("\(prefix.isEmpty ? "Shared " : prefix)an article\(t.isEmpty ? "" : " \u{00b7} \(t)")", "doc.richtext.fill")
        }
        if WhisperStickerPack.isWhisperSticker(body) {
            return ("\(prefix.isEmpty ? "Sent " : prefix)a sticker", "face.smiling.inverse")
        }
        if WhisperPlanQuizAnswersEmbed.decode(body) != nil {
            return ("Questionnaire answers", "checklist.checked")
        }
        if WhisperPlanQuizEmbed.decode(body) != nil {
            return ("Coach questionnaire", "checklist")
        }
        // Any other (or future) embed token — never leak raw JSON into a
        // preview line, even when this build doesn't know the type yet.
        if body.contains("::whisper-") {
            return ("\(prefix.isEmpty ? "Sent " : prefix)an attachment", "paperclip")
        }
        return (body, nil)
    }

    /// Renders a 1080x1920 vertical gradient image used as the background
    /// when re-sharing a question answer to the author's story. Mirrors
    /// Instagram's Q&A re-share aesthetic (vivid two-stop gradient).
    static func gradientStoryBackground() -> UIImage {
        let size = CGSize(width: 1080, height: 1920)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let cs = CGColorSpaceCreateDeviceRGB()
            let top = UIColor(red: 0.62, green: 0.41, blue: 0.94, alpha: 1).cgColor
            let bot = UIColor(red: 0.95, green: 0.32, blue: 0.55, alpha: 1).cgColor
            let grad = CGGradient(colorsSpace: cs, colors: [top, bot] as CFArray, locations: [0, 1])!
            cg.drawLinearGradient(
                grad,
                start: .zero,
                end: CGPoint(x: 0, y: size.height),
                options: []
            )
        }
    }

    /// Builds the sticker stack that lands on the canvas when re-sharing
    /// an anonymous question response: the original question card up top,
    /// the responder's answer in a large text sticker just below.
    static func answerStickers(
        question: String,
        answer: String,
        responderUsername: String
    ) -> [WhisperStorySticker] {
        // Single question card with the answer baked into the bubble —
        // matches the IG Q&A re-share where the response replaces the
        // "Type something…" placeholder inside the original card.
        let questionCard = WhisperStorySticker(
            kind: .question,
            x: 0.5,
            y: 0.45,
            scale: 1.1,
            text: question.isEmpty ? "Ask me anything" : question,
            answer: answer,
            responderUsername: responderUsername
        )
        return [questionCard]
    }

    /// Instagram-style "Suggested" strip below the conversation list: shows
    /// people you follow on Whisper that you haven't messaged yet, so you can
    /// start a DM in one tap. Hidden in the Requests filter and once you've
    /// already DM'd everyone you follow.
    @ViewBuilder
    private var suggestedFollowsSection: some View {
        let existingOthers = Set(backend.threads.map { $0.otherUserID })
        let candidates = followingProfiles.filter { !existingOthers.contains($0.user_id) }
        if filter != .requests, !candidates.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Suggested")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Spacer()
                    Button {
                        Haptics.tap()
                        inboxSheet = .newMessage
                    } label: {
                        Text("See all")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                VStack(spacing: 0) {
                    ForEach(Array(candidates.prefix(10).enumerated()), id: \.element.id) { idx, p in
                        Button {
                            Haptics.tap()
                            openThread = WhisperConversationSummary(
                                otherUserID: p.user_id,
                                otherUsername: p.username,
                                lastMessage: "",
                                lastDate: Date()
                            )
                        } label: {
                            suggestedRow(p)
                        }
                        .buttonStyle(.plain)
                        if idx < min(candidates.count, 10) - 1 {
                            Divider().background(WhisperTheme.hairline(colorScheme)).padding(.leading, 70)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            .padding(.top, 10)
        }
    }

    private func suggestedRow(_ p: WhisperUserRow) -> some View {
        HStack(spacing: 12) {
            WhisperAvatar(
                username: p.username,
                size: 48,
                imageURL: p.profile_image_url.flatMap(URL.init(string:)),
                ring: false
            )
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(p.username)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("You follow them")
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer()
            Text("Message")
                .font(.caption.weight(.bold))
                .foregroundStyle(WhisperTheme.surface(colorScheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(WhisperTheme.ink(colorScheme), in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(.rect)
    }

    private func timeLabel(_ d: Date) -> String {
        let s = tickerNow.timeIntervalSince(d)
        if s < 60 { return "now" }
        if s < 3600 {
            let m = Int(s / 60)
            return "\(m)m"
        }
        if s < 86_400 {
            let h = Int(s / 3600)
            return "\(h)h"
        }
        if s < 86_400 * 7 {
            let d2 = Int(s / 86_400)
            return "\(d2)d"
        }
        return d.formatted(.dateTime.month().day())
    }

    /// Instagram-style absolute timestamp shown when the inbox row is tapped.
    private func exactStamp(_ d: Date) -> String {
        let cal = Calendar.current
        let df = DateFormatter()
        df.locale = Locale.current
        if cal.isDateInToday(d) {
            df.dateFormat = "h:mm a"
            return df.string(from: d)
        }
        if cal.isDateInYesterday(d) {
            df.dateFormat = "h:mm a"
            return "Yesterday " + df.string(from: d)
        }
        let days = cal.dateComponents([.day], from: d, to: Date()).day ?? 0
        if days < 7 {
            df.dateFormat = "EEE h:mm a"
            return df.string(from: d)
        }
        df.dateFormat = "MMM d, h:mm a"
        return df.string(from: d)
    }

    /// Filtered story-response inbox used by Activity. Question responses
    /// (free-text replies to a story `question` sticker) auto-expire 24h
    /// after they were received — matching the story's own 24h lifetime,
    /// so the inbox doesn't accumulate stale replies after the underlying
    /// story is gone. Poll votes and slider ratings are kept indefinitely.
    private var visibleStoryResponses: [WhisperStoryResponseRow] {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        return responsesSvc.inbox.filter { row in
            guard row.kind == "question" else { return true }
            guard let iso = row.created_at,
                  let date = WhisperBackendService.parseISO(iso)
            else { return true }
            return date >= cutoff
        }
    }

    /// True when anything on the Activity tab still shows an unread dot —
    /// drives the explicit "Mark all as read" control.
    private var hasVisibleUnreadActivity: Bool {
        !stickyUnreadMentionIDs.isEmpty
            || !stickyUnreadResponseIDs.isEmpty
            || mentionsSvc.unreadCount > 0
            || activity.unreadCount > 0
    }

    /// Explicit mark-all-read: clears the sticky dot sets immediately (the
    /// user asked for it, so no lingering dots) and stamps every read state.
    private var markAllReadRow: some View {
        HStack {
            Spacer()
            Button {
                Haptics.tap()
                stickyUnreadMentionIDs = []
                stickyUnreadResponseIDs = []
                activityUnreadCutoff = Date()
                activity.markAllRead()
                Task {
                    await mentionsSvc.markAllRead()
                    await responsesSvc.markAllRead()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle")
                        .font(.caption.weight(.bold))
                    Text("Mark all as read")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(WhisperTheme.card(colorScheme), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
    }

    private var activityList: some View {
        VStack(spacing: 18) {
            if hasVisibleUnreadActivity {
                markAllReadRow
            }
            if !liveAlerts.isEmpty {
                liveNowSection
            }
            if !followRequestsSvc.incoming.isEmpty {
                followRequestsSection
            }
            if !visibleStoryResponses.isEmpty {
                storyResponsesSection
            }
            if !mentionsSvc.mentions.isEmpty {
                mentionsSection
            }
            activityFeedSection
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .task(id: "\(rootChromeActive)|\(tab)|\(AccountStorage.generation)") {
            guard rootChromeActive, tab == .activity else { return }
            let generation = AccountStorage.generation
            // Capture cutoffs once on first appearance (covers the case
            // where the inbox opens directly on the Activity tab via the
            // bell button, where `.onChange(of: tab)` doesn't fire).
            if activityUnreadCutoff == nil { activityUnreadCutoff = activity.lastReadAt }
            async let followRequests: Void = refreshActivityFollowRequests()
            async let mentions: Void = mentionsSvc.fetch()
            async let responses: Void = responsesSvc.fetch()
            async let events: Void = activity.fetch()
            async let alerts = WhisperLiveModerationService.shared.fetchMyLiveAlerts(userID: AccountStorage.currentUserID)
            let currentAlerts = await alerts
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            liveAlerts = currentAlerts
            _ = await (followRequests, mentions, responses, events)
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            // Capture sticky unread IDs AFTER the fetch so freshly loaded
            // rows are included — covers the bell-button cold open which
            // lands directly on the Activity tab.
            if stickyUnreadMentionIDs.isEmpty {
                stickyUnreadMentionIDs = Set(mentionsSvc.mentions.filter { mentionsSvc.isUnread($0) }.map { $0.id })
            }
            if stickyUnreadResponseIDs.isEmpty {
                stickyUnreadResponseIDs = Set(responsesSvc.inbox.filter { $0.read_at == nil }.map { $0.id })
            }
            if tab == .activity {
                async let mentionsRead: Void = mentionsSvc.markAllRead()
                async let responsesRead: Void = responsesSvc.markAllRead()
                activity.markAllRead()
                _ = await (mentionsRead, responsesRead)
            }
        }
        .onChange(of: tab) { _, newTab in
            // Auto-clear unread mentions + story responses once the user
            // lands on Activity, and re-fetch so newly arrived question
            // responses don't go missing when the tab is re-entered.
            guard newTab == .activity else { return }
            // Snapshot the unread cutoff BEFORE markAllRead advances it,
            // so blue dots stay visible while the user is still on the
            // screen instead of clearing in the same frame the tab opens.
            activityUnreadCutoff = activity.lastReadAt
            stickyUnreadMentionIDs = Set(mentionsSvc.mentions.filter { mentionsSvc.isUnread($0) }.map { $0.id })
            stickyUnreadResponseIDs = Set(responsesSvc.inbox.filter { $0.read_at == nil }.map { $0.id })
            // The keyed task above owns refresh and read receipts; a tab
            // change only captures the visual unread snapshot here.
        }
        .fullScreenCover(item: $liveAlertRoom) { room in
            WhisperLiveRoomView(room: room, isHost: false)
        }
    }

    private func refreshActivityFollowRequests() async {
        let generation = AccountStorage.generation
        await followRequestsSvc.refresh()
        guard !Task.isCancelled, generation == AccountStorage.generation else { return }
        await hydrateFollowRequestProfiles()
    }

    /// Bold ink section titles — Instagram's "Today / This week" grammar —
    /// replacing the faint uppercase kickers that fell into the page.
    private func activitySectionTitle(_ title: String, count: Int = 0, liveDot: Bool = false) -> some View {
        HStack(spacing: 8) {
            if liveDot {
                Circle()
                    .fill(Color(red: 0.95, green: 0.15, blue: 0.35))
                    .frame(width: 8, height: 8)
            }
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            if count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.heavy).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(WhisperTheme.accent, in: Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Live now (go-live alerts)

    /// "@host went live" rows — IG-style strip with a red Join pill. Only
    /// rooms still live make it here; tapping verifies before opening.
    private var liveNowSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            activitySectionTitle("Live now", liveDot: true)
            VStack(spacing: 0) {
                ForEach(Array(liveAlerts.enumerated()), id: \.element.id) { idx, alert in
                    liveAlertRow(alert)
                    if idx < liveAlerts.count - 1 {
                        Divider()
                            .background(WhisperTheme.hairline(colorScheme))
                            .padding(.leading, 64)
                    }
                }
            }
            .whisperActivityRows(colorScheme)
        }
    }

    private func liveAlertRow(_ alert: WhisperLiveModerationService.AlertRow) -> some View {
        Button {
            Haptics.tap()
            openLiveAlert(alert)
        } label: {
            HStack(spacing: 12) {
                WhisperAvatar(username: alert.host_username, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    (Text("@\(alert.host_username) ").font(.subheadline.weight(.bold))
                        + Text("went live").font(.subheadline))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(1)
                    if !alert.room_name.isEmpty {
                        Text(alert.room_name)
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    Circle().fill(.white).frame(width: 5, height: 5)
                    Text("Join")
                        .font(.caption.weight(.black))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(red: 0.95, green: 0.15, blue: 0.35), in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Verifies the room is still live before opening — a dead room simply
    /// drops its row instead of opening onto an "ended" screen.
    private func openLiveAlert(_ alert: WhisperLiveModerationService.AlertRow) {
        Task {
            if let fresh = try? await WhisperLiveRoomService.shared.fetchRoom(id: alert.room_id),
               fresh.is_live {
                liveAlertRoom = fresh
            } else {
                withAnimation(.whisperSnappy) {
                    liveAlerts.removeAll { $0.id == alert.id }
                }
            }
        }
    }

    // MARK: - Follow requests (private account)

    /// Pulls avatar/display-name profiles for every pending requester so
    /// the rows render real photos instead of initials.
    private func hydrateFollowRequestProfiles() async {
        let generation = AccountStorage.generation
        let ids = followRequestsSvc.incoming.map { $0.requester_id }
            .filter { followRequestProfiles[$0] == nil }
        guard !ids.isEmpty else { return }
        let map = await backend.fetchPublicProfiles(userIDs: ids)
        guard !Task.isCancelled, generation == AccountStorage.generation else { return }
        for (uid, profile) in map { followRequestProfiles[uid] = profile }
    }

    /// Instagram-style pending follow requests pinned to the top of the
    /// Activity tab — Confirm / Delete inline, so private-account owners
    /// never have to dig into Settings to act on them.
    private var followRequestsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            activitySectionTitle("Follow requests", count: followRequestsSvc.incoming.count)
            VStack(spacing: 0) {
                let rows = followRequestsSvc.incoming
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, req in
                    followRequestRow(req)
                    if idx < rows.count - 1 {
                        Divider()
                            .background(WhisperTheme.hairline(colorScheme))
                            .padding(.leading, 64)
                    }
                }
            }
            .whisperActivityRows(colorScheme)
        }
    }

    private func followRequestRow(_ req: WhisperFollowRequestRow) -> some View {
        let busy = followRequestWorking.contains(req.id)
        let profile = followRequestProfiles[req.requester_id]
        return HStack(spacing: 12) {
            WhisperAvatar(
                username: profile?.username ?? req.requester_username,
                size: 44,
                imageURL: profile?.profile_image_url.flatMap { URL(string: $0) }
            )
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(profile?.username ?? req.requester_username)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                Text("Wants to follow you")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer(minLength: 6)
            HStack(spacing: 6) {
                Button {
                    Haptics.success()
                    decideFollowRequest(req, approve: true)
                } label: {
                    Text("Confirm")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(WhisperTheme.ink(colorScheme), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(busy)

                Button {
                    Haptics.tap()
                    decideFollowRequest(req, approve: false)
                } label: {
                    Text("Delete")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(WhisperTheme.surface(colorScheme), in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
            .opacity(busy ? 0.5 : 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func decideFollowRequest(_ req: WhisperFollowRequestRow, approve: Bool) {
        followRequestWorking.insert(req.id)
        Task {
            if approve {
                _ = await followRequestsSvc.approve(req)
            } else {
                _ = await followRequestsSvc.deny(req)
            }
            await MainActor.run {
                followRequestWorking.remove(req.id)
                withAnimation(.whisperSnappy) {}
            }
        }
    }

    /// Story interactions inbox — poll votes, slider ratings, and question
    /// replies on the current user's stories. Sits above mentions so the
    /// freshest reactions to your latest story are the first thing you see.
    private var storyResponsesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            activitySectionTitle("Story responses", count: responsesSvc.unreadCount)
            VStack(spacing: 0) {
                let rows = Array(visibleStoryResponses.prefix(200))
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    storyResponseRow(row)
                    if idx < rows.count - 1 {
                        Divider()
                            .background(WhisperTheme.hairline(colorScheme))
                            .padding(.leading, 70)
                    }
                }
            }
            .whisperActivityRows(colorScheme)
        }
    }

    private func storyResponseRow(_ row: WhisperStoryResponseRow) -> some View {
        let (symbol, tint): (String, Color) = {
            switch row.kind {
            case "poll":     return ("chart.bar.doc.horizontal", Color(red: 0.36, green: 0.55, blue: 0.95))
            case "slider":   return ("slider.horizontal.below.rectangle", Color(red: 1.0, green: 0.55, blue: 0.18))
            case "like": return ("heart.fill", .pink)
            case "reaction": return ("face.smiling.fill", .orange)
            case "question": return ("questionmark.bubble.fill", Color(red: 0.62, green: 0.41, blue: 0.94))
            default: return ("bubble.left.fill", .secondary)
            }
        }()
        let actionCopy = row.actionDescription
        // Compare against the session cutoff snapshot so the blue dot
        // remains visible during this viewing even after `markAllRead`
        // stamps `read_at` on the server. Falls back to `read_at == nil`
        // when we don't yet have a cutoff (cold open).
        let isUnread = stickyUnreadResponseIDs.contains(row.id) || row.read_at == nil
        let timeAgo = WhisperPost.relativeTime(from: row.created_at ?? "")
        return HStack(spacing: 12) {
            Button {
                Haptics.tap()
                openProfile(row.responder_username)
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    WhisperAvatar(username: row.responder_username, size: 46)
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(tint, in: Circle())
                        .overlay {
                            Circle().strokeBorder(WhisperTheme.surface(colorScheme), lineWidth: 2)
                        }
                        .offset(x: 4, y: 4)
                }
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    Haptics.tap()
                    openProfile(row.responder_username)
                } label: {
                    Text("@\(row.responder_username)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
                .buttonStyle(.plain)
                (
                    Text(actionCopy + " ")
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    + Text("\u{201C}\(row.response)\u{201D}")
                        .fontWeight(.bold)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    + Text("  \(timeAgo)")
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                )
                .font(.subheadline)
                .lineLimit(3)
            }
            Spacer(minLength: 8)
            storyResponseThumb(row: row, tint: tint, symbol: symbol)
            if isUnread {
                Circle()
                    .fill(WhisperTheme.accent)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(.rect)
        // Tapping anywhere on a story-response row routes to the
        // referenced story (or the responses sheet for question stickers,
        // mirroring what swipe-up on your own story shows) so every row in
        // Activity actually leads somewhere.
        .onTapGesture {
            Haptics.tap()
            let story = stories.stories.first { $0.id == row.story_id }
            if row.kind == "question", let story {
                openResponsesFor = story
            } else if let story {
                openStory = story
            } else {
                openProfile(row.responder_username)
            }
        }
    }

    /// Inline preview of the story the response was sent to. Pulls the
    /// current user's matching story out of `WhisperStoryService.stories`
    /// by `story_id` and renders a 36×52 portrait thumb with the sticker
    /// glyph overlaid in the corner. Tapping it opens the story viewer so
    /// the author can immediately see which question/poll/slider drew the
    /// response. When the story has already expired (no longer cached),
    /// falls back to a tinted glyph tile so the row still reads cleanly.
    @ViewBuilder
    private func storyResponseThumb(row: WhisperStoryResponseRow, tint: Color, symbol: String) -> some View {
        let story = stories.stories.first { $0.id == row.story_id }
        Button {
            Haptics.tap()
            // IG-style: tapping the photo on a question response opens an
            // action sheet with "Message" + "Share response" instead of
            // jumping straight to the story viewer.
            // IG-style: tap a question response → open the same viewers /
            // responses sheet as swipe-up on your own story, so every
            // answer is visible in one place. Other sticker kinds still
            // jump straight to the story viewer.
            if row.kind == "question", let story {
                openResponsesFor = story
            } else if let story {
                openStory = story
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.15))
                    .frame(width: 36, height: 52)
                    .overlay {
                        if let urlString = story?.image_url, let url = URL(string: urlString) {
                            WhisperCachedAsyncImage(url: url) { phase in
                                if let img = phase.image {
                                    img.resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    Color.clear
                                }
                            }
                            .allowsHitTesting(false)
                        } else {
                            Image(systemName: symbol)
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundStyle(tint)
                        }
                    }
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
                    }
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(tint, in: Circle())
                    .overlay { Circle().strokeBorder(WhisperTheme.surface(colorScheme), lineWidth: 1.5) }
                    .offset(x: 4, y: 4)
            }
        }
        .buttonStyle(.plain)
        .disabled(story == nil && row.kind != "question")
        .opacity((story == nil && row.kind != "question") ? 0.55 : 1)
    }

    /// Mentions inbox — every `@you` reference from a post, comment, reel,
    /// or DM. Tapping a row routes to the correct surface; the unread
    /// badge clears as soon as Activity is opened.
    private var mentionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            activitySectionTitle("Tags & mentions", count: mentionsSvc.unreadCount)
            VStack(spacing: 0) {
                let rows = Array(mentionsSvc.mentions.prefix(20))
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    mentionRow(row)
                    if idx < rows.count - 1 {
                        Divider()
                            .background(WhisperTheme.hairline(colorScheme))
                            .padding(.leading, 70)
                    }
                }
            }
            .whisperActivityRows(colorScheme)
        }
    }

    private func mentionRow(_ row: WhisperMentionRow) -> some View {
        let kindCopy: String = {
            switch row.source_type {
            case "post":    return "tagged you in a post"
            case "comment": return "tagged you in a comment"
            case "reel":    return "tagged you in a reel"
            case "dm":      return "mentioned you in a message"
            default:        return "tagged you"
            }
        }()
        let timeAgo = WhisperPost.relativeTime(from: row.created_at)
        let isUnread = stickyUnreadMentionIDs.contains(row.id) || mentionsSvc.isUnread(row)
        let authorName: String = mentionAuthors[row.author_id] ?? ""
        let thumb: URL? = mentionThumbs[row.source_id] ?? nil
        let hasAuthor = !authorName.isEmpty
        return HStack(spacing: 12) {
            Button {
                Haptics.tap()
                if hasAuthor { openProfile(authorName) }
            } label: {
                if hasAuthor {
                    WhisperAvatar(username: authorName, size: 46)
                } else {
                    Circle()
                        .fill(WhisperTheme.accent.opacity(0.15))
                        .frame(width: 46, height: 46)
                        .overlay {
                            Image(systemName: "at")
                                .font(.system(size: 20, weight: .heavy))
                                .foregroundStyle(WhisperTheme.accent)
                        }
                }
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    if hasAuthor {
                        Button {
                            Haptics.tap()
                            openProfile(authorName)
                        } label: {
                            Text("@\(authorName)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                        }
                        .buttonStyle(.plain)
                        Text(" \(kindCopy)")
                            .font(.subheadline)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .lineLimit(2)
                    } else {
                        Text(kindCopy)
                            .font(.subheadline)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .lineLimit(2)
                    }
                }
                Text(timeAgo)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer(minLength: 8)
            if let thumb = thumb {
                Color(.secondarySystemBackground)
                    .frame(width: 48, height: 48)
                    .overlay {
                        WhisperCachedAsyncImage(url: thumb) { phase in
                            if case .success(let image) = phase {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Image(systemName: "photo")
                                    .font(.caption)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
                    }
            }
            if isUnread {
                Circle()
                    .fill(WhisperTheme.accent)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(.rect)
        .onTapGesture {
            Haptics.tap()
            handleMentionTap(row)
        }
        .task(id: row.id) {
            await hydrateMention(row)
        }
    }

    /// Lazily resolves the author username + post media thumb for a mention
    /// row so the inbox shows a real “@author tagged you in [thumb]” card.
    private func hydrateMention(_ row: WhisperMentionRow) async {
        if mentionAuthors[row.author_id] == nil {
            if let p = await backend.fetchPublicProfile(userID: row.author_id),
               let uname = p.username, !uname.isEmpty {
                mentionAuthors[row.author_id] = uname
            } else {
                mentionAuthors[row.author_id] = ""
            }
        }
        if (row.source_type == "post" || row.source_type == "reel"),
           mentionThumbs[row.source_id] == nil {
            if let post = await backend.fetchPost(postID: row.source_id),
               let first = (post.media_urls ?? []).first,
               let url = URL(string: first) {
                mentionThumbs[row.source_id] = url
            } else {
                mentionThumbs[row.source_id] = .some(nil)
            }
        }
    }

    /// Routes a tapped mention to the actual referenced piece of content —
    /// post/reel mentions open the post detail sheet, comment mentions
    /// resolve the comment's parent post and open that, DM mentions open
    /// the thread. Falls back to the author's profile only when we can't
    /// resolve the source (e.g. a deleted post).
    private func handleMentionTap(_ row: WhisperMentionRow) {
        // Mirror `handleActivityTap`: close the inbox sheet first so the
        // destination presents cleanly on top of the feed instead of
        // stacking behind the activity panel. DM mentions stay in-sheet
        // because the thread sheet is presented from the inbox itself.
        switch row.source_type {
        case "dm":
            Task {
                let generation = AccountStorage.generation
                let profile = await backend.fetchPublicProfile(userID: row.author_id)
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                let username = profile?.username ?? "user"
                openThread = WhisperConversationSummary(
                    otherUserID: row.author_id.lowercased(),
                    otherUsername: username,
                    lastMessage: "",
                    lastDate: Date(),
                    kind: .resolve(threadID: row.source_id, first: AccountStorage.currentUserID, second: row.author_id)
                )
            }
        case "post", "reel":
            dismiss()
            let pid = row.source_id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                NotificationCenter.default.post(
                    name: Notification.Name("WhisperOpenPostByID"),
                    object: nil,
                    userInfo: ["postID": pid]
                )
            }
        case "comment":
            Task {
                if let postID = await fetchCommentParentPostID(commentID: row.source_id),
                   !postID.isEmpty {
                    await MainActor.run { dismiss() }
                    try? await Task.sleep(for: .milliseconds(350))
                    NotificationCenter.default.post(
                        name: Notification.Name("WhisperOpenPostByID"),
                        object: nil,
                        userInfo: [
                            "postID": postID,
                            "commentID": row.source_id
                        ]
                    )
                } else {
                    let profile = await backend.fetchPublicProfile(userID: row.author_id)
                    if let username = profile?.username, !username.isEmpty {
                        await MainActor.run { openProfile(username) }
                    }
                }
            }
        default:
            Task {
                let profile = await backend.fetchPublicProfile(userID: row.author_id)
                if let username = profile?.username, !username.isEmpty {
                    await MainActor.run { openProfile(username) }
                }
            }
        }
    }

    /// Looks up `whisper_post_comments.post_id` for a given comment ID so
    /// mention rows whose source is a comment can route straight to the
    /// post that comment lives on.
    private func fetchCommentParentPostID(commentID: String) async -> String? {
        struct CommentParentRow: Decodable, Sendable { let post_id: String }
        do {
            let row: CommentParentRow = try await SupabaseService.shared.client
                .from("whisper_post_comments")
                .select("post_id")
                .eq("id", value: commentID)
                .limit(1)
                .single()
                .execute()
                .value
            return row.post_id
        } catch {
            return nil
        }
    }

    /// Real-data activity feed — likes/comments on my posts + new followers,
    /// bucketed into Today / This week / Earlier so the bell screen mirrors
    /// Instagram's grouping. Items newer than `activity.lastReadAt` carry a
    /// blue unread dot.
    @ViewBuilder private var activityFeedSection: some View {
        let cal = Calendar.current
        let now = Date()
        let today = activity.items.filter { cal.isDateInToday($0.createdAt) }
        let week = activity.items.filter {
            !cal.isDateInToday($0.createdAt) &&
            (cal.dateComponents([.day], from: $0.createdAt, to: now).day ?? 99) < 7
        }
        let earlier = activity.items.filter {
            (cal.dateComponents([.day], from: $0.createdAt, to: now).day ?? 0) >= 7
        }
        if activity.items.isEmpty {
            activityEmptyCard
        } else {
            if !today.isEmpty { activityRealSection(title: "Today", items: today) }
            if !week.isEmpty { activityRealSection(title: "This week", items: week) }
            if !earlier.isEmpty { activityRealSection(title: "Earlier", items: earlier) }
        }
    }

    private var activityEmptyCard: some View {
        VStack(spacing: 8) {
            WhisperMeetDoodle(symbol: "bell", height: 144)
            Text("No activity yet")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Likes, comments, and new followers will show up here.")
                .font(.footnote)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
    }

    private func activityRealSection(title: String, items: [WhisperActivityService.Item]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            activitySectionTitle(title)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    activityRealRow(item)
                    if idx < items.count - 1 {
                        Divider()
                            .background(WhisperTheme.hairline(colorScheme))
                            .padding(.leading, 70)
                    }
                }
            }
            .whisperActivityRows(colorScheme)
        }
    }

    private func activityRealRow(_ item: WhisperActivityService.Item) -> some View {
        let kind: WhisperNotification.Kind = {
            switch item.kind {
            case .like:    return .like
            case .comment: return .comment
            case .follow:  return .follow
            }
        }()
        let detail: String = {
            switch item.kind {
            case .like:    return "liked your post"
            case .comment:
                let body = WhisperContentPreview.text(item.commentBody, limit: 80)
                if body.isEmpty { return "commented on your post" }
                // Never leak wire tokens (shared cards / stickers) into the
                // notification line — show the friendly preview instead.
                if body.contains("::whisper-") || body.contains("-sticker://") {
                    let preview = Self.previewFor(body: body, fallback: "commented on your post").text
                    return "commented \u{00B7} \(preview)"
                }
                return "commented: \u{201C}\(body.prefix(80))\u{201D}"
            case .follow:  return "started following you"
            }
        }()
        let cutoff = activityUnreadCutoff ?? activity.lastReadAt
        let isUnread = item.createdAt > cutoff
        // Two-layer hit testing: a background Button handles taps on the
        // empty parts of the row (opens the post / follower profile), and
        // the avatar + @username Buttons in front absorb taps before they
        // reach the background. Replaces the previous outer `.onTapGesture`
        // which was occasionally swallowing the username Button so taps on
        // the handle routed to the post instead of the profile.
        return ZStack {
            Button {
                Haptics.tap()
                handleActivityTap(item)
            } label: {
                Color.clear.contentShape(.rect)
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                Button {
                    Haptics.tap()
                    openProfile(item.actorUsername)
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        WhisperAvatar(username: item.actorUsername, size: 46)
                        iconForKind(kind).offset(x: 4, y: 4)
                    }
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Button {
                        Haptics.tap()
                        openProfile(item.actorUsername)
                    } label: {
                        Text("@\(item.actorUsername)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(2)
                    Text(WhisperPost.relativeTime(from: item.createdAt))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                Spacer(minLength: 8)
                if isUnread {
                    Circle().fill(WhisperTheme.accent).frame(width: 8, height: 8)
                }
                // Instagram-style trailing thumbnail of the referenced
                // post for like/comment rows. Follow rows have no post,
                // so the slot is omitted entirely.
                if let urlString = item.postMediaURL, let url = URL(string: urlString) {
                    WhisperCachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            WhisperTheme.card(colorScheme)
                        }
                    }
                    .frame(width: 42, height: 42)
                    .clipShape(.rect(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
                    }
                    .allowsHitTesting(false)
                }
            }
            .allowsHitTesting(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// Routes to a username's profile via the global open-user notification.
    /// Dismisses the inbox sheet first so the profile sheet presents on
    /// top of the feed instead of stacking behind the activity panel —
    /// matches the behaviour of `handleActivityTap`.
    private func openProfile(_ username: String) {
        guard !username.isEmpty else { return }
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NotificationCenter.default.post(
                name: .whisperOpenUserByUsername,
                object: nil,
                userInfo: ["username": username]
            )
        }
    }

    /// Routes a tapped activity row to the right destination — like/comment
    /// rows open the post, follow rows open the new follower's profile.
    private func handleActivityTap(_ item: WhisperActivityService.Item) {
        // Close the activity sheet first so the destination (post detail or
        // profile) presents cleanly on top of the feed instead of stacking
        // behind the inbox. A short delay lets SwiftUI complete the dismiss
        // transition before the root view tries to present the next sheet.
        dismiss()
        let userInfo: [AnyHashable: Any]
        let name: Notification.Name
        switch item.kind {
        case .follow:
            name = .whisperOpenUserByUsername
            userInfo = ["username": item.actorUsername]
        case .like, .comment:
            guard let pid = item.postID else { return }
            name = Notification.Name("WhisperOpenPostByID")
            userInfo = ["postID": pid]
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
        }
    }

    private func iconForKind(_ kind: WhisperNotification.Kind) -> some View {
        let (symbol, tint): (String, Color) = {
            switch kind {
            case .like:    return ("heart.fill",          Color(red: 0.95, green: 0.32, blue: 0.45))
            case .comment: return ("bubble.right.fill",   Color(red: 0.36, green: 0.55, blue: 0.95))
            case .follow:  return ("person.fill.badge.plus", Color(red: 1.0, green: 0.55, blue: 0.18))
            case .friend:  return ("checkmark.seal.fill", Color(red: 0.2, green: 0.78, blue: 0.5))
            }
        }()
        return Image(systemName: symbol)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(tint, in: Circle())
            .overlay {
                Circle().strokeBorder(WhisperTheme.surface(colorScheme), lineWidth: 2)
            }
    }
}

// MARK: - Activity rows shell

private extension View {
    /// Activity rows sit directly on the surface between two hairlines —
    /// Instagram's grammar. The flat gray wells they used to sit in were
    /// only ~4% off the page colour and read as "everything blends".
    func whisperActivityRows(_ scheme: ColorScheme) -> some View {
        self
            .overlay(alignment: .top) {
                Rectangle().fill(WhisperTheme.hairline(scheme)).frame(height: 0.5)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(WhisperTheme.hairline(scheme)).frame(height: 0.5)
            }
    }
}

// MARK: - Story viewer

/// Full-screen story viewer. Renders the photo, auto-advances every 7s
/// through all stories from the same user, loops the attached music clip,
/// and re-draws interactive stickers on top of the photo.
///
/// Tap right third → next story (or dismiss after the last).
/// Tap left third → previous story (or restart current if it's the first).
/// Long-press anywhere → pause the auto-advance + music.
struct WhisperStoryViewer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    /// Story groups — one list per author, Instagram-style. Finishing an
    /// author's last story slides into the next author's stories.
    let groups: [[WhisperStoryRow]]
    var accessSuspended: Bool = false
    @State private var groupIndex: Int
    private var stories: [WhisperStoryRow] {
        groups.indices.contains(groupIndex) ? groups[groupIndex] : []
    }
    @State private var index: Int
    /// The segment clock is DATE MATH now — progress is derived from when
    /// the segment started plus whatever ran before a pause, and the bar
    /// reads it inside a TimelineView. No state write per frame (the whole
    /// viewer used to re-render 60× a second), so the timer runs butter-
    /// smooth and gestures never fight a render.
    @State private var segmentStart: Date = Date()
    @State private var elapsedBeforePause: Double = 0
    @State private var player = WhisperStoryMusicPlayer()
    @State private var storySoundEnabled = false
    @State private var paused: Bool = false
    /// The black band under the media card where the reply bar / seen-by
    /// live — the reference's layered bottom.
    private static let toolbarBand: CGFloat = 64
    /// Vertical drag offset for swipe-to-dismiss. Positive = dragging down,
    /// negative = swipe-up to reveal the viewer list (own stories only).
    @State private var dragOffset: CGFloat = 0
    /// Horizontal follow while the downward dismissal is engaged — the
    /// Instagram card tracks the finger on both axes on the way out.
    @State private var dragX: CGFloat = 0
    @State private var storyService = WhisperStoryService.shared
    @State private var viewService = WhisperStoryViewService.shared
    @State private var highlightsService = WhisperStoryHighlightsService.shared
    @State private var showViewers: Bool = false
    /// When non-nil, presents a sheet letting the viewer DM the story
    /// author with their response to a question / poll / slider sticker.
    @State private var responsePrompt: StoryResponsePrompt? = nil
    /// ID of the question sticker the viewer is currently typing on.
    /// When set, the same on-canvas question card swaps its placeholder
    /// for an inline TextField — no separate sheet, no re-created card.
    @State private var editingQuestionStickerID: String? = nil
    @State private var questionReplyText: String = ""
    @State private var sendingQuestionReply: Bool = false
    /// Flips to true briefly after a successful submit so the Send pill
    /// turns green + says “Sent” before the overlay tears down.
    @State private var questionReplySent: Bool = false
    @FocusState private var questionFieldFocused: Bool
    /// ID of the poll or slider sticker the viewer is currently
    /// interacting with. When set, that sticker is pulled into a lifted
    /// overlay over a blurred backdrop — same pattern as the question
    /// card — with a dedicated Send pill below that commits the choice
    /// and turns green “Sent” before tearing down.
    @State private var editingPollSliderStickerID: String? = nil
    @State private var pendingPollIndex: Int? = nil
    @State private var pendingSliderValue: Double? = nil
    @State private var sendingPollSlider: Bool = false
    @State private var pollSliderSent: Bool = false
    /// Vote counts per option for the poll currently being voted on —
    /// fetched right after a successful submit so the lifted card morphs
    /// into a percentage-bar results view before tearing down.
    @State private var pollResultsCounts: [Int]? = nil
    @State private var pollVotedIndex: Int? = nil
    @State private var presentReport: Bool = false
    @State private var confirmDeleteStory: Bool = false
    /// Quick-save-to-Highlights sheet — opened from the new bookmark button
    /// in the viewer chrome (owner only).
    @State private var showHighlightSave: Bool = false
    // Instagram reply bar — "Send message", the like heart, quick emoji
    // reactions, and the floating reaction burst.
    @State private var replyText: String = ""
    @FocusState private var replyFocused: Bool
    @State private var sendingReply: Bool = false
    @State private var storyShareTarget: WhisperStoryRow?
    @State private var storyMentionHandle: String?
    @State private var pendingStoryLink: String?
    @State private var storyLinkFailed: Bool = false
    @State private var viewerGeneration: UUID = AccountStorage.generation
    @State private var viewerClosed: Bool = false
    @State private var revealedFrameIDs: Set<String> = []
    @State private var readyPhotoCardIDs: Set<String> = []
    private var photoCardsPending: Bool {
        metadata.stickers.contains { $0.isPhotoCard && (!readyPhotoCardIDs.contains($0.id) || ($0.isRevealFrame && !revealedFrameIDs.contains($0.id))) }
    }
    private var canRevealFrames: Bool {
        !viewerClosed && !accessSuspended && viewerGeneration == AccountStorage.generation
            && storyScenePhase == .active && readyPlaybackKey == playbackKey && !paused
            && !replyFocused && !questionFieldFocused && editingQuestionStickerID == nil && editingPollSliderStickerID == nil
            && storyShareTarget == nil && storyMentionHandle == nil && pendingStoryLink == nil && presentWavePost == nil && presentSharedPost == nil
            && !showViewers && !presentReport && !showHighlightSave && !confirmDeleteStory && responsePrompt == nil
    }
    @State private var likedStoryIDs: Set<String> = []
    @State private var burstEmoji: String? = nil
    @State private var burstTick: Int = 0
    /// Round 77 — video stories run for the clip's real length (3–60s);
    /// photo stories keep Instagram's 7-second beat.
    @State private var videoDuration: Double = 15
    @State private var videoProgress: Double = 0
    @State private var readyPlaybackKey: String? = nil
    @State private var failedPlaybackKey: String? = nil
    @State private var replayID: UUID = UUID()
    @Environment(\.scenePhase) private var storyScenePhase
    private var playbackKey: String { "\(story.id)|\(story.video_url ?? story.image_url)|\(replayID)" }
    private var playbackPaused: Bool { photoCardsPending || paused || accessSuspended || pendingStoryLink != nil || !replyText.isEmpty || storyShareTarget != nil || storyMentionHandle != nil || viewerClosed || storyScenePhase != .active || readyPlaybackKey != playbackKey || failedPlaybackKey == playbackKey }
    /// A wave sticker tapped in someone's story — opens the original wave.
    @State private var presentWavePost: WhisperPost?
    /// A post sticker tapped in someone's story — opens the original post.
    @State private var presentSharedPost: WhisperStorySticker?
    private var duration: Double {
        story.isVideo ? max(3, min(60, videoDuration)) : (metadata.musicSelection?.durationSeconds ?? 7)
    }

    /// True when this viewer is playing back the current user's own stories
    /// — unlocks the bottom-left view counter and the swipe-up viewers
    /// list, matches Instagram/Snapchat parity.
    private var isMyStory: Bool {
        guard let first = stories.first else { return false }
        return first.user_id.lowercased() == AccountStorage.currentUserID.lowercased()
    }

    /// Backwards-compatible single-story init — still used by older call
    /// sites that don't have the full per-user list handy.
    init(story: WhisperStoryRow, accessSuspended: Bool = false) {
        self.accessSuspended = accessSuspended
        self.groups = [[story]]
        self._groupIndex = State(initialValue: 0)
        self._index = State(initialValue: 0)
    }

    init(stories: [WhisperStoryRow], startIndex: Int = 0) {
        self.groups = stories.isEmpty ? [] : [stories]
        self._groupIndex = State(initialValue: 0)
        // Clamp startIndex into [0, count-1]. Without the count>0 guard,
        // an empty story list would compute min(startIndex, -1) and crash
        // the viewer the instant it tried to read `stories[index]`.
        let clamped: Int
        if stories.isEmpty {
            clamped = 0
        } else {
            clamped = max(0, min(startIndex, stories.count - 1))
        }
        self._index = State(initialValue: clamped)
    }

    /// Instagram-style multi-author viewer — opens at `startGroup` and
    /// advances author to author until the last story dismisses.
    init(groups: [[WhisperStoryRow]], startGroup: Int, startIndex: Int = 0) {
        let safe = groups.filter { !$0.isEmpty }
        self.groups = safe
        let g = safe.isEmpty ? 0 : max(0, min(startGroup, safe.count - 1))
        self._groupIndex = State(initialValue: g)
        let count = safe.indices.contains(g) ? safe[g].count : 0
        self._index = State(initialValue: count == 0 ? 0 : max(0, min(startIndex, count - 1)))
    }

    /// Safe accessor — when the source list is empty (deleted last story
    /// mid-presentation) we hand back a placeholder row so SwiftUI doesn't
    /// crash before `.onChange` can dismiss the viewer.
    private var story: WhisperStoryRow {
        if stories.indices.contains(index) { return stories[index] }
        return WhisperStoryRow(
            id: "", user_id: "", username: "", image_url: "",
            caption: nil, metadata: nil,
            music_url: nil, music_title: nil, music_artist: nil, music_artwork: nil,
            created_at: nil, expires_at: nil, video_url: nil
        )
    }

    private var metadata: WhisperStoryMetadata {
        WhisperStoryMetadata.decode(story.metadata)
    }

    private var music: WhisperStoryMusic? {
        guard let preview = story.music_url, !preview.isEmpty,
              let title = story.music_title,
              let artist = story.music_artist else { return nil }
        return WhisperStoryMusic(
            id: story.id + "-music",
            title: title,
            artist: artist,
            artworkURL: story.music_artwork,
            previewURL: preview,
            startSeconds: metadata.musicSelection?.startSeconds ?? 0,
            durationSeconds: metadata.musicSelection?.durationSeconds
        )
    }

    var body: some View {
        GeometryReader { geo in
            // The story STAGE is the same 9:16 rect the editor composed on —
            // letterboxed on tall phones, exactly like Instagram — so every
            // sticker lands where its author put it on any device.
            // The media is a CARD above a bottom toolbar band (the reference's
            // layered look): the 9:16 stage fits the width, anchors to the
            // top, and the reply bar / seen-by live on the black band below.
            let mediaKey = playbackKey
            let stageArea = CGSize(width: geo.size.width, height: max(240, geo.size.height - Self.toolbarBand))
            let stage = WhisperStoryEditor.stageSize(in: stageArea)
            let stageOrigin = CGPoint(x: (geo.size.width - stage.width) / 2, y: 0)
            let stageCenter = CGPoint(x: stageOrigin.x + stage.width / 2, y: stageOrigin.y + stage.height / 2)
            ZStack {
                Color.black.ignoresSafeArea()
                if let clip = story.video_url, story.isVideo, let clipURL = URL(string: clip) {
                    WhisperStoryViewerVideo(
                        url: clipURL,
                        paused: (photoCardsPending && readyPlaybackKey == mediaKey) || paused || accessSuspended || pendingStoryLink != nil || !replyText.isEmpty || storyShareTarget != nil || storyMentionHandle != nil || viewerClosed || storyScenePhase != .active,
                        muted: !storySoundEnabled || music != nil,
                        onDuration: { d in if mediaKey == playbackKey, d > 0 { videoDuration = d } },
                        onProgress: { value in if mediaKey == playbackKey { videoProgress = value } },
                        onReady: { markMediaReady(key: mediaKey) },
                        onFailure: { if mediaKey == playbackKey { failedPlaybackKey = mediaKey } },
                        replayID: replayID
                    )
                    .frame(width: stage.width, height: stage.height)
                    .clipShape(.rect(cornerRadius: 16, style: .continuous))
                    .position(x: stageCenter.x, y: stageCenter.y)
                    .id(mediaKey)
                    .transition(.opacity)
                } else if let url = URL(string: story.image_url) {
                    WhisperCachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            Color.clear.overlay { img.resizable().aspectRatio(contentMode: .fill).allowsHitTesting(false) }
                                .onAppear { markMediaReady(key: mediaKey) }
                        case .failure:
                            Color.clear.onAppear {
                                if mediaKey == playbackKey { failedPlaybackKey = mediaKey }
                            }
                        default:
                            WhisperPhotoLoader()
                        }
                    }
                    .id(replayID)
                    .frame(width: stage.width, height: stage.height)
                    .clipShape(.rect(cornerRadius: 16, style: .continuous))
                    .position(x: stageCenter.x, y: stageCenter.y)
                    .id(mediaKey)
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                }
                // Tap zones — left third = back, right two-thirds = next.
                // Long-press on either side pauses the auto-advance.
                // Rendered BEFORE the sticker layer so interactive stickers
                // (polls, sliders, questions, mentions, location) sit on top
                // and receive their own taps instead of advancing the story.
                HStack(spacing: 0) {
                    tapZone(width: geo.size.width / 3) { goPrevious() }
                    tapZone(width: geo.size.width * 2 / 3) { goNext() }
                }
                .frame(maxHeight: .infinity)

                if failedPlaybackKey == mediaKey {
                    VStack(spacing: 12) {
                        Text("This story couldn't load.").font(.subheadline)
                        Button("Try again") { resetPlaybackAttempt() }
                            .frame(minWidth: 120, minHeight: 44)
                            .buttonStyle(.borderedProminent)
                    }
                    .foregroundStyle(.white)
                    .position(stageCenter)
                }

                // Blurred backdrop behind the editable question card so
                // the viewer's focus snaps to the card. Tapping the backdrop
                // commits the keyboard / cancels editing.
                if editingQuestionStickerID != nil || editingPollSliderStickerID != nil {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                        .overlay(Color.black.opacity(0.18).ignoresSafeArea())
                        .contentShape(.rect)
                        .onTapGesture {
                            if editingQuestionStickerID != nil { cancelQuestionEditing() }
                            if editingPollSliderStickerID != nil { cancelPollSliderEditing() }
                        }
                        .transition(.opacity)
                }

                // Interactive sticker layer — on top so polls/sliders/etc
                // capture taps before the underlying tap zones do. When a
                // question sticker is being typed on, that one sticker is
                // pulled into a separate overlay below so we can lift it
                // above the keyboard; the rest still render here.
                ZStack {
                    ForEach(metadata.stickers) { sticker in
                        stickerLayer(sticker: sticker, stage: stage, origin: .zero)
                    }
                }
                .frame(width: stage.width, height: stage.height)
                .clipShape(.rect(cornerRadius: 16))
                .position(stageCenter)

                liftedQuestionOverlay(geo: geo)
                liftedPollSliderOverlay(geo: geo)

                // Dim the stage while the reply field is focused — the
                // Instagram quick-reaction state. Tapping the dim dismisses.
                if replyFocused {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .contentShape(.rect)
                        .onTapGesture { replyFocused = false }
                        .transition(.opacity)
                }

                VStack {
                    // Multi-segment progress bar — one segment per story. Only
                    // THIS subtree redraws per frame (the clock is date math).
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: playbackPaused)) { ctx in
                        HStack(spacing: 4) {
                            ForEach(stories.indices, id: \.self) { i in
                                GeometryReader { barGeo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(.white.opacity(0.35))
                                        Capsule()
                                            .fill(.white)
                                            .frame(width: barGeo.size.width * segmentProgress(for: i, at: ctx.date))
                                    }
                                }
                                .frame(height: 2)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                    HStack(alignment: .center, spacing: 10) {
                        Button {
                            Haptics.tap()
                            openAuthorProfile()
                        } label: {
                            // Show the author's actual profile photo here —
                            // passing story.image_url shoved the story
                            // thumbnail into the 32pt header circle, which
                            // read as a tiny duplicate of the background.
                            // `WhisperAvatar` will resolve the real avatar
                            // from the username cache.
                            WhisperAvatar(username: story.username, size: 32)
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Button {
                                    Haptics.tap()
                                    openAuthorProfile()
                                } label: {
                                    Text(story.username)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                                .buttonStyle(.plain)
                                VerifiedBadge(
                                    badge: UserVerificationService.shared.badge(forUsername: story.username),
                                    size: 12,
                                    username: story.username,
                                    userID: story.user_id,
                                    maxChips: 0
                                )
                                // Instagram-style age right beside the name.
                                Text(whisperStoryTimeAgo(story.created_at))
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                                .lineLimit(1)
                            if let m = music {
                                // Instagram-parity music label — sits directly
                                // under the username in muted gray with a
                                // music glyph, and marquees the full "Title —
                                // Artist" line when it's wider than the
                                // available column.
                                StoryMusicMarquee(title: m.title, artist: m.artist)
                            }
                        }
                        Spacer()
                        if story.isVideo || music != nil {
                            Button { storySoundEnabled.toggle(); Haptics.tap() } label: {
                                Image(systemName: storySoundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                    .foregroundStyle(.white).frame(width: 44, height: 44)
                            }
                            .accessibilityLabel(storySoundEnabled ? "Mute story" : "Enable story sound")
                        }
                        if isMyStory {
                            Button {
                                Haptics.tap()
                                paused = true
                                showHighlightSave = true
                            } label: {
                                Image(systemName: isSavedToHighlight ? "bookmark.fill" : "bookmark")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .contentShape(.rect)
                                    .overlay(alignment: .topTrailing) {
                                        if highlightNudge {
                                            // Ember nudge — this story has real
                                            // reach but isn't saved anywhere yet.
                                            Circle()
                                                .fill(Color(red: 0.95, green: 0.56, blue: 0.34))
                                                .frame(width: 7, height: 7)
                                                .phaseAnimator([0.55, 1.0]) { view, s in
                                                    view.scaleEffect(s).opacity(s)
                                                } animation: { _ in
                                                    .easeInOut(duration: 0.8)
                                                }
                                                .offset(x: -4, y: 5)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isSavedToHighlight ? "Saved to Highlights" : "Save to Highlights")
                        }
                        Menu {
                            if isMyStory {
                                saveToHighlightMenu
                                Button(role: .destructive) {
                                    Haptics.warning()
                                    paused = true
                                    confirmDeleteStory = true
                                } label: {
                                    Label("Delete story", systemImage: "trash")
                                }
                            } else {
                                Button(role: .destructive) {
                                    Haptics.tap()
                                    paused = true
                                    presentReport = true
                                } label: {
                                    Label("Report", systemImage: "flag")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .contentShape(.rect)
                        }
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    Spacer()
                    if let caption = story.caption, !caption.isEmpty {
                        Text(caption)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(.black.opacity(0.45), in: .rect(cornerRadius: 14))
                            .padding(.bottom, 8)
                    }
                    storyBottomBar
                }
                .allowsHitTesting(true)
                .opacity(paused && !replyFocused ? 0 : 1)
                .animation(.easeOut(duration: 0.15), value: paused)

                // Floating emoji burst after a like / quick reaction.
                if let burstEmoji {
                    WhisperStoryReactionBurst(emoji: burstEmoji, trigger: burstTick)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 120)
                        .allowsHitTesting(false)
                }
            }
            .offset(x: dragX, y: dragOffset)
            // Clamp drag to non-negative values so the upward swipe-up
            // gesture (viewers sheet) doesn't scale the viewer ABOVE 1×
            // and crop the chrome on the way up.
            .scaleEffect(1 - min(max(dragOffset, 0), 320) / 1400)
            // Instagram's dismissal grammar — the card rounds its corners
            // as it shrinks away from the screen edges.
            .clipShape(.rect(cornerRadius: dragOffset > 0 ? min(dragOffset / 3, 44) : 0))
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { v in
                        dragOffset = v.translation.height
                        // The card follows the finger sideways too once the
                        // downward dismissal is engaged — Instagram's feel.
                        dragX = v.translation.height > 0 ? v.translation.width * 0.6 : 0
                        paused = true
                    }
                    .onEnded { v in
                        // Swipe up on my own story → open viewer list.
                        if isMyStory && v.translation.height < -80 {
                            withAnimation(.whisperSnappy) {
                                dragOffset = 0
                                dragX = 0
                            }
                            paused = true
                            showViewers = true
                            return
                        }
                        if v.translation.height > 120 || v.predictedEndTranslation.height > 240 {
                            player.stop()
                            dismiss()
                        } else {
                            withAnimation(.whisperSnappy) {
                                dragOffset = 0
                                dragX = 0
                            }
                            paused = false
                        }
                    }
            )
        }
        .background(Color.black.opacity(dragOffset > 0 ? max(0, 1 - Double(dragOffset) / 400) : 1).ignoresSafeArea())
        .fullScreenCover(item: $presentWavePost, onDismiss: { paused = false }) { post in
            WhisperReelsPlayerView(reels: [post], start: post)
        }
        .fullScreenCover(item: $presentSharedPost, onDismiss: { paused = false }) { sticker in
            WhisperReferencedPostView(postID: sticker.postID ?? "")
        }
        .confirmationDialog("Open website?", isPresented: Binding(get: { pendingStoryLink != nil }, set: { if !$0 { pendingStoryLink = nil } }), titleVisibility: .visible) {
            if let raw = pendingStoryLink, let url = WhisperStoryLinkSheet.validURL(raw) {
                Button("Open \(url.host ?? "website")") {
                    guard !accessSuspended, !viewerClosed, viewerGeneration == AccountStorage.generation else { return }
                    paused = true
                    pendingStoryLink = nil
                    Task { @MainActor in
                        // Let the confirmation dialog finish dismissing before
                        // presenting the browser over this full-screen viewer.
                        try? await Task.sleep(for: .milliseconds(350))
                        guard !Task.isCancelled, !accessSuspended, !viewerClosed,
                              viewerGeneration == AccountStorage.generation else { return }
                        if !WhisperInAppBrowser.isWebPage(url) {
                            UIApplication.shared.open(url) { success in
                                guard viewerGeneration == AccountStorage.generation, !viewerClosed else { return }
                                paused = replyFocused
                                if !success { storyLinkFailed = true }
                            }
                            return
                        }
                        let opened = WhisperInAppBrowser.shared.presentWebPage(url) {
                            guard viewerGeneration == AccountStorage.generation, !viewerClosed else { return }
                            paused = replyFocused
                        }
                        if !opened { paused = replyFocused; storyLinkFailed = true }
                    }
                }
            }
            Button("Cancel", role: .cancel) { pendingStoryLink = nil }
        } message: { Text(pendingStoryLink ?? "") }
        .alert("Couldn't open this website", isPresented: $storyLinkFailed) { Button("OK", role: .cancel) {} } message: { Text("Please try again later.") }
        .sheet(isPresented: Binding(get: { storyMentionHandle != nil }, set: { if !$0 { storyMentionHandle = nil } }), onDismiss: { paused = replyFocused }) {
            if let handle = storyMentionHandle { WhisperStoryMentionProfileView(handle: handle) }
        }
        .sheet(item: $storyShareTarget, onDismiss: { paused = replyFocused }) { sharedStory in
            if let body = WhisperSharedStoryEmbed.encode(storyID: sharedStory.id) {
                WhisperRecipientShareSheet(payload: body, sendingDisabledReason: accessSuspended ? "Story access is being checked or is no longer available." : nil) { EmptyView() }
            }
        }
        .onShake(isEnabled: canRevealFrames && metadata.stickers.contains { $0.isRevealFrame && !revealedFrameIDs.contains($0.id) }) {
            guard canRevealFrames else { return }
            revealedFrameIDs.formUnion(metadata.stickers.filter(\.isRevealFrame).map(\.id))
            Haptics.tap()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            revealedFrameIDs = []; readyPhotoCardIDs = []
            viewerClosed = true; paused = true; player.stop(); storyShareTarget = nil; storyMentionHandle = nil; pendingStoryLink = nil
            replyText = ""; questionReplyText = ""; dismiss()
        }
        .sheet(isPresented: $showViewers, onDismiss: { paused = false }) {
            WhisperStoryViewersSheet(story: story)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .whisperSheetBorder()
        }
        .sheet(isPresented: $presentReport, onDismiss: { paused = false }) {
            WhisperReportSheet(
                kind: .story,
                targetID: story.id,
                targetUserID: story.user_id,
                targetUsername: story.username
            )
        }
        .sheet(isPresented: $showHighlightSave, onDismiss: { paused = false }) {
            WhisperStoryHighlightQuickSave(story: story)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
                .whisperSheetBorder()
        }
        .alert("Delete this story?", isPresented: $confirmDeleteStory) {
            Button("Cancel", role: .cancel) { paused = false }
            Button("Delete", role: .destructive) {
                Haptics.warning()
                let storyID = story.id
                Task {
                    await storyService.deleteStory(id: storyID)
                    await MainActor.run { dismiss() }
                }
            }
        } message: {
            Text("This story will be permanently removed for everyone.")
        }
        .sheet(item: $responsePrompt, onDismiss: { paused = false }) { prompt in
            StoryResponseSheet(prompt: prompt, story: story)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
                .whisperSheetBorder()
        }
        .animation(.easeInOut(duration: 0.18), value: editingQuestionStickerID)
        .animation(.easeInOut(duration: 0.18), value: editingPollSliderStickerID)
        .task(id: groupIndex) {
            // Pull viewer counts for every story I'm about to flip through
            // so the counter is accurate on first paint (re-runs per author
            // group so crossing into my own stories still hydrates).
            if isMyStory {
                await viewService.loadViewersForMyStories(storyIDs: stories.map { $0.id })
                // Hydrate highlight albums so "Save to highlight" lists them.
                await highlightsService.refresh(forUserID: AccountStorage.currentUserID)
            }
        }
        .task(id: playbackKey) {
            // Reset the segment clock + music + reply state for each attempt.
            resetSegmentClock()
            videoProgress = 0
            videoDuration = 15
            replyFocused = false
            replyText = ""
            player.stop()
            if storySoundEnabled, !playbackPaused, let m = music { player.play(m) }
            // Mark this segment as seen locally (drops the unread ring) and
            // record a view receipt server-side when it's someone else's.
        }
        // Restart only the timer when admission changes, never the draft-owning initialization.
        .task(id: "\(playbackKey)|\(playbackPaused)") {
            guard !playbackPaused else { return }
            let key = playbackKey
            while !Task.isCancelled, key == playbackKey {
                if !playbackPaused, currentProgress(at: Date()) >= 1 {
                    goNext()
                    return
                }
                do { try await Task.sleep(for: .milliseconds(40)) }
                catch { return }
            }
        }
        .task(id: readyPlaybackKey) {
            guard readyPlaybackKey == playbackKey else { return }
            let viewedStory = story
            storyService.markSeen(storyIDs: [viewedStory.id])
            if !isMyStory { await viewService.recordView(story: viewedStory) }
        }
        .onChange(of: storySoundEnabled) { _, enabled in
            if enabled, !playbackPaused, let music { player.play(music) }
            else { player.pause() }
        }
        .onDisappear { player.stop() }
        // If every story for this user gets deleted while the viewer is
        // open (own-story delete from the menu), bail out instead of
        // sitting on a placeholder row.
        .onChange(of: stories.count) { _, newCount in
            if newCount == 0 { dismiss() }
        }
        // Typing a reply pauses the story, Instagram-style.
        .onChange(of: replyFocused) { _, focused in
            paused = focused
        }
        // The clock's bookkeeping: bank the running time on pause, restart
        // the running span on resume.
        .onChange(of: playbackPaused) { wasPaused, isPaused in
            if isPaused {
                player.pause()
                if !wasPaused { elapsedBeforePause += max(0, Date().timeIntervalSince(segmentStart)) }
            } else {
                segmentStart = Date()
                if storySoundEnabled, let music { player.play(music) }
            }
        }
    }

    /// "Save to highlight…" menu row — owner only. Opens the quick-save
    /// sheet (same one as the bookmark button), which lists every album AND
    /// creates new ones inline — no more dead-end when no albums exist.
    @ViewBuilder
    private var saveToHighlightMenu: some View {
        Button {
            Haptics.tap()
            paused = true
            showHighlightSave = true
        } label: {
            Label(
                isSavedToHighlight ? "Saved to Highlights" : "Save to highlight…",
                systemImage: isSavedToHighlight ? "bookmark.fill" : "bookmark"
            )
        }
    }

    /// True when this story's image already lives in ANY of my highlight
    /// albums — fills the bookmark and flips the menu label.
    private var isSavedToHighlight: Bool {
        highlightsService.isSaved(imageURL: story.image_url)
    }

    /// Jasper's gentle "this one popped" nudge — an ember dot on the
    /// bookmark when the story has real reach (5+ views) but isn't saved.
    private var highlightNudge: Bool {
        isMyStory && !isSavedToHighlight && (viewService.counts[story.id] ?? 0) >= 5
    }

    @ViewBuilder
    private func stickerLayer(sticker: WhisperStorySticker, stage: CGSize, origin: CGPoint) -> some View {
        let attempt = playbackKey
        let isLifted = (sticker.id == editingQuestionStickerID) || (sticker.id == editingPollSliderStickerID)
        if isLifted {
            Color.clear
        } else {
            WhisperStoryStickerView(
                sticker: sticker,
                stageWidth: metadata.referenceStageWidth.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? stage.width,
                isInteractive: true,
                frameRevealed: !sticker.isRevealFrame || revealedFrameIDs.contains(sticker.id),
                onPhotoCardReady: {
                    guard attempt == playbackKey, !viewerClosed, viewerGeneration == AccountStorage.generation else { return }
                    readyPhotoCardIDs.insert(sticker.id)
                },
                onVote: { idx in beginPollEditing(sticker: sticker, optionIndex: idx) },
                onSlider: { _ in /* commit deferred to Send pill */ },
                onBeginInteract: { beginSliderEditing(sticker: sticker) },
                onTap: { handleStickerTap(sticker) },
                authorUsername: story.username
            )
            .id(sticker.isPhotoCard ? "\(attempt)|\(sticker.id)" : sticker.id)
            .scaleEffect(sticker.scale * (metadata.referenceStageWidth.flatMap { $0.isFinite && $0 > 0 ? stage.width / $0 : nil } ?? 1))
            .rotationEffect(.radians(sticker.rotation))
            .position(x: origin.x + sticker.x * stage.width, y: origin.y + sticker.y * stage.height)
            .allowsHitTesting(isTappable(sticker.kind) || sticker.linkURL != nil || sticker.isPhotoCard)
        }
    }

    @ViewBuilder
    private func liftedQuestionOverlay(geo: GeometryProxy) -> some View {
        if let editingID = editingQuestionStickerID,
           let sticker = metadata.stickers.first(where: { $0.id == editingID }) {
            VStack {
                Spacer(minLength: 0)
                WhisperStoryStickerView(
                    sticker: sticker,
                    isInteractive: true,
                    editableQuestionText: $questionReplyText,
                    onSubmitQuestion: { submitQuestionReply(for: sticker) },
                    questionFieldFocused: $questionFieldFocused,
                    authorUsername: story.username
                )
                .scaleEffect(min(1.05, max(0.5, (geo.size.width - 48) / 280)))
                .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
                .padding(.bottom, 22)
                questionSendPill(for: sticker)
                    .padding(.bottom, 18)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    private func questionSendPill(for sticker: WhisperStorySticker) -> some View {
        let trimmedEmpty = questionReplyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button {
            Haptics.tap()
            submitQuestionReply(for: sticker)
        } label: {
            HStack(spacing: 8) {
                if sendingQuestionReply {
                    ProgressView().tint(.white)
                } else if questionReplySent {
                    Image(systemName: "checkmark").font(.footnote.weight(.heavy))
                }
                Text(questionReplySent ? "Sent" : (sendingQuestionReply ? "Sending…" : "Send"))
                    .font(.subheadline.weight(.heavy))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 26)
            .padding(.vertical, 11)
            .background(Capsule().fill(questionReplySent ? Color.green : Color.black))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .scaleEffect(questionReplySent ? 1.05 : 1)
            .animation(.whisperSnappy, value: questionReplySent)
        }
        .buttonStyle(.plain)
        .disabled(trimmedEmpty || sendingQuestionReply || questionReplySent)
        .opacity((trimmedEmpty && !questionReplySent && !sendingQuestionReply) ? 0.5 : 1)
    }

    @ViewBuilder
    private func liftedPollSliderOverlay(geo: GeometryProxy) -> some View {
        if let editingID = editingPollSliderStickerID,
           let sticker = metadata.stickers.first(where: { $0.id == editingID }) {
            VStack {
                Spacer(minLength: 0)
                liftedPollSliderCard(for: sticker)
                    .scaleEffect(min(1.05, max(0.5, (geo.size.width - 48) / 280)))
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
                    .padding(.bottom, 22)
                pollSliderSendPill(for: sticker)
                    .padding(.bottom, 32)
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    private func liftedPollSliderCard(for sticker: WhisperStorySticker) -> some View {
        let pollBinding: Binding<Int?>? = (sticker.kind == .poll && pollResultsCounts == nil)
            ? Binding(get: { pendingPollIndex }, set: { pendingPollIndex = $0 })
            : nil
        let sliderBinding: Binding<Double?>? = sticker.kind == .slider
            ? Binding(get: { pendingSliderValue }, set: { pendingSliderValue = $0 })
            : nil
        return WhisperStoryStickerView(
            sticker: sticker,
            isInteractive: true,
            pendingPollSelection: pollBinding,
            pendingSliderValue: sliderBinding,
            pollTally: sticker.kind == .poll ? pollResultsCounts : nil,
            votedIndex: pollVotedIndex,
            authorUsername: story.username
        )
    }

    private func pollSliderSendPill(for sticker: WhisperStorySticker) -> some View {
        let hasChoice = hasPendingPollSliderChoice(for: sticker)
        return Button {
            Haptics.tap()
            submitPollSliderReply(for: sticker)
        } label: {
            HStack(spacing: 8) {
                if sendingPollSlider {
                    ProgressView().tint(.white)
                } else if pollSliderSent {
                    Image(systemName: "checkmark").font(.footnote.weight(.heavy))
                }
                Text(pollSliderSent ? "Sent" : (sendingPollSlider ? "Sending…" : "Send"))
                    .font(.subheadline.weight(.heavy))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 26)
            .padding(.vertical, 11)
            .background(Capsule().fill(pollSliderSent ? Color.green : Color.black))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .scaleEffect(pollSliderSent ? 1.05 : 1)
            .animation(.whisperSnappy, value: pollSliderSent)
        }
        .buttonStyle(.plain)
        .disabled(!hasChoice || sendingPollSlider || pollSliderSent)
        .opacity((!hasChoice && !pollSliderSent && !sendingPollSlider) ? 0.5 : 1)
    }

    private func tapZone(width: CGFloat, onTap: @escaping () -> Void) -> some View {
        Color.clear
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .onTapGesture { onTap() }
            // `simultaneousGesture` so the long-press pause doesn't
            // swallow the tap-to-advance — previously a quick tap could
            // race the LongPressGesture and feel dead.
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.18)
                    .onChanged { _ in paused = true }
                    .onEnded { _ in paused = false }
            )
    }

    /// Where the current segment is, 0…1, at a given instant.
    private func currentProgress(at now: Date) -> Double {
        if story.isVideo { return videoProgress }
        let running: Double = playbackPaused ? 0 : max(0, now.timeIntervalSince(segmentStart))
        return min(1, (elapsedBeforePause + running) / max(duration, 0.1))
    }

    private func markMediaReady(key: String) {
        guard key == playbackKey, readyPlaybackKey != key else { return }
        segmentStart = Date()
        elapsedBeforePause = 0
        readyPlaybackKey = key
    }

    private func resetPlaybackAttempt() {
        revealedFrameIDs = []; readyPhotoCardIDs = []
        readyPlaybackKey = nil
        failedPlaybackKey = nil
        replayID = UUID()
        videoProgress = 0
        player.stop()
        resetSegmentClock()
    }

    private func resetSegmentClock() {
        segmentStart = Date()
        elapsedBeforePause = 0
    }

    private func segmentProgress(for i: Int, at now: Date) -> Double {
        if i < index { return 1 }
        if i == index { return currentProgress(at: now) }
        return 0
    }

    private func goNext() {
        Haptics.tap()
        resetPlaybackAttempt()
        if index + 1 < stories.count {
            index += 1
            resetSegmentClock()
        } else if groupIndex + 1 < groups.count {
            // Instagram parity — finishing an author's stories slides
            // into the next author's first story.
            withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) {
                groupIndex += 1
                index = 0
            }
            resetSegmentClock()
        } else {
            player.stop()
            dismiss()
        }
    }

    private func goPrevious() {
        Haptics.tap()
        if currentProgress(at: Date()) > 0.15 {
            // Restart media and progress together, not just the progress bar.
            resetPlaybackAttempt()
            return
        }
        resetPlaybackAttempt()
        if index > 0 {
            index -= 1
            resetSegmentClock()
        } else if groupIndex > 0 {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) {
                groupIndex -= 1
                index = 0
            }
            resetSegmentClock()
        } else {
            resetSegmentClock()
        }
    }

    /// Tapping the story author's avatar / username dismisses the viewer
    /// and routes to their profile. Mirrors Instagram's behavior: the
    /// story closes so the profile sheet can take focus.
    private func openAuthorProfile() {
        let handle = story.username
        player.stop()
        dismiss()
        // Defer the routing one runloop so the fullScreenCover finishes
        // dismissing before the profile sheet tries to present — SwiftUI
        // refuses to present a sheet while another cover is still active.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NotificationCenter.default.post(
                name: .whisperOpenUserByUsername,
                object: nil,
                userInfo: ["username": handle]
            )
        }
    }

    private func isTappable(_ kind: WhisperStorySticker.Kind) -> Bool {
        switch kind {
        case .poll, .slider, .question, .mention, .location, .wave, .post: return true
        default: return false
        }
    }

    private func handleStickerTap(_ sticker: WhisperStorySticker) {
        guard !accessSuspended, !viewerClosed, viewerGeneration == AccountStorage.generation else { return }
        if sticker.isRevealFrame {
            guard canRevealFrames else { return }
            revealedFrameIDs.insert(sticker.id); Haptics.tap(); return
        }
        if let raw = sticker.linkURL, WhisperStoryLinkSheet.validURL(raw) != nil { pendingStoryLink = raw; return }
        // Shared waves open for everyone — including the author reviewing
        // their own story.
        if sticker.kind == .wave {
            openSharedWave(sticker)
            return
        }
        if sticker.kind == .post {
            openSharedPost(sticker)
            return
        }
        guard !isMyStory else { return }
        paused = true
        switch sticker.kind {
        case .question:
            // Type directly on the actual on-canvas question card by
            // swapping it for an editable instance. No separate sheet,
            // no re-created card.
            questionReplyText = ""
            editingQuestionStickerID = sticker.id
            // Pop the keyboard once the overlay has had a chance to lay
            // out — a single tick is enough for SwiftUI to install the
            // focus binding before we flip it.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                questionFieldFocused = true
                try? await Task.sleep(for: .milliseconds(220))
                if !questionFieldFocused { questionFieldFocused = true }
            }
            return
        case .location:
            // Hand the place off to Apple Maps. Prefer the pinned lat/lon
            // captured when the author added the sticker — that way even
            // if they renamed the label ("the spot", "home", etc.) the
            // pin still drops on the exact coordinates. Fall back to a
            // text search by label if coordinates aren't present.
            let q = (sticker.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let encodedLabel = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let lat = sticker.latitude, let lon = sticker.longitude {
                let urlString = "https://maps.apple.com/?ll=\(lat),\(lon)&q=\(encodedLabel)"
                if let url = URL(string: urlString) {
                    UIApplication.shared.open(url)
                }
            } else if !q.isEmpty, let url = URL(string: "https://maps.apple.com/?q=\(encodedLabel)") {
                UIApplication.shared.open(url)
            }
            paused = false
            return
        case .mention:
            let handle = (sticker.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            guard !handle.isEmpty, handle.count <= 64, !accessSuspended, !viewerClosed,
                  viewerGeneration == AccountStorage.generation else { paused = false; return }
            replyFocused = false
            storyMentionHandle = handle
            paused = true
        default: break
        }
    }

    /// Instagram's "Watch reel" tap on a shared wave sticker — pauses the
    /// story and opens the original wave in the full player. Built straight
    /// from the sticker (cover · clip · author · caption) so it opens even
    /// when the post isn't in the local feed cache; likes/comments resolve
    /// against the real post id.
    private func openSharedWave(_ sticker: WhisperStorySticker) {
        Haptics.tap()
        paused = true
        var media: [URL] = []
        if let v = sticker.videoURL, let u = URL(string: v) { media.append(u) }
        if let i = sticker.imageURL, let u = URL(string: i) { media.append(u) }
        let cached = WhisperBackendService.shared.posts.first { $0.id.lowercased() == (sticker.postID ?? "").lowercased() }
        if let cached {
            presentWavePost = WhisperRootView.mapRowToPost(
                cached,
                fallbackUsername: WhisperBackendService.shared.postAuthorProfiles[cached.user_id]?.username
            )
            return
        }
        presentWavePost = WhisperPost(
            id: UUID(uuidString: sticker.postID ?? "") ?? UUID(),
            username: sticker.label ?? "",
            timeAgo: "",
            kind: .photo,
            caption: sticker.text ?? "",
            symbol: "play.rectangle.fill",
            accent: Color(red: 0.98, green: 0.22, blue: 0.33),
            mediaURLs: media,
            likes: 0,
            comments: 0,
            isReel: true
        )
    }

    /// A shared POST card tapped in a story — opens the original post (the
    /// cached row when the feed has it, else a light stand-in from the
    /// sticker's own fields).
    private func openSharedPost(_ sticker: WhisperStorySticker) {
        Haptics.tap()
        paused = true
        presentSharedPost = sticker
    }

    /// Cancel inline question editing without sending — used by tapping
    /// the dim backdrop. Resumes story playback.
    private func cancelQuestionEditing() {
        questionFieldFocused = false
        editingQuestionStickerID = nil
        questionReplyText = ""
        questionReplySent = false
        paused = false
    }

    /// Send the inline question reply to the story author's responses
    /// inbox and tear down the editing overlay.
    private func submitQuestionReply(for sticker: WhisperStorySticker) {
        let body = questionReplyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !sendingQuestionReply else { return }
        sendingQuestionReply = true
        let prompt = sticker.text ?? "Ask me anything"
        let target = story
        Task {
            await WhisperStoryResponseService.shared.record(
                story: target,
                kind: "question",
                prompt: prompt,
                response: body
            )
            await MainActor.run {
                sendingQuestionReply = false
                questionFieldFocused = false
                withAnimation(.whisperSnappy) {
                    questionReplySent = true
                }
                Haptics.success()
            }
            try? await Task.sleep(for: .milliseconds(900))
            await MainActor.run {
                editingQuestionStickerID = nil
                questionReplyText = ""
                questionReplySent = false
                paused = false
            }
        }
    }

    /// Tapping a poll option enters the lifted/blurred editing state
    /// with that option pre-selected. The viewer can change their pick
    /// freely; nothing is committed until the Send pill is tapped.
    private func beginPollEditing(sticker: WhisperStorySticker, optionIndex: Int) {
        guard !isMyStory else { return }
        paused = true
        pendingPollIndex = optionIndex
        pendingSliderValue = nil
        editingPollSliderStickerID = sticker.id
    }

    /// First drag on a slider lifts the sticker into editing mode.
    /// Subsequent drags update `pendingSliderValue` through the binding.
    private func beginSliderEditing(sticker: WhisperStorySticker) {
        guard !isMyStory, sticker.kind == .slider else { return }
        paused = true
        if editingPollSliderStickerID != sticker.id {
            pendingSliderValue = 0.5
            pendingPollIndex = nil
            editingPollSliderStickerID = sticker.id
        }
    }

    private func hasPendingPollSliderChoice(for sticker: WhisperStorySticker) -> Bool {
        switch sticker.kind {
        case .poll: return pendingPollIndex != nil
        case .slider: return pendingSliderValue != nil
        default: return false
        }
    }

    private func cancelPollSliderEditing() {
        editingPollSliderStickerID = nil
        pendingPollIndex = nil
        pendingSliderValue = nil
        pollSliderSent = false
        pollResultsCounts = nil
        pollVotedIndex = nil
        paused = false
    }

    /// Commit the staged poll/slider response, flash the green "Sent"
    /// pill, then tear down the lifted overlay.
    private func submitPollSliderReply(for sticker: WhisperStorySticker) {
        guard !sendingPollSlider, !pollSliderSent else { return }
        let target = story
        switch sticker.kind {
        case .poll:
            guard let idx = pendingPollIndex else { return }
            let options = sticker.pollOptions ?? ["Yes", "No"]
            guard idx < options.count else { return }
            sendingPollSlider = true
            let prompt = sticker.text ?? "Poll"
            let answer = options[idx]
            Task {
                await WhisperStoryResponseService.shared.record(
                    story: target, kind: "poll", prompt: prompt, response: answer
                )
                // Pull live counts so the card morphs into a % bar
                // results view before tearing down.
                let map = await WhisperStoryResponseService.shared.fetchPollTally(
                    storyID: target.id, prompt: prompt
                )
                await MainActor.run {
                    // Ensure the voter's own pick is reflected even if the
                    // RPC count hasn't caught up yet (eventual consistency).
                    var merged = map
                    if (merged[answer] ?? 0) < 1 { merged[answer] = 1 }
                    let counts = options.map { merged[$0] ?? 0 }
                    pollResultsCounts = counts
                    pollVotedIndex = idx
                }
                await finishPollSliderSubmit(isPoll: true)
            }
        case .slider:
            guard let v = pendingSliderValue else { return }
            sendingPollSlider = true
            let pct = Int(round(v * 100))
            let prompt = sticker.text ?? "Slide to rate"
            Task {
                await WhisperStoryResponseService.shared.record(
                    story: target, kind: "slider", prompt: prompt, response: "\(pct)%"
                )
                await finishPollSliderSubmit(isPoll: false)
            }
        default: return
        }
    }

    @MainActor
    private func finishPollSliderSubmit(isPoll: Bool) async {
        sendingPollSlider = false
        withAnimation(.whisperSnappy) {
            pollSliderSent = true
        }
        Haptics.success()
        // Polls morph into a percentage-bar results card — hold it a bit
        // longer so the viewer can read the % split before we dismiss.
        let hold: Int = isPoll ? 2400 : 900
        try? await Task.sleep(for: .milliseconds(hold))
        editingPollSliderStickerID = nil
        pendingPollIndex = nil
        pendingSliderValue = nil
        pollSliderSent = false
        pollResultsCounts = nil
        pollVotedIndex = nil
        paused = false
    }

    /// Instagram bottom chrome — the "Seen by" facepile on my own
    /// stories, the reply bar (+ quick reactions while typing) on
    /// everyone else's.
    @ViewBuilder
    private var storyBottomBar: some View {
        if isMyStory {
            viewCountBar
        } else {
            VStack(spacing: 16) {
                if replyFocused {
                    WhisperStoryQuickReactionsGrid { emoji in
                        sendQuickReaction(emoji)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                WhisperStoryReplyBar(
                    text: $replyText,
                    focused: $replyFocused,
                    liked: likedStoryIDs.contains(story.id),
                    sending: sendingReply,
                    onShare: { openStorySharing() },
                    onSend: { sendReply() },
                    onLike: { toggleLike() }
                )
            }
            .padding(.bottom, 14)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: replyFocused)
        }
    }

    private func openStorySharing() {
        guard !viewerClosed, !accessSuspended, !sendingReply, viewerGeneration == AccountStorage.generation,
              WhisperSharedStoryEmbed.encode(storyID: story.id) != nil else { return }
        Haptics.tap(); storyShareTarget = story; replyFocused = false; paused = true
    }

    /// DM the typed reply to the story author — lands in the normal
    /// message thread with story context, Instagram-style.
    private func sendReply() {
        let body = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !sendingReply else { return }
        sendingReply = true
        let target = story
        Task {
            _ = await WhisperBackendService.shared.sendMessage(
                toUserID: target.user_id,
                toUsername: target.username,
                body: "Replied to your story: \(body)"
            )
            await MainActor.run {
                sendingReply = false
                replyText = ""
                replyFocused = false
                Haptics.success()
                showBurst("💬")
            }
        }
    }

    /// One-tap quick reaction — fires the emoji as a DM, records it in
    /// the author's story-responses inbox, and plays the burst.
    private func sendQuickReaction(_ emoji: String) {
        let target = story
        replyFocused = false
        showBurst(emoji)
        Task {
            _ = await WhisperBackendService.shared.sendMessage(
                toUserID: target.user_id,
                toUsername: target.username,
                body: "\(emoji) Reacted to your story"
            )
            await WhisperStoryResponseService.shared.record(
                story: target, kind: "reaction", prompt: "Story reaction", response: emoji
            )
        }
    }

    /// Instagram's silent story like — fills the heart and lands in the
    /// author's story-responses inbox without a DM.
    private func toggleLike() {
        let target = story
        if likedStoryIDs.contains(target.id) {
            likedStoryIDs.remove(target.id)
            return
        }
        likedStoryIDs.insert(target.id)
        showBurst("❤️")
        Task {
            await WhisperStoryResponseService.shared.record(
                story: target, kind: "like", prompt: "Story like", response: "❤️"
            )
        }
    }

    private func showBurst(_ emoji: String) {
        burstEmoji = emoji
        burstTick &+= 1
        let tickAtFire = burstTick
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1400))
            if burstTick == tickAtFire { burstEmoji = nil }
        }
    }

    /// Bottom-left "Seen by N" facepile shown only on my own stories.
    /// Tapping it (or swiping up) opens the full viewer list sheet.
    private var viewCountBar: some View {
        let viewers = viewService.viewersByStory[story.id] ?? []
        let count = max(viewService.counts[story.id] ?? 0, viewers.count)
        return HStack {
            WhisperStorySeenByFacepile(viewers: viewers, count: count) {
                paused = true
                showViewers = true
            }
            Spacer()
            Button { openStorySharing() } label: {
                WhisperRoundedGlyph(kind: .share).foregroundStyle(.white).frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel("Send Story in a message")
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 24)
    }
}

// MARK: - Story response sheet

/// Identifies which kind of response sheet the viewer wants to present
/// after tapping an interactive sticker (question, @mention pill, location
/// pill). Carries the prompt text and a placeholder for the input field.
nonisolated struct StoryResponsePrompt: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case question, message }
    let id = UUID()
    let kind: Kind
    let title: String
    let placeholder: String
}

/// Compact glass sheet that lets a viewer reply to an interactive sticker
/// on someone else's story. The reply is delivered as a DM to the story
/// author, prefixed with the original prompt so context isn't lost.
struct StoryResponseSheet: View {
    let prompt: StoryResponsePrompt
    let story: WhisperStoryRow
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var sending: Bool = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if prompt.kind == .question {
                questionBody
            } else {
                messageBody
            }
        }
        .task {
            // Sheets animate in over ~0.3s; waiting for the presentation
            // animation to finish before focusing makes the keyboard land
            // reliably on question / mention / location response prompts.
            try? await Task.sleep(for: .milliseconds(500))
            focused = true
            // Belt-and-braces: a second pass after another tick covers
            // edge cases where the first focus attempt was eaten by a
            // late sheet layout pass.
            try? await Task.sleep(for: .milliseconds(250))
            if !focused { focused = true }
        }
    }

    /// Inline question response that mirrors the on-canvas "ask me anything"
    /// bubble — the viewer types their answer directly inside the same
    /// white card the author drew, instead of a separate dark sheet.
    private var questionBody: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(.rect)
                .onTapGesture { dismiss() }

            VStack(spacing: 14) {
                VStack(spacing: 10) {
                    Text("ask me anything")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.lowercase)
                    Text(prompt.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.black)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    TextField(
                        "",
                        text: $text,
                        prompt: Text("Type your answer\u{2026}").foregroundStyle(.gray),
                        axis: .vertical
                    )
                    .focused($focused)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .tint(.black)
                    .multilineTextAlignment(.center)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.05), in: .rect(cornerRadius: 12))
                }
                .padding(.top, 22 + 32)
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity)
                .background(.white, in: .rect(cornerRadius: 22))
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                .overlay(alignment: .top) {
                    WhisperAvatar(username: story.username, size: 56, ring: false)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                        .offset(y: -28)
                }
                .padding(.horizontal, 24)

                Button { send() } label: {
                    let note = WhisperThoughtService.shared.activeThought(forUserID: story.user_id)
                    let noteStyle = WhisperThoughtStyle(rawValue: note?.style ?? "") ?? .plain
                    let noteHex = note?.color_hex ?? ""
                    HStack(spacing: 8) {
                        if sending { ProgressView().tint(WhisperThoughtBubble.bubbleTextColor(colorHex: noteHex, style: noteStyle)) }
                        Text(sending ? "Sending\u{2026}" : "Reply to @\(story.username)")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(WhisperThoughtBubble.bubbleTextColor(colorHex: noteHex, style: noteStyle))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(WhisperThoughtBubble.bubbleGradient(colorHex: noteHex, style: noteStyle), in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.45), Color.white.opacity(0.05), Color.black.opacity(0.18)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.8
                        )
                    )
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                .opacity((text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending) ? 0.5 : 1)
                .padding(.horizontal, 40)
                .padding(.bottom, 28)
            }
        }
    }

    /// Mention / location reply UI — unchanged dark sheet.
    private var messageBody: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(.white.opacity(0.25))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
            VStack(spacing: 4) {
                Text("Message")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(prompt.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.horizontal, 24)
            TextField("", text: $text, prompt: Text(prompt.placeholder).foregroundStyle(.white.opacity(0.4)), axis: .vertical)
                .focused($focused)
                .font(.body)
                .foregroundStyle(.white)
                .tint(.white)
                .lineLimit(1...3)
                .padding(14)
                .background(Color.white.opacity(0.08), in: .rect(cornerRadius: 14))
                .padding(.horizontal, 16)
            Button { send() } label: {
                HStack(spacing: 8) {
                    if sending { ProgressView().tint(.black) }
                    Text(sending ? "Sending\u{2026}" : "Send to @\(story.username)")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
            .opacity((text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending) ? 0.5 : 1)
            .padding(.horizontal, 16)
            Spacer(minLength: 0)
        }
        .environment(\.colorScheme, .dark)
    }

    private func send() {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        sending = true
        Task {
            switch prompt.kind {
            case .question:
                // Land in the Story Responses inbox in Activity.
                await WhisperStoryResponseService.shared.record(
                    story: story,
                    kind: "question",
                    prompt: prompt.title,
                    response: body
                )
            case .message:
                // @mention / location pills still DM the author.
                _ = await WhisperBackendService.shared.sendMessage(
                    toUserID: story.user_id,
                    toUsername: story.username,
                    body: body
                )
            }
            await MainActor.run {
                sending = false
                dismiss()
            }
        }
    }
}

/// Bottom sheet listing every user who's watched the given story. Loaded
/// from `whisper_story_views`; only shown to the story owner.
struct WhisperStoryViewersSheet: View {
    let story: WhisperStoryRow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewService = WhisperStoryViewService.shared
    @State private var responsesSvc = WhisperStoryResponseService.shared
    @State private var loading: Bool = true
    @State private var answerShare: ResponseSharePayload?
    @State private var replyTarget: ReplyTarget?

    /// Routed into the story composer when the owner taps a response card.
    /// The composer opens the real camera so the author can shoot a fresh
    /// background — the question card + answer pill ride along as
    /// pre-loaded stickers.
    struct ResponseSharePayload: Identifiable {
        let id = UUID()
        let question: String
        let answer: String
        let responderUsername: String
    }

    /// DM compose target for the Reply pill on a response card.
    struct ReplyTarget: Identifiable {
        let id = UUID()
        let userID: String
        let username: String
        let question: String
        let answer: String
    }

    private var viewers: [WhisperStoryViewRow] {
        viewService.viewersByStory[story.id] ?? []
    }

    /// Responses to this specific story (question/poll/slider). Used for
    /// the IG-style "Tap a response to share it in your story" strip.
    private var responses: [WhisperStoryResponseRow] {
        responsesSvc.inbox.filter { $0.story_id == story.id }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                if loading && viewers.isEmpty && responses.isEmpty {
                    ProgressView().tint(WhisperTheme.ink(colorScheme))
                } else if viewers.isEmpty && responses.isEmpty {
                    VStack(spacing: 8) {
                        WhisperMeetDoodle(symbol: "eye", height: 144)
                        Text("No views yet")
                            .font(.headline)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        Text("You'll see who's watched this story here.")
                            .font(.footnote)
                            .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if !responses.isEmpty {
                                responsesSection
                            }
                            if !viewers.isEmpty {
                                Text("Who viewed this story")
                                    .font(.headline.weight(.heavy))
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                                    .padding(.horizontal, 16)
                                    .padding(.top, responses.isEmpty ? 8 : 18)
                                    .padding(.bottom, 6)
                                ForEach(viewers, id: \.viewer_id) { v in
                                    viewerRow(v)
                                    Divider().background(WhisperTheme.hairline(colorScheme))
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .navigationTitle("\(viewers.count) \(viewers.count == 1 ? "view" : "views")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
        .task {
            await viewService.loadViewersForMyStories(storyIDs: [story.id])
            await responsesSvc.fetch()
            loading = false
        }
        .fullScreenCover(item: $answerShare) { payload in
            WhisperStoryComposerView(
                initialStickers: WhisperInboxView.answerStickers(
                    question: payload.question,
                    answer: payload.answer,
                    responderUsername: payload.responderUsername
                )
            )
        }
        .sheet(item: $replyTarget) { target in
            StoryResponseReplySheet(target: target)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .whisperSheetBorder()
        }
    }

    /// IG-style response list — mirrors the notification row layout exactly
    /// (avatar + inline “@user responded with \"X\" · time” + story thumb),
    /// so swipe-up on your own story shows the same row style users already
    /// recognize from the activity inbox. Tapping a question row shares the
    /// answer to your story; the Reply chevron opens a DM composer.
    @ViewBuilder
    private var responsesSection: some View {
        let questionResponses = responses.filter { $0.kind == "question" }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Responses")
                    .font(.footnote.weight(.heavy))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .textCase(.uppercase)
                Text("\(responses.count)")
                    .font(.caption2.weight(.heavy).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(WhisperTheme.accent, in: Capsule())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            if !questionResponses.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill")
                        .font(.caption.weight(.heavy))
                    Text("Tap a question response to share it in your story")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
                }
                .padding(.horizontal, 16)
            }
            VStack(spacing: 0) {
                ForEach(Array(responses.enumerated()), id: \.element.id) { idx, row in
                    responseInlineRow(row)
                    if idx < responses.count - 1 {
                        Divider()
                            .background(WhisperTheme.hairline(colorScheme))
                            .padding(.leading, 70)
                    }
                }
            }
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
            }
            .padding(.horizontal, 16)
        }
    }

    /// Notification-parity row: avatar (with kind glyph badge), inline
    /// “responded with \"X\" · 9s”, trailing Reply chevron. The whole row is
    /// tappable when the response is a question (taps share to story);
    /// poll/slider rows are read-only but the Reply chevron always works.
    private func responseInlineRow(_ row: WhisperStoryResponseRow) -> some View {
        let canShare = row.kind == "question"
        let (symbol, tint): (String, Color) = {
            switch row.kind {
            case "poll":   return ("chart.bar.doc.horizontal", Color(red: 0.36, green: 0.55, blue: 0.95))
            case "slider": return ("slider.horizontal.below.rectangle", Color(red: 1.0, green: 0.55, blue: 0.18))
            default:       return ("questionmark.bubble.fill", Color(red: 0.62, green: 0.41, blue: 0.94))
            }
        }()
        let actionCopy: String = {
            switch row.kind {
            case "poll":   return "voted on your poll"
            case "slider": return "rated your slider"
            default:       return "responded with"
            }
        }()
        let timeAgo = WhisperPost.relativeTime(from: row.created_at ?? "")
        return Button {
            guard canShare else { return }
            Haptics.tap()
            answerShare = ResponseSharePayload(
                question: row.prompt,
                answer: row.response,
                responderUsername: row.responder_username
            )
        } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    WhisperAvatar(username: row.responder_username, size: 46)
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(tint, in: Circle())
                        .overlay {
                            Circle().strokeBorder(WhisperTheme.card(colorScheme), lineWidth: 2)
                        }
                        .offset(x: 4, y: 4)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("@\(row.responder_username)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    (
                        Text(actionCopy + " ")
                            .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.9))
                        + Text("\u{201C}\(row.response)\u{201D}")
                            .fontWeight(.bold)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        + Text("  \(timeAgo)")
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    )
                    .font(.subheadline)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Button {
                    Haptics.tap()
                    replyTarget = ReplyTarget(
                        userID: row.responder_id,
                        username: row.responder_username,
                        question: row.prompt,
                        answer: row.response
                    )
                } label: {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.footnote.weight(.heavy))
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .frame(width: 34, height: 34)
                        .background(WhisperTheme.ink(colorScheme), in: Circle())
                }
                .buttonStyle(.plain)
                if row.read_at == nil {
                    Circle()
                        .fill(WhisperTheme.accent)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!canShare)
    }

    private func viewerRow(_ v: WhisperStoryViewRow) -> some View {
        HStack(spacing: 12) {
            WhisperAvatar(username: v.viewer_username, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(v.viewer_username)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                if let ts = v.created_at {
                    Text(relativeLabel(from: ts))
                        .font(.caption2)
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.55))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func relativeLabel(from iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) ?? Date()
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .abbreviated
        return rel.localizedString(for: date, relativeTo: Date())
    }
}

/// Lightweight DM compose sheet for replying to a story-question responder
/// straight from the viewers sheet. Sends via WhisperBackendService so the
/// thread shows up in the responder's inbox immediately.
private struct StoryResponseReplySheet: View {
    let target: WhisperStoryViewersSheet.ReplyTarget
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var text: String = ""
    @State private var sending: Bool = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Reply to @\(target.username)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("Their answer to \u{201C}\(target.question)\u{201D}:")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                Text(target.answer)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TextField(
                "",
                text: $text,
                prompt: Text("Send a message\u{2026}").foregroundStyle(WhisperTheme.muted(colorScheme)),
                axis: .vertical
            )
            .focused($focused)
            .font(.body)
            .foregroundStyle(WhisperTheme.ink(colorScheme))
            .tint(WhisperTheme.accent)
            .lineLimit(1...4)
            .padding(12)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
            }
            Button { send() } label: {
                HStack(spacing: 8) {
                    if sending {
                        ProgressView().tint(WhisperTheme.surface(colorScheme))
                    }
                    Text(sending ? "Sending\u{2026}" : "Send")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(WhisperTheme.surface(colorScheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(WhisperTheme.ink(colorScheme), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
            .opacity((text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending) ? 0.5 : 1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WhisperTheme.surface(colorScheme).ignoresSafeArea())
        .onAppear { focused = true }
    }

    private func send() {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        sending = true
        Task {
            _ = await WhisperBackendService.shared.sendMessage(
                toUserID: target.userID,
                toUsername: target.username,
                body: body
            )
            await MainActor.run {
                sending = false
                dismiss()
            }
        }
    }
}

/// Instagram-style new-message sheet: search bar on top, then "Suggested"
/// (people you follow) and "Friends" sections beneath. Tapping any row opens
/// a DM thread with that user.
struct WhisperNewMessageSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var requests = FriendRequestsService.shared
    @State private var follows = WhisperFollowService.shared
    @State private var users = WhisperUserService.shared
    @State private var query: String = ""
    @State private var suggested: [WhisperUserRow] = []
    @State private var searchResults: [WhisperUserRow] = []
    @State private var isSearching: Bool = false

    /// Callback receives (userID, username) so callers can open a thread
    /// regardless of whether the user came from friendships or follows.
    let onSelect: (String, String) -> Void

    private struct Suggestion: Identifiable, Hashable {
        let userID: String
        let username: String
        let imageURL: String?
        let source: Source
        var displayName: String? = nil
        enum Source: String { case friend = "Friend", following = "Following", search = "Whisper user" }
        var id: String { userID }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Following + friends, deduped, optionally filtered by `query`.
    private var localSuggestions: [Suggestion] {
        var seen = Set<String>()
        var out: [Suggestion] = []
        for f in requests.friendships {
            guard seen.insert(f.friend_user_id).inserted else { continue }
            out.append(.init(userID: f.friend_user_id, username: f.friend_username, imageURL: nil, source: .friend))
        }
        for u in suggested {
            guard seen.insert(u.user_id).inserted else { continue }
            out.append(.init(userID: u.user_id, username: u.username, imageURL: u.profile_image_url, source: .following, displayName: u.display_name))
        }
        let q = trimmedQuery.lowercased()
        guard !q.isEmpty else { return out }
        return out.filter { WhisperUserSearch.matches(q, username: $0.username, displayName: $0.displayName) }
    }

    /// Whisper-wide search results, excluding anyone already in the local list.
    private var remoteSuggestions: [Suggestion] {
        let localIDs = Set(localSuggestions.map { $0.userID })
        return searchResults
            .filter { !localIDs.contains($0.user_id) }
            .map { Suggestion(userID: $0.user_id, username: $0.username, imageURL: $0.profile_image_url, source: .search, displayName: $0.display_name) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        searchField
                        if localSuggestions.isEmpty && remoteSuggestions.isEmpty && !trimmedQuery.isEmpty {
                            noResultsState
                        } else if localSuggestions.isEmpty && suggested.isEmpty && requests.friendships.isEmpty && trimmedQuery.isEmpty {
                            emptyState
                        } else {
                            suggestionsSection(title: "Suggested", items: localSuggestions)
                            if !remoteSuggestions.isEmpty {
                                suggestionsSection(title: "All of Whisper", items: remoteSuggestions)
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("New message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            .task {
                await requests.refresh()
                await follows.refresh()
                suggested = await follows.followingProfiles()
            }
            .onChange(of: query) { _, newValue in
                Task { await runSearch(newValue) }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            TextField("Search", text: $query)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if isSearching {
                ProgressView().scaleEffect(0.7)
            } else if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(WhisperTheme.card(colorScheme), in: Capsule())
        .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
        .padding(.horizontal, 16)
    }

    private func suggestionsSection(title: String, items: [Suggestion]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 22)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    Button {
                        Haptics.tap()
                        onSelect(item.userID, item.username)
                    } label: {
                        HStack(spacing: 12) {
                            WhisperAvatar(
                                username: item.username,
                                size: 44,
                                imageURL: item.imageURL.flatMap(URL.init(string:)),
                                ring: false
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text("@\(item.username)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                                Text(item.source.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    if idx < items.count - 1 {
                        Divider().background(WhisperTheme.hairline(colorScheme)).padding(.leading, 70)
                    }
                }
            }
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
            .padding(.horizontal, 16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            WhisperMeetDoodle(symbol: "paperplane", height: 120)
            Text("No one to message yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Follow people on Whisper to see them here.")
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 50)
        .frame(maxWidth: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: 6) {
            WhisperMeetDoodle(symbol: "magnifyingglass", height: 120)
            Text("No results for \u{201C}\(trimmedQuery)\u{201D}")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
        }
        .padding(.top, 50)
        .frame(maxWidth: .infinity)
    }

    private func runSearch(_ raw: String) async {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            searchResults = []
            return
        }
        isSearching = true
        let rows = await users.search(q, limit: 20)
        // Debounce-style guard: only commit if the query still matches.
        if q == query.trimmingCharacters(in: .whitespacesAndNewlines) {
            searchResults = rows
        }
        isSearching = false
    }
}

/// Compact "Title — Artist" marquee that lives under the username on the
/// story viewer. Instagram-style: the music glyph is fixed on the left and
/// the label text scrolls horizontally when it overflows the available
/// width, otherwise it sits still.
struct StoryMusicMarquee: View {
    let title: String
    let artist: String
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var animating: Bool = false

    private var combined: String { "\(title) \u{2014} \(artist)" }
    private let gap: CGFloat = 28
    /// Slightly slower than the thought-bubble marquee for a calmer ticker feel.
    private let speed: Double = 22
    private var needsScroll: Bool {
        textWidth > containerWidth + 0.5 && containerWidth > 0
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "music.note")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    if needsScroll {
                        HStack(spacing: gap) {
                            label
                            label
                        }
                        .offset(x: offset)
                    } else {
                        label
                            .frame(width: geo.size.width, alignment: .leading)
                    }
                }
                .frame(width: geo.size.width, alignment: .leading)
                .clipped()
                .onAppear {
                    containerWidth = geo.size.width
                    startIfNeeded()
                }
                .onChange(of: geo.size.width) { _, w in
                    containerWidth = w
                    startIfNeeded()
                }
            }
            .frame(height: 12)
            .frame(maxWidth: 160)
        }
        .background(
            label
                .hidden()
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { textWidth = proxy.size.width; startIfNeeded() }
                            .onChange(of: proxy.size.width) { _, w in
                                textWidth = w
                                startIfNeeded()
                            }
                    }
                )
        )
        .onChange(of: combined) { _, _ in
            animating = false
            offset = 0
            startIfNeeded()
        }
    }

    private var label: some View {
        Text(combined)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.78))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func startIfNeeded() {
        guard needsScroll, !animating else { return }
        animating = true
        offset = 0
        let distance = textWidth + gap
        let duration = Double(distance) / max(speed, 1)
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            offset = -distance
        }
    }
}

private struct TextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Wrapper so `.sheet(item:)` in the inbox can present a reply sheet for
/// another user's IG-Notes thought tapped in the DM stories strip.
struct InboxFriendThoughtTarget: Identifiable, Equatable {
    let id = UUID()
    let note: WhisperThoughtRow
    let username: String

    static func == (lhs: InboxFriendThoughtTarget, rhs: InboxFriendThoughtTarget) -> Bool {
        lhs.id == rhs.id
    }
}

/// iMessage-style long-press peek for a conversation row — renders the last
/// few messages instantly from the already-loaded conversation cache (no
/// fetch), so the user can glance at a thread without opening it. Embed
/// tokens collapse to their inbox preview labels so raw JSON never shows.
private struct WhisperConversationPeek: View {
    @Environment(\.colorScheme) private var colorScheme
    let thread: WhisperConversationSummary

    private var rows: [WhisperMessageRow] {
        Array(WhisperBackendService.shared.directMessages(with: thread.otherUserID, kind: thread.kind).filter {
            WhisperThoughtReplyEmbed.decode($0.body) == nil
        }.suffix(7))
    }

    var body: some View {
        let cached = rows
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                WhisperAvatar(username: thread.otherUsername, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("@\(thread.otherUsername)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("Hold to peek · tap Open to reply")
                        .font(.caption2)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(WhisperTheme.card(colorScheme))

            Divider()

            if cached.isEmpty {
                // Cache hasn't hydrated this thread yet — fall back to the
                // inbox's last-message preview so the peek is never blank.
                let p = WhisperInboxView.previewFor(
                    body: thread.lastMessage,
                    fallback: "No messages yet"
                )
                HStack(spacing: 6) {
                    if let icon = p.icon {
                        Image(systemName: icon)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    Text(p.text)
                        .font(.footnote)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(3)
                }
                .padding(14)
            } else {
                VStack(spacing: 6) {
                    ForEach(cached) { row in
                        peekBubble(row)
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 330)
        .background(WhisperTheme.surface(colorScheme))
    }

    @ViewBuilder
    private func peekBubble(_ row: WhisperMessageRow) -> some View {
        let mine = row.from_user_id == AccountStorage.currentUserID
        let isToken = row.body.contains("::whisper-")
            || row.body.hasPrefix(WhisperGroupChatService.headerPrefix)
            || row.body.hasPrefix("jasper-sticker://")
            || WhisperDMThreadView.imageURL(in: row.body) != nil
        let p = WhisperInboxView.previewFor(body: row.body, fallback: "…")
        HStack(spacing: 0) {
            if mine { Spacer(minLength: 44) }
            HStack(spacing: 5) {
                if isToken, let icon = p.icon {
                    Image(systemName: icon)
                        .font(.caption2.weight(.bold))
                }
                Text(isToken ? p.text : row.body)
                    .font(.footnote)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                mine ? WhisperChatStyle.ownFill(colorScheme) : WhisperChatStyle.theirFill(colorScheme),
                in: RoundedRectangle(cornerRadius: WhisperChatStyle.bigRadius)
            )
            .foregroundStyle(
                mine ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme)
            )
            if !mine { Spacer(minLength: 44) }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }
}
