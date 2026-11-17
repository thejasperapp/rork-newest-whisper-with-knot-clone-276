import SwiftUI
import UIKit
import Supabase

// MARK: - Time-spent tracker

/// On-device "time spent" — foreground seconds per calendar day, per account,
/// in UserDefaults. Nothing leaves the phone. Started once at launch; the
/// Your-activity screen reads the last seven days.
@MainActor
final class WhisperUsageTracker {
    static let shared = WhisperUsageTracker()

    private var activeSince: Date?
    private var started: Bool = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        activeSince = UIApplication.shared.applicationState == .active ? Date() : nil
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.activeSince = Date() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.flush() }
        }
    }

    /// Writes the open session into today's bucket.
    func flush() {
        guard let since = activeSince else { return }
        let seconds = Date().timeIntervalSince(since)
        activeSince = UIApplication.shared.applicationState == .active ? Date() : nil
        guard seconds > 0.5 else { return }
        let key = Self.key(for: Date())
        let current = UserDefaults.standard.double(forKey: key)
        UserDefaults.standard.set(current + seconds, forKey: key)
    }

    /// Seconds spent on each of the last `days` days (oldest first), today
    /// including the still-open session.
    func recentDays(_ days: Int = 7) -> [(day: Date, seconds: Double)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var out: [(Date, Double)] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            var seconds = UserDefaults.standard.double(forKey: Self.key(for: day))
            if offset == 0, let since = activeSince {
                seconds += Date().timeIntervalSince(since)
            }
            out.append((day, seconds))
        }
        return out
    }

    private static func key(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "whisper.usage.v1.\(AccountStorage.currentUserID).\(f.string(from: date))"
    }
}

// MARK: - Your activity

/// Settings → YOUR ACTIVITY — Instagram's hub, built on Whisper's real
/// tables: Interactions (likes · comments · reposts · saved), Content you
/// shared (whisps · waves · stories · highlights), Time spent (on-device),
/// Account history, and Download your information (a JSON export). Every
/// count is a live head-count query; nothing is estimated.
struct WhisperYourActivityView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var backend = WhisperBackendService.shared
    @State private var users = WhisperUserService.shared
    @State private var stories = WhisperStoryService.shared
    @State private var highlights = WhisperStoryHighlightsService.shared
    @State private var auth = AuthenticationService.shared

    @State private var likes: Int?
    @State private var comments: Int?
    @State private var reposts: Int?
    @State private var saved: Int?
    @State private var whisps: Int?
    @State private var waves: Int?
    @State private var storiesCount: Int?
    @State private var highlightsCount: Int?
    @State private var exportURL: WhisperExportFile?
    @State private var exporting: Bool = false
    @State private var usage: [(day: Date, seconds: Double)] = []

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }
    private var client: SupabaseClient { SupabaseService.shared.client }
    private var uid: String { AccountStorage.currentUserID }

    private var username: String {
        users.me?.username ?? auth.currentUser.username ?? "you"
    }

    var body: some View {
        ZStack {
            WhisperTheme.surface(colorScheme).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    timeSpentCard
                    group("Interactions", footer: "Review and manage the likes, comments, and reposts you've left.") {
                        NavigationLink(value: ActivityRoute.likes) {
                            row(icon: "heart", title: "Likes", detail: "Posts you've liked", count: likes)
                        }
                        divider
                        NavigationLink(value: ActivityRoute.comments) {
                            row(icon: "bubble.right", title: "Comments", detail: "Replies you've left on posts", count: comments)
                        }
                        divider
                        NavigationLink(value: ActivityRoute.reposts) {
                            row(icon: "arrow.2.squarepath", title: "Reposts", detail: "Posts you've shared to your profile", count: reposts)
                        }
                        divider
                        NavigationLink(value: ActivityRoute.saved) {
                            row(icon: "bookmark", title: "Saved", detail: "Posts you've bookmarked", count: saved)
                        }
                    }
                    group("Content you shared", footer: "Everything you've published, by format.") {
                        row(icon: "text.bubble", title: "Whisps", detail: "Text and media posts", count: whisps)
                        divider
                        row(icon: "play.rectangle", title: "Waves", detail: "Short videos on the Waves tab", count: waves)
                        divider
                        row(icon: "circle.dashed", title: "Stories", detail: "Live right now (stories last 24 hours)", count: storiesCount)
                        divider
                        row(icon: "sparkles.rectangle.stack", title: "Highlights", detail: "Saved story collections on your profile", count: highlightsCount)
                    }
                    group("Account history", footer: nil) {
                        infoRow(icon: "clock.arrow.circlepath", title: "Member since", detail: memberSince)
                        divider
                        infoRow(icon: "at", title: "Username", detail: username)
                        divider
                        infoRow(icon: "person.text.rectangle", title: "Account", detail: WhisperAccountAccess.tierLabel(username: username))
                        divider
                        infoRow(icon: "checkmark.seal", title: "Verification", detail: WhisperVerifiedPerks.isVerified(username: username) ? "Verified creator" : "Not verified")
                    }
                    group("Download your information", footer: "A JSON file of your profile and everything you've posted — generated on this phone, nothing is sent anywhere.") {
                        Button {
                            Haptics.tap()
                            Task { await exportInformation() }
                        } label: {
                            HStack(spacing: 12) {
                                iconChip("square.and.arrow.down")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exporting ? "Preparing your file…" : "Request a download")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(ink)
                                    Text("Profile, posts, and captions as JSON")
                                        .font(.caption)
                                        .foregroundStyle(muted)
                                }
                                Spacer()
                                if exporting {
                                    ProgressView().controlSize(.small).tint(muted)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(muted)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(exporting)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Your activity")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ActivityRoute.self) { route in
            WhisperActivityListView(route: route)
        }
        .task { await load() }
        .sheet(item: $exportURL) { file in
            WhisperShareLinkSheet(url: file.url)
        }
    }

    enum ActivityRoute: Hashable {
        case likes, comments, reposts, saved
    }

    // MARK: - Time spent

    private var timeSpentCard: some View {
        let total = usage.reduce(0) { $0 + $1.seconds }
        let today = usage.last?.seconds ?? 0
        let average = usage.isEmpty ? 0 : total / Double(usage.count)
        let peak = max(1, usage.map { $0.seconds }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TIME SPENT")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.1)
                        .foregroundStyle(muted)
                    Text(Self.duration(today))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                        .contentTransition(.numericText())
                    Text("today on Whisper")
                        .font(.caption)
                        .foregroundStyle(muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Self.duration(average))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                    Text("daily average")
                        .font(.caption2)
                        .foregroundStyle(muted)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(usage.enumerated()), id: \.offset) { idx, point in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(idx == usage.count - 1 ? AnyShapeStyle(WhisperBrandGradient.vertical) : AnyShapeStyle(WhisperTheme.hairline(colorScheme)))
                            .frame(height: max(4, 72 * CGFloat(point.seconds / peak)))
                            .frame(maxHeight: 72, alignment: .bottom)
                        Text(point.day.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(idx == usage.count - 1 ? ink : muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 92, alignment: .bottom)
            Text("Counted on this phone while Whisper is open. Never shared.")
                .font(.caption2)
                .foregroundStyle(muted)
        }
        .padding(16)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
    }

    // MARK: - Rows

    private func group<Content: View>(_ title: String, footer: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.9)
                .foregroundStyle(muted)
                .padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16).strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
                }
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(muted)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var divider: some View {
        Divider().background(WhisperTheme.hairline(colorScheme)).padding(.leading, 60)
    }

    private func iconChip(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(ink.opacity(0.8))
            .frame(width: 34, height: 34)
            .background(WhisperTheme.hairline(colorScheme).opacity(0.6), in: .rect(cornerRadius: 10))
    }

    private func row(icon: String, title: String, detail: String, count: Int?) -> some View {
        HStack(spacing: 12) {
            iconChip(icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let count {
                Text(Self.compact(count))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(WhisperTheme.hairline(colorScheme).opacity(0.7), in: Capsule())
                    .contentTransition(.numericText())
            } else {
                ProgressView().controlSize(.mini).tint(muted)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(muted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(.rect)
    }

    private func infoRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            iconChip(icon)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ink)
            Spacer(minLength: 0)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var memberSince: String {
        if let d = client.auth.currentUser?.createdAt {
            return WhisperAnalyticsDates.monthYear(d)
        }
        if let d = WhisperAnalyticsDates.parse(users.me?.onboarded_at) {
            return WhisperAnalyticsDates.monthYear(d)
        }
        return WhisperAnalyticsDates.monthYear(auth.currentUser.joinDate)
    }

    // MARK: - Loading

    private func load() async {
        WhisperUsageTracker.shared.start()
        usage = WhisperUsageTracker.shared.recentDays(7)
        guard !uid.isEmpty, uid != "guest", !uid.hasPrefix("local_") else {
            likes = 0; comments = 0; reposts = 0; saved = 0
            whisps = 0; waves = 0; storiesCount = 0; highlightsCount = 0
            return
        }
        async let likesCount = headCount(table: "whisper_post_likes", column: "post_id")
        async let commentsCount = headCount(table: "whisper_post_comments", column: "id")
        async let repostsCount = headCount(table: "whisper_reposts", column: "post_id")
        async let savedCount = headCount(table: "whisper_bookmarks", column: "post_id")
        async let wavesCount = headCount(table: "whisper_posts", column: "id", extra: ("is_reel", true))
        async let postsCount = headCount(table: "whisper_posts", column: "id")
        let (l, c, r, s, w, p) = await (likesCount, commentsCount, repostsCount, savedCount, wavesCount, postsCount)
        likes = l
        comments = c
        reposts = r
        saved = s
        waves = w
        whisps = max(0, (p ?? 0) - (w ?? 0))
        await stories.fetch()
        storiesCount = stories.myStories().count
        await highlights.refresh(forUserID: uid)
        highlightsCount = highlights.albums(forUserID: uid).count
    }

    private func headCount(table: String, column: String, extra: (String, Bool)? = nil) async -> Int? {
        var query = client.from(table).select(column, head: true, count: .exact).eq("user_id", value: uid)
        if let extra {
            query = query.eq(extra.0, value: extra.1)
        }
        let response = try? await query.execute()
        return response?.count ?? 0
    }

    // MARK: - Export

    private func exportInformation() async {
        exporting = true
        defer { exporting = false }
        await backend.fetchMyPosts()
        let profile = users.me
        let posts = backend.myPosts.map { row -> [String: Any] in
            var dict: [String: Any] = [
                "id": row.id,
                "kind": row.kind ?? "text",
                "caption": WhisperPostMeta.strip(from: row.caption ?? ""),
                "is_wave": row.is_reel ?? false,
                "likes": row.likes_count ?? 0,
                "comments": row.comments_count ?? 0
            ]
            if let created = row.created_at { dict["created_at"] = created }
            if let media = row.media_urls, !media.isEmpty { dict["media_urls"] = media }
            return dict
        }
        var root: [String: Any] = [
            "exported_at": ISO8601DateFormatter().string(from: Date()),
            "username": username,
            "posts": posts
        ]
        if let profile {
            root["profile"] = [
                "display_name": profile.display_name ?? "",
                "bio": profile.bio ?? "",
                "interests": profile.interests ?? [],
                "account_type": profile.account_type ?? "personal",
                "professional_category": profile.professional_category ?? "",
                "is_private": profile.is_private ?? false,
                "onboarded_at": profile.onboarded_at ?? ""
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("whisper-\(username)-export.json")
        do {
            try data.write(to: url, options: .atomic)
            exportURL = WhisperExportFile(url: url)
        } catch {
            print("[YourActivity] export failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Formatting

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

/// Identifiable wrapper so the export file can drive a `.sheet(item:)`.
struct WhisperExportFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Minimal system share sheet for the export file.
private struct WhisperShareLinkSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Interaction lists

/// The drill-down lists behind Interactions — posts you liked / reposted /
/// saved render as real post cards; comments render as your reply rows.
struct WhisperActivityListView: View {
    let route: WhisperYourActivityView.ActivityRoute
    @Environment(\.colorScheme) private var colorScheme
    @State private var rows: [WhisperPostRow] = []
    @State private var comments: [WhisperCommentRow] = []
    @State private var loading: Bool = true

    private var client: SupabaseClient { SupabaseService.shared.client }
    private var uid: String { AccountStorage.currentUserID }

    private var title: String {
        switch route {
        case .likes: return "Likes"
        case .comments: return "Comments"
        case .reposts: return "Reposts"
        case .saved: return "Saved"
        }
    }

    var body: some View {
        ZStack {
            WhisperTheme.surface(colorScheme).ignoresSafeArea()
            ScrollView {
                if loading {
                    ProgressView()
                        .tint(WhisperTheme.ink(colorScheme))
                        .padding(.top, 40)
                } else if route == .comments {
                    commentsList
                } else if rows.isEmpty {
                    WhisperEmptyState(
                        icon: emptyIcon,
                        title: "Nothing here yet",
                        message: emptyMessage
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 32)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                            WhisperPostCard(post: WhisperRootView.mapRowToPost(row))
                            if idx < rows.count - 1 {
                                Divider().background(WhisperTheme.hairline(colorScheme))
                            }
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var emptyIcon: String {
        switch route {
        case .likes: return "heart"
        case .comments: return "bubble.right"
        case .reposts: return "arrow.2.squarepath"
        case .saved: return "bookmark"
        }
    }

    private var emptyMessage: String {
        switch route {
        case .likes: return "Posts you like will show up here."
        case .comments: return "Replies you leave on posts will show up here."
        case .reposts: return "Posts you repost will show up here."
        case .saved: return "Posts you save will show up here."
        }
    }

    @ViewBuilder
    private var commentsList: some View {
        if comments.isEmpty {
            WhisperEmptyState(icon: "bubble.right", title: "Nothing here yet", message: emptyMessage)
                .padding(.horizontal, 16)
                .padding(.top, 32)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(comments) { c in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(c.username)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme))
                            Text(whisperStoryTimeAgo(c.created_at))
                                .font(.caption)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                            Spacer()
                            if let likes = c.likes_count, likes > 0 {
                                Label("\(likes)", systemImage: "heart.fill")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                        }
                        Text(c.body)
                            .font(.subheadline)
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    Divider().background(WhisperTheme.hairline(colorScheme))
                }
            }
            .padding(.bottom, 32)
        }
    }

    private func load() async {
        defer { loading = false }
        guard !uid.isEmpty, uid != "guest", !uid.hasPrefix("local_") else { return }
        switch route {
        case .comments:
            let fetched: [WhisperCommentRow]? = try? await client
                .from("whisper_post_comments")
                .select()
                .eq("user_id", value: uid)
                .order("created_at", ascending: false)
                .limit(200)
                .execute()
                .value
            comments = fetched ?? []
        case .likes:
            rows = await postsFromJoin(table: "whisper_post_likes")
        case .reposts:
            rows = await WhisperRepostService.shared.fetchRepostedPosts()
        case .saved:
            rows = await postsFromJoin(table: "whisper_bookmarks")
        }
    }

    private nonisolated struct IDRow: Decodable, Sendable {
        let post_id: String
    }

    /// Reads my post ids from a join table, then the posts themselves.
    private func postsFromJoin(table: String) async -> [WhisperPostRow] {
        let ids: [IDRow]? = try? await client
            .from(table)
            .select("post_id")
            .eq("user_id", value: uid)
            .order("created_at", ascending: false)
            .limit(150)
            .execute()
            .value
        let postIDs = (ids ?? []).map { $0.post_id }
        guard !postIDs.isEmpty else { return [] }
        let posts: [WhisperPostRow]? = try? await client
            .from("whisper_posts")
            .select()
            .in("id", values: postIDs)
            .execute()
            .value
        let order = Dictionary(uniqueKeysWithValues: postIDs.enumerated().map { ($1, $0) })
        return (posts ?? []).sorted { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
    }
}
