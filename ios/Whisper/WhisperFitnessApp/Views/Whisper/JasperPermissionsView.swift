import SwiftUI

/// Permission selection precedes token creation; sensitive reads and all writes start off.
struct JasperPermissionsView: View {
    let onAllow: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = ["read:profile", "read:workouts", "read:nutrition"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Choose only what you need. Jasper may grant fewer permissions; Whisper reads back what was actually allowed.")
                    Text("Private Files and original health reports are not available through Connect. Read access is never permission to publish your records.")
                        .foregroundStyle(.secondary)
                }
                Section("Permissions") {
                    ForEach(JasperPermissionChoice.options) { option in
                        Toggle(option.title, isOn: Binding(
                            get: { selected.contains(option.id) },
                            set: { if $0 { selected.insert(option.id) } else { selected.remove(option.id) } }
                        ))
                    }
                }
                Section {
                    Button("Allow selected permissions") {
                        let scopes = selected.sorted()
                        dismiss()
                        onAllow(scopes)
                    }
                    .disabled(selected.isEmpty)
                    .frame(minHeight: 44)
                } footer: {
                    Text("You can revoke Whisper in Jasper → Settings → Jasper Connect. Existing records are not deleted when you disconnect.")
                }
            }
            .navigationTitle("Share with Whisper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
