import SwiftUI

/// Compatibility entry for grid routes; the master feed card and discussion
/// host now own every post style, including highlighted notification replies.
struct WhisperGridPostDetailView: View {
    let post: WhisperPost
    var autoFocusReply: Bool = false
    var highlightCommentID: String? = nil

    var body: some View {
        WhisperPostDetailView(post: post, highlightCommentID: highlightCommentID, autoFocusReply: autoFocusReply)
    }
}
