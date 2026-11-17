import Foundation

nonisolated enum WhisperMentionToken {
    static func trailing(in text: String) -> String? {
        guard let at = text.lastIndex(of: "@") else { return nil }
        if at > text.startIndex {
            let previous = text[text.index(before: at)]
            if previous.isLetter || previous.isNumber || previous == "_" || previous == "." { return nil }
        }
        let token = text[text.index(after: at)...]
        guard token.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }) else { return nil }
        return String(token)
    }

    static func replacingTrailing(in text: String, username: String) -> String {
        guard trailing(in: text) != nil, let at = text.lastIndex(of: "@") else { return text }
        return String(text[..<at]) + "@" + username + " "
    }
}
