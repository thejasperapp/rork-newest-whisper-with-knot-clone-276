import SwiftUI

/// Inline "shared post" card sent through DM when a user taps the
/// paperplane on a feed/detail post and picks a friend. Encodes enough
/// of the original post into the message body that we can render a
/// rich preview directly inside the chat bubble and deep-link to the
/// real `WhisperPostDetailView` on tap.
nonisolated enum WhisperSharedPostEmbed {
    static let prefix = "::whisper-sharedpost-v1::"

    nonisolated struct Payload: Codable, Sendable, Hashable, Identifiable {
        let postID: String
        let username: String
        let caption: String
        let kindRaw: String
        let symbol: String
        let accentHex: String?
        let mediaURL: String?
        let isVideo: Bool
        let likes: Int
        let comments: Int
        /// True when the shared post is a WAVE — the receiver opens it in the
        /// full-screen Waves player instead of the post detail. Optional so
        /// older embeds (and web's encoder) keep decoding.
        var isReel: Bool? = nil

        var commentID: String? = nil
        var commentUsername: String? = nil
        var commentExcerpt: String? = nil

        var id: String { postID + (commentID.map { ":" + $0 } ?? "") }

        var kind: WhisperPostKind {
            WhisperPostKind(rawValue: kindRaw) ?? .photo
        }
    }

    nonisolated static func encode(_ p: Payload) -> String {
        guard let data = try? JSONEncoder().encode(p),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return prefix + json
    }

    nonisolated static func decode(_ body: String) -> Payload? {
        guard body.hasPrefix(prefix) else { return nil }
        let json = String(body.dropFirst(prefix.count))
        guard let data = json.data(using: .utf8),
              let p = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return p
    }

    /// Rebuilds a lightweight `WhisperPost` from the embed so the bubble
    /// can push directly into `WhisperPostDetailView` and the detail
    /// view immediately renders. The detail view re-fetches comments /
    /// likes from Supabase using the real post id.
    nonisolated static func rebuildPost(_ p: Payload) -> WhisperPost? {
        guard let uuid = UUID(uuidString: p.postID) else { return nil }
        let accent = WhisperPost.color(fromHex: p.accentHex) ?? Color(red: 0.55, green: 0.55, blue: 0.62)
        let urls: [URL] = {
            guard let s = p.mediaURL, let u = URL(string: s) else { return [] }
            return [u]
        }()
        return WhisperPost(
            id: uuid,
            username: p.username,
            timeAgo: "",
            kind: p.kind,
            caption: p.caption,
            symbol: p.symbol,
            accent: accent,
            mediaURLs: urls,
            likes: p.likes,
            comments: p.comments,
            liked: false,
            isReel: p.isReel ?? false,
            createdAt: nil
        )
    }
}

/// Card rendered inside a DM bubble representing a shared post.
///
/// Media (grid) posts get the full Instagram-DM treatment: author header
/// on top, a big square photo/video preview, then the caption and stats —
/// so a shared grid post looks exactly like the post itself, not a link
/// preview. Text-only posts keep a compact quote-style card.
struct WhisperSharedPostInlineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: WhisperSharedPostEmbed.Payload
    let mine: Bool
    var onTap: () -> Void

    private var accent: Color {
        WhisperPost.color(fromHex: payload.accentHex) ?? Color(red: 0.55, green: 0.55, blue: 0.62)
    }

    private var hasMedia: Bool { payload.mediaURL != nil }

    /// Poster frame for a shared WAVE (the picked cover first, else a frame
    /// pulled from the video) — same cache the profile grid uses.
    @State private var wavePoster: UIImage?

    var body: some View {
        Button(action: onTap) {
            if payload.commentID != nil {
                replyCard
            } else if payload.isReel == true {
                waveCard
            } else if hasMedia {
                gridStyleCard
            } else {
                compactCard
            }
        }
        .buttonStyle(.plain)
    }

    private var replyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "text.bubble").font(.body)
                Text("Reply by @\(payload.commentUsername ?? payload.username)")
                    .font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            Text(payload.commentExcerpt ?? "View reply").font(.subheadline).lineLimit(4)
            Text("In @\(payload.username)'s thread").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Label("View reply", systemImage: "arrow.up.right").font(.caption.weight(.semibold))
        }
        .foregroundStyle(WhisperTheme.ink(colorScheme)).padding(14).frame(width: 250, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75) }
    }

    // MARK: - Wave — a bare 9:16 poster, never boxed

    /// A shared wave is JUST the wave: the footage's poster at 9:16 with the
    /// author chip, a play disc, the caption and counts laid over it. The
    /// feed-card box (header + square media + footer) broke the wave's
    /// proportions and made it read as a post. Mirrors the web wave embed.
    private var waveCard: some View {
        let width: CGFloat = 200
        let height: CGFloat = width * 16 / 9
        return Color.black
            .frame(width: width, height: height)
            .overlay {
                if let wavePoster {
                    Image(uiImage: wavePoster)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                } else {
                    LinearGradient(
                        colors: [accent.opacity(0.55), accent.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .allowsHitTesting(false)
                }
            }
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0.42), .clear, .clear, .black.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    WhisperAvatar(username: payload.username, size: 22, ring: false)
                    Text(payload.username)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(10)
            }
            .overlay {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.2))
                        .frame(width: 48, height: 48)
                        .overlay { Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1) }
                    Image(systemName: "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: 1)
                }
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    if !payload.caption.isEmpty {
                        Text(payload.caption)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    HStack(spacing: 10) {
                        Label("\(payload.likes)", systemImage: "heart")
                        Label("\(payload.comments)", systemImage: "bubble.right")
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.92))
                }
                .padding(10)
            }
            .clipShape(.rect(cornerRadius: 18))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            .task(id: payload.mediaURL) {
                guard wavePoster == nil else { return }
                if let cover = WhisperPostMeta.coverURL(from: payload.caption) {
                    wavePoster = await WhisperWavePosterCache.shared.poster(for: cover)
                    if wavePoster != nil { return }
                }
                guard let s = payload.mediaURL, let url = URL(string: s) else { return }
                wavePoster = await WhisperWavePosterCache.shared.poster(for: url)
            }
    }

    // MARK: - Instagram-style media card

    private var gridStyleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Author header ABOVE the media — exactly like an IG share.
            HStack(spacing: 8) {
                WhisperAvatar(username: payload.username, size: 26, ring: false)
                Text(payload.username)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: payload.kind.icon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            mediaPreview(width: 260, height: 260)

            VStack(alignment: .leading, spacing: 7) {
                if !payload.caption.isEmpty {
                    (Text(payload.username).font(.caption.weight(.bold))
                     + Text("  ") 
                     + Text(payload.caption).font(.caption))
                        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.92))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                HStack(spacing: 12) {
                    statChip(icon: "heart", count: payload.likes)
                    statChip(icon: "bubble.right", count: payload.comments)
                    Spacer(minLength: 0)
                    HStack(spacing: 3) {
                        Text(payload.isReel == true ? "Watch wave" : "View post")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .heavy))
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WhisperTheme.muted(colorScheme))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 11)
        }
        .frame(width: 260, alignment: .leading)
        .background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: 20))
    }

    // MARK: - Compact card (text / workout / other kinds)

    private var compactCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            symbolBanner
                .frame(width: 240, height: 92)
                .clipped()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    WhisperAvatar(username: payload.username, size: 20, ring: false)
                    Text("@\(payload.username)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(mine ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
                    Spacer(minLength: 0)
                    Image(systemName: payload.kind.icon)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle((mine ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme)).opacity(0.55))
                }
                if !payload.caption.isEmpty {
                    Text(payload.caption)
                        .font(.caption)
                        .foregroundStyle((mine ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme)).opacity(0.9))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                HStack(spacing: 10) {
                    compactStatChip(icon: "heart", count: payload.likes)
                    compactStatChip(icon: "bubble.right", count: payload.comments)
                    Spacer(minLength: 0)
                    Text("View post")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle((mine ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme)).opacity(0.7))
                }
            }
            .padding(12)
        }
        .frame(width: 240, alignment: .leading)
        .background(
            mine ? WhisperTheme.ink(colorScheme) : WhisperTheme.card(colorScheme),
            in: .rect(cornerRadius: 18)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(mine ? Color.clear : WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: 18))
    }

    // MARK: - Pieces

    @ViewBuilder
    private func mediaPreview(width: CGFloat, height: CGFloat) -> some View {
        Color(.secondarySystemBackground)
            .frame(width: width, height: height)
            .overlay {
                if let s = payload.mediaURL, let url = URL(string: s) {
                    if payload.isVideo {
                        ZStack {
                            LinearGradient(
                                colors: [accent.opacity(0.55), accent.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 44, weight: .bold))
                                .foregroundStyle(.white.opacity(0.95))
                                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                        }
                        .allowsHitTesting(false)
                    } else {
                        WhisperCachedAsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            case .failure:
                                symbolBanner
                            default:
                                symbolBanner.overlay { ProgressView().tint(.white) }
                            }
                        }
                        .allowsHitTesting(false)
                    }
                } else {
                    symbolBanner.allowsHitTesting(false)
                }
            }
            .clipped()
    }

    private var symbolBanner: some View {
        ZStack {
            LinearGradient(
                colors: [accent.opacity(0.65), accent.opacity(0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: payload.symbol)
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
        }
    }

    private func statChip(icon: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text("\(count)")
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(WhisperTheme.ink(colorScheme).opacity(0.7))
    }

    private func compactStatChip(icon: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text("\(count)")
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle((mine ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme)).opacity(0.7))
    }
}
