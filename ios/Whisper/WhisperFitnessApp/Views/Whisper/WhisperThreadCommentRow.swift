import SwiftUI

/// A reply's text opens its reading page; the bubble starts composing to that exact reply.
struct WhisperThreadCommentRow: View {
    let comment: WhisperCommentRow
    let isChild: Bool
    let isLiked: Bool
    let replyCount: Int
    let commentsOff: Bool
    let hideCounts: Bool
    let threadPosition: (Int, Int)?
    var replyingTo: String? = nil
    var isFocused: Bool = false
    var isPostAuthor: Bool = false
    let onProfile: () -> Void
    let onAvatar: () -> Void
    let onLike: () -> Void
    let onReply: () -> Void
    let onOptions: () -> Void
    var onOpen: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if isFocused {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) { avatar; header }
                    content
                    actions
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    avatar
                    VStack(alignment: .leading, spacing: 2) {
                        header
                        if let replyingTo {
                            Text("Replying to \(replyingTo)").font(.caption)
                                .foregroundStyle(WhisperTheme.muted(scheme)).lineLimit(1)
                        }
                        content
                        actions
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .foregroundStyle(WhisperTheme.ink(scheme))
        .accessibilityAction(named: "Open reply") { onOpen?() }
    }

    private var avatar: some View {
        Button(action: onAvatar) {
            WhisperAvatar(username: comment.username, size: isFocused ? 40 : (isChild ? 28 : 36),
                          ring: WhisperStoryService.shared.hasUnseenStories(userID: comment.user_id))
                .frame(width: 44, height: 44).contentShape(.rect)
        }
        .buttonStyle(.plain).accessibilityLabel("Open \(comment.username)")
    }

    private var header: some View {
        HStack(spacing: 4) {
            Button(action: onProfile) {
                HStack(spacing: 4) {
                    Text(comment.username).font(.subheadline.weight(.semibold)).lineLimit(1)
                        .frame(minWidth: 44, alignment: .leading)
                    VerifiedBadge(badge: UserVerificationService.shared.badge(forUsername: comment.username),
                                  size: 12, username: comment.username)
                }
                .frame(minHeight: 44).contentShape(.rect)
            }
            .buttonStyle(.plain).layoutPriority(1)
            Text(WhisperPost.relativeTime(from: comment.created_at))
                .font(.caption).foregroundStyle(WhisperTheme.muted(scheme)).lineLimit(1)
            if isPostAuthor {
                Text("Author").font(.caption).foregroundStyle(WhisperTheme.muted(scheme)).lineLimit(1)
            }
            if let (index, total) = threadPosition {
                Text("\(index)/\(total)").font(.caption).foregroundStyle(WhisperTheme.muted(scheme)).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: onOptions) {
                Image(systemName: "ellipsis").font(.body)
                    .foregroundStyle(WhisperTheme.muted(scheme))
                    .frame(width: 44, height: 44).contentShape(.rect)
            }
            .buttonStyle(.plain).accessibilityLabel("Reply options")
        }
    }

    private var content: some View {
        WhisperCommentBodyView(text: comment.body, stripThreadMarker: threadPosition != nil,
                               usesThreadMediaLayout: true, onOpenReply: isFocused ? nil : onOpen)
    }

    private var actions: some View {
        HStack(spacing: 14) {
            Button(action: onLike) {
                HStack(spacing: 5) {
                    WhisperRoundedGlyph(kind: .heart, size: 22, selected: isLiked)
                        .foregroundStyle(isLiked ? WhisperTheme.likeRed : WhisperTheme.ink(scheme))
                    if !hideCounts, let count = comment.likes_count, count > 0 {
                        Text(count.formatted(.number.notation(.compactName))).font(.caption).lineLimit(1)
                    }
                }
                .frame(minWidth: 44, minHeight: 44, alignment: .leading).contentShape(.rect)
            }
            .buttonStyle(.plain).accessibilityLabel(isLiked ? "Unlike reply" : "Like reply")
            if !commentsOff {
                Button(action: onReply) {
                    HStack(spacing: 5) {
                        WhisperRoundedGlyph(kind: .comment, size: 22)
                        if !hideCounts, replyCount > 0 {
                            Text(replyCount.formatted(.number.notation(.compactName))).font(.caption)
                        }
                    }
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading).contentShape(.rect)
                }
                .buttonStyle(.plain).accessibilityLabel("Reply to \(comment.username)")
            }
            if let onShare {
                Button(action: onShare) {
                    WhisperRoundedGlyph(kind: .plane, size: 22)
                        .frame(width: 44, height: 44, alignment: .leading).contentShape(.rect)
                }
                .buttonStyle(.plain).accessibilityLabel("Share reply by \(comment.username)")
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(WhisperTheme.ink(scheme))
    }
}
