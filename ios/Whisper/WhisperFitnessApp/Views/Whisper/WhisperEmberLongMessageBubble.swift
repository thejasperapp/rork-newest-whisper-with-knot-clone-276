import SwiftUI

/// Collapsed text bubble used for long Jasper replies in DM threads.
///
/// Jasper occasionally returns a multi-paragraph answer that, rendered as a
/// normal text bubble, dominates the entire screen and makes the chat
/// unusable. This bubble caps the inline preview to a few lines and exposes
/// a "Tell me more" pill that opens a scrollable sheet with the full reply.
struct WhisperEmberLongMessageBubble: View {
    @Environment(\.colorScheme) private var colorScheme

    let messageBody: String
    let isFirstInRun: Bool
    let isLastInRun: Bool

    /// Anything longer than this many characters is considered "long" and
    /// gets the collapsed treatment.
    static let collapseThreshold: Int = 280

    @State private var expanded: Bool = false

    private var preview: String {
        let firstParagraph = messageBody
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? messageBody
        if firstParagraph.count <= 220 { return firstParagraph }
        let idx = firstParagraph.index(firstParagraph.startIndex, offsetBy: 220)
        return String(firstParagraph[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WhisperMentionText(text: preview, font: .subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(4)
            Button {
                Haptics.tap()
                expanded = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "text.alignleft")
                        .font(.caption2.weight(.bold))
                    Text("Tell me more")
                        .font(.caption.weight(.bold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(WhisperTheme.surface(colorScheme).opacity(0.9), in: Capsule())
                .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .frame(maxWidth: 280, alignment: .leading)
        .background(
            WhisperTheme.card(colorScheme),
            in: bubbleShape
        )
        .sheet(isPresented: $expanded) {
            WhisperEmberLongMessageSheet(text: messageBody)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
                .whisperSheetBorder()
        }
    }

    private var bubbleShape: some Shape {
        let big: CGFloat = 18
        let small: CGFloat = 6
        return UnevenRoundedRectangle(
            topLeadingRadius: isFirstInRun ? big : small,
            bottomLeadingRadius: isLastInRun ? big : small,
            bottomTrailingRadius: big,
            topTrailingRadius: big,
            style: .continuous
        )
    }
}

private struct WhisperEmberLongMessageSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let text: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        WhisperEmberBadge(size: 24)
                        WhisperKnotWordmark()
                        Spacer()
                    }
                    WhisperMentionText(text: text, font: .body)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(16)
            }
            .background(WhisperTheme.surface(colorScheme))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = text
                        Haptics.success()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }
}
