import SwiftUI

struct WorkspaceWorkEditor: View {
    @Bindable var draft: WorkspaceWorkDraft
    let model: WorkspaceWorkViewModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(draft.audience).font(.subheadline).foregroundStyle(.secondary) }
                Section {
                    ForEach(draft.fields) { field in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(field.label).font(.caption.weight(.semibold))
                            if !field.options.isEmpty {
                                Picker(field.label, selection: binding(field.id)) {
                                    Text("Choose a person").tag("")
                                    ForEach(field.options) { person in Text(person.username).tag(person.id) }
                                }.labelsHidden()
                            } else if field.multiline {
                                TextEditor(text: binding(field.id)).frame(minHeight: 120).accessibilityLabel(field.label)
                            } else {
                                TextField(field.label, text: binding(field.id)).textInputAutocapitalization(field.id == "username" || field.id == "url" ? .never : .sentences).autocorrectionDisabled(field.id == "username" || field.id == "url").accessibilityLabel(field.label)
                            }
                            if (draft.values[field.id] ?? "").utf16.count > field.maximum { Text("Use at most \(field.maximum) characters.").font(.caption).foregroundStyle(.red) }
                        }
                    }
                }.disabled(draft.isSaving)
                Section {
                    Toggle("I reviewed this content and who can see it", isOn: $draft.approved).disabled(draft.isSaving)
                    if let error = draft.errorText { Text(error).font(.caption).foregroundStyle(.red) }
                    Button(draft.isSaving ? "Confirming save…" : draft.title) { Task { await model.save(draft) } }.disabled(!draft.canSave).frame(minHeight: 44)
                }
            }
            .navigationTitle(draft.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(draft.isSaving) } }
            .interactiveDismissDisabled(draft.isSaving)
        }
    }
    private func binding(_ key: String) -> Binding<String> { Binding(get: { draft.values[key] ?? "" }, set: { draft.values[key] = $0; draft.approved = false }) }
}
