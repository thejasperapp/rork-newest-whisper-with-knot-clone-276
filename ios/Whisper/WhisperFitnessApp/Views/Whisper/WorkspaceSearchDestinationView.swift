import SwiftUI

/// Reopens the existing object surfaces; every assistant keeps its own source approval.
struct WorkspaceSearchDestinationView: View {
    let result: WorkspaceSearchResult
    let ask: Bool
    let search: WorkspaceSearchViewModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            switch result.kind {
            case "Meetings":
                WorkspaceSearchMeetingView(meetingID: result.objectID, ask: ask)
            case "Notes":
                if ask { WorkspaceNoteJasperView(noteID: result.objectID) }
                else { WhisperNotebookView(noteID: result.objectID) }
            case "Recordings":
                if let archive = search.recordings.archives.first(where: { $0.id == result.objectID }) {
                    NavigationStack {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                if ask { Text("Choose the recording passages below, then approve Jasper’s scope. Playback does not send audio to AI.").font(.subheadline).foregroundStyle(.secondary) }
                                WhisperRecordingArchivePlayerView(archive: archive)
                            }.padding(.horizontal, 16)
                        }.navigationTitle("Recording").navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                    }
                }
            case "People":
                if let person = search.people.first(where: { $0.id == result.objectID }) { RecruiterClientProfileView(prospect: person, focusJasper: ask) }
            default:
                NavigationStack {
                    WorkspaceWorkDetailView(model: search.work, itemID: result.objectID, focusJasper: ask)
                        .onAppear { search.work.path = [result.objectID] }
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                        .sheet(item: Binding(get: { search.work.draft }, set: { search.work.draft = $0 })) { draft in WorkspaceWorkEditor(draft: draft, model: search.work) }
                }
            }
        }
    }
}
