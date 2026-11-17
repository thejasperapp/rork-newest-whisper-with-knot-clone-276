import SwiftUI

/// The feed's WAVES break — Instagram's "Suggested reels" grammar. No shelf
/// plate, no card chrome: a quiet title row ("Suggested waves" + ⋯) and tall
/// 9:16 tiles that sit seamlessly inside the feed with the wave's caption
/// laid over the video and a ⋯ on every tile. Tap opens the wave; LONG-PRESS
/// peeks it — the tile squeezes under the finger, then the whole app blurs
/// and the wave lifts into the big preview card with Like · Repost · Share ·
/// View profile · Report (see `WhisperPeekCenter`).
struct FeedReelsCarousel: View {
    let pool: [WhisperPost]
    let seed: Int
    let onTap: (WhisperPost) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var showAll: Bool = false
    @State private var pressingID: UUID?
    /// "Not interested" hides a tile for this session.
    @State private var hidden: Set<UUID> = []

    private let tileWidth: CGFloat = 160
    private let tileHeight: CGFloat = 284

    var body: some View {
        // Rotate the pool by the shelf's seed so consecutive shelves show
        // different waves, WITHOUT wrapping duplicates (identity stays clean).
        let start = (seed * 2) % max(pool.count, 1)
        let rotated = Array(pool.dropFirst(start) + pool.prefix(start))
        let reels = Array(rotated.filter { !hidden.contains($0.id) }.prefix(8))
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Suggested waves")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                Spacer(minLength: 0)
                Menu {
                    Button {
                        Haptics.tap()
                        showAll = true
                    } label: {
                        Label("See all waves", systemImage: "square.grid.3x3")
                    }
                    Button {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            for r in reels { hidden.insert(r.id) }
                        }
                    } label: {
                        Label("Not interested", systemImage: "eye.slash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .frame(width: 36, height: 30)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Suggested waves options")
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    if reels.isEmpty {
                        Text("You're all caught up").font(.subheadline).foregroundStyle(.secondary)
                            .frame(width: 260, height: tileHeight)
                    }
                    ForEach(reels) { r in
                        tile(r)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: tileHeight + 4)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollClipDisabled()
        }
        .padding(.vertical, 6)
        .sheet(isPresented: $showAll) {
            WhisperWavesSeeAllSheet(pool: pool, onTap: onTap)
        }
    }

    // MARK: Tile

    private func tile(_ post: WhisperPost) -> some View {
        let caption = post.displayCaption.trimmingCharacters(in: .whitespacesAndNewlines)
        let pressing = pressingID == post.id
        return ZStack(alignment: .top) {
            media(post)

            // A soft top shade so the caption + ⋯ read on any footage.
            LinearGradient(colors: [.black.opacity(0.42), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)

            if !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .shadow(color: .black.opacity(0.6), radius: 4, y: 1)
                    .padding(.horizontal, 14)
                    .padding(.top, 50)
                    .allowsHitTesting(false)
            }

            HStack {
                Spacer(minLength: 0)
                Menu {
                    Button {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            _ = hidden.insert(post.id)
                        }
                    } label: {
                        Label("Not interested", systemImage: "eye.slash")
                    }
                    Button {
                        Haptics.tap()
                        WhisperPeekCenter.shared.sharePost = post
                    } label: {
                        Label("Share", systemImage: "paperplane")
                    }
                    Button {
                        Haptics.tap()
                        WhisperPeekCenter.shared.present(.wave(post))
                    } label: {
                        Label("Preview", systemImage: "eye")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 3)
                        .frame(width: 40, height: 40)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Wave options")
            }
            .padding(.trailing, 2)
            .padding(.top, 4)
        }
        .frame(width: tileWidth, height: tileHeight)
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .scaleEffect(pressing ? 0.96 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: pressing)
        .contentShape(.rect)
        .onTapGesture {
            Haptics.tap()
            onTap(post)
        }
        .onLongPressGesture(minimumDuration: 0.3, maximumDistance: 12) {
            pressingID = nil
            WhisperPeekCenter.shared.present(.wave(post))
        } onPressingChanged: { down in
            pressingID = down ? post.id : nil
        }
        .accessibilityLabel("Wave by \(post.username)")
        .accessibilityHint("Double-tap to watch, press and hold to preview")
    }

    @ViewBuilder
    private func media(_ post: WhisperPost) -> some View {
        Color.black
            .overlay {
                Group {
                    if let url = post.mediaURLs.first {
                        if WhisperVideo.isVideo(url) {
                            WhisperVideoView(url: url, autoplay: true, startsMuted: true, showsControls: false)
                        } else {
                            WhisperCachedAsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().aspectRatio(contentMode: .fill)
                                default:
                                    fallback(post)
                                }
                            }
                        }
                    } else {
                        fallback(post)
                    }
                }
                .allowsHitTesting(false)
            }
    }

    private func fallback(_ post: WhisperPost) -> some View {
        LinearGradient(
            colors: [post.accent.opacity(0.95), post.accent.opacity(0.55)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: post.symbol)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}
