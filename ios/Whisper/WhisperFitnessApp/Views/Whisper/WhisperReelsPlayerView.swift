import SwiftUI
import AVKit
import AVFoundation

/// Full-screen swipeable Reels viewer — rebuilt to feel like a first-party
/// short-video surface:
///
/// - Paged vertical scroll, one reel per screen, snap behavior.
/// - Autoplay + loop on the active reel, paused when scrolled away, with a
///   real buffering spinner while the video loads.
/// - Header (Instagram Reels grammar): "+" to create top-left, the
///   "Waves · Friends" scope pair centered with a facepile of friends who
///   have waves, and the sliders glyph top-right opening "Your algorithm".
/// - Right rail: like · comment · repost · share with counts beneath, ⋯,
///   and the spinning sound disc at the foot.
/// - Bottom-left: top-comment bubble, avatar · @username · Follow, the
///   white caption, and the plate-less scrolling sound line.
/// - Thin scrubber with a drag knob; tap pauses, double-tap likes with a
///   tilted heart burst.
///
/// `embedded` renders it as a dock-free root tab with Back; `isVisible`
/// lets the host pause playback when the tab scrolls off screen.
struct WhisperReelsPlayerView: View {
    @Environment(\.dismiss) private var dismiss

    let reels: [WhisperPost]
    var embedded: Bool = false
    var isVisible: Bool = true
    /// Embedded (tab) mode: called when the user swipes RIGHT on the For-you
    /// scope to leave Waves — the host switches back to Home.
    var onExit: (() -> Void)? = nil
    var hasMore: Bool = false
    var isLoadingMore: Bool = false
    var continuationError: String?
    var onNearEnd: ((String) async -> Void)?
    var onLoadMore: (() async -> Void)?
    var onRefresh: (() async -> Void)?
    @State private var currentID: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.whisperHeaderShelf) private var headerShelf
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playerIsVisible: Bool = false
    @State private var embeddedHeaderHeight: CGFloat = 46
    @ScaledMetric(relativeTo: .subheadline) private var commentUnderlayerHeight: CGFloat = 44
    @State private var inlineComments: WhisperPost?
    @State private var commentsFullyExpanded = false
    @State private var commentsCloseRequest = UUID()
    @State private var commentPreviewEpoch = UUID()
    @State private var commentsDetent: PresentationDetent = .medium

    private var activeReel: WhisperPost? {
        displayedReels.first { WhisperReelPage.reelID($0.id) == currentID }
    }

    // Waves has no bottom dock. Keep just the home-indicator clearance.
    private var commentBottomClearance: CGFloat {
        WhisperTabBarMetrics.windowBottomInset
    }

    private var embeddedStageBottomInset: CGFloat {
        commentBottomClearance + commentUnderlayerHeight
    }

    private func showComments(for reel: WhisperPost) {
        Haptics.tap()
        if embedded {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
                inlineComments = reel
                commentsFullyExpanded = false
            }
        } else {
            commentsDetent = .large
            presentComments = reel
        }
    }

    private var embeddedHeaderHidden: Bool {
        // With no tab bar, Back must remain available throughout paging.
        false
    }
    @State private var reelAds: WhisperFeedAdService = WhisperFeedAdService(placement: .reels)

    private var mediaActive: Bool {
        isVisible && playerIsVisible && scenePhase == .active && presentComments == nil && inlineComments == nil
            && presentUser == nil && shareTarget == nil && sendTarget == nil && storyShare == nil
            && soundSheet == nil && createWithSound == nil && !presentReelComposer
            && !presentAlgorithm && !preparingStoryShare
    }

    private var pages: [WhisperReelPage] {
        let ads = reelAds.ads
        var result: [WhisperReelPage] = []
        for (index, reel) in displayedReels.enumerated() {
            result.append(.reel(reel))
            if !ads.isEmpty, (index + 1) % 5 == 0 {
                result.append(.ad(ads[(index / 5) % ads.count], after: reel.id))
            }
        }
        return result
    }
    /// Media residency follows real page positions, including sponsored pages.
    /// Lazy-stack retention is not a resource budget: distant retained views own no item.
    private var residentPageIDs: Set<String> {
        guard isVisible, playerIsVisible, scenePhase == .active else { return [] }
        let sequence = pages
        guard let index = sequence.firstIndex(where: { $0.id == currentID }) else { return [] }
        return Set(sequence[max(0, index - 1)...min(sequence.count - 1, index + 1)].map(\.id))
    }

    /// Live horizontal drag offset for the scope swipe — the whole stage
    /// nudges with the finger so the gesture reads as a real page turn.
    @State private var presentComments: WhisperPost?
    @State private var presentUser: WhisperUserRow?
    @State private var resolvingUser: Bool = false
    @State private var navigationTask: Task<Void, Never>?
    @State private var navigationEpoch: UUID = UUID()
    @State private var presentReelComposer: Bool = false
    @State private var shareTarget: WhisperPost?
    /// "Send to…" picked from the share sheet — opens the DM recipient picker.
    @State private var sendTarget: WhisperPost?
    /// "Add wave to your story" — the composed gradient + wave sticker that
    /// opens the story editor (Instagram's reel-to-story grammar).
    @State private var storyShare: WaveStoryShare?
    @State private var preparingStoryShare: Bool = false
    /// Session-wide mute — flipping sound on one reel applies to all of them.
    @State private var muted: Bool = true
    /// Friends filter — narrows the pool to authors you follow.
    @State private var friendsOnly: Bool = false
    @State private var follows = WhisperFollowService.shared
    /// The Sounds system — the tapped sound's page, and the recorder opened
    /// from its "Use this sound" with that sound pre-loaded.
    @State private var soundSheet: WhisperStoryMusic?
    @State private var createWithSound: WhisperStoryMusic?
    /// "Your algorithm" — the sliders glyph in the header.
    @State private var presentAlgorithm: Bool = false

    init(reels: [WhisperPost], start: WhisperPost? = nil, embedded: Bool = false, isVisible: Bool = true, onExit: (() -> Void)? = nil,
         hasMore: Bool = false, isLoadingMore: Bool = false, continuationError: String? = nil,
         onNearEnd: ((String) async -> Void)? = nil, onLoadMore: (() async -> Void)? = nil, onRefresh: (() async -> Void)? = nil) {
        self.reels = reels
        self.embedded = embedded
        self.isVisible = isVisible
        self.onExit = onExit
        self.hasMore = hasMore
        self.isLoadingMore = isLoadingMore
        self.continuationError = continuationError
        self.onNearEnd = onNearEnd
        self.onLoadMore = onLoadMore
        self.onRefresh = onRefresh
        let startID: UUID? = (start ?? reels.first)?.id
        self._currentID = State(initialValue: startID.map(WhisperReelPage.reelID))
        self._pendingStartID = State(initialValue: start?.id)
    }

    /// The wave the player was asked to OPEN ON. `scrollPosition(id:)` alone
    /// often failed to land here on first layout (the lazy stack hadn't sized
    /// its rows yet), leaving the paging scroll parked on the FIRST wave while
    /// the "active" id pointed off-screen — the visible card never played.
    /// The stack now scrolls to it explicitly once laid out, with retries.
    @State private var pendingStartID: UUID?

    /// Scrolls the paging stack onto the requested start wave once its row
    /// exists, retrying across the first layout passes (the lazy stack can
    /// drop the target before it's sized). Clears the request once landed.
    private func landOnStart(proxy: ScrollViewProxy) {
        guard let target = pendingStartID, displayedReels.contains(where: { $0.id == target }) else { return }
        let attempts: [TimeInterval] = [0, 0.05, 0.16, 0.4]
        for delay in attempts {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard pendingStartID == target else { return }
                let pageID = WhisperReelPage.reelID(target)
                proxy.scrollTo(pageID, anchor: .top)
                if currentID != pageID { currentID = pageID }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if pendingStartID == target { pendingStartID = nil }
        }
    }

    /// Usernames you follow, lowercased.
    private var followedNames: Set<String> {
        Set(follows.followingUsernames.values.map { $0.lowercased() })
    }

    /// Active pool — the Friends scope narrows reels to authors you follow.
    private var displayedReels: [WhisperPost] {
        let available = reels.filter { !WhisperBackendService.shared.deletedPostIDs.contains($0.id.uuidString.lowercased()) }
        guard friendsOnly else { return available }
        let names = followedNames
        return available.filter { names.contains($0.username.lowercased()) }
    }

    private var nearEnd: Bool {
        guard let currentID, let index = displayedReels.firstIndex(where: { WhisperReelPage.reelID($0.id) == currentID }) else { return false }
        return index >= max(0, displayedReels.count - 3)
    }

    /// Up to three friends who have waves — the facepile beside "Friends".
    private var friendFaces: [String] {
        let names = followedNames
        var seen = Set<String>()
        var out: [String] = []
        for reel in reels {
            let key = reel.username.lowercased()
            guard names.contains(key), !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(reel.username)
            if out.count == 3 { break }
        }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            let residentIDs = residentPageIDs
            let expandedHeight = min(
                geo.size.height * (commentsFullyExpanded ? 0.84 : 0.56),
                max(0, geo.size.height - WhisperSafeArea.top - embeddedHeaderHeight - commentBottomClearance)
            )
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(pages) { page in
                            Group {
                            switch page {
                            case .reel(let reel):
                            WhisperReelCard(
                                post: reel,
                                isActive: mediaActive && currentID == page.id,
                                isResident: residentIDs.contains(page.id),
                                muted: $muted,
                                bottomChromeOffset: embedded ? max(0, embeddedStageBottomInset - 64) : 0,
                                showsInlineComment: !embedded,
                                openComments: { showComments(for: reel) },
                                openProfile: { openProfile(for: reel.username) },
                                openShare: { shareTarget = reel },
                                openSound: { soundSheet = $0 },
                                remix: { createWithSound = WhisperWaveSound.sound(for: reel) }
                            )
                            case .ad(let ad, after: _):
                                WhisperSponsoredAdCard(ad: ad, service: reelAds, isFeedActive: mediaActive && currentID == page.id)
                            }
                            }
                            .frame(width: geo.size.width, height: geo.size.height)
                            .id(page.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { old, new in
                    headerShelf?.update(old: old, new: new, enabled: embedded && isVisible && !voiceOver)
                }
                .onScrollPhaseChange { _, phase in
                    guard embedded, isVisible, !voiceOver else { return }
                    if phase == .interacting {
                        WhisperTabBarVisibility.shared.collapse()
                    }
                }
                .scrollDisabled(inlineComments != nil)
                .allowsHitTesting(inlineComments == nil)
                .refreshable { await onRefresh?() }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $currentID)
                .ignoresSafeArea()
                .onAppear {
                    landOnStart(proxy: proxy)
                }
                .onChange(of: currentID) { old, new in
                    // A page turned under the finger — a soft bump, never on
                    // the initial landing.
                    guard old != nil, new != nil, old != new else { return }
                    inlineComments = nil
                    WhisperFeedback.pageTurned()
                }
                .onChange(of: displayedReels.count) { _, _ in
                    landOnStart(proxy: proxy)
                }
            }
            // Keep paging/video dimensions intact while exposing the top
            // controls and bottom comments as one recessed dark underlayer.
            .mask {
                UnevenRoundedRectangle(
                    topLeadingRadius: embedded ? 24 : 0,
                    bottomLeadingRadius: embedded ? 24 : 0,
                    bottomTrailingRadius: embedded ? 24 : 0,
                    topTrailingRadius: embedded ? 24 : 0,
                    style: .continuous
                )
                .padding(.top, embedded ? WhisperSafeArea.top + (embeddedHeaderHidden ? 4 : embeddedHeaderHeight) : 0)
                .padding(.bottom, embedded && activeReel != nil ? (inlineComments == nil ? embeddedStageBottomInset : expandedHeight + commentBottomClearance) : 0)
            }
            .overlay(alignment: .bottom) {
                if embedded, let reel = activeReel {
                    VStack(spacing: 0) {
                        if let thread = inlineComments {
                            WhisperCommentsView(
                                postID: thread.id.uuidString.lowercased(),
                                postUsername: thread.username,
                                postCaption: thread.displayCaption,
                                onClose: { closeInlineComments() },
                                onExpand: {
                                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) { commentsFullyExpanded.toggle() }
                                },
                                closeRequest: commentsCloseRequest
                            )
                            .id("\(thread.id)-\(commentPreviewEpoch)")
                            .frame(height: expandedHeight)
                        } else {
                            HStack(spacing: 0) {
                                WhisperWaveCommentUnderlayer(post: reel, isActive: mediaActive) {
                                    showComments(for: reel)
                                }
                                .id("\(reel.id)-\(commentPreviewEpoch)")
                                algorithmButton
                            }
                            .frame(height: commentUnderlayerHeight)
                            .padding(.horizontal, 8)
                        }
                    }
                    .background(.black)
                    .contentShape(.rect)
                    .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
                        guard inlineComments == nil,
                              abs(value.translation.height) > abs(value.translation.width),
                              value.translation.height < -40 else { return }
                        showComments(for: reel)
                    })
                    .padding(.bottom, commentBottomClearance)
                    .environment(\.colorScheme, .dark)
                }
            }
        }
        .ignoresSafeArea(.container)
        .whisperEdgeBack(isEnabled: isVisible && soundSheet == nil && presentComments == nil && inlineComments == nil && shareTarget == nil && !presentAlgorithm,
            requiresDecision: embedded, revealPresentation: !embedded) {
                if embedded && friendsOnly { setFriendsOnly(false) }
                else if embedded { onExit?() }
                else { dismiss() }
            }
        .background(Color.black.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            header
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if embedded, height > 0, abs(embeddedHeaderHeight - height) > 0.5 {
                        embeddedHeaderHeight = height
                    }
                }
                .background {
                    if embedded {
                        Color.black.ignoresSafeArea(edges: .top)
                    }
                }
                .offset(y: embeddedHeaderHidden ? -embeddedHeaderHeight : 0)
                .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: headerShelf?.isHidden)
                .clipped()
                .allowsHitTesting(true)
                .accessibilityHidden(false)
        }
        .task(id: isVisible) {
            guard isVisible else { return }
            await reelAds.refresh()
        }
        .task(id: "\(currentID ?? "none")-\(displayedReels.count)-\(isVisible)-\(scenePhase == .active)") {
            guard isVisible, scenePhase == .active, nearEnd, hasMore,
                  !isLoadingMore, continuationError == nil, let currentID else { return }
            await onNearEnd?(currentID)
        }
        .overlay(alignment: .topLeading) {
            if !displayedReels.isEmpty && ((nearEnd && hasMore) || continuationError != nil) {
                continuationControl.padding(.top, WhisperSafeArea.top + 60).padding(.leading, 16)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .whisperAccountSwitched)) { _ in
            presentComments = nil
            inlineComments = nil
            commentPreviewEpoch = UUID()
            reelAds.resetForCurrentAccount()
            if isVisible { Task { await reelAds.refresh(force: true) } }
        }
        .onChange(of: pages.map(\.id)) { oldIDs, newIDs in
            guard let currentID, !newIDs.contains(currentID) else { return }
            let oldIndex = oldIDs.firstIndex(of: currentID) ?? 0
            self.currentID = newIDs.isEmpty ? nil : newIDs[min(oldIndex, newIDs.count - 1)]
            if newIDs.isEmpty && !embedded { dismiss() }
        }
        .onDisappear { playerIsVisible = false; cancelPendingNavigation() }
        .onChange(of: isVisible) { _, visible in if !visible { inlineComments = nil; cancelPendingNavigation() } }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            presentComments = nil
            inlineComments = nil
            cancelPendingNavigation()
        }
        .onAppear {
            playerIsVisible = true
            if currentID == nil { currentID = displayedReels.first.map { WhisperReelPage.reelID($0.id) } }
        }
        .onChange(of: reels.count) { _, _ in
            if currentID == nil { currentID = displayedReels.first.map { WhisperReelPage.reelID($0.id) } }
        }
        .overlay(alignment: .center) {
            if displayedReels.isEmpty { emptyState }
        }
        .fullScreenCover(isPresented: $presentReelComposer, onDismiss: { WhisperWaveResponsiveness.sampleReturn() }) {
            WhisperWaveCreateFlow()
        }
        .fullScreenCover(item: $createWithSound, onDismiss: { WhisperWaveResponsiveness.sampleReturn() }) { sound in
            WhisperWaveCreateFlow(initialMusic: sound)
        }
        .fullScreenCover(isPresented: $presentAlgorithm) {
            WhisperAlgorithmView(pool: reels)
        }
        .sheet(item: $soundSheet) { sound in
            WhisperSoundSheet(sound: sound, pool: reels) { picked in
                soundSheet = nil
                // Let the sheet finish dismissing before the camera rises.
                navigationTask?.cancel()
                let token = navigationEpoch
                let account = AccountStorage.generation
                navigationTask = Task {
                    do { try await Task.sleep(for: .milliseconds(380)) } catch { return }
                    guard token == navigationEpoch, account == AccountStorage.generation, isVisible, !Task.isCancelled else { return }
                    createWithSound = picked
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $presentComments) { reel in
            WhisperCommentsView(
                postID: reel.id.uuidString.lowercased(),
                postUsername: reel.username,
                postCaption: reel.displayCaption
            )
            .presentationDetents(embedded ? [.medium, .large] : [.large], selection: $commentsDetent)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
            .preferredColorScheme(embedded ? .dark : nil)
        }
        .sheet(item: $shareTarget) { reel in
            WhisperPostShareSheet(post: reel)
        }
        .sheet(item: $sendTarget) { reel in
            WhisperPostShareSheet(post: reel)
        }
        .fullScreenCover(item: $storyShare) { share in
            WhisperStoryEditor(
                image: share.background,
                initialStickers: [share.sticker],
                sharedPostBackground: true,
                onPosted: { storyShare = nil }
            )
        }
        .overlay {
            if preparingStoryShare {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    VStack(spacing: 10) {
                        ProgressView().tint(.white).controlSize(.large)
                        Text("Setting up your story…")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
                .transition(.opacity)
            }
        }
        .fullScreenCover(item: $presentUser) { user in
            NavigationStack {
                WhisperUserProfileView(user: user)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { presentUser = nil }
                                .foregroundStyle(.white)
                        }
                    }
            }
        }
        .preferredColorScheme(embedded ? nil : .dark)
        .environment(\.colorScheme, .dark)
    }

    private func closeInlineComments() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
            inlineComments = nil
            commentsFullyExpanded = false
        }
    }

    private var algorithmButton: some View {
        Button { Haptics.tap(); presentAlgorithm = true } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Your algorithm")
    }

    // MARK: - Header

    /// One compact row hugging the status bar.
    /// Balanced Back and creation controls around the scopes; algorithm
    /// lives in the bottom underlayer. No bottom navigation on Waves.
    private var header: some View {
        HStack(spacing: 0) {
            if embedded {
                Button {
                    Haptics.tap()
                    if inlineComments != nil { commentsCloseRequest = UUID() }
                    else { onExit?() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(inlineComments == nil ? "Back to Home" : "Collapse comments")

                scopePair
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)

                Button {
                    Haptics.tap()
                    presentReelComposer = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 25, weight: .light))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New wave")
            } else {
                standaloneHeader
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 6)
        .padding(.top, 2)
    }

    private var standaloneHeader: some View {
        ZStack {
            Text("Waves")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 5, y: 1)
            HStack {
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.55), radius: 5, y: 1)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Spacer()
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 4)
    }

    /// "Waves" · "Friends [facepile]" — the active scope is bright white, the
    /// other dimmed, exactly Instagram's "Reels  Friends" pair.
    private var scopePair: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                setFriendsOnly(false)
            } label: {
                Text("Waves")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(friendsOnly ? Color.white.opacity(0.5) : Color.white)
                    .frame(height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("For you")

            Button {
                Haptics.tap()
                setFriendsOnly(true)
            } label: {
                HStack(spacing: 7) {
                    Text("Friends")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(friendsOnly ? Color.white : Color.white.opacity(0.5))
                    if !embedded && !friendFaces.isEmpty {
                        HStack(spacing: -7) {
                            ForEach(friendFaces, id: \.self) { name in
                                WhisperAvatar(username: name, size: 22, ring: false)
                                    .overlay { Circle().strokeBorder(Color.black.opacity(0.85), lineWidth: 1.5) }
                            }
                        }
                        .opacity(friendsOnly ? 1 : 0.7)
                    }
                }
                .frame(height: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Friends")
        }
        .shadow(color: .black.opacity(0.55), radius: 5, y: 1)
        .animation(.easeOut(duration: 0.15), value: friendsOnly)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            WhisperMeetDoodle(symbol: "play.rectangle")
                .frame(maxWidth: 300)
                .environment(\.colorScheme, .dark)
            Text(isLoadingMore ? "Loading waves…" : (hasMore ? "More waves to explore" : (friendsOnly ? "No waves from friends yet" : "No waves yet")))
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            Text(hasMore ? "Keep looking for a wave you’ll love." : (friendsOnly ? "Follow more people to see their waves here." : "Be the first — make a wave."))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            if hasMore || isLoadingMore || continuationError != nil { continuationControl }
            Button {
                Haptics.tap()
                presentReelComposer = true
            } label: {
                Label("New wave", systemImage: "camera.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    private var continuationControl: some View {
        Group {
            if isLoadingMore {
                ProgressView("Loading waves…").tint(.white).foregroundStyle(.white)
            } else {
                Button {
                    Task { await onLoadMore?() }
                } label: {
                    Label(continuationError == nil ? "More waves" : "Waves couldn’t load · Retry", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold)).padding(12)
                        .foregroundStyle(.white).background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func setFriendsOnly(_ on: Bool) {
        guard friendsOnly != on else { return }
        withAnimation(.easeOut(duration: 0.15)) { friendsOnly = on }
        currentID = displayedReels.first.map { WhisperReelPage.reelID($0.id) }
    }

    private func openProfile(for username: String) {
        guard !resolvingUser, isVisible else { return }
        resolvingUser = true
        let token = navigationEpoch
        let account = AccountStorage.generation
        navigationTask?.cancel()
        navigationTask = Task {
            let row = await WhisperUserService.shared.fetchByUsername(username)
            guard token == navigationEpoch, account == AccountStorage.generation, isVisible, !Task.isCancelled else { return }
            resolvingUser = false
            presentUser = row
        }
    }

    private func cancelPendingNavigation() {
        navigationTask?.cancel(); navigationTask = nil
        navigationEpoch = UUID(); resolvingUser = false
    }

    /// Instagram's "Add reel to your story": sample the wave's own colors
    /// into a two-tone gradient canvas, drop the wave card sticker on it, and
    /// hand both to the story editor.
    private func prepareStoryShare(_ post: WhisperPost) async {
        guard !preparingStoryShare else { return }
        withAnimation(.easeOut(duration: 0.15)) { preparingStoryShare = true }
        defer { withAnimation(.easeOut(duration: 0.15)) { preparingStoryShare = false } }
        var cover: UIImage? = nil
        if let still = post.mediaURLs.first(where: { !WhisperVideo.isVideo($0) }),
           let (data, _) = try? await URLSession.shared.data(from: still) {
            cover = UIImage(data: data)
        } else if let video = post.mediaURLs.first(where: { WhisperVideo.isVideo($0) }) {
            cover = await WhisperStoryPoster.firstFrame(of: video, maxSize: CGSize(width: 540, height: 960))
        }
        let background = WhisperWaveStoryBackground.blurred(from: cover)
        storyShare = WaveStoryShare(background: background, sticker: .wave(post: post))
    }

    /// Encodes the reel as a shared-post DM embed so the recipient gets the
    /// same rich preview bubble as sharing from the feed.
    private func sharePayload(_ post: WhisperPost) -> String {
        WhisperSharedPostEmbed.encode(
            WhisperSharedPostEmbed.Payload(
                postID: post.id.uuidString.lowercased(),
                username: post.username,
                caption: post.displayCaption,
                kindRaw: post.kind.rawValue,
                symbol: post.symbol,
                accentHex: nil,
                mediaURL: post.mediaURLs.first?.absoluteString,
                isVideo: post.mediaURLs.first.map { WhisperVideo.isVideo($0) } ?? false,
                likes: post.likes,
                comments: post.comments,
                isReel: true
            )
        )
    }
}

/// Single full-screen reel. Auto-plays when `isActive`, pauses otherwise.
private struct WhisperReelCard: View {
    let post: WhisperPost
    let isActive: Bool
    let isResident: Bool
    @Binding var muted: Bool
    let bottomChromeOffset: CGFloat
    let showsInlineComment: Bool
    let openComments: () -> Void
    let openProfile: () -> Void
    let openShare: () -> Void
    /// Opens the sound page for this wave's sound (attribution line + disc).
    let openSound: (WhisperStoryMusic) -> Void
    /// Instagram's Remix — opens the recorder with this wave's sound attached.
    let remix: () -> Void

    @State private var player: AVPlayer = AVPlayer()
    @State private var looper: NSObjectProtocol?
    @State private var paused: Bool = false
    @State private var buffering: Bool = false
    @State private var liked: Bool
    @State private var likes: Int
    @State private var doubleTapHeart: Bool = false
    @State private var heartTilt: Double = 0
    /// Instagram's "Save to collection" sheet from the ⋯ menu.
    @State private var presentSaveToCollection: Bool = false
    @State private var confirmDelete: Bool = false
    @State private var deleting: Bool = false
    @State private var deleteError: String?
    @State private var resumeAfterDelete: Bool = false
    @State private var captionExpanded: Bool = false
    @State private var progress: Double = 0
    @State private var scrubbing: Bool = false
    /// Buffered fraction of the video — the pale ahead-of-playhead track.
    @State private var buffered: Double = 0
    @State private var currentSeconds: Double = 0
    @State private var durationSeconds: Double = 0
    @State private var discSpinning: Bool = false
    @State private var showSoundFlash: Bool = false
    @State private var soundFlashTick: Int = 0
    @State private var holdPaused: Bool = false
    /// Seconds this wave has been on screen this visit — feeds the watch log
    /// behind "Your algorithm" once it crosses 2.5s.
    @State private var activeSeconds: Double = 0
    @State private var watchLogged: Bool = false
    @State private var reposts = WhisperRepostService.shared
    @State private var repostSpin: Int = 0
    @State private var storyRingService = WhisperStoryService.shared
    @State private var authorRow: WhisperUserRow?
    @State private var following: Bool = false
    @State private var followBusy: Bool = false
    @State private var backend = WhisperBackendService.shared
    @State private var bookmarks = WhisperBookmarkService.shared
    @State private var follows = WhisperFollowService.shared

    init(
        post: WhisperPost,
        isActive: Bool,
        isResident: Bool,
        muted: Binding<Bool>,
        bottomChromeOffset: CGFloat = 0,
        showsInlineComment: Bool = true,
        openComments: @escaping () -> Void,
        openProfile: @escaping () -> Void,
        openShare: @escaping () -> Void,
        openSound: @escaping (WhisperStoryMusic) -> Void,
        remix: @escaping () -> Void
    ) {
        self.post = post
        self.isActive = isActive
        self.isResident = isResident
        self._muted = muted
        self.bottomChromeOffset = bottomChromeOffset
        self.showsInlineComment = showsInlineComment
        self.openComments = openComments
        self.openProfile = openProfile
        self.openShare = openShare
        self.openSound = openSound
        self.remix = remix
        self._liked = State(initialValue: post.liked)
        self._likes = State(initialValue: post.likes)
    }

    private var postIDString: String { post.id.uuidString.lowercased() }
    /// The wave's sound — its picked track, else its own original sound.
    private var sound: WhisperStoryMusic { WhisperWaveSound.sound(for: post) }
    private var videoURL: URL? { post.mediaURLs.first(where: { WhisperVideo.isVideo($0) }) }
    private var firstMedia: URL? { post.mediaURLs.first }

    private var caption: String { post.displayCaption }

    /// Latest root comment — rendered as the preview bubble above the
    /// identity row.
    @State private var topComment: WhisperCommentRow?

    /// Hide the follow affordances on my own reels.
    private var isMe: Bool {
        let me = (LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "").lowercased()
        return !me.isEmpty && me == post.username.lowercased()
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            media

            // Legibility scrims — top and bottom, so chrome always reads.
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0.5), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 150)
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.62)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 250)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Instagram's reel gestures: tap toggles sound (speaker glyph
            // flashes center), press-and-hold pauses, double-tap likes.
            Color.clear
                .contentShape(.rect)
                .onTapGesture(count: 2) {
                    Haptics.success()
                    if !liked { toggleLike() } else { burstHeart() }
                }
                .onTapGesture(count: 1) {
                    Haptics.tap()
                    muted.toggle()
                    player.isMuted = muted
                    soundFlashTick &+= 1
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { showSoundFlash = true }
                    Task {
                        try? await Task.sleep(for: .milliseconds(700))
                        await MainActor.run {
                            withAnimation(.easeOut(duration: 0.25)) { showSoundFlash = false }
                        }
                    }
                }
                .onLongPressGesture(minimumDuration: 0.25, pressing: { pressing in
                    guard videoURL != nil else { return }
                    if pressing {
                        if !paused {
                            holdPaused = true
                            paused = true
                            player.pause()
                            updateDiscSpin()
                        }
                    } else if holdPaused {
                        holdPaused = false
                        paused = false
                        if isActive { player.play() }
                        updateDiscSpin()
                    }
                }, perform: {})

            // Speaker glyph flash on tap (IG grammar).
            if showSoundFlash {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(.black.opacity(0.55), in: Circle())
                    .id(soundFlashTick)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            // Dim + play glyph while paused.
            if paused && videoURL != nil {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                Image(systemName: "play.fill")
                    .font(.system(size: 58, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.6), radius: 12)
                    .allowsHitTesting(false)
                    .transition(.scale(scale: 1.25).combined(with: .opacity))
            }

            // Buffering spinner — only when the active video is actually
            // stalled, so slow networks read as loading instead of broken.
            if buffering && !paused && videoURL != nil {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .allowsHitTesting(false)
            }

            // The like burst — a brand-gradient heart blooms in the center
            // (double-tap or the rail heart, same moment).
            if doubleTapHeart {
                WhisperWaveHeartBurst(tilt: heartTilt)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            rightRail
            bottomInfo

            // Scrubber — pinned to the very bottom of the reel.
            if videoURL != nil {
                seekBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 78 + bottomChromeOffset)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .animation(.easeOut(duration: 0.18), value: paused)
        .alert("Delete this wave?", isPresented: $confirmDelete) {
            Button("Delete wave", role: .destructive) {
                deleting = true
                let generation = AccountStorage.generation
                Task {
                    let success = await backend.deletePost(postID: postIDString)
                    guard generation == AccountStorage.generation else { return }
                    deleting = false
                    if !success { deleteError = backend.lastError ?? "Couldn't delete this wave. Please try again." }
                }
            }
            Button("Cancel", role: .cancel) { resumeAfterDeletion() }
        } message: { Text("This removes the wave from Whisper. This can't be undone.") }
        .alert("Wave not deleted", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("Try again") { deleteError = nil; confirmDelete = true }
            Button("Keep wave", role: .cancel) { deleteError = nil; resumeAfterDeletion() }
        } message: { Text(deleteError ?? "") }
        .overlay { if deleting { ProgressView("Deleting wave…").tint(.white).foregroundStyle(.white).padding(20).background(.black.opacity(0.8), in: .rect(cornerRadius: 16)) } }
        .task(id: isActive) {
            guard isActive, !backend.ownsPost(postIDString) else { return }
            if !backend.posts.contains(where: { $0.id.lowercased() == postIDString }) { _ = await backend.fetchPost(postID: postIDString) }
        }
        .onAppear {
            configureIfNeeded()
            measureFirstFrame()
            updateDiscSpin()
        }
        .onChange(of: isResident) { _, resident in
            if resident { configureIfNeeded() } else { releaseMedia() }
        }
        .onChange(of: isActive) { _, active in
            if active {
                configureIfNeeded()
                if !paused { player.play() }
                measureFirstFrame()
            } else {
                player.pause()
                firstFrameSpan?.finish(); firstFrameSpan = nil
            }
            updateDiscSpin()
        }
        .onChange(of: muted) { _, m in
            player.isMuted = m
        }
        .task(id: isActive) {
            // Progress + stall poller — light 5Hz tick while on screen.
            guard isActive else { return }
            activeSeconds = 0
            _ = await reposts.fetchCountIfNeeded(for: postIDString)
            while isActive && !Task.isCancelled {
                updateProgress()
                let stalled = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                if stalled != buffering {
                    withAnimation(.easeOut(duration: 0.2)) { buffering = stalled }
                }
                if !paused {
                    activeSeconds += 0.2
                    // A real watch (not a flick-past) — the algorithm's view signal.
                    if activeSeconds >= 2.5 {
                        if !watchLogged {
                            watchLogged = true
                            WhisperAlgorithmPreferences.shared.recordWatch(postID: postIDString, seconds: 2.5)
                        } else if Int(activeSeconds * 5) % 25 == 0 {
                            WhisperAlgorithmPreferences.shared.recordWatch(postID: postIDString, seconds: 5)
                        }
                    }
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        .task {
            // Resolve the author once so follow state + the rail badge render.
            guard !isMe, authorRow == nil else { return }
            let row = await WhisperUserService.shared.fetchByUsername(post.username)
            await MainActor.run {
                authorRow = row
                if let row { following = follows.isFollowing(userID: row.user_id) }
            }
        }
        .task(id: isActive) {
            // Only the visible wave needs a preview. Full-thread hydration waits
            // until comments are opened; the preview never replaces that cache.
            guard isActive, showsInlineComment, post.comments > 0, topComment == nil else { return }
            let generation = AccountStorage.generation
            let preview = await backend.fetchCommentPreview(postID: postIDString)
            guard !Task.isCancelled, isActive, generation == AccountStorage.generation else { return }
            withAnimation(.easeOut(duration: 0.2)) { topComment = preview }
        }
        .onDisappear { releaseMedia() }
    }

    private func resumeAfterDeletion() {
        if resumeAfterDelete { paused = false; if isActive { player.play() } }
        resumeAfterDelete = false
    }

    // MARK: - Media

    @State private var videoFrameReady: Bool = false
    @State private var firstFrameSpan: WhisperPerformance.Span?
    @State private var resumeTime: CMTime = .zero

    private func measureFirstFrame() {
        guard isActive, isResident, videoURL != nil else { return }
        firstFrameSpan?.finish()
        firstFrameSpan = WhisperPerformance.Span("WavesFirstFrame")
        if videoFrameReady { firstFrameSpan?.finish(completed: true); firstFrameSpan = nil }
    }

    private func releaseMedia() {
        player.pause()
        firstFrameSpan?.finish(); firstFrameSpan = nil
        if player.currentItem != nil {
            WhisperPerformance.waveItemChanged(by: -1)
            let time = player.currentTime()
            if time.seconds.isFinite { resumeTime = time }
        }
        if let looper { NotificationCenter.default.removeObserver(looper) }
        looper = nil
        player.currentItem?.cancelPendingSeeks()
        player.replaceCurrentItem(with: nil)
        videoFrameReady = false
        buffering = false
    }

    @ViewBuilder
    private var media: some View {
        if let videoURL {
            ReelPlayerLayerView(player: player, onReadyChanged: { ready in
                videoFrameReady = ready && player.currentItem != nil && isResident
                if videoFrameReady, isActive {
                    firstFrameSpan?.finish(completed: true); firstFrameSpan = nil
                }
            })
                .overlay {
                    if !videoFrameReady {
                        WhisperWavePosterView(videoURL: videoURL, coverURL: WhisperPostMeta.coverURL(from: post.caption))
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
        } else if let url = firstMedia {
            WhisperCachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    LinearGradient(
                        colors: [post.accent.opacity(0.95), post.accent.opacity(0.55)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
            }
            .ignoresSafeArea()
        } else {
            LinearGradient(
                colors: [post.accent.opacity(0.95), post.accent.opacity(0.55)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .overlay {
                Image(systemName: post.symbol)
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    // MARK: - Right rail

    /// The kit's Reels rail, bottom-aligned: heart · comment · share with
    /// their counts beneath, the horizontal ⋯, then the audio square (album
    /// art / author) at the foot. Save lives in ⋯ like the real app; the
    /// follow affordance lives in the identity row, not on the rail.
    private var rightRail: some View {
        VStack(spacing: 16) {
            Spacer()

            WhisperWaveHeartButton(liked: liked, count: likes) {
                toggleLike()
            }
            .sensoryFeedback(.impact(weight: .light), trigger: likes)

            railButton(icon: "message", count: post.comments) {
                Haptics.tap()
                openComments()
            }

            // Instagram's repost — the two-arrow glyph with its count; spins
            // once when you repost, lit green while it's yours.
            railButton(
                icon: "arrow.2.squarepath",
                count: reposts.count(for: postIDString),
                tint: reposts.isReposted(postIDString) ? Color(red: 0.18, green: 0.78, blue: 0.32) : .white
            ) {
                toggleRepost()
            }
            .rotationEffect(.degrees(Double(repostSpin) * 360))
            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: repostSpin)

            railButton(icon: "paperplane", count: 0) {
                Haptics.tap()
                openShare()
            }.accessibilityLabel("Share wave")

            Menu {
                if backend.ownsPost(postIDString) {
                    Button("Delete wave", systemImage: "trash", role: .destructive) {
                        resumeAfterDelete = !paused
                        paused = true; player.pause(); confirmDelete = true
                    }.disabled(deleting)
                    Divider()
                }
                Button {
                    Haptics.tap()
                    remix()
                } label: {
                    Label("Remix — record with this sound", systemImage: "waveform.badge.plus")
                }
                Button {
                    Haptics.tap()
                    Task { _ = await bookmarks.toggle(postID: postIDString) }
                } label: {
                    Label(
                        bookmarks.isBookmarked(postIDString) ? "Saved" : "Save",
                        systemImage: bookmarks.isBookmarked(postIDString) ? "bookmark.fill" : "bookmark"
                    )
                }
                Button {
                    Haptics.tap()
                    presentSaveToCollection = true
                } label: {
                    Label("Save to collection…", systemImage: "folder.badge.plus")
                }
                Button {
                    Haptics.tap()
                    openShare()
                } label: {
                    Label("Add wave to your story", systemImage: "plus.circle")
                }
                Button {
                    Haptics.tap()
                    muted.toggle()
                    player.isMuted = muted
                } label: {
                    Label(muted ? "Unmute sounds" : "Mute sounds", systemImage: muted ? "speaker.wave.2" : "speaker.slash")
                }
                Button {
                    Haptics.tap()
                    openProfile()
                } label: {
                    Label("View profile", systemImage: "person.crop.circle")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 5, y: 1)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("More")

            soundDisc
        }
        .padding(.trailing, 12)
        .padding(.bottom, 108 + bottomChromeOffset)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .sheet(isPresented: $presentSaveToCollection) {
            WhisperSaveToCollectionSheet(postID: postIDString)
        }
    }

    /// TikTok's spinning record at the foot of the rail — album art (or the
    /// creator for original sounds), notes drifting off it while the wave
    /// plays. Tap → the sound page.
    private var soundDisc: some View {
        Button {
            Haptics.tap()
            openSound(sound)
        } label: {
            WhisperSoundDisc(sound: sound, username: post.username, spinning: discSpinning)
                .padding(.top, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sound: \(WhisperWaveSound.label(sound))")
    }

    /// The attribution line — "♪ Original sound · username" or "♪ Title ·
    /// Artist" — plain white on the video like Instagram (no plate), fading
    /// at its trailing edge and gliding sideways only when it doesn't fit.
    /// Tap → the sound page.
    private var soundLine: some View {
        Button {
            Haptics.tap()
            openSound(sound)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.system(size: 11, weight: .bold))
                WhisperSoundMarquee(
                    text: WhisperWaveSound.label(sound),
                    font: .system(size: 13, weight: .semibold),
                    maxWidth: 190
                )
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 4)
            .frame(height: 22)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func toggleRepost() {
        Haptics.tap()
        let wasReposted = reposts.isReposted(postIDString)
        if !wasReposted { repostSpin &+= 1 }
        Task {
            let now = await reposts.toggle(postID: postIDString)
            if now && !wasReposted { Haptics.success() }
        }
    }

    private func updateDiscSpin() {
        let shouldSpin = isActive && !paused && videoURL != nil
        if discSpinning != shouldSpin { discSpinning = shouldSpin }
    }

    /// Kit metrics: 28pt regular-weight outline glyph, 12/semibold count.
    private func railButton(
        icon: String,
        count: Int,
        tint: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Group {
                    if icon == "paperplane" { WhisperRoundedGlyph(kind: .plane, size: 22) }
                    else if icon.hasPrefix("heart") { WhisperRoundedGlyph(kind: .heart, size: 22, selected: icon == "heart.fill") }
                    else if icon == "message" || icon == "bubble.right" { WhisperRoundedGlyph(kind: .comment, size: 22) }
                    else if icon == "arrow.2.squarepath" { WhisperRoundedGlyph(kind: .repost, size: 22) }
                    else { Image(systemName: icon).font(.system(size: 27, weight: .regular)) }
                }
                    .foregroundStyle(tint)
                    .shadow(color: .black.opacity(0.5), radius: 5, y: 1)
                    .contentTransition(.symbolEffect(.replace))
                if count > 0 {
                    Text(compactCount(count))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 4)
                        .monospacedDigit()
                }
            }
            .frame(minWidth: 46, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom info

    /// The kit's bottom-left stack, top to bottom: the pinned comment
    /// bubble → identity row (ringed avatar · username · badge · Follow) →
    /// one-line caption → "Liked by [facepile] name and N others" → the
    /// chips row (♪ Original audio · location / community).
    private var bottomInfo: some View {
        VStack(alignment: .leading, spacing: 9) {
            Spacer()

            if showsInlineComment, let tc = topComment {
                Button {
                    Haptics.tap()
                    openComments()
                } label: {
                    HStack(spacing: 8) {
                        WhisperAvatar(username: tc.username, size: 26, ring: false)
                        (Text(tc.username).font(.system(size: 13, weight: .bold))
                            + Text("  \(tc.body)").font(.system(size: 13)))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                    .padding(.trailing, 14)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.42), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Identity row — Instagram's: ringed avatar · username + badge with
            // the community as its subline · the outlined Follow pill.
            HStack(alignment: .center, spacing: 10) {
                Button {
                    Haptics.tap()
                    openProfile()
                } label: {
                    HStack(spacing: 10) {
                        WhisperAvatar(username: post.username, size: 38, ring: authorHasStory)
                            .overlay { if !authorHasStory { Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1) } }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text(post.username)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                VerifiedBadge(
                                    badge: UserVerificationService.shared.badge(forUsername: post.username),
                                    size: 13,
                                    username: post.username,
                                    maxChips: 0
                                )
                            }
                            if let community = post.communityName?.trimmingCharacters(in: .whitespacesAndNewlines), !community.isEmpty {
                                Text("in \(community)")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.78))
                                    .lineLimit(1)
                            }
                        }
                        .shadow(color: .black.opacity(0.5), radius: 4)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                if !isMe && !following && authorRow != nil {
                    Button {
                        followAuthor()
                    } label: {
                        Text("Follow")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(0.85), lineWidth: 1) }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(followBusy)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }

            WhisperPostCorrectionNotice(postID: postIDString, compact: true)

            // The caption — always WHITE on the video whatever the app's color
            // scheme (the mention renderer used to paint theme ink, which read
            // black on light-mode phones).
            if !caption.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        captionExpanded.toggle()
                    }
                } label: {
                    HStack(alignment: .bottom, spacing: 4) {
                        WhisperMentionText(
                            text: caption,
                            font: .system(size: 14),
                            lineLimit: captionExpanded ? 12 : 1,
                            inkColor: .white,
                            linkColor: .white
                        )
                        if !captionExpanded && caption.count > 44 {
                            Text("more")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .shadow(color: .black.opacity(0.45), radius: 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            // Sound line · location — plain white text on the video, no plates.
            HStack(spacing: 10) {
                soundLine
                if let loc = postMeta?.location, !loc.isEmpty {
                    metaText(icon: "mappin", text: loc)
                }
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 78)
        .padding(.bottom, 108 + bottomChromeOffset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    /// Plain glyph + text line for the bottom-left meta row (Instagram shows
    /// the location / audio lines bare on the video).
    private func metaText(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.5), radius: 4)
        .frame(maxWidth: 140, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var postMeta: WhisperPostMeta? { WhisperPostMeta.parse(from: post.caption) }

    private var authorHasStory: Bool {
        storyRingService.storiesByUser().contains { $0.username.lowercased() == post.username.lowercased() }
    }

    private func followAuthor() {
        guard !followBusy, let row = authorRow else { return }
        followBusy = true
        Haptics.tap()
        Task {
            let ok = await follows.follow(userID: row.user_id, username: row.username)
            await MainActor.run {
                followBusy = false
                if ok {
                    Haptics.success()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) { following = true }
                }
            }
        }
    }

    // MARK: - Seek bar

    /// Premium scrubber — the film-theater control language on the reel:
    /// buffered ahead-of-playhead track, an always-there knob that grows
    /// under the finger, and a floating timecode pill while scrubbing.
    private var seekBar: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.22))
                    .frame(height: scrubbing ? 6 : 2.5)
                Capsule()
                    .fill(.white.opacity(0.30))
                    .frame(
                        width: max(0, width * buffered),
                        height: scrubbing ? 6 : 2.5
                    )
                Capsule()
                    .fill(.white)
                    .frame(
                        width: max(0, width * progress),
                        height: scrubbing ? 6 : 2.5
                    )
                Circle()
                    .fill(.white)
                    .frame(width: scrubbing ? 16 : 9, height: scrubbing ? 16 : 9)
                    .shadow(color: .black.opacity(0.4), radius: 3)
                    .offset(x: max(0, width * progress - (scrubbing ? 8 : 4.5)))
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .overlay(alignment: .topLeading) {
                if scrubbing {
                    Text("\(Self.timecode(currentSeconds)) / \(Self.timecode(durationSeconds))")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.6), in: Capsule())
                        .overlay { Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.5) }
                        .fixedSize()
                        .offset(x: min(max(0, width * progress - 40), width - 84), y: -32)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if !scrubbing {
                            Haptics.tap()
                            withAnimation(.easeOut(duration: 0.15)) { scrubbing = true }
                        }
                        progress = min(max(v.location.x / max(geo.size.width, 1), 0), 1)
                        currentSeconds = progress * durationSeconds
                    }
                    .onEnded { v in
                        let fraction = min(max(v.location.x / max(geo.size.width, 1), 0), 1)
                        seek(to: fraction)
                        Haptics.tap()
                        withAnimation(.easeOut(duration: 0.15)) { scrubbing = false }
                    }
            )
        }
        .frame(height: 26)
        .accessibilityLabel("Video progress")
    }

    /// 83 → "1:23" — the scrub pill's timecode.
    private static func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func updateProgress() {
        guard let item = player.currentItem else { return }
        let dur = item.duration.seconds
        guard dur.isFinite, dur > 0 else { return }
        durationSeconds = dur
        // Buffered fraction — the pale track ahead of the playhead.
        if let range = item.loadedTimeRanges.first?.timeRangeValue {
            let end = range.start.seconds + range.duration.seconds
            if end.isFinite {
                buffered = min(max(end / dur, 0), 1)
            }
        }
        guard !scrubbing else { return }
        let now = player.currentTime().seconds
        currentSeconds = now
        progress = min(max(now / dur, 0), 1)
    }

    private func seek(to fraction: Double) {
        guard let item = player.currentItem else { return }
        let dur = item.duration.seconds
        guard dur.isFinite, dur > 0 else { return }
        let target = CMTime(seconds: dur * fraction, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        if isActive && !paused { player.play() }
    }

    // MARK: - Playback

    private func configureIfNeeded() {
        guard isResident, let url = videoURL else { return }
        // Inactive/preloaded cards must not repeatedly reconfigure the global audio session.
        if isActive, !WhisperCameraCallMonitor.shared.callOwnsAudio, WhisperCallService.shared.active == nil {
            let session = AVAudioSession.sharedInstance()
            if session.category != .playback || session.mode != .moviePlayback {
                try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
                try? session.setActive(true)
            }
        }

        if player.currentItem == nil {
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 2
            videoFrameReady = false
            player.replaceCurrentItem(with: item)
            WhisperPerformance.waveItemChanged(by: 1)
            if resumeTime > .zero { player.seek(to: resumeTime) }
            player.actionAtItemEnd = .none
            player.automaticallyWaitsToMinimizeStalling = false
        }
        if looper == nil, let item = player.currentItem {
            looper = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { _ in
                guard player.currentItem === item else { return }
                let shouldResume = player.rate > 0
                player.seek(to: .zero)
                if shouldResume { player.play() }
            }
        }
        player.isMuted = muted
        if isActive && !paused { player.play() }
    }

    /// The big gradient heart in the center of the wave.
    private func burstHeart() {
        heartTilt = Double.random(in: -14...14)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) { doubleTapHeart = true }
        Task {
            try? await Task.sleep(for: .milliseconds(680))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) { doubleTapHeart = false }
            }
        }
    }

    private func toggleLike() {
        let wasLiked = liked
        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
            liked.toggle()
            likes += liked ? 1 : -1
        }
        Haptics.tap()
        if !wasLiked {
            burstHeart()
            WhisperMeetChime.playLike()
        }
        Task {
            let newLiked = await backend.toggleLike(postID: postIDString)
            if newLiked != liked {
                await MainActor.run {
                    withAnimation(.spring(response: 0.25)) {
                        liked = wasLiked
                        likes += wasLiked ? 1 : -1
                    }
                }
            }
        }
    }

    /// 12300 → "12.3K" — keeps the rail labels compact.
    private func compactCount(_ n: Int) -> String {
        switch n {
        case ..<1000: return "\(n)"
        case ..<1_000_000:
            let v = Double(n) / 1000
            return v >= 100 ? "\(Int(v))K" : String(format: "%.1fK", v).replacingOccurrences(of: ".0K", with: "K")
        default:
            let v = Double(n) / 1_000_000
            return String(format: "%.1fM", v).replacingOccurrences(of: ".0M", with: "M")
        }
    }
}

// MARK: - Share sheet ("Add wave to your story")

/// The composed story hand-off: the color-sampled gradient canvas + the
/// wave card sticker, opened in the story editor.
struct WaveStoryShare: Identifiable {
    let id = UUID()
    let background: UIImage
    let sticker: WhisperStorySticker
}

/// Instagram's reel share sheet, Whisper-sized: the wave's thumbnail and
/// author up top, then "Add wave to your story" (IG's first row), "Send
/// to…" (the DM recipient picker), and "Copy link".
struct WhisperWaveShareSheet: View {
    let post: WhisperPost
    let onAddToStory: () -> Void
    let onSend: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var copied: Bool = false

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black)
                    if let u = post.mediaURLs.first(where: { !WhisperVideo.isVideo($0) }) {
                        WhisperCachedAsyncImage(url: u) { phase in
                            if case .success(let img) = phase { img.resizable().aspectRatio(contentMode: .fill) }
                        }
                    } else {
                        Image(systemName: "play.rectangle.on.rectangle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .frame(width: 46, height: 62)
                .clipShape(.rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Wave by @\(post.username)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text(post.displayCaption.isEmpty ? "Share this wave" : post.displayCaption)
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            VStack(spacing: 0) {
                row(icon: "plus.circle.fill", title: "Add wave to your story", subtitle: "Shares the wave as a card on your story for 24 hours", accent: true) {
                    Haptics.tap()
                    onAddToStory()
                }
                Divider().padding(.leading, 62)
                row(icon: "paperplane.fill", title: "Send to…", subtitle: "Pick a friend or a group") {
                    Haptics.tap()
                    onSend()
                }
                Divider().padding(.leading, 62)
                row(icon: copied ? "checkmark.circle.fill" : "link", title: copied ? "Link copied" : "Copy link", subtitle: "mydailywhisper.com") {
                    Haptics.tap()
                    UIPasteboard.general.string = "https://www.mydailywhisper.com/post/\(post.id.uuidString.lowercased())"
                    withAnimation(.spring(response: 0.3)) { copied = true }
                }
            }
            .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
            .padding(.horizontal, 14)
            Spacer(minLength: 0)
        }
        .background(WhisperTheme.surface(colorScheme).ignoresSafeArea())
    }

    private func row(icon: String, title: String, subtitle: String, accent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(accent ? Color.white : WhisperTheme.ink(colorScheme))
                    .frame(width: 36, height: 36)
                    .background(
                        accent
                            ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.98, green: 0.35, blue: 0.55), Color(red: 0.55, green: 0.31, blue: 0.97)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(WhisperTheme.hairline(colorScheme).opacity(0.6)),
                        in: Circle()
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reels tab

/// Root-tab wrapper for the Reels player — maps the backend post cache
/// into the reels pool and pauses playback whenever the tab goes off
/// screen so audio never leaks into other tabs.
struct WhisperReelsTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    var isActive: Bool = true
    /// Swipe-right-to-exit on the For-you scope hands control back to the
    /// host, which switches to the Home tab.
    var onExit: (() -> Void)? = nil
    @State private var backend = WhisperBackendService.shared
    @State private var visible: Bool = false
    @State private var reelRows: [WhisperPostRow] = []
    @State private var refreshError: String?
    @State private var reelGeneration: UUID = UUID()
    @State private var refreshInFlight: Bool = false
    @State private var next: WhisperHistoryCursor?
    @State private var hasLoaded = false
    @State private var retryReconciliation = false
    @State private var retryOlder = false
    @State private var lastDemandID: String?
    @State private var pageTask: Task<Void, Never>?

    private var reelsPool: [WhisperPost] {
        let pool = reelRows
            .map { row in
                WhisperRootView.mapRowToPost(
                    row,
                    fallbackUsername: backend.postAuthorProfiles[row.user_id]?.username
                )
            }
            .filter { p in
                p.mediaURLs.contains(where: { WhisperVideo.isVideo($0) })
            }
        // The stored sequence is ranked once per arrival batch. Recomputing
        // watch/engagement scores must not move the Wave under the reader.
        return pool
    }

    var body: some View {
        WhisperReelsPlayerView(reels: reelsPool, embedded: true, isVisible: visible && isActive, onExit: onExit,
            hasMore: next != nil, isLoadingMore: refreshInFlight, continuationError: refreshError,
            onNearEnd: { id in
                guard lastDemandID != id, refreshError == nil else { return }
                lastDemandID = id
                await loadWaves(older: true)
            }, onLoadMore: { await loadWaves(older: refreshError == nil ? hasLoaded : retryOlder, revalidate: retryReconciliation) },
            onRefresh: { cancelPage(); await loadWaves(older: false) })
            .onAppear { visible = true }
            .onDisappear { visible = false; cancelPage() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
                cancelPage()
                reelRows = []; refreshError = nil; next = nil; hasLoaded = false; lastDemandID = nil; retryReconciliation = false
            }
            .task(id: "\(isActive && visible && scenePhase == .active)-\(AccountStorage.currentUserID)") {
                guard isActive, visible, scenePhase == .active else { return }
                await loadWaves(older: false, revalidate: hasLoaded)
                // No overlapping 120-row polling/replacement. Older pages are
                // demand-owned, and an explicit refresh starts a new sequence.
            }
            .onChange(of: isActive && scenePhase == .active) { _, active in
                if !active { cancelPage() }
            }
            .accessibilityAction(named: "Refresh waves") {
                cancelPage()
                Task { await loadWaves(older: false) }
            }
    }

    private func cancelPage() {
        reelGeneration = UUID()
        pageTask?.cancel(); pageTask = nil; refreshInFlight = false
        lastDemandID = nil
    }

    private func loadWaves(older: Bool, revalidate: Bool = false) async {
        guard isActive, visible, scenePhase == .active, !Task.isCancelled,
              !refreshInFlight, !older || next != nil else { return }
        refreshInFlight = true
        let generation = reelGeneration
        let account = AccountStorage.generation
        let cursor = older ? next : nil
        let task = Task {
            defer { if generation == reelGeneration { refreshInFlight = false; pageTask = nil } }
            do {
                if revalidate {
                    let verified = try await backend.reconcileReelRows(reelRows)
                    guard !Task.isCancelled, isActive, visible, scenePhase == .active,
                          generation == reelGeneration, account == AccountStorage.generation else { return }
                    reelRows = verified
                    refreshError = nil; retryReconciliation = false
                    return
                }
                let page = try await backend.fetchReelPage(before: cursor)
                guard !Task.isCancelled, isActive, visible, scenePhase == .active,
                      generation == reelGeneration, account == AccountStorage.generation else { return }
                let mapped = page.rows.map { WhisperRootView.mapRowToPost($0, fallbackUsername: backend.postAuthorProfiles[$0.user_id]?.username) }
                let ranks = Dictionary(WhisperAlgorithmService.wavesRank(mapped).enumerated().map { ($0.element.id.uuidString.lowercased(), $0.offset) }, uniquingKeysWith: { a, _ in a })
                let ranked = page.rows.sorted { (ranks[$0.id.lowercased()] ?? Int.max) < (ranks[$1.id.lowercased()] ?? Int.max) }
                reelRows = older ? WhisperFeedPaging.append(ranked, to: reelRows, deleted: backend.deletedPostIDs) : ranked
                next = page.next
                hasLoaded = true
                refreshError = nil; retryReconciliation = false
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled, generation == reelGeneration, account == AccountStorage.generation else { return }
                retryReconciliation = revalidate
                retryOlder = older
                refreshError = "Waves couldn’t load just now."
            }
        }
        pageTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }
}

/// Raw `AVPlayerLayer`-backed view so the video fills the screen TikTok-style
/// (`resizeAspectFill`) with no system controls and no tap-through chrome.
private struct ReelPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var onReadyChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onReadyChanged) }

    final class Coordinator {
        var callback: (Bool) -> Void
        var observation: NSKeyValueObservation?
        weak var layer: AVPlayerLayer?
        init(_ callback: @escaping (Bool) -> Void) { self.callback = callback }
        func observe(_ layer: AVPlayerLayer) {
            self.layer = layer
            observation = layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
                Task { @MainActor [weak self, weak layer] in
                    guard let self, let layer, self.layer === layer else { return }
                    self.callback(layer.isReadyForDisplay)
                }
            }
        }
    }

    func makeUIView(context: Context) -> PlayerContainerView {
        let v = PlayerContainerView()
        v.backgroundColor = .black
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspectFill
        context.coordinator.observe(v.playerLayer)
        return v
    }

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: Coordinator) {
        coordinator.observation = nil
        coordinator.layer = nil
        uiView.playerLayer.player = nil
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        context.coordinator.callback = onReadyChanged
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

final class PlayerContainerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
