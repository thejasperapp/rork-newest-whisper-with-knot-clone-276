import SwiftUI
import AVFoundation
import UIKit

/// A 9:16 wave tile for the profile's Waves grid — a poster frame pulled
/// from the video (cached in memory so scrolling never regenerates), the
/// play glyph, and the like count bottom-left in Instagram's grammar.
struct WhisperWaveGridTile: View {
    let row: WhisperPostRow
    var tileAspect: CGFloat = 9.0 / 16.0
    @Environment(\.colorScheme) private var colorScheme
    @State private var poster: UIImage?

    private var videoURL: URL? {
        row.media_urls?.compactMap { URL(string: $0) }.first(where: { WhisperVideo.isVideo($0) })
            ?? row.media_urls?.first.flatMap { URL(string: $0) }
    }

    var body: some View {
        WhisperTheme.card(colorScheme)
            .aspectRatio(tileAspect, contentMode: .fit)
            .overlay {
                if let poster {
                    Image(uiImage: poster)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                } else {
                    LinearGradient(
                        colors: [Color.black.opacity(0.55), Color.black.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }
            }
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 48)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                    if WhisperPostMeta.parse(from: row.caption)?.hideCounts != true {
                        Text(Self.compact(row.likes_count ?? 0))
                            .font(.system(size: 11, weight: .heavy))
                    }
                }
                .foregroundStyle(.white)
                .padding(6)
                .allowsHitTesting(false)
            }
            .task(id: row.id) {
                guard poster == nil else { return }
                // The creator's picked COVER (on the caption meta wire) wins;
                // a frame pulled from the video is only the fallback.
                if let cover = WhisperPostMeta.coverURL(from: row.caption) {
                    poster = await WhisperWavePosterCache.shared.poster(for: cover)
                    if poster != nil { return }
                }
                guard let url = videoURL else { return }
                poster = await WhisperWavePosterCache.shared.poster(for: url)
            }
    }

    private static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

/// Poster frames for wave tiles — one generation per URL, then memory.
@MainActor
final class WhisperWavePosterCache {
    static let shared = WhisperWavePosterCache()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 72
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    func reset() {
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        cache.removeAllObjects()
    }

    func poster(for url: URL) async -> UIImage? {
        let generation = AccountStorage.generation
        let key = generation.uuidString + ":" + url.absoluteString
        if let hit = cache.object(forKey: key as NSString) { return hit }
        if let running = inFlight[key] {
            let result = await running.value
            return !Task.isCancelled && generation == AccountStorage.generation ? result : nil
        }
        let task = Task<UIImage?, Never> {
            await Self.generate(url: url)
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        guard !Task.isCancelled, generation == AccountStorage.generation else { return nil }
        if let image {
            let cost = (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)
            cache.setObject(image, forKey: key as NSString, cost: cost)
        }
        return image
    }

    nonisolated private static func generate(url: URL) async -> UIImage? {
        // Image URLs (a poster already) short-circuit through the image cache.
        if !WhisperVideo.isVideo(url) {
            return await WhisperImageCache.load(url, maxPixelSize: 960)
        }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 540, height: 960)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        let time = CMTime(seconds: 0.4, preferredTimescale: 600)
        guard let (cgImage, _) = try? await generator.image(at: time) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
