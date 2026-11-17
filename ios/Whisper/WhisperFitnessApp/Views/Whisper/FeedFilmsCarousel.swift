import SwiftUI

/// "Featured Film Friday" inline shelf — surfaces published Whisper films
/// inside the social feed so premieres feel like a native content break,
/// not a separate destination you have to know about. Mirrors the web's
/// eventized films page: only the current/most-recent premiere is shown as
/// the hero card, with a compact archive rail beside it. Tapping a card
/// opens the full cinema experience (`WhisperFilmDetailView`) — custom
/// player, reactions, moments rail, and the comment thread.
struct FeedFilmsCarousel: View {
    let films: [WhisperFeedFilm]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        WhisperStableShelf {
          VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if films.isEmpty {
                        Text("No films available right now").font(.subheadline).foregroundStyle(.secondary).padding(24)
                    }
                    ForEach(films.prefix(8)) { film in
                        FilmCard(film: film)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 14)
        }
        .background(WhisperTheme.surface(colorScheme))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "film.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Text("Featured Film Friday")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            Spacer()
            if films.count > 1 {
                Text("Whisper Studios")
                    .font(.caption2.weight(.bold))
                    .tracking(0.4)
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Card

    /// Formats a duration in seconds as `m:ss` (or `h:mm:ss` for long films).
    /// Free helper so nested card types can call it without reaching into the
    /// enclosing detail view's private scope.
    static func formatTimecode(_ seconds: Int) -> String {
        if seconds >= 3600 {
            let h = seconds / 3600
            let m = (seconds % 3600) / 60
            let s = seconds % 60
            return "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", s))"
        } else {
            let m = seconds / 60
            let s = seconds % 60
            return "\(m):\(String(format: "%02d", s))"
        }
    }

    private struct FilmCard: View {
        let film: WhisperFeedFilm
        @Environment(\.colorScheme) private var colorScheme
        @State private var showDetail: Bool = false

        var body: some View {
            Button {
                Haptics.tap()
                showDetail = true
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .bottomLeading) {
                        posterStage
                        LinearGradient(
                            colors: [.black.opacity(0.0), .black.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .allowsHitTesting(false)

                        // "Featured Film" tag
                        Text("FEATURED FILM")
                            .font(.caption2.weight(.black))
                            .tracking(0.5)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.2), in: Capsule())
                            .padding(.leading, 12)
                            .padding(.bottom, 12)
                    }
                    .frame(width: 280, height: 158)
                    .clipShape(.rect(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(film.title)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        if let s = film.synopsis, !s.isEmpty {
                            Text(s)
                                .font(.caption)
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }

                        HStack(spacing: 6) {
                            if let name = film.director_name ?? film.director_username, !name.isEmpty {
                                Text(name)
                                    .font(.caption2.weight(.semibold))
                            }
                            if let secs = film.duration_seconds, secs > 0 {
                                Text("·")
                                    .font(.caption2)
                                Text(FeedFilmsCarousel.formatTimecode(secs))
                                    .font(.caption2.weight(.semibold))
                            }
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(WhisperTheme.muted(colorScheme))
                    }
                    .padding(12)
                }
                .frame(width: 280)
                .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
                .contentShape(.rect)
            }
            .buttonStyle(WhisperMenuPressStyle())
            .fullScreenCover(isPresented: $showDetail) {
                WhisperFilmDetailView(film: film)
            }
        }

        @ViewBuilder
        private var posterStage: some View {
            if let p = film.poster_url, let url = URL(string: p) {
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
                LinearGradient(
                    colors: [Color.black, Color(white: 0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "film.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
    }
}

// MARK: - Feed film model

/// Lightweight film row used by the feed carousel. Mirrors the subset of
/// columns the feed shelf needs — the full film detail view hydrates the
/// rest (reactions, comments, timestamps) on open.
struct WhisperFeedFilm: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let synopsis: String?
    let video_url: String
    let poster_url: String?
    let duration_seconds: Int?
    let featured_date: String?
    let director_id: String?
    let director_name: String?
    let director_username: String?
}
