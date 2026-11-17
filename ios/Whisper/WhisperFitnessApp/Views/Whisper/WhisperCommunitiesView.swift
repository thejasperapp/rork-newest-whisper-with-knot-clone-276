import SwiftUI
import Combine

/// Communities — Threads-style topic hubs. Each community is a curated
/// bucket of posts (filtered by hashtag/keyword in the caption) tied to
/// one of the interests users pick during onboarding. Tapping a card
/// pushes `WhisperCommunityDetailView` which renders the filtered feed.
///
/// The catalog is intentionally generated locally (no schema change) so
/// any post that mentions a topic via hashtag or keyword automatically
/// lands in the matching community.
struct WhisperCommunitiesView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var backend = WhisperBackendService.shared
    @State private var users = WhisperUserService.shared
    @State private var query: String = ""

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var allCommunities: [WhisperCommunity] { WhisperCommunity.catalog }

    private var filtered: [WhisperCommunity] {
        guard !trimmedQuery.isEmpty else { return allCommunities }
        return allCommunities.filter {
            $0.name.lowercased().contains(trimmedQuery)
            || $0.tagline.lowercased().contains(trimmedQuery)
            || $0.keywords.contains(where: { $0.lowercased().contains(trimmedQuery) })
        }
    }

    /// Communities the current user explicitly chose during onboarding.
    private var joined: [WhisperCommunity] {
        let interests = Set((users.displayProfile?.interests ?? []).map { $0.lowercased() })
        guard !interests.isEmpty else { return [] }
        return allCommunities.filter { interests.contains($0.name.lowercased()) }
    }

    /// Everything that isn't already in the user's joined list — surfaced
    /// as "Discover" below the joined strip.
    private var discover: [WhisperCommunity] {
        let joinedNames = Set(joined.map { $0.name })
        return filtered.filter { !joinedNames.contains($0.name) }
    }

    var body: some View {
        ZStack {
            WhisperTheme.surface(colorScheme).ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 22, pinnedViews: []) {
                    searchField
                    if !joined.isEmpty && trimmedQuery.isEmpty {
                        joinedSection
                    }
                    if trimmedQuery.isEmpty {
                        WhisperNearbyCommunitiesSection()
                    }
                    discoverSection
                    Color.clear.frame(height: 112)
                }
                .padding(.top, 8)
            }
            .whisperRefreshable {
                await backend.fetchPosts()
            }
        }
        .navigationTitle("Communities")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: WhisperCommunity.self) { c in
            WhisperCommunityDetailView(community: c)
        }
        .overlay(alignment: .bottom) {
            // Jasper's community matchmaker — the same meeting-style dock as
            // the inbox/studio, PINNED right above the nav bar: when the tab
            // bar hides on scroll the padding compensates so the pill never
            // drops to the screen edge or slides under the bar.
            JasperAnalysisDock(
                pillLabel: "Knot's picks",
                boxTitle: "Community matchmaker",
                focus: "You are Whisper's community matchmaker. From CANDIDATES (and NEARBY when present) pick the 2-3 communities this user would genuinely enjoy — each with a one-line reason grounded in their interests, joined list, or recent captions. Mention a NEARBY hub when it fits (that's a real place by them). End with one sentence on what they should post there first. Never invent communities that aren't listed.",
                buildContext: { communitiesAnalysisContext() },
                emptyText: "Join a community or post something first — then I'll have signal to match you."
            )
            .whisperPinnedAboveTabBar()
        }
        .task { await backend.fetchPostsIfStale() }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            TextField("Search communities", text: $query)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    Haptics.tap()
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
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Sections

    private var joinedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Your communities")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(joined) { c in
                        NavigationLink(value: c) {
                            joinedCard(c)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
        }
    }

    private var discoverSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(trimmedQuery.isEmpty ? "Discover" : "Results")
            if discover.isEmpty {
                emptyState
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 10) {
                    ForEach(discover) { c in
                        NavigationLink(value: c) {
                            discoverRow(c)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            WhisperMeetDoodle(symbol: "person.3", height: 120)
            Text("No communities match \"\(trimmedQuery)\"")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: - Cards

    private func joinedCard(_ c: WhisperCommunity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                LinearGradient(
                    colors: c.gradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: c.symbol)
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 178, height: 110)
            .clipShape(.rect(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 2) {
                Text(c.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                Text("\(postCount(for: c)) posts")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
        }
        .frame(width: 178)
    }

    private func discoverRow(_ c: WhisperCommunity) -> some View {
        HStack(spacing: 14) {
            ZStack {
                LinearGradient(
                    colors: c.gradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: c.symbol)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 60, height: 60)
            .clipShape(.rect(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(c.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if c.requiresJasperLink {
                        Text(JasperConnectClient.shared.connection != nil ? "👻 LINKED" : "LINK TO VIEW")
                            .font(.system(size: 8, weight: .black))
                            .tracking(0.7)
                            .foregroundStyle(Color(red: 0.92, green: 0.42, blue: 0.12))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(Color(red: 0.98, green: 0.45, blue: 0.09).opacity(0.10), in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(Color(red: 0.98, green: 0.45, blue: 0.09).opacity(0.35), lineWidth: 1)
                            }
                    }
                }
                // One line + ellipsis — taglines (especially location-tagged
                // hubs) must never wrap onto a second line in the list.
                Text(c.tagline)
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(postCount(for: c)) posts")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
        .padding(12)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    c.requiresJasperLink
                        ? Color(red: 0.98, green: 0.45, blue: 0.09).opacity(0.40)
                        : WhisperTheme.hairline(colorScheme),
                    lineWidth: 1
                )
        }
        // The Jasper Circle row wears the ember glow in the list — white
        // card, warm aura — so the linked lounge reads special at a glance.
        .shadow(
            color: c.requiresJasperLink
                ? Color(red: 0.98, green: 0.45, blue: 0.09).opacity(0.16)
                : .clear,
            radius: 12, y: 5
        )
    }

    private func postCount(for c: WhisperCommunity) -> Int {
        backend.posts.reduce(0) { acc, row in
            acc + (c.matches(row: row) ? 1 : 0)
        }
    }

    /// Live context for the matchmaker dock — interests, joined + nearby
    /// hubs, candidate list, and caption signal from me + the feed.
    private func communitiesAnalysisContext() -> String? {
        var lines: [String] = []
        let interests = users.me?.interests ?? []
        if !interests.isEmpty {
            lines.append("MY INTERESTS: " + interests.joined(separator: ", "))
        }
        let joinedNames = joined.map { $0.name }
        if !joinedNames.isEmpty {
            lines.append("JOINED: " + joinedNames.joined(separator: ", "))
        }
        let nearby = WhisperNearbyCommunitiesService.shared.suggestions
        if !nearby.isEmpty {
            let near = nearby.map { c -> String in
                if let origin = c.origin { return "\(c.name) (\(origin))" }
                return c.name
            }
            lines.append("NEARBY (geo-detected): " + near.joined(separator: ", "))
        }
        let candidates = discover.prefix(18).map { "\($0.name) — \($0.tagline)" }
        if !candidates.isEmpty {
            lines.append("CANDIDATES:\n" + candidates.joined(separator: "\n"))
        }
        let me = AccountStorage.currentUserID.lowercased()
        let mine = backend.posts
            .filter { $0.user_id.lowercased() == me }
            .prefix(10)
            .map { String($0.caption.prefix(90)) }
        if !mine.isEmpty {
            lines.append("MY RECENT CAPTIONS:\n" + mine.joined(separator: "\n"))
        }
        let feed = backend.posts.prefix(14).map { String($0.caption.prefix(90)) }
        if !feed.isEmpty {
            lines.append("FEED RIGHT NOW:\n" + feed.joined(separator: "\n"))
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n\n")
    }
}

// MARK: - Community detail

/// Renders the feed filtered to one community. Reuses the existing
/// `WhisperPostCard` so threading, comments, and actions behave the same
/// as the main feed.
/// The say-hi DM target under a dating post (sheet item).
fileprivate struct SayHiUser: Identifiable {
    let userID: String
    let username: String
    var id: String { userID }
}

struct WhisperCommunityDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var backend = WhisperBackendService.shared
    @State private var users = WhisperUserService.shared
    @State private var presentComposer: Bool = false
    @State private var sortMode: SortMode = .top
    @State private var shareItem: ShareItem?
    @State private var shareInMessages = false
    @State private var muted: Bool = false
    @State private var working: Bool = false
    @State private var membershipError: String?
    @State private var showInfo: Bool = false
    @State private var didFirstFetch: Bool = false
    /// Dating hub — icebreaker roulette override, safety card expansion,
    /// the composer prefill for "Answer it", and the say-hi DM target.
    @State private var shuffledPrompt: String? = nil
    /// 30s ticker — keeps the hourly icebreaker + its countdown live.
    @State private var icebreakerTick: Date = Date()
    @State private var showDatingCardEditor: Bool = false
    @State private var startingSpeedDate: Bool = false
    @State private var speedDateLinkCopied: Bool = false
    /// The structured icebreaker ANSWER sheet (private by default).
    @State private var answerPrompt: DatingAnswerPrompt? = nil
    /// Bumps when a private answer saves so the For-you sort recomputes.
    @State private var answersTick: Int = 0
    /// Q&A share queued from the answer sheet — the composer opens after
    /// the sheet fully dismisses (presenting both at once drops the cover).
    @State private var pendingSharePrefill: String? = nil
    /// The custom speed-date LOBBY — the starter's join screen.
    @State private var speedDateLobby: SpeedDateLobbyItem? = nil
    /// Blind dating — the finder behind the header's video circle, the
    /// preferences sheet, and the nearby set that filters the hub by radius.
    @State private var showBlindDateFinder: Bool = false
    @State private var showDatingPrefs: Bool = false
    /// The community's tool drawer — every dating special in one sheet.
    @State private var showDatingTools: Bool = false
    @State private var datingPrefs: WhisperDatingPrefs = WhisperDatingPrefsStore.load()
    @State private var nearby: [WhisperDatingNearbyPerson] = []
    @State private var nearbyOnly: Bool = WhisperDatingPrefsStore.nearbyOnly
    @State private var blindQueueCount: Int = 0
    @State private var safetyExpanded: Bool = false
    @State private var composerPrefill: String = ""
    @State private var sayHiUser: SayHiUser? = nil
    @State private var showJasperSettings: Bool = false
    /// "Sorry — VIP only 👻" gate when joining Jasper Circle unlinked.
    @State private var showVIPGate: Bool = false
    let community: WhisperCommunity

    /// Jasper Circle: viewable only when the Jasper account link exists.
    private var jasperLocked: Bool {
        community.requiresJasperLink && JasperConnectClient.shared.connection == nil
    }

    private struct ShareItem: Identifiable {
        let id = UUID()
        let text: String
    }

    private struct DatingAnswerPrompt: Identifiable {
        let id = UUID()
        let text: String
    }

    private struct SpeedDateLobbyItem: Identifiable {
        let row: WhisperMeetingRow
        let code: String
        var id: String { row.id }
    }

    enum SortMode: String, CaseIterable, Identifiable {
        case forYou = "For you"
        case top = "Top posts"
        case newest = "Newest"
        case oldest = "Oldest"
        var id: String { rawValue }
    }

    /// Dating gets the similarity sort; every other hub keeps the classic three.
    private var availableSortModes: [SortMode] {
        community.id == "dating" ? SortMode.allCases : SortMode.allCases.filter { $0 != .forYou }
    }

    private var isJoined: Bool {
        let interests = Set((users.me?.interests ?? []).map { $0.lowercased() })
        return interests.contains(community.name.lowercased())
    }

    /// Real numbers derived from the live feed: members = unique authors
    /// who have posted to this community at least once; posts = total
    /// matching posts in the feed. No more synthetic 267K placeholders.
    private var displayMemberCount: String {
        WhisperCommunityDetailView.compact(memberCount)
    }
    private var memberCount: Int {
        var seen = Set<String>()
        for row in backend.posts where community.matches(row: row) {
            seen.insert(row.user_id.lowercased())
        }
        return seen.count
    }
    private var postCount: Int {
        backend.posts.reduce(0) { acc, row in
            community.matches(row: row) ? acc + 1 : acc
        }
    }

    /// Nearby people keyed by lowercased user id (radius filter + score boost).
    private var nearbyByID: [String: WhisperDatingNearbyPerson] {
        Dictionary(nearby.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private var matching: [WhisperPost] {
        var authors: [UUID: String] = [:]
        let me = AccountStorage.currentUserID.lowercased()
        let mapped: [WhisperPost] = backend.posts.compactMap { row in
            guard community.matches(row: row) else { return nil }
            let urls: [URL] = (row.media_urls ?? []).compactMap { URL(string: $0) }
            let postID = UUID(uuidString: row.id) ?? UUID()
            authors[postID] = row.user_id.lowercased()
            return WhisperPost(
                id: postID,
                username: WhisperBackendService.shared.resolvedAuthorUsername(rowUsername: row.username, rowUserID: row.user_id),
                timeAgo: WhisperPost.relativeTime(from: row.created_at),
                kind: WhisperPostKind(rawValue: row.kind ?? "") ?? .photo,
                caption: row.caption,
                symbol: row.symbol ?? WhisperPostKind(rawValue: row.kind ?? "")?.icon ?? "sparkles",
                accent: WhisperPost.color(fromHex: row.accent_hex) ?? Color(red: 0.5, green: 0.5, blue: 0.5),
                mediaURLs: urls,
                likes: row.likes_count ?? 0,
                comments: row.comments_count ?? 0,
                liked: backend.myLikedPostIDs.contains(row.id),
                isReel: row.is_reel ?? false,
                createdAt: WhisperBackendService.parseISO(row.created_at),
                communityID: row.community_id,
                communityName: row.community_name
            )
        }
        // Dating: the RADIUS filter — with a saved location and "Nearby only"
        // on, people outside my radius (or without a location) drop out.
        let pool: [WhisperPost]
        if community.id == "dating", nearbyOnly, datingPrefs.hasLocation, !nearby.isEmpty {
            let allowed = Set(nearby.map { $0.id })
            pool = mapped.filter { post in
                guard let uid = authors[post.id] else { return true }
                return uid == me || allowed.contains(uid)
            }
        } else {
            pool = mapped
        }
        switch sortMode {
        case .forYou:
            // Dating's match sort (engine v2) — themes + literal overlap +
            // same-prompt bonus against ALL my recent answers, boosted by
            // distance inside my radius and a shared intent. Newest until I
            // have an answer of my own to compare.
            let mine = myDatingAnswers
            guard !mine.isEmpty else {
                return pool.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            }
            let near = nearbyByID
            let scored = pool.map { post in
                (post, WhisperDatingMatch.personScore(
                    myAnswers: mine,
                    caption: post.caption,
                    nearby: authors[post.id].flatMap { near[$0] },
                    prefs: datingPrefs
                ))
            }
            return scored.sorted { l, r in
                if abs(l.1 - r.1) > 0.0001 { return l.1 > r.1 }
                return (l.0.createdAt ?? .distantPast) > (r.0.createdAt ?? .distantPast)
            }.map { $0.0 }
        case .top:
            return pool.sorted { ($0.likes + $0.comments) > ($1.likes + $1.comments) }
        case .newest:
            return pool.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        case .oldest:
            return pool.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        }
    }

    /// My dating-hub answers, newest first (up to 8) — the anchors for
    /// "For you". Every answer I give is another signal: each person is
    /// scored by their BEST resonance with ANY of my answers, so the
    /// hourly prompts genuinely dial matches in over time.
    private var myDatingAnswers: [WhisperDatingMatch.Answer] {
        let me = AccountStorage.currentUserID.lowercased()
        guard !me.isEmpty else { return [] }
        let mine = backend.posts
            .filter { $0.user_id.lowercased() == me && community.matches(row: $0) }
            .sorted {
                (WhisperBackendService.parseISO($0.created_at) ?? .distantPast) >
                (WhisperBackendService.parseISO($1.created_at) ?? .distantPast)
            }
        _ = answersTick
        // Private answers lead — answering is private by default, and the
        // sort reads them straight off the device (no post required).
        var answers: [WhisperDatingMatch.Answer] = WhisperDatingAnswers.all().map {
            WhisperDatingMatch.Answer(prompt: $0.prompt, text: $0.answer)
        }
        for row in mine {
            guard answers.count < 8 else { break }
            let parsed = WhisperDatingMatch.answer(from: row.caption)
            if !parsed.text.isEmpty { answers.append(parsed) }
        }
        return Array(answers.prefix(8))
    }

    /// Newest answer — what the matchmaker context leads with.
    private var myDatingAnswer: WhisperDatingMatch.Answer? { myDatingAnswers.first }

    var body: some View {
        ZStack {
            WhisperTheme.surface(colorScheme).ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    threadsHeader
                    if jasperLocked {
                        jasperLockedCard
                    } else {
                    if community.id == "dating" {
                        datingToolsBar
                        datingPrefsRow
                        datingIcebreakerCard
                        datingSafetyCard
                    }
                    membersRow
                    if let membershipError { Text(membershipError).font(.footnote).foregroundStyle(.red).padding(.horizontal, 16) }
                    Divider().background(WhisperTheme.hairline(colorScheme))
                        .padding(.top, 14)
                    postPill
                    Divider().background(WhisperTheme.hairline(colorScheme))
                    sortRow
                    if community.id == "dating", sortMode == .forYou {
                        datingSortChip
                    }
                    if matching.isEmpty {
                        if backend.posts.isEmpty && !didFirstFetch {
                            // Cold cache — the shimmer skeletons, not a blank
                            // "no posts" flash that lies while we fetch.
                            WhisperPostSkeletonList(count: 2)
                        } else {
                            emptyState
                        }
                    } else {
                        ForEach(matching) { post in
                            if community.requiresJasperLink {
                                // White post, Jasper glow — the ember aura wraps
                                // each post inside the Circle without repainting
                                // the card itself.
                                WhisperPostCard(post: post, specialReact: community.resolvedReact)
                                    .background(WhisperTheme.card(colorScheme))
                                    .clipShape(.rect(cornerRadius: 22))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 22)
                                            .strokeBorder(
                                                LinearGradient(
                                                    colors: [
                                                        Color(red: 0.98, green: 0.45, blue: 0.09).opacity(0.45),
                                                        Color(red: 1.00, green: 0.72, blue: 0.42).opacity(0.30),
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    }
                                    .shadow(color: Color(red: 0.98, green: 0.45, blue: 0.09).opacity(0.20), radius: 15, y: 6)
                                    .shadow(color: Color(red: 0.98, green: 0.45, blue: 0.09).opacity(0.08), radius: 4, y: 2)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                            } else if community.id == "dating" {
                                VStack(spacing: 0) {
                                    WhisperPostCard(post: post, specialReact: community.resolvedReact)
                                    if let why = matchWhyLine(for: post) { matchWhyChip(why) }
                                    if let hi = sayHiTarget(for: post) { sayHiPill(hi) }
                                }
                                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 24))
                                .clipShape(.rect(cornerRadius: 24))
                                .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(Color.pink.opacity(0.16), lineWidth: 1) }
                                .padding(.horizontal, 12).padding(.vertical, 7)
                            } else {
                                WhisperPostCard(post: post, specialReact: community.resolvedReact)
                                Divider().background(WhisperTheme.hairline(colorScheme))
                            }
                        }
                    }
                    }
                }
                .padding(.bottom, community.id == "dating" && !jasperLocked ? 140 : 24)
            }
            .whisperRefreshable {
                await backend.fetchPosts()
            }
        }
        .overlay(alignment: .bottom) {
            // Cupid Jasper — the dating-tuned matchmaker dock behind the
            // "matched" pill. PINNED like the inbox dock: measured anchoring
            // keeps it above the tab bar instead of hidden underneath it.
            if community.id == "dating", !jasperLocked {
                datingMatchmakerDock
                    .whisperPinnedAboveTabBar()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .whisperEdgeBack { dismiss() }
        .task {
            if community.id == "dating", sortMode == .top { sortMode = .forYou }
            await backend.fetchPostsIfStale()
            withAnimation(.easeOut(duration: 0.25)) { didFirstFetch = true }
        }
        .task {
            // Dating: preferences (cloud wins over an empty device), the
            // nearby set that drives the radius filter, and the queue count.
            guard community.id == "dating" else { return }
            datingPrefs = await WhisperDatingPrefsStore.syncFromCloud()
            nearby = await WhisperDatingPrefsStore.fetchNearby()
            blindQueueCount = await WhisperBlindDate.queueCount()
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now in
            if community.id == "dating" {
                icebreakerTick = now
                Task { blindQueueCount = await WhisperBlindDate.queueCount() }
            }
        }
        .sheet(isPresented: $showInfo) {
            WhisperCommunityInfoSheet(
                community: community,
                memberCount: memberCount,
                postCount: postCount
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showJasperSettings) {
            WhisperSettingsView()
        }
        .fullScreenCover(isPresented: $presentComposer, onDismiss: { composerPrefill = "" }) {
            WhisperComposerView(
                initialTopic: community.name.lowercased(),
                initialText: composerPrefill
            )
        }
        .sheet(isPresented: $showDatingCardEditor) {
            WhisperDatingCardEditorSheet()
        }
        .sheet(item: $answerPrompt, onDismiss: {
            if let text = pendingSharePrefill {
                pendingSharePrefill = nil
                composerPrefill = text
                presentComposer = true
            }
        }) { p in
            WhisperIcebreakerAnswerSheet(
                prompt: p.text,
                onShare: { text in pendingSharePrefill = text },
                onSaved: { answersTick += 1 }
            )
        }
        .fullScreenCover(item: $speedDateLobby) { item in
            WhisperSpeedDateLobbyView(meeting: item.row, code: item.code)
        }
        .sheet(isPresented: $showBlindDateFinder) {
            WhisperBlindDateFinderView(onInvite: { startSpeedDate() })
        }
        .sheet(isPresented: $showDatingPrefs) {
            WhisperDatingPrefsSheet(onSaved: {
                datingPrefs = WhisperDatingPrefsStore.load()
                Task { nearby = await WhisperDatingPrefsStore.fetchNearby() }
            })
        }
        .sheet(isPresented: $showDatingTools) {
            datingToolsSheet
        }
        .sheet(item: $sayHiUser) { t in
            NavigationStack {
                WhisperDMThreadView(otherUserID: t.userID, otherUsername: t.username, conversationKind: .dating)
            }
            // Say-hi chats land in the 💘 Dating inbox filter.
            .task { WhisperDatingContacts.mark(t.userID) }
        }
        .sheet(isPresented: $shareInMessages) {
            WhisperRecipientShareSheet(payload: WhisperSharedCommunityEmbed.encode(.init(communityID: community.id))) { EmptyView() }
        }
        .sheet(item: $shareItem) { item in
            CommunityShareSheet(text: item.text)
        }
        .alert("Sorry — VIP only 👻", isPresented: $showVIPGate) {
            Button("Link Jasper account") {
                Haptics.tap()
                showJasperSettings = true
            }
            Button("Maybe later", role: .cancel) {}
        } message: {
            Text("Jasper Circle is the linked-accounts lounge. Connect your Jasper account and the doors open — one tap in Settings, no codes.")
        }
    }

    // MARK: - Header (Fitness Threads · Beta · Community / Joined / ⋯)
    private var threadsHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .center, spacing: 8) {
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            VStack(alignment: .leading, spacing: 2) {
                Text(community.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 4) {
                    if let origin = community.origin {
                        Image(systemName: "mappin")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                        Text(origin)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .lineLimit(1)
                    } else {
                        Text("Beta")
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    Text("·")
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                    // fixedSize keeps "Community" on ONE line — without it the
                    // HStack squeezes this label and hyphenates it across two
                    // lines on narrow screens; the origin text truncates instead.
                    Text("Community")
                        .foregroundStyle(Color(red: 0.55, green: 0.45, blue: 0.92))
                        .lineLimit(1)
                        .fixedSize()
                    if let react = community.resolvedReact {
                        Text(react)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .font(.footnote.weight(.semibold))
            }
            Spacer(minLength: 0)
            Button {
                Haptics.tap()
                Task { await toggleJoin() }
            } label: {
                Text(isJoined ? "Joined" : "Join")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isJoined ? WhisperTheme.ink(colorScheme) : WhisperTheme.surface(colorScheme))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(isJoined ? Color.clear : WhisperTheme.ink(colorScheme), in: .rect(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
                    .frame(minHeight: 44).contentShape(.rect)
                    .opacity(working ? 0.55 : 1)
            }
            .buttonStyle(.plain)
            .disabled(working)
            Menu {
                Button { showInfo = true } label: { Label("About this community", systemImage: "info.circle") }
                if WhisperSharedCommunityEmbed.community(for: .init(communityID: community.id)) != nil {
                    Button("Share in Messages", systemImage: "paperplane") { Haptics.tap(); shareInMessages = true }
                }
                Button {
                    Haptics.tap()
                    shareItem = ShareItem(text: "Join the \(community.name) community on Whisper — \(community.tagline)")
                } label: { Label("Share community", systemImage: "square.and.arrow.up") }
                if isJoined {
                    Button(role: .destructive) {
                        Haptics.tap()
                        Task { await toggleJoin() }
                    } label: { Label("Leave", systemImage: "rectangle.portrait.and.arrow.right") }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Community options")
        }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var membersRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: -8) {
                ForEach(Array(Set(matching.map(\.username))).sorted().prefix(3), id: \.self) { username in
                    WhisperAvatar(username: username, size: 24, ring: false)
                        .overlay { Circle().strokeBorder(WhisperTheme.surface(colorScheme), lineWidth: 2) }
                }
            }.accessibilityHidden(true)
            HStack(spacing: 6) {
                Text("\(displayMemberCount) recent \(memberCount == 1 ? "contributor" : "contributors")")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                if postCount > 0 {
                    Text("·")
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                    Text("\(WhisperCommunityDetailView.compact(postCount)) \(postCount == 1 ? "post" : "posts")")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var postPill: some View {
        Button {
            Haptics.tap()
            presentComposer = true
        } label: {
            HStack(spacing: 12) {
                WhisperAvatar(username: users.me?.username ?? "you", size: 40)
                Text("Post to \(community.name)…")
                    .font(.body)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var sortRow: some View {
        HStack {
            Menu {
                ForEach(availableSortModes) { mode in
                    Button(mode.rawValue) {
                        Haptics.tap()
                        sortMode = mode
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(sortMode.rawValue)
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.85))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func toggleJoin() async {
        guard !working else { return }
        // VIP door policy: joining Jasper Circle requires the Jasper account
        // link — pitch the link instead of silently joining.
        if !isJoined, community.requiresJasperLink, JasperConnectClient.shared.connection == nil {
            Haptics.tap()
            showVIPGate = true
            return
        }
        working = true; membershipError = nil
        let epoch = AccountStorage.generation
        defer { working = false }
        let key = community.name.lowercased()
        var current = (users.me?.interests ?? []).map { $0 }
        let lowered = Set(current.map { $0.lowercased() })
        if lowered.contains(key) {
            current.removeAll { $0.lowercased() == key }
        } else {
            current.append(community.name)
        }
        let ok = await users.updateInterests(current)
        guard !Task.isCancelled, epoch == AccountStorage.generation else { return }
        if !ok { membershipError = "Couldn't update your membership. Try again." }
    }

    private static func compact(_ n: Int) -> String {
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

    /// Warm ember lock stage — shown instead of the feed when the Jasper
    /// account link is missing. One tap opens Settings → Sync with Jasper.
    private var jasperLockedCard: some View {
        let ember = Color(red: 0.98, green: 0.45, blue: 0.09)
        return VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(ember)
                .frame(width: 52, height: 52)
                .background(ember.opacity(0.12), in: Circle())
            Text("Sorry — VIP only 👻")
                .font(.headline.weight(.heavy))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Jasper Circle opens once your Jasper account is linked — one tap in Settings → Sync with Jasper, no codes. Members' posts glow in here.")
                .font(.footnote)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .multilineTextAlignment(.center)
            Button {
                Haptics.tap()
                showJasperSettings = true
            } label: {
                Text("Connect Jasper")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.surface(colorScheme))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(WhisperTheme.ink(colorScheme), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(ember.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: ember.opacity(0.18), radius: 16, y: 6)
        .padding(16)
    }

    // MARK: - Dating hub extras (icebreaker · safety · say hi)

    private var datingIcebreakerCard: some View {
        let rose = Color(red: 0.91, green: 0.28, blue: 0.49)
        let prompt = shuffledPrompt ?? WhisperCommunity.datingIcebreakerForHour(at: icebreakerTick)
        _ = answersTick
        let answered = WhisperDatingAnswers.answer(for: prompt) != nil
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                Text("THIS HOUR'S ICEBREAKER")
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.4)
            }
            .foregroundStyle(rose)
            Text(prompt)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    Haptics.tap()
                    answerPrompt = DatingAnswerPrompt(text: prompt)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(answered ? "Edit answer" : "Answer it")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(rose))
                }
                .buttonStyle(.plain)
                Button {
                    Haptics.tap()
                    let pool = WhisperCommunity.datingIcebreakers.filter { $0 != prompt }
                    shuffledPrompt = pool.randomElement()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "shuffle")
                            .font(.system(size: 12, weight: .bold))
                        Text("Shuffle")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(rose)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(rose.opacity(0.10)))
                    .overlay(Capsule().strokeBorder(rose.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                Text("New prompt in \(WhisperCommunity.minutesUntilNextIcebreaker(at: icebreakerTick))m")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(rose.opacity(0.8))
                    .monospacedDigit()
            }
            if answered {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("Answered privately — every answer sharpens your matches")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(rose.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(rose.opacity(colorScheme == .dark ? 0.14 : 0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(rose.opacity(0.30), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var datingSafetyCard: some View {
        let emerald = Color(red: 0.02, green: 0.59, blue: 0.41)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    safetyExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(emerald)
                    Text("Date safe on Whisper")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .rotationEffect(.degrees(safetyExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)
            if safetyExpanded {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(WhisperCommunity.datingSafetyTips, id: \.self) { tip in
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(emerald)
                                .padding(.top, 2)
                            Text(tip)
                                .font(.system(size: 12.5))
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(WhisperTheme.card(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    /// The say-hi target for a dating post — the author's userID + handle;
    /// nil for your own posts or when the backing row can't be found.
    private func sayHiTarget(for post: WhisperPost) -> SayHiUser? {
        guard let row = backend.posts.first(where: {
            $0.id.lowercased() == post.id.uuidString.lowercased()
        }) else { return nil }
        let me = AccountStorage.currentUserID.lowercased()
        guard !row.user_id.isEmpty, row.user_id.lowercased() != me else { return nil }
        return SayHiUser(userID: row.user_id, username: post.username)
    }

    private func sayHiPill(_ target: SayHiUser) -> some View {
        let rose = Color(red: 0.91, green: 0.28, blue: 0.49)
        return HStack {
            Spacer()
            Button {
                Haptics.tap()
                sayHiUser = target
            } label: {
                HStack(spacing: 6) {
                    Text("\u{1F44B}")
                        .font(.system(size: 13))
                    Text("Say hi to @\(target.username)")
                        .font(.subheadline.weight(.semibold)).lineLimit(2)
                }
                .foregroundStyle(rose)
                .padding(.horizontal, 13)
                .frame(minHeight: 44)
                .background(Capsule().fill(rose.opacity(0.10)))
                .overlay(Capsule().strokeBorder(rose.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    /// The community's TOOL DRAWER door — every dating special (blind dates,
    /// preferences, your card, nearby) lives in one sheet instead of a
    /// button riding the masthead. Wears the live queue count.
    private var datingToolsBar: some View {
        let rose = Color(red: 0.91, green: 0.28, blue: 0.49)
        return Button {
            Haptics.tap()
            showDatingTools = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [rose, Color(red: 0.98, green: 0.45, blue: 0.62)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Make a connection")
                        .font(.headline)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(1)
                    Text("Speed dates, preferences & your card")
                        .font(.footnote)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 6)
                if blindQueueCount > 0 {
                    Text("\(min(blindQueueCount, 99)) waiting")
                        .font(.system(size: 10.5, weight: .black))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(red: 0.16, green: 0.72, blue: 0.45)))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(rose)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(rose.opacity(colorScheme == .dark ? 0.16 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(rose.opacity(0.28), lineWidth: 1)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .accessibilityLabel("Dating tools")
    }

    /// The drawer itself — tool rows that hand off to their sheets.
    private var datingToolsSheet: some View {
        let rose = Color(red: 0.91, green: 0.28, blue: 0.49)
        let mint = Color(red: 0.16, green: 0.72, blue: 0.45)
        return NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        datingToolRow(
                            icon: "video.fill",
                            tint: rose,
                            title: "Find me a blind date",
                            subtitle: blindQueueCount > 0
                                ? "\(blindQueueCount) waiting right now · five minutes, cameras behind the curtain"
                                : "Get paired with a compatible stranger · five minutes, cameras behind the curtain",
                            badge: blindQueueCount > 0 ? "\(min(blindQueueCount, 99))" : nil
                        ) {
                            openDatingTool { showBlindDateFinder = true }
                        }
                        datingToolRow(
                            icon: "slider.horizontal.3",
                            tint: rose,
                            title: "Dating preferences",
                            subtitle: datingPrefs.isConfigured
                                ? datingPrefs.summaryLine
                                : "Who you want to meet, how far, what you're looking for",
                            badge: nil
                        ) {
                            openDatingTool { showDatingPrefs = true }
                        }
                        datingToolRow(
                            icon: "heart.text.square.fill",
                            tint: rose,
                            title: WhisperSpeedDating.hasCard ? "My dating card ✓" : "My dating card",
                            subtitle: "Five prompts Jasper builds every date from",
                            badge: nil
                        ) {
                            openDatingTool { showDatingCardEditor = true }
                        }
                        if datingPrefs.hasLocation {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(mint.opacity(0.14))
                                    Image(systemName: nearbyOnly ? "location.fill" : "location")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(mint)
                                }
                                .frame(width: 40, height: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Nearby only")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                                        .lineLimit(1)
                                    Text(nearbyOnly
                                         ? (nearby.isEmpty ? "Nobody in range yet" : "\(nearby.count) people inside your radius")
                                         : "Everyone, anywhere")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 6)
                                Toggle("", isOn: Binding(
                                    get: { nearbyOnly },
                                    set: { value in
                                        Haptics.tap()
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { nearbyOnly = value }
                                        WhisperDatingPrefsStore.nearbyOnly = value
                                    }
                                ))
                                .labelsHidden()
                                .tint(rose)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1))
                        }
                        Text("Blind dates run five minutes with cameras behind the curtain until you both reveal. Preferences and your card stay private — other people only ever see a rounded distance.")
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .padding(.top, 6)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Dating tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showDatingTools = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Close the drawer, then present the chosen tool once the sheet is gone.
    private func openDatingTool(_ present: @escaping () -> Void) {
        Haptics.tap()
        showDatingTools = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { present() }
    }

    private func datingToolRow(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        badge: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.14))
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(tint)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 6)
                if let badge {
                    Text(badge)
                        .font(.system(size: 10.5, weight: .black))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(red: 0.16, green: 0.72, blue: 0.45)))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Who you want to meet + how far — the radius chips under the masthead.
    private var datingPrefsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                datingChip(
                    icon: "slider.horizontal.3",
                    text: datingPrefs.isConfigured ? datingPrefs.summaryLine : "Who do you want to meet?",
                    filled: datingPrefs.isConfigured
                ) { showDatingPrefs = true }
                if datingPrefs.hasLocation {
                    datingChip(
                        icon: nearbyOnly ? "location.fill" : "location",
                        text: nearbyOnly
                            ? (nearby.isEmpty ? "Nearby · nobody in range yet" : "Nearby only · \(nearby.count)")
                            : "Everyone, anywhere",
                        filled: nearbyOnly
                    ) {
                        nearbyOnly.toggle()
                        WhisperDatingPrefsStore.nearbyOnly = nearbyOnly
                    }
                }
                datingChip(
                    icon: "heart.text.square.fill",
                    text: WhisperSpeedDating.hasCard ? "Dating card ✓" : "Your dating card",
                    filled: false
                ) { showDatingCardEditor = true }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 10)
    }

    private func datingChip(icon: String, text: String, filled: Bool, action: @escaping () -> Void) -> some View {
        let rose = Color(red: 0.91, green: 0.28, blue: 0.49)
        return Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { action() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .bold))
                Text(text)
                    .font(.system(size: 11.5, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(filled ? .white : rose)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(filled ? rose : rose.opacity(colorScheme == .dark ? 0.16 : 0.09)))
            .overlay(Capsule().strokeBorder(rose.opacity(filled ? 0 : 0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// "You both: Outdoors · Food · 12 km away" — why this person ranks in For you.
    private func matchWhyLine(for post: WhisperPost) -> String? {
        guard sortMode == .forYou else { return nil }
        let me = AccountStorage.currentUserID.lowercased()
        guard let row = backend.posts.first(where: { $0.id.lowercased() == post.id.uuidString.lowercased() }),
              row.user_id.lowercased() != me else { return nil }
        var parts: [String] = []
        let mine = myDatingAnswers
        if !mine.isEmpty {
            let theirs = WhisperDatingMatch.answer(from: post.caption).text
            let shared = WhisperDatingMatch.sharedThemes(mine: mine, theirsText: theirs)
            if !shared.isEmpty { parts.append("You both: " + shared.joined(separator: " · ")) }
        }
        if let near = nearbyByID[row.user_id.lowercased()] {
            if let d = near.distanceLabel { parts.append(d) }
            if let intent = near.intent, intent == datingPrefs.intent,
               let label = WhisperDatingPrefs.intentLabel(intent) {
                parts.append("both want \(label.lowercased())")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func matchWhyChip(_ text: String) -> some View {
        let rose = Color(red: 0.91, green: 0.28, blue: 0.49)
        return HStack(spacing: 5) {
            Image(systemName: "heart.fill")
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(rose)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    /// A hub member's say-hi target by @handle — the matchmaker cards use it.
    private func sayHiTarget(forHandle handle: String) -> SayHiUser? {
        let needle = handle.lowercased().replacingOccurrences(of: "@", with: "")
        let me = AccountStorage.currentUserID.lowercased()
        for row in backend.posts where community.matches(row: row) {
            let resolved = WhisperBackendService.shared.resolvedAuthorUsername(rowUsername: row.username, rowUserID: row.user_id)
            if resolved.lowercased() == needle, !row.user_id.isEmpty, row.user_id.lowercased() != me {
                return SayHiUser(userID: row.user_id, username: resolved)
            }
        }
        return nil
    }

    /// Mints a wsp room, copies the invite link, and opens the custom
    /// speed-date LOBBY — entering from there primes the room and opens
    /// the real meeting window; the guest joins from the same link.
    private func startSpeedDate() {
        guard !startingSpeedDate else { return }
        startingSpeedDate = true
        let hex = "0123456789abcdef"
        let chunk: () -> String = { String((0..<4).map { _ in hex.randomElement() ?? "0" }) }
        let code = "wsp-\(chunk())-\(chunk())"
        let roomID = WhisperMeetingService.meetingID(fromCode: code)
        // ?sd=1 lets a web guest see the speed-date welcome instantly.
        UIPasteboard.general.string = "https://mydailywhisper.com/meet/\(code)?sd=1"
        withAnimation(.easeOut(duration: 0.2)) { speedDateLinkCopied = true }
        Task {
            await WhisperMeetingService.shared.ensureRoom(id: roomID)
            let row = await WhisperMeetingService.shared.fetch(id: roomID)
            startingSpeedDate = false
            speedDateLinkCopied = false
            if let row {
                speedDateLobby = SpeedDateLobbyItem(row: row, code: code)
            }
        }
    }

    /// The match-sort explainer under the sort row — pink when active, an
    /// honest hint until I've answered an icebreaker myself.
    private var datingSortChip: some View {
        let rose = Color(red: 0.91, green: 0.28, blue: 0.49)
        let hasAnswer = !myDatingAnswers.isEmpty
        return HStack(spacing: 6) {
            Image(systemName: hasAnswer ? "heart.fill" : "sparkles")
                .font(.system(size: 10, weight: .bold))
            // One line, always — shorter copy plus a scale floor instead of wrapping.
            Text(hasAnswer
                ? "Sorted for you · closest answers first"
                : "Answer the icebreaker to sort by closeness")
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(rose)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(rose.opacity(colorScheme == .dark ? 0.14 : 0.07), in: .rect(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    /// The dating-tuned Jasper analysis dock v2 — cupid costume, a real
    /// matchmaker brain (preferences + private answers + distance in the
    /// context), smart lenses, and a STRUCTURED response system: the reply
    /// comes back as READ / MATCH / MOVE and renders as tappable match cards.
    private var datingMatchmakerDock: some View {
        let rose = Color(red: 0.91, green: 0.28, blue: 0.49)
        let blush = Color(red: 0.98, green: 0.70, blue: 0.79)
        return JasperAnalysisDock(
            pillLabel: "matched",
            boxTitle: "Knot Matchmaker",
            focus: """
            You are Knot, Whisper's MATCHMAKER in the Dating hub — think like a sharp, kind friend who reads people well, not a horoscope. In the context: this hour's icebreaker, MY preferences, my dating card, my private icebreaker answers, and other members' latest answers (with distance and intent when known). Rank my 2-3 most compatible people from what they ACTUALLY wrote — shared themes, matching intent, real chemistry signals, distance inside my radius — and give me an opener I'd genuinely send. Never invent people or details, zero clichés, zero cringe, no flattery. If I haven't answered anything yet, READ the room honestly and make my MOVE answering the icebreaker.
            \(WhisperMatchmakerReply.format)
            """,
            buildContext: { datingAnalysisContext() },
            emptyText: "Nothing to read yet — answer this hour's icebreaker and give me some signal.",
            actions: [
                JasperDockAction(
                    id: "openers",
                    label: "Openers",
                    icon: "hand.wave.fill",
                    kind: .lens("""
                    From the dating hub context, pick my top 2 matches and write ONE opener for each that I'd actually send — warm, playful, specific to their exact words, first person, one line. READ = one line on my opener style. MOVE = when and how to send it.
                    \(WhisperMatchmakerReply.format)
                    """)
                ),
                JasperDockAction(
                    id: "vibe",
                    label: "My vibe",
                    icon: "sparkles",
                    kind: .lens("""
                    Read MY dating card, preferences, and private answers like a matchmaker would: what I actually signal (one honest line), what might be scaring good matches off, and the single edit that would sharpen how I come across. Put the signal in READ, skip MATCH lines unless someone in the hub clearly fits me, and make MOVE the one edit.
                    \(WhisperMatchmakerReply.format)
                    """)
                ),
                JasperDockAction(
                    id: "coach",
                    label: "Answer coach",
                    icon: "pencil.and.outline",
                    kind: .lens("Help ME answer this hour's icebreaker (in the context) in a way that attracts the people I say I want. Draft 2 short answers in a natural first-person voice — specific, warm, a little playful, no clichés — one line each, then one line on why they'd stand out in a dating feed.")
                ),
                JasperDockAction(
                    id: "answer",
                    label: "Answer it",
                    icon: "heart.fill",
                    kind: .perform {
                        answerPrompt = DatingAnswerPrompt(text: shuffledPrompt ?? WhisperCommunity.datingIcebreakerForHour())
                    }
                ),
            ],
            costume: .datingMatchmaker,
            replyContent: { text in
                guard let parsed = WhisperMatchmakerReply.parse(text) else { return nil }
                return AnyView(
                    WhisperMatchmakerCardsView(
                        parsed: parsed,
                        accent: rose,
                        softAccent: blush,
                        avatarFor: { _ in nil },
                        onSayHi: { match in
                            if let target = sayHiTarget(forHandle: match.username) {
                                sayHiUser = target
                            }
                        }
                    )
                )
            }
        )
    }

    /// Live context for the matchmaker v2 — this hour's prompt, my
    /// preferences + card + private answers, and the hub's people with
    /// distance/intent when known (out-of-radius people drop out when the
    /// Nearby filter is on).
    private func datingAnalysisContext() -> String? {
        var lines: [String] = []
        lines.append("THIS HOUR'S ICEBREAKER: \(shuffledPrompt ?? WhisperCommunity.datingIcebreakerForHour())")
        var prefsLine = "MY PREFERENCES: \(datingPrefs.summaryLine)"
        if let city = datingPrefs.cityLabel { prefsLine += " · near \(city)" }
        if let age = datingPrefs.age { prefsLine += " · I'm \(age)" }
        lines.append(prefsLine)
        let myCard = WhisperSpeedDating.loadCard()
        if !myCard.isEmpty {
            lines.append(WhisperSpeedDating.contextBlock(label: "MY DATING CARD", answers: myCard))
        }
        let mine = myDatingAnswers
        if mine.isEmpty {
            lines.append("I HAVEN'T ANSWERED ANY ICEBREAKER YET.")
        } else {
            let list = mine.prefix(5).map { a -> String in
                if let p = a.prompt { return "- \"\(String(p.prefix(70)))\" → \(String(a.text.prefix(160)))" }
                return "- \(String(a.text.prefix(160)))"
            }
            lines.append("MY ANSWERS (newest first):\n" + list.joined(separator: "\n"))
        }
        let me = AccountStorage.currentUserID.lowercased()
        let near = nearbyByID
        let radiusOn = nearbyOnly && datingPrefs.hasLocation && !nearby.isEmpty
        var people: [String] = []
        let rows = backend.posts
            .filter { community.matches(row: $0) && $0.user_id.lowercased() != me }
            .sorted {
                (WhisperBackendService.parseISO($0.created_at) ?? .distantPast) >
                (WhisperBackendService.parseISO($1.created_at) ?? .distantPast)
            }
        for row in rows.prefix(16) {
            let uid = row.user_id.lowercased()
            if radiusOn, near[uid] == nil { continue }
            let parsed = WhisperDatingMatch.answer(from: row.caption)
            guard !parsed.text.isEmpty else { continue }
            let handle = WhisperBackendService.shared.resolvedAuthorUsername(rowUsername: row.username, rowUserID: row.user_id)
            var meta: [String] = []
            if let n = near[uid] {
                if let d = n.distanceLabel { meta.append(d) }
                if let age = n.age { meta.append("\(age)") }
                if let intent = WhisperDatingPrefs.intentLabel(n.intent) { meta.append("wants \(intent.lowercased())") }
            }
            let shared = mine.isEmpty ? [] : WhisperDatingMatch.sharedThemes(mine: mine, theirsText: parsed.text)
            if !shared.isEmpty { meta.append("shared: \(shared.joined(separator: ", "))") }
            let metaText = meta.isEmpty ? "" : " [\(meta.joined(separator: " · "))]"
            if let prompt = parsed.prompt {
                people.append("@\(handle)\(metaText) — answered \"\(String(prompt.prefix(60)))\": \(String(parsed.text.prefix(140)))")
            } else {
                people.append("@\(handle)\(metaText): \(String(parsed.text.prefix(140)))")
            }
        }
        if !people.isEmpty {
            lines.append("PEOPLE IN THE DATING HUB (newest first):\n" + people.joined(separator: "\n"))
        }
        return (people.isEmpty && mine.isEmpty) ? nil : lines.joined(separator: "\n\n")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            WhisperMeetDoodle(symbol: community.symbol, height: 144)
            Text("No posts here yet")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text(
                community.id == "dating"
                    ? "Nobody's made the first move yet — answer this hour's icebreaker and break the ice."
                    : "Be the first — pick \(community.name) in the composer when you post."
            )
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Dating logo card (the match engine lives in WhisperDatingMatchEngine.swift)

/// The Whisper Dating wordmark floating over slow-drifting rose blooms —
/// the hub's masthead. Color anchors the size; blooms live in the overlay
/// so they can never inflate the layout (the round-22 bug class).
private struct WhisperDatingLogoCard: View {
    @State private var drift: Bool = false

    var body: some View {
        Color(red: 0.99, green: 0.83, blue: 0.88)
            .frame(height: 128)
            .overlay {
                ZStack {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.63, blue: 0.76).opacity(0.6))
                        .frame(width: 220, height: 220)
                        .blur(radius: 46)
                        .offset(x: drift ? -96 : 70, y: drift ? -52 : 26)
                    Circle()
                        .fill(Color(red: 0.93, green: 0.36, blue: 0.58).opacity(0.35))
                        .frame(width: 190, height: 190)
                        .blur(radius: 52)
                        .offset(x: drift ? 104 : -80, y: drift ? 46 : -30)
                    Circle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 150, height: 150)
                        .blur(radius: 48)
                        .offset(x: drift ? -22 : 32, y: drift ? 54 : -46)
                    Image("WhisperDatingLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 66)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(.rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color(red: 0.91, green: 0.28, blue: 0.49).opacity(0.22), lineWidth: 1)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                    drift = true
                }
            }
            .accessibilityLabel("Whisper Dating")
    }
}

// MARK: - Share sheet wrapper

private struct CommunityShareSheet: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Info sheet

/// The community "i" sheet — everything about a hub in one place: what it
/// is, where it came from (campus / gym provenance with the real address
/// and distance), its signature react, and the caption keywords that file
/// posts into it.
struct WhisperCommunityInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let community: WhisperCommunity
    let memberCount: Int
    let postCount: Int

    private var isGeo: Bool { community.id.hasPrefix("geo-") }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        hero
                        statsRow
                        if community.origin != nil || community.originAddress != nil {
                            originCard
                        }
                        if let react = community.resolvedReact {
                            reactCard(react)
                        }
                        matchingCard
                        Text(isGeo
                             ? "Location community — it appears while you're nearby. Joining keeps it in Your communities wherever you are."
                             : "Part of the Whisper catalog — the same community on every account.")
                            .font(.caption2)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .padding(.horizontal, 2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: community.symbol)
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(.white)
                Text(community.name)
                    .font(.title2.weight(.black))
                    .foregroundStyle(.white)
                Text(community.tagline)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                LinearGradient(
                    colors: community.gradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: .rect(cornerRadius: 20)
            )
            if let react = community.resolvedReact {
                Text(react)
                    .font(.system(size: 20))
                    .padding(8)
                    .background(.black.opacity(0.3), in: Circle())
                    .padding(10)
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 8) {
            statChip(icon: "person.2.fill", label: "\(memberCount) member\(memberCount == 1 ? "" : "s")")
            statChip(icon: "square.text.square.fill", label: "\(postCount) post\(postCount == 1 ? "" : "s")")
            Spacer(minLength: 0)
        }
    }

    private func statChip(icon: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(WhisperTheme.ink(colorScheme))
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(WhisperTheme.card(colorScheme), in: Capsule())
        .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
    }

    private var originCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHERE IT COMES FROM")
                .font(.system(size: 9, weight: .black))
                .tracking(1.2)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            if let origin = community.origin {
                infoRow(icon: "mappin.circle.fill", title: origin,
                        subtitle: community.id.hasPrefix("geo-gym-")
                            ? "Your gym — detected near your location"
                            : "Unlocked by a campus near your location")
            }
            if let address = community.originAddress {
                infoRow(icon: "building.2.fill", title: address, subtitle: "Address")
            }
            Text("Detected on-device — Whisper only keeps the place name, never your coordinates.")
                .font(.caption2)
                .foregroundStyle(WhisperTheme.muted(colorScheme).opacity(0.85))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func reactCard(_ react: String) -> some View {
        HStack(spacing: 12) {
            Text(react)
                .font(.system(size: 30))
                .frame(width: 52, height: 52)
                .background(WhisperTheme.surface(colorScheme), in: .rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text("Signature react")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("Liking a post inside this community bursts \(react) instead of the heart.")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private var matchingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HOW POSTS LAND HERE")
                .font(.system(size: 9, weight: .black))
                .tracking(1.2)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            Text("Captions mentioning any of these join the feed automatically:")
                .font(.caption)
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], alignment: .leading, spacing: 6) {
                keywordChip("#\(community.name.replacingOccurrences(of: " ", with: "").lowercased())")
                ForEach(community.keywords.prefix(6), id: \.self) { keyword in
                    keywordChip(keyword.trimmingCharacters(in: .whitespaces))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func keywordChip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(WhisperTheme.ink(colorScheme))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .frame(maxWidth: .infinity)
            .background(WhisperTheme.surface(colorScheme), in: Capsule())
            .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
    }

    private func infoRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .frame(width: 30, height: 30)
                .background(WhisperTheme.surface(colorScheme), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Model

/// A community is a curated topic with display chrome + a matcher that
/// figures out whether a post's caption belongs to it. Lightweight enough
/// to live entirely in the client — no backend table required.
nonisolated struct WhisperCommunity: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let tagline: String
    let symbol: String
    let keywords: [String]
    /// Two-stop gradient colours for the hero / card.
    let gradient: [Color]
    /// Signature react emoji — bursts on like and fills the heart inside
    /// this community's feed (geo hubs always carry one).
    var specialReact: String? = nil
    /// Provenance line for geo-suggested hubs ("Near Harvard University",
    /// "1.2 km away"). nil for catalog communities.
    var origin: String? = nil
    /// Street address of the real place behind a geo hub (campus / gym),
    /// shown in the community info sheet. nil for catalog communities.
    var originAddress: String? = nil
    /// Viewable only when the user's Jasper account is linked — posts inside
    /// wear the ember glow shell. Mirrors the web catalog flag.
    var requiresJasperLink: Bool = false

    /// The react this community actually uses — explicit override first,
    /// then the curated catalog mapping. nil = standard heart everywhere.
    var resolvedReact: String? {
        specialReact ?? WhisperCommunity.catalogReacts[id]
    }

    func matches(caption: String) -> Bool {
        let needle = " \(caption.lowercased()) "
        let nameLower = name.lowercased()
        if needle.contains("#\(nameLower)") { return true }
        if needle.contains("#\(nameLower.replacingOccurrences(of: " ", with: ""))") { return true }
        if needle.contains("#\(id.lowercased())") { return true }
        return keywords.contains { Self.keywordHit(needle: needle, keyword: $0) }
    }

    /// Strict keyword hit — must START at a word boundary and may run at
    /// most 4 extra letters, so "run" catches "running" but never "brunch",
    /// and "rest" never catches "restaurant". Mirrors the web matcher.
    nonisolated static func keywordHit(needle: String, keyword: String) -> Bool {
        let k = keyword.trimmingCharacters(in: .whitespaces).lowercased()
        guard !k.isEmpty else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: k)
        let pattern = "(^|[^a-z0-9])\(escaped)[a-z]{0,4}($|[^a-z0-9])"
        return needle.range(of: pattern, options: .regularExpression) != nil
    }

    /// The one true membership check — EXPLICIT-ONLY. A post belongs to a
    /// community only when the author picked it at compose time; captions
    /// and hashtags never auto-file a post. Mirrors web `communityMatchesPost`.
    func matches(row: WhisperPostRow) -> Bool {
        guard let cid = row.community_id, !cid.isEmpty else { return false }
        return cid == id
    }

    /// Resolves a composer topic string (community id, name, or free text)
    /// to a catalog community. nil for unknown/custom topics.
    nonisolated static func resolve(topic: String) -> WhisperCommunity? {
        let t = topic.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return nil }
        return catalog.first { $0.id.lowercased() == t || $0.name.lowercased() == t }
    }

    static func == (lhs: WhisperCommunity, rhs: WhisperCommunity) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension WhisperCommunity {
    /// The dating hub's daily icebreakers — mirrors web `DATING_ICEBREAKERS` 1:1.
    static let datingIcebreakers: [String] = [
        "What's your idea of a perfect first date — coffee, a walk, or something braver?",
        "Two truths and a lie — go.",
        "What's a green flag people don't talk about enough?",
        "What song would play when you walk into a room?",
        "Early bird date or late-night talker?",
        "What's the best meal you could cook for someone?",
        "What hobby could you talk about for an hour straight?",
        "Describe your weekend in three emojis.",
        "What's something small that instantly makes your day?",
        "Dogs, cats, or 'let me show you my plant'?",
        "What's a place you'd take someone to show them who you are?",
        "What are you actually looking for right now — honestly?",
        "Your go-to karaoke song. No skipping.",
        "What's the most spontaneous thing you've ever done?"
    ]

    /// Safety checklist — mirrors web `DATING_SAFETY_TIPS`.
    static let datingSafetyTips: [String] = [
        "Meet in public for the first few dates.",
        "Tell a friend where you're going and with whom.",
        "Keep chats on Whisper until you trust them — report anything off.",
        "Never send money or financial info. Ever.",
        "Video-chat before meeting — it should feel easy, not pressured."
    ]

    /// Same prompt for EVERYONE, rotating every hour — UTC day-of-year × 24
    /// + hour, so the whole world answers the same question at the same
    /// time and matches dial in as the day moves. Mirrors web exactly.
    static func datingIcebreakerForHour(at date: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        let day = cal.ordinality(of: .day, in: .year, for: date) ?? 1
        let hour = cal.component(.hour, from: date)
        return datingIcebreakers[(day * 24 + hour) % datingIcebreakers.count]
    }

    /// Minutes until the prompt rotates (top of the next hour, UTC).
    static func minutesUntilNextIcebreaker(at date: Date = Date()) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        let minute = cal.component(.minute, from: date)
        return max(1, 60 - minute)
    }

    /// Signature reacts for the built-in catalog — the like button inside
    /// each community's feed bursts (and fills) with its own emoji instead
    /// of the plain heart. Mirrored on web so both apps react identically.
    nonisolated static let catalogReacts: [String: String] = [
        "dating": "💘",
        "workouts": "💪", "running": "🏃", "yoga": "🧘", "mobility": "🤸",
        "lifting": "🏋️", "hiit": "⚡️", "recovery": "🌿", "sleep": "😴",
        "nutrition": "🥗", "hydration": "💧", "mindset": "🧠", "mindfulness": "🫧",
        "outdoors": "🌲", "hiking": "🥾", "climbing": "🧗", "cycling": "🚴",
        "swimming": "🏊", "stretching": "🤸", "progress": "📈", "food": "🍜",
        "cooking": "🍳", "coffee": "☕️", "books": "📚", "music": "🎵",
        "movies": "🎬", "tv": "📺", "gaming": "🎮", "art": "🎨",
        "photography": "📸", "travel": "✈️", "fashion": "👗", "tech": "💻",
        "pets": "🐾", "faith": "🙏", "business": "💼", "basketball": "🏀",
        "soccer": "⚽️", "football": "🏈", "tennis": "🎾", "golf": "⛳️"
    ]

    /// Canonical list. Names mirror the onboarding `allInterests` list so
    /// the user's picked interests automatically land in "Your communities".
    nonisolated static let catalog: [WhisperCommunity] = [
        // Linked-accounts-only lounge — anyone sees it in the list, the feed
        // opens once the Jasper account link exists. Posts wear the ember glow.
        .init(id: "jasper-circle", name: "Jasper Circle",
              tagline: "The linked-account lounge — train, track, and talk with Jasper's people.",
              symbol: "flame.fill", keywords: ["jasper", "jaspercircle", "jasper circle", "jasperapp"],
              gradient: [Color(red: 0.98, green: 0.45, blue: 0.09), Color(red: 1.00, green: 0.72, blue: 0.40)],
              specialReact: "👻", requiresJasperLink: true),
        .init(id: "dating", name: "Dating",
              tagline: "Meet someone real — it starts with a whisper.",
              symbol: "heart.fill",
              keywords: ["dating", "single", "date night", "first date", "situationship", "meet someone", "relationship"],
              gradient: [Color(red: 0.91, green: 0.28, blue: 0.49), Color(red: 1.00, green: 0.62, blue: 0.72)]),
        .init(id: "workouts", name: "Workouts", tagline: "Daily splits, PRs, and program drops.",
              symbol: "dumbbell.fill", keywords: ["workout", "lift", "session", "gym"],
              gradient: [Color(red: 0.98, green: 0.50, blue: 0.20), Color(red: 1.00, green: 0.72, blue: 0.42)]),
        .init(id: "running", name: "Running", tagline: "Long runs, intervals, race day.",
              symbol: "figure.run", keywords: ["run", "mile", "5k", "10k", "marathon", "pace"],
              gradient: [Color(red: 0.42, green: 0.62, blue: 0.92), Color(red: 0.55, green: 0.82, blue: 0.96)]),
        .init(id: "yoga", name: "Yoga", tagline: "Slow flows, deep stretch, breath.",
              symbol: "figure.yoga", keywords: ["yoga", "flow", "asana"],
              gradient: [Color(red: 0.52, green: 0.84, blue: 0.86), Color(red: 0.86, green: 0.92, blue: 0.62)]),
        .init(id: "mobility", name: "Mobility", tagline: "Move better. Stay durable.",
              symbol: "figure.cooldown", keywords: ["mobility", "stretch", "warmup", "cooldown"],
              gradient: [Color(red: 0.76, green: 0.55, blue: 0.92), Color(red: 0.52, green: 0.84, blue: 0.86)]),
        .init(id: "lifting", name: "Lifting", tagline: "Strength, hypertrophy, the iron.",
              symbol: "figure.strengthtraining.traditional", keywords: ["lift", "lifting", "squat", "deadlift", "bench", "press"],
              gradient: [Color(red: 0.20, green: 0.20, blue: 0.22), Color(red: 0.55, green: 0.55, blue: 0.60)]),
        .init(id: "hiit", name: "HIIT", tagline: "Short. Hard. Done.",
              symbol: "bolt.fill", keywords: ["hiit", "interval", "circuit"],
              gradient: [Color(red: 0.96, green: 0.30, blue: 0.40), Color(red: 1.00, green: 0.62, blue: 0.32)]),
        .init(id: "recovery", name: "Recovery", tagline: "Rest is part of the program.",
              symbol: "leaf.fill", keywords: ["recovery", "rest", "deload"],
              gradient: [Color(red: 0.49, green: 0.78, blue: 0.55), Color(red: 0.86, green: 0.92, blue: 0.62)]),
        .init(id: "sleep", name: "Sleep", tagline: "Lights out. Real gains.",
              symbol: "moon.stars.fill", keywords: ["sleep", "rest", "rem"],
              gradient: [Color(red: 0.18, green: 0.20, blue: 0.45), Color(red: 0.55, green: 0.50, blue: 0.92)]),
        .init(id: "nutrition", name: "Nutrition", tagline: "Meals, macros, the plate.",
              symbol: "fork.knife", keywords: ["nutrition", "meal", "macro", "protein", "calorie"],
              gradient: [Color(red: 0.96, green: 0.55, blue: 0.32), Color(red: 1.00, green: 0.78, blue: 0.42)]),
        .init(id: "hydration", name: "Hydration", tagline: "Drink first. Talk later.",
              symbol: "drop.fill", keywords: ["hydrat", "water", "electrolyte"],
              gradient: [Color(red: 0.30, green: 0.70, blue: 0.92), Color(red: 0.62, green: 0.92, blue: 0.96)]),
        .init(id: "mindset", name: "Mindset", tagline: "Hard things, done daily.",
              symbol: "brain.head.profile", keywords: ["mindset", "discipline", "grit"],
              gradient: [Color(red: 0.18, green: 0.18, blue: 0.22), Color(red: 0.78, green: 0.50, blue: 0.92)]),
        .init(id: "mindfulness", name: "Mindfulness", tagline: "Breath, presence, quiet wins.",
              symbol: "sparkles", keywords: ["mindful", "meditat", "breath"],
              gradient: [Color(red: 0.78, green: 0.50, blue: 0.92), Color(red: 0.96, green: 0.78, blue: 0.92)]),
        .init(id: "outdoors", name: "Outdoors", tagline: "Trail, mountain, salt air.",
              symbol: "tree.fill", keywords: ["outdoor", "trail", "nature"],
              gradient: [Color(red: 0.20, green: 0.50, blue: 0.32), Color(red: 0.76, green: 0.88, blue: 0.50)]),
        .init(id: "hiking", name: "Hiking", tagline: "Type-2 fun, peaks bagged.",
              symbol: "figure.hiking", keywords: ["hike", "trail", "summit"],
              gradient: [Color(red: 0.35, green: 0.55, blue: 0.35), Color(red: 0.82, green: 0.72, blue: 0.45)]),
        .init(id: "climbing", name: "Climbing", tagline: "Send it. Send it again.",
              symbol: "figure.climbing", keywords: ["climb", "boulder", "send", "crux"],
              gradient: [Color(red: 0.55, green: 0.25, blue: 0.20), Color(red: 0.96, green: 0.62, blue: 0.42)]),
        .init(id: "cycling", name: "Cycling", tagline: "Watts, wheels, long rides.",
              symbol: "bicycle", keywords: ["cycle", "cycling", "bike", "ride", "watts"],
              gradient: [Color(red: 0.25, green: 0.45, blue: 0.65), Color(red: 0.62, green: 0.84, blue: 0.96)]),
        .init(id: "swimming", name: "Swimming", tagline: "Laps, open water, breath sets.",
              symbol: "figure.pool.swim", keywords: ["swim", "pool", "open water"],
              gradient: [Color(red: 0.20, green: 0.50, blue: 0.72), Color(red: 0.52, green: 0.84, blue: 0.86)]),
        .init(id: "stretching", name: "Stretching", tagline: "Lengthen. Soften. Stay.",
              symbol: "figure.flexibility", keywords: ["stretch", "flex", "mobility"],
              gradient: [Color(red: 0.86, green: 0.55, blue: 0.62), Color(red: 0.96, green: 0.78, blue: 0.62)]),
        .init(id: "progress", name: "Progress", tagline: "Befores, afters, the long arc.",
              symbol: "chart.line.uptrend.xyaxis", keywords: ["progress", "transformation", "before", "after"],
              gradient: [Color(red: 0.49, green: 0.78, blue: 0.55), Color(red: 0.42, green: 0.62, blue: 0.92)]),
        // -- Lifestyle & general communities (Threads-style topic hubs) --
        .init(id: "food", name: "Food", tagline: "What you cooked, what you crave.",
              symbol: "fork.knife.circle.fill", keywords: ["food", "meal", "recipe", "dinner", "breakfast", "lunch", "snack"],
              gradient: [Color(red: 0.98, green: 0.42, blue: 0.32), Color(red: 1.00, green: 0.78, blue: 0.42)]),
        .init(id: "cooking", name: "Cooking", tagline: "Home kitchen, slow Sundays.",
              symbol: "flame.fill", keywords: ["cook", "cooking", "chef", "baking", "bake", "recipe"],
              gradient: [Color(red: 0.85, green: 0.45, blue: 0.30), Color(red: 0.95, green: 0.75, blue: 0.55)]),
        .init(id: "coffee", name: "Coffee", tagline: "Beans, brews, slow mornings.",
              symbol: "cup.and.saucer.fill", keywords: ["coffee", "espresso", "latte", "barista", "brew"],
              gradient: [Color(red: 0.40, green: 0.25, blue: 0.18), Color(red: 0.78, green: 0.55, blue: 0.38)]),
        .init(id: "books", name: "Books", tagline: "What you're reading right now.",
              symbol: "book.closed.fill", keywords: ["book", "reading", "novel", "chapter", "author"],
              gradient: [Color(red: 0.55, green: 0.35, blue: 0.62), Color(red: 0.92, green: 0.78, blue: 0.55)]),
        .init(id: "music", name: "Music", tagline: "Albums, playlists, live shows.",
              symbol: "music.note", keywords: ["music", "song", "album", "playlist", "concert", "band"],
              gradient: [Color(red: 0.92, green: 0.30, blue: 0.62), Color(red: 0.55, green: 0.38, blue: 0.92)]),
        .init(id: "movies", name: "Movies", tagline: "Theatre nights and deep cuts.",
              symbol: "film.fill", keywords: ["movie", "film", "cinema", "theatre"],
              gradient: [Color(red: 0.18, green: 0.18, blue: 0.30), Color(red: 0.78, green: 0.20, blue: 0.32)]),
        .init(id: "tv", name: "TV & Streaming", tagline: "Shows, finales, hot takes.",
              symbol: "tv.fill", keywords: ["tv", "show", "series", "netflix", "hbo", "hulu"],
              gradient: [Color(red: 0.20, green: 0.30, blue: 0.55), Color(red: 0.62, green: 0.50, blue: 0.92)]),
        .init(id: "gaming", name: "Gaming", tagline: "Runs, raids, ranked grinds.",
              symbol: "gamecontroller.fill", keywords: ["game", "gaming", "playstation", "xbox", "steam", "valorant", "fortnite"],
              gradient: [Color(red: 0.25, green: 0.55, blue: 0.92), Color(red: 0.55, green: 0.30, blue: 0.92)]),
        .init(id: "anime", name: "Anime", tagline: "Seasonal drops, manga, lore.",
              symbol: "play.tv.fill", keywords: ["anime", "manga", "otaku", "shonen"],
              gradient: [Color(red: 0.95, green: 0.40, blue: 0.62), Color(red: 0.55, green: 0.62, blue: 0.95)]),
        .init(id: "sports", name: "Sports", tagline: "Game day, every day.",
              symbol: "sportscourt.fill", keywords: ["sports", "game", "team", "season"],
              gradient: [Color(red: 0.20, green: 0.50, blue: 0.92), Color(red: 0.55, green: 0.92, blue: 0.62)]),
        .init(id: "basketball", name: "Basketball", tagline: "Buckets, plays, league nights.",
              symbol: "basketball.fill", keywords: ["basketball", "nba", "hoops", "dunk"],
              gradient: [Color(red: 0.92, green: 0.45, blue: 0.20), Color(red: 0.55, green: 0.20, blue: 0.20)]),
        .init(id: "football", name: "Football", tagline: "Touchdowns, tailgates, fantasy.",
              symbol: "football.fill", keywords: ["football", "nfl", "touchdown", "superbowl"],
              gradient: [Color(red: 0.20, green: 0.35, blue: 0.20), Color(red: 0.62, green: 0.85, blue: 0.42)]),
        .init(id: "soccer", name: "Soccer", tagline: "The beautiful game.",
              symbol: "soccerball", keywords: ["soccer", "football", "futbol", "premier", "laliga", "messi", "ronaldo"],
              gradient: [Color(red: 0.15, green: 0.55, blue: 0.30), Color(red: 0.55, green: 0.92, blue: 0.62)]),
        .init(id: "travel", name: "Travel", tagline: "Cities, road trips, jet lag.",
              symbol: "airplane", keywords: ["travel", "trip", "flight", "vacation", "holiday"],
              gradient: [Color(red: 0.30, green: 0.62, blue: 0.92), Color(red: 0.92, green: 0.72, blue: 0.42)]),
        .init(id: "photography", name: "Photography", tagline: "Frames, light, slow shutters.",
              symbol: "camera.fill", keywords: ["photo", "photography", "camera", "shot", "lens"],
              gradient: [Color(red: 0.18, green: 0.18, blue: 0.22), Color(red: 0.86, green: 0.78, blue: 0.62)]),
        .init(id: "art", name: "Art", tagline: "Sketches, studies, finished pieces.",
              symbol: "paintpalette.fill", keywords: ["art", "drawing", "painting", "sketch", "illustration"],
              gradient: [Color(red: 0.96, green: 0.62, blue: 0.42), Color(red: 0.92, green: 0.30, blue: 0.62)]),
        .init(id: "design", name: "Design", tagline: "UI, type, the craft.",
              symbol: "square.on.square.dashed", keywords: ["design", "ui", "ux", "figma", "typography"],
              gradient: [Color(red: 0.95, green: 0.50, blue: 0.32), Color(red: 0.30, green: 0.30, blue: 0.55)]),
        .init(id: "fashion", name: "Fashion", tagline: "Fits, drops, archive finds.",
              symbol: "tshirt.fill", keywords: ["fashion", "fit", "outfit", "style", "ootd"],
              gradient: [Color(red: 0.18, green: 0.18, blue: 0.22), Color(red: 0.78, green: 0.42, blue: 0.55)]),
        .init(id: "beauty", name: "Beauty", tagline: "Skin, hair, daily rituals.",
              symbol: "sparkles", keywords: ["beauty", "makeup", "skincare", "haircare"],
              gradient: [Color(red: 0.95, green: 0.65, blue: 0.78), Color(red: 0.98, green: 0.85, blue: 0.62)]),
        .init(id: "tech", name: "Tech", tagline: "Gadgets, launches, hot takes.",
              symbol: "laptopcomputer", keywords: ["tech", "apple", "iphone", "android", "gadget"],
              gradient: [Color(red: 0.20, green: 0.30, blue: 0.45), Color(red: 0.55, green: 0.75, blue: 0.95)]),
        .init(id: "ai", name: "AI", tagline: "Models, prompts, the new wave.",
              symbol: "brain.head.profile", keywords: ["ai", "gpt", "chatgpt", "claude", "gemini", "llm"],
              gradient: [Color(red: 0.18, green: 0.50, blue: 0.92), Color(red: 0.55, green: 0.30, blue: 0.92)]),
        .init(id: "coding", name: "Coding", tagline: "Side projects, bugs, ships.",
              symbol: "chevron.left.forwardslash.chevron.right", keywords: ["code", "coding", "developer", "swift", "react", "python"],
              gradient: [Color(red: 0.20, green: 0.20, blue: 0.30), Color(red: 0.42, green: 0.85, blue: 0.62)]),
        .init(id: "startups", name: "Startups", tagline: "Builders, launches, lessons.",
              symbol: "flame.fill", keywords: ["startup", "founder", "launch", "yc", "vc"],
              gradient: [Color(red: 0.96, green: 0.45, blue: 0.20), Color(red: 0.55, green: 0.30, blue: 0.78)]),
        .init(id: "finance", name: "Finance", tagline: "Money moves, slow and steady.",
              symbol: "chart.bar.fill", keywords: ["finance", "money", "invest", "stocks", "crypto", "budget"],
              gradient: [Color(red: 0.18, green: 0.45, blue: 0.30), Color(red: 0.62, green: 0.92, blue: 0.55)]),
        .init(id: "business", name: "Business", tagline: "Operating, selling, growing.",
              symbol: "briefcase.fill", keywords: ["business", "sales", "marketing", "growth"],
              gradient: [Color(red: 0.22, green: 0.30, blue: 0.45), Color(red: 0.62, green: 0.72, blue: 0.92)]),
        .init(id: "productivity", name: "Productivity", tagline: "Systems, focus, deep work.",
              symbol: "checkmark.circle.fill", keywords: ["productivity", "focus", "deep work", "system", "workflow"],
              gradient: [Color(red: 0.20, green: 0.30, blue: 0.55), Color(red: 0.55, green: 0.85, blue: 0.95)]),
        .init(id: "study", name: "Study", tagline: "Notes, deadlines, lock-ins.",
              symbol: "graduationcap.fill", keywords: ["study", "school", "college", "university", "exam", "finals"],
              gradient: [Color(red: 0.30, green: 0.30, blue: 0.62), Color(red: 0.92, green: 0.78, blue: 0.42)]),
        .init(id: "languages", name: "Languages", tagline: "Learning, slowly then suddenly.",
              symbol: "character.book.closed.fill", keywords: ["language", "duolingo", "spanish", "french", "japanese", "korean"],
              gradient: [Color(red: 0.42, green: 0.62, blue: 0.92), Color(red: 0.96, green: 0.62, blue: 0.42)]),
        .init(id: "mentalhealth", name: "Mental Health", tagline: "Quiet wins, hard days, honest talk.",
              symbol: "heart.text.square.fill", keywords: ["mental health", "anxiety", "therapy", "depression", "selfcare"],
              gradient: [Color(red: 0.78, green: 0.85, blue: 0.95), Color(red: 0.55, green: 0.72, blue: 0.92)]),
        .init(id: "parenting", name: "Parenting", tagline: "Tiny humans, big questions.",
              symbol: "figure.and.child.holdinghands", keywords: ["parent", "parenting", "baby", "toddler", "kids", "mom", "dad"],
              gradient: [Color(red: 0.96, green: 0.78, blue: 0.62), Color(red: 0.78, green: 0.62, blue: 0.92)]),
        .init(id: "pets", name: "Pets", tagline: "Dogs, cats, the whole zoo.",
              symbol: "pawprint.fill", keywords: ["pet", "dog", "cat", "puppy", "kitten"],
              gradient: [Color(red: 0.92, green: 0.65, blue: 0.42), Color(red: 0.78, green: 0.92, blue: 0.62)]),
        .init(id: "plants", name: "Plants", tagline: "Repots, propagations, leaf goals.",
              symbol: "leaf.fill", keywords: ["plant", "houseplant", "garden", "gardening", "monstera"],
              gradient: [Color(red: 0.30, green: 0.55, blue: 0.32), Color(red: 0.78, green: 0.92, blue: 0.55)]),
        .init(id: "diy", name: "DIY", tagline: "Hands on, weekend builds.",
              symbol: "hammer.fill", keywords: ["diy", "build", "woodwork", "makerspace", "project"],
              gradient: [Color(red: 0.55, green: 0.35, blue: 0.20), Color(red: 0.96, green: 0.72, blue: 0.42)]),
        .init(id: "cars", name: "Cars", tagline: "Builds, drives, garage life.",
              symbol: "car.fill", keywords: ["car", "cars", "auto", "driving", "mod"],
              gradient: [Color(red: 0.18, green: 0.18, blue: 0.22), Color(red: 0.92, green: 0.30, blue: 0.32)]),
        .init(id: "motorcycles", name: "Motorcycles", tagline: "Two wheels, open road.",
              symbol: "motorcycle", keywords: ["motorcycle", "moto", "bike", "rider"],
              gradient: [Color(red: 0.22, green: 0.22, blue: 0.30), Color(red: 0.96, green: 0.62, blue: 0.20)]),
        .init(id: "comedy", name: "Comedy", tagline: "Shitposts and stand-up.",
              symbol: "face.smiling.inverse", keywords: ["comedy", "funny", "meme", "joke", "standup"],
              gradient: [Color(red: 0.98, green: 0.78, blue: 0.30), Color(red: 0.96, green: 0.42, blue: 0.62)]),
        .init(id: "news", name: "News", tagline: "What just happened.",
              symbol: "newspaper.fill", keywords: ["news", "politics", "world", "current events"],
              gradient: [Color(red: 0.18, green: 0.20, blue: 0.22), Color(red: 0.55, green: 0.55, blue: 0.58)]),
        .init(id: "science", name: "Science", tagline: "Papers, space, weird discoveries.",
              symbol: "atom", keywords: ["science", "physics", "space", "nasa", "research"],
              gradient: [Color(red: 0.18, green: 0.20, blue: 0.45), Color(red: 0.42, green: 0.78, blue: 0.95)]),
        .init(id: "philosophy", name: "Philosophy", tagline: "Big questions, quiet answers.",
              symbol: "text.book.closed.fill", keywords: ["philosophy", "stoic", "existential", "thinking"],
              gradient: [Color(red: 0.30, green: 0.25, blue: 0.35), Color(red: 0.78, green: 0.72, blue: 0.62)]),
        .init(id: "history", name: "History", tagline: "Then. And what it tells us now.",
              symbol: "scroll.fill", keywords: ["history", "ancient", "empire", "medieval"],
              gradient: [Color(red: 0.55, green: 0.40, blue: 0.22), Color(red: 0.92, green: 0.78, blue: 0.55)]),
        .init(id: "home", name: "Home", tagline: "Spaces, decor, slow upgrades.",
              symbol: "house.fill", keywords: ["home", "decor", "interior", "apartment", "house"],
              gradient: [Color(red: 0.78, green: 0.65, blue: 0.55), Color(red: 0.96, green: 0.92, blue: 0.85)]),
        .init(id: "writing", name: "Writing", tagline: "Drafts, edits, ship the thing.",
              symbol: "square.and.pencil", keywords: ["writing", "writer", "essay", "poem", "novel"],
              gradient: [Color(red: 0.20, green: 0.20, blue: 0.30), Color(red: 0.78, green: 0.62, blue: 0.92)])
    ]
}
