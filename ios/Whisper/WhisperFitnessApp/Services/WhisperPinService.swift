import Foundation
import Observation

/// Client-side pinning + per-comment hide store. The deployed
/// `whisper_post_comments` schema doesn't carry an `is_pinned` column, so
/// to ship the Threads-style "pin a reply" + "hide a reply" menu without a
/// migration we persist these decisions locally per signed-in user. Each
/// post can have a single pinned comment id and any number of hidden
/// comment ids; both are scoped to the *post author* (only they can pin
/// or hide on their own post).
@MainActor
@Observable
final class WhisperPinService {
    static let shared = WhisperPinService()

    /// postID(lower) -> pinned commentID
    private(set) var pinnedByPost: [String: String] = [:]
    /// commentID set that the local user has chosen to hide
    private(set) var hiddenCommentIDs: Set<String> = []

    private let pinnedKey = "whisper.pinned.comments.v1"
    private let hiddenKey = "whisper.hidden.comments.v1"

    init() {
        load()
    }

    func pinnedCommentID(for postID: String) -> String? {
        pinnedByPost[postID.lowercased()]
    }

    func isPinned(commentID: String, postID: String) -> Bool {
        pinnedByPost[postID.lowercased()] == commentID
    }

    func togglePin(commentID: String, postID: String) {
        let key = postID.lowercased()
        if pinnedByPost[key] == commentID {
            pinnedByPost.removeValue(forKey: key)
        } else {
            pinnedByPost[key] = commentID
        }
        persist()
    }

    func isHidden(commentID: String) -> Bool {
        hiddenCommentIDs.contains(commentID)
    }

    func hide(commentID: String) {
        hiddenCommentIDs.insert(commentID)
        persist()
    }

    func unhide(commentID: String) {
        hiddenCommentIDs.remove(commentID)
        persist()
    }

    private func load() {
        let d = UserDefaults.standard
        if let dict = d.dictionary(forKey: pinnedKey) as? [String: String] {
            pinnedByPost = dict
        }
        if let arr = d.array(forKey: hiddenKey) as? [String] {
            hiddenCommentIDs = Set(arr)
        }
    }

    private func persist() {
        let d = UserDefaults.standard
        d.set(pinnedByPost, forKey: pinnedKey)
        d.set(Array(hiddenCommentIDs), forKey: hiddenKey)
    }
}
