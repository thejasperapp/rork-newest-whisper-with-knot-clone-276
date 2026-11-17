import SwiftUI

struct JasperMeetingPreferencesView: View {
    @Bindable var model: JasperMeetingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var focus: String = ""
    @State private var instructions: String = ""
    @State private var confirmErase: Bool = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Teach Jasper what matters to you.").font(.title2.weight(.semibold))
                    Text("Your preferences shape future scans and answers. They never change what was said, and they are private to your account.").font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Highlight priorities") {
                    TextField("Client numbers, decisions, deadlines…", text: $focus, axis: .vertical).lineLimit(2...5)
                    Text("Separate topics with commas. Up to 12 topics, 80 characters each.").font(.caption).foregroundStyle(.secondary)
                }
                Section("How you like your notes") {
                    TextField("For example: lead with metrics and put unanswered questions last.", text: $instructions, axis: .vertical).lineLimit(4...8)
                    Text("\(instructions.utf16.count)/600").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Text("These are editable preferences, not model training. Review and change them anytime; Jasper won’t secretly learn from private conversations.").font(.caption).foregroundStyle(.secondary)
                    Button("Delete private Jasper answers", role: .destructive) { confirmErase = true }
                    Button("Reset preferences") { focus = "Decisions, Client numbers, Next steps"; instructions = "" }
                    if let error = model.errorText { Text(error).foregroundStyle(.red) }
                }
            }.navigationTitle("Personalize Jasper").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { let topics = focus.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }; if await model.change(["action": "preferences", "focus": topics, "instructions": instructions]) { dismiss() } } }.disabled(model.isSaving || model.library == nil || instructions.utf16.count > 600) }
                }
                .confirmationDialog("Delete private Jasper answers?", isPresented: $confirmErase) { Button("Delete answers and source snapshots", role: .destructive) { Task { if await model.eraseAnswers() { dismiss() } } } } message: { Text("Original meetings, transcripts, recordings and earlier writing will not be deleted.") }
                .task { if model.library == nil { await model.load() }; focus = model.library?.preferences.focus.joined(separator: ", ") ?? ""; instructions = model.library?.preferences.instructions ?? "" }
        }
    }
}
