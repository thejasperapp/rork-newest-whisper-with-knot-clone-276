import SwiftUI

/// Native in-app article reader. Renders a published Whisper article with a
/// hero cover, author byline, and clean paragraph layout so the reader never
/// leaves the app. Keeps Whisper's monochrome palette and comfortable typography.
struct WhisperArticleReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let article: WhisperArticle

    @State private var authorProfile: WhisperBackendService.WhisperPublicProfile?
    @State private var engagement = WhisperArticleEngagementService.shared
    @State private var likeCount: Int = 0
    /// Linked film hydrated from `film_id` — renders the tappable embed.
    @State private var film: WhisperFeedFilm?
    @State private var presentFilm: Bool = false
    /// In-app share sheet — DMs, wall repost, or the system sheet.
    @State private var showShare: Bool = false

    var body: some View {
        ZStack {
            WhisperTheme.surface(colorScheme).ignoresSafeArea()
            // The hero extends to the physical top of the screen (under the
            // clock) — the ScrollView itself ignores the top safe area, and
            // close/share float OVER the image instead of a nav bar.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroSection
                    VStack(alignment: .leading, spacing: 18) {
                        titleSection
                        byline
                        if !article.excerpt.isEmpty {
                            Text(article.excerpt)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.85))
                                .lineSpacing(2)
                        }
                        if article.film_id != nil {
                            filmEmbed
                        }
                        paragraphs
                        footer
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 20)
                    // Clearance for the fact-check dock pinned at the bottom.
                    .padding(.bottom, 150)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            // Jasper's fact check — the meeting-style pill with the
            // peeking mascot, pinned right above the bottom edge. Tap to
            // run (cached per article — reopening never re-bills).
            JasperFactCheckDock(
                cacheKey: "article-\(article.id)",
                claim: Self.claimText(for: article)
            )
            .padding(.bottom, 30)
        }
        .overlay(alignment: .top) { floatingTopBar }
        .task {
            await hydrateAuthor()
        }
        .task {
            // Hydrate the linked film (article → film / clip embeds).
            if let filmID = article.film_id, !filmID.isEmpty {
                film = await WhisperFilmEngagementService.shared.fetchFilm(id: filmID)
            }
        }
        .sheet(isPresented: $showShare) {
            WhisperContentShareSheet(
                kicker: "WHISPER JOURNAL",
                title: article.title,
                subtitle: "By \(article.author_name ?? "Whisper Team")",
                imageURL: article.cover_url.flatMap(URL.init(string:)),
                embedBody: articleEmbedLine,
                linkURL: articleURL,
                onRepost: {
                    // Close the reader first — the composer presents from the
                    // root, so the sheet has to clear before the route fires.
                    let draft = articleEmbedLine
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        WhisperEmberActionRouter.shared.openComposer(draft: draft)
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $presentFilm) {
            if let film {
                WhisperFilmDetailView(film: film, startAt: article.clip_time_seconds)
            }
        }
    }

    /// Floating chrome over the hero — replaces the old nav bar so the
    /// cover art owns the whole top edge.
    private var floatingTopBar: some View {
        HStack {
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.black))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.42), in: Circle())
                    .overlay { Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            Spacer()
            // Same in-app share sheet as the bottom action — DMs, wall
            // repost, or the system sheet. (Was a bare system ShareLink,
            // which skipped DM sharing entirely.)
            Button {
                Haptics.tap()
                showShare = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.42), in: Circle())
                    .overlay { Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share article")
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
    }

    /// Dense claim text for the fact-check — title + excerpt + the first
    /// body paragraphs, capped so the research query stays sharp.
    private static func claimText(for article: WhisperArticle) -> String {
        var parts: [String] = [article.title]
        if !article.excerpt.isEmpty { parts.append(article.excerpt) }
        for p in article.paragraphs ?? [] where !p.hasPrefix("#") {
            parts.append(p)
            if parts.joined(separator: " ").count > 700 { break }
        }
        return String(parts.joined(separator: " ").prefix(750))
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            if let cover = article.cover_url, !cover.isEmpty, let url = URL(string: cover) {
                GeometryReader { geo in
                    WhisperCachedAsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                                .allowsHitTesting(false)
                        } else {
                            placeholderGradient
                                .frame(width: geo.size.width, height: geo.size.height)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: heroHeight)
            } else {
                placeholderGradient
                    .frame(maxWidth: .infinity)
                    .frame(height: heroHeight)
            }

            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            if let cat = article.category, !cat.isEmpty {
                Text(cat.uppercased())
                    .font(.caption2.weight(.black))
                    .tracking(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.18), in: Capsule())
                    .padding(.leading, 18)
                    .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: heroHeight)
        .clipShape(.rect(cornerRadius: 0))
    }

    /// Hero height including the status-bar area it now covers — slightly
    /// shorter on compact phones (SE / mini) so the title stays above the fold.
    private var heroHeight: CGFloat {
        UIScreen.main.bounds.height < 700 ? 270 : 330
    }

    private var placeholderGradient: some View {
        ZStack {
            WhisperTheme.card(colorScheme)
            Image(systemName: "doc.text.fill")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.12))
        }
    }

    // MARK: - Title

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(article.title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .lineSpacing(2)
            HStack(spacing: 5) {
                if !article.formattedDate.isEmpty {
                    Text(article.formattedDate)
                    Text("·")
                }
                Image(systemName: "book")
                    .font(.system(size: 9, weight: .bold))
                Text("\(readingMinutes) min read")
            }
            .font(.caption)
            .foregroundStyle(WhisperTheme.muted(colorScheme))
        }
    }

    /// ~200 wpm reading estimate across excerpt + paragraphs.
    private var readingMinutes: Int {
        let words = ([article.excerpt] + (article.paragraphs ?? []))
            .joined(separator: " ")
            .split(separator: " ")
            .count
        return max(1, Int((Double(words) / 200.0).rounded(.up)))
    }

    // MARK: - Film embed

    /// Tappable card for the linked film — opens the full cinema, seeking
    /// straight to the clip moment when the article pinned one.
    private var filmEmbed: some View {
        Button {
            guard film != nil else { return }
            Haptics.tap()
            presentFilm = true
        } label: {
            ZStack(alignment: .bottomLeading) {
                Color(white: 0.06)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        if let poster = film?.poster_url, let url = URL(string: poster) {
                            WhisperCachedAsyncImage(url: url) { phase in
                                if let img = phase.image {
                                    img.resizable().aspectRatio(contentMode: .fill)
                                        .allowsHitTesting(false)
                                }
                            }
                        } else {
                            Image(systemName: "film.fill")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(.white.opacity(0.2))
                        }
                    }
                    .clipped()
                LinearGradient(
                    colors: [.black.opacity(0.0), .black.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .black))
                        if let clip = article.clip_time_seconds, clip > 0 {
                            Text("CLIP · \(FeedFilmsCarousel.formatTimecode(clip))")
                        } else {
                            Text("WATCH THE FILM")
                        }
                    }
                    .font(.caption2.weight(.black))
                    .tracking(0.8)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.22), in: Capsule())
                    if let title = film?.title {
                        Text(title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
                .padding(12)
            }
            .clipShape(.rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
            .opacity(film == nil ? 0.6 : 1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(film == nil)
        .accessibilityLabel("Watch the linked film")
    }

    // MARK: - Byline

    private var byline: some View {
        HStack(spacing: 12) {
            let avatarURL = authorProfile?.profile_image_url.flatMap(URL.init(string:))
            WhisperAvatar(
                username: authorProfile?.username ?? article.author_name ?? "Whisper Team",
                size: 44,
                imageURL: avatarURL,
                ring: false
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(authorProfile?.display_name ?? authorProfile?.username ?? article.author_name ?? "Whisper Team")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                if let username = authorProfile?.username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.caption)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Paragraphs

    private var paragraphs: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array((article.paragraphs ?? []).enumerated()), id: \.offset) { _, paragraph in
                paragraphView(paragraph)
            }
        }
    }

    @ViewBuilder
    private func paragraphView(_ paragraph: String) -> some View {
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            if trimmed.hasPrefix("## ") {
                Text(String(trimmed.dropFirst(3)))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .padding(.top, 8)
            } else if trimmed.hasPrefix("# ") {
                Text(String(trimmed.dropFirst(2)))
                    .font(.title2.weight(.black))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .padding(.top, 12)
            } else {
                Text(trimmed)
                    .font(.body)
                    .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.92))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            let liked = engagement.isLiked(articleID: article.id)
            footerChip(
                icon: liked ? "heart.fill" : "heart",
                label: liked ? "Liked" : "Like",
                tint: liked ? WhisperTheme.likeRed : nil
            ) {
                engagement.toggleLike(articleID: article.id)
            }

            let saved = engagement.isSaved(articleID: article.id)
            footerChip(
                icon: saved ? "bookmark.fill" : "bookmark",
                label: saved ? "Saved" : "Save",
                tint: saved ? Color(red: 0.13, green: 0.55, blue: 0.96) : nil
            ) {
                engagement.toggleSave(articleID: article.id)
            }

            footerChip(icon: "square.and.arrow.up", label: "Share", tint: nil) {
                showShare = true
            }

            Spacer()
        }
        .padding(.top, 12)
    }

    private func footerChip(icon: String, label: String, tint: Color?, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint ?? WhisperTheme.ink(colorScheme))
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(WhisperTheme.card(colorScheme), in: Capsule())
            .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var articleURL: URL {
        URL(string: "\(WhisperBillingBackend.webOrigin)/articles/\(article.slug)") ?? URL(string: "https://www.mydailywhisper.com")!
    }

    /// The `::whisper-article-v1::` line — the DM body / wall-post draft.
    private var articleEmbedLine: String {
        WhisperArticleEmbed.encode(.init(
            id: article.id,
            slug: article.slug,
            title: article.title,
            author: article.author_name ?? "Whisper Team",
            cover: article.cover_url,
            category: article.category
        ))
    }

    private func hydrateAuthor() async {
        guard let uid = article.author_user_id, !uid.isEmpty else { return }
        let profile = await WhisperBackendService.shared.fetchPublicProfile(userID: uid)
        authorProfile = profile
    }
}

// MARK: - Fact-check dock

/// The meeting-style Jasper companion for the article reader — the living
/// mascot peeks from behind the mint pill ("Fact check"); tapping floats it
/// into the dark glass box and runs the research read right there. Cached
/// per article via `factCheckOnce`, with an explicit re-run chip.
struct JasperFactCheckDock: View {
    @Environment(\.colorScheme) private var colorScheme
    /// Cache key — `factCheckOnce` dedupes on this, so reopening is free.
    let cacheKey: String
    /// Dense claim text (title + excerpt + first paragraphs).
    let claim: String

    @State private var open = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var busy = false
    @State private var result: WhisperEmberService.FactCheck?
    @State private var ran = false
    @State private var expanded = false
    @State private var mode: WhisperEmberCoachMode = WhisperEmberCoachMode.load()
    @Namespace private var ns

    var body: some View {
        Group {
            if open {
                box
                    .transition(.opacity)
            } else {
                pill
            }
        }
        .onAppear {
            mode = WhisperEmberCoachMode.load()

        }
    }

    // MARK: Pill

    private var pill: some View {
        Button {
            Haptics.tap()
            mode = WhisperEmberCoachMode.load()
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { open = true }
            if !ran, !busy {
                Task { await run(force: false) }
            }
        } label: {
            WhisperJasperIntelligencePill(working: busy)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Knot fact check")
        .accessibilityHint("Research the claims in this article")
        .matchedGeometryEffect(id: "factDockHeader", in: ns, isSource: !open)

    }

    // MARK: Box

    private var box: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    WhisperKnotWordmark()
                    Text("Article fact check").font(.caption).foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.6))
                }
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                Spacer(minLength: 8)
                Button {
                    Haptics.tap()
                    withAnimation(.spring(duration: 0.36, bounce: 0.12)) { open = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.6))
                        .frame(width: 22, height: 22)
                        .background(WhisperTheme.ink(colorScheme).opacity(0.06), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close fact check")
            }
            .padding(.leading, 16)
            .padding(.trailing, 7)
            .frame(minHeight: 54)
            .background { WhisperJasperIntelligenceShell(shape: Capsule()) }
            .matchedGeometryEffect(id: "factDockHeader", in: ns, isSource: open)
            .padding(.horizontal, 10)
            .padding(.top, 10)

            ViewThatFits(in: .vertical) {
                contentBlock
                ScrollView(showsIndicators: false) { contentBlock }
            }
            .frame(maxHeight: 300, alignment: .top)

            HStack(spacing: 6) {
                Button {
                    Haptics.tap()
                    guard !busy else { return }
                    Task { await run(force: true) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .bold))
                        Text(busy ? "Checking…" : "Re-run")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .overlay { Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                Text("AI research read")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: 380)
        .padding(.horizontal, 12)
        .background { WhisperJasperIntelligenceShell(shape: RoundedRectangle(cornerRadius: 24), panel: true, onDark: true) }
    }

    private var contentBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            if busy {
                WhisperEmberThinkingSteps(
                    coachMode: mode,
                    resolvedLabel: nil,
                    isAnalytical: true,
                    onDark: true,
                    flavor: .meeting,
                    listenState: .hidden
                )
            } else if let result {
                verdictCard(result)
            } else if ran {
                Text("Couldn't research this one right now — re-run to try again.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func verdictCard(_ result: WhisperEmberService.FactCheck) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(mode.softAccent)
                Text("JASPER")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.4)
                    .foregroundStyle(mode.softAccent)
                Spacer(minLength: 6)
                HStack(spacing: 4) {
                    Image(systemName: result.verdict.symbol)
                        .font(.system(size: 9, weight: .bold))
                    Text(result.verdict.label.uppercased())
                        .font(.system(size: 9, weight: .black))
                        .tracking(0.7)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(result.verdict.tint, in: Capsule())
            }
            Text(result.summary)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
            if expanded {
                if result.explanation != result.summary && !result.explanation.isEmpty {
                    Text(result.explanation)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.78))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !result.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(result.sources.prefix(3), id: \.self) { source in
                            if let url = URL(string: source) {
                                Link(destination: url) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "link")
                                            .font(.system(size: 9, weight: .bold))
                                        Text(url.host() ?? source)
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                    }
                                    .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 1.0))
                                }
                            }
                        }
                    }
                }
            }
            Button {
                Haptics.tap()
                withAnimation(.whisperSnappy) { expanded.toggle() }
            } label: {
                Text(expanded ? "Show less" : "Why this verdict")
                    .frame(minHeight: 44)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            Text("Check the sources yourself — Jasper can be wrong.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.vertical, 11)
        .padding(.leading, 14)
        .padding(.trailing, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 16))
        .overlay(alignment: .leading) {
            Capsule()
                .fill((result.verdict.tint).opacity(0.8))
                .frame(width: 3)
                .padding(.vertical, 10)
                .padding(.leading, 5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(mode.accent.opacity(0.2), lineWidth: 1)
        }
    }

    // MARK: Run

    private func run(force: Bool) async {
        guard !busy else { return }
        withAnimation(.easeInOut(duration: 0.2)) { busy = true }
        defer {
            withAnimation(.spring(duration: 0.35)) { busy = false }
            ran = true
        }
        if force {
            result = await WhisperEmberService.shared.factCheck(claim)
        } else {
            result = await WhisperEmberService.shared.factCheckOnce(postID: cacheKey, caption: claim)
        }
    }
}

#Preview {
    let json: [String: Any] = [
        "id": "preview",
        "slug": "preview-article",
        "title": "The Quiet Power of Consistency",
        "excerpt": "Small daily wins compound into outcomes that look like luck to everyone else.",
        "cover_url": NSNull(),
        "category": "Mindset",
        "author_name": "Whisper Team",
        "author_user_id": NSNull(),
        "paragraphs": [
            "Every athlete, creator, and coach hits the same wall: the gap between wanting something and doing it daily.",
            "## The invisible reps",
            "The work nobody sees is what separates the people who stay from the people who quit. One post, one set, one conversation at a time.",
            "Whisper is built to make those invisible reps visible — to you, your community, and the people who will eventually find you."
        ],
        "published": true,
        "published_at": "2026-07-20T00:00:00Z",
        "created_at": "2026-07-20T00:00:00Z",
        "updated_at": NSNull()
    ]
    let data = try! JSONSerialization.data(withJSONObject: json)
    let article = try! JSONDecoder().decode(WhisperArticle.self, from: data)
    return WhisperArticleReaderView(article: article)
}
