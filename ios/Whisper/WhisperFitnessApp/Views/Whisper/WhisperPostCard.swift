import SwiftUI

/// Shared real-post presentation for Home, profiles and discussion.
struct WhisperPostCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.whisperMediaActive) private var surfaceActive
    @State private var visibleInScroll: Bool = false
    private var canRecordView: Bool { !isPreview && surfaceActive && visibleInScroll && !presentDetail && !presentPhotoViewer }
    let post: WhisperPost
    /// A detail host supplies discussion navigation instead of opening another copy.
    var onOpenDiscussion: ((Bool) -> Void)? = nil
    var onDeleted: (() -> Void)? = nil
    var isPreview: Bool = false
    /// Compact connected original above a focused reply, never a second detail host.
    var isThreadContext: Bool = false
    var quoteDepth: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Community special react — when set (rendering inside a community
    /// feed), liking bursts THIS emoji and the filled heart becomes the
    /// community's signature react (⚖️ in Whisper Law, 💪 at your gym).
    var specialReact: String? = nil
    @State private var moderation = WhisperModerationService.shared
    @State private var backend = WhisperBackendService.shared
    @State private var ghostService = WhisperGhostService.shared
    @State private var presentModerationSheet: Bool = false
    @State private var presentComments: Bool = false
    @State private var presentDetail: Bool = false
    /// When true, the detail view auto-focuses its reply bar on open — set
    /// by the comment icon so "tap comment" means "start writing a reply".
    @State private var detailFocusReply: Bool = false
    @State private var presentForward: Bool = false
    /// Press and hold the bookmark → Instagram's "Save to collection" sheet.
    @State private var presentSaveToCollection: Bool = false
    @State private var bookmarkPressing: Bool = false
    @State private var presentLikers: Bool = false
    @State private var presentUser: WhisperUserRow?
    @State private var resolvingUser: Bool = false
    @State private var presentEmberProfile: Bool = false
    @State private var coach = WhisperCoachService.shared
    @State private var bookmarks = WhisperBookmarkService.shared
    @State private var ember = WhisperEmberService.shared
    @State private var confirmDelete: Bool = false
    @State private var deleted: Bool = false
    @State private var presentInsights: Bool = false
    @State private var presentReport: Bool = false
    @State private var presentRepostMenu: Bool = false
    @State private var presentQuoteComposer: Bool = false
    @State private var pendingRepostQuote: Bool = false
    @State private var repostError: String?
    @State private var repostGeneration: UUID = AccountStorage.generation
    @State private var reposts = WhisperRepostService.shared
    @State private var presentFactCheck: Bool = false
    @State private var factCheckResult: WhisperEmberService.FactCheck?
    @State private var factCheckLoading: Bool = false
    @State private var presentPhotoViewer: Bool = false
    @State private var photoViewerStartIndex: Int = 0
    /// Carousel-wide pinch magnification while a pinch is live. Drives the
    /// progress that closes the gap between photos — turning the gallery
    /// into a panoramic strip.
    @State private var carouselPinch: CGFloat = 1.0
    @State private var carouselPinchActive: Bool = false
    /// Persists across gestures: once the user has pinched the photos
    /// together they stay that way (panoramic). Pinching out again on
    /// the merged strip restores the gap.
    @State private var carouselMerged: Bool = false
    /// Currently centered card index in the carousel — used for haptic
    /// feedback while pinching.
    @State private var focusedIndex: Int? = 0
    /// Top-liked comment preview shown inline on the card (Threads-style).
    /// Loaded lazily when the post has at least one reply.
    @State private var topComment: WhisperCommentRow?
    /// Number of root-level self-replies by the post author. The original
    /// post is 1/N, each self-reply is 2/N, 3/N… (Threads numbering).
    @State private var selfThreadCount: Int = 0
    /// 1-based position of the top-comment preview inside the author's
    /// self-thread chain, if it is one. `nil` when the top comment is
    /// from a different user.
    @State private var topCommentThreadIndex: Int? = nil
    /// Floating category emoji burst played when the viewer likes /
    /// reposts / shares the post. The emoji is picked from the caption
    /// and post kind so a workout pops 💪, a business post 💼, a
    /// celebratory caption 🎉, and so on.
    @State private var reactionEmoji: String = ""
    @State private var reactionTrigger: Int = 0
    /// X-offset (from leading edge of the action row) at which the
    /// reaction-burst emoji should pop. Updated per action so the burst
    /// floats up directly over the icon the user just tapped instead of
    /// always firing from the like button.
    @State private var reactionAnchorX: CGFloat = 16
    /// Bumped after a real repost happens — spins the repost glyph.
    @State private var repostSpinTrigger: Int = 0
    /// Bumped when the share icon is tapped — launches the paperplane.
    @State private var shareFlyTrigger: Int = 0
    @State private var notes = WhisperCommunityNotesService.shared
    @State private var presentCommunityNotes: Bool = false
    @State private var verifiedPerks = WhisperVerifiedPerksService.shared
    /// Branded ellipsis menu — replaces the system `Menu` bubble so the
    /// 3-dots sheet matches Whisper on every platform.
    @State private var postMenu: WhisperActionMenuModel?
    /// Local mutable mirror of `post.liked` / `post.likes` so the like button
    /// can toggle optimistically without mutating the immutable `post`.
    @State private var localLiked: Bool = false
    @State private var localLikes: Int = 0
    /// Local mirror of `post.comments` so a reply posted from the detail
    /// page bumps the card's count immediately instead of after a refetch.
    @State private var localComments: Int = 0
    /// First likers for the Instagram "Liked by X and others" line under
    /// grid posts (session-cached per post so scroll re-mounts don't refetch).
    @State private var likersPreview: [WhisperLiker] = []
    /// Instagram double-tap heart burst over grid media.
    @State private var igHeartVisible: Bool = false
    @State private var storyRingService = WhisperStoryService.shared
    /// IG behavior: a ringed avatar opens the author's story instead of the
    /// profile (unringed avatars keep jumping to the profile).
    @State private var presentAuthorStories: Bool = false
    @State private var deleting: Bool = false
    @State private var deleteFailed: Bool = false

    /// True if the local user authored this post — enables the Delete menu.
    private var isMyPost: Bool {
        backend.ownsPost(postIDString)
    }

    private func openDiscussion() {
        if let onOpenDiscussion {
            onOpenDiscussion(detailFocusReply)
            detailFocusReply = false
        } else {
            presentDetail = true
        }
    }

    private var postIDString: String { post.id.uuidString.lowercased() }
    private var isGhost: Bool { ghostService.isGhost(postIDString) }

    private var observedContent: some View {
        Group {
            if !deleted && !backend.deletedPostIDs.contains(postIDString) {
                VStack(alignment: .leading, spacing: 0) {
                // A wave that opted into the feed ("Also share to feed") wears
                // the Instagram card too — the reel-in-feed grammar.
                if quoteDepth > 0 {
                    quotedBody
                } else if isThreadContext {
                    threadContextPost
                } else if WhisperPostPresentationPolicy.usesMediaCard(kind: post.kind, isReel: post.isReel) {
                    igMediaCard
                } else if onOpenDiscussion != nil {
                    threadDetailPost
                } else {
                    threadsRow
                }
                WhisperPostCorrectionNotice(postID: postIDString).padding(.horizontal, 16)
                }
            }
        }
        .background {
            if !isPreview, onOpenDiscussion == nil, !deleted {
                Button { detailFocusReply = false; openDiscussion() } label: {
                    Color.clear.contentShape(.rect)
                }.buttonStyle(.plain).accessibilityLabel("Open full post")
            }
        }
        .onAppear {
            // Sync local like state — prefer the live backend set over the
            // immutable `post.liked` snapshot so likes persist across app
            // restarts (fetchMyLoads populates myLikedPostIDs from the DB).
            localLiked = backend.myLikedPostIDs.contains(postIDString) || post.liked
            localLikes = post.likes
            localComments = post.comments
            if let rows = backend.commentsByPostID[postIDString] { updateCommentPreview(rows) }

        }
        .onChange(of: backend.myLikedPostIDs) { _, newSet in
            // Re-sync when the backend's liked set updates (e.g. after
            // the batched likes read completes or another screen toggles a like).
            let backendLiked = newSet.contains(postIDString)
            if backendLiked != localLiked {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                    localLiked = backendLiked
                }
            }
        }
        .onChange(of: post.likes) { _, value in localLikes = value }
        .onChange(of: post.comments) { _, value in localComments = value }
        .onChange(of: backend.commentsByPostID[postIDString]) { _, rows in
            // Cache eviction is not a deletion; an explicit empty response is.
            if let rows { updateCommentPreview(rows) }
        }
        .task(id: "\(postIDString)-\(post.comments)-\(surfaceActive && visibleInScroll)") {
            guard surfaceActive, visibleInScroll, !isPreview else { return }
            backend.ensurePostLikeLoaded(postID: postIDString)
            await loadTopComment()
        }
        .onReceive(NotificationCenter.default.publisher(for: .whisperCommentPosted)) { note in
            guard (note.userInfo?["postID"] as? String)?.lowercased() == postIDString else { return }
            withAnimation(.whisperSnappy) { localComments += 1 }
        }
        .whisperActionMenu($postMenu)
        .alert(post.isReel ? "Delete this wave?" : "Delete this post?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                guard !deleting else { return }
                deleting = true
                let generation = AccountStorage.generation
                Task {
                    let ok = await backend.deletePost(postID: postIDString)
                    guard generation == AccountStorage.generation else { return }
                    deleting = false
                    if ok {
                        withAnimation(.spring(response: 0.3)) { deleted = true }
                        Haptics.success()
                        onDeleted?()
                    } else {
                        deleteFailed = true
                        Haptics.warning()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove your post for everyone. This can't be undone.")
        }
        .alert("Couldn't delete", isPresented: $deleteFailed) {
            Button("Try again") { confirmDelete = true }
            Button("Cancel", role: .cancel) {}
        } message: { Text(backend.lastError ?? "Please check your connection and try again.") }
        .task(id: post.username) {
            guard !isPreview else { return }
            await coach.ensureCoachStatus(username: post.username)
        }
        .task(id: postIDString) {
            guard !isPreview else { return }
            // Session-cached variants — cards remount constantly while the
            // user scrolls, so each one must NOT re-fire its full request
            // fan-out (comments preview, notes, repost count) every time.
            // The independent lookups run together: one round trip of
            // latency per card instead of six in a row.
            async let noteRefresh: Void = notes.refreshIfNeeded(postID: postIDString)
            async let repostCount: Int = reposts.fetchCountIfNeeded(for: postIDString)
            async let likers: Void = loadLikersPreviewIfNeeded()
            _ = await (noteRefresh, repostCount, likers)
        }
        .onScrollVisibilityChange(threshold: 0.3) { visibleInScroll = $0 }
        .task(id: "\(postIDString)-\(canRecordView)") {
            await trackVisiblePost()
        }
    }

    var body: some View {
        observedContent
        // Full-screen cover (with NavigationStack) instead of a sheet so
        // tapping a post header / media / comment count opens the detail
        // page the same way activity-section taps do — true push feel
        // with the detail view's built-in chevron back. No more
        // half-sheet with a drag handle inconsistency in the feed.
        .fullScreenCover(isPresented: $presentDetail, onDismiss: { detailFocusReply = false }) {
            if post.isReel {
                // A wave opens as a wave — the full-screen player, never a
                // detail page.
                WhisperReelsPlayerView(reels: [post], start: post)
            } else {
                WhisperPostDetailView(post: post, autoFocusReply: detailFocusReply)
            }
        }
        .fullScreenCover(isPresented: $presentInsights) {
            WhisperPostActivityView(postID: postIDString)
        }
        .fullScreenCover(isPresented: $presentQuoteComposer) {
            WhisperComposerView(initialQuotedPost: post)
        }
        .sheet(isPresented: $presentRepostMenu, onDismiss: {
            guard pendingRepostQuote else { return }
            pendingRepostQuote = false
            guard repostGeneration == AccountStorage.generation else { return }
            presentQuoteComposer = true
        }) {
            WhisperRepostOptionsSheet(
                isReposted: reposts.isReposted(postIDString),
                hasMedia: !post.mediaURLs.isEmpty,
                onQuote: {
                    playReaction(.repost)
                    repostSpinTrigger &+= 1
                    repostGeneration = AccountStorage.generation
                    pendingRepostQuote = true
                },
                onMarkup: {
                    playReaction(.repost)
                    repostSpinTrigger &+= 1
                    repostGeneration = AccountStorage.generation
                    pendingRepostQuote = true
                },
                onUseMedia: {
                    playReaction(.repost)
                    repostSpinTrigger &+= 1
                    repostGeneration = AccountStorage.generation
                    pendingRepostQuote = true
                },
                onRepostOnly: {
                    let generation = AccountStorage.generation
                    Task {
                        let wasReposted = reposts.isReposted(postIDString)
                        let current = await reposts.toggle(postID: postIDString)
                        guard generation == AccountStorage.generation else { return }
                        guard current != wasReposted else { repostError = "Couldn't update your repost. Please try again."; return }
                        if !wasReposted {
                            await MainActor.run {
                                Haptics.success()
                                playReaction(.repost)
                                repostSpinTrigger &+= 1
                            }
                        } else {
                            await MainActor.run { Haptics.soft() }
                        }
                    }
                }
            )
            .whisperSheetBorder()
        }
        .alert("Repost not updated", isPresented: Binding(get: { repostError != nil }, set: { if !$0 { repostError = nil } })) {
            Button("OK") { repostError = nil }
        } message: { Text(repostError ?? "") }
        .sheet(isPresented: $presentReport) {
            WhisperReportSheet(
                kind: .post,
                targetID: postIDString,
                targetUserID: nil,
                targetUsername: post.username
            )
            .whisperSheetBorder()
        }
        .sheet(isPresented: $presentForward) {
            WhisperPostShareSheet(post: post)
        }
        .fullScreenCover(isPresented: $presentLikers) {
            WhisperPostActivityView(postID: postIDString)
        }
        .sheet(isPresented: $presentFactCheck) {
            factCheckSheet
                .presentationDetents([.fraction(0.5), .medium])
                .presentationDragIndicator(.visible)
                .whisperSheetBorder()
        }
        .sheet(isPresented: $presentCommunityNotes) {
            WhisperCommunityNotesSheet(postID: postIDString)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .whisperSheetBorder()
        }
        .fullScreenCover(isPresented: $presentPhotoViewer) {
            WhisperPostPhotoViewer(urls: post.mediaURLs, startIndex: photoViewerStartIndex)
        }
        .navigationDestination(item: $presentUser) { user in
            WhisperUserProfileView(user: user)
        }
        .navigationDestination(isPresented: $presentEmberProfile) {
            WhisperEmberProfileView()
        }
    }

    private func trackVisiblePost() async {
        guard canRecordView, !Task.isCancelled else { return }
        WhisperFeedSeenTracker.shared.markSeen(post.id)
        let postID: String = postIDString
        let authorUID: String? = insightsAuthorUserID(for: postID)
        await WhisperPostInsightsService.shared.trackView(postID: postID, authorUserID: authorUID)
        guard canRecordView, !Task.isCancelled else { return }
        await maybeAutoFactCheck()
    }

    private func insightsAuthorUserID(for postID: String) -> String? {
        let feedPost: WhisperPostRow? = backend.posts.first(where: { row in
            row.id == postID
        })
        if let feedPost { return feedPost.user_id }
        let ownPost: WhisperPostRow? = backend.myPosts.first(where: { row in
            row.id == postID
        })
        return ownPost?.user_id
    }

    /// Inline verdict badge shown directly on the post when Jasper's
    /// auto fact-check has flagged the caption as false or misleading.
    /// Tapping opens the full fact-check sheet (claim + summary +
    /// explanation + sources) so the viewer can see exactly how Jasper
    /// reached the verdict.
    /// Top-right verdict chip — mirrors the verified seal style but with
    /// a thumbs-down glyph and a verdict tint (red = false, amber =
    /// misleading). Unverified posts get no chip. Tapping opens the
    /// fact-check sheet with Jasper's reasoning and sources.
    @ViewBuilder
    private var factCheckBadge: some View {
        if let r = factCheckResult,
           r.verdict == .falseClaim || r.verdict == .misleading {
            let tint: Color = r.verdict == .falseClaim
                ? Color(red: 0.90, green: 0.22, blue: 0.22)
                : Color(red: 0.95, green: 0.70, blue: 0.18)
            Button {
                Haptics.tap()
                presentFactCheck = true
            } label: {
                Image(systemName: "hand.thumbsdown.fill")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.82)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Circle()
                    )
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                    )
                    .shadow(color: tint.opacity(0.45), radius: 2.5, y: 0.5)
                    .accessibilityLabel(Text(r.verdict == .falseClaim ? "False" : "Misleading"))
            }
            .buttonStyle(.plain)
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
        }
    }

    /// Short one-liner shown inside the inline badge. Prefers Jasper's
    /// summary field, falls back to the first sentence of the
    /// explanation, and finally a generic phrase keyed off the verdict.
    private func factCheckBadgeSummary(_ r: WhisperEmberService.FactCheck) -> String {
        let summary = r.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty { return summary }
        let explanation = r.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explanation.isEmpty {
            if let end = explanation.firstIndex(where: { ".!?".contains($0) }) {
                return String(explanation[...end])
            }
            return explanation
        }
        switch r.verdict {
        case .falseClaim:  return "Jasper could not verify this claim and found contradicting sources."
        case .misleading:  return "Jasper found this claim to be missing important context."
        case .unverified:  return "Jasper could not find reliable sources to verify this claim."
        default:           return ""
        }
    }

    @ViewBuilder
    private var factCheckSheet: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                            Text("Fact-check")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                            Spacer()
                        }
                        Text("\u{201C}\(post.displayCaption)\u{201D}")
                            .font(.subheadline.italic())
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                        if let r = factCheckResult {
                            WhisperFactCheckInlineCard(
                                payload: .init(
                                    id: postIDString,
                                    claim: post.displayCaption,
                                    verdictRaw: r.verdict.rawValue,
                                    summary: r.summary,
                                    explanation: r.explanation,
                                    sources: r.sources
                                ),
                                mine: false
                            )
                        } else if factCheckLoading {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Jasper is checking sources\u{2026}")
                                    .font(.subheadline)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("AI analysis · not moderation")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// CACHE-ONLY hydration as the post scrolls into view — shows a verdict
    /// badge if this post was already fact-checked this session, but never
    /// spends an AI call in the background. Fresh checks run only from the
    /// explicit "Fact-check with Jasper" menu action (`runFactCheck`).
    private func maybeAutoFactCheck() async {
        if let cached = ember.cachedFactCheck(postID: postIDString) {
            await MainActor.run { factCheckResult = cached }
        }
    }

    private func runFactCheck(silent: Bool = false) async {
        guard factCheckResult == nil, !factCheckLoading else { return }
        if !silent { factCheckLoading = true }
        let r = await ember.factCheck(post.displayCaption)
        await MainActor.run {
            factCheckResult = r
            factCheckLoading = false
        }
        // Cache the verdict so re-mounts of this card (scroll out + back
        // in, profile → feed jumps) render the badge instantly.
        ember.cacheFactCheck(postID: postIDString, result: r)
        // Optional AI analysis never issues strikes, corrections, or restrictions.
    }

    private func toggleBookmarkWithAutoCategorize() async {
        let wasBookmarked = bookmarks.isBookmarked(postIDString)
        await bookmarks.toggle(postID: postIDString)
        // Only auto-categorize when newly saved and not already assigned.
        guard !wasBookmarked,
              bookmarks.isBookmarked(postIDString),
              bookmarks.category(forPostID: postIDString) == "All",
              !post.caption.isEmpty else { return }
        if let cat = await ember.autoCategorize(caption: post.caption, available: bookmarks.categories) {
            await MainActor.run {
                bookmarks.setCategory(cat, forPostID: postIDString)
            }
        }
    }

    private func openProfile() {
        // Tapping the Jasper avatar/username opens Jasper's curated profile
        // — a list of every post Jasper has replied to via `@ember`.
        if post.username.lowercased() == "ember" {
            presentEmberProfile = true
            return
        }
        guard !resolvingUser else { return }
        resolvingUser = true
        Task {
            let row = await WhisperUserService.shared.fetchByUsername(post.username)
            await MainActor.run {
                resolvingUser = false
                presentUser = row
            }
        }
    }

    /// Threads-style row: avatar column on the left, content column on the
    /// right (username/time header, caption text, optional rounded media,
    /// compact action row). Replaces the old IG card layout entirely.
    private var threadsRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                threadAuthorAvatar
                VStack(alignment: .leading, spacing: 4) {
                    // Header is its own tap target so the ellipsis menu /
                    // username button inside still fire correctly.
                    threadsHeader
                    // Caption sits OUTSIDE the outer Button so the inline
                    // `@user` / `#tag` AttributedString links in
                    // `WhisperMentionText` actually receive the tap. A
                    // background tap on the caption still opens detail via
                    // an explicit gesture (links shadow this gesture).
                    let visibleCaption = displayedCaption
                    if !visibleCaption.isEmpty {
                        WhisperMentionText(text: visibleCaption, font: .subheadline, onOpenPost: {
                            Haptics.tap()
                            detailFocusReply = false
                            openDiscussion()
                        })
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    captionEmbedCards
                    if let top = notes.topNote(forPostID: postIDString) {
                        WhisperCommunityNoteInlineCard(
                            note: top,
                            totalNotes: notes.notes(forPostID: postIDString).count
                        ) {
                            Haptics.tap()
                            presentCommunityNotes = true
                        }
                    }
                    threadsMedia
                    threadsActions
                    threadsMetaLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(alignment: .leading) {
                if hasReplyPreview {
                    WhisperThreadConnector()
                        .stroke(WhisperTheme.hairline(colorScheme), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .allowsHitTesting(false)
                }
            }
            topCommentPreview
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .sheet(isPresented: $presentModerationSheet) {
            WhisperModerationSheet(username: post.username)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var threadContextPost: some View {
        HStack(alignment: .top, spacing: 8) {
            threadAuthorAvatar
            VStack(alignment: .leading, spacing: 2) {
                threadsHeader
                if !displayedCaption.isEmpty {
                    WhisperMentionText(text: displayedCaption, font: .subheadline, onOpenPost: {
                        detailFocusReply = false
                        openDiscussion()
                    }).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                }
                if !post.mediaURLs.isEmpty || displayedCaption.isEmpty {
                    Button {
                        detailFocusReply = false
                        openDiscussion()
                    } label: {
                        Label("View original \(post.isReel ? "wave" : "post")", systemImage: post.isReel ? "play.rectangle" : "arrow.up.right")
                            .font(.caption).frame(minHeight: 44)
                    }.buttonStyle(.plain).foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                threadsActions
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 12)
        .background(alignment: .leading) {
            WhisperThreadConnector(startY: 44)
                .stroke(WhisperTheme.hairline(colorScheme), style: StrokeStyle(lineWidth: 1.25, lineCap: .round))
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 12).padding(.top, 4)
    }

    /// The selected post expands out of the feed's avatar gutter, as in the reference.
    private var threadDetailPost: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                threadAuthorAvatar
                threadsHeader
            }
            if !displayedCaption.isEmpty {
                WhisperMentionText(text: displayedCaption, font: .subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            captionEmbedCards
            threadsMedia
            if let location = gridMeta?.location, !location.isEmpty {
                Text(location).font(.caption).foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            threadsActions
            if let top = notes.topNote(forPostID: postIDString) {
                WhisperCommunityNoteInlineCard(note: top, totalNotes: notes.notes(forPostID: postIDString).count) {
                    presentCommunityNotes = true
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 4)
        .sheet(isPresented: $presentModerationSheet) {
            WhisperModerationSheet(username: post.username)
                .presentationDetents([.large])
        }
    }

    private var hasReplyPreview: Bool {
        onOpenDiscussion == nil && gridMeta?.commentsOff != true && post.comments > 0
    }

    private var threadAuthorAvatar: some View {
        Button {
            Haptics.tap()
            if authorStoryRing != nil { presentAuthorStories = true }
            else { openProfile() }
        } label: {
            ZStack {
                WhisperAvatar(username: post.username, size: 38, ring: false)
                    .opacity(isGhost ? 0.85 : 1)
                if let ring = authorStoryRing {
                    Circle().strokeBorder(ring, lineWidth: authorHasUnseenStory ? 2 : 1)
                        .frame(width: 44, height: 44)
                } else if isGhost {
                    WhisperGhostRing(size: 44, lineWidth: 1.5)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(post.username)")
        .fullScreenCover(isPresented: $presentAuthorStories) { authorStoryViewer }
    }

    private var quotedBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Button { openProfile() } label: {
                    WhisperAvatar(username: post.username, size: 24, ring: false)
                }.buttonStyle(.plain)
                threadsHeader
            }
            if !displayedCaption.isEmpty {
                WhisperMentionText(text: displayedCaption, font: .subheadline)
            }
            captionEmbedCards
            threadsMedia
            threadsActions
        }
        .padding(12)
    }

    // MARK: - Instagram-style media card
    /// Full-width, photo-first card for posts with media. Header on top,
    /// 4:5 media carousel, action bar, likes, caption, and timestamp below.
    @ViewBuilder
    private var igMediaCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            igHeader
            igMediaCarousel
                // Long-press peek — flips through the whole set in place.
                .contextMenu {
                    Button {
                        Haptics.tap()
                        openDiscussion()
                    } label: {
                        Label("Open post", systemImage: "arrow.up.right.square")
                    }
                } preview: {
                    WhisperGridPostPeek(
                        urls: post.isReel
                            ? [WhisperPostMeta.coverURL(from: post.caption)].compactMap { $0 }
                            : post.mediaURLs,
                        caption: post.caption,
                        likes: localLikes,
                        comments: localComments
                    )
                }
            igActionBar
            igMeta
        }
        .padding(.bottom, 12)
        .background(WhisperTheme.surface(colorScheme))
    }

    @ViewBuilder
    private var igHeader: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                if authorStoryRing != nil {
                    presentAuthorStories = true
                } else {
                    openProfile()
                }
            } label: {
                ZStack {
                    if let ringStyle = authorStoryRing {
                        Circle()
                            .strokeBorder(ringStyle, lineWidth: authorHasUnseenStory ? 2.8 : 1.3)
                            .frame(width: 44, height: 44)
                    }
                    if isGhost {
                        WhisperGhostRing(size: 40, lineWidth: 1.5)
                    }
                    WhisperAvatar(username: post.username, size: 36)
                        .opacity(isGhost ? 0.85 : 1)
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $presentAuthorStories) { authorStoryViewer }

            // The handle is just as tappable as the avatar — both jump
            // straight to the author's profile. Timestamp lives up here in
            // the header (IG style, matching the web grid card) — NOT at the
            // bottom of the caption block.
            Button {
                Haptics.tap()
                openProfile()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(post.username)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        VerifiedBadge(
                            badge: UserVerificationService.shared.badge(forUsername: post.username),
                            size: 13,
                            username: post.username
                        )
                    }
                    // Instagram header: location under the username; the
                    // timestamp moved to the bottom of the card (kit order).
                    // A wave carries its SOUND line here instead (reel-in-feed).
                    if post.isReel {
                        HStack(spacing: 4) {
                            Image(systemName: "music.note")
                                .font(.caption2.weight(.semibold))
                            Text(waveSoundLine)
                                .lineLimit(1)
                        }
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.6))
                    } else if let location = gridMeta?.location, !location.isEmpty {
                        Text(location)
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.6))
                            .lineLimit(1)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                Haptics.tap()
                postMenu = buildPostMenu()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.55))
                    .frame(width: 22, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @State private var igCarouselIndex: Int = 0

    /// Instagram's reel-in-feed header line: the picked sound, or the
    /// creator's original audio.
    private var waveSoundLine: String {
        if let music = gridMeta?.music {
            return "\(music.title) · \(music.artist)"
        }
        return "\(post.username) · Original audio"
    }

    @ViewBuilder
    private var igMediaCarousel: some View {
        if post.isReel,
           let waveURL = post.mediaURLs.first(where: { WhisperVideo.isVideo($0) }) ?? post.mediaURLs.first {
            waveFeedMedia(url: waveURL)
        } else {
            igPhotoCarousel
        }
    }

    /// Instagram's reel-in-feed media: the wave inside the card's 4:5 frame
    /// over its blurred cover, playing muted, the Waves mark top-right, a
    /// tap opens the full-screen player, a double tap likes. Mirrors web
    /// `WaveFeedMedia`.
    @ViewBuilder
    private func waveFeedMedia(url: URL) -> some View {
        Color.black
            .overlay {
                if let cover = WhisperPostMeta.coverURL(from: post.caption) {
                    WhisperCachedAsyncImage(url: cover) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .blur(radius: 24)
                                .opacity(0.6)
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
            .overlay {
                if isPreview {
                    WhisperWavePosterView(videoURL: url, coverURL: WhisperPostMeta.coverURL(from: post.caption))
                } else {
                    WhisperVideoView(url: url, autoplay: !presentDetail && !presentPhotoViewer)
                }
            }
            .clipped()
            .overlay(alignment: .topTrailing) {
                WavesTabGlyph(isSelected: false, ink: .white)
                    .scaleEffect(0.82)
                    .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
                    .padding(10)
                    .allowsHitTesting(false)
            }
            .overlay {
                if igHeartVisible {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 96))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 4)
                        .transition(.scale(scale: 0.35).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(.rect)
            .onTapGesture(count: 2) {
                igDoubleTapLike()
            }
            .onTapGesture {
                Haptics.tap()
                openDiscussion()
            }
            .aspectRatio(4 / 5, contentMode: .fit)
    }

    @ViewBuilder
    private var igPhotoCarousel: some View {
        let urls = post.mediaURLs
        GeometryReader { geo in
            TabView(selection: $igCarouselIndex) {
                ForEach(Array(urls.enumerated()), id: \.offset) { idx, url in
                    Color(.secondarySystemBackground)
                        .overlay {
                            if WhisperVideo.isVideo(url), isPreview {
                                WhisperWavePosterView(videoURL: url, coverURL: WhisperPostMeta.coverURL(from: post.caption))
                            } else if WhisperVideo.isVideo(url) {
                                WhisperVideoView(url: url, autoplay: igCarouselIndex == idx && !presentPhotoViewer, showsMuteButton: false)
                                    .allowsHitTesting(false)
                            } else {
                                WhisperSizedAsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    case .empty:
                                        WhisperPhotoLoader()
                                    case .failure:
                                        Image(systemName: "photo")
                                            .font(.largeTitle)
                                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                                .allowsHitTesting(false)
                            }
                        }
                        .clipped()
                        .tag(idx)
                        .onTapGesture(count: 2) {
                            igDoubleTapLike()
                        }
                        .onTapGesture {
                            Haptics.tap()
                            if onOpenDiscussion == nil { detailFocusReply = false; openDiscussion() }
                            else { photoViewerStartIndex = idx; presentPhotoViewer = true }
                        }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .overlay(alignment: .topTrailing) {
                if urls.count > 1 {
                    Text("\(igCarouselIndex + 1) / \(urls.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.5))
                        .clipShape(.rect(cornerRadius: 12))
                        .padding(8)
                }
            }
            .overlay {
                if igHeartVisible {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 96))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 4)
                        .transition(.scale(scale: 0.35).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
        }
        .aspectRatio(4 / 5, contentMode: .fit)
        .overlay {
            if urls.isEmpty { ContentUnavailableView("Media unavailable", systemImage: "photo") }
        }
        .task(id: isPreview) {
            guard isPreview, !reduceMotion, urls.count > 1 else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1.8)) } catch { return }
                withAnimation(.easeInOut(duration: 0.25)) { igCarouselIndex = (igCarouselIndex + 1) % urls.count }
            }
        }
    }

    /// Optimistically toggles the like state, then reconciles with the backend.
    private func toggleLikeOptimistically() {
        let wasLiked = localLiked
        if !wasLiked {
            playReaction(.like)
            WhisperFeedback.liked()
        } else {
            WhisperFeedback.unliked()
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
            localLiked.toggle()
            localLikes += localLiked ? 1 : -1
        }
        Task {
            let newLiked = await backend.toggleLike(postID: postIDString)
            if newLiked != !wasLiked {
                await MainActor.run {
                    withAnimation {
                        localLiked = wasLiked
                        localLikes += wasLiked ? 1 : -1
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var igActionBar: some View {
        HStack(spacing: 4) {
            Button {
                toggleLikeOptimistically()
            } label: {
                Group {
                    if localLiked, let react = specialReact {
                        Text(react)
                            .font(.system(size: 20))
                    } else {
                        WhisperRoundedGlyph(kind: .heart, size: 22, selected: localLiked)
                            .foregroundStyle(localLiked ? WhisperTheme.likeRed : WhisperTheme.ink(colorScheme))
                    }
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)

            // Kit 4.0: the count sits right beside the icon (12/semibold).
            if gridMeta?.hideCounts != true && localLikes > 0 {
                Text(localLikes.formatted())
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .padding(.leading, -8)
            }

            if gridMeta?.commentsOff != true {
                Button {
                    Haptics.tap()
                    detailFocusReply = true
                    openDiscussion()
                } label: {
                    WhisperRoundedGlyph(kind: .comment, size: 22)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            if gridMeta?.commentsOff != true && gridMeta?.hideCounts != true && localComments > 0 {
                Text(localComments.formatted())
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .padding(.leading, -8)
            }

            Button {
                Haptics.tap()
                presentForward = true
            } label: {
                WhisperRoundedGlyph(kind: .plane, size: 22)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(false)
                    .accessibilityLabel("Share post")
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            // Tap saves; PRESS AND HOLD files it into a collection.
            Image(systemName: bookmarks.isBookmarked(postIDString) ? "bookmark.fill" : "bookmark")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
                .scaleEffect(bookmarkPressing ? 0.86 : 1)
                .animation(.spring(response: 0.28, dampingFraction: 0.7), value: bookmarkPressing)
                .contentTransition(.symbolEffect(.replace))
                .onTapGesture {
                    Haptics.tap()
                    Task { await toggleBookmarkWithAutoCategorize() }
                }
                .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 12) {
                    Haptics.rigid()
                    presentSaveToCollection = true
                } onPressingChanged: { down in
                    bookmarkPressing = down
                }
                .accessibilityLabel(bookmarks.isBookmarked(postIDString) ? "Saved" : "Save")
                .accessibilityHint("Double-tap to save, press and hold to pick a collection")
                .sheet(isPresented: $presentSaveToCollection) {
                    WhisperSaveToCollectionSheet(postID: postIDString)
                }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        // Instagram carousel dots — centered between the action clusters.
        .overlay {
            if post.mediaURLs.count > 1 {
                HStack(spacing: 4) {
                    ForEach(0..<post.mediaURLs.count, id: \.self) { i in
                        Circle()
                            .fill(i == igCarouselIndex
                                ? Color(red: 0.22, green: 0.59, blue: 0.94)
                                : WhisperTheme.ink(colorScheme).opacity(0.18))
                            .frame(
                                width: i == igCarouselIndex ? 6 : 5,
                                height: i == igCarouselIndex ? 6 : 5
                            )
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: igCarouselIndex)
                .allowsHitTesting(false)
            }
        }
    }

    /// Instagram double-tap: big white heart burst; likes, never unlikes.
    private func igDoubleTapLike() {
        Haptics.tap()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) {
            igHeartVisible = true
        }
        if !localLiked { toggleLikeOptimistically() }
        Task {
            try? await Task.sleep(for: .seconds(0.75))
            withAnimation(.easeOut(duration: 0.3)) { igHeartVisible = false }
        }
    }

    /// Loads the first likers once per post per session (grid cards only).
    private func loadLikersPreviewIfNeeded() async {
        guard post.kind == .grid, post.likes > 0 || localLikes > 0 else { return }
        if let cached = whisperGridLikersCache[postIDString] {
            likersPreview = cached
            return
        }
        let all = await WhisperBackendService.shared.fetchPostLikers(postID: postIDString)
        let preview = Array(all.prefix(3))
        whisperGridLikersCache[postIDString] = preview
        likersPreview = preview
    }

    @ViewBuilder
    private var igMeta: some View {
        let hideCounts = gridMeta?.hideCounts == true
        VStack(alignment: .leading, spacing: 7) {
            // Instagram music attribution — "♪ title · artist". When the
            // track carries a preview clip it actually PLAYS: tap toggles
            // the shared post player (one post at a time), the note glyph
            // becomes live equalizer bars while playing.
            if let music = gridMeta?.music {
                let trackID = music.id ?? "post-music-\(postIDString)"
                let player = WhisperStoryMusicPlayer.shared
                let isThisPlaying = player.nowPlayingID == trackID && player.isPlaying
                if let preview = music.previewURL, !preview.isEmpty {
                    Button {
                        Haptics.tap()
                        player.toggle(WhisperStoryMusic(
                            id: trackID,
                            title: music.title,
                            artist: music.artist,
                            artworkURL: music.artworkURL,
                            previewURL: preview
                        ))
                    } label: {
                        HStack(spacing: 6) {
                            if isThisPlaying {
                                WhisperEqualizerBars(
                                    color: WhisperTheme.ink(colorScheme),
                                    bars: 3,
                                    size: 9
                                )
                            } else {
                                Image(systemName: "music.note")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Text("\(music.title) · \(music.artist)")
                                .font(isThisPlaying ? .caption.weight(.semibold) : .caption)
                                .lineLimit(1)
                            Image(systemName: isThisPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 8, weight: .bold))
                                .opacity(0.55)
                        }
                        .foregroundStyle(
                            WhisperTheme.ink(colorScheme).opacity(isThisPlaying ? 0.95 : 0.65)
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "music.note")
                            .font(.system(size: 11, weight: .semibold))
                        Text("\(music.title) · \(music.artist)")
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.65))
                }
            }

            // "Liked by X and others" with the likers facepile — opens the
            // full likers sheet. Falls back to "N likes" while likers load.
            if !hideCounts && localLikes > 0 {
                Button {
                    Haptics.tap()
                    presentLikers = true
                } label: {
                    HStack(spacing: 8) {
                        if !likersPreview.isEmpty {
                            HStack(spacing: -7) {
                                ForEach(likersPreview) { liker in
                                    WhisperAvatar(username: liker.username, size: 18)
                                        .overlay(
                                            Circle().strokeBorder(
                                                WhisperTheme.surface(colorScheme),
                                                lineWidth: 1.5
                                            )
                                        )
                                }
                            }
                        }
                        likedByText
                            .lineLimit(1)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            // Caption with the bold inline username — Instagram grammar.
            let visibleCaption = displayedCaption
            if !visibleCaption.isEmpty {
                WhisperMentionText(text: visibleCaption, font: .subheadline, boldPrefix: post.username, onOpenPost: { detailFocusReply = false; openDiscussion() })
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let tagged = gridMeta?.tagged, !tagged.isEmpty {
                WhisperMentionText(
                    text: "with " + tagged.map { "@\($0)" }.joined(separator: " "),
                    font: .footnote
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            captionEmbedCards

            // "View all N comments" + the top comment preview line.
            // Turn-off-commenting (web Share step) hides every comment
            // affordance — same behavior as the web card.
            if onOpenDiscussion == nil, gridMeta?.commentsOff != true, localComments > 0 {
                Button {
                    Haptics.tap()
                    openDiscussion()
                } label: {
                    Text("View all \(localComments) comment\(localComments == 1 ? "" : "s")")
                        .font(.footnote)
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.5))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            if hasReplyPreview {
                Button {
                    Haptics.tap()
                    openDiscussion()
                } label: {
                    Text(topComment.map { $0.username + ": " + WhisperFeedReplyPreview.summaryText($0.body) } ?? "Open the conversation")
                        .font(.footnote).lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            // "Add a comment…" row — opens the thread with the reply bar
            // focused, exactly like tapping the comment icon.
            if gridMeta?.commentsOff != true {
                Button {
                    Haptics.tap()
                    detailFocusReply = true
                    openDiscussion()
                } label: {
                    HStack(spacing: 8) {
                        WhisperAvatar(username: viewerUsername, size: 24)
                        Text("Add a comment…")
                            .font(.footnote)
                            .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.45))
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.top, 1)
            }

            // Instagram bottom timestamp — long form, quiet.
            Text(igTimestamp)
                .font(.caption)
                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.42))
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
    }

    /// Post-meta payload (music/location/tagged/hideCounts) written by the
    /// grid composer — mirrors web `lib/postMeta.ts`.
    private var gridMeta: WhisperPostMeta? {
        WhisperPostMeta.parse(from: post.caption)
    }

    /// "Liked by first and others" — falls back to the plain count while
    /// the likers preview loads.
    private var likedByText: Text {
        if let first = likersPreview.first {
            var line = Text("Liked by ").font(.footnote)
            line = line + Text(first.username).font(.footnote.weight(.semibold))
            if localLikes > 1 {
                line = line + Text(" and ").font(.footnote)
                line = line + Text("\((localLikes - 1).formatted()) others").font(.footnote.weight(.semibold))
            }
            return line
        }
        return Text("\(localLikes) like\(localLikes == 1 ? "" : "s")")
            .font(.subheadline.weight(.semibold))
    }

    /// The signed-in viewer's handle — used for the add-a-comment avatar.
    private var viewerUsername: String {
        let me = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? ""
        return me.isEmpty ? "you" : me
    }

    /// Long-form Instagram bottom timestamp — "2 hours ago".
    private var igTimestamp: String {
        guard let date = post.createdAt else { return post.timeAgo }
        let s = Date().timeIntervalSince(date)
        if s < 60 { return "just now" }
        let m = Int(s / 60)
        if m < 60 { return "\(m) minute\(m == 1 ? "" : "s") ago" }
        let h = Int(s / 3600)
        if h < 24 { return "\(h) hour\(h == 1 ? "" : "s") ago" }
        let d = Int(s / 86_400)
        if d < 7 { return "\(d) day\(d == 1 ? "" : "s") ago" }
        let w = Int(s / 604_800)
        return "\(w) week\(w == 1 ? "" : "s") ago"
    }

    /// Instagram story ring around the grid header avatar — conic gradient
    /// while the author has unseen stories, hairline gray once viewed,
    /// nothing when they have no active story.
    private var authorHasUnseenStory: Bool {
        guard let group = storyRingService.storiesByUser().first(where: {
            $0.username.lowercased() == post.username.lowercased()
        }) else { return false }
        return storyRingService.hasUnseenStories(userID: group.userID)
    }

    private var authorStoryRing: AnyShapeStyle? {
        let hasStory = storyRingService.storiesByUser().contains {
            $0.username.lowercased() == post.username.lowercased()
        }
        guard hasStory else { return nil }
        return authorHasUnseenStory
            ? AnyShapeStyle(WhisperIGRing.gradient)
            : AnyShapeStyle(WhisperTheme.hairline(colorScheme))
    }

    /// Instagram's avatar story-jump: opens the author's stories at their
    /// group inside the full flow (next authors follow), oldest-first.
    @ViewBuilder
    private var authorStoryViewer: some View {
        let ordered = storyRingService.storiesByUser().map { Array($0.all.reversed()) }
        let gi = ordered.firstIndex { list in
            list.contains { $0.username.lowercased() == post.username.lowercased() }
        }
        if let gi {
            WhisperStoryViewer(
                groups: ordered,
                startGroup: gi,
                startIndex: storyRingService.firstUnseenIndex(in: ordered[gi])
            )
        } else {
            Color.black
                .ignoresSafeArea()
                .onAppear { presentAuthorStories = false }
        }
    }

    /// The community this post belongs to — the explicit composer pick wins
    /// (rendered by name, never a hashtag); legacy posts fall back to strict
    /// caption matching. Custom hubs not in the catalog still get a chip.
    private var matchedCommunity: WhisperCommunity? {
        if let cid = post.communityID, !cid.isEmpty {
            if let known = WhisperCommunity.catalog.first(where: { $0.id == cid }) {
                return known
            }
            return WhisperCommunity(
                id: cid,
                name: post.communityName ?? cid.capitalized,
                tagline: "",
                symbol: "person.2.fill",
                keywords: [],
                gradient: [Color(red: 0.98, green: 0.51, blue: 0.20), Color(red: 1.00, green: 0.72, blue: 0.42)]
            )
        }
        // EXPLICIT-ONLY: captions never auto-file a post into a community.
        return nil
    }

    /// Film/article embed lines planted in the caption by "Post to your
    /// wall" — stripped from the visible text and rendered as cards below.
    private var captionEmbeds: WhisperContentEmbedParser.Split {
        WhisperContentEmbedParser.parse(post.displayCaption)
    }

    /// Shared film/article cards rendered under the caption — the wall
    /// repost surface. Tap opens the native theater / reader.
    @ViewBuilder
    private var captionEmbedCards: some View {
        WhisperPostCaptionView(text: post.displayCaption, showsText: false, quoteDepth: quoteDepth, parentPostID: post.id)
    }

    /// The caption shown to the user. When the post matches a community,
    /// strip the leading/trailing `#community` hashtag so the chip in the
    /// header is the only surface that renders the community — the post
    /// body no longer reads like raw `#fitness` spam.
    private var displayedCaption: String {
        var s = captionEmbeds.cleaned
        if let c = matchedCommunity {
            let needle = "#" + c.name.replacingOccurrences(of: " ", with: "").lowercased()
            // Case-insensitive removal of every occurrence.
            while let r = s.range(of: needle, options: .caseInsensitive) {
                s.removeSubrange(r)
            }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }

    private var threadsHeader: some View {
        HStack(spacing: 4) {
                Button { Haptics.tap(); openProfile() } label: {
                    HStack(spacing: 4) {
                        Text(post.username).font(.subheadline.weight(.semibold)).lineLimit(1)
                            .frame(minWidth: 44, alignment: .leading)
                        VerifiedBadge(badge: UserVerificationService.shared.badge(forUsername: post.username),
                                      size: 13, username: post.username)
                        if isGhost { Image(systemName: "moon.zzz.fill").font(.caption2) }
                    }
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(post.username)")
                .layoutPriority(1)
                if let community = matchedCommunity {
                    inlineCommunityLink(community)
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                }
                Text(post.timeAgo).font(.caption).foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(1).fixedSize()
                Spacer(minLength: 0)
                factCheckBadge
                Button { Haptics.tap(); postMenu = buildPostMenu() } label: {
                    Image(systemName: "ellipsis").font(.body.weight(.medium))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .frame(width: 44, height: 44).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Post options")
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }

    /// Builds the branded 3-dots sheet for this post — same actions the
    /// old system Menu offered, in Whisper's own action sheet.
    private func buildPostMenu() -> WhisperActionMenuModel {
        var actions: [WhisperMenuAction] = []
        if moderation.canMuteAsViewer || moderation.canBanAsViewer {
            actions.append(WhisperMenuAction(icon: "shield.lefthalf.filled", title: "Moderate \(post.username)") {
                presentModerationSheet = true
            })
        }
        let saved = bookmarks.isBookmarked(postIDString)
        actions.append(WhisperMenuAction(
            icon: saved ? "bookmark.fill" : "bookmark",
            title: saved ? "Unsave" : "Save",
            subtitle: saved ? nil : "Add to your saved posts"
        ) {
            Task { await toggleBookmarkWithAutoCategorize() }
        })
        actions.append(WhisperMenuAction(icon: "checkmark.seal.fill", title: "Fact-check with Jasper") {
            presentFactCheck = true
            Task { await runFactCheck() }
        })
        actions.append(WhisperMenuAction(icon: "person.2.fill", title: "Add community context") {
            presentCommunityNotes = true
        })
        if isMyPost {
            actions.append(WhisperMenuAction(icon: "chart.bar.xaxis", title: "View activity") {
                presentInsights = true
            })
            if WhisperVerifiedPerks.isVerified(username: post.username) {
                let pinned = verifiedPerks.isPinned(postID: postIDString)
                actions.append(WhisperMenuAction(
                    icon: pinned ? "pin.slash" : "pin.fill",
                    title: pinned ? "Unpin from profile" : "Pin to profile"
                ) {
                    Task {
                        if pinned { await verifiedPerks.unpin(postID: postIDString) }
                        else { await verifiedPerks.pin(postID: postIDString) }
                    }
                })
            }
            actions.append(WhisperMenuAction(icon: "trash", title: "Delete", isDestructive: true) {
                confirmDelete = true
            })
        }
        actions.append(WhisperMenuAction(icon: "flag", title: "Report", isDestructive: true) {
            presentReport = true
        })
        return WhisperActionMenuModel(title: "@\(post.username)", actions: actions)
    }

    /// Inline community link rendered next to the username — matches the
    /// Threads-style header: `username  >  • Community Name` where the
    /// community name reads in the system tint and the dot-cluster glyph
    /// sits to its left. Tapping pushes the community detail screen.
    @ViewBuilder
    private func inlineCommunityLink(_ c: WhisperCommunity) -> some View {
        NavigationLink(value: c) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.4))
                HStack(spacing: 4) {
                    Text(c.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.75))
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var threadsMedia: some View {
        if let payload = post.decodedWorkoutPayload() {
            // Workout + photo pair up into one hero card — the photo becomes
            // the card's full-bleed header instead of rendering separately.
            WhisperWorkoutPostCard(
                payload: payload,
                username: post.username,
                accent: post.accent,
                photoURL: post.mediaURLs.first(where: { !WhisperVideo.isVideo($0) })
            )
        } else if !post.mediaURLs.isEmpty {
            threadsMediaCarousel
        } else if post.kind != .photo {
            // For workout/progress posts (or photo posts without media), keep
            // the symbol art but render it as a smaller, rounded inline card
            // so it reads like a Threads attachment rather than a full bleed.
            threadsSymbolCard
                .contentShape(.rect)
                .onTapGesture {
                    Haptics.tap()
                    openDiscussion()
                }
        }
    }

    /// Threads-style media row. Single photo fills the column. Multiple
    /// photos render as a horizontal snap scroll with a peek of the next
    /// card. A carousel-wide pinch gesture collapses the gallery into a
    /// single stacked tile (spacing -> 0, cards overlap into the center)
    /// just like Threads; pinching out opens the fullscreen viewer.
    @ViewBuilder
    private var threadsMediaCarousel: some View {
        let multiple = post.mediaURLs.count > 1
        if multiple {
            mergeableCarousel
        } else if let url = post.mediaURLs.first {
            Color(.secondarySystemBackground)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    GeometryReader { geometry in
                        mediaCard(url: url, width: geometry.size.width, height: geometry.size.height, preservesWholeImage: true)
                    }
                    .allowsHitTesting(false)
                }
                .clipShape(.rect(cornerRadius: 16))
                .contentShape(.rect)
                .accessibilityLabel("Open post media")
                .accessibilityAddTraits(.isButton)
                .onTapGesture {
                    Haptics.tap()
                    if onOpenDiscussion == nil { detailFocusReply = false; openDiscussion() }
                    else { photoViewerStartIndex = 0; presentPhotoViewer = true }
                }
                .gesture(
                    MagnifyGesture()
                        .onEnded { value in
                            if value.magnification > 1.15 {
                                Haptics.tap()
                                photoViewerStartIndex = 0
                                presentPhotoViewer = true
                            }
                        }
                )
        }
    }

    /// Live progress (0…1) for the panoramic merge — combines whatever the
    /// user is currently pinching with any previously-committed merge state.
    /// 0 = full 8pt gaps between photos, 1 = photos touching edge-to-edge.
    private var mergeProgress: CGFloat {
        // While pinching, map [1.0 → 0.78] to [0 → 1] so a small pinch is
        // enough to close the gap (matches Threads' sensitivity).
        let livePinch: CGFloat = {
            guard carouselPinchActive else { return carouselMerged ? 1 : 0 }
            let clamped = min(max(carouselPinch, 0.5), 1.0)
            let p = (1.0 - clamped) / 0.22
            return min(max(p, 0), 1)
        }()
        if carouselMerged && !carouselPinchActive { return 1 }
        return livePinch
    }

    /// Single-photo height — a little shorter than before so a photo
    /// post doesn't dominate the entire feed viewport. On iPad we let the
    /// height grow a touch since the column is wider.
    private var singlePhotoHeight: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 320 : 260
    }

    /// Multi-photo carousel height — deliberately shorter than the
    /// single-photo case so when the user pinches the gallery into the
    /// panoramic strip, two adjacent photos fit on screen side by side.
    private var carouselHeight: CGFloat { onOpenDiscussion != nil ? 320 : 274 }

    private var mergeableCarousel: some View {
        GeometryReader { geo in
            // Card width is sized so adjacent photos can sit next to each
            // other on screen once the user pinches them into the panoramic
            // strip. Capped on iPad so a 2-photo merge doesn't span the
            // whole column.
            let cardWidth: CGFloat = min(geo.size.width * 0.78, carouselHeight * 0.8)
            mergeableCarouselScroll(cardWidth: cardWidth, progress: mergeProgress)
        }
        .frame(height: carouselHeight)
    }

    @ViewBuilder
    private func mergeableCarouselScroll(cardWidth: CGFloat, progress: CGFloat) -> some View {
        // Gap goes from 8pt → 0 as the user pinches in. That's the entire
        // effect — no scaling, no z-stacking, no opacity. Cards stay in
        // place and the photos touch when merged. Inner corners flatten in
        // lockstep so adjacent photos read as one continuous panoramic strip
        // (no rounded notches at the join lines).
        let spacing: CGFloat = 8 * (1 - progress)
        let count = post.mediaURLs.count
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                ForEach(Array(post.mediaURLs.enumerated()), id: \.offset) { idx, url in
                    let isFirst = idx == 0
                    let isLast = idx == count - 1
                    let outerR: CGFloat = 18
                    let leadingR: CGFloat = isFirst ? outerR : outerR * (1 - progress)
                    let trailingR: CGFloat = isLast ? outerR : outerR * (1 - progress)
                    mediaCard(
                        url: url,
                        width: cardWidth,
                        height: carouselHeight,
                        leadingCornerRadius: leadingR,
                        trailingCornerRadius: trailingR
                    )
                    .id(idx)
                    .onTapGesture {
                        Haptics.tap()
                        if onOpenDiscussion == nil { detailFocusReply = false; openDiscussion() }
                        else { photoViewerStartIndex = idx; presentPhotoViewer = true }
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $focusedIndex)
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
        // ScrollView eats single-finger touches but a 2-finger pinch can run
        // alongside it. `.gesture(...)` loses the race because the scroll view
        // already claimed the touch sequence; `.simultaneousGesture` lets the
        // MagnifyGesture observe both fingers without fighting the scroll.
        .simultaneousGesture(carouselPinchGesture)
    }

    private var carouselPinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                carouselPinchActive = true
                carouselPinch = min(max(value.magnification, 0.5), 1.6)
            }
            .onEnded { value in
                let mag = value.magnification
                // Hard pinch-out still opens the fullscreen viewer.
                if mag > 1.25 {
                    Haptics.tap()
                    photoViewerStartIndex = focusedIndex ?? 0
                    presentPhotoViewer = true
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        carouselPinch = 1.0
                        carouselPinchActive = false
                    }
                    return
                }
                // Pinch-in: latch the merged (panoramic) state and stay there.
                // Pinch-out on an already-merged strip: unlatch and restore
                // the natural 8pt gap.
                let pinchedIn = mag < 0.92
                let pinchedOut = mag > 1.05
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    if pinchedIn {
                        carouselMerged = true
                        Haptics.tap()
                    } else if pinchedOut && carouselMerged {
                        carouselMerged = false
                        Haptics.tap()
                    }
                    carouselPinch = 1.0
                    carouselPinchActive = false
                }
            }
    }

    @ViewBuilder
    private func mediaCard(
        url: URL,
        width: CGFloat?,
        height: CGFloat = 260,
        leadingCornerRadius: CGFloat = 18,
        trailingCornerRadius: CGFloat = 18,
        preservesWholeImage: Bool = false
    ) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: leadingCornerRadius,
            bottomLeadingRadius: leadingCornerRadius,
            bottomTrailingRadius: trailingCornerRadius,
            topTrailingRadius: trailingCornerRadius
        )
        Color(.secondarySystemBackground)
            .frame(width: width, height: height)
            .overlay {
                if WhisperVideo.isVideo(url), isPreview {
                    WhisperWavePosterView(videoURL: url, coverURL: WhisperPostMeta.coverURL(from: post.caption))
                } else if WhisperVideo.isVideo(url) {
                    WhisperVideoView(url: url, autoplay: !presentDetail && !presentPhotoViewer)
                        .allowsHitTesting(false)
                } else {
                    WhisperSizedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: preservesWholeImage ? .fit : .fill)
                        case .empty:
                            WhisperPhotoLoader(quiet: true)
                        case .failure:
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipShape(shape)
    }

    /// Quiet Threads-style attachment row for workout/progress posts
    /// without media. The post's accent survives only as a small tinted
    /// icon disc — the card itself stays in Whisper's black & white
    /// language, and the old full-bleed gradient with fake stat badges
    /// is gone.
    @ViewBuilder
    private var threadsSymbolCard: some View {
        if post.kind == .progress || post.kind == .workout {
            HStack(spacing: 12) {
                Image(systemName: post.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(post.accent)
                    .frame(width: 44, height: 44)
                    .background(post.accent.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.kind == .progress ? "Progress check-in" : "Workout session")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("Tap to view")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
            }
        }
    }

    /// Threads-style action row — thin outlined icons with their counts
    /// rendered inline immediately to the right of each glyph, clustered
    /// to the leading edge. Mirrors the reference screenshot exactly:
    /// heart 29K · bubble 457 · repost 3.3K · paperplane 99.
    private var threadsActions: some View {
        HStack(spacing: 10) {
            Group {
                if let react = specialReact {
                    // Community special react — the liked state wears the
                    // community's own emoji instead of the red heart.
                    threadsActionButtonCustom(
                        count: gridMeta?.hideCounts == true ? 0 : localLikes,
                        action: { likeTapAction() }
                    ) {
                        if localLiked {
                            Text(react)
                                .font(.system(size: 18))
                        } else {
                            WhisperRoundedGlyph(kind: .heart, size: 22)
                                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.9))
                        }
                    }
                } else {
                    threadsActionButton(
                        icon: localLiked ? "heart.fill" : "heart",
                        count: gridMeta?.hideCounts == true ? 0 : localLikes,
                        tint: localLiked ? WhisperTheme.likeRed : WhisperTheme.ink(colorScheme).opacity(0.9)
                    ) {
                        likeTapAction()
                    }
                }
            }
            if gridMeta?.commentsOff != true {
            threadsActionButton(
                icon: "message",
                count: gridMeta?.hideCounts == true ? 0 : localComments,
                tint: WhisperTheme.ink(colorScheme).opacity(0.9)
            ) {
                Haptics.tap()
                // Open the conversation for reading first; the pinned field owns keyboard focus.
                detailFocusReply = onOpenDiscussion != nil
                openDiscussion()
            }
            }
            threadsActionButtonCustom(
                count: gridMeta?.hideCounts == true ? 0 : reposts.count(for: postIDString),
                action: {
                    Haptics.tap()
                    presentRepostMenu = true
                }
            ) {
                WhisperSpinningRepostIcon(
                    tint: reposts.isReposted(postIDString)
                        ? Color(red: 0.18, green: 0.78, blue: 0.32)
                        : WhisperTheme.ink(colorScheme).opacity(0.9),
                    trigger: repostSpinTrigger
                )
            }
            threadsActionButtonCustom(
                count: 0,
                action: {
                    Haptics.tap()
                    shareFlyTrigger &+= 1
                    presentForward = true
                }
            ) {
                WhisperFlyingPaperplane(
                    tint: WhisperTheme.ink(colorScheme).opacity(0.9),
                    trigger: shareFlyTrigger
                )
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .leading) {
            WhisperReactionBurst(emoji: reactionEmoji, trigger: reactionTrigger)
                .offset(x: reactionAnchorX, y: -10)
        }
    }

    /// Shared optimistic like toggle used by both action-bar styles —
    /// bursts the react, flips local state, then reconciles with the server.
    private func likeTapAction() {
        let wasLiked = localLiked
        if !wasLiked {
            playReaction(.like)
            WhisperFeedback.liked()
        } else {
            WhisperFeedback.unliked()
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
            localLiked.toggle()
            localLikes += localLiked ? 1 : -1
        }
        Task {
            let newLiked = await backend.toggleLike(postID: postIDString)
            if newLiked != !wasLiked {
                await MainActor.run {
                    withAnimation {
                        localLiked = wasLiked
                        localLikes += wasLiked ? 1 : -1
                    }
                }
            }
        }
    }

    /// Fires the category-aware emoji burst over the action row. Anchors
    /// the burst over the action button that triggered it so a repost
    /// pop appears over the repost icon (not over the like icon). Inside a
    /// community feed the like burst uses the community's special react.
    private func playReaction(_ action: WhisperReactionEmoji.Action) {
        reactionEmoji = (action == .like ? specialReact : nil) ?? WhisperReactionEmoji.emoji(
            forCaption: post.caption,
            kind: post.kind,
            action: action
        )
        // Approximate per-icon anchor in the HStack(spacing: 18) of
        // 32-wide icon buttons. Each step accounts for the icon width plus
        // a typical count label so the burst lines up over the matching
        // glyph instead of always firing from the leading edge.
        switch action {
        case .like:   reactionAnchorX = 4
        case .repost: reactionAnchorX = 132
        case .share:  reactionAnchorX = 196
        }
        reactionTrigger &+= 1
    }

    /// Variant that lets the caller supply a custom icon view (e.g. the
    /// animated repost / paperplane glyphs). Layout matches
    /// `threadsActionButton` exactly so the row stays visually identical.
    private func threadsActionButtonCustom<Icon: View>(
        count: Int,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                icon()
                    .frame(width: 22, height: 44)
                if count > 0 {
                    Text(Self.compactCount(count))
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .monospacedDigit()
                }
            }
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func threadsActionButton(icon: String, count: Int, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                WhisperRoundedGlyph(kind: icon.hasPrefix("heart") ? .heart : .comment, size: 22, selected: icon == "heart.fill")
                    .foregroundStyle(tint)
                    .frame(width: 22, height: 44)
                if count > 0 {
                    Text(Self.compactCount(count))
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .monospacedDigit()
                }
            }
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Compact count formatter to match Threads (29K, 3.3K, 457, 99).
    private static func compactCount(_ n: Int) -> String {
        if n >= 1_000_000 {
            let v = Double(n) / 1_000_000
            return v >= 10 ? String(format: "%.0fM", v) : String(format: "%.1fM", v)
        }
        if n >= 1_000 {
            let v = Double(n) / 1_000
            return v >= 10 ? String(format: "%.0fK", v) : String(format: "%.1fK", v)
        }
        return "\(n)"
    }

    @ViewBuilder
    private var topCommentPreview: some View {
        if hasReplyPreview {
            Button {
                Haptics.tap()
                openDiscussion()
            } label: {
                WhisperFeedReplyPreview(comment: topComment, replyCount: localComments,
                    threadIndex: topCommentThreadIndex, threadCount: selfThreadCount)
            }
            .buttonStyle(.plain)
        }
    }

    private func loadTopComment() async {
        guard post.comments > 0 || !(backend.commentsByPostID[postIDString] ?? []).isEmpty else {
            topComment = nil
            selfThreadCount = 0
            topCommentThreadIndex = nil
            return
        }
        // Reuse the shared comments cache when this post's replies were
        // already fetched (detail view, earlier mount) — scrolling back
        // over a card must not refetch its comment preview.
        let generation = AccountStorage.generation
        let rows = await backend.fetchComments(postID: postIDString, maxAge: 45)
        guard !Task.isCancelled, generation == AccountStorage.generation else { return }
        updateCommentPreview(backend.commentsByPostID[postIDString] ?? rows)
    }

    private func updateCommentPreview(_ rows: [WhisperCommentRow]) {
        // Only root-level comments qualify as previews (skip replies).
        let roots = rows.filter { $0.parent_comment_id == nil && !$0.id.hasPrefix("local-") }
            .sorted { ($0.created_at ?? "", $0.id) < ($1.created_at ?? "", $1.id) }
        // Root-level replies authored by the post owner form the
        // Threads-style self-thread chain. When the chain exists,
        // PREFER its first entry as the preview so the feed card
        // reads as 1/N → 2/N rather than dropping into a random reply.
        let authorID = post.authorUserID ?? (backend.posts + backend.myPosts).first { $0.id.lowercased() == postIDString }?.user_id
        let chain = roots.filter { row in
            if let authorID { return row.user_id.lowercased() == authorID.lowercased() && row.username.lowercased() != "ember" }
            return false
        }
        let top: WhisperCommentRow?
        let threadIndex: Int?
        if let first = chain.first {
            top = first
            threadIndex = 2 // root post is 1, first self-reply is 2
        } else {
            top = roots.max(by: { ($0.likes_count ?? 0) < ($1.likes_count ?? 0) })
                ?? roots.first
            threadIndex = nil
        }
        topComment = top
        selfThreadCount = chain.count
        topCommentThreadIndex = threadIndex
    }

    /// Counts now live inline on each action icon (Threads-style), so the
    /// separate meta line below the row is no longer needed.
    @ViewBuilder
    private var threadsMetaLine: some View { EmptyView() }
}

/// Session cache: first likers per post id so grid cards don't refetch the
/// facepile every time they re-mount while scrolling.
@MainActor private var whisperGridLikersCache: [String: [WhisperLiker]] = [:]
