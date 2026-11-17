import SwiftUI

// MARK: - The peek moment
//
// Long-press a wave tile in the feed or a story bubble in a strip and the
// whole app blurs and dims in place while the thing you pressed lifts into a
// big preview card with a quiet actions card under it — the reference
// grammar exactly:
//
//   ┌──────────────────────────────┐
//   │ ◉ username            0:34   │
//   │                              │
//   │        the wave, playing     │
//   │                              │
//   │ ♪ username · Original audio  │
//   └──────────────────────────────┘
//   ┌──────────────────┐
//   │ ♡  Like          │
//   │ ⟳  Repost        │
//   │ ✈  Share         │
//   │ ◎  View profile  │
//   │ !  Report        │   (red)
//   └──────────────────┘
//
// ONE center drives it (`WhisperPeekCenter.shared`), hosted once at the app
// root so the tab bar dims too. Peeking a story never records a view — the
// full viewer (a tap on the card) does.

/// What can be peeked.
enum WhisperPeekItem: Identifiable {
    case wave(WhisperPost)
    /// One author's stories, oldest → newest (the viewer's order).
    case story([WhisperStoryRow])

    var id: String {
        switch self {
        case .wave(let post): return "wave-\(post.id.uuidString)"
        case .story(let group): return "story-\(group.first?.user_id ?? "")"
        }
    }
}

/// Identifiable wrappers for the host's presentations.
struct WhisperPeekStoryGroup: Identifiable {
    let id = UUID()
    let stories: [WhisperStoryRow]
}

struct WhisperPeekDMTarget: Identifiable {
    let id = UUID()
    let userID: String
    let username: String
}

struct WhisperPeekReportTarget: Identifiable {
    let id = UUID()
    let kind: WhisperReportTargetKind
    let targetID: String
    let targetUserID: String
    let targetUsername: String
}

/// The one peek center. Views call `present`; the root hosts the overlay and
/// every hand-off (player, viewer, profile, DM, share, report).
@MainActor
@Observable
final class WhisperPeekCenter {
    static let shared = WhisperPeekCenter()

    var item: WhisperPeekItem?

    // Hand-offs — set by the overlay, presented by the host (which is always
    // mounted, so a presentation never dies with the overlay).
    var openWave: WhisperPost?
    var openStories: WhisperPeekStoryGroup?
    var openUser: WhisperUserRow?
    var openDM: WhisperPeekDMTarget?
    var sharePost: WhisperPost?
    var report: WhisperPeekReportTarget?

    private init() {}

    func present(_ item: WhisperPeekItem) {
        Haptics.rigid()
        withAnimation(.easeOut(duration: 0.18)) { self.item = item }
    }

    func dismiss() {
        withAnimation(.easeOut(duration: 0.18)) { item = nil }
    }
}

// MARK: - Story favorites (device-local)

/// Stories you've starred — they sort first in every strip and wear a small
/// star. Device-local, per account.
@MainActor
@Observable
final class WhisperStoryFavorites {
    static let shared = WhisperStoryFavorites()

    private(set) var userIDs: Set<String> = []

    private var key: String { "whisper.story.favorites.\(AccountStorage.currentUserID)" }

    private init() { reload() }

    func reload() {
        let stored = UserDefaults.standard.stringArray(forKey: key) ?? []
        userIDs = Set(stored.map { $0.lowercased() })
    }

    func isFavorite(_ userID: String) -> Bool {
        userIDs.contains(userID.lowercased())
    }

    func toggle(_ userID: String) {
        let id = userID.lowercased()
        if userIDs.contains(id) { userIDs.remove(id) } else { userIDs.insert(id) }
        UserDefaults.standard.set(Array(userIDs).sorted(), forKey: key)
    }

    /// Favorites first, otherwise the original order.
    func sorted<T>(_ items: [T], userID: (T) -> String) -> [T] {
        guard !userIDs.isEmpty else { return items }
        let favs = items.filter { isFavorite(userID($0)) }
        let rest = items.filter { !isFavorite(userID($0)) }
        return favs + rest
    }
}

// MARK: - Host

/// Mount ONCE at the app root: blurs + dims the whole app while a peek is
/// up, renders the overlay, and owns every hand-off presentation.
struct WhisperPeekHost: ViewModifier {
    @State private var center = WhisperPeekCenter.shared
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        ZStack {
            // The peek's blur is a GPU material inside the overlay — blurring
            // the whole app root per frame was the lag on every long-press.
            content

            if let item = center.item {
                WhisperPeekOverlay(item: item)
                    .zIndex(90)
                    .transition(.opacity)
            }
        }
        .fullScreenCover(item: $center.openWave) { post in
            WhisperReelsPlayerView(reels: [post], start: post)
        }
        .fullScreenCover(item: $center.openStories) { group in
            WhisperStoryViewer(
                stories: group.stories,
                startIndex: WhisperStoryService.shared.firstUnseenIndex(in: group.stories)
            )
        }
        .fullScreenCover(item: $center.openUser) { user in
            NavigationStack {
                WhisperUserProfileView(user: user)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { center.openUser = nil }
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                        }
                    }
            }
        }
        .fullScreenCover(item: $center.openDM) { target in
            WhisperDMThreadView(otherUserID: target.userID, otherUsername: target.username)
        }
        .sheet(item: $center.sharePost) { post in
            WhisperPostShareSheet(post: post)
        }
        .sheet(item: $center.report) { target in
            WhisperReportSheet(
                kind: target.kind,
                targetID: target.targetID,
                targetUserID: target.targetUserID,
                targetUsername: target.targetUsername
            )
        }
    }
}

extension View {
    /// See `WhisperPeekHost`.
    func whisperPeekHost() -> some View { modifier(WhisperPeekHost()) }
}

// MARK: - Overlay

struct WhisperPeekOverlay: View {
    let item: WhisperPeekItem

    @Environment(\.colorScheme) private var colorScheme
    @State private var center = WhisperPeekCenter.shared
    @State private var favorites = WhisperStoryFavorites.shared
    @State private var shown: Bool = false
    @State private var releasing: Bool = false
    @State private var liked: Bool = false
    @State private var likes: Int = 0
    @State private var resolvingUser: Bool = false

    private let menuRow: CGFloat = 50
    private let menuWidth: CGFloat = 226

    private struct Row: Identifiable {
        let id: String
        let icon: String
        let title: String
        var tint: Color? = nil
        var destructive: Bool = false
        let action: () -> Void
    }

    var body: some View {
        GeometryReader { geo in
            let safeTop: CGFloat = geo.safeAreaInsets.top
            let safeBottom: CGFloat = geo.safeAreaInsets.bottom
            let rows = menuRows
            let menuHeight: CGFloat = CGFloat(rows.count) * menuRow + 12
            let cardWidth: CGFloat = min(geo.size.width * 0.8, 340)
            let room: CGFloat = geo.size.height - safeTop - safeBottom - menuHeight - 14 - 36
            let cardHeight: CGFloat = max(220, min(cardWidth * 16 / 9, room))
            let cardX: CGFloat = (geo.size.width - cardWidth) / 2
            let cardY: CGFloat = safeTop + 16

            ZStack(alignment: .topLeading) {
                ZStack {
                    Rectangle().fill(.regularMaterial)
                    (colorScheme == .dark ? Color.black.opacity(0.42) : Color.black.opacity(0.18))
                }
                    .ignoresSafeArea()
                    .opacity(shown ? 1 : 0)
                    .contentShape(.rect)
                    .onTapGesture { release() }

                card
                    .frame(width: cardWidth, height: cardHeight)
                    .clipShape(.rect(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 30, y: 16)
                    .offset(x: cardX, y: cardY)
                    .scaleEffect(shown ? 1 : 0.86, anchor: .center)
                    .opacity(shown ? 1 : 0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: shown)

                menu(rows)
                    .frame(width: menuWidth)
                    .offset(x: cardX, y: cardY + cardHeight + 14)
                    .scaleEffect(shown ? 1 : 0.86, anchor: .topLeading)
                    .offset(y: shown ? 0 : -10)
                    .opacity(shown ? 1 : 0)
                    .animation(.spring(response: 0.42, dampingFraction: 0.8).delay(shown ? 0.05 : 0), value: shown)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            if case .wave(let post) = item {
                liked = post.liked
                likes = post.likes
            }
            shown = true
        }
    }

    // MARK: Card

    @ViewBuilder
    private var card: some View {
        switch item {
        case .wave(let post):
            waveCard(post)
        case .story(let group):
            storyCard(group)
        }
    }

    private func waveCard(_ post: WhisperPost) -> some View {
        Button {
            Haptics.tap()
            handoff { center.openWave = post }
        } label: {
            ZStack {
                Color.black
                if let url = post.mediaURLs.first(where: { WhisperVideo.isVideo($0) }) {
                    WhisperVideoView(url: url, autoplay: true, startsMuted: true, showsControls: false)
                        .allowsHitTesting(false)
                } else if let url = post.mediaURLs.first {
                    WhisperCachedAsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            LinearGradient(colors: [post.accent.opacity(0.9), post.accent.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                        }
                    }
                    .allowsHitTesting(false)
                } else {
                    LinearGradient(colors: [post.accent.opacity(0.9), post.accent.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                }

                LinearGradient(colors: [.black.opacity(0.45), .clear, .clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        WhisperAvatar(username: post.username, size: 32, ring: false)
                        Text(post.username)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if likes > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text(compact(likes))
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 14)

                    let caption = post.displayCaption.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !caption.isEmpty {
                        Text(caption)
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .shadow(color: .black.opacity(0.55), radius: 6, y: 1)
                            .padding(.horizontal, 22)
                            .padding(.top, 34)
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 6) {
                        Image(systemName: "music.note")
                            .font(.system(size: 12, weight: .bold))
                        Text("\(post.username) · Original audio")
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .allowsHitTesting(false)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open wave by \(post.username)")
    }

    private func storyCard(_ group: [WhisperStoryRow]) -> some View {
        let story = group.last ?? group.first
        return Button {
            Haptics.tap()
            handoff { center.openStories = WhisperPeekStoryGroup(stories: group) }
        } label: {
            ZStack {
                Color.black
                if let story {
                    if story.isVideo, let clip = story.video_url, let url = URL(string: clip) {
                        WhisperStoryViewerVideo(url: url, paused: false, muted: true, onDuration: { _ in })
                            .allowsHitTesting(false)
                    } else if let url = URL(string: story.image_url) {
                        WhisperCachedAsyncImage(url: url) { phase in
                            if case .success(let img) = phase {
                                img.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Color(white: 0.12)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                }
                LinearGradient(colors: [.black.opacity(0.5), .clear, .clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    if group.count > 1 {
                        HStack(spacing: 3) {
                            ForEach(group.indices, id: \.self) { _ in
                                Capsule().fill(.white.opacity(0.75)).frame(height: 2)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                    }
                    HStack(spacing: 10) {
                        WhisperAvatar(username: story?.username ?? "", size: 32, ring: false)
                        Text(story?.username ?? "")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let story {
                            Text(whisperStoryTimeAgo(story.created_at))
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer(minLength: 0)
                        if let story, favorites.isFavorite(story.user_id) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(WhisperBrandGradient.diagonal)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, group.count > 1 ? 10 : 14)
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 11, weight: .bold))
                        Text("Peeking — they won't see a view")
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.35), in: Capsule())
                    .padding(.bottom, 14)
                }
                .allowsHitTesting(false)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open story")
    }

    // MARK: Menu

    private var menuRows: [Row] {
        switch item {
        case .wave(let post):
            let pid = post.id.uuidString.lowercased()
            let reposted = WhisperRepostService.shared.isReposted(pid)
            return [
                Row(id: "like", icon: liked ? "heart.fill" : "heart", title: liked ? "Liked" : "Like", tint: liked ? WhisperBrandGradient.accent : nil) {
                    toggleLike(post)
                },
                Row(id: "repost", icon: "arrow.2.squarepath", title: reposted ? "Reposted" : "Repost", tint: reposted ? Color(red: 0.18, green: 0.78, blue: 0.32) : nil) {
                    Task { _ = await WhisperRepostService.shared.toggle(postID: pid) }
                    Haptics.success()
                    release()
                },
                Row(id: "share", icon: "paperplane", title: "Share") {
                    handoff { center.sharePost = post }
                },
                Row(id: "profile", icon: "person.circle", title: "View profile") {
                    openProfile(username: post.username)
                },
                Row(id: "report", icon: "exclamationmark.bubble", title: "Report", destructive: true) {
                    let row = WhisperBackendService.shared.posts.first { $0.id.lowercased() == pid }
                    let target = WhisperPeekReportTarget(
                        kind: .reel,
                        targetID: pid,
                        targetUserID: row?.user_id ?? "",
                        targetUsername: post.username
                    )
                    handoff { center.report = target }
                },
            ]
        case .story(let group):
            guard let story = group.last ?? group.first else { return [] }
            let fav = favorites.isFavorite(story.user_id)
            return [
                Row(id: "fav", icon: fav ? "star.fill" : "star", title: fav ? "Remove from favorites" : "Add to favorites", tint: fav ? WhisperBrandGradient.accent : nil) {
                    Haptics.success()
                    withAnimation(.spring(response: 0.3)) { favorites.toggle(story.user_id) }
                },
                Row(id: "view", icon: "play.circle", title: "View story") {
                    handoff { center.openStories = WhisperPeekStoryGroup(stories: group) }
                },
                Row(id: "profile", icon: "person.circle", title: "View profile") {
                    openProfile(username: story.username)
                },
                Row(id: "message", icon: "bubble.left", title: "Send message") {
                    let target = WhisperPeekDMTarget(userID: story.user_id, username: story.username)
                    handoff { center.openDM = target }
                },
                Row(id: "report", icon: "exclamationmark.bubble", title: "Report", destructive: true) {
                    let target = WhisperPeekReportTarget(
                        kind: .story,
                        targetID: story.id,
                        targetUserID: story.user_id,
                        targetUsername: story.username
                    )
                    handoff { center.report = target }
                },
            ]
        }
    }

    private var menuFill: Color {
        colorScheme == .dark ? Color(white: 0.13) : WhisperTheme.card(colorScheme)
    }

    private func menu(_ rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                Button {
                    if row.destructive { Haptics.warning() } else { Haptics.tap() }
                    row.action()
                } label: {
                    HStack(spacing: 14) {
                        Group {
                            if row.id == "repost" { WhisperRoundedGlyph(kind: .repost, size: 22) }
                            else { Image(systemName: row.icon).font(.system(size: 20, weight: .regular)) }
                        }
                        .frame(width: 26)
                        Text(row.title)
                            .font(.system(size: 16, weight: .regular))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if resolvingUser && row.id == "profile" {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .foregroundStyle(
                        row.destructive
                            ? Color(red: 0.93, green: 0.22, blue: 0.22)
                            : (row.tint ?? WhisperTheme.ink(colorScheme))
                    )
                    .padding(.horizontal, 18)
                    .frame(height: menuRow)
                    .contentShape(.rect)
                }
                .buttonStyle(WhisperMenuPressStyle())
            }
        }
        .padding(.vertical, 6)
        .background(menuFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.12), radius: 20, y: 8)
    }

    // MARK: Actions

    private func toggleLike(_ post: WhisperPost) {
        let was = liked
        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
            liked.toggle()
            likes += liked ? 1 : -1
        }
        Haptics.soft()
        Task {
            let now = await WhisperBackendService.shared.toggleLike(postID: post.id.uuidString.lowercased())
            if now != liked {
                await MainActor.run {
                    liked = was
                    likes += was ? 1 : -1
                }
            }
        }
    }

    private func openProfile(username: String) {
        guard !resolvingUser else { return }
        resolvingUser = true
        Task {
            let row = await WhisperUserService.shared.fetchByUsername(username)
            await MainActor.run {
                resolvingUser = false
                if let row {
                    handoff { center.openUser = row }
                } else {
                    release()
                }
            }
        }
    }

    /// Let the peek go, then hand the presentation to the host once the
    /// overlay has faded.
    private func handoff(_ present: @escaping () -> Void) {
        release()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { present() }
    }

    private func release() {
        guard !releasing else { return }
        releasing = true
        shown = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { center.dismiss() }
    }

    private func compact(_ n: Int) -> String {
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
