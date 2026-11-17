import SwiftUI
import LinkPresentation
import UIKit

/// LINKS IN CHAT — a message that carries a URL renders the URL as a real,
/// tappable link inside the bubble AND unfurls a preview card beneath it
/// (site image · title · host), the way Instagram and iMessage do. The
/// metadata comes from Apple's LinkPresentation framework (the same fetcher
/// iMessage uses) and is cached per URL for the session so scrolling never
/// refetches.
/// Thread-safe memo for `firstLinkURL` — the detector ran on every visible
/// bubble on every render of the thread (every keystroke). Bounded.
private final class WhisperLinkURLCache: @unchecked Sendable {
    private let lock = NSLock()
    private var map: [String: URL?] = [:]

    func lookup(_ key: String) -> URL?? {
        lock.lock(); defer { lock.unlock() }
        return map[key]
    }

    func store(_ key: String, _ value: URL?) {
        lock.lock(); defer { lock.unlock() }
        if map.count > 3000 { map.removeAll(keepingCapacity: true) }
        map[key] = value
    }
}

enum WhisperLinkDetector {
    /// One shared detector — `NSDataDetector` is immutable and thread-safe,
    /// and creating one per call was measurable at chat scale.
    nonisolated(unsafe) private static let detector: NSDataDetector? =
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    nonisolated(unsafe) private static let cache = WhisperLinkURLCache()

    /// The first http(s) URL inside a message body — nil for bodies that are
    /// ONLY a bare image URL (those render as image bubbles already) and for
    /// Whisper wire tokens (`::whisper-…::`, `jasper-sticker://`).
    nonisolated static func firstLinkURL(in body: String) -> URL? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("::"), !trimmed.hasPrefix("{") else { return nil }
        // No dot → no host → no link. Most chat lines exit here for free.
        guard trimmed.contains(".") else { return nil }
        if let cached = cache.lookup(trimmed) { return cached }
        var found: URL? = nil
        if let detector {
            let ns = trimmed as NSString
            let matches = detector.matches(in: trimmed, options: [], range: NSRange(location: 0, length: ns.length))
            for match in matches {
                guard let url = match.url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { continue }
                if WhisperDMThreadView.imageURL(in: url.absoluteString) != nil { continue }
                found = url
                break
            }
        }
        cache.store(trimmed, found)
        return found
    }

    /// The body with every URL turned into a tappable `.link` run (underlined)
    /// so `Text` opens it on tap.
    nonisolated static func linkedAttributedString(_ body: String, linkColor: Color) -> AttributedString {
        var attributed = AttributedString(body)
        guard let detector else { return attributed }
        let ns = body as NSString
        let matches = detector.matches(in: body, options: [], range: NSRange(location: 0, length: ns.length))
        for match in matches {
            guard let url = match.url,
                  let range = Range(match.range, in: body),
                  let lower = AttributedString.Index(range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(range.upperBound, within: attributed) else { continue }
            attributed[lower..<upper].link = url
            attributed[lower..<upper].underlineStyle = .single
            attributed[lower..<upper].foregroundColor = linkColor
        }
        return attributed
    }
}

/// Bubble text whose URLs are live links (own bubbles keep surface-colored
/// text, so the links stay readable on ink).
struct WhisperLinkedText: View {
    let text: String
    let mine: Bool

    @Environment(\.colorScheme) private var colorScheme

    @Environment(\.whisperChatAppearance) private var appearance
    @Environment(\.whisperChatDesign) private var design

    var body: some View {
        let base = (design?.palette(colorScheme) ?? appearance.palette(colorScheme)).text(mine: mine)
        Text(WhisperLinkDetector.linkedAttributedString(text, linkColor: base))
            .font(WhisperChatStyle.bodyFont)
            .foregroundStyle(base)
            .tint(base)
    }
}

/// Session cache of unfurled metadata — one fetch per URL, ever.
@MainActor
final class WhisperLinkMetadataCache {
    static let shared = WhisperLinkMetadataCache()

    struct Entry {
        var title: String?
        var host: String
        var image: UIImage?
    }

    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<Entry, Never>] = [:]

    func cached(_ url: URL) -> Entry? { entries[url.absoluteString] }

    func fetch(_ url: URL) async -> Entry {
        let key = url.absoluteString
        if let hit = entries[key] { return hit }
        if let running = inFlight[key] { return await running.value }
        let task = Task<Entry, Never> {
            let provider = LPMetadataProvider()
            provider.timeout = 8
            var entry = Entry(title: nil, host: url.host?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString, image: nil)
            if let metadata = try? await provider.startFetchingMetadata(for: url) {
                entry.title = metadata.title
                if let final = metadata.url ?? metadata.originalURL, let host = final.host {
                    entry.host = host.replacingOccurrences(of: "www.", with: "")
                }
                if let imageProvider = metadata.imageProvider {
                    entry.image = await Self.loadImage(from: imageProvider)
                }
            }
            return entry
        }
        inFlight[key] = task
        let result = await task.value
        entries[key] = result
        inFlight[key] = nil
        return result
    }

    private static func loadImage(from provider: NSItemProvider) async -> UIImage? {
        await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
    }
}

/// The preview card under a link message — image on top when the page has
/// one, then title (ink, semibold) and host (muted). Tapping opens the URL.
struct WhisperLinkPreviewCard: View {
    let url: URL
    let mine: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var entry: WhisperLinkMetadataCache.Entry?

    private var ink: Color { WhisperTheme.ink(colorScheme) }
    private var muted: Color { WhisperTheme.muted(colorScheme) }

    var body: some View {
        Button {
            Haptics.tap()
            openURL(url)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if let image = entry?.image {
                    Color.clear
                        .frame(height: 140)
                        .overlay {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .allowsHitTesting(false)
                        }
                        .clipped()
                }
                HStack(spacing: 10) {
                    if entry?.image == nil {
                        Image(systemName: "link")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ink)
                            .frame(width: 38, height: 38)
                            .background(WhisperTheme.surface(colorScheme), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        if WhisperNotesLink.parse(url) != nil {
                            Text("Open in Whisper Notes")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ink)
                        } else if let title = entry?.title, !title.isEmpty {
                            Text(title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        } else if entry == nil {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(WhisperTheme.hairline(colorScheme))
                                .frame(width: 150, height: 12)
                        }
                        Text(entry?.host ?? (url.host?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString))
                            .font(.system(size: 12))
                            .foregroundStyle(muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(width: 250, alignment: .leading)
            .background(WhisperTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.75)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .task(id: url.absoluteString) {
            // Restricted documents have a neutral preview, never a background read.
            if WhisperNotesLink.isNotesURL(url) { entry = nil; return }
            if let hit = WhisperLinkMetadataCache.shared.cached(url) {
                entry = hit
                return
            }
            let fetched = await WhisperLinkMetadataCache.shared.fetch(url)
            withAnimation(.easeOut(duration: 0.2)) { entry = fetched }
        }
        .accessibilityLabel("Link preview: \(entry?.title ?? url.absoluteString)")
    }
}
