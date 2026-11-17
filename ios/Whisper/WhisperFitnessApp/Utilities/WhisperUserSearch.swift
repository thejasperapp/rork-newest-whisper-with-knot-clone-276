import Foundation

/// Names are search labels only; account IDs remain the identity for every action.
nonisolated enum WhisperUserSearch {
    static func matches(_ query: String, username: String, displayName: String?) -> Bool {
        let terms = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let labels = username + " " + (displayName ?? "")
        return terms.allSatisfy { labels.localizedStandardContains($0) }
    }
}
