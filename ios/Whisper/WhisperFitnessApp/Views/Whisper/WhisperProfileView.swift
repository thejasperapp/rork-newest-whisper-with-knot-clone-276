import SwiftUI

/// Profile pulls real data from Whisper services so the "synced from Whisper"
/// promise is real on day one — workouts come from `workoutSessionHistory`,
/// progress photos from `ProgressPhotoService`.
///
/// Visually styled after Instagram: + button top-left, username (with chevron)
/// centered, threads/menu icons top-right, large avatar on the left with stat
/// columns to its right, action row of three full-width buttons, story
/// highlights row, and Threads-style content tabs.
/// Pair backing a row in the Replies tab: a post the user replied to, plus
/// the user's most-recent comment on that post.
nonisolated struct WhisperReplyPair: Identifiable, Sendable, Hashable {
    let post: WhisperPostRow
    let myComment: WhisperCommentRow
    var id: String { post.id + ":" + myComment.id }
}

struct WhisperProfileView: View {
    var onRootSwipeAvailability: ((Bool) -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.whisperRootChromeActive) private var rootChromeActive
    @State private var auth = AuthenticationService.shared
    @State private var leaderboard = LeaderboardService.shared
    @State private var thoughts = WhisperThoughtService.shared
    @State private var backend = WhisperBackendService.shared
    @State private var follows = WhisperFollowService.shared
    @State private var stories = WhisperStoryService.shared
    @State private var users = WhisperUserService.shared
    @State private var bookmarks = WhisperBookmarkService.shared
    @State private var liar = WhisperLiarLiarService.shared
    @State private var safety = WhisperSafetyService.shared

    @State private var tab: Tab = .threads
    @State private var workouts: [WorkoutSessionRecord] = []

    /// Every modal the profile can present, funneled through ONE
    /// `.sheet(item:)` and ONE `.fullScreenCover(item:)`. Stacking a dozen
    /// separate `.sheet(isPresented:)` modifiers on a single view is a
    /// SwiftUI footgun — it works in debug builds but hard-crashes on
    /// presentation in release/TestFlight builds (this exact crash hit the
    /// hamburger menu). Same pattern as `WhisperSettingsView`.
    private enum ActiveSheet: Identifiable {
        case editProfile, saved, followSuggestions, share
        case thought, lyrics, composer
        case analytics, accountSwitcher
        case followList(WhisperFollowListView.Tab)
        case badgeInfo(WhisperBadgeKind?)
        var id: String {
            switch self {
            case .editProfile: return "editProfile"
            case .saved: return "saved"
            case .followSuggestions: return "followSuggestions"
            case .share: return "share"
            case .thought: return "thought"
            case .lyrics: return "lyrics"
            case .composer: return "composer"
            case .analytics: return "analytics"
            case .accountSwitcher: return "accountSwitcher"
            case .followList(let tab): return "followList-\(String(describing: tab))"
            case .badgeInfo(let kind): return "badgeInfo-\(kind?.storageKey ?? "all")"
            }
        }
    }

    /// Full-screen surfaces (auth, stories, post detail, waves) — one cover modifier.
    private enum ActiveCover: Identifiable {
        case auth, storyComposer, waveCreate, creatorStudio, avatarZoom
        case myStory(WhisperStoryRow)
        case postDetail(WhisperPostRow)
        case waves(WhisperPostRow)
        var id: String {
            switch self {
            case .auth: return "auth"
            case .storyComposer: return "storyComposer"
            case .waveCreate: return "waveCreate"
            case .creatorStudio: return "creatorStudio"
            case .avatarZoom: return "avatarZoom"
            case .myStory(let row): return "myStory-\(String(describing: row.id))"
            case .postDetail(let row): return "post-\(row.id)"
            case .waves(let row): return "waves-\(row.id)"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?
    @State private var activeCover: ActiveCover?

    // SETTINGS AS A BACK SHEET. The settings menu is the layer BEHIND the
    // profile: the profile is a card with the phone's own corner radius that
    // slides off to the left as you swipe, revealing settings underneath
    // — the more you swipe, the more you see. `settingsReveal` is 0 (profile
    // parked) → 1 (settings fully shown); the back sheet mounts lazily on the
    // first drag so its services never hydrate while the profile is idle.
    @State private var settingsReveal: CGFloat = 0
    @State private var settingsSettling: Bool = false
    @State private var settingsTransitionID: UUID = UUID()
    @Environment(\.accessibilityReduceMotion) private var settingsReduceMotion
    @State private var settingsAtRoot: Bool = true
    @State private var settingsMounted: Bool = false
    @State private var isDraggingSettings: Bool = false
    @State private var settingsDragBase: CGFloat = 0
    @State private var settingsDragID = UUID()
    @State private var settingsOpening: Bool = false
    /// How far the profile card travels when settings is fully revealed —
    /// the FULL width, so settings is a full sheet; the way back is the
    /// header's "‹ Profile" or a drag from the left edge of the sheet.
    private let settingsRevealFraction: CGFloat = 1.0

    @State private var bookmarkRows: [WhisperPostRow] = []
    @State private var loadingBookmarks: Bool = false
    @State private var bookmarkRequestID = UUID()
    @State private var repliesRequestID = UUID()
    @State private var selectedBookmarkCategory: String = "All"
    @State private var presentNewCategoryAlert: Bool = false
    @State private var newCategoryName: String = ""

    /// The profile's content tabs — Whisps (text + media posts in a vertical
    /// feed), WAVES (the 9:16 grid — the ONLY place waves render on a
    /// profile), Replies (posts replied to, reply quoted underneath),
    /// Reposts, and Media (the IG-style photo grid, waves excluded). Saved
    /// posts live in the settings menu so the public tabs stay short.
    private typealias Tab = WhisperProfileTab

    /// The grid COMPOSER is a verified-creator perk (see `WhisperAccountAccess`);
    /// the Media grid itself is for everyone.
    private var canPostGrid: Bool {
        WhisperAccountAccess.canPostGrid(username: displayUsername)
    }

    private var visibleTabs: [Tab] { Tab.allCases }

    /// The insights door for the header's top-left: Analytics (professional
    /// / One) or Creator Studio (verified) — nil for personal accounts.
    private var insightsDoor: WhisperAccountAccess.InsightsDoor? {
        WhisperAccountAccess.insightsDoor(username: displayUsername)
    }

    /// Cached pairs of (post, my latest comment on it) backing the Replies
    /// tab — fetched lazily so we don't pay the round-trip until needed.
    @State private var repliedPairs: [WhisperReplyPair] = []
    @State private var loadingReplies: Bool = false
    @State private var lastSecondaryRefresh: Date?
    @State private var reposts = WhisperRepostService.shared
    @State private var repostRows: [WhisperPostRow] = []
    @State private var loadingReposts: Bool = false
    @State private var didLoadReposts: Bool = false
    @State private var repostLoadError: String?
    @State private var repostRevision: Int = 0
    @State private var repostRequestID: UUID = UUID()
    @GestureState private var settingsGestureActive: Bool = false

    /// Legacy IG-style content surfaces kept behind a long-press on the
    /// profile so workouts / photos / bookmarks remain reachable without
    /// cluttering the new Threads-style profile.
    @State private var verifiedPerks = WhisperVerifiedPerksService.shared

    /// The whole screen: the settings BACK SHEET underneath, the profile CARD
    /// on top. The container ignores the safe area so the card's clip reaches
    /// the physical corners of the display; the NavigationStacks inside
    /// re-apply the safe area to their own content through UIKit.
    private var mainContent: some View {
        GeometryReader { geo in
            let width: CGFloat = max(geo.size.width, 1)
            ZStack {
                WhisperTheme.surface(colorScheme)
                if settingsMounted {
                    settingsBackSheet(width: width)
                        .transition(.identity)
                }
                profileCard(width: width)
            }
            // The gesture belongs to the stationary container, never the
            // moving profile or a hit-testing-dependent edge overlay.
            .contentShape(.rect)
            .coordinateSpace(name: "profileSettingsReveal")
            .simultaneousGesture(
                settingsRevealDrag(width: width),
                including: settingsAtRoot && rootChromeActive && !settingsSettling
                    && activeSheet == nil && activeCover == nil ? .all : .subviews
            )
        }
        .ignoresSafeArea()
        .onChange(of: settingsGestureActive) { _, active in
            guard !active, isDraggingSettings else { return }
            let dragID = settingsDragID
            // GestureState may reset BEFORE onEnded. Give the velocity-based
            // end handler first refusal; only settle here for cancellation.
            DispatchQueue.main.async {
                guard settingsDragID == dragID, !settingsGestureActive,
                      isDraggingSettings, !settingsSettling else { return }
                settleSettings(toRevealed: settingsReveal > 0.5)
            }
        }
        .onChange(of: settingsMounted, initial: true) { _, mounted in onRootSwipeAvailability?(!mounted) }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            resetSettingsReveal()
            bookmarkRequestID = UUID()
            repliesRequestID = UUID()
            repostRequestID = UUID()
            bookmarkRows = []
            repliedPairs = []
            repostRows = []
            loadingBookmarks = false
            loadingReplies = false
            loadingReposts = false
            didLoadReposts = false
            lastSecondaryRefresh = nil
        }
    }

    /// Settings rendered as the layer behind the profile card — a FULL sheet
    /// with REAL frames: no scale, offset, or opacity transforms on the
    /// navigation stack (a UIKit navigation controller under the hood; layer
    /// transforms on it are exactly what made pushed sub-screens fail to
    /// appear). Depth comes from a scrim that lifts as the card slides away.
    /// The stationary parent owns both swipe directions so changing either
    /// child's hit testing cannot remove the recognizer during a drag.
    private func settingsBackSheet(width: CGFloat) -> some View {
        let reveal: CGFloat = settingsReveal
        return ZStack(alignment: .leading) {
            WhisperSettingsBackSheetHost(
                onOpenSaved: {
                    // Present OVER the settings — never close first.
                    activeSheet = .saved
                },
                onClose: { closeSettings() },
                onRootChanged: { settingsAtRoot = $0 }
            )
            .equatable()
            .frame(width: width)
            .task {
                // A button-open first installs the navigation stack at rest.
                // Start travel only after it has entered the mounted hierarchy.
                guard settingsOpening else { return }
                let transition = settingsTransitionID
                let generation = AccountStorage.generation
                await Task.yield()
                guard !Task.isCancelled, settingsOpening, settingsMounted,
                      settingsTransitionID == transition,
                      AccountStorage.generation == generation else { return }
                settingsOpening = false
                animateSettings(to: 1)
            }
            .allowsHitTesting(reveal == 1 && !isDraggingSettings && !settingsSettling)
            .accessibilityHidden(reveal != 1 || settingsSettling || isDraggingSettings)

            Color.black
                .opacity(Double(0.30 * (1 - reveal)))
                .allowsHitTesting(false)
        }
    }

    /// The device's display corner radius (heuristic from the top inset —
    /// Dynamic Island 55pt, notch 47pt, older 41pt, flat-corner phones 18pt
    /// so the card still reads as a card).
    private var deviceCornerRadius: CGFloat {
        let top: CGFloat = WhisperSafeArea.top
        if top >= 59 { return 55 }
        if top >= 47 { return 47 }
        if top > 24 { return 41 }
        return 18
    }

    /// The profile as the front card: rounded to the device corners while it
    /// travels, a soft edge shadow, offset by the reveal.
    private func profileCard(width: CGFloat) -> some View {
        let reveal: CGFloat = settingsReveal
        let radius: CGFloat = deviceCornerRadius * min(1, reveal * 6)
        return ZStack {
            if reveal > 0.001 {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.black)
                    .shadow(color: .black.opacity(Double(0.34 * min(1, reveal * 4))), radius: 28, x: 10, y: 0)
            }
            profileStack(width: width)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .offset(x: -width * settingsRevealFraction * reveal)
        .allowsHitTesting(!settingsSettling && (isDraggingSettings || reveal == 0))
        .accessibilityHidden(settingsMounted)
    }

    private func openSettings() {
        guard !settingsSettling, !isDraggingSettings, settingsReveal == 0,
              activeSheet == nil, activeCover == nil else { return }
        Haptics.tap()
        if settingsMounted {
            animateSettings(to: 1)
        } else {
            settingsTransitionID = UUID()
            settingsAtRoot = true
            settingsOpening = true
            settingsSettling = true
            // Do not insert the settings NavigationStack into the same
            // animated transaction that sends the profile off-screen.
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { settingsMounted = true }
        }
    }

    private func closeSettings() {
        guard !settingsSettling, !isDraggingSettings else { return }
        animateSettings(to: 0)
    }

    private func resetSettingsReveal() {
        // Invalidate queued opens, cancellation fallbacks and animation
        // completions before another account can take ownership.
        settingsTransitionID = UUID()
        settingsDragID = UUID()
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            settingsOpening = false
            settingsSettling = false
            isDraggingSettings = false
            settingsReveal = 0
            settingsDragBase = 0
            settingsMounted = false
            settingsAtRoot = true
        }
        onRootSwipeAvailability?(true)
    }

    private func animateSettings(to target: CGFloat) {
        settingsOpening = false
        isDraggingSettings = false
        settingsSettling = true
        let transition = UUID()
        settingsTransitionID = transition
        withAnimation(settingsReduceMotion ? nil : .spring(response: 0.34, dampingFraction: 1), completionCriteria: .removed) {
            settingsReveal = target
        } completion: {
            guard settingsTransitionID == transition else { return }
            settingsSettling = false
            if target == 0 { settingsMounted = false }
        }
    }

    /// Snaps the reveal to a resting state after a drag ends. Always clears
    /// the drag flag first — a stuck flag is what froze both layers.
    private func settleSettings(toRevealed revealed: Bool) {
        isDraggingSettings = false
        guard !settingsSettling else { return }
        if revealed { Haptics.tap() }
        animateSettings(to: revealed ? 1 : 0)
    }

    /// One interactive swipe on the stationary container: a horizontal drag
    /// engages the reveal and the card follows the finger; release settles
    /// on the nearer side using the predicted end point. Vertical scrolling
    /// is untouched — the drag only engages when it's clearly horizontal.
    private func settingsRevealDrag(width: CGFloat) -> some Gesture {
        let travel: CGFloat = max(width * settingsRevealFraction, 1)
        return DragGesture(minimumDistance: 12, coordinateSpace: .named("profileSettingsReveal"))
            .updating($settingsGestureActive) { _, active, _ in active = true }
            .onChanged { value in
                let dx: CGFloat = value.translation.width
                let dy: CGFloat = value.translation.height
                if !isDraggingSettings {
                    guard !settingsSettling, activeSheet == nil, activeCover == nil else { return }
                    guard rootChromeActive, abs(dx) > abs(dy) * 1.6 else { return }
                    let opening = settingsReveal == 0 && dx < 0
                        && value.startLocation.x >= width - 24 && value.startLocation.x <= width
                    let closing = settingsReveal == 1 && settingsAtRoot && dx > 0
                        && value.startLocation.x >= 0 && value.startLocation.x <= 24
                    guard opening || closing else { return }
                    settingsDragID = UUID()
                    settingsDragBase = settingsReveal
                    isDraggingSettings = true
                    settingsMounted = true
                }
                let progress: CGFloat = settingsDragBase + (-dx / travel)
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    settingsReveal = min(1, max(0, progress))
                }
            }
            .onEnded { value in
                guard isDraggingSettings else { return }
                isDraggingSettings = false
                let predicted: CGFloat = settingsDragBase + (-value.predictedEndTranslation.width / travel)
                settleSettings(toRevealed: predicted > 0.5)
            }
    }

    /// The profile content (feed, grid, tabs, etc.) — the front card's body.
    private func profileStack(width: CGFloat) -> some View {
        NavigationStack {
            ZStack {
                WhisperTheme.card(colorScheme).ignoresSafeArea()
                GeometryReader { viewport in
                    ScrollView {
                        VStack(spacing: 12) {
                            if !backend.isSignedInRemotely {
                                signInRequiredBanner
                            }
                            if let err = backend.lastError {
                                errorBanner(err)
                            } else if let err = WhisperFollowService.shared.lastError {
                                errorBanner(err)
                            }
                            WhisperProfileHeaderCard(userID: AccountStorage.currentUserID, viewportHeight: viewport.size.height, coverTopInset: viewport.safeAreaInsets.top) {
                                igHeader
                                actionRow
                                WhisperFeaturedLinksRow(
                                    userID: AccountStorage.currentUserID,
                                    username: displayUsername,
                                    isMe: true
                                )
                                WhisperStoryHighlightsRow(
                                    userID: AccountStorage.currentUserID,
                                    isMe: true
                                )
                                threadsTabBar
                                threadsTabContent
                            }
                        }
                        .padding(.bottom, 32)
                    }
                    .whisperHidesTabBarOnScroll(reservesHeaderSpace: false)
                    .ignoresSafeArea(.container, edges: .top)
                }
            }
            // Keep controls in the safe area, floating directly over the cover.
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .top) {
                profileHeaderBar
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
            }
            .task(id: rootChromeActive) {
                guard rootChromeActive else { return }
                let generation = AccountStorage.generation
                // Local caches first — instant, no network.
                thoughts.reloadFromDefaults()
                loadWorkouts()
                // The user's own posts are the profile's primary content —
                // fetch them FIRST so the Whisps tab fills immediately
                // instead of waiting behind a dozen secondary refreshes.
                await backend.fetchMyPostsIfStale()
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                backend.startPostsRealtime()
                if let lastSecondaryRefresh, Date().timeIntervalSince(lastSecondaryRefresh) < 60 { return }
                let uname = displayUsername
                let myUID = AccountStorage.currentUserID
                // Secondary hydration runs concurrently — these used to run
                // back-to-back, which kept the profile half-empty for
                // seconds on cold start.
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await WhisperThoughtService.shared.refreshFromServer() }
                    group.addTask { await WhisperUserService.shared.refreshMe() }
                    group.addTask { await WhisperFollowService.shared.refreshIfStale() }
                    group.addTask { await WhisperStoryService.shared.fetchIfStale() }
                    group.addTask { await UserVerificationService.shared.preload(usernames: [uname]) }
                    group.addTask { await WhisperLiarLiarService.shared.preload(usernames: [uname]) }
                    group.addTask { await WhisperOneService.shared.preload(usernames: [uname]) }
                    group.addTask { await WhisperThoughtRepliesService.shared.refreshForMe() }
                    group.addTask {
                        if !myUID.isEmpty, myUID != "guest", !myUID.hasPrefix("local_") {
                            await WhisperSafetyService.shared.preloadAgeBands(userIDs: [myUID])
                            await WhisperSafetyService.shared.preloadWatchFlags(
                                userIDs: [myUID],
                                usernames: [uname]
                            )
                        }
                    }
                    group.addTask { await WhisperModerationService.shared.refresh() }
                    group.addTask { await WhisperVerifiedPerksService.shared.refresh(forUserID: myUID) }
                    group.addTask { await WhisperDirectorService.shared.refreshMyStatus() }
                }
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                lastSecondaryRefresh = Date()
            }
            .task(id: rootChromeActive) {
                guard rootChromeActive, !Task.isCancelled else { return }
                let epoch = AccountStorage.generation
                loadWorkouts()
                await backend.syncLocalWorkouts(workouts)
                guard !Task.isCancelled, epoch == AccountStorage.generation else { return }
                await backend.fetchWorkouts()
                guard !Task.isCancelled, epoch == AccountStorage.generation else { return }
                mergeRemoteWorkouts()
            }
            .whisperRefreshable {
                let generation = AccountStorage.generation
                await backend.fetchMyPosts()
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await WhisperFollowService.shared.refresh() }
                    group.addTask { await WhisperBackendService.shared.fetchWorkouts() }
                    group.addTask { await WhisperStoryService.shared.fetch() }
                }
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                if tab == .replies { await reloadReplies() }
                if tab == .reposts { await reloadReposts() }
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                loadWorkouts()
                mergeRemoteWorkouts()
            }
            .task(id: "\(rootChromeActive)-\(tab.rawValue)-\(repostRevision)") {
                guard rootChromeActive else { return }
                if tab == .replies { await reloadReplies() }
                if tab == .reposts, !didLoadReposts { await reloadReposts() }
            }
            .onChange(of: reposts.repostedPostIDs) { _, ids in
                repostRows.removeAll { !ids.contains($0.id.lowercased()) }
            }
            .onChange(of: reposts.contentRevision) { _, _ in
                didLoadReposts = false; repostRevision += 1
            }
            .task {
                // Keep the switcher's stored session fresh while the profile is up.
                await WhisperAccountSwitcher.shared.rememberCurrent()
            }
            .onChange(of: bookmarks.bookmarkedPostIDs) { _, ids in
                bookmarkRows.removeAll { !ids.contains($0.id) }
                if activeSheet?.id == "saved" { Task { await reloadBookmarkRows() } }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .editProfile:
                    WhisperEditProfileView()
                        .whisperSheetBorder()
                case .saved:
                    savedPostsSheet
                        .whisperSheetBorder()
                case .followSuggestions:
                    WhisperFollowSuggestionsSheet()
                        .whisperSheetBorder()
                case .share:
                    WhisperShareSheet(username: displayUsername)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .whisperSheetBorder()
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
                        posterUsername: displayUsername,
                        isOwner: true,
                        onEdit: {
                            // Bounce from the lyrics sheet into the composer so
                            // the owner can edit the song / text right there.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                activeSheet = .thought
                            }
                        }
                    )
                    .presentationDetents([.height(360)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(22)
                    .whisperSheetBorder()
                case .composer:
                    WhisperComposerView()
                        .whisperSheetBorder()
                case .analytics:
                    WhisperAnalyticsView()
                        .whisperSheetBorder()
                case .accountSwitcher:
                    WhisperAccountSwitcherSheet()
                        .whisperSheetBorder()
                case .followList(let tab):
                    WhisperFollowListView(
                        userID: AccountStorage.currentUserID,
                        username: displayUsername,
                        initialTab: tab
                    )
                    .whisperSheetBorder()
                case .badgeInfo(let kind):
                    WhisperBadgeInfoSheet(highlight: kind)
                        .whisperSheetBorder()
                }
            }
            .fullScreenCover(item: $activeCover) { cover in
                switch cover {
                case .auth:
                    WhisperAuthSheet()
                case .storyComposer:
                    WhisperStoryComposerView()
                        .task { await stories.fetch() }
                case .waveCreate:
                    WhisperWaveCreateFlow()
                case .creatorStudio:
                    WhisperCreatorDashboardView()
                case .avatarZoom:
                    WhisperAvatarZoomView(
                        username: displayUsername,
                        imageURL: (users.displayProfile?.profile_image_url ?? auth.currentUser.profileImageURL).flatMap { URL(string: $0) }
                    )
                case .waves(let row):
                    // The user's own waves, opened ON the tapped one in the
                    // full-screen Waves player — the only format waves render in.
                    let pool = wavePosts.map { postFromRow($0) }
                    let start = postFromRow(row)
                    WhisperReelsPlayerView(reels: pool, start: start)
                case .myStory:
                    WhisperStoryViewer(stories: stories.myStories(), startIndex: 0)
                case .postDetail(let row):
                    // Same full-screen detail the feed opens — grid posts get
                    // the IG-style photo detail, text posts get the thread.
                    WhisperPostDetailView(post: postFromRow(row))
                }
            }
        }
    }

    // MARK: - Athlete perks

    // MARK: - Identity

    private var displayUsername: String {
        // Prefer the canonical whisper_profiles handle so the header never
        // falls back to @you when the local username cache is empty (e.g.
        // right after sign-in on a fresh device).
        users.displayProfile?.username
            ?? leaderboard.savedUsername
            ?? auth.currentUser.username
            ?? "you"
    }

    private var displayName: String {
        users.displayProfile?.display_name ?? auth.currentUser.displayName ?? displayUsername.capitalized
    }

    private var signInRequiredBanner: some View {
        Button {
            Haptics.tap()
            activeCover = .auth
        } label: {
            signInRequiredBannerContent
        }
        .buttonStyle(.plain)
    }

    private var signInRequiredBannerContent: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text("Sign in to post")
                    .font(.subheadline.weight(.bold))
                Text("Whisper needs a Supabase account to save posts, DMs, and likes.")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .foregroundStyle(WhisperTheme.ink(colorScheme))
        .padding(12)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
                .lineLimit(3)
            Spacer()
            Button {
                Haptics.tap()
                backend.lastError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.red)
        .padding(12)
        .background(Color.red.opacity(0.08), in: .rect(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    /// Only professional tools and settings float above the cover.
    /// Account switching belongs beside the name; story creation stays on the portrait.
    private var profileHeaderBar: some View {
        HStack(spacing: 8) {
                if let door = insightsDoor {
                    Button {
                        Haptics.tap()
                        switch door {
                        case .analytics: activeSheet = .analytics
                        case .creatorStudio: activeCover = .creatorStudio
                        }
                    } label: {
                        Image(systemName: door.icon)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .frame(width: 44, height: 44)
                            .modifier(WhisperControlGlass(shape: Circle()))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(door.title)
                }
                Spacer()
                Button {
                    openSettings()
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .frame(width: 44, height: 44)
                        .modifier(WhisperControlGlass(shape: Circle()))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
    }

    private var igHeader: some View {
        WhisperProfileIdentityView(displayName: displayName, username: displayUsername, onSwitchAccount: {
            Haptics.tap()
            activeSheet = .accountSwitcher
        }, biography: AnyView(bio)) {
            avatarStack
        } stats: {
            statsRow
        }
    }

    private var avatarStack: some View {
        // Always show the IG-Notes bubble so tapping it opens the composer.
        // Text is the user's active thought, or the kit's "Note..." ghost
        // prompt when nothing's been posted yet.
        let bubbleText = thoughts.isActive ? thoughts.displayText : "Note..."
        let hasStory = stories.meHasActiveStory
        return WhisperAvatarChrome(
            username: displayUsername,
            size: 144,
            storyRing: hasStory,
            ringTint: hasStory ? Color(red: 0.20, green: 0.55, blue: 1.0) : nil,
            plusButton: true,
            plusSymbol: "plus",
            plusDiameter: 32,
            thoughtText: bubbleText,
            thoughtStyle: thoughts.isActive ? thoughts.style : .plain,
            thoughtAccent: thoughts.isActive ? thoughts.accent : "",
            thoughtEmoji: thoughts.isActive ? thoughts.emoji : "",
            thoughtColorHex: thoughts.isActive ? thoughts.colorHex : "",
            bubbleScale: 1.18,
            reservesThoughtSpace: false,
            onPlusTap: { presentStoryPicker() },
            onBubbleTap: {
                if thoughts.isActive && thoughts.style == .music {
                    activeSheet = .lyrics
                } else {
                    activeSheet = .thought
                }
            }
        )
        .onTapGesture {
            if hasStory, let first = stories.myStories().first {
                Haptics.tap()
                activeCover = .myStory(first)
            } else {
                // No story to open — a tap lifts the profile picture onto the
                // full-screen zoom stage instead of doing nothing.
                Haptics.tap()
                activeCover = .avatarZoom
            }
        }
        // Long-press ALWAYS zooms the picture, story or not.
        .onLongPressGesture(minimumDuration: 0.35) {
            Haptics.tap()
            activeCover = .avatarZoom
        }
    }

    private func presentStoryPicker() {
        activeCover = .storyComposer
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell("followers", value: shortNumber(follows.followerCount)) {
                activeSheet = .followList(.followers)
            }
            statCell("posts", value: "\(myPosts.count)") {
                withAnimation(.whisperSnappy) { tab = .threads }
            }
            statCell("following", value: shortNumber(follows.followingCount)) {
                activeSheet = .followList(.following)
            }
        }
    }

    /// All posts the current user has shared, newest first. Pulled from
    /// `WhisperBackendService.myPosts` (a direct user_id query), with a
    /// fallback filter on the global feed cache so freshly-created posts
    /// always surface even before the next round-trip.
    private var myPosts: [WhisperPostRow] {
        let uid = AccountStorage.currentUserID
        var seen: Set<String> = []
        var out: [WhisperPostRow] = []
        for row in backend.myPosts where !backend.deletedPostIDs.contains(row.id.lowercased()) && seen.insert(row.id).inserted {
            out.append(row)
        }
        for row in backend.posts where row.user_id == uid && !backend.deletedPostIDs.contains(row.id.lowercased()) && seen.insert(row.id).inserted {
            out.append(row)
        }
        return out
    }

    private func statCell(_ label: String, value: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(alignment: .center, spacing: 3) {
                Text(value)
                    .font(.headline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text(label)
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func shortNumber(_ n: Int) -> String {
        switch n {
        case 0..<1_000:        return "\(n)"
        case 1_000..<1_000_000: return String(format: "%.1fK", Double(n) / 1_000.0)
        default:                return String(format: "%.1fM", Double(n) / 1_000_000.0)
        }
    }

    // MARK: - Bio (Instagram layout)

    /// The user's actual bio. Prefers the live `whisper_profiles.bio`, then
    /// the local cache (set during onboarding / edit-profile), then a friendly
    /// default so first-launch users still see meaningful text.
    private var bioText: String {
        if let server = users.displayProfile?.bio, !server.isEmpty { return server }
        let cached = AccountStorage.string(forKey: "whisper.bio") ?? ""
        if !cached.isEmpty { return cached }
        return "Quiet wins. Loud progress."
    }

    /// Kit 4.0 profile grammar — lifts the first URL out of the bio so it can
    /// render as the dedicated link row under the bio text.
    private func bioParts(_ raw: String) -> (text: String, url: URL?, label: String, extra: Int) {
        guard !raw.isEmpty else { return ("", nil, "", 0) }
        guard let range = raw.range(of: #"https?://\S+|www\.\S+"#, options: .regularExpression) else {
            return (raw, nil, "", 0)
        }
        let rawLink = String(raw[range])
        let normalized = rawLink.lowercased().hasPrefix("www.") ? "https://" + rawLink : rawLink
        let label = rawLink
            .replacingOccurrences(of: #"^https?://"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cleaned = raw.replacingCharacters(in: range, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Kit grammar: extra bio links collapse into "and N more".
        var extra = 0
        var rest = cleaned[...]
        while let r = rest.range(of: #"https?://\S+|www\.\S+"#, options: .regularExpression) {
            extra += 1
            rest = rest[r.upperBound...]
        }
        return (cleaned, URL(string: normalized), label, extra)
    }

    private var bio: some View {
        WhisperProfileBioView(text: bioText, category: users.displayProfile?.professional_category ?? "", interests: users.displayProfile?.interests ?? [])
    }

    private var legacyBio: some View {
        let parts = bioParts(bioText)
        let niche: String = users.displayProfile?.professional_category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return VStack(alignment: .leading, spacing: 5) {
            // The creator niche / professional category — the light-gray line
            // UNDER THE AVATAR, right above the bio (the web profile's grammar).
            if !niche.isEmpty {
                Text(niche)
                    .font(.footnote)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(1)
            }
            if !parts.text.isEmpty {
                Text(parts.text)
                    .font(.subheadline)
                    .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.9))
            }
            // Kit 4.0 link row — chain glyph + domain in ink, semibold (the
            // real Figma file renders it #0C1014, not link blue).
            if let url = parts.url {
                Link(destination: url) {
                    HStack(spacing: 5) {
                        Image(systemName: "link")
                            .font(.caption.weight(.bold))
                        Text(parts.extra > 0 ? "\(parts.label) and \(parts.extra) more" : parts.label)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Action row (3 buttons IG-style)

    private var actionRow: some View {
        HStack(spacing: 6) {
            actionButton("Edit profile") {
                activeSheet = .editProfile
            }
            actionButton("Create post") {
                activeSheet = .composer
            }
            Button {
                Haptics.tap()
                activeSheet = .followSuggestions
            } label: {
                Image(systemName: "person.badge.plus")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .frame(width: 44, height: 44)
                    .modifier(WhisperControlGlass(shape: Circle()))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    private func actionButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(label)
        }
        .buttonStyle(WhisperFlatProfileButtonStyle())
    }

    // MARK: - Tab bar + content

    // MARK: - Threads-style tabs

    /// Threads-style tab strip: four text labels with an animated underline
    /// on the active tab. Replaces the old IG icon strip.
    private var threadsTabBar: some View {
        WhisperProfileTabsView(selection: $tab)
    }

    /// Posts surfaced for the active tab. Waves render ONLY in the Waves
    /// grid — never in Whisps or Media.
    @ViewBuilder
    private var threadsTabContent: some View {
        if (tab == .threads || tab == .waves || tab == .media), backend.myPosts.isEmpty,
           backend.myPostsLoadedGeneration != AccountStorage.generation, backend.isSignedInRemotely {
            if let error = backend.myPostsLoadError {
                VStack(spacing: 12) {
                    Text(error).font(.subheadline).multilineTextAlignment(.center)
                    Button("Try again") { Task { await backend.fetchMyPosts() } }.frame(minHeight: 44)
                }.padding(24)
            } else {
                ProgressView("Loading your posts…").frame(maxWidth: .infinity).padding(32)
            }
        } else {
            switch tab {
            case .threads: threadsListContent(rows: threadsTabRows, emptyTitle: "No whisps yet", emptyMessage: "Tap the + button at the top to share your first whisp.", emptyIcon: "text.bubble")
            case .waves:   wavesContent
            case .replies: repliesTabContent
            case .reposts: repostsTabContent
            case .media:   gridContent
            }
        }
    }

    /// The WAVES grid — 3-column 9:16 tiles, tap opens the full-screen
    /// Waves player on that wave with the rest of your waves queued behind.
    @ViewBuilder
    private var wavesContent: some View {
        let columns = [
            GridItem(.flexible(), spacing: 2),
            GridItem(.flexible(), spacing: 2),
            GridItem(.flexible(), spacing: 2)
        ]
        if wavePosts.isEmpty {
            WhisperProfileEmptyState(
                illustration: .waves, title: "No waves yet",
                message: "Short videos you post land here, in the Waves format. Record one and it shows up on this tab — nowhere else.",
                actionTitle: "Make a wave",
                action: { activeCover = .waveCreate }
            )
            .padding(.horizontal, 16)
            .padding(.top, 24)
        } else {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(wavePosts) { row in
                    Button {
                        Haptics.tap()
                        activeCover = .waves(row)
                    } label: {
                        WhisperWaveGridTile(row: row)
                    }
                    .buttonStyle(GridCellPressStyle())
                }
            }
        }
    }

    @ViewBuilder
    private var gridContent: some View {
        let columns = [
            GridItem(.flexible(), spacing: 3),
            GridItem(.flexible(), spacing: 3),
            GridItem(.flexible(), spacing: 3)
        ]
        VStack(spacing: 12) {
            if gridTabRows.isEmpty {
                WhisperProfileEmptyState(
                    title: canPostGrid ? "Your grid starts here" : "No media yet",
                    message: canPostGrid
                        ? "Share your first photo or video — gym shots, meals, race day. It all lives here."
                        : "Photos and videos attached to your whisps show up here. Waves have their own tab.",
                    actionTitle: canPostGrid ? "Share your first post" : "Share a whisp with a photo",
                    action: { activeSheet = .composer }
                )
                .padding(.horizontal, 16)
                .padding(.top, 24)
            } else {
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(gridTabRows) { row in
                        gridCell(row)
                    }
                }
            }
        }
    }

    private func gridCell(_ row: WhisperPostRow) -> some View {
        Button { Haptics.tap(); activeCover = .postDetail(row) } label: {
            WhisperProfileMediaTile(row: row)
        }
        .buttonStyle(GridCellPressStyle())
        .contextMenu {
            Button("Open post", systemImage: "arrow.up.right.square") { activeCover = .postDetail(row) }
        } preview: {
            ScrollView {
                WhisperPostCard(post: postFromRow(row), onOpenDiscussion: { _ in }, isPreview: true)
                    .environment(\.whisperMediaActive, false)
            }
            .frame(width: 340, height: 560)
        }
    }

    private func legacyGridCell(_ row: WhisperPostRow) -> some View {
        let url = row.media_urls?.first.flatMap { URL(string: $0) }
        let photoCount = row.media_urls?.count ?? 0
        let likes = row.likes_count ?? 0
        let comments = row.comments_count ?? 0
        return Button {
            Haptics.tap()
            activeCover = .postDetail(row)
        } label: {
            WhisperTheme.card(colorScheme)
                .overlay {
                    if let url = url {
                        WhisperCachedAsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().aspectRatio(contentMode: .fill)
                            default:
                                EmptyView()
                            }
                        }
                    }
                }
                .aspectRatio(1, contentMode: .fill)
                .clipped()
                // Soft scrim so the engagement preview stays legible.
                .overlay(alignment: .bottom) {
                    if likes > 0 || comments > 0 {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 44)
                        .allowsHitTesting(false)
                    }
                }
                // Like/comment counts — Instagram-style engagement preview.
                .overlay(alignment: .bottomLeading) {
                    if likes > 0 || comments > 0 {
                        HStack(spacing: 8) {
                            if likes > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "heart.fill")
                                        .font(.system(size: 9, weight: .bold))
                                    Text(compactCount(likes))
                                        .font(.system(size: 10, weight: .heavy))
                                }
                            }
                            if comments > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "bubble.right.fill")
                                        .font(.system(size: 9, weight: .bold))
                                    Text(compactCount(comments))
                                        .font(.system(size: 10, weight: .heavy))
                                }
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(6)
                        .allowsHitTesting(false)
                    }
                }
                // Multi-photo indicator, top-right — like IG's stacked squares.
                .overlay(alignment: .topTrailing) {
                    if photoCount > 1 {
                        Image(systemName: "square.fill.on.square.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                            .padding(6)
                            .allowsHitTesting(false)
                    }
                }
        }
        .buttonStyle(GridCellPressStyle())
        // Long-press peek — flips through the whole set without opening it.
        .contextMenu {
            Button {
                Haptics.tap()
                activeCover = .postDetail(row)
            } label: {
                Label("Open post", systemImage: "arrow.up.right.square")
            }
        } preview: {
            WhisperGridPostPeek(
                urls: (row.media_urls ?? []).compactMap { URL(string: $0) },
                caption: row.caption,
                likes: row.likes_count ?? 0,
                comments: row.comments_count ?? 0
            )
        }
    }

    /// Compact count formatting for grid tile previews (1.2K, 3.4M).
    private func compactCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    /// Everything that is NOT a wave — whisps, media posts, grid posts.
    private var nonWavePosts: [WhisperPostRow] {
        myPosts.filter { $0.is_reel != true }
    }

    /// Waves only — the Waves tab's pool.
    private var wavePosts: [WhisperPostRow] {
        myPosts.filter { $0.is_reel == true }
    }

    private var gridTabRows: [WhisperPostRow] {
        nonWavePosts.filter { ($0.media_urls?.isEmpty == false) }
    }

    @ViewBuilder
    private var repostsTabContent: some View {
        if (loadingReposts || !didLoadReposts) && repostRows.isEmpty && repostLoadError == nil {
            ProgressView()
                .tint(WhisperTheme.ink(colorScheme))
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
        } else if let repostLoadError, repostRows.isEmpty {
            VStack(spacing: 12) {
                Text(repostLoadError).font(.subheadline).foregroundStyle(.secondary)
                Button("Try again") { didLoadReposts = false; repostLoadErrorReset() }
                    .frame(minHeight: 44)
            }.padding(24)
        } else if repostRows.isEmpty {
            WhisperEmptyState(
                icon: "arrow.2.squarepath",
                title: "No reposts yet",
                message: "Tap the repost icon under any post to share it on your profile."
            )
            .padding(.horizontal, 16)
            .padding(.top, 24)
        } else {
            threadsListContent(
                rows: repostRows,
                emptyTitle: "No reposts yet",
                emptyMessage: "Tap the repost icon under any post to share it on your profile.",
                emptyIcon: "arrow.2.squarepath"
            )
        }
    }

    /// Sheet shown when the user taps "Saved posts" inside the hamburger
    /// menu. Reuses the same bookmark UI that used to live as the Saved
    /// tab on the profile.
    private var savedPostsSheet: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    // Instagram's Saved: collections as mosaic tiles (All posts
                    // first), a tap unrolls one into its grid.
                    WhisperSavedCollectionsView(
                        rows: bookmarkRows,
                        loading: loadingBookmarks,
                        onOpen: { row in activeCover = .postDetail(row) }
                    )
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Saved")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { activeSheet = nil }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            .task {
                let generation = AccountStorage.generation
                await bookmarks.refresh()
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                await reloadBookmarkRows()
            }
        }
    }

    private func repostLoadErrorReset() { repostLoadError = nil; repostRevision += 1 }

    private func reloadReposts() async {
        let request = UUID(); repostRequestID = request
        let generation = AccountStorage.generation
        let owner = AccountStorage.currentUserID
        loadingReposts = true; repostLoadError = nil
        defer { if repostRequestID == request { loadingReposts = false } }
        do {
            let rows = try await reposts.fetchPublicReposts(userID: owner, limit: 200)
            let allowed = try await WhisperPostVisibilityService.visible(rows)
            guard !Task.isCancelled, request == repostRequestID, generation == AccountStorage.generation else { return }
            repostRows = allowed.filter { reposts.isReposted($0.id) }; didLoadReposts = true
        } catch {
            guard !Task.isCancelled, request == repostRequestID, generation == AccountStorage.generation else { return }
            repostLoadError = "Couldn't load reposts. Please try again."
        }
    }

    /// Pinned post IDs surfaced at the top of the threads tab (verified perk).
    private var pinnedPostIDs: [String] {
        guard WhisperVerifiedPerks.isVerified(username: displayUsername) else { return [] }
        return verifiedPerks.pinnedPostIDs(forUserID: AccountStorage.currentUserID)
    }

    /// Reorders `myPosts` so any pinned posts float to the top in their
    /// configured order. Non-pinned posts keep their newest-first ordering.
    private func applyingPins(_ rows: [WhisperPostRow]) -> [WhisperPostRow] {
        let ids = pinnedPostIDs
        guard !ids.isEmpty else { return rows }
        let lookup = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        var pinned: [WhisperPostRow] = []
        for id in ids { if let r = lookup[id] { pinned.append(r) } }
        let pinnedSet = Set(pinned.map { $0.id })
        let rest = rows.filter { !pinnedSet.contains($0.id) }
        return pinned + rest
    }

    private var threadsTabRows: [WhisperPostRow] { applyingPins(nonWavePosts) }
    private var mediaTabRows: [WhisperPostRow] {
        nonWavePosts.filter { ($0.media_urls?.isEmpty == false) }
    }

    /// Renders posts I've replied to, with my reply quoted underneath
    /// (Threads-style "Replies" tab).
    @ViewBuilder
    private var repliesTabContent: some View {
        if loadingReplies && repliedPairs.isEmpty {
            ProgressView()
                .tint(WhisperTheme.ink(colorScheme))
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
        } else if repliedPairs.isEmpty {
            WhisperEmptyState(
                icon: "bubble.left.and.bubble.right",
                title: "No replies yet",
                message: "When you reply to someone's post, it will show up here with your reply."
            )
            .padding(.horizontal, 16)
            .padding(.top, 24)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(repliedPairs.enumerated()), id: \.element.id) { idx, pair in
                    VStack(spacing: 0) {
                        WhisperPostCard(post: postFromRow(pair.post))
                        myReplyRow(pair.myComment)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 12)
                    }
                    if idx < repliedPairs.count - 1 {
                        Divider().background(WhisperTheme.hairline(colorScheme))
                    }
                }
            }
        }
    }

    /// Threads-style "my reply" row that sits underneath the original post.
    private func myReplyRow(_ c: WhisperCommentRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            WhisperAvatar(username: c.username, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(c.username)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("replied")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                    Spacer(minLength: 0)
                    if let likes = c.likes_count, likes > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 9, weight: .semibold))
                            Text(likes.formatted())
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                }
                WhisperCommentBodyView(text: c.body)
            }
        }
        .padding(10)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
        }
    }

    private func reloadReplies() async {
        let generation = AccountStorage.generation
        let requestID = UUID()
        repliesRequestID = requestID
        loadingReplies = true
        defer { if generation == AccountStorage.generation, repliesRequestID == requestID { loadingReplies = false } }
        let pairs = await backend.fetchPostsIRepliedTo()
        guard !Task.isCancelled, generation == AccountStorage.generation, repliesRequestID == requestID else { return }
        repliedPairs = pairs.map { WhisperReplyPair(post: $0.post, myComment: $0.myComment) }
        loadingReplies = false
    }

    @ViewBuilder
    private func threadsListContent(
        rows: [WhisperPostRow],
        emptyTitle: String,
        emptyMessage: String,
        emptyIcon: String
    ) -> some View {
        if rows.isEmpty {
            WhisperEmptyState(icon: emptyIcon, title: emptyTitle, message: emptyMessage)
                .padding(.horizontal, 16)
                .padding(.top, 24)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    if tab == .threads && verifiedPerks.isPinned(postID: row.id) {
                        WhisperPinnedPostLabel()
                    }
                    WhisperPostCard(post: postFromRow(row))
                    if idx < rows.count - 1 {
                        Divider().background(WhisperTheme.hairline(colorScheme))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var bookmarksContent: some View {
        let columns = [
            GridItem(.flexible(), spacing: 3),
            GridItem(.flexible(), spacing: 3),
            GridItem(.flexible(), spacing: 3)
        ]
        if loadingBookmarks && bookmarkRows.isEmpty {
            ProgressView()
                .tint(WhisperTheme.ink(colorScheme))
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
        } else if bookmarkRows.isEmpty {
            WhisperEmptyState(
                icon: "bookmark",
                title: "No saved posts yet",
                message: "Tap the bookmark icon under any post to save it here. Only you can see your saved posts."
            )
            .padding(.horizontal, 16)
        } else {
            VStack(spacing: 10) {
                bookmarkCategoryChips
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(filteredBookmarkRows, id: \.id) { row in
                        Button {
                            Haptics.tap()
                            activeCover = .postDetail(row)
                        } label: {
                            gridCell(for: row)
                                .contextMenu {
                                    bookmarkCategoryMenu(for: row.id)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Horizontal pill row letting the user filter bookmarks by category,
    /// plus a `+` to add a new one. "All" is always pinned first.
    private var bookmarkCategoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(bookmarks.categories, id: \.self) { name in
                    Button {
                        Haptics.tap()
                        withAnimation(.whisperSnappy) {
                            selectedBookmarkCategory = name
                        }
                    } label: {
                        Text(name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selectedBookmarkCategory == name ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                selectedBookmarkCategory == name ? WhisperTheme.ink(colorScheme) : WhisperTheme.card(colorScheme),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: selectedBookmarkCategory == name ? 0 : 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if name != "All" {
                            Button(role: .destructive) {
                                bookmarks.removeCategory(name)
                                if selectedBookmarkCategory == name {
                                    selectedBookmarkCategory = "All"
                                }
                            } label: {
                                Label("Delete folder", systemImage: "trash")
                            }
                        }
                    }
                }
                Button {
                    Haptics.tap()
                    newCategoryName = ""
                    presentNewCategoryAlert = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                        Text("New")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(WhisperTheme.card(colorScheme), in: Capsule())
                    .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
        .alert("New folder", isPresented: $presentNewCategoryAlert) {
            TextField("Folder name", text: $newCategoryName)
            Button("Add") {
                let n = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !n.isEmpty {
                    bookmarks.addCategory(n)
                    selectedBookmarkCategory = n
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Organize your saved posts into a folder — only you can see it.")
        }
    }

    @ViewBuilder
    private func bookmarkCategoryMenu(for postID: String) -> some View {
        Section("Move to folder") {
            ForEach(bookmarks.categories, id: \.self) { name in
                Button {
                    bookmarks.setCategory(name, forPostID: postID)
                    Haptics.tap()
                } label: {
                    Label(name, systemImage: bookmarks.category(forPostID: postID) == name ? "checkmark" : "folder")
                }
            }
        }
    }

    /// Bookmarks filtered by the active category. "All" shows everything.
    private var filteredBookmarkRows: [WhisperPostRow] {
        let cat = selectedBookmarkCategory
        if cat == "All" { return bookmarkRows }
        return bookmarkRows.filter { bookmarks.category(forPostID: $0.id) == cat }
    }

    private func reloadBookmarkRows() async {
        let generation = AccountStorage.generation
        let requestID = UUID()
        bookmarkRequestID = requestID
        loadingBookmarks = true
        defer { if generation == AccountStorage.generation, bookmarkRequestID == requestID { loadingBookmarks = false } }
        let rows = await bookmarks.fetchBookmarkedPosts()
        guard !Task.isCancelled, generation == AccountStorage.generation, bookmarkRequestID == requestID else { return }
        bookmarkRows = rows
        loadingBookmarks = false
    }

    private func postFromRow(_ row: WhisperPostRow) -> WhisperPost {
        let urls: [URL] = (row.media_urls ?? []).compactMap { URL(string: $0) }
        return WhisperPost(
            id: UUID(uuidString: row.id) ?? UUID(),
            username: row.username ?? displayUsername,
            timeAgo: WhisperPost.relativeTime(from: row.created_at),
            kind: WhisperPostKind(rawValue: row.kind ?? "") ?? .photo,
            caption: row.caption,
            symbol: row.symbol ?? WhisperPostKind(rawValue: row.kind ?? "")?.icon ?? "sparkles",
            accent: WhisperPost.color(fromHex: row.accent_hex) ?? Color.gray,
            mediaURLs: urls,
            likes: row.likes_count ?? 0,
            comments: row.comments_count ?? 0,
            liked: backend.myLikedPostIDs.contains(row.id),
            isReel: row.is_reel ?? false,
            createdAt: WhisperBackendService.parseISO(row.created_at)
        )
    }

    @ViewBuilder
    private func gridCell(for row: WhisperPostRow) -> some View {
        let accent = WhisperPost.color(fromHex: row.accent_hex) ?? Color.gray
        let symbol = row.symbol ?? (WhisperPostKind(rawValue: row.kind ?? "")?.icon ?? "sparkles")
        let firstURL = (row.media_urls ?? []).first.flatMap { URL(string: $0) }
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let url = firstURL {
                    WhisperCachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            LinearGradient(
                                colors: [accent.opacity(0.95), accent.opacity(0.55)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                    }
                    .allowsHitTesting(false)
                } else {
                    LinearGradient(
                        colors: [accent.opacity(0.95), accent.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay {
                        Image(systemName: symbol)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if (row.media_urls?.count ?? 0) > 1 {
                    Image(systemName: "square.on.square")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .shadow(radius: 1)
                        .padding(6)
                }
            }
            .clipped()
            .contentShape(.rect)
    }

    // MARK: - Data

    private func loadWorkouts() {
        guard let data = AccountStorage.data(forKey: "workoutSessionHistory"),
              let decoded = try? JSONDecoder().decode([WorkoutSessionRecord].self, from: data) else {
            workouts = []
            return
        }
        workouts = decoded.sorted { $0.date > $1.date }
    }

    /// Merge any remote-only workouts (logged on another device) into the
    /// profile's workouts list so the count reflects every signed-in device.
    private func mergeRemoteWorkouts() {
        let known = Set(workouts.map { $0.id.uuidString })
        let iso = ISO8601DateFormatter()
        for row in backend.workouts where !known.contains(row.id) {
            guard let id = UUID(uuidString: row.id),
                  let date = iso.date(from: row.performed_at) else { continue }
            workouts.append(
                WorkoutSessionRecord(
                    id: id,
                    programId: UUID(),
                    dayName: row.display_name,
                    focus: row.focus,
                    date: date,
                    duration: TimeInterval(row.duration_seconds),
                    exercises: [],
                    averageHeartRate: 0,
                    peakHeartRate: 0,
                    heartRateTimeline: [],
                    caloriesBurned: Double(row.calories),
                    avgOxygenSaturation: 0,
                    customName: nil
                )
            )
        }
        workouts.sort { $0.date > $1.date }
    }

    var body: some View {
        mainContent
    }
}
