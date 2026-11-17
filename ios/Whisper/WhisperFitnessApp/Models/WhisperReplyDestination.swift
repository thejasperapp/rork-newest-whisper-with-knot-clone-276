import Foundation

/// A reply is a reading destination within its original post, never a copied post.
nonisolated struct WhisperReplyDestination: Hashable {
    let commentID: String?
}
