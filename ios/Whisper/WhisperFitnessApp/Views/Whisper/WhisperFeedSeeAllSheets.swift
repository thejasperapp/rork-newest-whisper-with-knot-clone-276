import SwiftUI

/// "SEE ALL" for the feed's break shelves — every carousel (Waves · From the
/// journal · People to follow) opens a full grid sheet in the same grammar:
/// surface canvas, inline title, a Done button, and a lazy grid of the SAME
/// cards the shelf shows, so the sheet reads as "the shelf, unrolled".
///
/// Waves — 3 columns of 9:16 tiles.
struct WhisperWavesSeeAllSheet: View {
    let pool: [WhisperPost]
    let onTap: (WhisperPost) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    if pool.isEmpty { WhisperEmptyState(icon: "play.rectangle", title: "No waves yet", message: "New waves will appear here.", isCard: false) }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                        ForEach(pool) { post in
                            Button {
                                Haptics.tap()
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onTap(post) }
                            } label: {
                                tile(post)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Wave by \(post.username)")
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Waves")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }

    private func tile(_ post: WhisperPost) -> some View {
        Color(.secondarySystemBackground)
            .aspectRatio(9 / 16, contentMode: .fit)
            .overlay {
                Group {
                    if let url = post.mediaURLs.first, !WhisperVideo.isVideo(url) {
                        WhisperCachedAsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                            default: gradient(post)
                            }
                        }
                    } else {
                        gradient(post)
                    }
                }
                .allowsHitTesting(false)
            }
            .clipped()
            .overlay(alignment: .topLeading) {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .padding(6)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(post.username)
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill").font(.system(size: 9))
                        Text("\(post.likes)").font(.system(size: 10, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 2)
                .padding(7)
            }
    }

    private func gradient(_ post: WhisperPost) -> some View {
        LinearGradient(
            colors: [post.accent.opacity(0.95), post.accent.opacity(0.55)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: post.symbol)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

/// From the journal — 2 columns of cover cards; tap opens the reader.
struct WhisperArticlesSeeAllSheet: View {
    let articles: [WhisperArticle]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var reader: WhisperArticle?

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    if articles.isEmpty { WhisperEmptyState(icon: "doc.text", title: "No articles yet", message: "New stories from the journal will appear here.", isCard: false) }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
                        ForEach(articles) { article in
                            Button {
                                Haptics.tap()
                                reader = article
                            } label: {
                                card(article)
                            }
                            .buttonStyle(WhisperMenuPressStyle())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("From the journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
            .sheet(item: $reader) { article in
                WhisperArticleReaderView(article: article)
                    .ignoresSafeArea()
            }
        }
    }

    private func card(_ article: WhisperArticle) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Color(.secondarySystemBackground)
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay {
                        if let cover = article.cover_url, !cover.isEmpty, let url = URL(string: cover) {
                            WhisperCachedAsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else {
                                    placeholder
                                }
                            }
                            .allowsHitTesting(false)
                        } else {
                            placeholder
                        }
                    }
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
                if let cat = article.category, !cat.isEmpty {
                    Text(cat.uppercased())
                        .font(.system(size: 9, weight: .black))
                        .tracking(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.22), in: Capsule())
                        .padding(8)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(article.author_name ?? "Whisper Team")
                    .font(.caption2)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                    .lineLimit(1)
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16, style: .continuous))
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .contentShape(.rect)
    }

    private var placeholder: some View {
        ZStack {
            WhisperTheme.ink(colorScheme).opacity(0.06)
            Image(systemName: "doc.text.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.2))
        }
    }
}

/// People to follow — 2 columns of people cards with Follow buttons.
struct WhisperPeopleSeeAllSheet: View {
    let users: [WhisperUserRow]
    let follows: WhisperFollowService
    let onOpenUser: (WhisperUserRow) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                WhisperTheme.surface(colorScheme).ignoresSafeArea()
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(users) { u in
                            card(u)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("People to follow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }

    private func card(_ u: WhisperUserRow) -> some View {
        let followed = follows.isFollowing(userID: u.user_id)
        let avatarURL = u.profile_image_url.flatMap(URL.init(string:))
        return VStack(spacing: 10) {
            Button {
                Haptics.tap()
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onOpenUser(u) }
            } label: {
                VStack(spacing: 8) {
                    WhisperAvatar(username: u.username, size: 72, imageURL: avatarURL, ring: false)
                    Text(u.username)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .lineLimit(1)
                    Text((u.bio?.isEmpty == false ? u.bio! : (u.display_name ?? "Suggested")))
                        .font(.caption2)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(height: 30, alignment: .top)
                }
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                Task {
                    if followed {
                        await follows.unfollow(userID: u.user_id)
                    } else {
                        await follows.follow(userID: u.user_id, username: u.username)
                    }
                }
            } label: {
                Text(followed ? "Following" : "Follow")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(followed ? WhisperTheme.ink(colorScheme) : WhisperTheme.surface(colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(followed ? WhisperTheme.card(colorScheme) : WhisperTheme.ink(colorScheme), in: .rect(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: followed ? 1 : 0)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16, style: .continuous))
        .contentShape(.rect)
    }
}

/// The shared "See all" header affordance for the feed's shelves.
struct WhisperShelfSeeAllButton: View {
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 2) {
                Text("See all")
                    .font(.caption.weight(.bold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(WhisperTheme.muted(colorScheme))
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("See all")
    }
}
