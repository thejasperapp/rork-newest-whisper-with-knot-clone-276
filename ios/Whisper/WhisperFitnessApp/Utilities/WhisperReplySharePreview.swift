import Foundation

/// Human-readable reply previews omit attachment wire URLs and generation sentinels.
enum WhisperReplySharePreview {
    static func excerpt(_ body: String) -> String {
        let segments = WhisperCommentSegment.parse(body)
        let text = segments.compactMap { segment -> String? in
            if case .text(let text) = segment { return WhisperCommentBodyView.stripLeadingMarker(text) }
            return nil
        }.joined(separator: "\n")
        if !text.isEmpty { return String(text.prefix(500)) }
        guard let first = segments.first else { return "Reply" }
        switch first {
        case .image: return "Photo"
        case .gif: return "GIF"
        case .sticker: return "Sticker"
        case .voice: return "Voice message"
        case .imagining: return "Image reply"
        case .text: return "Reply"
        }
    }
}
