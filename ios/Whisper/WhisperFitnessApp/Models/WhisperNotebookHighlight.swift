import Foundation

/// UTF-16 offsets interoperate with web selection. Changed evidence is retained, never guessed.
nonisolated struct WhisperNotebookHighlight: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let kind: String
    var start: Int
    var end: Int
    let text: String
    var revision: Int
    let origin: String
    var stale: Bool

    var isValid: Bool { UUID(uuidString: id) != nil && ["notes", "transcript"].contains(kind) && ["manual", "jasper"].contains(origin) && start >= 0 && end <= 60000 && end > start && end - start == text.utf16.count && text.utf16.count <= 1200 && revision >= 0 }

    func matches(_ body: String) -> Bool {
        let source = body as NSString
        return isValid && !stale && end <= source.length && source.substring(with: NSRange(location: start, length: end - start)) == text
    }

    static func rebase(_ items: [Self], kind: String, before: String, after: String, revision: Int) -> [Self] {
        guard before != after else { return items }
        let old = Array(before.utf16), new = Array(after.utf16)
        var prefix = 0, suffix = 0
        while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
        while suffix < min(old.count, new.count) - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        return items.map { item in
            guard item.kind == kind, !item.stale else { return item }
            var next = item
            if item.end <= prefix { next.revision = revision }
            else if item.start >= old.count - suffix { next.start += new.count - old.count; next.end += new.count - old.count; next.revision = revision }
            else { next.stale = true }
            return next
        }
    }
}
