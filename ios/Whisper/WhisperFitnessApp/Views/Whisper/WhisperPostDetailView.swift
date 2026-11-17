import SwiftUI

/// Threads-style "Thread" detail view. Shown when the user taps a post in
/// the feed or its comment / reply-count buttons. The original post takes
/// the top of the screen at full size, followed by the action row, a
/// "Top \u{2228} / View activity" meta row, and a threaded comments list
/// with avatar guide-lines. A compact composer bar is pinned to the
/// bottom; tapping the expand glyph (or the field itself) opens the
/// full-screen `WhisperReplyComposerSheet`.
struct WhisperPostDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var replySort: String = "Top"
    @State private var rootOrder: [String] = []

    let post: WhisperPost
    private let focusedCommentID: String?
    private let onOpenBranch: ((String?) -> Void)?
    @State private var navigationPath: NavigationPath = NavigationPath()
    @State private var shareComment: WhisperCommentRow?
    @State private var initializedTarget: Bool = false
    @State private var highlightTask: Task<Void, Never>?
    /// Optional comment ID to scroll to and pulse on appear. Set when the
    /// detail view is opened from a "tagged in a comment" activity row so
    /// the user lands directly on the comment that referenced them instead
    /// of the top of the thread.
    let highlightCommentID: String?

    @State private var backend = WhisperBackendService.shared
    @State private var bookmarks = WhisperBookmarkService.shared
    @State private var coach = WhisperCoachService.shared
    @State private var ghostService = WhisperGhostService.shared
    @State private var pins = WhisperPinService.shared
    @State private var localPost: WhisperPost
    @State private var presentReply: Bool = false
    @State private var replyDrafts: [String: (text: String, attachments: WhisperComposerAttachments)] = [:]
    @State private var confirmLeave: Bool = false
    @State private var back: WhisperBackAction = WhisperBackAction()
    @State private var commentsLoadFailed: Bool = false
    @State private var commentToReport: WhisperCommentRow?
    @State private var presentLikers: Bool = false
    @State private var presentForward: Bool = false
    @State private var presentPhotoViewer: Bool = false
    @State private var photoViewerStartIndex: Int = 0
    @State private var loading: Bool = false
    @State private var expandedReplies: Set<String> = []
    @State private var replyTarget: WhisperCommentRow?
    /// Branded ellipsis sheet for a comment — replaces the old system
    /// confirmationDialog so comment actions match Whisper's action menu
    /// on every platform.
    @State private var commentMenu: WhisperActionMenuModel?
    @State private var presentEmberProfile: Bool = false
    @State private var confirmDeleteCommentID: String?
    @State private var presentInsights: Bool = false
    @State private var presentReport: Bool = false
    @State private var presentRepostMenu: Bool = false
    @State private var presentQuoteComposer: Bool = false
    @State private var reposts = WhisperRepostService.shared
    @State private var subscriptions = WhisperPostSubscriptionService.shared
    /// Branded action sheet for the post's ellipsis menu — replaces both
    /// the inline `Menu` (drops taps inside sheets) and the system
    /// confirmationDialog (off-brand bubble).
    @State private var postMenu: WhisperActionMenuModel?
    /// Floating category emoji burst (like / repost / share). Bumping the
    /// trigger replays the animation in `WhisperReactionBurst`.
    @State private var reactionEmoji: String = ""
    @State private var reactionTrigger: Int = 0
    @State private var repostSpinTrigger: Int = 0
    @State private var shareFlyTrigger: Int = 0
    @State private var communityNotes = WhisperCommunityNotesService.shared
    @State private var presentCommunityNotes: Bool = false

    // Bottom-bar inline composer pill state. Typing here posts directly
    // without opening the full-screen composer; the photo / sticker / GIF
    // / expand icons hand off to the full composer with the chosen picker
    // auto-presented.
    @State private var pillDraft: String = ""
    @State private var pillSending: Bool = false
    @FocusState private var pillFocused: Bool
    @State private var pillAttachments: WhisperComposerAttachments = WhisperComposerAttachments()
    @State private var replyInitialPicker: WhisperReplyComposerPicker? = nil

    init(post: WhisperPost, highlightCommentID: String? = nil, autoFocusReply: Bool = false,
         focusedCommentID: String? = nil, onOpenBranch: ((String?) -> Void)? = nil) {
        self.focusedCommentID = focusedCommentID
        self.onOpenBranch = onOpenBranch
        self.post = post
        self.highlightCommentID = highlightCommentID
        self.autoFocusReply = autoFocusReply
        self._localPost = State(initialValue: post)
        self._pendingHighlight = State(initialValue: highlightCommentID)
    }

    /// When true (comment icon tap), the bottom reply pill focuses as soon
    /// as the thread opens so the user can start typing immediately.
    private let autoFocusReply: Bool

    /// Active comment ID currently pulsing. Cleared after the highlight
    /// animation finishes so subsequent scroll/refresh doesn't keep the
    /// background tinted.
    @State private var pendingHighlight: String?
    @State private var pulseHighlight: Bool = false

    private var postIDString: String { localPost.id.uuidString.lowercased() }
    private var isGhost: Bool { ghostService.isGhost(postIDString) }

    private var comments: [WhisperCommentRow] {
        backend.commentsByPostID[postIDString] ?? []
    }
    /// Visible root comments excluding any the post-author chose to hide.
    /// Self-replies (root-level comments authored by the post owner) are
    /// the chain that Threads numbers "1/N · 2/N…".
    private var rootComments: [WhisperCommentRow] {
        comments.filter { $0.parent_comment_id == focusedCommentID && !pins.isHidden(commentID: $0.id) }
    }
    /// All self-replies on the original post (author of the post replying
    /// to themselves) ordered oldest-first. Used to compute the small
    /// "2/N" thread numbering badge shown on each one.
    private var selfThreadChain: [WhisperCommentRow] {
        rootComments
            .filter { row in
                guard let authorID = localPost.authorUserID else { return false }
                return row.user_id.lowercased() == authorID.lowercased()
            }
            .sorted { ($0.created_at ?? "", $0.id) < ($1.created_at ?? "", $1.id) }
    }
    private var focusedComment: WhisperCommentRow? {
        guard let id = focusedCommentID, !pins.isHidden(commentID: id),
              !WhisperThreadReplyTree.ancestors(of: id, in: comments).contains(where: { pins.isHidden(commentID: $0.id) }) else { return nil }
        return comments.first { $0.id == id }
    }
    private var pinnedID: String? { focusedCommentID == nil ? pins.pinnedCommentID(for: postIDString) : nil }
    private var orderedRootComments: [WhisperCommentRow] {
        let positions = Dictionary(uniqueKeysWithValues: rootOrder.enumerated().map { ($1, $0) })
        var list = rootComments.sorted {
            let lhs = positions[$0.id] ?? Int.max
            let rhs = positions[$1.id] ?? Int.max
            return lhs == rhs ? $0.id < $1.id : lhs < rhs
        }
        if let pid = pinnedID, let idx = list.firstIndex(where: { $0.id == pid }) {
            let pinned = list.remove(at: idx)
            list.insert(pinned, at: 0)
        }
        return list
    }
    private func updateRootOrder(force: Bool = false) {
        let sorted = rootComments.sorted { lhs, rhs in
            if replySort == "Top", (lhs.likes_count ?? 0) != (rhs.likes_count ?? 0) {
                return (lhs.likes_count ?? 0) > (rhs.likes_count ?? 0)
            }
            let left = (lhs.created_at ?? "", lhs.id)
            let right = (rhs.created_at ?? "", rhs.id)
            return replySort == "Newest" ? left > right : left < right
        }.map(\.id)
        let admitted = Set(sorted)
        if force || rootOrder.isEmpty { rootOrder = sorted }
        else {
            let existing = Set(rootOrder)
            rootOrder = rootOrder.filter { admitted.contains($0) } + sorted.filter { !existing.contains($0) }
        }
    }

    private func threadIndex(for comment: WhisperCommentRow) -> (Int, Int)? {
        guard let idx = selfThreadChain.firstIndex(where: { $0.id == comment.id }) else { return nil }
        return (idx + 2, selfThreadChain.count + 1) // original is 1/N
    }
    private func replies(for parentID: String) -> [WhisperCommentRow] {
        comments.filter { $0.parent_comment_id == parentID && !pins.isHidden(commentID: $0.id) }
            .sorted { ($0.created_at ?? "", $0.id) < ($1.created_at ?? "", $1.id) }
    }
    private var isMyPost: Bool {
        let me = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? ""
        return !me.isEmpty && me.lowercased() == localPost.username.lowercased()
    }

    /// True when the local user authored the given comment — enables the
    /// destructive Delete action in the comment’s ellipsis menu.
    private func isMyComment(_ c: WhisperCommentRow) -> Bool {
        let me = (LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "").lowercased()
        let uid = AccountStorage.currentUserID.lowercased()
        if !uid.isEmpty, c.user_id.lowercased() == uid { return true }
        if !me.isEmpty, c.username.lowercased() == me { return true }
        return false
    }

    private var postMetadata: WhisperPostMeta? { WhisperPostMeta.parse(from: localPost.caption) }
    private var commentsOff: Bool { postMetadata?.commentsOff == true }

    var body: some View {
        if focusedCommentID == nil, onOpenBranch == nil, WhisperPostPresentationPolicy.opensWavePlayer(isReel: post.isReel, commentID: highlightCommentID, focusReply: autoFocusReply) {
            WhisperReelsPlayerView(reels: [post], start: post)
        } else {
            discussionBody
        }
    }

    @ViewBuilder
    private var discussionBody: some View {
        if onOpenBranch != nil {
            discussionPage
        } else {
            NavigationStack(path: $navigationPath) {
                discussionPage
                    .navigationDestination(for: WhisperReplyDestination.self) { destination in
                        WhisperPostDetailView(post: localPost, focusedCommentID: destination.commentID,
                                              onOpenBranch: { navigationPath.append(WhisperReplyDestination(commentID: $0)) })
                    }
                    .navigationDestination(for: WhisperCommunity.self) { community in
                        WhisperCommunityDetailView(community: community)
                    }
            }
        }
    }

    private var discussionPage: some View {
            GeometryReader { viewport in
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                if focusedCommentID != nil {
                                    branchHeader
                                } else {
                                WhisperPostCard(post: localPost, onOpenDiscussion: { focus in
                                    if focus && !commentsOff { selectReplyTarget(nil); pillFocused = true }
                                    else { withAnimation(.whisperSnappy) { proxy.scrollTo("discussion", anchor: .top) } }
                                }, onDeleted: { dismiss() })
                                }
                                metaRow.id("discussion")
                                commentsList
                                Color.clear.frame(height: 8)
                            }
                            .frame(width: viewport.size.width)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: comments.map(\.id), initial: true) { _, _ in
                            updateRootOrder()
                            tryScrollToHighlight(proxy: proxy)
                        }
                        .task(id: comments.count) {
                            tryScrollToHighlight(proxy: proxy)
                        }
                    }
                    if !commentsOff && (focusedCommentID == nil || (focusedComment != nil && initializedTarget)) { composerBar }
                }
                .frame(width: viewport.size.width, height: viewport.size.height)
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationBarBackButtonHidden(true)
            .interactiveDismissDisabled(hasReplyDrafts || pillSending || presentReply)
            .whisperEdgeBack(isEnabled: !pillSending, requiresDecision: hasReplyDrafts, controller: back) { requestBack() }
            .confirmationDialog("Discard unsent replies?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Discard replies", role: .destructive) { back.perform { dismiss() } }
                Button("Keep editing", role: .cancel) {}
            } message: {
                Text("Your unsent text and attachments will be lost if you leave this thread.")
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(WhisperTheme.surface(colorScheme), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(WhisperTheme.ink(colorScheme))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: requestBack) {
                        Image(systemName: "chevron.left").font(.system(size: 19, weight: .medium))
                            .frame(width: 44, height: 44).contentShape(.rect)
                    }
                    .buttonStyle(.plain).disabled(pillSending).accessibilityLabel("Back")
                }.whisperFlatToolbar()
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(focusedCommentID != nil ? "Reply" : (localPost.kind == .grid ? "Post" : "Thread"))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        if focusedCommentID == nil, postMetadata?.hideCounts != true && localPost.comments > 0 {
                            Text("\(localPost.comments.formatted()) \(localPost.comments == 1 ? "reply" : "replies")")
                                .font(.caption2)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 2) {
                        Button {
                            Haptics.tap()
                            let nowOn = subscriptions.toggle(postIDString)
                            if nowOn { Haptics.success() }
                        } label: {
                            Image(systemName: subscriptions.isSubscribed(postIDString) ? "bell.fill" : "bell")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(
                                    subscriptions.isSubscribed(postIDString)
                                        ? WhisperTheme.accent
                                        : WhisperTheme.ink(colorScheme)
                                )
                                .frame(width: 44, height: 44).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(subscriptions.isSubscribed(postIDString) ? "Mute thread notifications" : "Get thread notifications")
                        Button {
                            Haptics.tap()
                            if let focusedComment { commentMenu = buildCommentMenu(focusedComment) }
                            else { postMenu = buildPostMenu() }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                                .frame(width: 44, height: 44).contentShape(.rect)
                        }
                        .buttonStyle(.plain).accessibilityLabel("Thread options")
                    }
                }.whisperFlatToolbar()
            }
            .whisperActionMenu($postMenu)
            .whisperActionMenu($commentMenu)
            .task { await loadReplies() }
            .task {
                guard !Task.isCancelled else { return }
                _ = await reposts.fetchCount(for: postIDString)
            }
            .task {
                guard !Task.isCancelled else { return }
                await communityNotes.refresh(postID: postIDString)
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
                pillFocused = false
                dismiss()
            }
            .task(id: autoFocusReply) {
                let generation = AccountStorage.generation
                guard autoFocusReply, !commentsOff else { return }
                do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                pillFocused = true
            }
            .fullScreenCover(isPresented: $presentReply, onDismiss: {
                replyInitialPicker = nil
            }) {
                WhisperReplyComposerSheet(
                    post: localPost,
                    replyTarget: replyTarget,
                    initialDraft: pillDraft,
                    initialPicker: replyInitialPicker,
                    onPosted: {
                        finishReply()
                        Task { await loadReplies() }
                    },
                    onDraftChanged: { pillDraft = $0 },
                    sharedAttachments: pillAttachments
                )
            }
            .fullScreenCover(isPresented: $presentPhotoViewer) {
                WhisperPostPhotoViewer(urls: localPost.mediaURLs, startIndex: photoViewerStartIndex)
            }
            .fullScreenCover(isPresented: $presentLikers) {
                WhisperPostActivityView(postID: postIDString)
            }
            .sheet(isPresented: $presentForward, onDismiss: { shareComment = nil }) {
                WhisperPostShareSheet(post: localPost, comment: shareComment)
            }
            .fullScreenCover(isPresented: $presentInsights) {
                WhisperPostActivityView(postID: postIDString)
            }
            .sheet(isPresented: $presentCommunityNotes) {
                WhisperCommunityNotesSheet(postID: postIDString)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .whisperSheetBorder()
            }
            .sheet(isPresented: $presentReport, onDismiss: { commentToReport = nil }) {
                WhisperReportSheet(
                    kind: commentToReport == nil ? .post : .comment,
                    targetID: commentToReport?.id ?? postIDString,
                    targetUserID: commentToReport?.user_id,
                    targetUsername: commentToReport?.username ?? localPost.username
                )
            }
            .fullScreenCover(isPresented: $presentQuoteComposer) {
                WhisperComposerView(initialQuotedPost: localPost)
            }
            .sheet(isPresented: $presentRepostMenu) {
                WhisperRepostOptionsSheet(
                    isReposted: reposts.isReposted(postIDString),
                    hasMedia: !localPost.mediaURLs.isEmpty,
                    onQuote: {
                        playReaction(.repost)
                        repostSpinTrigger &+= 1
                        presentQuoteComposer = true
                    },
                    onMarkup: {
                        playReaction(.repost)
                        repostSpinTrigger &+= 1
                        presentQuoteComposer = true
                    },
                    onUseMedia: {
                        playReaction(.repost)
                        repostSpinTrigger &+= 1
                        presentQuoteComposer = true
                    },
                    onRepostOnly: {
                        Task {
                            let wasReposted = reposts.isReposted(postIDString)
                            _ = await reposts.toggle(postID: postIDString)
                            if !wasReposted {
                                await MainActor.run {
                                    playReaction(.repost)
                                    repostSpinTrigger &+= 1
                                }
                            }
                        }
                    }
                )
            }

            .background(deleteCommentAlert)
            .sheet(isPresented: $presentEmberProfile) {
                NavigationStack {
                    WhisperEmberProfileView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Close") { presentEmberProfile = false }
                                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                            }
                        }
                }
            }
            .onDisappear { highlightTask?.cancel(); highlightTask = nil; pillFocused = false }
    }

    private func openBranch(_ commentID: String?) {
        guard !pillSending, !presentReply, commentID != focusedCommentID else { return }
        if let commentID, commentID.hasPrefix("local-") { return }
        pillFocused = false
        Haptics.tap()
        if let onOpenBranch { onOpenBranch(commentID) }
        else { navigationPath.append(WhisperReplyDestination(commentID: commentID)) }
    }

    @ViewBuilder
    private var branchHeader: some View {
        WhisperThreadParentContext(post: localPost) { compose in
            if compose && !commentsOff { selectReplyTarget(nil); pillFocused = true }
            else { openBranch(nil) }
        }
        if let focusedComment {
            ForEach(WhisperThreadReplyTree.ancestors(of: focusedComment.id, in: comments).filter { !pins.isHidden(commentID: $0.id) }) { ancestor in
                commentRow(ancestor, isReply: false, hasReplies: true)
            }
            commentRow(focusedComment, isReply: false, hasReplies: false, isFocused: true)
                .padding(.bottom, 8)
        } else if !loading {
            VStack(spacing: 4) {
                Text("This reply isn't available").font(.subheadline.weight(.semibold))
                Text("It may be hidden, removed, or not loaded yet.").font(.footnote).foregroundStyle(.secondary)
                Button("Try again") { Task { await loadReplies() } }.frame(minHeight: 44)
            }.frame(maxWidth: .infinity).padding(.vertical, 16)
        }
        Divider().overlay(WhisperTheme.hairline(colorScheme))
    }

    /// Confirmation alert for deleting an authored comment. Driven by
    /// `confirmDeleteCommentID` so the destructive action is never one tap
    /// away.
    @ViewBuilder
    private var deleteCommentAlert: some View {
        EmptyView()
            .alert(
                "Delete this comment?",
                isPresented: Binding(
                    get: { confirmDeleteCommentID != nil },
                    set: { if !$0 { confirmDeleteCommentID = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let id = confirmDeleteCommentID {
                        Task {
                            let ok = await backend.deleteComment(commentID: id, postID: postIDString)
                            if ok { Haptics.success() } else { Haptics.warning() }
                        }
                    }
                    confirmDeleteCommentID = nil
                }
                Button("Cancel", role: .cancel) { confirmDeleteCommentID = nil }
            } message: {
                Text("This will permanently remove your reply. This can't be undone.")
            }
    }

    // MARK: - Original post block

    private var originalPostBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button { openAuthorProfile() } label: {
                    WhisperAvatar(username: localPost.username, size: 38)
                }
                .buttonStyle(.plain)
                HStack(spacing: 4) {
                    Button { openAuthorProfile() } label: {
                        Text(localPost.username)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                    .buttonStyle(.plain)
                    VerifiedBadge(
                        badge: UserVerificationService.shared.badge(forUsername: localPost.username),
                        size: 13,
                        username: localPost.username
                    )
                    if !selfThreadChain.isEmpty {
                        // Original post is 1/N. N = chain count + 1.
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.4))
                        WhisperThreadPositionPill(index: 1, total: selfThreadChain.count + 1)
                    }
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.45))
                    Text(localPost.timeAgo)
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.55))
                }
                Spacer(minLength: 0)
                Button {
                    Haptics.tap()
                    presentReply = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            // If this post carries a workout embed, render the rich
            // workout card (with expand → save-to-library) and only show
            // the user-typed caption text underneath, never the raw JSON.
            if let workoutPayload = localPost.decodedWorkoutPayload() {
                WhisperPostCaptionView(text: localPost.displayCaption, font: .body)
                WhisperWorkoutPostCard(
                    payload: workoutPayload,
                    username: localPost.username,
                    accent: localPost.accent
                )
            } else if !localPost.displayCaption.isEmpty {
                WhisperPostCaptionView(text: localPost.displayCaption, font: .body)
            }

            if let top = communityNotes.topNote(forPostID: postIDString) {
                WhisperCommunityNoteInlineCard(
                    note: top,
                    totalNotes: communityNotes.notes(forPostID: postIDString).count
                ) {
                    Haptics.tap()
                    presentCommunityNotes = true
                }
            }

            if !localPost.mediaURLs.isEmpty {
                mediaCarousel
            }

            actionRow
                .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var mediaCarousel: some View {
        if localPost.mediaURLs.count == 1, let url = localPost.mediaURLs.first {
            mediaCard(url: url)
                .frame(height: 360)
                .onTapGesture {
                    Haptics.tap()
                    photoViewerStartIndex = 0
                    presentPhotoViewer = true
                }
        } else {
            GeometryReader { geo in
                let cardWidth: CGFloat = max(240, geo.size.width * 0.85)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(localPost.mediaURLs.enumerated()), id: \.offset) { idx, url in
                            mediaCard(url: url)
                                .frame(width: cardWidth, height: 360)
                                .onTapGesture {
                                    Haptics.tap()
                                    photoViewerStartIndex = idx
                                    presentPhotoViewer = true
                                }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollClipDisabled()
            }
            .frame(height: 360)
        }
    }

    @ViewBuilder
    private func mediaCard(url: URL) -> some View {
        Color(.secondarySystemBackground)
            .overlay {
                if WhisperVideo.isVideo(url) {
                    WhisperVideoView(url: url, showsMuteButton: false).allowsHitTesting(false)
                } else {
                    WhisperCachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        case .empty:
                            WhisperPhotoLoader()
                        case .failure:
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        @unknown default: EmptyView()
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipShape(.rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5)
            }
    }

    // MARK: - Action row (Threads-style: outlined icons spaced across the row)

    /// Threads-style action row — outlined icons with inline counts,
    /// clustered to the leading edge. Matches the feed card exactly so
    /// the visual language stays consistent when a user taps in.
    private var actionRow: some View {
        HStack(spacing: 18) {
            actionButton(
                icon: localPost.liked ? "heart.fill" : "heart",
                count: localPost.likes,
                tint: localPost.liked ? WhisperTheme.likeRed : WhisperTheme.ink(colorScheme).opacity(0.9)
            ) {
                Haptics.tap()
                let wasLiked = localPost.liked
                if !wasLiked { playReaction(.like) }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                    localPost.liked.toggle()
                    localPost.likes += localPost.liked ? 1 : -1
                }
                Task {
                    let newLiked = await backend.toggleLike(postID: postIDString)
                    if newLiked != !wasLiked {
                        await MainActor.run {
                            withAnimation {
                                localPost.liked = wasLiked
                                localPost.likes += wasLiked ? 1 : -1
                            }
                        }
                    }
                }
            }
            actionButton(
                icon: "message",
                count: localPost.comments,
                tint: WhisperTheme.ink(colorScheme).opacity(0.9)
            ) {
                Haptics.tap()
                selectReplyTarget(nil)
                pillFocused = true
            }
            actionButtonCustom(
                count: reposts.count(for: postIDString),
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
            actionButtonCustom(
                count: 0,
                action: {
                    Haptics.tap()
                    shareFlyTrigger &+= 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        presentForward = true
                    }
                }
            ) {
                WhisperFlyingPaperplane(
                    tint: WhisperTheme.ink(colorScheme).opacity(0.9),
                    trigger: shareFlyTrigger
                )
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        .overlay(alignment: .leading) {
            WhisperReactionBurst(emoji: reactionEmoji, trigger: reactionTrigger)
                .offset(x: 6, y: -8)
        }
    }

    private func actionButtonCustom<Icon: View>(
        count: Int,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                icon()
                    .frame(width: 32, height: 32)
                if count > 0 {
                    Text(Self.compactCount(count))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.7))
                        .monospacedDigit()
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func actionButton(icon: String, count: Int, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                if count > 0 {
                    Text(Self.compactCount(count))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.7))
                        .monospacedDigit()
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Routes a tap on the post's author to the same destination the
    /// `@mention` tap path uses — the user profile sheet for normal users,
    /// or the Jasper curated profile for Jasper.
    private func openAuthorProfile() {
        Haptics.tap()
        let handle = localPost.username
        if handle.lowercased() == "ember" {
            presentEmberProfile = true
            return
        }
        NotificationCenter.default.post(
            name: .whisperOpenUserByUsername,
            object: nil,
            userInfo: ["username": handle]
        )
    }

    /// Fires the category-aware emoji burst over the action row.
    private func playReaction(_ action: WhisperReactionEmoji.Action) {
        reactionEmoji = WhisperReactionEmoji.emoji(
            forCaption: localPost.caption,
            kind: localPost.kind,
            action: action
        )
        reactionTrigger &+= 1
    }

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

    // MARK: - Meta row (Top / View activity)

    private var metaRow: some View {
        HStack {
            Menu {
                ForEach(["Top", "Newest", "Oldest"], id: \.self) { sort in
                    Button {
                        replySort = sort
                        updateRootOrder(force: true)
                    } label: {
                        if replySort == sort { Label(sort, systemImage: "checkmark") }
                        else { Text(sort) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(replySort)
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.85))
                .frame(minWidth: 44, minHeight: 44)
            }
            Spacer()
            if focusedCommentID == nil {
            Button {
                Haptics.tap()
                if isMyPost {
                    presentInsights = true
                } else {
                    presentLikers = true
                }
            } label: {
                HStack(spacing: 4) {
                    Text("View activity")
                        .font(.subheadline)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.55))
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: - Comments list

    @ViewBuilder
    private var commentsList: some View {
        if loading && comments.isEmpty {
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 64)
                .accessibilityLabel("Loading replies")
        } else if commentsLoadFailed && comments.isEmpty {
            VStack(spacing: 4) {
                Text("Couldn't load replies").font(.subheadline).foregroundStyle(.secondary)
                Button("Try again") { Task { await loadReplies() } }.frame(minHeight: 44)
            }.frame(maxWidth: .infinity).padding(.vertical, 16)
        } else if focusedCommentID != nil && focusedComment == nil {
            EmptyView()
        } else if rootComments.isEmpty {
            VStack(spacing: 6) {
                Text(commentsOff ? "Comments are off" : "No replies yet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text(commentsOff ? "The author has turned off commenting." : "Start the conversation.")
                    .font(.footnote)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(orderedRootComments) { c in
                    commentBlock(c)
                        .padding(.bottom, 12)
                }
                WhisperCommentAdView(threadID: postIDString,
                    isActive: !presentReply && !presentLikers && !presentForward
                        && !presentPhotoViewer && !presentEmberProfile && !presentInsights && !presentReport
                        && !presentRepostMenu && !presentQuoteComposer && !presentCommunityNotes
                        && commentMenu == nil && postMenu == nil && confirmDeleteCommentID == nil)
            }
        }
    }

    @ViewBuilder
    private func commentBlock(_ c: WhisperCommentRow) -> some View {
        let kids = replies(for: c.id)
        let isPinned = pins.isPinned(commentID: c.id, postID: postIDString)
        VStack(alignment: .leading, spacing: 0) {
            if isPinned {
                HStack(spacing: 6) {
                    Image(systemName: "pin.fill")
                        .font(.caption2.weight(.bold))
                    Text("Pinned")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.leading, 62)
                .padding(.top, 10)
            }
            commentRow(c, isReply: false, hasReplies: !kids.isEmpty)
            if !kids.isEmpty {
                let isOpen = expandedReplies.contains(c.id)
                let shown = isOpen ? kids : Array(kids.prefix(2))
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(shown) { child in
                        VStack(alignment: .leading, spacing: 0) {
                            commentRow(child, isReply: true, hasReplies: false)
                            if !replies(for: child.id).isEmpty {
                                Button { openBranch(child.id) } label: {
                                    Label("View replies", systemImage: "arrow.turn.down.right")
                                        .font(.subheadline).frame(minHeight: 44)
                                }
                                .buttonStyle(.plain).foregroundStyle(WhisperTheme.muted(colorScheme))
                                .padding(.leading, 64)
                            }
                        }
                        .background {
                            WhisperThreadBranchConnector(continues: child.id != shown.last?.id || kids.count > 2)
                                .stroke(WhisperTheme.hairline(colorScheme), style: StrokeStyle(lineWidth: 1.25, lineCap: .round))
                                .padding(.horizontal, 12).allowsHitTesting(false)
                        }
                    }
                    if kids.count > 2 {
                        Button {
                            Haptics.tap()
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                if isOpen { expandedReplies.remove(c.id) }
                                else { expandedReplies.insert(c.id) }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                HStack(spacing: -6) {
                                    ForEach(Array(kids.dropFirst(2).prefix(2))) { child in
                                        WhisperAvatar(username: child.username, size: 16, ring: false)
                                            .overlay { Circle().stroke(WhisperTheme.surface(colorScheme), lineWidth: 1.5) }
                                    }
                                    Image(systemName: isOpen ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                        .font(.system(size: 15))
                                        .background(WhisperTheme.surface(colorScheme), in: .circle)
                                }
                                Text(isOpen ? "Hide replies" : "Show \(kids.count - 2) more \(kids.count == 3 ? "reply" : "replies")")
                                    .font(.subheadline)
                            }
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .frame(minHeight: 44).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue("\(max(kids.count - 2, 0)) more replies")
                        .padding(.leading, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            WhisperThreadBranchConnector(continues: false)
                                .stroke(WhisperTheme.hairline(colorScheme), style: StrokeStyle(lineWidth: 1.25, lineCap: .round))
                                .padding(.horizontal, 12).allowsHitTesting(false)
                        }
                    }
                }
                .padding(.leading, 24)
            }
        }
    }

    private func commentRow(_ c: WhisperCommentRow, isReply: Bool, hasReplies: Bool, isFocused: Bool = false) -> some View {
        WhisperThreadCommentRow(comment: c, isChild: isReply,
            isLiked: backend.myLikedCommentIDs.contains(c.id), replyCount: replies(for: c.id).count,
            commentsOff: commentsOff || c.id.hasPrefix("local-"), hideCounts: postMetadata?.hideCounts == true,
            threadPosition: isReply || focusedCommentID != nil ? nil : threadIndex(for: c),
            replyingTo: nil, isFocused: isFocused,
            isPostAuthor: localPost.authorUserID.map { $0.lowercased() == c.user_id.lowercased() } ?? false,
            onProfile: {
                Haptics.tap()
                NotificationCenter.default.post(name: .whisperOpenUserByUsername, object: nil, userInfo: ["username": c.username])
            },
            onAvatar: {
                Haptics.tap()
                if c.username.lowercased() == "ember" { presentEmberProfile = true }
                else if let story = WhisperStoryService.shared.storiesByUser().first(where: { $0.username.lowercased() == c.username.lowercased() })?.all.first {
                    NotificationCenter.default.post(name: .whisperOpenStory, object: nil, userInfo: ["storyID": story.id])
                } else {
                    NotificationCenter.default.post(name: .whisperOpenUserByUsername, object: nil, userInfo: ["username": c.username])
                }
            },
            onLike: {
                Haptics.tap()
                Task { _ = await backend.toggleCommentLike(commentID: c.id, postID: postIDString) }
            },
            onReply: {
                guard !commentsOff, !pillSending, !c.id.hasPrefix("local-") else { return }
                Haptics.tap()
                selectReplyTarget(c)
                pillFocused = true
            },
            onOptions: { Haptics.tap(); commentMenu = buildCommentMenu(c) },
            onOpen: { openBranch(c.id) },
            onShare: UUID(uuidString: c.id) == nil ? nil : {
                shareComment = c; presentForward = true
            })
        .padding(.bottom, hasReplies ? 6 : 0)
        .background(alignment: .leading) {
            if hasReplies {
                WhisperThreadConnector(startY: 44)
                    .stroke(WhisperTheme.hairline(colorScheme), style: StrokeStyle(lineWidth: 1.25, lineCap: .round))
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 12)
        .background((pendingHighlight == c.id || (pulseHighlight && highlightCommentID == c.id))
            ? WhisperTheme.accent.opacity(pulseHighlight ? 0.18 : 0) : .clear)
        .id(c.id)
    }

    /// Scrolls to the highlighted comment (if any) once the comments list
    /// has hydrated, pulses its background, then clears the pending flag
    /// so the row settles back to normal. Safe to call multiple times —
    /// `pendingHighlight` is cleared after the first successful scroll.
    private func tryScrollToHighlight(proxy: ScrollViewProxy) {
        guard highlightTask == nil, let target = pendingHighlight,
              let row = comments.first(where: { $0.id == target }), !pins.isHidden(commentID: target) else { return }
        let ancestors = WhisperThreadReplyTree.ancestors(of: target, in: comments)
        guard !ancestors.contains(where: { pins.isHidden(commentID: $0.id) }) else { pendingHighlight = nil; return }
        if ancestors.count > 1 {
            pendingHighlight = nil
            openBranch(target)
            return
        }
        if let parent = row.parent_comment_id { expandedReplies.insert(parent) }
        let generation = AccountStorage.generation
        highlightTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                proxy.scrollTo(target, anchor: .center)
                pulseHighlight = true
            }
            do { try await Task.sleep(for: .milliseconds(1600)) } catch { return }
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { pulseHighlight = false }
            pendingHighlight = nil
            highlightTask = nil
        }
    }

    /// Builds the branded action sheet for the post's ellipsis menu —
    /// same actions the old system confirmationDialog offered.
    private func buildPostMenu() -> WhisperActionMenuModel {
        var actions: [WhisperMenuAction] = []
        let saved = bookmarks.isBookmarked(postIDString)
        actions.append(WhisperMenuAction(
            icon: saved ? "bookmark.fill" : "bookmark",
            title: saved ? "Unsave" : "Save",
            subtitle: saved ? nil : "Add to your saved posts"
        ) {
            Task { await bookmarks.toggle(postID: postIDString) }
        })
        actions.append(WhisperMenuAction(icon: "paperplane", title: "Send via DM") {
            presentForward = true
        })
        let subscribed = subscriptions.isSubscribed(postIDString)
        actions.append(WhisperMenuAction(
            icon: subscribed ? "bell.slash" : "bell",
            title: subscribed ? "Mute notifications" : "Get notified",
            subtitle: subscribed ? nil : "Alerts for new replies"
        ) {
            _ = subscriptions.toggle(postIDString)
        })
        actions.append(WhisperMenuAction(icon: "person.2.fill", title: "Add community context") {
            presentCommunityNotes = true
        })
        if isMyPost {
            actions.append(WhisperMenuAction(icon: "chart.bar.xaxis", title: "View activity") {
                presentInsights = true
            })
        }
        actions.append(WhisperMenuAction(icon: "flag", title: "Report", isDestructive: true) {
            presentReport = true
        })
        return WhisperActionMenuModel(title: "@\(localPost.username)", actions: actions)
    }

    /// Per-comment ellipsis button — opens Whisper's branded action sheet.
    @ViewBuilder
    private func commentMenuButton(_ c: WhisperCommentRow) -> some View {
        Button {
            Haptics.tap()
            commentMenu = buildCommentMenu(c)
        } label: {
            Image(systemName: "ellipsis")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .frame(width: 36, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Builds the branded action sheet for a comment row.
    private func buildCommentMenu(_ c: WhisperCommentRow) -> WhisperActionMenuModel {
        var actions: [WhisperMenuAction] = []
        if UUID(uuidString: c.id) != nil {
            if c.id != focusedCommentID {
                actions.append(WhisperMenuAction(icon: "arrow.up.left.and.arrow.down.right", title: "Open reply") { openBranch(c.id) })
            }
            actions.append(WhisperMenuAction(icon: "paperplane", title: "Share reply") {
                shareComment = c; presentForward = true
            })
        }
        if isMyPost {
            let pinned = pins.isPinned(commentID: c.id, postID: postIDString)
            if c.parent_comment_id == nil {
                actions.append(WhisperMenuAction(icon: pinned ? "pin.slash" : "pin.fill", title: pinned ? "Unpin" : "Pin to top") {
                    pins.togglePin(commentID: c.id, postID: postIDString)
                })
            }
            actions.append(WhisperMenuAction(icon: "eye.slash", title: "Hide") {
                pins.hide(commentID: c.id)
            })
        }
        actions.append(WhisperMenuAction(icon: "doc.on.doc", title: "Copy text") {
            UIPasteboard.general.string = WhisperReplySharePreview.excerpt(c.body)
            Haptics.success()
        })
        if isMyComment(c) {
            actions.append(WhisperMenuAction(icon: "trash", title: "Delete", isDestructive: true) {
                confirmDeleteCommentID = c.id
            })
        }
        actions.append(WhisperMenuAction(icon: "flag", title: "Report", isDestructive: true) {
            commentToReport = c
            presentReport = true
        })
        return WhisperActionMenuModel(title: "@\(c.username)", subtitle: nil, actions: actions)
    }

    private func loadReplies() async {
        guard !loading, !Task.isCancelled else { return }
        let generation = AccountStorage.generation
        loading = true
        defer { if generation == AccountStorage.generation { loading = false } }
        _ = await backend.fetchComments(postID: postIDString)
        guard !Task.isCancelled, generation == AccountStorage.generation else { return }
        commentsLoadFailed = backend.commentsByPostID[postIDString] == nil
        if !initializedTarget, let focusedComment {
            selectReplyTarget(focusedComment)
            initializedTarget = true
        }
        updateRootOrder()
    }

    private var hasReplyDrafts: Bool {
        !pillDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pillAttachments.isEmpty
            || replyDrafts.values.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !$0.attachments.isEmpty }
    }

    private func requestBack() {
        guard !pillSending else { return }
        pillFocused = false
        if hasReplyDrafts { confirmLeave = true }
        else { back.perform { dismiss() } }
    }

    private func selectReplyTarget(_ target: WhisperCommentRow?) {
        guard !pillSending, target?.id != replyTarget?.id else { return }
        let oldKey = replyTarget?.id ?? "post"
        if !pillDraft.isEmpty || !pillAttachments.isEmpty {
            replyDrafts[oldKey] = (pillDraft, pillAttachments)
        } else { replyDrafts.removeValue(forKey: oldKey) }
        replyTarget = target
        let saved = replyDrafts.removeValue(forKey: target?.id ?? "post")
        pillDraft = saved?.text ?? ""
        pillAttachments = saved?.attachments ?? WhisperComposerAttachments()
    }

    private func finishReply() {
        if let target = replyTarget {
            expandedReplies.insert(target.id)
        }
        replyDrafts.removeValue(forKey: replyTarget?.id ?? "post")
        pillDraft = ""
        pillAttachments = WhisperComposerAttachments()
        selectReplyTarget(focusedComment)
    }

    // MARK: - Composer bar

    /// True when the pill has typed text or queued attachments to send.
    private var pillCanSend: Bool {
        (!pillDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pillAttachments.isEmpty)
            && pillDraft.count <= WhisperVerifiedPerks.characterLimit(username: composerUsername)
    }

    private var composerUsername: String {
        LeaderboardService.shared.savedUsername ?? AuthenticationService.shared.currentUser.username ?? "you"
    }

    private var composerBar: some View {
        WhisperThreadReplyBar(draft: $pillDraft, username: composerUsername,
            placeholder: replyTarget.map { "Reply to \($0.username)…" } ?? (isMyPost ? "Add to thread…" : "Add your reply…"),
            attachments: pillAttachments, isSending: pillSending, canSend: pillCanSend,
            characterLimit: WhisperVerifiedPerks.characterLimit(username: composerUsername), focused: $pillFocused,
            onPicker: { handOff(picker: $0) },
            onExpand: {
                Haptics.tap()
                pillFocused = false
                replyInitialPicker = nil
                presentReply = true
            },
            onSend: { Task { await sendPill() } },
            replyTo: replyTarget?.username,
            onClearTarget: { selectReplyTarget(focusedComment) })
    }

    /// User tapped a media picker icon on the pill. Surrender keyboard
    /// focus and open the full reply composer with that picker pre-armed.
    private func handOff(picker: WhisperReplyComposerPicker) {
        guard !pillSending else { return }
        pillFocused = false
        replyInitialPicker = picker
        presentReply = true
    }

    /// Posts whatever is currently in the pill (text + queued attachments)
    /// directly without opening the full composer.
    private func sendPill() async {
        guard pillCanSend, !pillSending, !commentsOff else { return }
        let generation = AccountStorage.generation
        pillSending = true
        defer { if generation == AccountStorage.generation { pillSending = false } }
        let parentID = replyTarget?.id
        let commentID = pillAttachments.commentID(baseBody: pillDraft, postID: postIDString, parentID: parentID)
        Haptics.tap()
        guard let body = await pillAttachments.finalize(baseBody: pillDraft, postID: postIDString) else {
            guard generation == AccountStorage.generation else { return }
            pillSending = false
            WhisperErrorService.shared.report("An attachment couldn't upload. Your reply is still here; please retry.")
            return
        }
        guard !Task.isCancelled, generation == AccountStorage.generation else { return }
        let posted = await backend.addComment(postID: postIDString, body: body, parentCommentID: parentID, commentID: commentID)
        guard !Task.isCancelled, generation == AccountStorage.generation else { return }
        guard posted != nil else {
            pillSending = false
            WhisperFeedback.failed()
            return
        }
        let caption = localPost.caption
        let pid = postIDString
        if posted != nil { WhisperFeedback.sent() } else { WhisperFeedback.failed() }
        // Clear the pill and refresh.
        pillSending = false
        finishReply()
        if WhisperEmberMention.shouldRespond(to: body) {
            let parentForReply = posted?.id
            Task {
                await WhisperEmberMention.respond(
                    toComment: body,
                    postID: pid,
                    parentCommentID: parentForReply,
                    postCaption: caption
                )
            }
        }
    }
}
