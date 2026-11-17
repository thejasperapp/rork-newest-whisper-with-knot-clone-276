import SwiftUI

/// Edits a question or poll in place without changing its position, transform or identity.
struct WhisperStoryPromptEditor: View {
    let sticker: WhisperStorySticker
    let onSave: (WhisperStorySticker) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var options: [String]
    @State private var generation: UUID = AccountStorage.generation

    init(sticker: WhisperStorySticker, onSave: @escaping (WhisperStorySticker) -> Void) {
        self.sticker = sticker; self.onSave = onSave
        _text = State(initialValue: sticker.text ?? "")
        _options = State(initialValue: sticker.pollOptions ?? ["This", "That"])
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= 180 &&
        (sticker.kind != .poll || options.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 80 })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Question") {
                    TextField("What would you like to ask?", text: $text, axis: .vertical).lineLimit(2...5)
                }
                if sticker.kind == .poll {
                    Section("Choices") {
                        // The existing poll's option count stays fixed during this edit.
                        ForEach(Array(options.enumerated()), id: \.offset) { index, _ in
                            TextField("Choice \(index + 1)", text: Binding(get: { options[index] }, set: { options[index] = $0 }))
                        }
                    }
                }
            }
            .navigationTitle(sticker.kind == .poll ? "Edit poll" : "Edit question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        guard canSave, generation == AccountStorage.generation else { return }
                        var updated = sticker
                        updated.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if sticker.kind == .poll { updated.pollOptions = options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
                        onSave(updated); dismiss()
                    }.disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium, .large]).presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible).presentationCornerRadius(30)
        .environment(\.colorScheme, .dark)
    }
}
