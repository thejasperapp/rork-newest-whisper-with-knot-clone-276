import SwiftUI

// MARK: - Score ring (shared by mini card, sheet hero, tools preview)

/// The Creator Studio score ring, reusable at any size — angular
/// electric→violet→mint sweep that animates in on appear.
struct WhisperCreatorScoreRing: View {
    let score: Int
    var size: CGFloat = 88
    var lineWidth: CGFloat = 8

    @State private var progress: CGFloat = 0

    private let electric = Color(red: 0.25, green: 0.62, blue: 1.0)
    private let violet = Color(red: 0.62, green: 0.40, blue: 1.0)
    private let mint = Color(red: 0.20, green: 0.83, blue: 0.60)

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(colors: [electric, violet, mint, electric], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.system(size: max(11, size * 0.3), weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                if size >= 64 {
                    Text("SCORE")
                        .font(.system(size: 8, weight: .black))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.spring(duration: 1.0, bounce: 0.15).delay(0.1)) {
                progress = CGFloat(max(0, min(100, score))) / 100
            }
        }
    }
}

// MARK: - Mini card pinned into the call

/// The compact analytics card pinned top-trailing in the room while a
/// creator shares — ring, live pill, headline numbers. Tap to expand into
/// the full sheet; the presenter gets an ✕ to stop sharing.
struct WhisperCreatorAnalyticsMiniCard: View {
    let card: WhisperCreatorAnalyticsCard
    let isMine: Bool
    let onExpand: () -> Void
    let onStop: () -> Void

    private let mint = Color(red: 0.20, green: 0.83, blue: 0.60)
    private let electric = Color(red: 0.25, green: 0.62, blue: 1.0)
    private let violet = Color(red: 0.62, green: 0.40, blue: 1.0)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: {
                Haptics.tap()
                onExpand()
            }) {
                HStack(spacing: 10) {
                    WhisperCreatorScoreRing(score: Int(card.score ?? 0), size: 40, lineWidth: 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("@\(card.username ?? "creator")")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Circle()
                                .fill(mint)
                                .frame(width: 4, height: 4)
                                .phaseAnimator([0.4, 1.0]) { view, glow in
                                    view.opacity(glow)
                                } animation: { _ in .easeInOut(duration: 0.9) }
                            Text("CREATOR ANALYTICS")
                                .font(.system(size: 7.5, weight: .black))
                                .tracking(0.8)
                                .foregroundStyle(.white.opacity(0.65))
                        }
                        Text("\(Int(card.followers ?? 0)) followers · \(String(format: "%.1f", card.engagementPct ?? 0))% eng")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.up.left.and.chevron.down.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.black.opacity(0.45))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [electric.opacity(0.7), violet.opacity(0.4)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                }
                .compositingGroup()
                .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
                .contentShape(.rect(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Expand creator analytics")

            if isMine {
                Button(action: {
                    Haptics.tap()
                    onStop()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.black.opacity(0.75), in: Circle())
                        .overlay { Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .offset(x: 7, y: -7)
                .accessibilityLabel("Stop sharing analytics")
            }
        }
        .frame(maxWidth: 250)
        .transition(.scale(scale: 0.85, anchor: .topTrailing).combined(with: .opacity))
    }
}

// MARK: - Shared analytics body (sheet + tools preview)

/// The real Creator Studio view of the shared numbers — dark hero with the
/// animated ring and verdict, momentum tiles, and the top performing posts
/// in the real post-row format (tap opens the true full-screen post).
struct WhisperCreatorAnalyticsBody: View {
    let card: WhisperCreatorAnalyticsCard
    let onOpenPost: (WhisperCreatorAnalyticsCard.TopPost) -> Void

    private let electric = Color(red: 0.25, green: 0.62, blue: 1.0)
    private let violet = Color(red: 0.62, green: 0.40, blue: 1.0)
    private let mint = Color(red: 0.20, green: 0.83, blue: 0.60)
    private let gold = Color(red: 1.0, green: 0.78, blue: 0.13)
    private let heartRed = Color(red: 0.98, green: 0.35, blue: 0.45)

    var body: some View {
        VStack(spacing: 12) {
            hero
            momentumRow
            topPostsCard
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        WhisperAvatar(
                            username: card.username ?? "creator",
                            size: 32,
                            imageURL: card.imageUrl.flatMap(URL.init(string:))
                        )
                        VStack(alignment: .leading, spacing: 1) {
                            Text("@\(card.username ?? "creator")")
                                .font(.subheadline.weight(.black))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(mint)
                                    .frame(width: 4, height: 4)
                                    .phaseAnimator([0.4, 1.0]) { view, glow in
                                        view.opacity(glow)
                                    } animation: { _ in .easeInOut(duration: 0.9) }
                                Text("CREATOR ANALYTICS · LIVE")
                                    .font(.system(size: 9, weight: .black))
                                    .tracking(0.8)
                                    .foregroundStyle(electric)
                            }
                        }
                    }
                    if let verdict = card.verdict, !verdict.isEmpty {
                        Text(verdict)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                WhisperCreatorScoreRing(score: Int(card.score ?? 0), size: 84, lineWidth: 8)
            }
            HStack(spacing: 8) {
                heroChip(value: shortNumber(Int(card.followers ?? 0)), label: "Followers")
                heroChip(value: String(format: "%.1f%%", card.engagementPct ?? 0), label: "Engage")
                heroChip(value: "\(Int(card.posts30 ?? 0))", label: "Posts · 30d")
            }
            if let delta = card.followerDelta.map({ Int($0) }), delta != 0 {
                HStack(spacing: 3) {
                    Image(systemName: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 9, weight: .black))
                    Text("\(delta > 0 ? "+" : "")\(delta) followers this week")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(delta > 0 ? mint : Color.red)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background((delta > 0 ? mint : Color.red).opacity(0.14), in: Capsule())
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.17),
                    Color(red: 0.10, green: 0.10, blue: 0.26),
                    Color(red: 0.16, green: 0.09, blue: 0.30),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: .rect(cornerRadius: 22)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(
                    LinearGradient(
                        colors: [electric.opacity(0.55), violet.opacity(0.35), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    private func heroChip(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.08), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        }
    }

    // MARK: Momentum

    private var momentumRow: some View {
        HStack(spacing: 10) {
            momentumTile(
                value: shortNumber(Int(card.likes30 ?? 0)),
                label: "Likes · 30 days",
                icon: "heart.fill",
                tint: heartRed
            )
            momentumTile(
                value: shortNumber(Int(card.comments30 ?? 0)),
                label: "Comments · 30 days",
                icon: "bubble.left.fill",
                tint: electric
            )
        }
    }

    private func momentumTile(value: String, label: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
    }

    // MARK: Top posts — real post rows, tap → real detail

    @ViewBuilder
    private var topPostsCard: some View {
        let tops = card.topPosts ?? []
        if !tops.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(gold)
                    Text("Top performing posts")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("tap to open")
                        .font(.system(size: 9, weight: .bold))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 6) {
                    ForEach(Array(tops.enumerated()), id: \.element.id) { index, top in
                        topPostRow(top, rank: index + 1)
                    }
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground).opacity(0.55), in: .rect(cornerRadius: 16))
        }
    }

    private func topPostRow(_ top: WhisperCreatorAnalyticsCard.TopPost, rank: Int) -> some View {
        Button {
            Haptics.tap()
            onOpenPost(top)
        } label: {
            HStack(spacing: 10) {
                Text("#\(rank)")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(rank == 1 ? gold : Color.secondary)
                    .frame(width: 22, alignment: .leading)
                postThumb(top)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if top.isReel == true {
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        Text(WhisperPostMeta.strip(from: top.caption ?? "").isEmpty ? "(media post)" : WhisperPostMeta.strip(from: top.caption ?? ""))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    Text("\(Int(top.likes ?? 0)) likes · \(Int(top.comments ?? 0)) comments · \(WhisperPost.relativeTime(from: top.createdAt))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if let score = top.score {
                    Text(String(format: "%.1f", score))
                        .font(.system(size: 10, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(electric)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(electric.opacity(0.13), in: Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(9)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    /// Media thumbnail via the Color-anchor pattern (the overflowing .fill
    /// image can never break layout or steal taps); symbol tile fallback.
    @ViewBuilder
    private func postThumb(_ top: WhisperCreatorAnalyticsCard.TopPost) -> some View {
        let accent = WhisperPost.color(fromHex: top.accentHex) ?? .gray
        if let first = (top.mediaUrls ?? []).first, let url = URL(string: first) {
            Color(.tertiarySystemFill)
                .frame(width: 44, height: 44)
                .overlay {
                    WhisperCachedAsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 10))
        } else {
            Image(systemName: top.symbol ?? "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 44, height: 44)
                .background(accent.opacity(0.14), in: .rect(cornerRadius: 10))
        }
    }

    private func shortNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - Expanded sheet (everyone in the call)

/// Full-screen-sheet view of a creator's shared analytics — the real
/// dashboard anatomy. Top posts open the true full-screen post detail.
struct WhisperCreatorAnalyticsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let card: WhisperCreatorAnalyticsCard
    let isMine: Bool
    let onStop: () -> Void

    @State private var openPost: WhisperPost?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    WhisperCreatorAnalyticsBody(card: card) { top in
                        openPost = WhisperCreatorMeetingKit.post(
                            from: top,
                            username: card.username ?? "creator"
                        )
                    }
                    Text("Shared live by \(card.presenterName)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if isMine {
                        Button(role: .destructive) {
                            Haptics.tap()
                            onStop()
                            dismiss()
                        } label: {
                            Text("Stop sharing")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.red.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .navigationTitle("@\(card.username ?? "creator") — analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .fullScreenCover(item: $openPost) { post in
                WhisperPostDetailView(post: post)
            }
        }
    }
}

// MARK: - Creator tools sheet (the creator's own entry point)

/// "Creator tools" inside a meeting — Jasper quick prompts wired to the
/// creator's LIVE analytics, a preview of the exact card everyone will see,
/// and one button to share it into the call.
struct WhisperMeetingCreatorToolsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onShare: (WhisperCreatorAnalyticsCard) -> Void
    let onAsk: (String) -> Void

    @State private var loading: Bool = true
    @State private var card: WhisperCreatorAnalyticsCard?
    @State private var openPost: WhisperPost?

    private let electric = Color(red: 0.25, green: 0.62, blue: 1.0)
    private let violet = Color(red: 0.62, green: 0.40, blue: 1.0)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    jasperPromptsCard
                    if loading {
                        loadingCard
                    } else if let card {
                        shareButton(card)
                        WhisperCreatorAnalyticsBody(card: card) { top in
                            openPost = WhisperCreatorMeetingKit.post(
                                from: top,
                                username: card.username ?? "creator"
                            )
                        }
                    } else {
                        emptyCard
                    }
                }
                .padding(16)
            }
            .navigationTitle("Creator tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                let name = WhisperUserService.shared.me?.username
                    ?? AuthenticationService.shared.currentUser.username
                    ?? "creator"
                card = await WhisperCreatorMeetingKit.buildCard(
                    presenterUserId: AccountStorage.currentUserID.lowercased(),
                    presenterName: name
                )
                loading = false
            }
            .fullScreenCover(item: $openPost) { post in
                WhisperPostDetailView(post: post)
            }
        }
    }

    // MARK: Jasper quick prompts

    private var jasperPromptsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                WhisperEmberBadge(size: 20)
                Text("Ask Jasper — grounded in your live numbers")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
            }
            promptRow(
                icon: "chart.line.uptrend.xyaxis",
                title: "Read my numbers",
                subtitle: "What's working, what's holding the score back",
                question: "Read my creator analytics — what's genuinely working, what's holding my score back, and my single next move this week?"
            )
            promptRow(
                icon: "lightbulb.fill",
                title: "Post ideas",
                subtitle: "3 ideas built from your top posts",
                question: "From my top-performing posts, pitch 3 specific post ideas I should make next — one line each with the format and the hook."
            )
            promptRow(
                icon: "flame.fill",
                title: "Growth move",
                subtitle: "The highest-leverage move right now",
                question: "What's my single highest-leverage growth move right now based on my live creator numbers? Explain the expected effect."
            )
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
    }

    private func promptRow(icon: String, title: String, subtitle: String, question: String) -> some View {
        Button {
            Haptics.tap()
            dismiss()
            onAsk(question)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(electric)
                    .frame(width: 28, height: 28)
                    .background(electric.opacity(0.13), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: Share + states

    private func shareButton(_ card: WhisperCreatorAnalyticsCard) -> some View {
        Button {
            Haptics.success()
            onShare(card)
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.inset.filled.and.person.filled")
                Text("Share my analytics to the meeting")
                    .font(.body.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                LinearGradient(colors: [electric, violet], startPoint: .leading, endPoint: .trailing),
                in: Capsule()
            )
            .shadow(color: electric.opacity(0.35), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Reading your live numbers…")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
    }

    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Post something first")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
            Text("Your analytics card unlocks with your first post — then you can share it live in meetings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 18)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
    }
}
