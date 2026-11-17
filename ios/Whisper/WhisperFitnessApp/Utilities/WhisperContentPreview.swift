import Foundation

/// Display-only previews; structured content never establishes access or authority.
nonisolated enum WhisperContentPreview {
    static func text(_ input: String?, fallback: String = "Shared content", limit: Int = 160) -> String {
        guard let input, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        let raw = String(input.prefix(65_536))
        guard let regex = try? NSRegularExpression(pattern: "::whisper-([a-z0-9-]+)-v[0-9]+::", options: .caseInsensitive) else { return fallback }
        let labels: [String: String] = ["workout": "Workout", "sharedpost": "Shared post", "film": "Film", "article": "Article", "recipe": "Recipe", "chart": "Chart", "checkin": "Check-in", "macros": "Nutrition", "healthshare": "Health update", "profileshare": "Shared profile", "story": "Story", "storytag": "Story mention", "teams": "Team invitation", "calendar": "Meet invitation", "map": "Shared place", "grocery": "Grocery list"]
        var cursor = raw.startIndex
        var output = ""
        var label = fallback
        for match in regex.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)) {
            guard let range = Range(match.range, in: raw), range.lowerBound >= cursor else { continue }
            output += raw[cursor..<range.lowerBound]
            if let kind = Range(match.range(at: 1), in: raw) { label = labels[String(raw[kind]).lowercased()] ?? label }
            var end = range.upperBound
            while end < raw.endIndex && (raw[end] == " " || raw[end] == "\t") { end = raw.index(after: end) }
            if end < raw.endIndex && (raw[end] == "{" || raw[end] == "[") {
                var stack: [Character] = []
                var quoted = false
                var escaped = false
                var complete = false
                while end < raw.endIndex {
                    let char = raw[end]
                    end = raw.index(after: end)
                    if quoted {
                        if escaped { escaped = false }
                        else if char == "\\" { escaped = true }
                        else if char == "\"" { quoted = false }
                        continue
                    }
                    if char == "\"" { quoted = true }
                    else if char == "{" || char == "[" { stack.append(char) }
                    else if char == "}" || char == "]" {
                        let open = stack.popLast()
                        if (char == "}" && open != "{") || (char == "]" && open != "[") { break }
                        if stack.isEmpty { complete = true; break }
                    }
                }
                if !complete { end = raw.endIndex }
            } else { end = raw[end...].firstIndex(of: "\n") ?? raw.endIndex }
            cursor = end
            output += " "
        }
        output += raw[cursor...]
        output = output.replacingOccurrences(of: "\\b(?:jasper|ember|whisper)-sticker://\\S+", with: "Sticker", options: .regularExpression)
        if let range = output.range(of: "::whisper-") { output = String(output[..<range.lowerBound]) }
        output = output.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String((output.isEmpty ? label : output).prefix(limit))
    }
}
