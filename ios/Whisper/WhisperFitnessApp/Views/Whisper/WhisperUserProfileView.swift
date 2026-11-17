import SwiftUI
import UIKit

/// Read-only Instagram-style profile for *another* Whisper user.
/// Pushed onto the navigation stack when the current user taps a username
/// or avatar in Explore search, the feed, comments, or the inbox.
struct WhisperUserProfileView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private let seedUser: WhisperUserRow
    @State private var resolvedUser: WhisperUserRow? = nil
    @State private var profileLoadFailed: Bool = false
    @State private var profileAccessReady: Bool = false
    @State private var loadOperation: UUID = UUID()
    @State private var presentEditProfile: Bool = false
    @State private var presentPostComposer = false
    private var user: WhisperUserRow { resolvedUser ?? seedUser }
    private var isSelf: Bool { user.user_id.lowercased() == AccountStorage.currentUserID.lowercased() }

    init(user: WhisperUserRow) { self.seedUser = user }

    @State private var follows = WhisperFollowService.shared
    @State private var followRequests = WhisperFollowRequestService.shared
    @State private var backend = WhisperBackendService.shared
    @State private var coach = WhisperCoachService.shared
    @State private var verifiedPerks = WhisperVerifiedPerksService.shared
    @State private var liar = WhisperLiarLiarService.shared
    @State private var safety = WhisperSafetyService.shared
    @State private var posts: [WhisperPostRow] = []
    @State private var nextPosts: WhisperHistoryCursor?
    @State private var loadingMorePosts = false
    @State private var morePostsError = false
    @State private var pageOperation = UUID()
    @State private var pageVisible = false
    @State private var continuationVisible = false
    @State private var automaticallyPagedBoundary: String?
    @State private var followerCount: Int = 0
    @State private var followingCount: Int = 0
    @State private var loading: Bool = true
    @State private var selectedPostRow: WhisperPostRow?
    @State private var openThread: WhisperConversationSummary?
    @State private var openFollowList: WhisperFollowListView.Tab?
    @State private var coachRequests = WhisperCoachRequestService.shared
    @State private var presentCoachRequestSheet: Bool = false
    @State private var billing = WhisperBillingService.shared
    @State private var featured = WhisperFeaturedService.shared
    @State private var hireStatus: WhisperHireStatus?
    @State private var coachRate: WhisperCoachRate?

    @State private var spotlightProfile: WhisperFeaturedProfile?
    @State private var detailSpotlight: WhisperFeaturedProfile?
    @State private var presentHireSheet: Bool = false
    @State private var blocks = WhisperBlockService.shared
    @State private var presentReport: Bool = false
    /// Branded 3-dots / block-confirm sheet for this profile.
    @State private var profileMenu: WhisperActionMenuModel?
    @State private var thoughts = WhisperThoughtService.shared
    /// Open the IG-Notes-style reply sheet when the viewer taps this
    /// user's What's-on-your-mind bubble above their profile photo.
    @State private var presentThoughtReply: Bool = false
    /// The full-screen pinch-zoom stage for this person's profile picture.
    @State private var presentAvatarZoom: Bool = false
    /// How the profile's posts render: the Threads-style list (default), the
    /// WAVES grid (the only place waves show), or the IG photo grid
    /// (creators). Waves never leak into the list or the photo grid.
    private typealias ProfileMode = WhisperProfileTab
    @State private var mode: ProfileMode = .threads
    /// A wave tapped in the Waves grid — opens the full-screen player.
    @State private var openWave: WhisperPostRow?
    @State private var presentShareSheet: Bool = false
    @State private var shareLinkCopied: Bool = false

    var body: some View {
        // Jasper has a bespoke profile view (his replies + bio) — short-
        // circuit here so any `@ember` mention or avatar tap that opens
        // a regular user profile lands on the curated Jasper experience
        // instead of an empty Threads-style profile.
        if ["knot", "ember", "jasper"].contains(user.username.lowercased()) {
            WhisperEmberProfileView().whisperNavigationBack().environment(\.whisperChatAppearance, .classic)
        } else {
            standardBody
        }
    }

    private var standardBody: some View {
        ZStack {
            WhisperTheme.card(colorScheme).ignoresSafeArea()
            GeometryReader { viewport in
                ScrollView {
                    VStack(spacing: 12) {
                        WhisperProfileHeaderCard(
                            userID: isLockedForViewer ? nil : user.user_id,
                            viewportHeight: viewport.size.height
                        ) {
                            header
                            if isSelf {
                                HStack(spacing: 8) {
                                    Button("Edit profile") { presentEditProfile = true }
                                    Button("Create post") { presentPostComposer = true }
                                }
                                .buttonStyle(WhisperFlatProfileButtonStyle())
                                .padding(.horizontal, 16)
                            } else { followAndMessage }
                            if !isLockedForViewer {
                                WhisperFeaturedLinksRow(
                                    userID: user.user_id,
                                    username: user.username,
                                    isMe: false
                                )
                                WhisperStoryHighlightsRow(userID: user.user_id, isMe: false)
                                profileViewModeToggle
                            }
                            postsListContent
                            profileContinuation
                        }
                    }
                    .padding(.bottom, !isLockedForViewer && !loading && !isSelf ? 120 : 32)
                }
            }
        }
        .whisperNavigationBack()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 0) {
                    Button { Haptics.tap(); presentShareSheet = true } label: {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share profile")
                    Button {
                        Haptics.tap()
                        profileMenu = buildProfileMenu()
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Profile options")
                }
            }.whisperFlatToolbar()
        }
        .whisperActionMenu($profileMenu)
        .task(id: seedUser.user_id) { await load(isInitial: true) }
        .onAppear { pageVisible = true }
        .onDisappear { pageVisible = false; pageOperation = UUID(); loadingMorePosts = false }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { pageOperation = UUID(); loadingMorePosts = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            pageOperation = UUID(); nextPosts = nil; loadingMorePosts = false
            resolvedUser = nil; posts = []; dismiss()
        }
        .onChange(of: isLockedForViewer) { _, locked in
            if locked { posts = []; nextPosts = nil; pageOperation = UUID(); loadingMorePosts = false }
        }
        .sheet(isPresented: $presentEditProfile) { WhisperEditProfileView() }
        .sheet(isPresented: $presentPostComposer) { WhisperComposerView().whisperSheetBorder() }
        .whisperRefreshable { await load(isInitial: false) }
        .overlay(alignment: .bottom) {
            // The meeting-style Jasper dock — the same analysis pill every
            // other surface wears (mascot peeking from behind the pill, floats
            // up into the dark glass box) instead of the old dashed "Ask
            // Jasper" rectangle at the top of the profile.
            if !isLockedForViewer && !loading && !isSelf {
                JasperAnalysisDock(
                    pillLabel: "Knot's read",
                    boxTitle: "@\(user.username) — Knot's read",
                    focus: """
                    You are reading @\(user.username)'s PUBLIC Whisper profile for another member who is viewing it. From the posts below give a quick, friendly read: what this person is about, what they're consistent at, and one genuine conversation-starter the viewer could open with. Ground every claim in the actual posts — never invent details.
                    """,
                    buildContext: { profileAnalysisContext() },
                    emptyText: "No posts to read yet — once @\(user.username) posts, I'll have signal here.",
                    actions: [
                        JasperDockAction(
                            id: "icebreaker",
                            label: "Icebreaker",
                            icon: "hand.wave.fill",
                            kind: .lens("Draft ONE friendly opening DM the viewer could send @\(user.username), grounded in their actual posts below — 1-2 sentences, warm, specific, never sycophantic. Then one short line on why it works.")
                        ),
                        JasperDockAction(
                            id: "common",
                            label: "Common ground",
                            icon: "person.2.fill",
                            kind: .lens("From the posts below, list 2-3 specific things worth connecting with @\(user.username) over — one line each, each grounded in a real post.")
                        ),
                    ]
                )
                .padding(.bottom, 10)
            }
        }
        .sheet(isPresented: $presentShareSheet) {
            WhisperShareSheet(username: user.username)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .whisperSheetBorder()
        }
        .overlay(alignment: .top) {
            if shareLinkCopied {
                Text("Link copied")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .fullScreenCover(item: $selectedPostRow) { row in
            postDetailSheet(row)
        }
        .fullScreenCover(item: $openWave) { row in
            // This user's waves, opened ON the tapped one — the Waves player
            // is the only format waves render in.
            WhisperReelsPlayerView(reels: wavePosts.map { postFromRow($0) }, start: postFromRow(row))
        }
        .fullScreenCover(item: $openThread) { thread in
            WhisperDMThreadView(otherUserID: thread.otherUserID, otherUsername: thread.otherUsername)
        }
        .sheet(item: $openFollowList) { tab in
            WhisperFollowListView(userID: user.user_id, username: user.username, initialTab: tab)
                .whisperSheetBorder()
        }
        .sheet(isPresented: $presentCoachRequestSheet) {
            WhisperCoachRequestSheet(coach: user)
                .whisperSheetBorder()
        }
        .sheet(isPresented: $presentHireSheet) {
            WhisperCoachHireSheet(
                coachUsername: user.username,
                coachUserID: user.user_id,
                monthlyPriceCents: coachRate?.monthlyPriceCents
            )
            .whisperSheetBorder()
        }
        .sheet(item: $detailSpotlight) { profile in
            WhisperFeaturedProfileDetailView(profile: profile)
        }
        .sheet(isPresented: $presentReport) {
            WhisperReportSheet(
                kind: .user,
                targetID: user.user_id,
                targetUserID: user.user_id,
                targetUsername: user.username
            )
            .whisperSheetBorder()
        }
    }

    /// Branded 3-dots sheet for this profile — Report + Block/Unblock in
    /// Whisper's own action menu instead of the system bubble.
    private func buildProfileMenu() -> WhisperActionMenuModel {
        var actions: [WhisperMenuAction] = [
            WhisperMenuAction(icon: "square.and.arrow.up", title: "Share profile", subtitle: "Send @\(user.username)'s profile link") {
                presentShareSheet = true
            },
            WhisperMenuAction(icon: "link", title: "Copy profile link") {
                copyProfileLink()
            },
            WhisperMenuAction(icon: "flag", title: "Report", isDestructive: true) {
                presentReport = true
            }
        ]
        if isSelf { return WhisperActionMenuModel(title: "@\(user.username)", actions: Array(actions.prefix(2))) }
        if blocks.isBlocked(userID: user.user_id) {
            actions.append(WhisperMenuAction(icon: "person.crop.circle.badge.checkmark", title: "Unblock") {
                Task { await blocks.unblock(userID: user.user_id, username: user.username) }
            })
        } else {
            actions.append(WhisperMenuAction(icon: "hand.raised.slash", title: "Block", isDestructive: true) {
                profileMenu = WhisperActionMenuModel(
                    title: "Block @\(user.username)?",
                    subtitle: "They won't be able to find your profile, stories, or DMs. You can unblock anytime from Settings.",
                    actions: [
                        WhisperMenuAction(icon: "hand.raised.slash", title: "Block", isDestructive: true) {
                            Task {
                                await blocks.block(userID: user.user_id, username: user.username)
                                dismiss()
                            }
                        }
                    ],
                    isConfirmStyle: true
                )
            })
        }
        return WhisperActionMenuModel(title: "@\(user.username)", actions: actions)
    }

    private func copyProfileLink() {
        let handle = user.username
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? user.username
        let link = "https://mydailywhisper.com/p/\(handle)"
        UIPasteboard.general.string = link
        Haptics.success()
        withAnimation(.spring(response: 0.3)) { shareLinkCopied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation { shareLinkCopied = false }
        }
    }

    /// Live context block for the Jasper dock — the viewer-visible profile
    /// numbers plus this user's recent posts (already loaded for the list).
    private func profileAnalysisContext() -> String? {
        guard !isLockedForViewer, !posts.isEmpty else { return nil }
        var lines: [String] = ["PROFILE @\(user.username) (public posts, newest first)"]
        lines.append("Followers \(followerCount) · following \(followingCount) · \(posts.count) posts loaded")
        for row in posts.prefix(12) {
            let caption = row.caption.isEmpty ? "(media post)" : String(row.caption.prefix(80))
            let kind = (row.is_reel ?? false) ? "reel" : (row.kind ?? "post")
            lines.append("- \(kind) · \(row.likes_count ?? 0) likes · \(row.comments_count ?? 0) comments · \(WhisperPost.relativeTime(from: row.created_at)) · \(caption)")
        }
        return lines.joined(separator: "\n")
    }

    private func load(isInitial: Bool = true) async {
        let contentReadiness = WhisperPerformance.Span("ProfileContentVisible")
        defer { contentReadiness.finish() }
        // Only show the full-screen spinner on the very first load. Pull-to-
        // refresh keeps the existing header/posts on screen and silently
        // swaps in the new values once the network calls return, so the
        // profile never "zeros out" mid-refresh.
        if isInitial && posts.isEmpty {
            loading = true
        }
        let generation = AccountStorage.generation
        let operation = UUID(); loadOperation = operation
        pageOperation = UUID(); loadingMorePosts = false; morePostsError = false
        // Public profiles can keep their currently visible content while revalidating.
        // Private profiles still hide content until current follow/access checks succeed.
        let retainsPublicContent = resolvedUser != nil && profileAccessReady && user.is_private == false && !isLockedForViewer
        if !retainsPublicContent { profileAccessReady = false; loading = true }
        profileLoadFailed = false
        guard let canonical = await WhisperUserService.shared.fetchByUserID(seedUser.user_id),
              canonical.user_id.lowercased() == seedUser.user_id.lowercased() else {
            guard !Task.isCancelled, generation == AccountStorage.generation, loadOperation == operation else { return }
            profileLoadFailed = true; loading = false; return
        }
        guard !Task.isCancelled, generation == AccountStorage.generation, loadOperation == operation else { return }
        resolvedUser = canonical
        async let followerCountTask = follows.followerCount(forUserID: user.user_id)
        async let followingCountTask = follows.followingCount(forUserID: user.user_id)
        async let accessFollows: Void = follows.refresh()
        async let accessRequests: Void = followRequests.refresh()
        _ = await (accessFollows, accessRequests)
        guard !Task.isCancelled, generation == AccountStorage.generation, loadOperation == operation else { return }
        guard follows.lastError == nil else { profileLoadFailed = true; loading = false; return }
        profileAccessReady = true
        var primary: [WhisperPostRow] = []
        var continuation: WhisperHistoryCursor?
        if !isLockedForViewer {
            do {
                let page = try await backend.fetchProfilePostPage(forUserID: user.user_id)
                primary = page.rows; continuation = page.next
            }
            catch {
                guard !Task.isCancelled, generation == AccountStorage.generation, loadOperation == operation else { return }
                profileLoadFailed = true; loading = false; return
            }
        }
        guard !Task.isCancelled, generation == AccountStorage.generation, loadOperation == operation else { return }
        // Content is authorized and useful now; statistics and badges must not
        // hold the grid behind the initial spinner.
        posts = isLockedForViewer ? [] : primary
        nextPosts = isLockedForViewer ? nil : continuation
        automaticallyPagedBoundary = nil
        loading = false
        contentReadiness.finish(completed: !isLockedForViewer)
        let fc = await followerCountTask
        let fg = await followingCountTask
        guard !Task.isCancelled, generation == AccountStorage.generation, loadOperation == operation else { return }
        followerCount = fc; followingCount = fg
        guard !isLockedForViewer else { return }
        guard !Task.isCancelled, generation == AccountStorage.generation, loadOperation == operation, !isLockedForViewer else { return }
        async let verificationLoad: Void = UserVerificationService.shared.preload(usernames: [user.username])
        // Director badge is not fetched by the general badge services — it has
        // its own cache. Preload it so a director's profile shows the media
        // team chip on first paint, and refresh my own status in case I'm
        // viewing my own profile through this path.
        async let directorLoad: Void = WhisperDirectorService.shared.preload(userIDs: [user.user_id])
        if user.user_id.lowercased() == AccountStorage.currentUserID.lowercased() {
            await WhisperDirectorService.shared.refreshMyStatus()
        }
        // Pull Liar Liar + safety chip data for this profile so the badge
        // strip + shelf render correctly on first paint instead of staying
        // empty until another screen happens to hydrate the same user.
        async let liarLoad: Void = WhisperLiarLiarService.shared.preload(usernames: [user.username])
        async let perksLoad: Void = WhisperOneService.shared.preload(userIDs: [user.user_id], usernames: [user.username])
        async let ageLoad: Void = WhisperSafetyService.shared.preloadAgeBands(userIDs: [user.user_id])
        async let watchLoad: Void = WhisperSafetyService.shared.preloadWatchFlags(
            userIDs: [user.user_id],
            usernames: [user.username]
        )
        async let coachIDLoad: Bool = coach.ensureCoachStatus(userID: user.user_id)
        async let coachNameLoad: Bool = coach.ensureCoachStatus(username: user.username)
        async let verifiedLoad: Void = verifiedPerks.refresh(forUserID: user.user_id)
        async let requestsLoad: Void = coachRequests.refresh()
        // Check if this member (coach or creator) has a featured spotlight
        // profile — both kinds get the spotlight banner.
        let spotlight = await featured.fetchByUsername(user.username)
        _ = await (verificationLoad, directorLoad, liarLoad, perksLoad, ageLoad, watchLoad, coachIDLoad, coachNameLoad, verifiedLoad, requestsLoad)
        guard !Task.isCancelled, generation == AccountStorage.generation, loadOperation == operation, !isLockedForViewer else { return }
        spotlightProfile = spotlight
        // If the viewed user is a coach, check their hire/payment status.
        let isTargetCoach = coach.isCoach(userID: user.user_id) || coach.isCoach(username: user.username)
        if isTargetCoach && user.user_id.lowercased() != AccountStorage.currentUserID.lowercased() {
            do {
                async let rateRead = billing.fetchCoachRate(coachUserID: user.user_id)
                async let statusRead = billing.fetchHireStatus(coachUserID: user.user_id)
                let (rate, status) = try await (rateRead, statusRead)
                guard !Task.isCancelled, generation == AccountStorage.generation, loadOperation == operation else { return }
                await MainActor.run {
                    self.coachRate = rate
                    self.hireStatus = status
                }
            } catch {
                // Rate or status not available — the hire button just won't show.
            }
        }
    }

    @ViewBuilder
    private var profileContinuation: some View {
        if !isLockedForViewer && !loading && !profileLoadFailed && mode != .replies && mode != .reposts && nextPosts != nil {
            VStack(spacing: 8) {
                if loadingMorePosts { ProgressView().accessibilityLabel("Loading more posts") }
                else {
                    if morePostsError { Text("Posts couldn’t load just now.").font(.footnote).foregroundStyle(.secondary) }
                    Button(morePostsError ? "Try again" : "More posts") { Task { await loadMoreProfilePosts() } }
                        .frame(minHeight: 44)
                }
            }
            .padding(16)
            .onScrollVisibilityChange(threshold: 0.1) { continuationVisible = $0 }
            .task(id: "\(continuationVisible)/\(mode)/\(posts.last?.id ?? "empty")") {
                // One automatic advance per visible content boundary. If a raw
                // page adds no visible rows, leave a deliberate More action.
                let boundary = "\(mode)/\(posts.last?.id ?? "empty")"
                guard pageVisible, continuationVisible, !morePostsError, automaticallyPagedBoundary != boundary else { return }
                automaticallyPagedBoundary = boundary
                await loadMoreProfilePosts()
            }
        }
    }

    private func loadMoreProfilePosts() async {
        guard pageVisible, scenePhase == .active, selectedPostRow == nil, openWave == nil,
              !loading, !loadingMorePosts, !isLockedForViewer, profileAccessReady,
              let cursor = nextPosts else { return }
        let generation = AccountStorage.generation, request = UUID(), profileRequest = loadOperation
        pageOperation = request; loadingMorePosts = true; morePostsError = false
        defer { if pageOperation == request { loadingMorePosts = false } }
        do {
            let page = try await backend.fetchProfilePostPage(forUserID: user.user_id, before: cursor)
            guard !Task.isCancelled, pageVisible, generation == AccountStorage.generation,
                  pageOperation == request, loadOperation == profileRequest, !isLockedForViewer else { return }
            posts = WhisperFeedPaging.append(page.rows, to: posts, deleted: backend.deletedPostIDs)
            nextPosts = page.next
        } catch {
            guard !Task.isCancelled, pageVisible, generation == AccountStorage.generation,
                  pageOperation == request, loadOperation == profileRequest else { return }
            morePostsError = true
        }
    }

    // MARK: - Header

    private var header: some View {
        // Surface this user's IG-Notes "What's on your mind?" bubble above
        // their avatar so viewers see the same floating note the stories
        // strip already exposes. Tapping the bubble opens the lyrics +
        // reply sheet so visitors can respond inline.
        let note = isLockedForViewer ? nil : thoughts.activeThought(forUserID: user.user_id)
        return WhisperProfileIdentityView(displayName: user.display_name?.isEmpty == false ? (user.display_name ?? user.username) : user.username, username: user.username, biography: AnyView(bio)) {
            WhisperAvatarChrome(
                username: user.username,
                size: 144,
                imageURL: user.profile_image_url.flatMap { URL(string: $0) },
                storyRing: false,
                plusButton: false,
                thoughtText: note?.text,
                thoughtStyle: WhisperThoughtStyle(rawValue: note?.style ?? "") ?? .plain,
                thoughtAccent: note?.accent ?? "",
                thoughtEmoji: note?.emoji ?? "",
                thoughtColorHex: note?.color_hex ?? "",
                bubbleScale: 1.18,
                reservesThoughtSpace: false,
                onBubbleTap: note == nil ? nil : {
                    Haptics.tap()
                    presentThoughtReply = true
                }
            )
            // Tap (or long-press) the picture → the full-screen zoom stage.
            .onTapGesture {
                Haptics.tap()
                presentAvatarZoom = true
            }
            .onLongPressGesture(minimumDuration: 0.35) {
                Haptics.tap()
                presentAvatarZoom = true
            }
            .fullScreenCover(isPresented: $presentAvatarZoom) {
                WhisperAvatarZoomView(
                    username: user.username,
                    imageURL: user.profile_image_url.flatMap { URL(string: $0) }
                )
            }
        } stats: {
            HStack(spacing: 0) {
                statCell("followers", value: shortNumber(followerCount)) { openFollowList = .followers }
                statCell("posts", value: "\(posts.count)") { mode = .threads }
                statCell("following", value: "\(followingCount)") { openFollowList = .following }
            }
        }
        .task(id: isLockedForViewer) {
            guard !isLockedForViewer else { return }
            await thoughts.refreshOthers(userIDs: [user.user_id])
        }
        .sheet(isPresented: $presentThoughtReply) {
            // Tapping another user's thought now opens the same community
            // group chat the owner sees — the thought is pinned at the top
            // and the composer is right there. RLS-allowed visibility means
            // repliers see each other if the group-read policy is installed.
            WhisperThoughtRepliesSheet(
                externalOwnerUID: user.user_id,
                externalOwnerUsername: user.username
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(22)
            .whisperSheetBorder()
        }
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

    /// Kit 4.0 profile grammar — lifts the first URL out of a bio so it can
    /// render as the dedicated link row under the bio text.
    private func bioParts(_ raw: String?) -> (text: String, url: URL?, label: String, extra: Int) {
        guard let raw, !raw.isEmpty else { return ("", nil, "", 0) }
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

    // MARK: - Bio

    private var bio: some View {
        WhisperProfileBioView(text: user.bio ?? "", category: user.professional_category ?? "", interests: user.interests ?? [])
    }

    private var legacyBio: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(user.display_name?.isEmpty == false ? user.display_name! : user.username)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            // The creator niche / professional category — Instagram's light-gray
            // line under the name ("Athlete", "Digital creator").
            if let niche = user.professional_category?.trimmingCharacters(in: .whitespacesAndNewlines), !niche.isEmpty {
                Text(niche)
                    .font(.footnote)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(1)
            }
            let parts = bioParts(user.bio)
            if !parts.text.isEmpty {
                Text(parts.text)
                    .font(.subheadline)
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
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
            if let interests = user.interests, !interests.isEmpty {
                Text(interests.prefix(4).map { "#\($0)" }.joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    // MARK: - Follow + message

    private var followAndMessage: some View {
        let isFollowing = follows.isFollowing(userID: user.user_id)
        let isRequested = followRequests.hasPendingOutgoing(targetID: user.user_id)
        return VStack(spacing: 6) {
        if let err = follows.lastError {
            Text(err)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.85), in: .rect(cornerRadius: 10))
                .padding(.horizontal, 16)
                .onTapGesture { follows.lastError = nil }
        }
        HStack(spacing: 6) {
            Button {
                Haptics.tap()
                Task {
                    if isFollowing {
                        _ = await follows.unfollow(userID: user.user_id)
                    } else if isRequested {
                        _ = await followRequests.cancelRequest(targetID: user.user_id)
                    } else {
                        _ = await follows.attemptFollow(userID: user.user_id, username: user.username)
                        await followRequests.refresh()
                    }
                    await load(isInitial: false)
                }
            } label: {
                let isOutlined = isFollowing || isRequested
                let label: String = {
                    if isFollowing { return "Following" }
                    if isRequested { return "Requested" }
                    return "Follow"
                }()
                Text(label)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isOutlined ? WhisperTheme.ink(colorScheme) : WhisperTheme.surface(colorScheme))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(
                        isOutlined ? WhisperTheme.card(colorScheme) : WhisperTheme.ink(colorScheme),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: isOutlined ? 1 : 0)
                    }
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                openThread = WhisperConversationSummary(
                    otherUserID: user.user_id,
                    otherUsername: user.username,
                    lastMessage: "",
                    lastDate: Date()
                )
            } label: {
                Text("Message")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .modifier(WhisperControlGlass(shape: Capsule()))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        coachRequestButton
        hireCoachButton
        featuredSpotlightLink
        }
    }

    @ViewBuilder
    private var coachRequestButton: some View {
        let isTargetCoach = coach.isCoach(userID: user.user_id) || coach.isCoach(username: user.username)
        let isSelf = user.user_id.lowercased() == AccountStorage.currentUserID.lowercased()
        if isTargetCoach && !isSelf {
            let status = coachRequests.outgoingStatus(coachUserID: user.user_id)
            Button {
                Haptics.tap()
                if status != "accepted" && status != "pending" {
                    presentCoachRequestSheet = true
                }
            } label: {
                WhisperCoachActionLabel(title: requestLabel(status), subtitle: status == "accepted" ? "Health sharing is connected" : status == "pending" ? "Waiting for their response" : "Choose what health data to share", icon: requestIcon(status))
            }
            .buttonStyle(.plain)
            .disabled(status == "pending" || status == "accepted")
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    private func requestLabel(_ status: String?) -> String {
        switch status {
        case "pending":  return "Request pending"
        case "accepted": return "Your coach"
        case "declined": return "Ask again"
        default:         return "Request coaching"
        }
    }

    private func requestIcon(_ status: String?) -> String {
        switch status {
        case "pending":  return "hourglass"
        case "accepted": return "checkmark.seal.fill"
        default:         return "seal.fill"
        }
    }

    // MARK: - Hire coach button

    /// When the viewed user is a coach with an active monthly rate and
    /// payout-ready bank account, show a "Hire" button that opens the
    /// Stripe Checkout flow. If the client has already paid, show an
    /// "Active" status instead.
    @ViewBuilder
    private var hireCoachButton: some View {
        let isTargetCoach = coach.isCoach(userID: user.user_id) || coach.isCoach(username: user.username)
        let isSelf = user.user_id.lowercased() == AccountStorage.currentUserID.lowercased()
        if isTargetCoach && !isSelf,
           let status = hireStatus, status.requiresPayment {
            if status.paid {
                WhisperCoachActionLabel(title: "Coaching subscription active", subtitle: "Your current plan", icon: "checkmark.seal")
                .padding(.horizontal, 16)
                .padding(.top, 4)
            } else {
                Button {
                    Haptics.tap()
                    presentHireSheet = true
                } label: {
                    WhisperCoachActionLabel(title: "Work with \(user.display_name ?? user.username)", subtitle: status.priceCents.map { "\(WhisperBillingService.formatCents($0)) per month · View plan" } ?? "View coaching plan", icon: "person.crop.rectangle", prominent: true)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
        }
    }

    /// If the viewed user has a featured spotlight profile (coach, athlete,
    /// or creator), show a kind-accented banner that opens the full
    /// spotlight detail — the "special appearance" for featured members.
    @ViewBuilder
    private var featuredSpotlightLink: some View {
        if let profile = spotlightProfile {
            let accent: Color = {
                switch profile.kindEnum {
                case .director: return Color(red: 0.10, green: 0.10, blue: 0.10)
                case .coach:    return WhisperTheme.coachAccent
                case .athlete:  return Color(red: 0.88, green: 0.11, blue: 0.28)
                case .creator:  return Color(red: 0.13, green: 0.55, blue: 0.96)
                }
            }()
            let kindLabel: String = {
                switch profile.kindEnum {
                case .director: return "Featured Director"
                case .coach:    return "Featured Coach"
                case .athlete:  return "Featured Athlete"
                case .creator:  return "Featured Creator"
                }
            }()
            Button {
                Haptics.tap()
                detailSpotlight = profile
            } label: {
                HStack(spacing: 12) {
                    WhisperTheme.card(colorScheme)
                        .frame(width: 40, height: 40)
                        .overlay {
                            if let raw = profile.photo_url, let url = URL(string: raw) {
                                WhisperCachedAsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let img):
                                        img.resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .allowsHitTesting(false)
                                    default:
                                        Image(systemName: "sparkles")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(accent)
                                    }
                                }
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(accent)
                            }
                        }
                        .clipShape(.rect(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kindLabel.uppercased())
                            .font(.caption2.weight(.black))
                            .tracking(1.1)
                            .foregroundStyle(accent)
                        Text("View \(profile.name)'s spotlight")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(accent.opacity(0.07), in: .rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(accent.opacity(0.35), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    // MARK: - Posts list

    /// True when the viewed user has flipped Private on AND the current
    /// viewer is neither the user themselves nor an approved follower. In
    /// that case posts + highlights are hidden behind a lock card, same as
    /// Instagram.
    private var isLockedForViewer: Bool {
        !WhisperProfileVisibilityPolicy.canView(viewerID: AccountStorage.currentUserID, authorID: user.user_id,
            resolved: resolvedUser != nil && profileAccessReady && !profileLoadFailed, isPrivate: user.is_private,
            following: follows.isFollowing(userID: user.user_id), blocked: blocks.isBlocked(userID: user.user_id))
    }

    /// True when the viewed user has a creator / verified badge — the grid
    /// view option is surfaced only for these accounts.
    private var isCreatorProfile: Bool {
        WhisperVerifiedPerks.isVerified(username: user.username)
    }

    /// Everything that is NOT a wave — the list + photo grid pool.
    private var nonWavePosts: [WhisperPostRow] {
        posts.filter { $0.is_reel != true && !backend.deletedPostIDs.contains($0.id.lowercased()) }
    }

    /// Waves only — the Waves grid pool.
    private var wavePosts: [WhisperPostRow] {
        posts.filter { $0.is_reel == true && !backend.deletedPostIDs.contains($0.id.lowercased()) }
    }

    /// List · Waves (· Grid for verified creators) — the segmented mode switch.
    private var profileViewModeToggle: some View {
        WhisperProfileTabsView(selection: $mode)
    }

    private var legacyModeToggle: some View {
        HStack(spacing: 0) {
            modeSegment(.threads, icon: "list.bullet", label: "List")
            modeSegment(.waves, icon: "play.rectangle", label: "Waves")
            if isCreatorProfile {
                modeSegment(.media, icon: "square.grid.2x2", label: "Grid")
            }
        }
        .padding(4)
        .background(WhisperTheme.surface(colorScheme), in: Capsule())
        .overlay {
            Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    private func modeSegment(_ target: ProfileMode, icon: String, label: String) -> some View {
        let active = mode == target
        return Button {
            Haptics.tap()
            withAnimation(.whisperSnappy) { mode = target }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(active ? WhisperTheme.ink(colorScheme) : WhisperTheme.muted(colorScheme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(active ? WhisperTheme.card(colorScheme) : Color.clear, in: Capsule())
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var postsListContent: some View {
        if profileLoadFailed {
            ContentUnavailableView {
                Label("Couldn't load profile", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: { Text("Check your connection and try again.") } actions: {
                Button("Try again") { Task { await load() } }
            }
        } else if resolvedUser == nil || loading {
            ProgressView()
                .tint(WhisperTheme.ink(colorScheme))
                .padding(.top, 32)
        } else if isLockedForViewer {
            privateAccountLockedCard
        } else if mode == .replies || mode == .reposts {
            WhisperProfileActivityView(userID: user.user_id, username: user.username, tab: mode)
        } else if mode == .waves {
            wavesContent
        } else if mode == .media {
            gridContent
        } else if nonWavePosts.isEmpty {
            WhisperProfileEmptyState(
                illustration: .posts, title: "Nothing here yet",
                message: wavePosts.isEmpty
                    ? "When @\(user.username) shares a post, this is where it lands. Say hi in the meantime."
                    : "@\(user.username) hasn't shared a whisp yet — check the Waves tab."
            )
            .padding(.horizontal, 16)
            .padding(.top, 16)
        } else {
            let ordered = applyingPins(nonWavePosts)
            LazyVStack(spacing: 0) {
                ForEach(Array(ordered.enumerated()), id: \.element.id) { idx, row in
                    if WhisperVerifiedPerks.isVerified(username: user.username),
                       verifiedPerks.pinnedPostIDs(forUserID: user.user_id).contains(where: { $0.lowercased() == row.id.lowercased() }) {
                        WhisperPinnedPostLabel()
                    }
                    WhisperPostCard(post: postFromRow(row))
                    if idx < ordered.count - 1 {
                        Divider().background(WhisperTheme.hairline(colorScheme))
                    }
                }
            }
        }
    }

    /// The WAVES grid — 3-column 9:16 tiles; tap opens the player on that wave.
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
                message: "@\(user.username) hasn't posted a wave. Their short videos will land here."
            )
            .padding(.horizontal, 16)
            .padding(.top, 24)
        } else {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(wavePosts) { row in
                    Button {
                        Haptics.tap()
                        openWave = row
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
        let mediaPosts = nonWavePosts.filter { ($0.media_urls?.isEmpty == false) }
        if mediaPosts.isEmpty {
            WhisperProfileEmptyState(
                title: "No photos yet",
                message: "@\(user.username)'s grid is waiting for its first shot."
            )
            .padding(.horizontal, 16)
            .padding(.top, 24)
        } else {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(mediaPosts) { row in
                    gridCell(row)
                }
            }
        }
    }

    private func gridCell(_ row: WhisperPostRow) -> some View {
        Button { Haptics.tap(); selectedPostRow = row } label: {
            WhisperProfileMediaTile(row: row)
        }
        .buttonStyle(GridCellPressStyle())
        .contextMenu {
            Button("Open post", systemImage: "arrow.up.right.square") { selectedPostRow = row }
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
        let mediaCount = row.media_urls?.count ?? 0
        let isVideo = url.map { WhisperVideo.isVideo($0) } ?? false
        let accent = WhisperPost.color(fromHex: row.accent_hex) ?? Color.gray
        let symbol = row.symbol ?? (WhisperPostKind(rawValue: row.kind ?? "")?.icon ?? "sparkles")
        return Button {
            Haptics.tap()
            selectedPostRow = row
        } label: {
            WhisperTheme.card(colorScheme)
                .aspectRatio(1, contentMode: .fill)
                .overlay {
                    if let url = url {
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
                    if mediaCount > 1 || isVideo {
                        Image(systemName: isVideo ? "play.fill" : "square.on.square")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .shadow(radius: 1)
                            .padding(6)
                    }
                }
                .clipped()
        }
        .buttonStyle(.plain)
        // Long-press peek — flips through the whole set without opening it.
        .contextMenu {
            Button {
                Haptics.tap()
                selectedPostRow = row
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

    /// Instagram-style locked card shown when the viewed user is private
    /// and the viewer hasn't been approved yet. Tells them exactly what to
    /// do next — send a follow request if they haven't already.
    private var privateAccountLockedCard: some View {
        let isRequested = followRequests.hasPendingOutgoing(targetID: user.user_id)
        return VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(WhisperTheme.card(colorScheme))
                    .frame(width: 72, height: 72)
                Image(systemName: "lock.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            Text("This account is private")
                .font(.headline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text(isRequested
                 ? "Your follow request is pending. You'll see @\(user.username)'s posts once they approve you."
                 : "Follow @\(user.username) to see their posts, highlights, and stories.")
                .font(.subheadline)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 16)
    }

    /// Verified perk: float pinned posts to the top in their configured order.
    private func applyingPins(_ rows: [WhisperPostRow]) -> [WhisperPostRow] {
        guard WhisperVerifiedPerks.isVerified(username: user.username) else { return rows }
        let ids = verifiedPerks.pinnedPostIDs(forUserID: user.user_id)
        guard !ids.isEmpty else { return rows }
        let lookup = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        var pinned: [WhisperPostRow] = []
        for id in ids { if let r = lookup[id] { pinned.append(r) } }
        let pinnedSet = Set(pinned.map { $0.id })
        let rest = rows.filter { !pinnedSet.contains($0.id) }
        return pinned + rest
    }

    private func postFromRow(_ row: WhisperPostRow) -> WhisperPost {
        let urls: [URL] = (row.media_urls ?? []).compactMap { URL(string: $0) }
        return WhisperPost(
            id: UUID(uuidString: row.id) ?? UUID(),
            username: row.username ?? user.username,
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
            createdAt: WhisperBackendService.parseISO(row.created_at),
            authorUserID: row.user_id
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
            .clipped()
            .contentShape(.rect)
    }

    /// Same full-screen detail the feed opens — grid posts get the IG-style
    /// photo detail, text posts get the thread view. No more mini sheet.
    private func postDetailSheet(_ row: WhisperPostRow) -> some View {
        WhisperPostDetailView(post: postFromRow(row))
    }

}
