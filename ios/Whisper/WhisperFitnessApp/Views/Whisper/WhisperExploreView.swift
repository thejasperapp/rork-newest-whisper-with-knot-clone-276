import SwiftUI

/// Search — Threads-style discovery surface. Search field pinned at the
/// top queries Whisper users; below it the screen layers four rails:
///   1. Communities entry — link into the topic hubs.
///   2. Trending topics — chip cloud sourced from real post hashtags.
///   3. Trending posts — top liked posts in the last 7 days, horizontal.
///   4. Suggested users — accounts to follow you don't already follow.
struct WhisperExploreView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var query: String = ""
    @State private var lastAutomaticRefresh: Date?
    @State private var showAlgorithm: Bool = false
    @State private var showKnotProfile = false
    @State private var tuning = WhisperAlgorithmPreferences.shared
    @State private var contentWidth: CGFloat = 390
    @State private var moderation = WhisperModerationService.shared
    @State private var users = WhisperUserService.shared
    @State private var follows = WhisperFollowService.shared
    @State private var backend = WhisperBackendService.shared
    @State private var coach = WhisperCoachService.shared
    @State private var director = WhisperDirectorService.shared
    @State private var results: [WhisperUserRow] = []
    @State private var suggested: [WhisperUserRow] = []
    @State private var hashtagResults: [WhisperPost] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var searchPending: Bool = false
    @State private var searchError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var openPost: WhisperPost?
    /// A wave tapped on the Discover Waves rail — opens the full-screen Waves
    /// player on that wave with the rest of the loaded waves queued behind.
    @State private var openWave: WhisperPost?
    @State private var presentFindFriends: Bool = false
    @State private var spotlightProfiles: [WhisperFeaturedProfile] = []
    @State private var openSpotlight: WhisperFeaturedProfile?
    @State private var featured = WhisperFeaturedService.shared
    @State private var brands: [WhisperBrandProfile] = []
    @State private var openBrand: WhisperBrandProfile?
    @State private var presentBrandDirectory: Bool = false
    /// AI one-liners for the "Trending now" rail, keyed by community name.
    /// Local caption snippets render immediately; these swap in when ready.
    @State private var trendingSummaries: [String: String] = [:]
    @State private var trendingSummarizing: Bool = false
    @State private var showAllTrending: Bool = false
    @State private var exploreFilter: String = "For you"
    @State private var ember = WhisperEmberService.shared
    /// Collapsing header state — the title + search bar slide away on
    /// scroll down and return on any scroll up (Instagram/Threads chrome).
    @Environment(\.whisperHeaderShelf) private var headerShelf
    @Environment(\.whisperRootChromeActive) private var rootChromeActive
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var headerHeight: CGFloat = 104
    @FocusState private var searchFocused: Bool

    private var headerHidden: Bool { headerShelf?.isHidden ?? false }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool { !trimmedQuery.isEmpty }

    private var matchesKnot: Bool {
        let token = trimmedQuery.lowercased()
        return token == "knot" || token == "@knot"
    }

    /// True when the query starts with `#` — we route to caption search
    /// instead of usernames so tags surface their posts.
    private var isHashtagQuery: Bool { trimmedQuery.hasPrefix("#") }

    /// The bare tag text (no `#`) lowercased for case-insensitive matching.
    private var hashtagToken: String {
        trimmedQuery.dropFirst().lowercased()
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                WhisperTheme.card(colorScheme).ignoresSafeArea()
                GeometryReader { viewport in
                ScrollView {
                    VStack(spacing: 24) {
                        if isSearching {
                            searchResults
                        } else {
                            quickChipsRow
                            trendingPostsSection
                            trendingNowSection
                            suggestedSection
                            brandsSection
                            Color.clear.frame(height: 24)
                        }
                    }
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                    .frame(minHeight: max(0, viewport.size.height - headerHeight), alignment: .top)
                    .modifier(WhisperStoriesForeground())
                }
                .contentMargins(.top, headerHeight + viewport.safeAreaInsets.top, for: .scrollContent)
                .ignoresSafeArea(.container, edges: .top)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
                .scrollDismissesKeyboard(.immediately)
                .task { rebuildMosaic() }
                .onChange(of: mosaicSignature) { _, _ in rebuildMosaic() }
                .onChange(of: exploreFilter) { _, _ in rebuildMosaic() }
                .onScrollGeometryChange(for: CGFloat.self) { geo in
                    geo.contentOffset.y + geo.contentInsets.top
                } action: { oldValue, newValue in
                    guard rootChromeActive else { return }
                    headerShelf?.updateOverlap(newValue)
                    guard !voiceOver else { return }
                    // Keep the header pinned while the user is searching —
                    // hiding the field they're typing into would be hostile.
                    if isSearching || searchFocused {
                        headerShelf?.reveal()
                        return
                    }
                    headerShelf?.update(old: oldValue, new: newValue, enabled: true)
                }
                .whisperRefreshable {
                    await refresh()
                }
                }

                discoverHeader
            }
            .overlay {
                WhisperStatusBarBackdrop(color: WhisperTheme.card(colorScheme), blurred: true, blurProgress: headerShelf?.blurProgress ?? 0)
                    .ignoresSafeArea(edges: .top).allowsHitTesting(false).accessibilityHidden(true)
            }
            .background(WhisperNavigationPreview())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: WhisperUserRow.self) { user in
                WhisperUserProfileView(user: user)
            }
            .navigationDestination(for: WhisperCommunity.self) { c in
                WhisperCommunityDetailView(community: c)
            }
            .navigationDestination(for: CommunitiesRoute.self) { _ in
                WhisperCommunitiesView()
            }
            .sheet(isPresented: $showKnotProfile) {
                WhisperKnotProfileView()
            }
            .sheet(isPresented: $presentFindFriends) {
                WhisperFindFriendsView()
            }
            .sheet(item: $openSpotlight) { profile in
                WhisperFeaturedProfileDetailView(profile: profile)
            }
            .sheet(item: $openBrand) { brand in
                WhisperBrandDetailView(brand: brand)
            }
            .fullScreenCover(isPresented: $presentBrandDirectory) {
                WhisperBrandDirectoryView()
            }
            // Use the full post-detail view (with comments + composer) on a
            // navigation push so a hashtag-result tap matches every other
            // post-open entry point in the app instead of opening a half
            // “preview” sheet with its own Close button.
            .fullScreenCover(item: $openPost) { post in
                WhisperPostDetailView(post: post)
            }
            .fullScreenCover(isPresented: $showAlgorithm, onDismiss: { rebuildMosaic() }) {
                WhisperAlgorithmView(pool: realPool)
            }
            .fullScreenCover(item: $openWave, onDismiss: { rebuildMosaic() }) { wave in
                // Waves render ONLY in the Waves format — the tapped wave first,
                // every other loaded wave queued behind it.
                let pool = WhisperAlgorithmService.wavesRank(realPool.filter { $0.isReel && !$0.mediaURLs.isEmpty })
                WhisperReelsPlayerView(reels: pool.isEmpty ? [wave] : pool, start: wave)
            }
            .task(id: rootChromeActive) {
                guard rootChromeActive,
                      lastAutomaticRefresh.map({ Date().timeIntervalSince($0) > 60 }) ?? true else { return }
                await refresh(force: false)
                guard !Task.isCancelled else { return }
                lastAutomaticRefresh = Date()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
                searchTask?.cancel(); searchPending = false
            }
            .onChange(of: query) { _, new in
                searchTask?.cancel()
                let q = new.trimmingCharacters(in: .whitespacesAndNewlines)
                let generation = AccountStorage.generation
                searchPending = !q.isEmpty; searchError = nil
                results = []; hashtagResults = []; spotlightProfiles = []
                guard !q.isEmpty else {
                    results = []
                    hashtagResults = []
                    spotlightProfiles = []
                    return
                }
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(220))
                    guard !Task.isCancelled, generation == AccountStorage.generation, trimmedQuery == q else { return }
                    if q.hasPrefix("#") {
                        let tag = String(q.dropFirst()).lowercased()
                        // Search cached posts — caption-contains match.
                        let pool = realPool.filter {
                            $0.caption.lowercased().contains("#\(tag)")
                                || $0.caption.lowercased().contains(tag)
                        }
                        hashtagResults = pool; searchPending = false
                    } else {
                        let rows = await users.search(q)
                        guard !Task.isCancelled, generation == AccountStorage.generation, trimmedQuery == q else { return }
                        // First useful result paints before optional badges and catalogs.
                        results = rows
                        searchPending = false
                        searchError = users.searchError
                        // Hydrate role statuses (coach / director / verified)
                        // and fetch the featured spotlight catalog for all
                        // kinds CONCURRENTLY — one round trip of latency
                        // instead of sequential awaits.
                        let names = rows.map { $0.username }
                        let userIDs = rows.map { $0.user_id }
                        async let coachHydration: Void = coach.ensureCoachStatuses(usernames: names)
                        async let directorHydration: Void = director.preload(userIDs: userIDs)
                        async let badgeHydration: Void = UserVerificationService.shared.preload(usernames: names)
                        async let coachFeatured = featured.fetchProfiles(kind: .coach)
                        async let creatorFeatured = featured.fetchProfiles(kind: .creator)
                        async let directorFeatured = featured.fetchProfiles(kind: .director)
                        let allFeatured = await coachFeatured + creatorFeatured + directorFeatured
                        _ = await (coachHydration, directorHydration, badgeHydration)
                        guard !Task.isCancelled, generation == AccountStorage.generation, trimmedQuery == q else { return }
                        let lowerQ = q.lowercased()
                        let resultNames = Set(rows.map { $0.username.lowercased() })
                        let matching = allFeatured.filter { profile in
                            let matches = profile.name.lowercased().contains(lowerQ)
                                || (profile.username?.lowercased().contains(lowerQ) ?? false)
                                || (profile.discipline?.lowercased().contains(lowerQ) ?? false)
                                || (profile.chips?.contains { $0.lowercased().contains(lowerQ) } ?? false)
                            // Users already in the results get their featured
                            // data folded into their spotlight card — skip
                            // the duplicate rail entry.
                            let duplicate = profile.username.map { resultNames.contains($0.lowercased()) } ?? false
                            return matches && !duplicate
                        }
                        await MainActor.run {
                            spotlightProfiles = matching
                        }
                    }
                }
            }
        }
    }

    /// Hashable placeholder used to push the Communities index from the
    /// "See all" link without conflicting with `WhisperCommunity` values.
    private struct CommunitiesRoute: Hashable {}

    // MARK: - Collapsing header

    /// Large "Search" title + search field pinned over the scroll view.
    /// Slides up and fades when the user scrolls down; returns on any
    /// upward scroll so the chrome never feels intrusive.
    private var discoverHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Discover")
                    .font(.system(size: 30, weight: .bold))
                Spacer()
                Button {
                    Haptics.tap()
                    showAlgorithm = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 21, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Your algorithm")
            }
            .foregroundStyle(WhisperTheme.ink(colorScheme))
            .padding(.horizontal, 16)
            searchField
        }
        .padding(.top, 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { WhisperScrollingHeaderBackdrop() }
        .background { Color.clear.contentShape(.rect).onTapGesture { } }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newValue in
            if newValue > 0, abs(newValue - headerHeight) > 1 {
                headerHeight = newValue
            }
        }
        .offset(y: headerHidden && !voiceOver ? -headerHeight : 0)
        .clipped()
        .allowsHitTesting(!headerHidden || voiceOver)
        .accessibilityHidden(headerHidden && !voiceOver)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: headerHidden)
    }

    // MARK: - Data

    private func refresh(force: Bool = true) async {
        let generation = AccountStorage.generation
        // First wave in parallel — moderation, follows, posts, suggestions,
        // and the brands rail all fetch concurrently so Discover paints in
        // one round trip instead of five.
        async let m: Void = moderation.refresh()
        async let f: Void = force ? follows.refresh() : follows.refreshIfStale()
        async let p: Void = force ? backend.fetchPosts() : backend.fetchPostsIfStale()
        async let sugg = users.suggestions(limit: 12)
        async let fetchedBrands = try? WhisperBrandService.shared.fetchBrands()
        let suggestions = await sugg
        guard !Task.isCancelled, generation == AccountStorage.generation else { return }
        suggested = suggestions
        _ = await (m, f, p)
        guard !Task.isCancelled, generation == AccountStorage.generation else { return }
        // Trending AI summaries are TAP-ONLY now (the "AI summary" chip in
        // the header) — Discover paints with local snippets and never
        // spends credits in the background.
        // Sponsor brands rail — published brands surface on Discover so
        // creators/athletes stumble into sponsorship opportunities.
        if let fetched = await fetchedBrands {
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            brands = fetched
        }
        guard !Task.isCancelled, generation == AccountStorage.generation else { return }
        let suggestedNames = suggested.map { $0.username }
        let suggestedIDs = suggested.map { $0.user_id }
        // Hydrate badges for the trending rail so verified / liar / safety
        // chips render in the first frame instead of popping in.
        let trendingUsernames = Array(Set(trendingPosts.map { $0.username })).filter { !$0.isEmpty }
        let trendingUserIDs = Array(Set(backend.posts.map { $0.user_id })).filter { !$0.isEmpty }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await WhisperCoachService.shared.ensureCoachStatuses(usernames: suggestedNames) }
            group.addTask { await WhisperDirectorService.shared.preload(userIDs: suggestedIDs) }
            group.addTask { await UserVerificationService.shared.preload(usernames: trendingUsernames) }
            group.addTask { await WhisperLiarLiarService.shared.preload(usernames: trendingUsernames) }
            group.addTask { await WhisperSafetyService.shared.preloadAgeBands(userIDs: trendingUserIDs) }
            group.addTask {
                await WhisperSafetyService.shared.preloadWatchFlags(userIDs: trendingUserIDs, usernames: trendingUsernames)
            }
        }
    }

    /// Real backend posts mapped to `WhisperPost` for trending rails.
    private var realPool: [WhisperPost] {
        backend.posts.map { row in
            let urls: [URL] = (row.media_urls ?? []).compactMap { URL(string: $0) }
            return WhisperPost(
                id: UUID(uuidString: row.id) ?? UUID(),
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
    }

    /// Trending posts surfaced on Discover. Uses the personalized discover
    /// ranker so verified accounts + interest matches bubble up, then we
    /// drop anything older than 14 days so the rail stays fresh. Top 6 are
    /// rendered in the full post-card format (not small thumbnails) so the
    /// surface matches the rest of the app. (Filter window is 14 days —
    /// keeps the rail populated on lighter-volume accounts.)
    private var trendingPosts: [WhisperPost] {
        let me = WhisperUserService.shared.me
        let interests = me?.interests ?? []
        let followingNames = Set(follows.followingUsernames.values.map { $0.lowercased() })
        let coachNames = Set(coach.coachByUsername.compactMap { $0.value ? $0.key : nil })
        let pool = realPool.filter { WhisperAlgorithmService.hoursSinceCreation($0) <= 24 * 14 }
        return WhisperAlgorithmService.personalizedDiscoverRank(
            pool,
            interests: interests,
            followingUsernames: followingNames,
            coachUsernames: coachNames
        )
        .prefix(6)
        .map { $0 }
    }

    /// Top communities ranked by post count, falling back to the static
    /// catalog when the feed is still warm-up.
    private var trendingCommunities: [WhisperCommunity] {
        let catalog = WhisperCommunity.catalog
        let scored: [(WhisperCommunity, Int)] = catalog.map { c in
            // EXPLICIT-ONLY: only posts the author filed into the community count.
            let n = backend.posts.reduce(0) { acc, row in
                acc + ((row.community_id ?? "") == c.id ? 1 : 0)
            }
            return (c, n)
        }
        let withPosts = scored.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        if withPosts.isEmpty {
            return Array(catalog.prefix(8))
        }
        return Array(withPosts.prefix(8).map { $0.0 })
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.55))
            TextField("Search", text: $query)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
            if !query.isEmpty {
                Button {
                    Haptics.tap()
                    query = ""
                    results = []
                    hashtagResults = []
                    spotlightProfiles = []
                    searchTask?.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(WhisperTheme.card(colorScheme), in: Capsule())
        .overlay {
            Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var searchResults: some View {
        if isHashtagQuery {
            hashtagSearchResults
        } else {
            VStack(spacing: 20) {
                if matchesKnot {
                    Button {
                        searchFocused = false
                        showKnotProfile = true
                    } label: {
                        HStack(spacing: 12) {
                            WhisperKnotProfilePortrait(size: 56)
                            VStack(alignment: .leading, spacing: 4) {
                                WhisperKnotWordmark()
                                Text("Whisper’s AI assistant · @knot")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Knot, Whisper’s AI assistant. View profile")
                }
                spotlightUserSection(title: "Directors", pool: directorResults, kind: .director)
                spotlightUserSection(title: "Coaches", pool: coachResults, kind: .coach)
                spotlightUserSection(title: "Creators", pool: creatorResults, kind: .creator)
                spotlightSection
                userSearchResults
            }
        }
    }

    // MARK: - Spotlight result grouping

    /// Directors, coaches, and verified creators get rich spotlight cards at
    /// the top of search results — everyone else keeps the plain rows.
    /// Mirrors the web app's search grouping exactly.
    private var directorResults: [WhisperUserRow] {
        results.filter { director.isDirector(userID: $0.user_id) }
    }

    private var coachResults: [WhisperUserRow] {
        results.filter {
            !director.isDirector(userID: $0.user_id) && coach.isCoach(username: $0.username)
        }
    }

    private var creatorResults: [WhisperUserRow] {
        results.filter {
            !director.isDirector(userID: $0.user_id)
                && !coach.isCoach(username: $0.username)
                && UserVerificationService.shared.badge(forUsername: $0.username) == .verified
        }
    }

    private var plainResults: [WhisperUserRow] {
        results.filter {
            !director.isDirector(userID: $0.user_id)
                && !coach.isCoach(username: $0.username)
                && UserVerificationService.shared.badge(forUsername: $0.username) != .verified
        }
    }

    /// Full-width spotlight cards for one kind of special account.
    @ViewBuilder
    private func spotlightUserSection(title: String, pool: [WhisperUserRow], kind: FeaturedKind) -> some View {
        if !pool.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(title)
                VStack(spacing: 8) {
                    ForEach(pool) { u in
                        NavigationLink(value: u) {
                            WhisperUserSpotlightCard(user: u, kind: kind)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    /// Spotlight cards for featured coaches, athletes, and creators that
    /// match the search query. Mirrors the web app's coach/athlete/creator
    /// search filter — featured profiles show as rich cards at the top.
    @ViewBuilder
    private var spotlightSection: some View {
        if !spotlightProfiles.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Featured")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(spotlightProfiles) { profile in
                            Button {
                                Haptics.tap()
                                openSpotlight = profile
                            } label: {
                                WhisperFeaturedSpotlightCard(profile: profile)
                                    .frame(width: 250)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .contentMargins(.horizontal, 16, for: .scrollContent)
                }
            }
        }
    }

    @ViewBuilder
    private var hashtagSearchResults: some View {
        if hashtagResults.isEmpty {
            VStack(spacing: 6) {
                WhisperMeetDoodle(symbol: "number", height: 120)
                Text("No posts tagged #\(hashtagToken)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("Be the first to post one.")
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(.top, 40)
            .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("#\(hashtagToken) · \(hashtagResults.count) post\(hashtagResults.count == 1 ? "" : "s")")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .padding(.horizontal, 16)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
                    ForEach(hashtagResults) { post in
                        Button {
                            Haptics.tap()
                            openPost = post
                        } label: {
                            hashtagPostCell(post)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func hashtagPostCell(_ post: WhisperPost) -> some View {
        Color(.secondarySystemBackground)
            .aspectRatio(1, contentMode: .fill)
            .overlay {
                if let url = post.mediaURLs.first, !WhisperVideo.isVideo(url) {
                    WhisperSizedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().aspectRatio(contentMode: .fill).allowsHitTesting(false)
                        default:
                            LinearGradient(colors: [post.accent.opacity(0.95), post.accent.opacity(0.55)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        }
                    }
                } else {
                    LinearGradient(colors: [post.accent.opacity(0.95), post.accent.opacity(0.55)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay {
                            Image(systemName: post.symbol)
                                .font(.title3.weight(.heavy))
                                .foregroundStyle(.white.opacity(0.95))
                        }
                }
            }
            .clipped()
    }

    @ViewBuilder
    private var userSearchResults: some View {
        if searchPending && results.isEmpty {
            ProgressView()
                .tint(WhisperTheme.ink(colorScheme))
                .padding(.top, 32)
        } else if let searchError, results.isEmpty {
            ContentUnavailableView("Search couldn't load", systemImage: "wifi.exclamationmark", description: Text(searchError))
        } else if results.isEmpty && spotlightProfiles.isEmpty && !matchesKnot {
            VStack(spacing: 6) {
                WhisperMeetDoodle(symbol: "magnifyingglass", height: 120)
                Text("No Whisper users match \"\(trimmedQuery)\"")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text("Only people who've finished Whisper signup show up here.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(.top, 40)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
        } else if !plainResults.isEmpty {
            VStack(spacing: 0) {
                ForEach(plainResults) { user in
                    userRow(user)
                    Divider().background(WhisperTheme.hairline(colorScheme))
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private func userRow(_ user: WhisperUserRow) -> some View {
        let following = follows.isFollowing(userID: user.user_id)
        return NavigationLink(value: user) {
            HStack(spacing: 12) {
                WhisperAvatar(
                    username: user.username,
                    size: 48,
                    imageURL: user.profile_image_url.flatMap { URL(string: $0) }
                )
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(user.display_name?.isEmpty == false ? user.display_name! : user.username)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                        if coach.isCoach(username: user.username) {
                            WhisperCoachBadge(size: 11)
                        }
                    }
                    Text("@\(user.username)")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                    if let bio = user.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.caption)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                            .lineLimit(1)
                    }
                }
                Spacer()
                followButton(user: user, following: following)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func followButton(user: WhisperUserRow, following: Bool) -> some View {
        Button {
            Haptics.tap()
            Task {
                if following {
                    _ = await follows.unfollow(userID: user.user_id)
                } else {
                    _ = await follows.follow(userID: user.user_id, username: user.username)
                }
            }
        } label: {
            Text(following ? "Following" : "Follow")
                .font(.caption.weight(.bold))
                .foregroundStyle(following ? WhisperTheme.ink(colorScheme) : WhisperTheme.surface(colorScheme))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(following ? WhisperTheme.card(colorScheme) : WhisperTheme.ink(colorScheme), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: following ? 1 : 0)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quick chips (Threads-style filter row under the search bar)

    /// Three clear destinations above the editorial trending list and mosaic.
    /// Topics keep their own rows instead of competing as utility chips.
    private var quickChipsRow: some View {
        HStack(spacing: 0) {
            Button {
                Haptics.tap()
                presentFindFriends = true
            } label: {
                plainChip(icon: "person.2.fill", title: "Find friends")
            }
            .buttonStyle(.plain)

            NavigationLink(value: CommunitiesRoute()) {
                plainChip(icon: "person.3.fill", title: "Communities")
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                presentBrandDirectory = true
            } label: {
                plainChip(icon: "building.2.fill", title: "Brands")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func plainChip(icon: String, title: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.title3.weight(.medium))
            Text(title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(WhisperTheme.ink(colorScheme))
        .frame(maxWidth: .infinity, minHeight: 76)
        .contentShape(.rect)
    }

    // MARK: - Trending now (AI-summarized)

    /// One trending topic row's derived data — computed locally from the
    /// post cache so the section renders instantly; the AI summary swaps
    /// in over the caption snippet when the Jasper call returns.
    private struct TrendingNowItem: Identifiable {
        let community: WhisperCommunity
        let count: Int
        let fallbackSummary: String
        let thumbURL: URL?
        var id: String { community.name }
    }

    private var trendingNowItems: [TrendingNowItem] {
        let weekPool = realPool.filter { WhisperAlgorithmService.hoursSinceCreation($0) <= 24 * 7 }
        let source = weekPool.isEmpty ? realPool : weekPool
        guard !source.isEmpty else { return [] }
        var items: [TrendingNowItem] = []
        for c in WhisperCommunity.catalog {
            let matched = source.filter { $0.communityID == c.id }
            guard !matched.isEmpty else { continue }
            let top = matched.max { $0.likes < $1.likes }
            let snippet = (top?.caption ?? "")
                .replacingOccurrences(of: "#", with: "")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            items.append(TrendingNowItem(
                community: c,
                count: matched.count,
                fallbackSummary: snippet.isEmpty ? "People are posting in \(c.name)." : String(snippet.prefix(90)),
                thumbURL: matched.compactMap { $0.mediaURLs.first }.first { !WhisperVideo.isVideo($0) }
            ))
        }
        return items.sorted { $0.count > $1.count }
    }

    @ViewBuilder
    private var trendingNowSection: some View {
        let items = trendingNowItems
        if !items.isEmpty {
            let visible = showAllTrending ? items.prefix(10) : items.prefix(3)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center) {
                    Text("Trending now")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Spacer()
                    // Explicit tap — Jasper only summarizes when asked.
                    if trendingSummaries.isEmpty {
                        Button {
                            Haptics.tap()
                            guard !trendingSummarizing else { return }
                            trendingSummarizing = true
                            Task {
                                await loadTrendingSummaries()
                                await MainActor.run { trendingSummarizing = false }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                if trendingSummarizing {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                Text(trendingSummarizing ? "Reading…" : "AI summary")
                                    .font(.caption.weight(.bold))
                            }
                            .foregroundStyle(WhisperEmberPillPalette.glow)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(WhisperEmberPillPalette.glow.opacity(0.12), in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(WhisperEmberPillPalette.glow.opacity(0.35), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(trendingSummarizing)
                    }
                }
                .padding(.horizontal, 16)
                Text(trendingSummaries.isEmpty ? "What people are talking about" : "What people are saying, summarized by Jasper")
                    .font(.footnote)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)

                VStack(spacing: 0) {
                    ForEach(visible) { item in
                        NavigationLink(value: item.community) {
                            trendingNowRow(item)
                        }
                        .buttonStyle(.plain)
                        if item.id != visible.last?.id {
                            Divider()
                                .background(WhisperTheme.hairline(colorScheme))
                                .padding(.horizontal, 16)
                        }
                    }
                }

                if items.count > 3 {
                    Button {
                        Haptics.tap()
                        withAnimation(.whisperSnappy) { showAllTrending.toggle() }
                    } label: {
                        HStack(spacing: 5) {
                            Text(showAllTrending ? "Show less" : "Show more")
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: showAllTrending ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func trendingNowRow(_ item: TrendingNowItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.community.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                Text("\(trendingSummaries[item.community.name] ?? item.fallbackSummary) \u{00b7} \(item.count) post\(item.count == 1 ? "" : "s")")
                    .font(.footnote)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let url = item.thumbURL {
                Color(.secondarySystemBackground)
                    .frame(width: 52, height: 52)
                    .overlay {
                        WhisperSizedAsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .allowsHitTesting(false)
                            default:
                                Image(systemName: item.community.symbol)
                                    .font(.footnote)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                        }
                    }
                    .clipShape(.rect(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(.rect)
    }

    /// Fires one cached Jasper call to summarize the top trending topics.
    /// Best-effort: on failure the local caption snippets simply stay.
    private func loadTrendingSummaries() async {
        let items = Array(trendingNowItems.prefix(8))
        guard !items.isEmpty else { return }
        let topics: [(name: String, captions: [String])] = items.map { item in
            let caps = realPool
                .filter { $0.communityID == item.community.id }
                .prefix(6)
                .map { String($0.caption.prefix(140)) }
            return (name: item.community.name, captions: Array(caps))
        }
        let map = await ember.trendingSummaries(topics: topics)
        guard !map.isEmpty else { return }
        await MainActor.run {
            withAnimation(.whisperSmooth) { trendingSummaries = map }
        }
    }

    // MARK: - Sponsor brands rail

    /// Horizontal rail of published sponsor brands on the Discover surface.
    /// Tapping a card opens the full brand profile (requirements, pay
    /// transparency, apply); "See all" opens the directory.
    @ViewBuilder
    private var brandsSection: some View {
        if !brands.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Sponsor brands") {
                    presentBrandDirectory = true
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(brands) { brand in
                            Button {
                                Haptics.tap()
                                openBrand = brand
                            } label: {
                                brandRailCard(brand)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
            }
        }
    }

    private func brandRailCard(_ brand: WhisperBrandProfile) -> some View {
        HStack(spacing: 12) {
            Color(.secondarySystemBackground)
                .frame(width: 44, height: 44)
                .overlay {
                    if let url = WhisperFeaturedProfile.resolvePhotoURL(brand.logoUrl) {
                        WhisperSizedAsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .allowsHitTesting(false)
                            default:
                                Image(systemName: "building.2.fill")
                                    .font(.footnote)
                                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                        }
                    } else {
                        Image(systemName: "building.2.fill")
                            .font(.footnote)
                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                }
                .clipShape(.rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(brand.companyName)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(1)
                    if brand.emberVerified {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.orange)
                    }
                }
                Text(brand.industry?.isEmpty == false ? brand.industry! : "Sponsor")
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(1)
                if let pay = brand.typicalPayText {
                    Text("Typically pays \(pay)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(1)
                } else {
                    Text("\(brand.minFollowers.formatted())+ followers · \(brand.minAge)+")
                        .font(.caption2)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 230, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .contentShape(.rect)
    }

    // MARK: - Waves rail (the tall 9:16 blocks)

    /// Waves for the Discover rail — newest first, media-backed, capped so
    /// the rail stays snappy. Rows (not mapped posts) so the tile can pull
    /// its cached poster frame exactly like the profile's Waves grid.
    private var discoverWaveRows: [WhisperPostRow] {
        let ranked = WhisperAlgorithmService.wavesRank(realPool.filter { $0.isReel && !$0.mediaURLs.isEmpty })
        var byID: [String: WhisperPostRow] = [:]
        for row in backend.posts { byID[row.id.lowercased()] = row }
        return ranked.prefix(14).compactMap { byID[$0.id.uuidString.lowercased()] }
    }


    /// A wave row mapped to the player's post model (same mapping as `realPool`).
    private func wavePost(from row: WhisperPostRow) -> WhisperPost {
        if let match = realPool.first(where: { $0.id.uuidString.lowercased() == row.id.lowercased() }) {
            return match
        }
        let urls: [URL] = (row.media_urls ?? []).compactMap { URL(string: $0) }
        return WhisperPost(
            id: UUID(uuidString: row.id) ?? UUID(),
            username: WhisperBackendService.shared.resolvedAuthorUsername(rowUsername: row.username, rowUserID: row.user_id),
            timeAgo: WhisperPost.relativeTime(from: row.created_at),
            kind: WhisperPostKind(rawValue: row.kind ?? "") ?? .photo,
            caption: row.caption,
            symbol: row.symbol ?? "play.rectangle",
            accent: WhisperPost.color(fromHex: row.accent_hex) ?? Color(red: 0.5, green: 0.5, blue: 0.5),
            mediaURLs: urls,
            likes: row.likes_count ?? 0,
            comments: row.comments_count ?? 0,
            liked: backend.myLikedPostIDs.contains(row.id),
            isReel: true,
            createdAt: WhisperBackendService.parseISO(row.created_at),
            communityID: row.community_id,
            communityName: row.community_name
        )
    }

    // MARK: - Explore mosaic (IG explore grammar)

    /// Media-first pool for the mosaic — photo/video posts ranked by the
    /// same personalized discover ranker, capped for a tight grid.
    private var explorePool: [WhisperPost] {
        let me = WhisperUserService.shared.me
        let interests = me?.interests ?? []
        let followingNames = Set(follows.followingUsernames.values.map { $0.lowercased() })
        let coachNames = Set(coach.coachByUsername.compactMap { $0.value ? $0.key : nil })
        let pool = realPool.filter {
            WhisperAlgorithmService.hoursSinceCreation($0) <= 24 * 30 && !$0.mediaURLs.isEmpty && !$0.isReel
        }
        return Array(
            WhisperAlgorithmService.personalizedDiscoverRank(
                pool,
                interests: interests,
                followingUsernames: followingNames,
                coachUsernames: coachNames
            ).prefix(21)
        )
    }

    // MARK: - The mosaic model (cached — ranking never runs inside body)

    /// One tile in the Discover mosaic — a media post or a WAVE. Waves are
    /// the tall 9:16 tiles INSIDE the grid (poster frame, no autoplay), so
    /// they read as the longer posts of the mosaic instead of a separate rail.
    private enum MosaicItem: Identifiable {
        case post(WhisperPost)
        case wave(WhisperPostRow)
        var id: String {
            switch self {
            case .post(let p): return "p-\(p.id.uuidString)"
            case .wave(let r): return "w-\(r.id)"
            }
        }
    }

    /// One 3-column band: either three squares, a tall tile + four squares,
    /// or (once media posts run out) a row of tall waves.
    private struct MosaicBand: Identifiable {
        let id: Int
        let tall: MosaicItem?
        let squares: [MosaicItem]
        let tallOnLeft: Bool
        let waveRow: Bool
    }

    @State private var mosaicBands: [MosaicBand] = []

    /// Cheap fingerprint of the inputs — the mosaic rebuilds only when the
    /// post pool or the follow graph actually changes, never on every render.
    private var mosaicSignature: String {
        var hash = Hasher()
        for row in backend.posts {
            hash.combine(row.id); hash.combine(row.likes_count); hash.combine(row.comments_count)
            hash.combine(row.caption); hash.combine(row.media_urls)
        }
        hash.combine(follows.followingUsernames)
        hash.combine(backend.myLikedPostIDs)
        hash.combine(users.me?.interests)
        hash.combine(tuning.moreOf); hash.combine(tuning.lessOf); hash.combine(tuning.strength)
        return String(hash.finalize())
    }

    /// Builds the bands: media posts fill the squares, waves take EVERY tall
    /// slot first (falling back to a media post when waves run out), and any
    /// waves left after the posts render as rows of tall tiles.
    private func rebuildMosaic() {
        let posts: [WhisperPost] = exploreFilter == "Waves" ? [] : explorePool
        let waves: [WhisperPostRow] = exploreFilter == "Photos" ? [] : discoverWaveRows
        var bands: [MosaicBand] = []
        var pi = 0
        var wi = 0
        var bandIndex = 0
        while pi < posts.count && bands.count < 14 {
            let isTall = bandIndex % 2 == 1
            if isTall {
                let tall: MosaicItem
                if wi < waves.count {
                    tall = .wave(waves[wi])
                    wi += 1
                } else {
                    tall = .post(posts[pi])
                    pi += 1
                }
                var squares: [MosaicItem] = []
                while squares.count < 4 && pi < posts.count {
                    squares.append(.post(posts[pi]))
                    pi += 1
                }
                bands.append(MosaicBand(id: bandIndex, tall: tall, squares: squares, tallOnLeft: (bandIndex / 2) % 2 == 1, waveRow: false))
            } else {
                var squares: [MosaicItem] = []
                while squares.count < 3 && pi < posts.count {
                    squares.append(.post(posts[pi]))
                    pi += 1
                }
                bands.append(MosaicBand(id: bandIndex, tall: nil, squares: squares, tallOnLeft: false, waveRow: false))
            }
            bandIndex += 1
        }
        while wi < waves.count && bands.count < 16 {
            var row: [MosaicItem] = []
            while row.count < 3 && wi < waves.count {
                row.append(.wave(waves[wi]))
                wi += 1
            }
            bands.append(MosaicBand(id: bandIndex, tall: nil, squares: row, tallOnLeft: false, waveRow: true))
            bandIndex += 1
        }
        mosaicBands = bands
    }

    @ViewBuilder
    private var trendingPostsSection: some View {
        if !mosaicBands.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                exploreFilterBar
                exploreMosaic()
            }
        } else if exploreFilter != "For you" {
            VStack(spacing: 16) {
                exploreFilterBar
                Text("No \(exploreFilter.lowercased()) to show yet.").font(.subheadline).foregroundStyle(WhisperTheme.muted(colorScheme))
                Button("Show everything") { exploreFilter = "For you" }.frame(minHeight: 44)
            }
        } else if !trendingPosts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Trending posts")
                LazyVStack(spacing: 0) {
                    ForEach(trendingPosts) { post in
                        WhisperPostCard(post: post)
                        Divider().background(WhisperTheme.hairline(colorScheme))
                    }
                }
            }
        } else if backend.isLoadingPosts {
            WhisperPostSkeletonList()
        } else {
            VStack(spacing: 12) {
                Text("Explore posts").font(.headline)
                Text("Search for people or refresh to discover posts.")
                    .font(.subheadline).foregroundStyle(WhisperTheme.muted(colorScheme))
                Button("Refresh") { Task { await refresh() } }.buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 32)
        }
    }

    /// Instagram's explore mosaic — 3-column bands; every other band carries
    /// a double-height tile (alternating sides) that is a WAVE whenever one
    /// is available, the rest are squares. 2pt gutters, nearly full-bleed.
    /// Reads the cached bands — no ranking, no layout math per render.
    private var exploreFilterBar: some View {
        HStack(spacing: 8) {
            ForEach(["For you", "Photos", "Waves"], id: \.self) { filter in
                Button { Haptics.tap(); exploreFilter = filter } label: {
                    Text(filter).font(.subheadline.weight(.semibold))
                        .foregroundStyle(exploreFilter == filter ? WhisperTheme.ink(colorScheme) : WhisperTheme.muted(colorScheme))
                        .padding(.horizontal, 8).frame(minHeight: 44)
                        .overlay(alignment: .bottom) {
                            if exploreFilter == filter {
                                Rectangle().fill(WhisperTheme.ink(colorScheme)).frame(height: 2)
                            }
                        }
                        .contentShape(.rect)
                }.buttonStyle(.plain).accessibilityAddTraits(exploreFilter == filter ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 16)
    }

    private func exploreMosaic() -> some View {
        let unit: CGFloat = max(1, (contentWidth - 36) / 3)
        let tallHeight: CGFloat = unit * 2 + 6
        return LazyVStack(spacing: 6) {
            ForEach(mosaicBands) { band in
                if band.waveRow {
                    HStack(spacing: 6) {
                        ForEach(band.squares) { item in
                            mosaicTile(item, width: unit, height: tallHeight, isTall: true)
                        }
                        if band.squares.count < 3 { Spacer(minLength: 0) }
                    }
                } else if let tall = band.tall {
                    mosaicTallBand(tall: tall, squares: band.squares, unit: unit, tallOnLeft: band.tallOnLeft)
                } else {
                    HStack(spacing: 6) {
                        ForEach(band.squares) { item in
                            mosaicTile(item, width: unit, height: unit)
                        }
                        if band.squares.count < 3 { Spacer(minLength: 0) }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
    }

    /// One tall band: a 1×2 tile on one side, up to four squares stacked
    /// 2×2 filling the rest (empty cells stay quiet surface).
    private func mosaicTallBand(tall: MosaicItem, squares: [MosaicItem], unit: CGFloat, tallOnLeft: Bool) -> some View {
        let tallHeight: CGFloat = unit * 2 + 6
        let squareCols = VStack(spacing: 6) {
            HStack(spacing: 6) {
                mosaicSquare(squares, index: 0, unit: unit)
                mosaicSquare(squares, index: 1, unit: unit)
            }
            HStack(spacing: 6) {
                mosaicSquare(squares, index: 2, unit: unit)
                mosaicSquare(squares, index: 3, unit: unit)
            }
        }
        return HStack(spacing: 6) {
            if tallOnLeft {
                mosaicTile(tall, width: unit, height: tallHeight, isTall: true)
                squareCols
            } else {
                squareCols
                mosaicTile(tall, width: unit, height: tallHeight, isTall: true)
            }
        }
    }

    @ViewBuilder
    private func mosaicSquare(_ squares: [MosaicItem], index: Int, unit: CGFloat) -> some View {
        if index < squares.count {
            mosaicTile(squares[index], width: unit, height: unit)
        } else {
            Color(.secondarySystemBackground).opacity(0.4).frame(width: unit, height: unit)
        }
    }

    @ViewBuilder
    private func mosaicTile(_ item: MosaicItem, width: CGFloat, height: CGFloat, isTall: Bool = false) -> some View {
        switch item {
        case .post(let post):
            exploreTile(post, width: width, height: height, isTall: isTall).clipShape(.rect(cornerRadius: 10))
        case .wave(let row):
            waveTile(row, width: width, height: height).clipShape(.rect(cornerRadius: 10))
        }
    }

    /// A wave inside the mosaic — the cached poster frame (the same one the
    /// profile grid uses), the author chip top-left, play + count bottom-left.
    /// Tap opens the full-screen Waves player on this wave.
    private func waveTile(_ row: WhisperPostRow, width: CGFloat, height: CGFloat) -> some View {
        let author = WhisperBackendService.shared.resolvedAuthorUsername(rowUsername: row.username, rowUserID: row.user_id)
        return Button {
            Haptics.tap()
            openWave = wavePost(from: row)
        } label: {
            WhisperWaveGridTile(row: row, tileAspect: width / height)
                .frame(width: width, height: height)
                .clipped()
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 5) {
                        WhisperAvatar(username: author, size: 18)
                        Text(author)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                    }
                    .padding(6)
                    .allowsHitTesting(false)
                }

        }
        .buttonStyle(GridCellPressStyle())
        .accessibilityLabel("Wave by \(author)")
    }

    /// A single mosaic tile — media fill with the IG badges (multi-photo
    /// stack, reel play). Tap opens the real post.
    private func exploreTile(_ post: WhisperPost, width: CGFloat, height: CGFloat, isTall: Bool = false) -> some View {
        Button {
            Haptics.tap()
            openPost = post
        } label: {
            Color(.secondarySystemBackground)
                .frame(width: width, height: height)
                .overlay {
                    Group {
                        if let url = post.mediaURLs.first {
                            if WhisperVideo.isVideo(url) {
                                // Never autoplay inside the grid — a poster-tone
                                // tile keeps scrolling smooth; waves carry their
                                // real poster frames via `waveTile`.
                                LinearGradient(
                                    colors: [post.accent.opacity(0.95), post.accent.opacity(0.55)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            } else {
                                WhisperSizedAsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let img):
                                        img.resizable().aspectRatio(contentMode: .fill)
                                    default:
                                        Color(.secondarySystemBackground)
                                    }
                                }
                            }
                        } else {
                            LinearGradient(
                                colors: [post.accent.opacity(0.95), post.accent.opacity(0.55)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        }
                    }
                    .allowsHitTesting(false)
                }
                .clipped()
                .overlay(alignment: .topTrailing) {
                    Group {
                        if post.mediaURLs.count > 1 {
                            Image(systemName: "square.on.square.fill")
                        } else if post.mediaURLs.first.map(WhisperVideo.isVideo) == true {
                            Image(systemName: "play.fill")
                        }
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .padding(6)
                    .allowsHitTesting(false)
                }
        }
        .buttonStyle(GridCellPressStyle())
        .accessibilityLabel("Post by \(post.username)")
    }


    // MARK: - Suggested users

    @ViewBuilder
    private var suggestedSection: some View {
        let pool = suggested.filter { !follows.isFollowing(userID: $0.user_id) }
        if !pool.isEmpty {
            // Plain rows (no card chrome) — matches the Threads-style
            // "Follow suggestions" list in the reference design.
            VStack(alignment: .leading, spacing: 4) {
                Text("Follow suggestions")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                VStack(spacing: 0) {
                    ForEach(pool.prefix(8)) { u in
                        userRow(u)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    // MARK: - Section header helper

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    /// Header with a trailing "See all" action — one shared style so every
    /// rail on Discover reads identically.
    private func sectionHeader(_ title: String, seeAll: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Spacer()
            Button {
                Haptics.tap()
                seeAll()
            } label: {
                Text("See all")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    private func sectionHeaderWithLink(_ title: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Spacer()
            NavigationLink(value: CommunitiesRoute()) {
                Text(trailing)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }
}
