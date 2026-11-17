import SwiftUI

struct WhisperNotebookFollowupSheet: View {
    @Binding var title: String
    @Binding var owner: String
    @Binding var when: String
    let onTrack: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Review the suggestion") {
                    TextField("Follow-up", text: $title, axis: .vertical).lineLimit(2...5)
                    TextField("Owner (optional)", text: $owner)
                    TextField("Due date or timing (optional)", text: $when)
                }
                Section {
                    Text("Tracking creates a checklist item in this private note only. It does not notify anyone, schedule an event, or create a task in a project.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Review follow-up").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Track") { onTrack() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 300 || owner.count > 80 || when.count > 80)
                }
            }
        }
    }
}
