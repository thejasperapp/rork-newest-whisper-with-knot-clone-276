import SwiftUI

/// Verified-only CREATOR STUDIO — the creator's private read on why the
/// algorithm is or isn't pushing their work. Everything is computed on this
/// device from posts the backend already streams down (`myPosts`, follower
/// counts) — no new tables.
///
/// Redone on the Whisper design language: a clean surface, the brand-gradient
/// TYPE-IN headline (the same entrance the algorithm screen and the paywalls
/// wear), a score card whose number wears the gradient and whose ring sweeps
/// it, quiet hairline tiles, the WPP payout card, a top-post spotlight with
/// its real cover, a 14-day cadence in the brand sweep, "what the algorithm
/// sees" as honest rows, and the ranked post list with thumbnails. The Jasper
/// analysis dock rides the bottom edge.
@MainActor
struct WhisperCreatorDashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var backend = WhisperBackendService.shared
    @State private var follows = WhisperFollowService.shared

    @State private var followerCount: Int = 0
    @State private var followerDeltaWeek: Int = 0
    @State private var loading: Bool = true
    @State private var ringProgress: CGFloat = 0
    @State private var barsShown: Bool = false
    @State private var reloadOperation = UUID()

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }
    private var accent: Color { WhisperBrandGradient.accent }

    private var me: String {
        WhisperUserService.shared.me?.username
            ?? AuthenticationService.shared.currentUser.username
            ?? ""
    }

    private var myBadge: UserBadge {
        UserVerificationService.shared.badge(forUsername: me)
    }

    /// Posts authored by the current user, mapped to the same `WhisperPost`
    /// the ranker scores. Sorted newest-first by `createdAt`.
    private var myPosts: [WhisperPost] {
        backend.myPosts.map { row in
            let urls: [URL] = (row.media_urls ?? []).compactMap { URL(string: $0) }
            return WhisperPost(
                id: UUID(uuidString: row.id) ?? UUID(),
                username: row.username ?? me,
                timeAgo: WhisperPost.relativeTime(from: row.created_at),
                kind: WhisperPostKind(rawValue: row.kind ?? "") ?? .photo,
                caption: row.caption,
                symbol: row.symbol ?? WhisperPostKind(rawValue: row.kind ?? "")?.icon ?? "sparkles",
                accent: WhisperPost.color(fromHex: row.accent_hex) ?? Color.gray,
                mediaURLs: urls,
                likes: row.likes_count ?? 0,
                comments: row.comments_count ?? 0,
                liked: false,
                isReel: row.is_reel ?? false,
                createdAt: WhisperBackendService.parseISO(row.created_at)
            )
        }
        .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    private var last30Days: [WhisperPost] {
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        return myPosts.filter { ($0.createdAt ?? .distantPast) >= cutoff }
    }

    private var totalLikes30: Int  { last30Days.reduce(0) { $0 + $1.likes } }
    private var totalComments30: Int { last30Days.reduce(0) { $0 + $1.comments } }
    private var engagementPct30: Double {
        guard followerCount > 0, !last30Days.isEmpty else { return 0 }
        let totalActions = Double(totalLikes30 + totalComments30)
        let totalReach = Double(followerCount * last30Days.count)
        return min(100, (totalActions / totalReach) * 100)
    }

    /// 0–100 composite that rewards engagement, cadence, audience and
    /// momentum — the number the ring animates to.
    private var creatorScore: Int {
        let engagement = min(40.0, engagementPct30 * 8)
        let cadence = min(30.0, Double(last30Days.count) * 3)
        let audience = min(20.0, Double(followerCount) / 50)
        let momentum: Double = followerDeltaWeek > 0 ? 10 : (followerDeltaWeek < 0 ? 0 : 5)
        return Int(min(100, engagement + cadence + audience + momentum))
    }

    private var scoreVerdict: String {
        let s = creatorScore
        if s >= 75 { return "On fire — the algorithm loves this pace." }
        if s >= 50 { return "Solid momentum. One more post this week pushes higher." }
        if s >= 25 { return "Warming up — consistency is your fastest lever." }
        return "Post something today to wake the algorithm up."
    }

    /// The headline — reads the state of the studio in one line.
    private var headlineText: String {
        let name = me.isEmpty ? "creator" : me
        if myPosts.isEmpty { return "Your studio is ready, @\(name). Post something and the numbers start." }
        let s = creatorScore
        if s >= 75 { return "You're on fire, @\(name). Here's what's carrying it." }
        if s >= 50 { return "Real momentum, @\(name). Here's how your work is landing." }
        if s >= 25 { return "Here's how your work is landing, @\(name)." }
        return "Here's where things stand, @\(name) — and the one move that changes it."
    }

    /// Highest-scoring post (per the live ranking algorithm).
    private var topPost: WhisperPost? {
        myPosts.max { WhisperAlgorithmService.score(for: $0) < WhisperAlgorithmService.score(for: $1) }
    }

    /// Posting cadence over the last 14 days, as count-per-day.
    private var cadence14: [Int] {
        var buckets = Array(repeating: 0, count: 14)
        let now = Date()
        for p in myPosts {
            guard let ts = p.createdAt else { continue }
            let days = Int(now.timeIntervalSince(ts) / 86_400)
            if days >= 0 && days < 14 { buckets[13 - days] += 1 }
        }
        return buckets
    }

    private var ranked: [WhisperPost] {
        myPosts.sorted {
            WhisperAlgorithmService.score(for: $0) > WhisperAlgorithmService.score(for: $1)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        headline
                        scoreCard
                        // Creator payouts — the WPP card mirrors web Creator
                        // Studio: 50% of real ad spend funds the pool.
                        WhisperWppCard()
                        overviewTiles
                        if let top = topPost { topPostCard(top) }
                        cadenceCard
                        algorithmPanel
                        perPostList
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .whisperRefreshable { await reload() }
            }
            .navigationTitle("Creator Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(ink)
                }
            }
            // The studio is the creator's own numbers — Jasper stays out of
            // the way here (no dock, no mascot); "What the algorithm sees"
            // carries the read in plain ink.
            .task(id: AccountStorage.generation) { await reload() }
            .onDisappear { reloadOperation = UUID() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
                reloadOperation = UUID(); followerCount = 0; followerDeltaWeek = 0; ringProgress = 0; barsShown = false
                dismiss()
            }
        }
    }

    /// Live creator context for the Jasper dock — the same client-side
    /// numbers the dashboard cards render.
    private func creatorAnalysisContext() -> String? {
        guard !myPosts.isEmpty else { return nil }
        var lines: [String] = ["CREATOR DASHBOARD (live, last 30 days)"]
        lines.append("Creator score \(creatorScore)/100 · followers \(followerCount) (\(followerDeltaWeek >= 0 ? "+" : "")\(followerDeltaWeek) this week) · engagement \(String(format: "%.1f", engagementPct30))% · posts 30d \(last30Days.count)")
        let waves = myPosts.filter { $0.isReel }.count
        lines.append("Formats: \(waves) waves · \(myPosts.count - waves) posts")
        for post in ranked.prefix(5) {
            let caption = (post.displayCaption.isEmpty ? "(no caption)" : String(post.displayCaption.prefix(60)))
            lines.append("- \(post.isReel ? "wave" : "post") · \(post.likes) likes · \(post.comments) comments · \(post.timeAgo) · \(caption)")
        }
        return lines.joined(separator: "\n")
    }

    private func reload() async {
        let owner = AccountStorage.currentUserID, generation = AccountStorage.generation, operation = UUID()
        reloadOperation = operation; loading = true
        async let count = follows.followerCount(forUserID: owner)
        await backend.fetchMyPosts()
        let nextCount = await count
        guard !Task.isCancelled, owner == AccountStorage.currentUserID, generation == AccountStorage.generation,
              reloadOperation == operation else { return }
        followerCount = nextCount
        followerDeltaWeek = computeFollowerDelta()
        loading = false
        ringProgress = 0
        barsShown = false
        withAnimation(.spring(duration: 1.1, bounce: 0.15).delay(0.15)) {
            ringProgress = CGFloat(creatorScore) / 100
        }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.82).delay(0.25)) {
            barsShown = true
        }
    }

    // MARK: - Headline

    /// The brand-gradient type-in — the same entrance the algorithm screen
    /// and the paywalls wear — settling to ink.
    private var headline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("CREATOR STUDIO")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.1)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.12), in: Capsule())
                if myBadge == .verified {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("VERIFIED")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1.1)
                    }
                    .foregroundStyle(muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(WhisperTheme.card(colorScheme), in: Capsule())
                }
                Spacer()
                if loading {
                    ProgressView().controlSize(.small).tint(muted)
                }
            }
            WhisperGradientTypeInText(
                text: headlineText,
                font: .system(size: 26, weight: .bold),
                speed: 34,
                settleColor: ink
            )
            .id(headlineText)
            Text("Your score, your reach, and what the algorithm actually sees — computed on this device from your own posts.")
                .font(.footnote)
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    // MARK: - Score card

    private var scoreCard: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                kicker("CREATOR SCORE")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(creatorScore)")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(WhisperBrandGradient.linear)
                        .contentTransition(.numericText())
                    Text("/ 100")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(muted)
                }
                Text(scoreVerdict)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(ink.opacity(0.85))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            scoreRing
        }
        .padding(16)
        .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
    }

    private var scoreRing: some View {
        ZStack {
            Circle()
                .stroke(WhisperTheme.hairline(colorScheme), lineWidth: 9)
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(
                    WhisperBrandGradient.angular,
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text("\(Int((ringProgress * 100).rounded()))")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                    .contentTransition(.numericText())
                Text("SCORE")
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(muted)
            }
        }
        .frame(width: 92, height: 92)
    }

    // MARK: - Overview tiles

    private var overviewTiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            tile(
                title: "Followers",
                value: shortNumber(followerCount),
                delta: followerDeltaWeek == 0 ? nil : followerDeltaWeek,
                deltaLabel: followerDeltaWeek == 0 ? nil : "\(followerDeltaWeek > 0 ? "+" : "")\(followerDeltaWeek) this week",
                icon: "person.2"
            )
            tile(
                title: "Engagement · 30d",
                value: String(format: "%.1f%%", engagementPct30),
                delta: nil,
                deltaLabel: nil,
                icon: "hand.thumbsup",
                footnote: "actions ÷ reach on your posts"
            )
            tile(title: "Likes · 30 days", value: shortNumber(totalLikes30), delta: nil, deltaLabel: nil, icon: "heart")
            tile(title: "Comments · 30 days", value: shortNumber(totalComments30), delta: nil, deltaLabel: nil, icon: "bubble.left")
        }
    }

    private func tile(title: String, value: String, delta: Int?, deltaLabel: String?, icon: String, footnote: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(muted)
                Spacer()
                if let delta, let deltaLabel {
                    HStack(spacing: 2) {
                        Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 9, weight: .bold))
                        Text(deltaLabel)
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(delta >= 0 ? accent : Color(red: 0.90, green: 0.35, blue: 0.35))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
            }
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(footnote ?? title)
                .font(.caption)
                .foregroundStyle(muted)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
    }

    // MARK: - Top post

    @ViewBuilder
    private func topPostCard(_ post: WhisperPost) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                kicker("TOP PERFORMING")
                Spacer()
                scoreChip(WhisperAlgorithmService.score(for: post), emphasized: true)
            }
            HStack(alignment: .top, spacing: 12) {
                postThumb(post, width: 64, height: post.isReel ? 92 : 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text(post.displayCaption.isEmpty ? (post.isReel ? "A wave" : "A media post") : post.displayCaption)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ink)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Label("\(post.likes)", systemImage: "heart.fill")
                        Label("\(post.comments)", systemImage: "bubble.left.fill")
                        Text(post.timeAgo)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(muted)
                    Text(post.isReel ? "Wave" : "Post")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(accent)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
    }

    /// The post's real cover — its first media frame — or its glyph tile.
    private func postThumb(_ post: WhisperPost, width: CGFloat, height: CGFloat) -> some View {
        Color(.secondarySystemBackground)
            .frame(width: width, height: height)
            .overlay {
                if let url = post.mediaURLs.first, !WhisperVideo.isVideo(url) {
                    WhisperCachedAsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.clear
                        }
                    }
                    .allowsHitTesting(false)
                } else {
                    Image(systemName: post.isReel ? "play.fill" : post.symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(muted)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func scoreChip(_ score: Double, emphasized: Bool = false) -> some View {
        Text(String(format: "%.1f", score))
            .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(emphasized ? WhisperTheme.surface(colorScheme) : ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(emphasized ? AnyShapeStyle(WhisperBrandGradient.diagonal) : AnyShapeStyle(WhisperTheme.surface(colorScheme)), in: Capsule())
            .overlay {
                if !emphasized {
                    Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
                }
            }
    }

    // MARK: - Cadence

    private var cadenceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                kicker("POSTING CADENCE")
                Spacer()
                Text("last 14 days")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(muted)
            }
            let buckets = cadence14
            let maxV = max(1, buckets.max() ?? 1)
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(buckets.enumerated()), id: \.offset) { i, count in
                    let h = CGFloat(count) / CGFloat(maxV) * 56
                    let isToday = i == buckets.count - 1
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(
                            count == 0
                                ? AnyShapeStyle(WhisperTheme.hairline(colorScheme))
                                : (isToday ? AnyShapeStyle(WhisperBrandGradient.vertical) : AnyShapeStyle(accent.opacity(0.85)))
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: barsShown ? max(4, h) : 4)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(Double(i) * 0.03), value: barsShown)
                }
            }
            .frame(height: 60)
            Text(cadenceHint)
                .font(.caption)
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
    }

    private var cadenceHint: String {
        let recent = cadence14.suffix(7).reduce(0, +)
        if recent == 0 { return "Nothing this week yet — even one post restarts your recency boost." }
        if recent >= 5 { return "Excellent rhythm — the recency boost is working for you all week." }
        return "\(recent) post\(recent == 1 ? "" : "s") this week. 4–5 keeps the recency boost alive."
    }

    // MARK: - Algorithm panel

    private var algorithmPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            kicker("WHAT THE ALGORITHM SEES")
                .padding(.bottom, 6)
            algoRow(icon: "checkmark.seal", label: "Badge boost",
                    value: String(format: "%.2f\u{00d7}", myBadge.algorithmBoost),
                    hint: "Active when a post has \u{2265} 3 likes + comments.")
            divider
            algoRow(icon: "clock", label: "Recency half-life",
                    value: "\(Int(WhisperAlgorithmService.recencyHalfLife))h",
                    hint: "Posts decay smoothly; you have ~3 days of strong push.")
            divider
            algoRow(icon: "eye", label: "Seen decay",
                    value: String(format: "%.2f\u{00d7}", WhisperAlgorithmService.seenDecayMultiplier),
                    hint: "Applied after a viewer scrolls past once.")
            divider
            algoRow(icon: "target", label: "Interest match",
                    value: "1.40\u{00d7}",
                    hint: "Use specific topic words in captions.")
            divider
            algoRow(icon: "photo", label: "Media bonus",
                    value: "1.15\u{00d7} · video 1.10\u{00d7}",
                    hint: "Attaching media outperforms text-only.")
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(WhisperTheme.hairline(colorScheme))
            .frame(height: 0.5)
            .padding(.leading, 42)
    }

    private func algoRow(icon: String, label: String, value: String, hint: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ink)
                .frame(width: 30, height: 30)
                .background(WhisperTheme.surface(colorScheme), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ink)
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Ranked posts

    private var perPostList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                kicker("YOUR POSTS, RANKED")
                Spacer()
                if !ranked.isEmpty {
                    Text("\(min(ranked.count, 20)) of \(ranked.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(muted)
                }
            }
            if ranked.isEmpty {
                Text("Post something to start seeing analytics here.")
                    .font(.caption)
                    .foregroundStyle(muted)
                    .padding(.vertical, 6)
            } else {
                ForEach(Array(ranked.prefix(20).enumerated()), id: \.element.id) { index, p in
                    perPostRow(p, rank: index + 1)
                    if index < min(ranked.count, 20) - 1 {
                        Rectangle()
                            .fill(WhisperTheme.hairline(colorScheme))
                            .frame(height: 0.5)
                            .padding(.leading, 74)
                    }
                }
            }
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
    }

    private func perPostRow(_ p: WhisperPost, rank: Int) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(rank <= 3 ? WhisperTheme.surface(colorScheme) : muted)
                .frame(width: 22, height: 22)
                .background(
                    rank <= 3 ? AnyShapeStyle(WhisperBrandGradient.diagonal) : AnyShapeStyle(Color.clear),
                    in: Circle()
                )
            postThumb(p, width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.displayCaption.isEmpty ? (p.isReel ? "A wave" : "A media post") : p.displayCaption)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Text("\(p.likes) likes \u{00B7} \(p.comments) comments \u{00B7} \(p.timeAgo)")
                    .font(.caption2)
                    .foregroundStyle(muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            scoreChip(WhisperAlgorithmService.score(for: p))
        }
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func kicker(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy))
            .tracking(1.1)
            .foregroundStyle(muted)
    }

    private func shortNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    /// Crude "this week" delta — uses the diff between current followers and
    /// the count stored from the last open, defaulting to 0 the first time.
    private func computeFollowerDelta() -> Int {
        let key = "whisper_creator_studio_followers_\(me.lowercased())"
        let last = UserDefaults.standard.integer(forKey: key)
        let delta = followerCount - last
        // Refresh the snapshot once a week so the delta keeps moving.
        let stampKey = key + "_at"
        let lastAt = UserDefaults.standard.double(forKey: stampKey)
        let now = Date().timeIntervalSince1970
        if now - lastAt > 7 * 86_400 || last == 0 {
            UserDefaults.standard.set(followerCount, forKey: key)
            UserDefaults.standard.set(now, forKey: stampKey)
        }
        return delta
    }
}
