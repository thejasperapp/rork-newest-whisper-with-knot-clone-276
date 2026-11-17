import SwiftUI

struct WhisperStoryLabelEditor: View {
    let isMention: Bool
    var existing: WhisperStorySticker? = nil
    let onCancel: () -> Void
    let onDone: (WhisperStorySticker) -> Void
    @State private var text: String = ""
    @State private var mentionBuffer: String = "@"
    @FocusState private var focused: Bool
    private var cleaned: String { text.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "@#")) }

    var body: some View {
        VStack(spacing: 0) {
            WhisperStoryToolHeader(inline: true, canConfirm: !cleaned.isEmpty, onConfirm: {
                var layer = existing ?? WhisperStorySticker(kind: isMention ? .mention : .hashtag)
                layer.label = cleaned
                onDone(layer)
            }, onCancel: onCancel)
            GeometryReader { geometry in
                ScrollView {
                    HStack(spacing: 2) {
                        Text(isMention ? "@" : "#").foregroundStyle(isMention ? .orange : .purple)
                        TextField(isMention ? "mention" : "hashtag", text: $text)
                            .focused($focused).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .foregroundStyle(.black).tint(.black)
                    }.font(.title3.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: max(1, min(280, geometry.size.width - 40)))
                        .background(.white, in: .rect(cornerRadius: 12))
                        .frame(maxWidth: .infinity).padding(.top, max(20, geometry.size.height * 0.35))
                }
            }
            if isMention { WhisperMentionSuggestionsBar(text: $mentionBuffer).frame(maxHeight: 150).padding(.horizontal, 16) }
        }.buttonStyle(.plain)
            .task { text = existing?.label ?? ""; focused = true }
            .onChange(of: text) { _, value in let target = "@\(value)"; if mentionBuffer != target { mentionBuffer = target } }
            .onChange(of: mentionBuffer) { _, value in
                let next = value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
                if text != next { text = next }
            }
    }
}
