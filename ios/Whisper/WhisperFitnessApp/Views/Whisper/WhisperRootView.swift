import SwiftUI

/// Root tab shell with five destinations, custom paging and native-glass
/// navigation that compacts to one expandable bubble during scrolling.
///
/// Whisper is gated behind two checks:
///   1. Real Supabase session — otherwise we surface `WhisperAuthSheet`.
///   2. Whisper-specific onboarding — even with a Whisper account, the user
///      is not a Whisper user until they finish bio + interests + follow
///      via `WhisperOnboardingView`.
struct WhisperRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var selection: Int = 0
    @State private var homeScrollRequest: UUID = UUID()
    @State private var pager: WhisperTabPagingState = WhisperTabPagingState()
    @State private var profileTabAtRoot: Bool = true
    /// Warm pages incrementally after the first frame, then retain their
    /// layouts and scroll positions. Playback is gated separately from mounting.
    @State private var pageGeneration: UUID = UUID()
    @State private var warmedTabs: Set<Int> = [0]
    @State private var presentComposer: Bool = false
    @State private var presentInbox: Bool = false
    /// Generic Jasper-routed destination sheet (meetings, calendar, settings,
    /// coach studio…) — lets Jasper link to every surface in the app.
    @State private var emberRouteSheet: WhisperEmberRouteSheet?
    @State private var presentOnboarding: Bool = false
    @State private var users = WhisperUserService.shared
    @State private var backend = WhisperBackendService.shared
    @State private var auth = AuthenticationService.shared
    @State private var profileTabIcon: UIImage?
    @State private var identityHydration: Task<Void, Never>?
    @State private var profileMediaWarmTask: Task<Void, Never>?
    @State private var accountWarmTask: Task<Void, Never>?
    @State private var accountWarmID: UUID = UUID()
    @State private var preparedAccountGeneration: UUID?
    @State private var accountTransition = WhisperAccountTransition.shared
    @State private var liarLiar = WhisperLiarLiarService.shared
    @State private var proposalReview = WhisperCoachProposalReviewService.shared
    @State private var identity = WhisperIdentityService.shared
    /// Scroll compaction never overrides explicit full-screen visibility locks.
    @State private var tabBarVisibility = WhisperTabBarVisibility.shared
    /// Resolved profile row to present when the user taps an `@username`
    /// mention rendered anywhere in the app. Powered by
    /// `.whisperOpenUserByUsername` notifications fired by `WhisperMentionText`.
    @State private var mentionedUser: WhisperUserRow?
    @State private var resolvingMention: Bool = false
    /// Story row to present full-screen when a `.whisperOpenStory`
    /// notification fires (tapping an avatar with an active story anywhere
    /// in the app).
    @State private var openedStory: WhisperStoryRow?
    /// Post row to present in a detail sheet when a `WhisperOpenPostByID`
    /// notification fires (tapping a like/comment row in the bell screen).
    @State private var openedPost: WhisperPost?
    /// Optional comment ID the post detail should scroll-to and highlight
    /// on appear — set when a "tagged in a comment" activity row routes
    /// here so the user lands directly on the comment that referenced them.
    @State private var openedPostHighlightCommentID: String?
    @State private var resolvingPost: Bool = false
    /// Surfaced when an activity / notification tap resolves to a post that
    /// no longer exists (deleted by author / moderation). Lets the user know
    /// what happened and prunes the orphan row from the bell screen.
    @State private var showPostUnavailableAlert: Bool = false
    @State private var showNotificationAccountAlert: Bool = false
    /// Shake-to-wake: a quick shake anywhere in the app summons the full Jasper
    /// assistant (the same shared-brain chat reachable from Jasper's profile).
    @State private var showEmberShakeChat: Bool = false
    @State private var presentCalendar: Bool = false
    @State private var communityPath: NavigationPath = NavigationPath()

    @State private var showsCommunities: Bool = false
    /// Coach Studio's client roster, opened by the Coach Clients widget.
    @State private var presentCoachClients: Bool = false

    private var isAuthed: Bool { !auth.isRestoringSession && auth.isSignedIn && backend.isSignedInRemotely }

    /// Routes deep links coming from the home-screen / lock-screen widgets
    /// (scheme `whisper://`). Each link maps onto a tab or fires a notification
    /// the relevant screen already listens to.
    private func handleWhisperWidgetURL(_ url: URL) {
        WhisperExternalRouteStore.shared.enqueue(url: url)
    }

    /// Unread DM count drives the red badge on the Inbox tab. Recomputed
    /// from `backend.threads` on every render — cheap, and `@Observable`
    /// invalidates this view as the thread list updates.
    private var inboxUnreadCount: Int {
        backend.threads.filter { !$0.lastReadByMe }.count
        + WhisperGroupChatService.shared.visibleGroups.filter { WhisperGroupChatService.shared.isUnread($0) }.count
    }

    var body: some View {
        Group {
            if let issue = auth.restorationError {
                ContentUnavailableView {
                    Label("Reconnect to Whisper", systemImage: "wifi.exclamationmark")
                } description: { Text(issue) } actions: {
                    Button("Try again") { auth.retrySessionRestoration() }.buttonStyle(.borderedProminent)
                }
                .background(WhisperTheme.surface(colorScheme))
            } else if auth.isRestoringSession {
                WhisperSplashView()
                    .safeAreaInset(edge: .bottom) {
                        if auth.restorationIsTakingLonger {
                            VStack(spacing: 10) {
                                Text("Connecting is taking a little longer.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Button("Try again") { auth.retrySessionRestoration() }
                                    .buttonStyle(.bordered).frame(minHeight: 44)
                            }
                            .padding(.horizontal, 24).padding(.bottom, 24)
                            .frame(maxWidth: .infinity)
                            .background(WhisperTheme.surface(colorScheme))
                        }
                    }
            } else if isAuthed {
                mainShell
            } else {
                WhisperAuthSheet()
            }
        }
        // ONE peek layer for the whole app — wave tiles and story bubbles
        // lift into it (the tab bar dims underneath, like the reference).
        .whisperPeekHost()
        .whisperGlobalErrorBanner()
        .background {
            WhisperKnotWelcomeAgent(ready: rootSurfaceAvailable && isAuthed && users.didLoadFromServer && users.hasOnboarded)
        }
        .onChange(of: accountTransition.adoptedGeneration) { _, generation in
            if generation == AccountStorage.generation { handleAccountSwitched() }
        }
        .modifier(WhisperExternalRouteHost(ready: !accountTransition.isActive && isAuthed && users.didLoadFromServer && users.hasOnboarded && !presentOnboarding, selectTab: { tab in selectRootTab(tab) }))
        .task(id: "\(isAuthed)-\(auth.currentUser.userID)") {
            guard isAuthed else { return }
            WhisperBusinessWorkspaceService.shared.resetForCurrentAccount()
        }
        .onChange(of: isAuthed) { _, authed in
            if !authed {
                tabBarVisibility.unlock()
                WhisperBusinessWorkspaceService.shared.resetForCurrentAccount()
            }
        }
        .sheet(item: Binding(
            get: { proposalReview.presentedProposalID.map { ProposalIDBox(id: $0) } },
            set: { newValue in if newValue == nil { proposalReview.presentedProposalID = nil } }
        )) { box in
            WhisperCoachProposalReviewSheet(proposalID: box.id)
                .presentationDetents([.large])
        }
        .onOpenURL { url in
            // Whisper bouncing back from its "Allow" consent screen:
            // whisper://linked?code=…&state=… (or denied=1). Redeem silently.
            if WhisperWhisperLinkService.shared.handleReturn(url: url) { return }
            // Coach invite bouncing back from Whisper's consent screen:
            // whisper://coach-linked?granted=1&state=… (or denied=1).
            if WhisperCoachGrantService.shared.handleReturn(url: url) { return }
            if proposalReview.handle(url: url) { return }
            handleWhisperWidgetURL(url)
        }
        .fullScreenCover(item: $mentionedUser) { user in
            NavigationStack {
                WhisperUserProfileView(user: user)
            }
        }
        .fullScreenCover(item: $openedStory) { story in
            // Reuse the existing viewer. Pull the whole per-user group so
            // the multi-segment progress bar shows every story, and start
            // on the first unseen segment (Instagram parity).
            let svc = WhisperStoryService.shared
            let group = svc.storiesByUser().first { $0.userID == story.user_id }
            let list = Array((group?.all ?? [story]).reversed())
            WhisperStoryViewer(
                stories: list,
                startIndex: svc.firstUnseenIndex(in: list)
            )
        }
        .fullScreenCover(item: $openedPost, onDismiss: {
            openedPostHighlightCommentID = nil
        }) { post in
            // `WhisperPostDetailView` already provides its own chevron-left
            // back button wired to `dismiss()`, which dismisses this cover.
            // Adding another toolbar item here would stack two chevrons.
            WhisperPostDetailView(post: post, highlightCommentID: openedPostHighlightCommentID)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperOpenPostByID"))) { note in
            guard
                let pid = (note.userInfo?["postID"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !pid.isEmpty,
                !resolvingPost
            else { return }
            let highlightCID = (note.userInfo?["commentID"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !accountTransition.isActive else { return }
            let generation = AccountStorage.generation
            resolvingPost = true
            Task {
                let row = await backend.fetchPost(postID: pid)
                guard generation == AccountStorage.generation, !accountTransition.isActive else { return }
                await MainActor.run {
                    resolvingPost = false
                    if let row {
                        let resolvedUsername = backend.postAuthorProfiles[row.user_id]?.username
                        openedPostHighlightCommentID = (highlightCID?.isEmpty == false) ? highlightCID : nil
                        openedPost = Self.mapRowToPost(row, fallbackUsername: resolvedUsername)
                    } else {
                        // Post is gone — prune any orphan rows in Activity
                        // that reference it (their parent comment/like is
                        // now meaningless) and let the user know.
                        showPostUnavailableAlert = true
                    }
                }
            }
        }
        .alert("Notification for another account", isPresented: $showNotificationAccountAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Switch to the account that received this notification, then open it again.")
        }
        .alert("Post no longer available", isPresented: $showPostUnavailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This post may be unavailable or private, or your connection may be interrupted. Try opening it again.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .whisperOpenStory)) { note in
            guard let id = note.userInfo?["storyID"] as? String else { return }
            let row = WhisperStoryService.shared.stories.first { $0.id == id }
            if let row { openedStory = row }
        }
        .onReceive(NotificationCenter.default.publisher(for: .whisperOpenUserByUsername)) { note in
            guard
                let handle = (note.userInfo?["username"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !handle.isEmpty,
                !resolvingMention
            else { return }
            guard !accountTransition.isActive else { return }
            let generation = AccountStorage.generation
            resolvingMention = true
            Task {
                // The built-in assistant has no remote profile row. Preserve its
                // legacy identity while routing Knot and older aliases to the original profile.
                guard generation == AccountStorage.generation, !accountTransition.isActive else { return }
                if ["knot", "ember", "jasper"].contains(handle.lowercased()) {
                    let stub = WhisperUserRow(
                        user_id: "ember",
                        username: "ember",
                        display_name: "Knot",
                        bio: nil,
                        interests: nil,
                        profile_image_url: nil,
                        onboarded_at: nil,
                        is_private: nil
                    )
                    await MainActor.run {
                        resolvingMention = false
                        mentionedUser = stub
                    }
                    return
                }
                let row = await WhisperUserService.shared.fetchByUsername(handle)
                guard generation == AccountStorage.generation, !accountTransition.isActive else { return }
                await MainActor.run {
                    resolvingMention = false
                    if let row { mentionedUser = row }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .whisperEmberNavigate)) { note in
            handleEmberRoute(
                (note.userInfo?["route"] as? String) ?? "",
                arg: (note.userInfo?["arg"] as? String) ?? ""
            )
        }
        .sheet(item: $emberRouteSheet) { sheet in
            WhisperEmberRouteSheetView(route: sheet.id)
        }
        .emberActionModals()
    }

    private struct ProposalIDBox: Identifiable, Hashable {
        let id: String
    }

    private var mainShell: some View {
        tabShell
            .background(WhisperNavigationPreview())
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    WhisperAccountReconcileBanner()
                        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: identity.mismatch)
                    WhisperDecisionInboxNotice().id(AccountStorage.generation)
                }
            }
            // Knot lives in Messages; shaking no longer opens the assistant.
            .fullScreenCover(isPresented: $showEmberShakeChat, onDismiss: {
                // Let the shake detector reclaim first-responder so the next
                // shake is caught immediately after the cover dismisses.
                NotificationCenter.default.post(
                    name: NSNotification.Name("EmberDismissed"),
                    object: nil
                )
            }) {
                // Full screen like native Jasper — the chat implements its
                // own swipe-down-to-close (drag down from the top of the
                // thread), so nothing is lost versus a sheet.
                WhisperEmberChatView()
                    .presentationBackground(.clear)
            }
    }

    private var feedSurfaceActive: Bool {
        !accountTransition.isActive && selection == 0 && pager.source == nil && !presentComposer && !presentInbox && !presentOnboarding
            && !showEmberShakeChat && !presentCalendar && !showsCommunities && !presentCoachClients
            && mentionedUser == nil && openedStory == nil && openedPost == nil
            && emberRouteSheet == nil && liarLiar.pendingPopup == nil
            && proposalReview.presentedProposalID == nil && !WhisperExternalRouteStore.shared.isPresenting
    }

    private var rootSurfaceAvailable: Bool {
        !accountTransition.isActive && !presentComposer && !presentInbox && !presentOnboarding && !showEmberShakeChat
        && !presentCalendar && !showsCommunities && !presentCoachClients && mentionedUser == nil && openedStory == nil
        && openedPost == nil && emberRouteSheet == nil && liarLiar.pendingPopup == nil
        && proposalReview.presentedProposalID == nil && !WhisperExternalRouteStore.shared.isPresenting
    }

    private var tabShell: some View {
        GeometryReader { outer in
        let layout = WhisperTabletLayout(width: outer.size.width, isPad: UIDevice.current.userInterfaceIdiom == .pad, fullBleed: (selection == 1 || tabBarVisibility.isLocked) && !showsCommunities)
        HStack(spacing: 0) {
            if layout.hasSidebar {
                WhisperTabletSidebar(selection: selection, unread: inboxUnreadCount,
                    select: { selectRootTab($0) },
                    openActivity: { presentInbox = true },
                    openCommunities: { openCommunityPage() }, openCommunity: { openCommunityPage($0) },
                    communitiesSelected: showsCommunities, compose: { presentComposer = true })
            }
        ZStack {
        GeometryReader { geometry in
        WhisperTabPager(pages: tabPages, selection: selection, pager: pager, insets: geometry.safeAreaInsets, isInteractive: !accountTransition.isActive && !showsCommunities)
            .frame(width: geometry.size.width, height: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom)
            .padding(.top, -geometry.safeAreaInsets.top)
            .padding(.bottom, -geometry.safeAreaInsets.bottom)
        .clipShape(WhisperPagingClip(radius: 0, top: geometry.safeAreaInsets.top, bottom: geometry.safeAreaInsets.bottom))
        .background(Color.black.ignoresSafeArea())
        .background(WhisperRootTabSwipe(enabled: !layout.hasSidebar && (selection != 4 || profileTabAtRoot) && !tabBarVisibility.isLocked && rootSurfaceAvailable, selection: selection, pager: pager, onBegin: { _ in }, onEnd: { commit, velocity in
            pager.settle(commit: commit, velocity: velocity, reduceMotion: reduceMotion) { next in
                if let next { selection = next; Haptics.selection() }
            }
        }))
        }
        .allowsHitTesting(!showsCommunities)
        .accessibilityHidden(showsCommunities)
        if showsCommunities {
            WhisperCommunityPane(path: $communityPath, onClose: closeCommunityPage)
        }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if layout.hasBottomBar && (selection != 1 || showsCommunities) && !tabBarVisibility.isHidden { whisperTabBar }
        }
        .frame(width: selection == 2 && UIDevice.current.userInterfaceIdiom == .pad ? max(0, outer.size.width - (layout.hasSidebar ? 260 : 0)) : layout.contentWidth)
        .environment(\.whisperHasBottomBar, layout.hasBottomBar && (selection != 1 || showsCommunities))
        if layout.hasRightRail && selection != 2 {
            WhisperTabletRightRail(searchAll: { selectRootTab(3) },
                openLive: { emberRouteSheet = .init(id: "live_rooms") }, openCommunity: { openCommunityPage($0) })
        }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WhisperTheme.surface(colorScheme).ignoresSafeArea())
        .onChange(of: outer.size) { _, _ in pager.reset() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in pager.reset() }
        .id(pageGeneration)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            resetAccountPresentation()
        }
        // Mount a tab when selected (or exposed by the swipe policy), not all
        // five at startup. Hidden pages must not compete with visible content.
        .task(id: "jasper-\(AccountStorage.generation)-\(auth.isSignedIn)") {
            guard auth.isSignedIn else { return }
            await JasperConnectClient.shared.resumeAfterSignIn()
        }
        .onChange(of: rootSurfaceAvailable) { _, available in if !available { pager.reset() } }
        .onChange(of: selection) { _, newValue in
            closeCommunityPage()
            warmedTabs.insert(newValue)
            pager.reset()
            // A fresh tab always starts with expanded navigation.
            tabBarVisibility.expand()
            tabBarVisibility.set(hidden: false)
        }
        .tint(WhisperTheme.ink(colorScheme))
        .task {
            // Drain a notification tap that launched the app from a killed
            // state — the AppDelegate buffered it before this view existed.
            if let pending = AppDelegate.pendingWhisperDeepLink {
                handleNotificationDeepLink(pending)
            }
            // On-device time-spent tracking for Settings → Your activity.
            WhisperUsageTracker.shared.start()
            // Identity first (profile row + tab avatar + onboarding gate),
            // then every independent warm-up in parallel. This used to be
            // ten serial round-trips before realtime even connected.
            let generation = AccountStorage.generation
            await hydrateIdentity()
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            if accountTransition.adoptedGeneration == generation { handleAccountSwitched() }
            backend.startMessagesRealtime()
            backend.startPostsRealtime()
            WhisperMentionsService.shared.start()
            WhisperFollowService.shared.startFollowersRealtime()
            WhisperNutritionRemoteService.shared.startRealtimeSync()
            async let notif: Void = WhisperNotificationService.shared.requestAuthorization()
            async let push: Void = WhisperPushService.shared.registerIfNeeded()
            async let voip: Void = WhisperVoIPService.shared.registerIfNeeded()
            async let bookmarks: Void = WhisperBookmarkService.shared.refresh()
            async let mentions: Void = WhisperMentionsService.shared.fetch()
            async let nutrition: Void = NutritionStore.shared.refreshFromWhisper()
            async let popup: Void = liarLiar.checkPopupForCurrentUser()
            async let mismatch: Void = identity.checkMismatch()
            _ = await (notif, push, voip, bookmarks, mentions, nutrition, popup, mismatch)
        }
        .task(id: "\(AccountStorage.generation)-\(auth.currentUser.profileImageURL ?? "")") {
            await refreshProfileTabIcon()
        }
        .onChange(of: backend.isSignedInRemotely) { _, signedIn in
            Task {
                await hydrateIdentity()
                if signedIn {
                    async let push: Void = WhisperPushService.shared.registerIfNeeded()
                    async let voip: Void = WhisperVoIPService.shared.registerIfNeeded()
                    async let bookmarks: Void = WhisperBookmarkService.shared.refresh()
                    async let mismatch: Void = identity.checkMismatch()
                    // Backend just came online (post cold-launch sign-in) —
                    // re-pull DMs + stories so the widget snapshot finally
                    // has real data.
                    async let threads: Void = backend.fetchThreads()
                    async let stories: Void = WhisperStoryService.shared.fetch()
                    _ = await (push, voip, bookmarks, mismatch, threads, stories)
                    backend.cacheWidgetSnapshot()
                }
            }
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if !signedIn {
                // Logged out — forget Whisper onboarding so the next sign-in
                // shows the auth screen and (if needed) onboarding flow.
                users.resetOnboardingLocally()
                profileTabIcon = nil
                WhisperAnalyticsService.shared.resetSession()
                Task {
                    await WhisperPushService.shared.unregister()
                    await WhisperVoIPService.shared.unregister()
                }
            } else {
                Analytics.record("session_start")
            }
            Task { await hydrateIdentity() }
        }
        .onChange(of: users.hasOnboarded) { _, onboarded in
            if onboarded { presentOnboarding = false }
        }
        .onChange(of: users.didLoadFromServer) { _, _ in
            evaluateGate()
        }
        .sheet(isPresented: $presentComposer) {
            WhisperComposerView()
        }
        .fullScreenCover(isPresented: $presentInbox) {
            // The bell in the feed header opens a dedicated full-page
            // Activity view — no Messages tab inside, just notifications,
            // with a back chevron in the leading toolbar slot. DMs still
            // live in the bottom Inbox tab.
            WhisperInboxView(initialTab: .activity, activityOnly: true)
        }
        .fullScreenCover(isPresented: $presentOnboarding) {
            WhisperOnboardingView()
                .background(WhisperAccountDestinationProbe(generation: accountTransition.contentGeneration))
                .interactiveDismissDisabled(true)
        }
        .fullScreenCover(isPresented: $presentCalendar) {
            WhisperCalendarView()
        }
        .fullScreenCover(isPresented: $presentCoachClients) {
            WhisperCoachClientsView()
        }
        // NOTE: the call UI no longer mounts here — `WhisperCallWindowManager`
        // hosts it in a dedicated window above every sheet/cover, so calls
        // ring, connect, and run even while the DM thread (itself a
        // fullScreenCover) is open.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperNotificationDeepLink"))) { note in
            guard let info = note.userInfo else { return }
            handleNotificationDeepLink(info)
        }
        .onReceive(NotificationCenter.default.publisher(for: .whisperAccountSwitched)) { _ in
            handleAccountSwitched()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperOpenCalendar"))) { _ in
            // A presented cover (the bell's Activity/Inbox) blocks a second
            // fullScreenCover from presenting — dismiss it first, then open
            // the calendar once the transition settles.
            if presentInbox {
                presentInbox = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    presentCalendar = true
                }
            } else {
                presentCalendar = true
            }
        }
    }

    private func openCommunityPage(_ community: WhisperCommunity? = nil) {
        guard isAuthed, !accountTransition.isActive else { return }
        pager.reset()
        var path = NavigationPath()
        if let community { path.append(community) }
        communityPath = path
        showsCommunities = true
        tabBarVisibility.set(hidden: false)
    }

    private func closeCommunityPage() {
        showsCommunities = false
        communityPath = NavigationPath()
    }

    private func selectRootTab(_ tab: Int) {
        let isHomeRetap = tab == 0 && selection == 0 && !showsCommunities
        closeCommunityPage()
        pager.reset(); selection = tab
        if isHomeRetap { homeScrollRequest = UUID() }
    }

    private var tabPages: [Int: AnyView] {
        [
            0: AnyView(WhisperFeedView(presentComposer: $presentComposer, presentInbox: $presentInbox, isActive: feedSurfaceActive, scrollToTopRequest: homeScrollRequest)
                .environment(\.whisperMediaActive, selection == 0 && rootSurfaceAvailable && pager.source == nil)),
            1: AnyView(WhisperReelsTabView(isActive: selection == 1 && rootSurfaceAvailable && pager.source == nil, onExit: {
                pager.reset(); selection = 0
            }).environment(\.whisperMediaActive, selection == 1 && rootSurfaceAvailable && pager.source == nil)),
            2: AnyView(WhisperInboxView().environment(\.whisperMediaActive, selection == 2 && rootSurfaceAvailable && pager.source == nil)),
            3: AnyView(WhisperExploreView().environment(\.whisperMediaActive, selection == 3 && rootSurfaceAvailable && pager.source == nil)),
            4: AnyView(WhisperProfileView(onRootSwipeAvailability: { profileTabAtRoot = $0 })
                .background(WhisperAccountDestinationProbe(generation: selection == 4 && !presentOnboarding ? accountTransition.contentGeneration : nil))
                .environment(\.whisperMediaActive, selection == 4 && rootSurfaceAvailable && pager.source == nil && profileTabAtRoot))
        ].filter { warmedTabs.contains($0.key) || $0.key == selection || $0.key == pager.target }
    }

    // MARK: - Liquid Glass navigation

    /// Keep the existing pager and destinations, using the system glass material.
    private var whisperTabBar: some View {
        let onReels = selection == 1 && !showsCommunities
        let barInk: Color = onReels ? .white : WhisperTheme.ink(colorScheme)
        let collapsed = tabBarVisibility.isCollapsed && !voiceOver && !showsCommunities
        return HStack(spacing: 0) {
            if collapsed {
                Button {
                    Haptics.tap()
                    tabBarVisibility.expand()
                } label: {
                    collapsedTabIcon(ink: barInk)
                        .frame(width: 44, height: 44)
                        .frame(maxWidth: .infinity)
                        .contentShape(Circle())
                        .overlay(alignment: .topTrailing) {
                            if inboxUnreadCount > 0 {
                                Circle().fill(.red).frame(width: 7, height: 7)
                                    .padding(3)
                                    .accessibilityHidden(true)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Expand tabs, \(selectedTabName) selected")
                .accessibilityValue(inboxUnreadCount > 0 ? "\(inboxUnreadCount) unread conversations" : "")
                .accessibilityIdentifier("rootTabs-expand")
            } else {
                tabButton(tag: 0, idle: "house", active: "house.fill", label: "Home", ink: barInk)
                tabButton(tag: 3, idle: "magnifyingglass", active: "magnifyingglass", label: "Search", ink: barInk)
                wavesTabButton(ink: barInk)
                tabButton(
                    tag: 2, idle: "paperplane", active: "paperplane.fill",
                    label: "Messages", ink: barInk, badge: inboxUnreadCount
                )
                profileTabButton(ink: barInk)
            }
        }
        .frame(width: collapsed ? 56 : nil)
        .padding(.vertical, 6)
        .modifier(WhisperControlGlass(shape: Capsule()))
        .environment(\.colorScheme, onReels ? .dark : colorScheme)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.88), value: collapsed)
        .onChange(of: voiceOver) { _, enabled in if enabled { tabBarVisibility.expand() } }
    }

    private var selectedTabName: String {
        switch selection {
        case 1: "Waves"
        case 2: "Messages"
        case 3: "Search"
        case 4: "Profile"
        default: "Home"
        }
    }

    @ViewBuilder private func collapsedTabIcon(ink: Color) -> some View {
        switch selection {
        case 1:
            WavesTabGlyph(isSelected: true, ink: ink, selectedCutout: .black)
        case 4:
            if let image = profileTabIcon {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: 26, height: 26).clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 25)).foregroundStyle(ink)
            }
        default:
            WhisperRoundedGlyph(kind: selection == 0 ? .home : (selection == 3 ? .search : .plane), size: 25, selected: true)
                .foregroundStyle(ink)
        }
    }

    private func tabButton(
        tag: Int,
        idle: String,
        active: String,
        label: String,
        ink: Color,
        badge: Int = 0
    ) -> some View {
        let isSelected = selection == tag && !showsCommunities
        return Button {
            if selection != tag { Haptics.tap() }
            selectRootTab(tag)
        } label: {
            WhisperRoundedGlyph(kind: tag == 0 ? .home : (tag == 3 ? .search : .plane), size: 25, selected: isSelected)
                .foregroundStyle(ink)
                .frame(width: 44, height: 44)
                .overlay(alignment: .bottomTrailing) {
                    if badge > 0 {
                        Text(badge > 99 ? "99+" : "\(badge)")
                            .font(.system(size: 10, weight: .heavy).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1.5)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Color(red: 0.98, green: 0.20, blue: 0.28), in: Capsule())
                            .offset(x: 4, y: 0)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(badge > 0 ? "\(badge) unread conversations" : "")
        .accessibilityIdentifier("rootTab-\(tag)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// The Waves tab — Whisper's short-video surface wears its own custom
    /// mark: a thick rounded squircle with a rounded play wedge that fills
    /// with solid ink and pops when selected.
    private func wavesTabButton(ink: Color) -> some View {
        let isSelected = selection == 1 && !showsCommunities
        return Button {
            if selection != 1 { Haptics.tap() }
            selectRootTab(1)
        } label: {
            WavesTabGlyph(isSelected: isSelected, ink: ink, selectedCutout: isSelected ? .black : WhisperTheme.surface(colorScheme))
                .frame(width: 44, height: 44)
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Waves")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Profile slot — renders the user's avatar as the icon with a thin
    /// ink ring when selected (Instagram parity). Falls back to the
    /// person glyph while the avatar downloads.
    private func profileTabButton(ink: Color) -> some View {
        let isSelected = selection == 4 && !showsCommunities
        return Button {
            if selection != 4 { Haptics.tap() }
            selectRootTab(4)
        } label: {
            Group {
                if let img = profileTabIcon {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 26, height: 26)
                        .clipShape(Circle())
                        .overlay {
                            Circle().strokeBorder(ink, lineWidth: isSelected ? 2 : 0)
                        }
                } else {
                    Image(systemName: isSelected ? "person.crop.circle.fill" : "person.crop.circle")
                        .font(.system(size: 23, weight: isSelected ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(ink)
                }
            }
            .frame(width: 44, height: 44)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Downloads the current user's avatar and renders it into a small
    /// circular UIImage so the Profile tab icon shows the user's photo.
    private func refreshProfileTabIcon() async {
        let generation = AccountStorage.generation
        guard let s = auth.currentUser.profileImageURL, let url = URL(string: s) else {
            profileTabIcon = nil
            return
        }
        guard let raw = await WhisperImageCache.load(url, maxPixelSize: 96),
              !Task.isCancelled, generation == AccountStorage.generation,
              auth.currentUser.profileImageURL == s else { return }
        profileTabIcon = Self.circularIcon(from: raw, size: 28)
    }

    /// Crops `image` to a centered square and clips to a circle at `size` pt.
    /// Renders with `.alwaysOriginal` so the tab bar shows the real photo.
    nonisolated static func circularIcon(from image: UIImage, size: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { _ in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            UIBezierPath(ovalIn: rect).addClip()
            // Aspect-fill the source into a centered square.
            let src = image.size
            let scale = max(size / src.width, size / src.height)
            let drawSize = CGSize(width: src.width * scale, height: src.height * scale)
            let origin = CGPoint(x: (size - drawSize.width) / 2, y: (size - drawSize.height) / 2)
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }.withRenderingMode(.alwaysOriginal)
    }

    /// Maps a backend `WhisperPostRow` into the in-memory `WhisperPost` the
    /// detail sheet renders. Mirrors the conversion done by `WhisperFeedView`
    /// so notification-triggered detail views look identical to feed-tapped
    /// ones.
    nonisolated static func mapRowToPost(_ row: WhisperPostRow, fallbackUsername: String? = nil) -> WhisperPost {
        let urls: [URL] = (row.media_urls ?? []).compactMap { URL(string: $0) }
        let kind = WhisperPostKind(rawValue: row.kind ?? "") ?? .photo
        // Prefer the row's own username, then the cached author-profile
        // lookup the caller resolved (postAuthorProfiles), and only fall
        // back to a uid-prefix as a last resort — never the literal
        // string "user", which read as the placeholder it was.
        let placeholders: Set<String> = ["user", "", "unknown"]
        let rawUsername = (row.username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedUsername: String = {
            if !placeholders.contains(rawUsername.lowercased()) { return rawUsername }
            if let fb = fallbackUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
               !placeholders.contains(fb.lowercased()) {
                return fb
            }
            return String(row.user_id.prefix(6))
        }()
        return WhisperPost(
            id: UUID(uuidString: row.id) ?? UUID(),
            username: resolvedUsername,
            timeAgo: WhisperPost.relativeTime(from: row.created_at),
            kind: kind,
            caption: row.caption,
            symbol: row.symbol ?? kind.icon,
            accent: WhisperPost.color(fromHex: row.accent_hex) ?? Color(red: 0.5, green: 0.5, blue: 0.5),
            mediaURLs: urls,
            likes: row.likes_count ?? 0,
            comments: row.comments_count ?? 0,
            isReel: row.is_reel ?? false,
            createdAt: WhisperBackendService.parseISO(row.created_at),
            communityID: row.community_id,
            communityName: row.community_name,
            authorUserID: row.user_id
        )
    }

    /// Routes a tapped Whisper notification to its exact destination:
    /// DMs / missed calls / calendar invites → the sender's thread,
    /// likes / comments / mentions / new posts → the post detail,
    /// new followers → their profile.
    private func handleNotificationDeepLink(_ info: [AnyHashable: Any]) {
        guard let kind = info["kind"] as? String else { return }
        guard isAuthed else { AppDelegate.pendingWhisperDeepLink = info; return }
        AppDelegate.pendingWhisperDeepLink = nil
        if WhisperExternalRouteStore.shared.enqueue(notification: info) { return }
        if let recipient = info["recipientUID"] as? String, !recipient.isEmpty,
           recipient.lowercased() != AccountStorage.currentUserID.lowercased() {
            showNotificationAccountAlert = true
            return
        }
        let generation = AccountStorage.generation

        func openThread(with username: String) {
            guard !username.isEmpty, generation == AccountStorage.generation else { return }
            presentInbox = false
            selectRootTab(2)
            WhisperExternalRouteStore.shared.enqueue(.init(
                kind: "dm", userID: (info["fromUID"] as? String) ?? "", username: username,
                owner: AccountStorage.currentUserID.lowercased(),
                messageID: (info["messageID"] as? String) ?? "",
                threadID: (info["threadID"] as? String) ?? (info["sourceID"] as? String) ?? ""
            ))
        }

        func openPost(_ postID: String, commentID: String = "") {
            guard !postID.isEmpty, generation == AccountStorage.generation else { return }
            NotificationCenter.default.post(
                name: Notification.Name("WhisperOpenPostByID"),
                object: nil,
                userInfo: ["postID": postID, "commentID": commentID]
            )
        }

        /// Remote pushes may only carry the sender's user id — resolve the
        /// username first, then run the navigation. Local notifications
        /// already include the username and skip the lookup entirely.
        func withUsername(_ username: String, uid: String, _ navigate: @escaping (String) -> Void) {
            let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                navigate(trimmed)
                return
            }
            guard !uid.isEmpty else { return }
            Task { @MainActor in
                let profile = await WhisperBackendService.shared.fetchPublicProfile(userID: uid)
                guard generation == AccountStorage.generation, !Task.isCancelled else { return }
                if let name = profile?.username, !name.isEmpty {
                    navigate(name)
                }
            }
        }

        switch kind {
        case "whisper_dm", "whisper_missed_call", "whisper_call_invite":
            withUsername(
                (info["fromUsername"] as? String) ?? "",
                uid: (info["fromUID"] as? String) ?? ""
            ) { openThread(with: $0) }
        case "whisper_activity", "whisper_new_post":
            openPost((info["postID"] as? String) ?? "", commentID: (info["commentID"] as? String) ?? "")
        case "whisper_mention":
            let sourceType = (info["sourceType"] as? String) ?? ""
            if sourceType == "dm" {
                withUsername(
                    (info["fromUsername"] as? String) ?? "",
                    uid: (info["fromUID"] as? String) ?? ""
                ) { openThread(with: $0) }
            } else if sourceType == "comment" {
                let commentID = (info["sourceID"] as? String) ?? ""
                Task {
                    let postID = await backend.postID(forCommentID: commentID)
                    guard generation == AccountStorage.generation, !Task.isCancelled else { return }
                    if let postID { openPost(postID, commentID: commentID) }
                    else { showPostUnavailableAlert = true }
                }
            } else {
                openPost((info["sourceID"] as? String) ?? "")
            }
        case "whisper_follow":
            withUsername(
                (info["followerUsername"] as? String) ?? "",
                uid: (info["followerID"] as? String) ?? ""
            ) { name in
                NotificationCenter.default.post(
                    name: .whisperOpenUserByUsername,
                    object: nil,
                    userInfo: ["username": name]
                )
            }
        case "whisper_story_response":
            let storyID = (info["storyID"] as? String) ?? ""
            guard !storyID.isEmpty else { presentInbox = true; return }
            Task {
                await WhisperStoryService.shared.fetch()
                guard generation == AccountStorage.generation, !Task.isCancelled else { return }
                if let row = WhisperStoryService.shared.stories.first(where: { $0.id == storyID }) {
                    openedStory = row
                } else {
                    // Expired Stories retain their responses in Activity.
                    presentInbox = true
                }
            }
        case "whisper_thought_reply":
            presentInbox = true
        case "whisper_calendar":
            NotificationCenter.default.post(name: Notification.Name("WhisperOpenCalendar"), object: nil)
        default:
            break
        }
    }

    /// Executes an Jasper navigation route — the linking layer that lets
    /// Jasper open ANY surface in Whisper (tabs, overlays, destination
    /// sheets, profiles, DM threads, posts). Route ids live in
    /// `WhisperEmberAtlas.entries`.
    private func handleEmberRoute(_ route: String, arg: String) {
        switch route {
        case "feed": selectRootTab(0)
        case "reels", "waves": selectRootTab(1)
        case "messages", "inbox", "dms": selectRootTab(2)
        case "explore", "search": selectRootTab(3)
        case "profile", "my_profile": selectRootTab(4)
        case "activity", "notifications": presentInbox = true
        case "composer", "new_post": presentComposer = true
        case "ember", "ember_chat": showEmberShakeChat = true
        case "user":
            guard !arg.isEmpty else { selectRootTab(3); return }
            NotificationCenter.default.post(
                name: .whisperOpenUserByUsername,
                object: nil,
                userInfo: ["username": arg]
            )
        case "dm":
            guard !arg.isEmpty else { selectRootTab(2); return }
            presentInbox = false
            selectRootTab(2)
            // Two posts: the first catches an already-mounted Messages tab;
            // the second covers the tab still mounting when the first fires.
            for delay in [0.3, 1.4] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    NotificationCenter.default.post(
                        name: Notification.Name("WhisperOpenDMByUsername"),
                        object: nil,
                        userInfo: ["username": arg]
                    )
                }
            }
        case "post":
            guard !arg.isEmpty else { return }
            NotificationCenter.default.post(
                name: Notification.Name("WhisperOpenPostByID"),
                object: nil,
                userInfo: ["postID": arg]
            )
        case "communities" where UIDevice.current.userInterfaceIdiom == .pad:
            openCommunityPage()
        case "meeting_sidekick":
            // Jasper Intelligence hands a meeting-memory question to the cited
            // Sidekick. The question only prefills; scope approval still applies.
            WhisperEmberActionRouter.shared.pendingSidekickQuestion = arg.isEmpty ? nil : String(arg.prefix(600))
            emberRouteSheet = WhisperEmberRouteSheet(id: route)
        default:
            if WhisperEmberRouteSheetView.supported.contains(route) {
                emberRouteSheet = WhisperEmberRouteSheet(id: route)
            }
        }
    }

    /// ACCOUNT SWITCH: the session flipped to another saved login WITHOUT a
    /// sign-out cycle (so `isSignedIn` never dipped and none of the sign-in
    /// hooks above fired). Re-pull everything that is per-account so the new
    /// user never sees the last one's inbox, stories, follows, or flags.
    private func handleAccountSwitched() {
        guard accountWarmTask == nil, preparedAccountGeneration != AccountStorage.generation,
              !accountTransition.isActive || accountTransition.adoptedGeneration == AccountStorage.generation else { return }
        let operation = UUID(); accountWarmID = operation
        let generation = AccountStorage.generation
        let owner = AccountStorage.currentUserID
        selection = 4
        presentInbox = false
        Analytics.record("session_start")
        accountTransition.watchReadiness(retry: retryAccountPreparation, recovery: returnToAccountSignIn)
        accountWarmTask = Task {
            defer { if operation == accountWarmID { accountWarmTask = nil } }
            let readiness = WhisperPerformance.Span("AccountReady")
            defer { readiness.finish() }
            if auth.profileLoadedGeneration != generation { await auth.refreshProfileNow() }
            guard !Task.isCancelled, generation == AccountStorage.generation, operation == accountWarmID else { return }
            await hydrateIdentity()
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            // Identity and authoritative role/restriction checks remain blocking.
            // Follows and the larger post window are not required for account readiness.
            async let ownPosts: Void = backend.fetchMyPosts(limit: 24)
            async let roles: Void = WhisperAccountStatusService.shared.refresh(force: true)
            _ = await (ownPosts, roles)
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            evaluateGate()
            guard operation == accountWarmID else { return }
            if users.didLoadFromServer && backend.myPostsLoadedGeneration == generation && auth.profileLoadedGeneration == generation {
                preparedAccountGeneration = generation
                accountTransition.prepared(owner: owner, generation: generation)
                readiness.finish(completed: true)
            } else {
                accountTransition.fail("Your login is ready, but your profile couldn't load. Check your connection and try again.", recoveryTitle: "Go to sign in", retry: retryAccountPreparation, recovery: returnToAccountSignIn)
            }
            readiness.finish()
            // The selected profile owns its larger post window. Feed, inbox,
            // stories and Saved load when visited rather than competing with
            // this account's first useful screen.
            async let flags: Void = UserFlagsService.shared.hydrate()
            async let friends: Void = FriendRequestsService.shared.refresh()
            async let followReqs: Void = WhisperFollowRequestService.shared.refresh()
            async let groups: Void = WhisperGroupChatService.shared.syncRegistry(force: true)
            async let follows: Void = WhisperFollowService.shared.refreshIfStale()
            async let coach: Void = WhisperCoachService.shared.refreshMyStatus()
            async let director: Void = WhisperDirectorService.shared.refreshMyStatus()
            async let mentions: Void = WhisperMentionsService.shared.fetch()
            _ = await (flags, friends, followReqs, follows, coach, director, mentions, groups)
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            backend.startMessagesRealtime()
            WhisperFollowService.shared.startFollowersRealtime()
            WhisperMentionsService.shared.start()
            WhisperNutritionRemoteService.shared.startRealtimeSync()
            await WhisperPushService.shared.registerIfNeeded()
            await WhisperVoIPService.shared.registerIfNeeded()
            backend.cacheWidgetSnapshot()
            evaluateGate()
        }
    }

    /// Profile row + tab avatar + onboarding gate, as one single-flight
    /// unit. Cold launch used to fire this three times at once (shell task,
    /// `isSignedIn` change, `isSignedInRemotely` change); now concurrent
    /// callers wait on the same run.
    private func hydrateIdentity() async {
        if let running = identityHydration {
            await running.value
            return
        }
        let generation = AccountStorage.generation
        let owner = AccountStorage.currentUserID
        profileMediaWarmTask?.cancel()
        profileMediaWarmTask = Task { @MainActor in
            // Useful media work is retained/cancelled but never blocks identity or other startup work.
            await WhisperVerifiedPerksService.shared.refreshAccentAndBanner(forUserID: owner)
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            if let url = WhisperVerifiedPerksService.shared.bannerURL(forUserID: owner) {
                await WhisperImageCache.prefetch(url)
            }
        }
        let task = Task { @MainActor in
            await users.refreshMeIfStale()
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            evaluateGate()
        }
        identityHydration = task
        await task.value
        if identityHydration == task { identityHydration = nil }
    }

    private func retryAccountPreparation() {
        preparedAccountGeneration = nil
        accountWarmID = UUID(); accountWarmTask?.cancel(); accountWarmTask = nil
        handleAccountSwitched()
    }

    private func returnToAccountSignIn() {
        accountWarmID = UUID(); accountWarmTask?.cancel(); accountWarmTask = nil
        AuthenticationService.shared.parkSessionForAccountSwitch()
        WhisperAccountSwitcher.shared.isAddingAccount = true
        accountTransition.close()
    }

    private func resetAccountPresentation() {
        preparedAccountGeneration = nil
        accountWarmID = UUID()
        identityHydration?.cancel(); identityHydration = nil
        profileMediaWarmTask?.cancel(); profileMediaWarmTask = nil
        accountWarmTask?.cancel(); accountWarmTask = nil
        pager.reset(); selection = 0; pageGeneration = UUID()
        profileTabIcon = nil; profileTabAtRoot = true
        presentInbox = false; presentComposer = false; presentOnboarding = false
        presentCalendar = false; closeCommunityPage(); presentCoachClients = false; showEmberShakeChat = false
        warmedTabs = [selection]
        mentionedUser = nil; openedStory = nil; openedPost = nil; emberRouteSheet = nil
        openedPostHighlightCommentID = nil; resolvingPost = false; resolvingMention = false
        showPostUnavailableAlert = false; liarLiar.pendingPopup = nil
        proposalReview.presentedProposalID = nil
        tabBarVisibility.unlock()
    }

    private func evaluateGate() {
        if !backend.isSignedInRemotely || !auth.isSignedIn {
            presentOnboarding = false
        } else if !users.didLoadFromServer {
            // Wait until we've actually checked Supabase for this user's
            // whisper_profiles row before showing the onboarding sheet.
            // Without this gate, signing back in flashes the "Create
            // profile" screen for one frame while the row is fetched.
            presentOnboarding = false
        } else if !users.hasOnboarded {
            presentOnboarding = true
        } else {
            presentOnboarding = false
        }
    }
}
