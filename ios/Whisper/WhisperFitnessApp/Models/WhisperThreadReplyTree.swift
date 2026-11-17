import Foundation

/// Keeps actual reply identities while presenting descendants in a bounded-width conversation.
nonisolated enum WhisperThreadReplyTree {
    static func descendants(of parentID: String, in comments: [WhisperCommentRow]) -> [WhisperCommentRow] {
        let children = Dictionary(grouping: comments, by: { $0.parent_comment_id ?? "" })
            .mapValues { $0.sorted { ($0.created_at ?? "", $0.id) < ($1.created_at ?? "", $1.id) } }
        var stack: [WhisperCommentRow] = Array((children[parentID] ?? []).reversed())
        var visited: Set<String> = [parentID]
        var result: [WhisperCommentRow] = []
        while let row = stack.popLast() {
            guard visited.insert(row.id).inserted else { continue }
            result.append(row)
            stack.append(contentsOf: (children[row.id] ?? []).reversed())
        }
        return result
    }

    static func ancestors(of commentID: String, in comments: [WhisperCommentRow]) -> [WhisperCommentRow] {
        let byID = Dictionary(comments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var current = commentID
        var visited: Set<String> = [current]
        var result: [WhisperCommentRow] = []
        while let parentID = byID[current]?.parent_comment_id, let parent = byID[parentID] {
            guard visited.insert(parentID).inserted else { break }
            result.append(parent)
            current = parentID
        }
        return result.reversed()
    }

    static func rootID(for commentID: String, in comments: [WhisperCommentRow]) -> String {
        let byID = Dictionary(comments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var current = commentID
        var visited: Set<String> = [current]
        while let parent = byID[current]?.parent_comment_id, byID[parent] != nil {
            guard visited.insert(parent).inserted else { break }
            current = parent
        }
        return current
    }
}
