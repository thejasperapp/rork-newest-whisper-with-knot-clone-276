import SwiftUI

/// Every caption phrase on the wave's clock — tap one to fix its words, swipe
/// to drop it. Edited words keep the phrase's original timing, spread across
/// it by their length, so the pop still lands with the speech.
struct WhisperWaveCaptionWordsSheet: View {
    @Binding var captions: WhisperWaveCaptions?
    let clips: [WhisperWaveClip]
    @Environment(\.dismiss) private var dismiss
    @State private var editingID: UUID?
    @State private var draft: String = ""
    @FocusState private var editorFocused: Bool

    private var phrases: [WhisperWaveCaptionPhrase] {
        guard let captions else { return [] }
        return WhisperWaveCaptionPhrase.phrases(captions.placed(in: clips))
    }

    var body: some View {
        NavigationStack {
            List {
                if phrases.isEmpty {
                    Text("No caption words fall inside the kept parts of your clips.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Section {
                        ForEach(phrases) { phrase in
                            row(phrase)
                        }
                    } footer: {
                        Text("Words follow their clip through trims, splits and speed changes. Edited words share the phrase's original timing.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Caption words")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        commit()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private func row(_ phrase: WhisperWaveCaptionPhrase) -> some View {
        if editingID == phrase.id {
            VStack(alignment: .leading, spacing: 8) {
                timeLabel(phrase)
                TextField("Words", text: $draft)
                    .focused($editorFocused)
                    .submitLabel(.done)
                    .onSubmit { commit() }
                    .font(.body)
                HStack {
                    Button("Cancel") {
                        editingID = nil
                        draft = ""
                    }
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("Save") { commit() }
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 4)
        } else {
            Button {
                commit()
                editingID = phrase.id
                draft = phrase.text
                editorFocused = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    timeLabel(phrase)
                    Text(phrase.text)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    Haptics.rigid()
                    captions?.remove(phrase: phrase)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
            .accessibilityHint("Edits this phrase")
        }
    }

    private func timeLabel(_ phrase: WhisperWaveCaptionPhrase) -> some View {
        Text("\(WhisperWaveClipsEditor.clock(phrase.start)) – \(WhisperWaveClipsEditor.clock(phrase.end))")
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private func commit() {
        guard let id = editingID, let phrase = phrases.first(where: { $0.id == id }) else {
            editingID = nil
            return
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if text != phrase.text {
            captions?.replace(phrase: phrase, with: text)
            Haptics.selection()
        }
        editingID = nil
        draft = ""
    }
}
