import SwiftUI
import PhotosUI

/// Whisper feed shell. Inline carousels (stories, reels, suggestions) have
/// been extracted into dedicated views (`FeedStoriesStrip`,
/// `FeedReelsCarousel`, `FeedSuggestionsCarousel`) so each one recomposes
/// independently as its data source changes instead of rebuilding the
/// entire feed on every update.
struct WhisperFeedView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.whisperRootChromeActive) private var rootChromeActive
    @Binding var presentComposer: Bool
    @Binding var presentInbox: Bool
    var isActive: Bool = true
    var scrollToTopRequest: UUID? = nil
    @State private var scrollPosition: ScrollPosition = ScrollPosition(edge: .top)
    @Environment(\.whisperHeaderShelf) private var headerShelf
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var feedViewportWidth: CGFloat = 390
    @Environment(\.scenePhase) private var scenePhase
    @State private var feedIsVisible: Bool = false
    @State private var feedEndVisible: Bool = false
    @State private var storyRailHeight: CGFloat = 140

    private var feedMediaActive: Bool {
        isActive && feedIsVisible && storyReveal == 0 && scenePhase == .active
            && !presentComposer && !presentInbox && openStory == nil && openReel == nil
            && openUser == nil && openLiveRoom == nil && !presentLive && !presentFindFriends
            && !presentWaveCreate && !presentArticles
    }

    // Only real backend posts are surfaced now — fake fixtures have been
    // retired so the feed never shows demo content over real users' posts.
    @State private var projection: WhisperFeedProjection = WhisperFeedProjection()
    @State private var imagePrefetcher: WhisperFeedImagePrefetcher = WhisperFeedImagePrefetcher()
    @State private var frozenShelfSlots: [UUID: Set<String>]? = nil
    @State private var frozenAds: [WhisperServedAd]? = nil
    private var posts: [WhisperPost] { projection.posts }
    @State private var storyCaptureBusy: Bool = false
    @State private var storyHasUnsavedLayout: Bool = false
    @State private var storyCloseRequest: Int = 0
    /// Kit "For you ⌄" header scope — "foryou" (ranked) or "following".
    @AppStorage("whisper.feed.scope") private var feedScope: String = "foryou"
    @State private var thoughts = WhisperThoughtService.shared
    @State private var backend = WhisperBackendService.shared
    @State private var moderation = WhisperModerationService.shared
    @State private var storyService = WhisperStoryService.shared
    @State private var follows = WhisperFollowService.shared
    @State private var openStory: WhisperStoryRow?
    @State private var storyPickerItem: PhotosPickerItem?
    @State private var suggestedUsers: [WhisperUserRow] = []
    @State private var coachPool: [WhisperUserRow] = []
    @State private var openUser: WhisperUserRow?
    @State private var dearEmber = WhisperDearEmberService.shared
    @State private var presentFindFriends: Bool = false
    @State private var openReel: WhisperPost?
    @State private var presentLive: Bool = false
    @State private var openLiveRoom: WhisperLiveRoom? = nil
    /// Creator-post doors behind THE CREATOR MARK in the composer row.
    @State private var presentWaveCreate: Bool = false
    @State private var presentArticles: Bool = false
    @State private var activitySvc = WhisperActivityService.shared
    @State private var mentionsSvc = WhisperMentionsService.shared
    @State private var storyRespSvc = WhisperStoryResponseService.shared
    @State private var followRequestsSvc = WhisperFollowRequestService.shared
    @State private var articlesSvc = WhisperArticlesService.shared
    @State private var feedAds: WhisperFeedAdService = WhisperFeedAdService()

    /// Unread count for the bell badge — combines new likes/comments/follows
    /// (activity), `@you` tags, poll/slider/question replies to your
    /// stories, and pending follow requests so every notification surface
    /// is reflected in one number.
    private var bellUnreadCount: Int {
        activitySvc.unreadCount + mentionsSvc.unreadCount + storyRespSvc.unreadCount
            + followRequestsSvc.pendingIncomingCount
    }

    /// Cadence (in posts) between interspersed carousels. A Facebook-style
    /// rectangular stories strip slots in after every 13 posts (within the
    /// 12–15 sweet spot) so it feels like a meaningful break, and a
    /// suggestions carousel after every 6.
    private let storiesCarouselEvery: Int = 13
    private let suggestionsEvery: Int = 6
    /// Cadence for the Instagram-style reels break — a horizontal reels
    /// shelf slots in after every 9 posts (offset from the stories and
    /// suggestions cadences so the breaks rarely stack).
    private let reelsBreakEvery: Int = 9
    /// "Coaches to hire" shelf cadence — offset from every other break so
    /// two rails never stack on the same post.
    private let coachesBreakEvery: Int = 10
    /// The journal shelf surfaces once, near the top of the feed, so
    /// long-form writing from the Whisper team gets seen without dominating.
    private let articlesBreakEvery: Int = 4
    /// True until the first-paint fetch lands — drives the shimmer
    /// skeletons so a cold start never shows a blank feed or a bare spinner.
    @State private var initialFeedLoad: Bool = true
    /// Entrance animation flag for the blank-feed illustration.
    @State private var starterAppeared: Bool = false

    // THE STORY COMPOSER AS THE LAYER BEHIND THE FEED. Instagram's grammar:
    // swipe RIGHT on the feed and the feed card follows your finger off to
    // the right, uncovering the story camera underneath. `storyReveal` is 0
    // (feed parked) → 1 (composer fully shown); the composer mounts lazily
    // on the first drag so the camera never runs while the feed is idle.
    // Same card mechanics as the profile's settings back sheet.
    @State private var storyReveal: CGFloat = 0
    @State private var storyMounted: Bool = false
    @State private var isDraggingStory: Bool = false
    @State private var storyDragBase: CGFloat = 0
    /// Gesture-owned drag flag — SwiftUI resets it when a drag is CANCELLED
    /// (a hit-test or identity change mid-drag), which never calls onEnded.
    /// Watching it lets a cancelled slide settle instead of freezing half open.
    @GestureState private var storyDragActive: Bool = false

    var body: some View {
        GeometryReader { geo in
            let width: CGFloat = max(geo.size.width, 1)
            ZStack {
                WhisperTheme.surface(colorScheme)
                    .contentShape(.rect)
                    // THE ESCAPE HATCH — if the layer above ever fails to paint
                    // or take touches while the card is off-screen, a tap on
                    // the bare surface brings the feed back. Nothing can strand
                    // the user on a blank screen.
                    .onTapGesture {
                        guard storyReveal > 0.5, !isDraggingStory else { return }
                        closeStoryComposer()
                    }
                // Mount the layer whenever the card is off its parking spot —
                // a revealed card over an unmounted layer was the blank screen
                // with nothing to tap.
                if storyMounted || storyReveal > 0.001 {
                    storyBackLayer(width: width, safeTop: WhisperSafeArea.top, safeBottom: WhisperTabBarMetrics.windowBottomInset)
                        .frame(width: width, height: geo.size.height)
                        .transition(.identity)
                        .zIndex(1)
                }
                feedCard(width: width, viewportHeight: geo.size.height)
                    .frame(width: width, height: geo.size.height)
                    .zIndex(2)
            }
            .frame(width: width, height: geo.size.height)
            .clipped()
            .onChange(of: width, initial: true) { _, value in
                feedViewportWidth = value
                updateImageLookAhead()
            }
        }
        .ignoresSafeArea()
        .onChange(of: isActive) { _, active in
            if !active, storyMounted, !storyCaptureBusy, !storyHasUnsavedLayout { closeStoryComposer() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .whisperAccountSwitched)) { _ in
            closeStoryComposer()
            imagePrefetcher.stop()
            imagePrefetcher.visiblePostIDs = []
            frozenShelfSlots = nil
            frozenAds = nil
            feedAds.resetForCurrentAccount()
            Task { await feedAds.refresh(force: true) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, isDraggingStory {
                isDraggingStory = false
                settleStory(toRevealed: storyReveal > 0.42)
            }
        }
        .onChange(of: storyDragActive) { _, active in
            // The system cancelled the drag (no onEnded) — settle wherever
            // the card is instead of leaving it stuck with nothing tappable.
            guard !active, isDraggingStory else { return }
            isDraggingStory = false
            settleStory(toRevealed: storyReveal > 0.42)
        }
    }

    /// The story composer rendered as the layer behind the feed card — REAL
    /// frames (no transforms on the camera view), with a scrim that lifts as
    /// the card slides away. Closing routes back through the slide, and a
    /// right-edge strip that's ALWAYS mounted drags the feed back over it.
    private func storyBackLayer(width: CGFloat, safeTop: CGFloat, safeBottom: CGFloat) -> some View {
        let reveal: CGFloat = storyReveal
        return ZStack(alignment: .trailing) {
            WhisperStoryComposerView(onClose: { closeStoryComposer() }, isActive: isActive && storyReveal > 0.001, onCaptureBusyChanged: { storyCaptureBusy = $0 }, closeRequest: storyCloseRequest, onLayoutDirtyChanged: { storyHasUnsavedLayout = $0 })
                .task { await storyService.fetch() }
                // The feed ignores the safe area, so hand the composer its
                // real insets back — otherwise its ✕ and shutter sat under
                // the Dynamic Island and the home indicator. The bottom inset
                // is the HOME INDICATOR only — the tab bar is hidden while
                // the camera is up, so its height must not pad the shutter.
                .safeAreaPadding(.top, safeTop)
                .safeAreaPadding(.bottom, min(safeBottom, WhisperTabBarMetrics.windowBottomInset))
                .frame(width: width)
                // Past halfway the card is mostly gone — the composer takes
                // touches so ✕ is reachable even if the settle spring is
                // still finishing.
                .allowsHitTesting(reveal > 0.5 && !isDraggingStory)
            Color.black
                .opacity(Double(0.30 * (1 - reveal)))
                .allowsHitTesting(false)
            // THE WAY BACK — drag the feed back over the camera from the right
            // edge. Mounted for the whole life of the layer (a strip that only
            // exists while revealed would be removed by the first frame of the
            // drag and cancel it).
            Color.clear
                .frame(width: 30)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(storyReturnDrag(width: width))
                .allowsHitTesting(!storyCaptureBusy && (isDraggingStory || reveal > 0.5))
        }
    }

    /// A leftward drag from the story layer's right edge brings the feed
    /// card back; release settles by the predicted end point.
    private func storyReturnDrag(width: CGFloat) -> some Gesture {
        let travel: CGFloat = max(width, 1)
        return DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .updating($storyDragActive) { _, state, _ in state = true }
            .onChanged { value in
                guard !storyCaptureBusy, !storyHasUnsavedLayout else { return }
                if !isDraggingStory {
                    isDraggingStory = true
                    storyDragBase = storyReveal
                }
                storyReveal = min(1, max(0, storyDragBase + value.translation.width / travel))
            }
            .onEnded { value in
                if storyHasUnsavedLayout {
                    if value.translation.width < -24 { storyCloseRequest &+= 1 }
                    return
                }
                guard isDraggingStory else { return }
                isDraggingStory = false
                let predicted: CGFloat = storyDragBase + (value.predictedEndTranslation.width / travel)
                settleStory(toRevealed: predicted > 0.58)
            }
    }

    /// The feed as the front card: rounded to the device corners while it
    /// travels right, a soft edge shadow, offset by the reveal.
    private func feedCard(width: CGFloat, viewportHeight: CGFloat) -> some View {
        let reveal: CGFloat = storyReveal
        let radius = WhisperBackRevealStyle.radius(topInset: WhisperSafeArea.top, progress: reveal)
        return ZStack {
            if reveal > 0.001 {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.black)
                    .shadow(color: .black.opacity(Double(0.34 * min(1, reveal * 4))), radius: 28, x: -10, y: 0)
            }
            feedStack(viewportHeight: viewportHeight)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .offset(x: width * reveal)
        // Hit testing must NOT flip while the finger is down — the drag lives
        // on the feed's own scroll view, and turning it off mid-gesture
        // cancels the drag with no onEnded (the card froze half open). It
        // only lets go once the card has settled off-screen.
        .allowsHitTesting(isDraggingStory || reveal < 0.5)
    }

    /// The device's display corner radius (heuristic from the top inset).
    private var deviceCornerRadius: CGFloat {
        let top: CGFloat = WhisperSafeArea.top
        if top >= 59 { return 55 }
        if top >= 47 { return 47 }
        if top > 24 { return 41 }
        return 18
    }

    /// Opens the story composer with the card slide (the "+" story bubbles
    /// and the swipe both land here).
    private func openStoryComposer() {
        storyMounted = true
        isDraggingStory = false
        WhisperTabBarVisibility.shared.lockHidden()
        Haptics.tap()
        withAnimation(.spring(response: 0.46, dampingFraction: 0.88)) {
            storyReveal = 1
        }
    }

    private func closeStoryComposer() {
        storyCaptureBusy = false; storyHasUnsavedLayout = false
        isDraggingStory = false
        WhisperTabBarVisibility.shared.unlock()
        withAnimation(.spring(response: 0.46, dampingFraction: 0.88)) {
            storyReveal = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            if storyReveal == 0, !isDraggingStory { storyMounted = false }
        }
    }

    private func settleStory(toRevealed revealed: Bool) {
        print("[StoryLayer] settle revealed=\(revealed) mounted=\(storyMounted)")
        isDraggingStory = false
        if revealed {
            Haptics.tap()
            WhisperTabBarVisibility.shared.lockHidden()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                storyReveal = 1
            }
        } else {
            closeStoryComposer()
        }
    }

    /// Only a rightward drag starting in the leftmost 24pt opens stories. A horizontal drag
    /// engages the reveal and the card follows the finger; release settles
    /// on the nearer side using the predicted end point. Vertical scrolling
    /// is untouched — the drag only engages when it's clearly horizontal.
    private var storyRevealDrag: some Gesture {
        let travel: CGFloat = max(UIScreen.main.bounds.width, 1)
        return DragGesture(minimumDistance: 22, coordinateSpace: .global)
            .updating($storyDragActive) { _, state, _ in state = true }
            .onChanged { value in
                let dx: CGFloat = value.translation.width
                let dy: CGFloat = value.translation.height
                if !isDraggingStory {
                    guard openStory == nil, openReel == nil, !presentLive, !presentWaveCreate, !presentArticles else { return }
                    guard value.startLocation.x <= 24,
                          abs(dx) > abs(dy) * 1.6, dx > 0 else { return }
                    isDraggingStory = true
                    storyMounted = true
                    // The camera is a full-screen surface — the tab bar slides
                    // away with the card and comes back when it parks.
                    WhisperTabBarVisibility.shared.lockHidden()
                    storyDragBase = storyReveal
                }
                let progress: CGFloat = storyDragBase + (dx / travel)
                storyReveal = min(1, max(0, progress))
            }
            .onEnded { value in
                guard isDraggingStory else { return }
                isDraggingStory = false
                let predicted: CGFloat = storyDragBase + (value.predictedEndTranslation.width / travel)
                settleStory(toRevealed: predicted > 0.42)
            }
    }

    private func feedStack(viewportHeight: CGFloat) -> some View {
        let feedStream = self.feedStream
        let reelsPool = self.reelsPool
        let inlineStoryGroups = self.inlineStoryGroups
        return NavigationStack {
            ZStack {
                WhisperTheme.card(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        FeedStoriesStrip(
                            storyService: storyService,
                            onCreateStory: { openStoryComposer() },
                            onOpenStory: { openStory = $0 },
                            onOpenMyStories: {
                                if let first = storyService.myStories().first {
                                    openStory = first
                                } else {
                                    openStoryComposer()
                                }
                            },
                            onOpenRoom: { room in
                                openLiveRoom = room
                            }
                        )
                        .padding(.bottom, 2)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { storyRailHeight = $0 }

                        LazyVStack(spacing: 0, pinnedViews: []) {
                        composerEntryRow
                        Divider().background(WhisperTheme.hairline(colorScheme))
                        // New-user checklist — renders nothing once done or
                        // dismissed, so mature accounts never see it.
                        WhisperGettingStartedCard()
                        if feedStream.isEmpty && initialFeedLoad {
                            WhisperPostSkeletonList(count: 3)
                        }
                        // Blank feed — Instagram-style "Create your first post"
                        // moment sits below the composer row, so stories and
                        // the entry field stay alive above it.
                        if feedStream.isEmpty && !initialFeedLoad {
                            if let error = backend.postsLoadError {
                                VStack(spacing: 12) {
                                    Text(error).font(.subheadline).multilineTextAlignment(.center)
                                    Button("Try again") { Task { await backend.fetchPosts() } }
                                        .frame(minHeight: 44).disabled(backend.isLoadingPosts)
                                }.padding(24)
                            } else if !backend.hasMorePosts && !backend.isLoadingPosts { starterEmptyState }
                        }
                        if !feedStream.isEmpty, let error = backend.postsLoadError {
                            Label(error, systemImage: "wifi.exclamationmark")
                                .font(.footnote).foregroundStyle(.secondary).padding(16)
                        }
                        ForEach(Array(feedStream.enumerated()), id: \.element.id) { index, post in
                            let slots = shelfSlots(for: post.id, index: index, count: feedStream.count)
                            VStack(spacing: 0) {
                            WhisperPostCard(post: post)
                                .onScrollVisibilityChange(threshold: 0.1) { visible in
                                    if visible { imagePrefetcher.visiblePostIDs.insert(post.id) }
                                    else { imagePrefetcher.visiblePostIDs.remove(post.id) }
                                    updateImageLookAhead()
                                }
                                .transition(.identity)
                            Divider().background(WhisperTheme.hairline(colorScheme))
                            if slots.contains("stories") {
                                FeedStoriesCarousel(
                                    groups: inlineStoryGroups,
                                    storyService: storyService,
                                    onCreateStory: { openStoryComposer() },
                                    onOpenStory: { openStory = $0 }
                                )
                                Divider().background(WhisperTheme.hairline(colorScheme))
                            }
                            let ads = frozenAds ?? feedAds.ads
                            if slots.contains("ad"), !ads.isEmpty {
                                let ad = ads[(index / 6) % ads.count]
                                WhisperSponsoredAdCard(ad: ad, service: feedAds, isFeedActive: feedMediaActive)
                                    .id("ad-\(post.id)-\(ad.id)")
                                Divider().background(WhisperTheme.hairline(colorScheme))
                            }
                            if slots.contains("suggestions"), !suggestedUsers.isEmpty {
                                FeedSuggestionsCarousel(
                                    users: suggestedUsers,
                                    follows: follows,
                                    onOpenUser: { openUser = $0 }
                                )
                                Divider().background(WhisperTheme.hairline(colorScheme))
                            }
                            if slots.contains("articles") {
                                FeedArticlesCarousel(articles: articlesSvc.publishedArticles)
                                    .padding(.vertical, 10)
                                Divider().background(WhisperTheme.hairline(colorScheme))
                            }
                            if slots.contains("reels") {
                                FeedReelsCarousel(
                                    pool: reelsPool,
                                    seed: (index + 1) / reelsBreakEvery,
                                    onTap: { openReel = $0 }
                                )
                                .padding(.vertical, 10)
                                Divider().background(WhisperTheme.hairline(colorScheme))
                            }
                            if slots.contains("coaches"), !coachPool.isEmpty {
                                FeedCoachesCarousel(
                                    coaches: coachPool,
                                    follows: follows,
                                    onOpenUser: { openUser = $0 }
                                )
                                Divider().background(WhisperTheme.hairline(colorScheme))
                            }
                            }
                        }
                        if feedStream.isEmpty, !initialFeedLoad {
                            if !reelsPool.isEmpty {
                                FeedReelsCarousel(pool: reelsPool, seed: 0, onTap: { openReel = $0 })
                                    .padding(.vertical, 10)
                            }
                            if !coachPool.isEmpty {
                                FeedCoachesCarousel(coaches: coachPool, follows: follows, onOpenUser: { openUser = $0 })
                            }
                        }
                        if backend.hasMorePosts {
                            VStack(spacing: 10) {
                                if let error = backend.morePostsError {
                                    Text(error).font(.footnote).foregroundStyle(.secondary)
                                    Button("Try again") { Task { await backend.loadMorePosts(retry: true) } }
                                        .frame(minHeight: 44).disabled(backend.isLoadingMorePosts)
                                } else if backend.isLoadingMorePosts {
                                    ProgressView().accessibilityLabel("Loading more posts")
                                }
                                Color.clear.frame(height: 1)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .onScrollVisibilityChange(threshold: 0.1) { feedEndVisible = $0 }
                            .task(id: "\(feedEndVisible)|\(feedMediaActive)|\(backend.feedContinuationID)") {
                                guard feedEndVisible, feedMediaActive else { return }
                                await backend.loadMorePosts()
                            }
                        }
                        Spacer(minLength: 24)
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                        .frame(minHeight: max(0, viewportHeight - 110 - storyRailHeight), alignment: .top)
                        .modifier(WhisperStoriesForeground())
                    }
                    // iPad readability — cap the feed column at a comfortable
                    // single-column width so posts (and their photos) don't
                    // span the full iPad screen and look stretched.
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                .scrollPosition($scrollPosition)
                .onScrollPhaseChange { _, phase in
                    if phase == .interacting { freezeShelfPlacement() }
                }
                .onChange(of: scrollToTopRequest) { _, _ in
                    guard storyReveal == 0 else { return }
                    headerShelf?.reveal()
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { scrollPosition.scrollTo(edge: .top) }
                }
                .onChange(of: feedRefresh) { _, value in
                    if value.isRefreshing || value.pullProgress > 0 { headerShelf?.reveal() }
                }
                .onAppear { feedIsVisible = true }
                .onDisappear { feedIsVisible = false; imagePrefetcher.stop() }
                .onChange(of: feedMediaActive) { _, active in
                    if active { updateImageLookAhead() } else { imagePrefetcher.stop() }
                }
                .onChange(of: feedScope) { _, _ in
                    imagePrefetcher.stop()
                    imagePrefetcher.visiblePostIDs = []
                    frozenShelfSlots = nil
                    frozenAds = nil
                    headerShelf?.reveal()
                    scrollPosition.scrollTo(edge: .top)
                }
                .whisperHidesTabBarOnScroll(scrollsUnderStatusBar: true)
                // SWIPE RIGHT TO OPEN THE STORY CAMERA — the card follows the
                // finger off to the right, uncovering the composer underneath.
                .simultaneousGesture(storyRevealDrag)
                .whisperRefreshable(headerStatus: $feedRefresh) {
                    // Run every relevant fetch in parallel so a pull-down
                    // actually surfaces new posts, stories, mentions, and
                    // bell alerts together — not just whichever finished
                    // first. The visible feed + badge update from the new
                    // Supabase state as soon as the awaits return.
                    let generation = AccountStorage.generation
                    async let m: Void = moderation.refresh()
                    async let p: Void = backend.fetchPosts()
                    async let s: Void = storyService.fetch()
                    async let f: Void = follows.refresh()
                    async let a: Void = activitySvc.fetch()
                    async let men: Void = mentionsSvc.fetch()
                    async let sr: Void = storyRespSvc.fetch()
                    async let fr: Void = followRequestsSvc.refresh()
                    async let art: Void = articlesSvc.fetchPublished()
                    async let ads: Void = feedAds.refresh(force: true)
                    _ = await (m, p, s, f, a, men, sr, fr, art, ads)
                    guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                    frozenShelfSlots = nil
                    frozenAds = nil
                    refreshProjection(forceRank: true)
                    freezeShelfPlacement()
                }
                .task {
                    let generation = AccountStorage.generation
                    refreshProjection()
                    if !posts.isEmpty { initialFeedLoad = false }
                    // Parallelize the first-paint fetches — one round trip of
                    // latency instead of five sequential awaits, so the feed
                    // fills in noticeably faster on cold start.
                    async let m: Void = moderation.refresh()
                    async let p: Void = backend.fetchPostsIfStale()
                    async let s: Void = storyService.fetchIfStale()
                    async let f: Void = follows.refreshIfStale()
                    _ = await (m, p)
                    guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                    refreshProjection()
                    initialFeedLoad = false
                    async let ads: Void = feedAds.refresh()
                    async let sugg = WhisperUserService.shared.suggestions(limit: 12)
                    async let coach = WhisperCoachDirectory.fetchCoaches(limit: 12)
                    _ = await (s, f, ads)
                    let suggestions = await sugg
                    let coaches = await coach
                    guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                    suggestedUsers = suggestions
                    coachPool = coaches
                    Task { await articlesSvc.fetchPublished() }
                    backend.startPostsRealtime()
                    refreshProjection()
                    withAnimation(.easeOut(duration: 0.3)) { initialFeedLoad = false }
                    // Hydrate the bell badge — activity (likes/comments/follows),
                    // @mentions, and story interaction replies all count.
                    // Re-hydrate the active thought from the local cache too,
                    // so the IG-Notes bubble survives an account wipe / cold
                    // start even when the Supabase round-trip is slow.
                    thoughts.reloadFromDefaults()
                    // These sections do not depend on one another. Keep the
                    // work tied to the view lifecycle rather than detaching a
                    // six-request waterfall that survives navigation.
                    async let readState: Void = activitySvc.refreshReadStateFromServer()
                    async let activityRows: Void = activitySvc.fetch()
                    async let mentions: Void = mentionsSvc.fetch()
                    async let responses: Void = storyRespSvc.fetch()
                    async let requests: Void = followRequestsSvc.refresh()
                    async let thoughtRows: Void = thoughts.refreshFromServer()
                    // Hydrate every visible badge surface for the authors of
                    // the feed posts. Without these calls Liar Liar / Teen /
                    // 18+ / Trusted / Established / Founding / Guardian /
                    // Restricted silently fail to render — the chip data
                    // simply never gets fetched.
                    let authorUsernames = Array(Set(posts.map { $0.username })).filter { !$0.isEmpty }
                    let authorUserIDs = Array(Set(backend.posts.map { $0.user_id })).filter { !$0.isEmpty }
                    async let liarBadges: Void = WhisperLiarLiarService.shared.preload(usernames: authorUsernames)
                    async let ageBands: Void = WhisperSafetyService.shared.preloadAgeBands(userIDs: authorUserIDs)
                    async let watchFlags: Void = WhisperSafetyService.shared.preloadWatchFlags(
                        userIDs: authorUserIDs,
                        usernames: authorUsernames
                    )
                    async let membership: Void = WhisperOneService.shared.preload(
                        userIDs: authorUserIDs,
                        usernames: authorUsernames
                    )
                    _ = await (readState, activityRows, mentions, responses, requests, thoughtRows,
                               liarBadges, ageBands, watchFlags, membership)
                }
                .onChange(of: backend.posts) { _, _ in
                    refreshProjection()
                }
                .onChange(of: backend.postAuthorProfiles) { _, _ in
                    // Re-resolve usernames once the author profile cache
                    // hydrates so rows that decoded with a missing
                    // `username` swap to the real handle instead of "user".
                    refreshProjection()
                }
                .onChange(of: backend.myLikedPostIDs) { _, _ in refreshProjection() }
                .onChange(of: follows.followingUsernames) { _, _ in updateImageLookAhead() }
                .onChange(of: moderation.bannedUsers) { _, _ in refreshProjection() }
                .onChange(of: moderation.activeMutes) { _, _ in refreshProjection() }
                .task(id: isActive) {
                    guard isActive else { return }
                    refreshProjection()
                    async let feed: Void = backend.fetchPostsIfStale()
                    async let stories: Void = storyService.fetchIfStale()
                    _ = await (feed, stories)
                }
                .onChange(of: dearEmber.isRunning) { _, isRunning in
                    // Once Jasper finishes curating, re-rank with the new
                    // keyword boost so the feed visibly shifts.
                    if !isRunning {
                        withAnimation(.whisperGentle) {
                            refreshProjection(forceRank: true)
                        }
                    }
                }
                .overlay {
                    if dearEmber.isRunning {
                        DearEmberCuratingOverlay(service: dearEmber)
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                            .zIndex(99)
                    }
                }
                .animation(.whisperSmooth, value: dearEmber.isRunning)
            }
            .navigationDestination(for: WhisperCommunity.self) { c in
                WhisperCommunityDetailView(community: c)
            }
            .fullScreenCover(item: $openStory) { story in
                // Instagram-style: open at the tapped author, then flow
                // into the next author's stories. Each group plays
                // oldest-first (same order storiesForUser produced).
                let ordered = storyService.storiesByUser().map { Array($0.all.reversed()) }
                let gi = ordered.firstIndex { list in
                    list.contains { $0.user_id.lowercased() == story.user_id.lowercased() }
                }
                if let gi {
                    WhisperStoryViewer(
                        groups: ordered,
                        startGroup: gi,
                        startIndex: storyService.firstUnseenIndex(in: ordered[gi])
                    )
                } else {
                    let list = storiesForUser(of: story)
                    WhisperStoryViewer(
                        stories: list,
                        startIndex: storyService.firstUnseenIndex(in: list)
                    )
                }
            }
            .navigationDestination(item: $openUser) { user in
                WhisperUserProfileView(user: user)
            }
            .sheet(isPresented: $presentFindFriends) {
                WhisperFindFriendsView()
            }
            .fullScreenCover(item: $openReel) { reel in
                WhisperReelsPlayerView(reels: reelsPool, start: reel)
            }
            .fullScreenCover(isPresented: $presentLive) {
                WhisperLiveRoomsListView()
            }
            .fullScreenCover(item: $openLiveRoom) { room in
                WhisperLiveRoomView(room: room, isHost: false)
            }
            .fullScreenCover(isPresented: $presentWaveCreate) {
                WhisperWaveCreateFlow()
            }
            .fullScreenCover(isPresented: $presentArticles) {
                WhisperMyArticlesView()
            }
            // Instagram-style flat header — the system toolbar (and its
            // liquid-glass button chrome on iOS 26) is hidden entirely; the
            // header is a plain pinned row on the feed surface.
            .background(WhisperNavigationPreview(enabled: rootChromeActive))
            .toolbar(.hidden, for: .navigationBar)
            .whisperShelvingHeader(backdrop: WhisperTheme.card(colorScheme), blurred: true) {
                feedHeader
            }
        }
    }

    /// Flat pinned header — Instagram layout: a bare `+` on the left, the
    /// Whisper wordmark centered, and the notifications heart inline on the
    /// right. Every element sits on one vertically-centered row — no glass,
    /// no chrome, just ink on the feed surface.
    @State private var feedRefresh: WhisperRefreshStatus = .init()

    private var feedHeader: some View {
        ZStack {
            // Kit 4.0 "For you ⌄" — the wordmark is the feed-scope menu.
            Menu {
                Button {
                    Haptics.tap()
                    feedScope = "foryou"
                } label: {
                    Label("For you", systemImage: feedScope == "foryou" ? "checkmark" : "sparkles")
                }
                Button {
                    Haptics.tap()
                    feedScope = "following"
                } label: {
                    Label("Following", systemImage: feedScope == "following" ? "checkmark" : "person.2")
                }
            } label: {
                HStack(spacing: 5) {
                    WhisperWordmark(size: 26, refreshStatus: feedRefresh)
                    if feedScope == "following" {
                        Text("Following")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.75))
                        .padding(.top, 2)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            HStack(spacing: 0) {
                Button {
                    Haptics.tap()
                    presentComposer = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .frame(width: 40, height: 40)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New post")
                Spacer()
                Button {
                    Haptics.tap()
                    presentInbox = true
                } label: {
                    Image(systemName: "heart")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .frame(width: 40, height: 40)
                        .contentShape(.rect)
                        .overlay(alignment: .topTrailing) {
                            if bellUnreadCount > 0 {
                                Text(bellUnreadCount > 99 ? "99+" : "\(bellUnreadCount)")
                                    .font(.system(size: 11, weight: .heavy).monospacedDigit())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .frame(minWidth: 18, minHeight: 18)
                                    .background(Color(red: 0.98, green: 0.20, blue: 0.28), in: Capsule())
                                    .overlay(Capsule().strokeBorder(WhisperTheme.surface(colorScheme), lineWidth: 1.5))
                                    .allowsHitTesting(false)
                                    .transition(.scale.combined(with: .opacity))
                                    .offset(x: 4, y: -2)
                            }
                        }
                        .animation(.whisperSnappy, value: bellUnreadCount)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Notifications, \(bellUnreadCount) unread")
                Button {
                    Haptics.tap()
                    presentLive = true
                } label: {
                    Image(systemName: "radio")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .frame(width: 40, height: 40)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Live Spaces")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .background { WhisperScrollingHeaderBackdrop() }
        .background { Color.clear.contentShape(.rect).onTapGesture { } }
    }

    /// Real backend posts only — demo `WhisperFixtures.posts` have been
    /// retired so the feed never shows placeholder content alongside real
    /// user posts. Maps `WhisperPostRow` -> `WhisperPost` so the existing
    /// card UI keeps working untouched.
    private func refreshProjection(forceRank: Bool = false) {
        var names: [String: String] = [:]
        for row in backend.posts where names[row.user_id] == nil {
            names[row.user_id] = backend.resolvedAuthorUsername(rowUsername: row.username, rowUserID: row.user_id)
        }
        projection.update(rows: backend.posts, names: names, likedIDs: backend.myLikedPostIDs, forceRank: forceRank)
        updateImageLookAhead()
    }

    /// A visit keeps its shelf anchors. Late responses become eligible on refresh,
    /// rather than inserting hundreds of points above an already scrolling reader.
    private func shelfSlots(for id: UUID, index: Int, count: Int) -> Set<String> {
        if let frozenShelfSlots { return frozenShelfSlots[id] ?? [] }
        var slots: Set<String> = []
        let position = index + 1
        if position % storiesCarouselEvery == 0, !inlineStoryGroups.isEmpty { slots.insert("stories") }
        if position % suggestionsEvery == 0 {
            if !feedAds.ads.isEmpty { slots.insert("ad") }
            else if !suggestedUsers.isEmpty { slots.insert("suggestions") }
        }
        if position == articlesBreakEvery, !articlesSvc.publishedArticles.isEmpty { slots.insert("articles") }
        if !reelsPool.isEmpty, position % reelsBreakEvery == 0 || (position == count && count < reelsBreakEvery) { slots.insert("reels") }
        if !coachPool.isEmpty, position % coachesBreakEvery == 0 || (position == count && count < coachesBreakEvery) { slots.insert("coaches") }
        return slots
    }

    private func freezeShelfPlacement() {
        guard frozenShelfSlots == nil else { return }
        let stream = feedStream
        frozenAds = feedAds.ads
        frozenShelfSlots = Dictionary(uniqueKeysWithValues: stream.enumerated().map { index, post in
            (post.id, shelfSlots(for: post.id, index: index, count: stream.count))
        })
    }

    private func updateImageLookAhead() {
        guard feedMediaActive else { imagePrefetcher.stop(); return }
        let stream = feedStream
        guard let lastVisible = stream.lastIndex(where: { imagePrefetcher.visiblePostIDs.contains($0.id) }) else { return }
        imagePrefetcher.update(posts: Array(stream.dropFirst(lastVisible + 1).prefix(3)),
                               pixelSize: WhisperSizedAsyncImage<EmptyView>.pixelSize(
                                size: CGSize(width: feedViewportWidth, height: feedViewportWidth * 1.25), scale: displayScale))
    }

    /// Threads-style "What's new?" entry row pinned to the top of the feed.
    /// Tapping anywhere on it opens the composer.
    private var composerEntryRow: some View {
        let me = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"
        return HStack(alignment: .center, spacing: 12) {
            Button {
                Haptics.tap()
                presentComposer = true
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    WhisperAvatar(username: me, size: 38, ring: false)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(me)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        Text("What's new?")
                            .font(.subheadline)
                            .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.45))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "square.and.pencil")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.55))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            // THE CREATOR MARK — verified creators get the animated cursive C
            // that opens every creator-post door (wave · grid post · article).
            // Everyone else keeps the photo glyph, which opens the regular
            // composer (grid posting is a verified-creator perk).
            if WhisperAccountAccess.canPostGrid(username: me) {
                Menu {
                    Section("Creator posts") {
                        Button {
                            Haptics.tap()
                            presentWaveCreate = true
                        } label: {
                            Label("New wave", systemImage: "play.rectangle.fill")
                        }
                        Button {
                            Haptics.tap()
                            presentArticles = true
                        } label: {
                            Label("Write an article", systemImage: "doc.richtext")
                        }
                    }
                } label: {
                    WhisperCreatorMark(size: 20)
                        .frame(width: 36, height: 36)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Creator posts")
            } else {
                Button {
                    Haptics.tap()
                    presentComposer = true
                } label: {
                    Image(systemName: "photo")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.55))
                        .frame(width: 36, height: 36)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New post with a photo")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// Blank-feed moment with the original pastel paper-and-quill illustration,
    /// "Create your first post", "Give this space some love.", and one
    /// Create button. Suggestions ride above (like IG's Discover people) so
    /// day-1 users still see a path to people worth following.
    @ViewBuilder
    private var starterEmptyState: some View {
        VStack(spacing: 0) {
            if !suggestedUsers.isEmpty {
                FeedSuggestionsCarousel(
                    users: suggestedUsers,
                    follows: follows,
                    onOpenUser: { openUser = $0 }
                )
                Divider().background(WhisperTheme.hairline(colorScheme))
            }
            VStack(spacing: 0) {
                WhisperMeetDoodle(illustration: .posts)
                    .frame(maxWidth: 300)
                Text("Create your first post")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .padding(.top, 18)
                Text("Give this space some love.")
                    .font(.subheadline)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .padding(.top, 6)
                Button {
                    Haptics.tap()
                    presentComposer = true
                } label: {
                    Text("Create")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.surface(colorScheme))
                        .padding(.horizontal, 32)
                        .padding(.vertical, 11)
                        .background(WhisperTheme.ink(colorScheme), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 22)
                if follows.following.isEmpty {
                    Button {
                        Haptics.tap()
                        presentFindFriends = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "person.2.fill")
                                .font(.caption.weight(.bold))
                            Text("Find friends from contacts")
                                .font(.footnote.weight(.semibold))
                        }
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
            .padding(.horizontal, 24)
            .onAppear {
                guard !starterAppeared else { return }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                    starterAppeared = true
                }
            }
        }
    }

    /// All stories for the same user as `story`, newest first — used to
    /// power the multi-segment story viewer so taps advance through every
    /// active story from that author.
    private func storiesForUser(of story: WhisperStoryRow) -> [WhisperStoryRow] {
        let group = storyService.storiesByUser().first { $0.userID == story.user_id }
        let all = group?.all ?? [story]
        // Service returns newest-first; viewer expects chronological order.
        return all.reversed()
    }

    /// Inline story groups for the rectangle carousel — excludes my own
    /// stories (my entry sits in the top strip) and unseen-first ordering
    /// matches Facebook.
    private var inlineStoryGroups: [FeedStoriesCarousel.Group] {
        let mine = AccountStorage.currentUserID.lowercased()
        return storyService.storiesByUser()
            .filter { $0.userID.lowercased() != mine }
            .map { ($0.username, $0.userID, $0.latest, $0.all) }
    }

    /// The main feed stream — reels live exclusively in the Reels tab and
    /// the inline reels shelf, so they never render as regular feed cards.
    private var feedStream: [WhisperPost] {
        // A wave rides the feed ONLY when its author flipped "Also share to
        // feed" — it then renders as the Instagram reel-in-feed card.
        let base = posts.filter { !$0.isReel || WhisperPostMeta.isSharedToFeed(caption: $0.caption) }
        guard feedScope == "following" else { return base }
        // Kit "Following" scope — only posts from authors the viewer follows.
        let followed = Set(follows.followingUsernames.values.map { $0.lowercased() })
        return base.filter { followed.contains($0.username.lowercased()) }
    }

    /// Reels pool for the full-screen viewer — every post flagged as a reel
    /// plus any post that carries a video, newest ranking preserved.
    private var reelsPool: [WhisperPost] {
        posts.filter { p in
            p.isReel || p.mediaURLs.contains(where: { WhisperVideo.isVideo($0) })
        }
    }
}

/// Full-screen-ish overlay shown while Jasper is curating the feed in
/// response to an `@dear ember …` request. Renders the user's wish back at
/// them, an animated progress bar, and the countdown so they know exactly
/// how long the refresh will take.
private struct DearEmberCuratingOverlay: View {
    @Environment(\.colorScheme) private var colorScheme
    let service: WhisperDearEmberService
    @State private var pulse: Bool = false
    @State private var sparkle: Bool = false

    private var progress: Double {
        let total = max(1, service.etaSeconds + 1)
        let elapsed = max(0, Double(total - service.etaSeconds))
        return min(1, elapsed / Double(total))
    }

    var body: some View {
        ZStack {
            // Dimmed scrim — taps fall through to nothing so the user can't
            // dismiss the curation mid-flight by accident, but a button is
            // provided below the card for explicit cancel.
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .transition(.opacity)

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.55, blue: 0.20),
                                    Color(red: 1.0, green: 0.30, blue: 0.45)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 76, height: 76)
                        .blur(radius: pulse ? 8 : 2)
                        .scaleEffect(pulse ? 1.08 : 1.0)
                    WhisperEmberBadge(size: 56)
                        .rotationEffect(.degrees(sparkle ? 6 : -6))
                }
                .frame(height: 84)

                VStack(spacing: 6) {
                    Text("Knot is curating your feed")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    if !service.wish.isEmpty {
                        Text("\u{201C}\(service.wish)\u{201D}")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                    }
                }
                .padding(.horizontal, 20)

                // Animated progress bar.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.55, blue: 0.20),
                                        Color(red: 1.0, green: 0.30, blue: 0.45)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(6, geo.size.width * progress))
                            .animation(.linear(duration: 1), value: progress)
                    }
                }
                .frame(height: 6)
                .frame(maxWidth: 260)

                Text(service.etaSeconds > 0
                     ? "About \(service.etaSeconds)s remaining…"
                     : "Almost done…")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .contentTransition(.numericText())
                    .animation(.whisperSnappy, value: service.etaSeconds)

                if !service.boostKeywords.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(service.boostKeywords, id: \.self) { kw in
                                Text("#\(kw)")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(.white.opacity(0.16), in: Capsule())
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .frame(maxWidth: 280)
                }
            }
            .padding(.vertical, 26)
            .padding(.horizontal, 22)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.black.opacity(0.55))
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: 24))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                sparkle = true
            }
        }
    }
}
