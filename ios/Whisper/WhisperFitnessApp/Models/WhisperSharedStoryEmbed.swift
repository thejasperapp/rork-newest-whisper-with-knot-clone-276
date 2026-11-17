import Foundation

/// Identity-only wire format. Media URLs and private Story contents never enter the message.
nonisolated enum WhisperSharedStoryEmbed {
    static let prefix: String = "::whisper-story-v1::"

    static func encode(storyID: String) -> String? {
        guard let id = UUID(uuidString: storyID) else { return nil }
        return prefix + id.uuidString.lowercased()
    }

    static func decode(_ body: String) -> String? {
        guard body.utf8.count <= 100 else { return nil }
        let value = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let marker = value.hasPrefix("::whisper-storytag-v1::") ? "::whisper-storytag-v1::" : prefix
        guard value.hasPrefix(marker), let id = UUID(uuidString: String(value.dropFirst(marker.count))) else { return nil }
        return id.uuidString.lowercased()
    }
}
