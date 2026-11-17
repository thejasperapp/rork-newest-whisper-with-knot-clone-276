import SwiftUI

/// Messaging templates remain available after the work hub is removed.
struct WhisperMessagingToolsListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRole: WhisperMessagingRole?

    var body: some View {
        NavigationStack {
            List(WhisperMessagingRole.allCases) { role in
                Button { selectedRole = role } label: {
                    Label(role.title, systemImage: "text.bubble")
                        .frame(minHeight: 44)
                }
            }
            .navigationTitle("Quick replies")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .fullScreenCover(item: $selectedRole) { role in WhisperRoleMessagingToolsView(role: role) }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in
            selectedRole = nil; dismiss()
        }
    }
}
