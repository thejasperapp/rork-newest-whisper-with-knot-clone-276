import SwiftUI

/// Shares the single-pill composer with messages without changing reply ownership or drafts.
struct WhisperThreadReplyBar: View {
    @Binding var draft: String
    let username: String
    let placeholder: String
    let attachments: WhisperComposerAttachments
    let isSending: Bool
    let canSend: Bool
    let characterLimit: Int
    var focused: FocusState<Bool>.Binding
    let onPicker: (WhisperReplyComposerPicker) -> Void
    let onExpand: () -> Void
    let onSend: () -> Void
    var replyTo: String? = nil
    var onClearTarget: () -> Void = {}
    @Environment(\.colorScheme) private var scheme
    @State private var showAttachments: Bool = false

    private var items: [WhisperChatAttachItem] {
        [
            WhisperChatAttachItem(id: "photo", title: "Photos", systemImage: "photo") { onPicker(.photos) },
            WhisperChatAttachItem(id: "sticker", title: "Stickers", systemImage: "face.smiling") { onPicker(.sticker) },
            WhisperChatAttachItem(id: "gif", title: "GIF", systemImage: "rectangle.stack") { onPicker(.gif) },
            WhisperChatAttachItem(id: "expand", title: "Expand reply", systemImage: "arrow.up.right.and.arrow.down.left", action: onExpand)
        ]
    }

    var body: some View {
        VStack(spacing: 6) {
            if let replyTo {
                HStack(spacing: 4) {
                    Text("Replying to \(replyTo)").font(.caption).lineLimit(1)
                    Spacer(minLength: 0)
                    Button(action: onClearTarget) { Image(systemName: "xmark").font(.caption.weight(.semibold)).frame(width: 44, height: 44) }
                        .buttonStyle(.plain).accessibilityLabel("Reply to the post instead")
                }.foregroundStyle(WhisperTheme.muted(scheme)).padding(.leading, 12)
            }
            if focused.wrappedValue { WhisperMentionSuggestionsBar(text: $draft).fixedSize(horizontal: false, vertical: true) }
            if !attachments.isEmpty { WhisperComposerAttachmentChips(bag: attachments).frame(height: 106) }
            HStack(alignment: .bottom, spacing: 4) {
                WhisperChatAttachmentButton(isPresented: $showAttachments, items: items) { focused.wrappedValue = false }
                WhisperChatField(focused: focused.wrappedValue) {
                    HStack(alignment: .bottom, spacing: 0) {
                        TextField(placeholder, text: $draft, axis: .vertical)
                            .font(.body).lineLimit(1...5).focused(focused)
                            .padding(.leading, 14).padding(.vertical, 12).accessibilityLabel("Write a reply")
                        Group {
                            if !draft.isEmpty || !attachments.isEmpty || isSending {
                                WhisperChatSendButton(enabled: canSend && !isSending, sending: isSending, action: onSend).accessibilityLabel("Post reply")
                            } else {
                                Button(action: onExpand) { Image(systemName: "arrow.up.right.and.arrow.down.left").font(.system(size: 17)).frame(width: 44, height: 44) }
                                    .buttonStyle(.plain).accessibilityLabel("Expand reply")
                            }
                        }.frame(width: 44, height: 44).padding(.trailing, 2)
                    }
                }
            }.foregroundStyle(WhisperTheme.ink(scheme)).tint(WhisperTheme.ink(scheme))
            if draft.count > characterLimit {
                Text("\(draft.count - characterLimit) characters over the limit").font(.caption).foregroundStyle(.red)
            }
        }.disabled(isSending).padding(.horizontal, 12).padding(.vertical, 4)
    }
}
