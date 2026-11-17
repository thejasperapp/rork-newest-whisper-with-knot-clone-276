import SwiftUI
import Charts

/// ANALYTICS — the insights screen for PROFESSIONAL accounts (self-selected
/// creator / business types) and Whisper One members. Deliberately the
/// basic tier: reach on your own posts, interactions, followers, content
/// mix, top posts. Creator Studio (score ring, WPP creator pay, momentum)
/// stays VERIFIED-ONLY — this screen says so plainly at the bottom instead
/// of pretending to be it. Everything here is computed on-device from the
/// posts and follow counts the app already holds; no new tables.
struct WhisperAnalyticsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var backend = WhisperBackendService.shared
    @State private var follows = WhisperFollowService.shared
    @State private var users = WhisperUserService.shared
    @State private var range: Range = .month
    @State private var loading: Bool = false

    enum Range: Int, CaseIterable, Identifiable {
        case week = 7, month = 30, quarter = 90
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .week: return "7D"
            case .month: return "30D"
            case .quarter: return "90D"
            }
        }
    }

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }

    /// A post with its interaction total and parsed publish date.
    private struct Entry: Identifiable {
        let row: WhisperPostRow
        let date: Date
        var id: String { row.id }
        var likes: Int { row.likes_count ?? 0 }
        var comments: Int { row.comments_count ?? 0 }
        var interactions: Int { likes + comments }
        var isWave: Bool { row.is_reel == true }
        var hasMedia: Bool { !(row.media_urls?.isEmpty ?? true) }
    }

    private struct DayPoint: Identifiable {
        let day: Date
        let interactions: Int
        let posts: Int
        var id: Date { day }
    }

    private var username: String {
        users.me?.username ?? AuthenticationService.shared.currentUser.username ?? "you"
    }

    private var tierLabel: String { WhisperAccountAccess.tierLabel(username: username) }

    private var allEntries: [Entry] {
        var seen: Set<String> = []
        var out: [Entry] = []
        let uid = AccountStorage.currentUserID
        for row in backend.myPosts + backend.posts.filter({ $0.user_id == uid }) where seen.insert(row.id).inserted {
            guard let date = WhisperAnalyticsDates.parse(row.created_at) else { continue }
            out.append(Entry(row: row, date: date))
        }
        return out.sorted { $0.date > $1.date }
    }

    private var rangeStart: Date {
        Calendar.current.date(byAdding: .day, value: -range.rawValue, to: Date()) ?? Date()
    }

    private var entries: [Entry] { allEntries.filter { $0.date >= rangeStart } }

    /// The previous window of the same length — for the delta chips.
    private var previousEntries: [Entry] {
        let prevStart = Calendar.current.date(byAdding: .day, value: -range.rawValue, to: rangeStart) ?? rangeStart
        return allEntries.filter { $0.date >= prevStart && $0.date < rangeStart }
    }

    private var totalInteractions: Int { entries.reduce(0) { $0 + $1.interactions } }
    private var previousInteractions: Int { previousEntries.reduce(0) { $0 + $1.interactions } }
    private var totalLikes: Int { entries.reduce(0) { $0 + $1.likes } }
    private var totalComments: Int { entries.reduce(0) { $0 + $1.comments } }

    private var averagePerPost: Double {
        entries.isEmpty ? 0 : Double(totalInteractions) / Double(entries.count)
    }

    private var dayPoints: [DayPoint] {
        let cal = Calendar.current
        var buckets: [Date: (Int, Int)] = [:]
        let days = range.rawValue
        for offset in 0..<days {
            if let d = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: Date())) {
                buckets[d] = (0, 0)
            }
        }
        for e in entries {
            let day = cal.startOfDay(for: e.date)
            let cur = buckets[day] ?? (0, 0)
            buckets[day] = (cur.0 + e.interactions, cur.1 + 1)
        }
        return buckets.keys.sorted().map { DayPoint(day: $0, interactions: buckets[$0]?.0 ?? 0, posts: buckets[$0]?.1 ?? 0) }
    }

    private var topPosts: [Entry] {
        Array(entries.sorted { $0.interactions > $1.interactions }.prefix(3))
    }

    private var waveCount: Int { entries.filter { $0.isWave }.count }
    private var mediaCount: Int { entries.filter { !$0.isWave && $0.hasMedia }.count }
    private var textCount: Int { entries.filter { !$0.isWave && !$0.hasMedia }.count }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        headline
                        rangePicker
                        overviewTiles
                        chartCard
                        contentMixCard
                        topPostsCard
                        creatorStudioNote
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(ink)
                }
            }
            .task {
                loading = true
                await backend.fetchMyPosts()
                await follows.refresh()
                loading = false
            }
        }
    }

    // MARK: - Sections

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(tierLabel.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.1)
                    .foregroundStyle(WhisperBrandGradient.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(WhisperBrandGradient.accent.opacity(0.12), in: Capsule())
                Spacer()
                if loading {
                    ProgressView().controlSize(.small).tint(muted)
                }
            }
            WhisperGradientTypeInText(
                text: "Here's how your last \(range.rawValue) days landed.",
                font: .system(size: 24, weight: .bold),
                speed: 34,
                settleColor: ink
            )
            .id(range)
            Text("Current interactions on loaded posts published in this period, not unique reach or when each interaction happened. Followers are your current total.")
                .font(.footnote)
                .foregroundStyle(muted)
        }
    }

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(Range.allCases) { r in
                Text(r.label).tag(r)
            }
        }
        .pickerStyle(.segmented)
    }

    private var overviewTiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            tile(title: "Posts", value: "\(entries.count)", delta: delta(entries.count, previousEntries.count), icon: "square.grid.2x2")
            tile(title: "Interactions", value: shortNumber(totalInteractions), delta: delta(totalInteractions, previousInteractions), icon: "hand.thumbsup")
            tile(title: "Followers", value: shortNumber(follows.followerCount), delta: nil, icon: "person.2", footnote: "\(shortNumber(follows.followingCount)) following")
            tile(title: "Avg per post", value: String(format: "%.1f", averagePerPost), delta: nil, icon: "chart.bar", footnote: "\(shortNumber(totalLikes)) likes · \(shortNumber(totalComments)) comments")
        }
    }

    private func tile(title: String, value: String, delta: Int?, icon: String, footnote: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(muted)
                Spacer()
                if let delta {
                    HStack(spacing: 2) {
                        Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 9, weight: .bold))
                        Text("\(abs(delta))%")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(delta >= 0 ? WhisperBrandGradient.accent : Color(red: 0.90, green: 0.35, blue: 0.35))
                }
            }
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
                .contentTransition(.numericText())
            Text(footnote ?? title)
                .font(.caption)
                .foregroundStyle(muted)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Interactions by publish day")
            if entries.isEmpty {
                Text("Post something in this window and the chart fills in.")
                    .font(.footnote)
                    .foregroundStyle(muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
            } else {
                Chart(dayPoints) { point in
                    BarMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value("Interactions", point.interactions)
                    )
                    .foregroundStyle(WhisperBrandGradient.vertical)
                    .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(1, range.rawValue / 6))) { _ in
                        AxisGridLine().foregroundStyle(WhisperTheme.hairline(colorScheme))
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                            .foregroundStyle(muted)
                            .font(.system(size: 10))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(WhisperTheme.hairline(colorScheme))
                        AxisValueLabel().foregroundStyle(muted).font(.system(size: 10))
                    }
                }
                .frame(height: 170)
            }
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
    }

    private var contentMixCard: some View {
        let total = max(1, entries.count)
        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Content mix")
            GeometryReader { g in
                HStack(spacing: 2) {
                    segment(width: g.size.width * CGFloat(textCount) / CGFloat(total), color: WhisperBrandGradient.mint)
                    segment(width: g.size.width * CGFloat(mediaCount) / CGFloat(total), color: WhisperBrandGradient.accent)
                    segment(width: g.size.width * CGFloat(waveCount) / CGFloat(total), color: WhisperBrandGradient.indigo)
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())
            .background(WhisperTheme.hairline(colorScheme), in: Capsule())
            HStack(spacing: 14) {
                legend("Whisps", count: textCount, color: WhisperBrandGradient.mint)
                legend("Media", count: mediaCount, color: WhisperBrandGradient.accent)
                legend("Waves", count: waveCount, color: WhisperBrandGradient.indigo)
            }
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
    }

    private func segment(width: CGFloat, color: Color) -> some View {
        Rectangle().fill(color).frame(width: max(0, width))
    }

    private func legend(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(label) \(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(muted)
        }
    }

    private var topPostsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Top posts")
            if topPosts.isEmpty {
                Text("Your best-performing posts in this window show up here.")
                    .font(.footnote)
                    .foregroundStyle(muted)
            } else {
                ForEach(Array(topPosts.enumerated()), id: \.element.id) { idx, entry in
                    HStack(spacing: 12) {
                        Text("\(idx + 1)")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(WhisperBrandGradient.diagonal, in: Circle())
                        thumb(entry)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(captionLine(entry))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ink)
                                .lineLimit(2)
                            Text("\(shortNumber(entry.likes)) likes · \(shortNumber(entry.comments)) comments · \(WhisperAnalyticsDates.short(entry.date))")
                                .font(.caption)
                                .foregroundStyle(muted)
                        }
                        Spacer(minLength: 0)
                    }
                    if idx < topPosts.count - 1 {
                        Divider().background(WhisperTheme.hairline(colorScheme))
                    }
                }
            }
        }
        .padding(14)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
    }

    private func thumb(_ entry: Entry) -> some View {
        let url = entry.row.media_urls?.first.flatMap { URL(string: $0) }
        return WhisperTheme.hairline(colorScheme)
            .frame(width: 44, height: entry.isWave ? 60 : 44)
            .overlay {
                if let url, !WhisperVideo.isVideo(url) {
                    WhisperCachedAsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().aspectRatio(contentMode: .fill).allowsHitTesting(false)
                        }
                    }
                } else {
                    Image(systemName: entry.isWave ? "play.rectangle.fill" : (entry.hasMedia ? "photo" : "text.alignleft"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(muted)
                }
            }
            .clipShape(.rect(cornerRadius: 8))
    }

    /// The separation, stated plainly: Creator Studio is a verified-only
    /// surface. Professional accounts see what it adds and where to apply.
    private var creatorStudioNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 1.0))
                Text("Creator Studio is for verified creators")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ink)
            }
            Text("Verification adds the creator score, WPP creator pay from ad revenue, momentum tracking, pinned posts, and the grid composer. Analytics here is the professional tier — apply for verification from Settings → Verification when you're ready.")
                .font(.footnote)
                .foregroundStyle(muted)
                .lineSpacing(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.card(colorScheme).opacity(0.6), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
        }
    }

    private func captionLine(_ entry: Entry) -> String {
        let stripped = WhisperPostMeta.strip(from: entry.row.caption ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.isEmpty { return entry.isWave ? "Wave" : "Media post" }
        return stripped
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(muted)
            .textCase(.uppercase)
    }

    private func delta(_ now: Int, _ before: Int) -> Int? {
        guard before > 0 else { return now > 0 ? 100 : nil }
        return Int((Double(now - before) / Double(before) * 100).rounded())
    }

    private func shortNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000 { return String(format: "%.0fK", Double(n) / 1_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

/// ISO-8601 parsing shared by the analytics + activity screens.
nonisolated enum WhisperAnalyticsDates {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        return fractional.date(from: iso) ?? plain.date(from: iso)
    }

    static func short(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func monthYear(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }
}
