import SwiftUI

/// A real root comment on Waves' recessed layer, separate from the wave's
/// own heart. The comments browser and this preview observe the same cache.
struct WhisperWaveCommentUnderlayer: View {
    let post: WhisperPost
    let isActive: Bool
    let openComments: () -> Void

    @State private var backend = WhisperBackendService.shared
    @State private var generation = AccountStorage.generation
    @State private var accountChanging = false
    @State private var loading = false
    @State private var liking = false
    @State private var likeError = false
    @State private var mounted = false

    private var postID: String { post.id.uuidString.lowercased() }
    private var accountIsCurrent: Bool {
        !accountChanging && generation == AccountStorage.generation
    }

    private var topComment: WhisperCommentRow? {
        guard accountIsCurrent else { return nil }
        return (backend.commentsByPostID[postID] ?? [])
            .filter { $0.parent_comment_id == nil && !$0.id.hasPrefix("local-") }
            .min {
                let lhs = $0.likes_count ?? 0
                let rhs = $1.likes_count ?? 0
                if lhs != rhs { return lhs > rhs }
                if $0.created_at != $1.created_at { return ($0.created_at ?? "") < ($1.created_at ?? "") }
                return $0.id < $1.id
            }
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                guard accountIsCurrent, isActive else { return }
                openComments()
            } label: {
                HStack(spacing: 10) {
                    if let comment = topComment {
                        WhisperAvatar(username: comment.username, size: 32, ring: false)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(comment.username.isEmpty ? "Comment" : comment.username)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(1)
                            Text(comment.body)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                    } else {
                        WhisperRoundedGlyph(kind: .comment, size: 22)
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(loading ? "Loading comments…" : (post.comments > 0 ? "View comments" : "Join the conversation"))
                                .font(.subheadline.weight(.semibold))
                            Text("Tap to open comments")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }
                    Spacer(minLength: 4)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isActive || !accountIsCurrent)
            .accessibilityHint("Expands comments in this underlayer. You can also swipe up.")

            if let comment = topComment {
                let liked = backend.myLikedCommentIDs.contains(comment.id)
                Button {
                    toggleLike(comment)
                } label: {
                    WhisperRoundedGlyph(kind: .heart, size: 22, selected: liked)
                        .foregroundStyle(liked ? Color.pink : Color.white.opacity(0.85))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(liking || !isActive || !accountIsCurrent)
                .accessibilityLabel(liked ? "Unlike comment" : "Like comment")
                .accessibilityValue(liked ? "Liked" : "Not liked")
            }
        }
        .foregroundStyle(.white)
        .onAppear { mounted = true }
        .onDisappear { mounted = false }
        .task(id: isActive) {
            guard isActive, accountIsCurrent else { return }
            loading = true
            _ = await backend.fetchComments(postID: postID, maxAge: 30)
            guard accountIsCurrent, !Task.isCancelled else { return }
            loading = false
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            accountChanging = true
            likeError = false
        }
        .alert("Comment like not saved", isPresented: $likeError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your previous like state was restored. Please try again.")
        }
    }

    private func toggleLike(_ comment: WhisperCommentRow) {
        guard isActive, accountIsCurrent, !liking, topComment?.id == comment.id else { return }
        let expected = !backend.myLikedCommentIDs.contains(comment.id)
        let epoch = generation
        liking = true
        Haptics.tap()
        Task {
            let result = await backend.toggleCommentLike(commentID: comment.id, postID: postID)
            guard epoch == AccountStorage.generation, accountIsCurrent else { return }
            liking = false
            if mounted && result != expected { likeError = true }
        }
    }
}
