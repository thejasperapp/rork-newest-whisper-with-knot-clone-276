import SwiftUI

/// Renders a comment body that may include attached media (GIF / sticker
/// URLs, image URLs, voice memo lines) inline. The composer serializes
/// attachments as URL lines appended to the text body — without this view
/// those lines would appear as raw text in the comment row.
struct WhisperCommentBodyView: View {
    let text: String
    /// When true, only the first text segment is rendered (no media) — used
    /// for compact previews like the top-comment row on a feed card.
    var preview: Bool = false
    /// Optional username rendered as a bold "@username " prefix on the
    /// leading text segment (Instagram-style). Pass nil to omit.
    var usernamePrefix: String? = nil
    /// When true, strips a legacy "k/N · " prefix from the leading text
    /// segment. Old self-thread replies were written with that prefix in
    /// the body before we moved numbering into the standalone pill.
    var stripThreadMarker: Bool = false
    /// Uses the full discussion column and reserves media space before loading.
    var usesThreadMediaLayout: Bool = false
    var onOpenReply: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var segments: [WhisperCommentSegment] {
        let parsed = WhisperCommentSegment.parse(text)
        guard stripThreadMarker else { return parsed }
        return parsed.enumerated().map { idx, seg in
            guard idx == 0, case .text(let s) = seg else { return seg }
            return .text(WhisperCommentBodyView.stripLeadingMarker(s))
        }
    }

    /// Strips a leading "k/N · " (or "k/N - ") prefix. Tolerant of optional
    /// whitespace and various unicode dashes/middots so legacy rows render
    /// cleanly next to the pill.
    static func stripLeadingMarker(_ s: String) -> String {
        let trimmed = s.drop { $0.isWhitespace }
        // Match `\d+/\d+` then a separator then a space.
        var i = trimmed.startIndex
        var sawDigit = false
        while i < trimmed.endIndex, trimmed[i].isNumber { sawDigit = true; i = trimmed.index(after: i) }
        guard sawDigit, i < trimmed.endIndex, trimmed[i] == "/" else { return s }
        i = trimmed.index(after: i)
        var sawDigit2 = false
        while i < trimmed.endIndex, trimmed[i].isNumber { sawDigit2 = true; i = trimmed.index(after: i) }
        guard sawDigit2 else { return s }
        // optional whitespace
        while i < trimmed.endIndex, trimmed[i].isWhitespace { i = trimmed.index(after: i) }
        guard i < trimmed.endIndex else { return s }
        let sep = trimmed[i]
        let separators: [Character] = ["·", "•", "-", "—", "–"]
        guard separators.contains(sep) else { return s }
        i = trimmed.index(after: i)
        while i < trimmed.endIndex, trimmed[i].isWhitespace { i = trimmed.index(after: i) }
        return String(trimmed[i...])
    }

    var body: some View {
        if preview {
            previewBody
        } else {
            fullBody
        }
    }

    @ViewBuilder
    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
                segmentView(seg, isFirst: idx == 0)
            }
            if let onOpenReply, !segments.contains(where: { if case .text = $0 { return true }; return false }) {
                Button("View reply", action: onOpenReply)
                    .font(.caption).foregroundStyle(WhisperTheme.muted(colorScheme))
                    .frame(minHeight: 44)
            }
        }
    }

    @ViewBuilder
    private var previewBody: some View {
        let firstText: WhisperCommentSegment? = segments.first(where: {
            if case .text = $0 { return true } else { return false }
        })
        let firstMedia: WhisperCommentSegment? = segments.first(where: {
            if case .text = $0 { return false } else { return true }
        })
        VStack(alignment: .leading, spacing: 6) {
            if case .text(let s)? = firstText, !s.isEmpty {
                textLine(s, isFirst: true)
                    .lineLimit(3)
            }
            // Render the first attached GIF/sticker/image/voice inline as a
            // small preview so comment cards never show "GIF" as a label or
            // raw URLs.
            if let media = firstMedia {
                previewMedia(media)
            }
        }
    }

    @ViewBuilder
    private func previewMedia(_ seg: WhisperCommentSegment) -> some View {
        switch seg {
        case .gif(let url), .sticker(let url):
            WhisperAnimatedGIFView(url: url, contentMode: .fit)
                .frame(maxWidth: 140, maxHeight: 140)
                .frame(minHeight: 90, alignment: .leading)
                .clipShape(.rect(cornerRadius: 12))
        case .image(let url):
            WhisperCachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    Color(.secondarySystemBackground)
                }
            }
            .frame(width: 140, height: 140)
            .clipShape(.rect(cornerRadius: 12))
        case .voice(let url, let duration):
            voiceChip(url: url, duration: duration)
        case .imagining(let prompt):
            EmberImagineLoadingCard(aspectRatio: 1, subtitle: prompt)
                .frame(maxWidth: 140, maxHeight: 140)
        case .text:
            EmptyView()
        }
    }

    private var mediaGlyph: (icon: String, label: String)? {
        for seg in segments {
            switch seg {
            case .gif: return ("photo.on.rectangle.angled", "GIF")
            case .sticker: return ("face.smiling", "Sticker")
            case .image: return ("photo", "Photo")
            case .voice: return ("waveform", "Voice memo")
            case .imagining: return ("sparkles", "Imagining")
            case .text: continue
            }
        }
        return nil
    }

    @ViewBuilder
    private func segmentView(_ seg: WhisperCommentSegment, isFirst: Bool) -> some View {
        switch seg {
        case .text(let s):
            textLine(s, isFirst: isFirst)
        case .gif(let url), .sticker(let url):
            WhisperAnimatedGIFView(url: url, contentMode: .fit)
                .frame(maxWidth: 220, maxHeight: 220)
                .frame(minHeight: 120, alignment: .leading)
                .clipShape(.rect(cornerRadius: 14))
        case .image(let url):
            if usesThreadMediaLayout {
                Color(.secondarySystemBackground)
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay {
                        WhisperSizedAsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image): image.resizable().scaledToFit()
                            case .empty: WhisperPhotoLoader(quiet: true)
                            default: Image(systemName: "photo").foregroundStyle(.secondary)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    .clipShape(.rect(cornerRadius: 16))
            } else {
            WhisperCachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFit()
                case .empty:
                    Color(.secondarySystemBackground)
                        .frame(height: 160)
                        .overlay { ProgressView() }
                case .failure:
                    Color(.secondarySystemBackground)
                        .frame(height: 160)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(WhisperTheme.muted(colorScheme))
                        }
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: 260)
            .clipShape(.rect(cornerRadius: 14))
            }
        case .voice(let url, let duration):
            voiceChip(url: url, duration: duration)
        case .imagining(let prompt):
            EmberImagineLoadingCard(
                aspectRatio: 1.0,
                title: "Imagining…",
                subtitle: prompt
            )
            .frame(maxWidth: 260)
        }
    }

    @ViewBuilder
    private func textLine(_ s: String, isFirst: Bool) -> some View {
        if isFirst, let user = usernamePrefix, !user.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("@\(user)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WhisperTheme.ink(colorScheme))
                WhisperMentionText(text: s, font: .subheadline, lineLimit: preview ? 3 : nil, onOpenPost: onOpenReply)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            WhisperMentionText(text: s, font: .subheadline, lineLimit: preview ? 3 : nil, onOpenPost: onOpenReply)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func voiceChip(url: URL?, duration: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.subheadline.weight(.semibold))
            Text(duration.isEmpty ? "Voice memo" : "Voice memo · \(duration)")
                .font(.caption.weight(.semibold))
            if let url {
                Spacer(minLength: 4)
                Link(destination: url) {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                }
            }
        }
        .foregroundStyle(WhisperTheme.ink(colorScheme))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(WhisperTheme.card(colorScheme), in: Capsule())
        .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 0.5) }
    }
}

/// One parsed piece of a comment body — plain text, an animated GIF /
/// sticker, an uploaded image, or a voice memo line.
enum WhisperCommentSegment: Hashable {
    case text(String)
    case gif(URL)
    case sticker(URL)
    case image(URL)
    case voice(URL?, String)
    /// Sentinel emitted by `WhisperEmberMention` while an image is being
    /// generated. Rendered as the animated `EmberImagineLoadingCard` so
    /// users see Jasper "making" the image live in the comment thread.
    case imagining(String)

    /// Splits a comment body into a sequence of segments. Lines that are
    /// just a URL are classified by extension / host; voice memo lines are
    /// detected by the "🎙️ Voice memo" prefix written by the composer.
    static func parse(_ body: String) -> [WhisperCommentSegment] {
        var out: [WhisperCommentSegment] = []
        var buffer: [String] = []

        func flushText() {
            let joined = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { out.append(.text(joined)) }
            buffer.removeAll(keepingCapacity: true)
        }

        for raw in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Jasper imagine sentinel: "[[EMBER_IMAGINING:<prompt>]]"
            if trimmed.hasPrefix("[[EMBER_IMAGINING:") && trimmed.hasSuffix("]]") {
                flushText()
                let inner = String(trimmed
                    .dropFirst("[[EMBER_IMAGINING:".count)
                    .dropLast(2))
                out.append(.imagining(inner))
                continue
            }

            // Voice memo line: "🎙️ Voice memo (0:12) https://..."
            if trimmed.hasPrefix("🎙️") || trimmed.hasPrefix("🎙") {
                flushText()
                let url = firstURL(in: trimmed)
                let duration = extractParens(trimmed) ?? ""
                out.append(.voice(url, duration))
                continue
            }

            // Pure-URL line → media.
            if let url = soleURL(in: trimmed) {
                flushText()
                let host = url.host?.lowercased() ?? ""
                let path = url.path.lowercased()
                let isGiphy = host.contains("giphy.com") || host.contains("giphy.media")
                let isGif = path.hasSuffix(".gif") || isGiphy
                let isSticker = isGiphy && (path.contains("/stickers/") || path.contains("sticker"))
                let isImage = path.hasSuffix(".jpg") || path.hasSuffix(".jpeg")
                    || path.hasSuffix(".png") || path.hasSuffix(".webp") || path.hasSuffix(".heic")

                if isSticker {
                    out.append(.sticker(url))
                } else if isGif {
                    out.append(.gif(url))
                } else if isImage {
                    out.append(.image(url))
                } else {
                    buffer.append(line)
                }
                continue
            }

            buffer.append(line)
        }
        flushText()
        return out
    }

    private static func soleURL(in s: String) -> URL? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard !trimmed.contains(" "),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }

    private static func firstURL(in s: String) -> URL? {
        for token in s.split(separator: " ") {
            if let u = URL(string: String(token)),
               let scheme = u.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                return u
            }
        }
        return nil
    }

    private static func extractParens(_ s: String) -> String? {
        guard let open = s.firstIndex(of: "("),
              let close = s.firstIndex(of: ")"),
              open < close
        else { return nil }
        return String(s[s.index(after: open)..<close])
    }
}
