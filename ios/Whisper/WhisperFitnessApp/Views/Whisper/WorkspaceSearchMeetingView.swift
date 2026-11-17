import SwiftUI
import Supabase

struct WorkspaceSearchMeetingView: View {
    let meetingID: String
    let ask: Bool
    @State private var meeting: WhisperMeetingRow?
    @State private var loading: Bool = true
    @Environment(\.dismiss) private var dismiss
    private let owner: String = AccountStorage.currentUserID.lowercased()
    private let generation: UUID = AccountStorage.generation
    var body: some View {
        Group {
            if let meeting {
                if ask { WorkspaceMeetingJasperView(meeting: meeting) }
                else { WhisperMeetingNotesView(meeting: meeting) }
            } else {
                NavigationStack {
                    VStack(spacing: 16) {
                        if loading { ProgressView("Checking meeting access…") }
                        else { ContentUnavailableView("Meeting unavailable", systemImage: "lock", description: Text("Access may have changed, or you may be offline.")); Button("Retry access") { Task { await load() } } }
                    }.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                }
            }
        }.task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WhisperMeetingAccountWillChange"))) { _ in meeting = nil; dismiss() }
    }
    private func load() async {
        loading = true; meeting = nil; defer { loading = false }
        let client = SupabaseService.shared.client
        do {
            struct Membership: Decodable { let meeting_id: String }
            async let rows: [WhisperMeetingRow] = client.from("whisper_meetings").select().eq("id", value: meetingID).limit(1).execute().value
            async let links: [Membership] = client.from("whisper_meeting_participants").select("meeting_id").eq("meeting_id", value: meetingID).eq("user_id", value: owner).limit(1).execute().value
            let (found, memberships) = try await (rows, links)
            guard !Task.isCancelled, generation == AccountStorage.generation, client.auth.currentUser?.id.uuidString.lowercased() == owner, let row = found.first, row.host_id.lowercased() == owner || !memberships.isEmpty else { return }
            meeting = row
        } catch { meeting = nil }
    }
}
