import SwiftUI

/// "From the journal" inline shelf — surfaces published Whisper articles
/// inside the social feed so long-form writing feels like a native content
/// break, not a boxed advertisement. Tapping a card opens a full native reader
/// so the user never leaves the app.
struct FeedArticlesCarousel: View {
    let articles: [WhisperArticle]
    @Environment(\.colorScheme) private var colorScheme
    @State private var showAll: Bool = false

    var body: some View {
        WhisperStableShelf {
          VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if articles.isEmpty {
                        Text("No articles available right now").font(.subheadline).foregroundStyle(.secondary).padding(24)
                    }
                    ForEach(articles.prefix(8)) { article in
                        ArticleCard(article: article)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 14)
        }
        .background(WhisperTheme.surface(colorScheme))
        .sheet(isPresented: $showAll) {
            WhisperArticlesSeeAllSheet(articles: articles)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("From the journal")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Spacer()
            WhisperShelfSeeAllButton { showAll = true }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Card

    private struct ArticleCard: View {
        let article: WhisperArticle
        @Environment(\.colorScheme) private var colorScheme
        @State private var showReader: Bool = false

        var body: some View {
            Button {
                Haptics.tap()
                showReader = true
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    // Full-bleed cover image with gradient overlay
                    ZStack(alignment: .bottomLeading) {
                        coverImage
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
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.white.opacity(0.2), in: Capsule())
                                .padding(.leading, 12)
                                .padding(.bottom, 12)
                        }
                    }
                    .frame(width: 260, height: 150)
                    .clipShape(.rect(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(article.title)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        if !article.excerpt.isEmpty {
                            Text(article.excerpt)
                                .font(.caption)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }

                        HStack(spacing: 6) {
                            Text(article.author_name ?? "Whisper Team")
                                .font(.caption2.weight(.semibold))
                            if !article.formattedDate.isEmpty {
                                Text("·")
                                    .font(.caption2)
                                Text(article.formattedDate)
                                    .font(.caption2)
                            }
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    .padding(12)
                }
                .frame(width: 260)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
                .contentShape(.rect)
            }
            .buttonStyle(WhisperMenuPressStyle())
            .sheet(isPresented: $showReader) {
                WhisperArticleReaderView(article: article)
                    .ignoresSafeArea()
            }
        }

        @ViewBuilder
        private var coverImage: some View {
            if let cover = article.cover_url, !cover.isEmpty, let url = URL(string: cover) {
                WhisperCachedAsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }

        private var placeholder: some View {
            ZStack {
                WhisperTheme.ink(colorScheme).opacity(0.06)
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.2))
            }
        }
    }
}
