import SwiftUI

/// Keep the real original's identity and actions above the focused reply.
struct WhisperThreadParentContext: View {
    let post: WhisperPost
    let onOpen: (Bool) -> Void

    var body: some View {
        WhisperPostCard(post: post, onOpenDiscussion: onOpen, isThreadContext: true)
    }
}
