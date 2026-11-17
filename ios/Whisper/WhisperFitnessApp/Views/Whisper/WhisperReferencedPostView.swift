import SwiftUI

/// Resolve shared references before rendering: snapshots are previews, not the original post.
struct WhisperReferencedPostView: View {
    let postID: String
    var highlightCommentID: String? = nil
    var focusedCommentID: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var post: WhisperPost? = nil
    @State private var loading: Bool = true
    @State private var attempt: Int = 0

    var body: some View {
        Group {
            if let post {
                WhisperPostDetailView(post: post, highlightCommentID: highlightCommentID, focusedCommentID: focusedCommentID)
            } else {
                NavigationStack {
                    Group {
                        if loading {
                            ProgressView("Opening post…").frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ContentUnavailableView {
                                Label("Couldn't open this post", systemImage: "photo")
                            } description: {
                                Text("It may be unavailable, private, or your connection may be interrupted.")
                            } actions: {
                                Button("Try again") { attempt += 1 }.buttonStyle(.bordered)
                            }
                        }
                    }
                    .navigationTitle("Post")
                    .navigationBarTitleDisplayMode(.inline)
                    .whisperNavigationBack()
                }
            }
        }
        .task(id: attempt) {
            loading = true
            let generation = AccountStorage.generation
            let backend = WhisperBackendService.shared
            let row = await backend.fetchPost(postID: postID)
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            if let row {
                post = WhisperRootView.mapRowToPost(row, fallbackUsername: backend.postAuthorProfiles[row.user_id]?.username)
            }
            loading = false
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            post = nil
            dismiss()
        }
    }
}
