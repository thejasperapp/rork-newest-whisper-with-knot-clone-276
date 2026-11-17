import SwiftUI

/// The same media tile for owner and visitor profiles. Videos use posters, not players.
struct WhisperProfileMediaTile: View {
    let row: WhisperPostRow
    @Environment(\.colorScheme) private var colorScheme
    @State private var retry: Int = 0

    var body: some View {
        let url = row.media_urls?.first.flatMap(URL.init(string:))
        let metadata = WhisperPostMeta.parse(from: row.caption)
        Group {
            if let url, WhisperVideo.isVideo(url) {
                WhisperWaveGridTile(row: row, tileAspect: 1)
            } else {
                WhisperTheme.card(colorScheme)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        WhisperSizedAsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                            case .empty: WhisperPhotoLoader()
                            default: Image(systemName: "photo").foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                        }
                        .id(retry)
                        .allowsHitTesting(false)
                    }
                    .clipped()
                    .overlay(alignment: .bottomLeading) {
                        if metadata?.hideCounts != true {
                            HStack(spacing: 8) {
                                if (row.likes_count ?? 0) > 0 { Label((row.likes_count ?? 0).formatted(), systemImage: "heart.fill") }
                                if metadata?.commentsOff != true && (row.comments_count ?? 0) > 0 { Label((row.comments_count ?? 0).formatted(), systemImage: "bubble.right.fill") }
                            }
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black, radius: 3)
                            .padding(6)
                            .allowsHitTesting(false)
                        }
                    }
            }
        }
        .overlay(alignment: .topTrailing) {
            if (row.media_urls?.count ?? 0) > 1 {
                Image(systemName: "square.fill.on.square.fill")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2).padding(6)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel("Post by \(row.username ?? "member")")
    }
}
