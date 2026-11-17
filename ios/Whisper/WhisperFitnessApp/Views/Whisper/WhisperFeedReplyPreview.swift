import SwiftUI

/// Fixed-height reply slot: hydration changes pixels, not the surrounding feed layout.
struct WhisperFeedReplyPreview: View {
    let comment: WhisperCommentRow?
    let replyCount: Int
    let threadIndex: Int?
    let threadCount: Int
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .subheadline) private var slotHeight: CGFloat = 72

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Group {
                if let comment {
                    WhisperAvatar(username: comment.username, size: 28, ring: false)
                } else {
                    Circle().fill(WhisperTheme.hairline(scheme)).frame(width: 28, height: 28)
                }
            }
            .frame(width: 44, height: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment?.username ?? "Replies")
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                    if let threadIndex {
                        WhisperThreadPositionPill(index: threadIndex, total: threadCount + 1)
                    }
                    Spacer(minLength: 0)
                    if let comment {
                        Text(WhisperPost.relativeTime(from: comment.created_at))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Text(summary)
                    .font(.subheadline).foregroundStyle(WhisperTheme.muted(scheme))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(WhisperTheme.ink(scheme))
        .padding(.top, 10)
        .frame(height: slotHeight, alignment: .top)
        .clipped()
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        guard let comment else { return "View \(replyCount) \(replyCount == 1 ? "reply" : "replies")" }
        return Self.summaryText(comment.body, stripThreadMarker: threadIndex != nil)
    }

    static func summaryText(_ body: String, stripThreadMarker: Bool = false) -> String {
        let segments = WhisperCommentSegment.parse(body)
        for segment in segments {
            if case .text(let text) = segment, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return stripThreadMarker ? WhisperCommentBodyView.stripLeadingMarker(text) : text
            }
        }
        guard let first = segments.first else { return "View reply" }
        switch first {
        case .gif: return "GIF · View reply"
        case .sticker: return "Sticker · View reply"
        case .image: return "Photo · View reply"
        case .voice: return "Voice message · View reply"
        case .imagining: return "Image · View reply"
        case .text: return "View reply"
        }
    }
}
