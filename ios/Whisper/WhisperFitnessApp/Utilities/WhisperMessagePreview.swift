import Foundation

/// Bounded, fail-closed notification previews. Never interpolate wire payloads into alerts.
nonisolated enum WhisperMessagePreview {
    static func group(_ raw: String) -> (id: UUID, name: String, body: String)? {
        guard raw.hasPrefix("::wg-v1::"), raw.utf8.count <= 262_144 else { return nil }
        let rest = raw.dropFirst(9)
        guard let first = rest.range(of: "::"),
              let id = UUID(uuidString: String(rest[..<first.lowerBound])) else { return nil }
        let tail = rest[first.upperBound...]
        guard let second = tail.range(of: "::") else { return nil }
        return (id, text(String(tail[..<second.lowerBound])), String(tail[second.upperBound...]))
    }

    static func text(_ raw: String) -> String {
        guard raw.utf8.count <= 262_144 else { return "New message" }
        if let group = group(raw) {
            // Nested envelopes are invalid and must not recurse without a bound.
            return group.body.contains("::wg-") ? "New message" : text(group.body)
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "New message" }
        if value.hasPrefix("Document invitation:") { return "Document invitation" }
        if value.hasPrefix("Signature request:") { return "Signature request" }
        if value.contains("::wg-") || value.hasPrefix("{") || value.hasPrefix("[") { return "New message" }
        if value.contains("jasper-sticker://") || value.contains("ember-sticker://") { return "Sent a sticker" }
        if let marker = value.range(of: "::whisper-") {
            let token = value[marker.upperBound...].prefix(48)
            let labels: [(String, String)] = [
                ("artifact-", "Shared a file"),
                ("teams-", "Team invitation"),
                ("story-", "Shared a story"),
                ("callsummary-", "Call ended"), ("call-", "Incoming call"),
                ("postmeta-", "Shared a post"), ("post-", "Shared a post"),
                ("media-", "Sent an attachment"), ("photo-", "Sent a photo"),
                ("video-", "Sent a video"), ("voice-", "Sent a voice message"),
                ("audio-", "Sent audio"), ("program-", "Sent a program"),
                ("workout", "Sent a workout"), ("recipe-", "Shared a recipe"),
                ("meeting-", "Meeting invite"), ("calendar-", "Calendar event"),
                ("profile-", "Shared a profile"), ("film-", "Shared a film"),
                ("article-", "Shared an article"), ("jasper-", "Shared a Jasper answer"),
                ("ember-", "Shared a Jasper answer"), ("chart-", "Sent a chart"),
                ("map-", "Sent a map"), ("grocery-", "Sent a grocery list")
            ]
            // Drop the entire wire suffix, including malformed JSON and escaped braces.
            return labels.first { token.hasPrefix($0.0) }?.1 ?? "New message"
        }
        if value.hasPrefix("http"), value.contains("whisper-media") { return "Sent an attachment" }
        return String(value.replacingOccurrences(of: "\n", with: " ").prefix(180))
    }
}
