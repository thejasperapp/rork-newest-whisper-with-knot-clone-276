import SwiftUI

// MARK: - Film embed

/// Inline "shared film" payload — sent through DMs and planted in wall
/// posts (`::whisper-film-v1::{json}` line). Mirrored 1:1 on web so a film
/// shared from either app renders as a tappable cinema card on both.
nonisolated enum WhisperFilmEmbed {
    static let prefix = "::whisper-film-v1::"

    nonisolated struct Payload: Codable, Sendable, Hashable, Identifiable {
        let id: String
        let title: String
        let director: String
        var poster: String? = nil
        var duration: Int? = nil
    }

    nonisolated static func encode(_ p: Payload) -> String {
        guard let data = try? JSONEncoder().encode(p),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return prefix + json
    }

    nonisolated static func decode(_ body: String) -> Payload? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return nil }
        let json = String(trimmed.dropFirst(prefix.count))
        guard let data = json.data(using: .utf8),
              let p = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return p
    }
}

// MARK: - Article embed

/// Inline "shared article" payload (`::whisper-article-v1::{json}`) —
/// same contract as the film embed, rendered as a journal card.
nonisolated enum WhisperArticleEmbed {
    static let prefix = "::whisper-article-v1::"

    nonisolated struct Payload: Codable, Sendable, Hashable, Identifiable {
        let id: String
        let slug: String
        let title: String
        let author: String
        var cover: String? = nil
        var category: String? = nil
    }

    nonisolated static func encode(_ p: Payload) -> String {
        guard let data = try? JSONEncoder().encode(p),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return prefix + json
    }

    nonisolated static func decode(_ body: String) -> Payload? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return nil }
        let json = String(trimmed.dropFirst(prefix.count))
        guard let data = json.data(using: .utf8),
              let p = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return p
    }
}

// MARK: - Caption parser

/// Splits a post caption into visible text + any film/article embed lines
/// planted by "Post to your wall". Cheap guard first so normal captions
/// never pay for line scanning.
nonisolated enum WhisperContentEmbedParser {
    nonisolated struct Split: Sendable {
        var cleaned: String
        var film: WhisperFilmEmbed.Payload?
        var article: WhisperArticleEmbed.Payload?
        var quote: WhisperSharedPostEmbed.Payload? = nil
    }

    nonisolated static func parse(_ text: String) -> Split {
        guard text.contains("::whisper-") else {
            return Split(cleaned: text, film: nil, article: nil)
        }
        var film: WhisperFilmEmbed.Payload?
        var article: WhisperArticleEmbed.Payload?
        var quote: WhisperSharedPostEmbed.Payload?
        var kept: [String] = []
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if film == nil, let f = WhisperFilmEmbed.decode(t) {
                film = f
                continue
            }
            if article == nil, let a = WhisperArticleEmbed.decode(t) {
                article = a
                continue
            }
            if t.hasPrefix(WhisperSharedPostEmbed.prefix) {
                if quote == nil { quote = WhisperSharedPostEmbed.decode(t) }
                continue
            }
            kept.append(line)
        }
        return Split(
            cleaned: kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            film: film,
            article: article,
            quote: quote
        )
    }
}

// MARK: - Film inline card

/// Tappable cinema card for a shared film — self-contained: it hydrates
/// the real film row on tap and opens the full theater.
struct WhisperFilmEmbedInlineCard: View {
    let payload: WhisperFilmEmbed.Payload

    @State private var film: WhisperFeedFilm?
    @State private var loading: Bool = false
    @State private var presenting: Bool = false

    var body: some View {
        Button {
            open()
        } label: {
            ZStack(alignment: .bottomLeading) {
                Color(white: 0.07)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        if let poster = payload.poster, let url = URL(string: poster) {
                            WhisperCachedAsyncImage(url: url) { phase in
                                if let img = phase.image {
                                    img.resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .allowsHitTesting(false)
                                }
                            }
                        } else {
                            Image(systemName: "film.fill")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(.white.opacity(0.18))
                        }
                    }
                    .clipped()
                LinearGradient(
                    colors: [.black.opacity(0.0), .black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8, weight: .black))
                        Text("WHISPER STUDIOS")
                            .font(.system(size: 8, weight: .black))
                            .tracking(1.1)
                        if let d = payload.duration, d > 0 {
                            Text("· \(FeedFilmsCarousel.formatTimecode(d))")
                                .font(.system(size: 8, weight: .black))
                                .monospacedDigit()
                        }
                    }
                    .foregroundStyle(.white.opacity(0.75))
                    Text(payload.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("A \(payload.director) film")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
                .padding(11)

                if loading {
                    Color.black.opacity(0.35).allowsHitTesting(false)
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: 270)
            .clipShape(.rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Watch \(payload.title)")
        .fullScreenCover(isPresented: $presenting) {
            if let film {
                WhisperFilmDetailView(film: film)
            }
        }
    }

    private func open() {
        Haptics.tap()
        if film != nil {
            presenting = true
            return
        }
        guard !loading else { return }
        loading = true
        Task {
            let fetched = await WhisperFilmEngagementService.shared.fetchFilm(id: payload.id)
            await MainActor.run {
                loading = false
                if let fetched {
                    film = fetched
                    presenting = true
                } else {
                    Haptics.warning()
                }
            }
        }
    }
}

// MARK: - Article inline card

/// Tappable journal card for a shared article — hydrates the published
/// article on tap and opens the native reader.
struct WhisperArticleEmbedInlineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: WhisperArticleEmbed.Payload

    @State private var article: WhisperArticle?
    @State private var loading: Bool = false
    @State private var presenting: Bool = false

    var body: some View {
        Button {
            open()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    Color(white: 0.10)
                        .frame(height: 96)
                        .overlay {
                            if let cover = payload.cover, let url = URL(string: cover) {
                                WhisperCachedAsyncImage(url: url) { phase in
                                    if let img = phase.image {
                                        img.resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .allowsHitTesting(false)
                                    }
                                }
                            } else {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.16))
                            }
                        }
                        .clipped()
                    if let cat = payload.category, !cat.isEmpty {
                        Text(cat.uppercased())
                            .font(.system(size: 8, weight: .black))
                            .tracking(0.8)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.45), in: Capsule())
                            .padding(8)
                    }
                    if loading {
                        Color.black.opacity(0.3)
                            .frame(height: 96)
                            .overlay { ProgressView().tint(.white) }
                            .allowsHitTesting(false)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(payload.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 5) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 9, weight: .bold))
                        Text("By \(payload.author)")
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text("Read")
                            .font(.caption2.weight(.black))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .heavy))
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
                .padding(11)
            }
            .frame(maxWidth: 270)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
            .clipShape(.rect(cornerRadius: 18))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Read \(payload.title)")
        .sheet(isPresented: $presenting) {
            if let article {
                WhisperArticleReaderView(article: article)
                    .ignoresSafeArea()
            }
        }
    }

    private func open() {
        Haptics.tap()
        if article != nil {
            presenting = true
            return
        }
        guard !loading else { return }
        loading = true
        Task {
            let svc = WhisperArticlesService.shared
            if svc.publishedArticles.isEmpty {
                await svc.fetchPublished()
            }
            let found = svc.publishedArticles.first { $0.id == payload.id }
            await MainActor.run {
                loading = false
                if let found {
                    article = found
                    presenting = true
                } else {
                    Haptics.warning()
                }
            }
        }
    }
}

// MARK: - Share sheet

/// One share surface for films and articles — send into DMs as a tappable
/// card, repost to your wall through the real composer, or fall out to the
/// system share sheet. Recipients mirror the post-forward sheet: recent DM
/// threads first, then everyone you follow.
struct WhisperContentShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// "WHISPER FILM" / "WHISPER JOURNAL" — the preview kicker.
    let kicker: String
    let title: String
    let subtitle: String
    let imageURL: URL?
    /// The `::whisper-…::` embed line sent as the DM body / wall draft.
    let embedBody: String
    let linkURL: URL
    /// "Post to your wall" — the host dismisses its stack and opens the
    /// real composer prefilled with the embed line.
    let onRepost: () -> Void

    @State private var follows = WhisperFollowService.shared
    @State private var backend = WhisperBackendService.shared
    @State private var query: String = ""
    @State private var sentTo: Set<String> = []

    /// Lightweight recipient row — DM threads first, then follows.
    private struct ShareRecipient: Identifiable {
        let userID: String
        let username: String
        let hasThread: Bool
        var id: String { userID }
    }

    private var recipients: [ShareRecipient] {
        let me = AccountStorage.currentUserID.lowercased()
        var seen: Set<String> = []
        var out: [ShareRecipient] = []
        let sortedThreads = backend.threads.sorted { $0.lastDate > $1.lastDate }
        for t in sortedThreads {
            let key = t.otherUserID.lowercased()
            guard key != me, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(ShareRecipient(
                userID: t.otherUserID,
                username: t.otherUsername,
                hasThread: true
            ))
        }
        for (id, name) in follows.followingUsernames {
            let key = id.lowercased()
            guard key != me, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(ShareRecipient(
                userID: id,
                username: name,
                hasThread: false
            ))
        }
        return out
    }

    private var filtered: [ShareRecipient] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return recipients }
        return recipients.filter { $0.username.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        previewCard
                        repostRow
                        searchBar
                        if recipients.isEmpty {
                            emptyRecipients
                        } else {
                            VStack(spacing: 0) {
                                ForEach(filtered) { r in
                                    recipientRow(r)
                                    Divider().background(WhisperTheme.hairline(colorScheme))
                                }
                            }
                            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
                            }
                            .padding(.horizontal, 16)
                        }
                        moreOptionsRow
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            .task {
                async let f: () = follows.refresh()
                async let t: () = backend.fetchThreads()
                _ = await (f, t)
            }
        }
    }

    private var previewCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Color(white: 0.10)
                if let imageURL {
                    WhisperCachedAsyncImage(url: imageURL) { phase in
                        if let img = phase.image {
                            img.resizable().aspectRatio(contentMode: .fill)
                        }
                    }
                } else {
                    Image(systemName: kicker.contains("FILM") ? "film.fill" : "doc.text.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(.rect(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text(kicker)
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    private var repostRow: some View {
        Button {
            Haptics.success()
            dismiss()
            onRepost()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.93, green: 0.42, blue: 0.22), Color(red: 1.00, green: 0.70, blue: 0.40)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "arrow.2.squarepath")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Post to your wall")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text("Opens the composer — add your take, it lands as a card.")
                        .font(.caption2)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(12)
            .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    private var moreOptionsRow: some View {
        ShareLink(item: linkURL) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                    .font(.footnote.weight(.bold))
                Text("More options")
                    .font(.footnote.weight(.bold))
            }
            .foregroundStyle(WhisperTheme.ink(colorScheme))
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(WhisperTheme.card(colorScheme), in: Capsule())
            .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
        }
        .padding(.horizontal, 16)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WhisperTheme.muted(colorScheme))
            TextField("Search people", text: $query)
                .foregroundStyle(WhisperTheme.ink(colorScheme))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    private var emptyRecipients: some View {
        Text("Follow people or start a DM to send this in chat.")
            .font(.caption)
            .foregroundStyle(WhisperTheme.muted(colorScheme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
    }

    private func recipientRow(_ r: ShareRecipient) -> some View {
        let sent = sentTo.contains(r.userID)
        return HStack(spacing: 12) {
            WhisperAvatar(username: r.username, size: 36, ring: false)
            VStack(alignment: .leading, spacing: 1) {
                Text("@\(r.username)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Text(r.hasThread ? "In your messages" : "Following")
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            Spacer()
            Button {
                Haptics.tap()
                Task {
                    let ok = await backend.sendMessage(
                        toUserID: r.userID,
                        toUsername: r.username,
                        body: embedBody
                    )
                    if ok { sentTo.insert(r.userID) }
                }
            } label: {
                Text(sent ? "Sent" : "Send")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(sent ? WhisperTheme.ink(colorScheme) : WhisperTheme.surface(colorScheme))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(sent ? WhisperTheme.card(colorScheme) : WhisperTheme.ink(colorScheme), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(sent ? WhisperTheme.hairline(colorScheme) : .clear, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(sent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
