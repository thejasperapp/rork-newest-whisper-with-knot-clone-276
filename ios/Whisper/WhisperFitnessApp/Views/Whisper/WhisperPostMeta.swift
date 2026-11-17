import Foundation

/// Rich post metadata written by the grid composer (music, location, tagged
/// people, hide-counts) — stored as a single `::whisper-postmeta-v1::{json}`
/// line at the start of the caption, mirroring web `lib/postMeta.ts` 1:1 so
/// grid posts render identically on both platforms.
nonisolated struct WhisperPostMeta: Decodable, Sendable {
    nonisolated struct Music: Decodable, Sendable {
        let id: String?
        let title: String
        let artist: String
        let artworkURL: String?
        let previewURL: String?
    }

    let music: Music?
    let location: String?
    let tagged: [String]?
    let hideCounts: Bool?
    /// Accessibility alt text for the post's media (web Share step).
    let altText: String?
    /// Instagram-style "turn off commenting" — hides every comment affordance.
    let commentsOff: Bool?
    /// A wave's COVER frame (the one the creator picked in the composer) as a
    /// public image URL — every grid/mosaic/shelf tile shows this instead of
    /// regenerating a frame from the video. Mirrors web `postMeta.ts` `cover`.
    let cover: String?
    /// Instagram's "Also share to feed" for a wave — when true the wave ALSO
    /// rides the ranked feed as a reel-in-feed card (still a wave everywhere
    /// else: the player, the profile Waves grid, Discover). Mirrors web
    /// `postMeta.ts` `feed`.
    let feed: Bool?

    static let prefix = "::whisper-postmeta-v1::"

    /// Whether a wave opted into the feed ("Also share to feed"). Cheap
    /// substring pre-check first so the feed filter never JSON-parses posts
    /// that can't possibly carry the flag.
    static func isSharedToFeed(caption: String) -> Bool {
        guard caption.hasPrefix(prefix), caption.contains("\"feed\":true") else { return false }
        return parse(from: caption)?.feed == true
    }

    /// The cover image URL for a post row, when its caption carries one.
    static func coverURL(from caption: String?) -> URL? {
        guard let caption, let cover = parse(from: caption)?.cover, !cover.isEmpty else { return nil }
        return URL(string: cover)
    }

    /// Decode the meta payload from a caption, or nil when absent/corrupt.
    static func parse(from caption: String) -> WhisperPostMeta? {
        guard caption.hasPrefix(prefix) else { return nil }
        let body = String(caption.dropFirst(prefix.count))
        let line = body
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? ""
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WhisperPostMeta.self, from: data)
    }

    /// The visible caption text with the meta line removed.
    static func strip(from caption: String) -> String {
        guard caption.hasPrefix(prefix) else { return caption }
        let body = String(caption.dropFirst(prefix.count))
        if let nl = body.firstIndex(of: "\n") {
            return String(body[body.index(after: nl)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }
}
