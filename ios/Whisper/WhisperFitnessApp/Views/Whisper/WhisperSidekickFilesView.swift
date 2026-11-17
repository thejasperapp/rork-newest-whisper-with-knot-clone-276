import SwiftUI

struct WhisperSidekickFilesView: View {
    @Bindable var model: WhisperMeetingSidekickViewModel
    let meetingID: String
    @State private var query: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Bring your context.").font(.system(.title2, design: .serif))
                Spacer()
                Button { model.filesOpen = false } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Close file picker")
            }
            Text("Select past transcripts or private notes. Only chosen files join your next request. No audio files are sent.").font(.caption).foregroundStyle(.secondary)
            TextField("Search meetings, notes, folders…", text: $query).textFieldStyle(.roundedBorder).frame(minHeight: 44)
            ForEach(model.files) { file in
                Button { model.removeFile(file.id) } label: {
                    HStack { Text(file.title).font(.caption); Spacer(); Image(systemName: "checkmark.circle.fill") }.frame(minHeight: 44)
                }
            }
            let notes = model.notebook.documents.filter { note in
                note.id != model.notebook.draft?.id && !model.files.contains { $0.id == "note:\(note.id)" } && matches("\(note.title) \(note.people) \(note.folder)")
            }
            Text("PRIVATE NOTES").font(.caption2.weight(.semibold)).tracking(1.3).foregroundStyle(.secondary)
            ForEach(notes) { note in
                Button { model.addNote(note) } label: {
                    row(title: note.displayTitle, detail: "\(note.folder.isEmpty ? "Private note" : note.folder) · \(note.updatedAt.prefix(10))")
                }.buttonStyle(.plain)
            }
            let meetings = model.archive.meetings.filter { meeting in
                meeting.id != meetingID && !model.files.contains { $0.id == "meeting:\(meeting.id)" } && matches(meeting.title)
            }
            Text("PAST MEETING TRANSCRIPTS").font(.caption2.weight(.semibold)).tracking(1.3).foregroundStyle(.secondary)
            ForEach(meetings) { meeting in
                Button { Task { await model.addMeeting(meeting) } } label: {
                    row(title: meeting.title, detail: "\((meeting.ended_at ?? meeting.created_at ?? "").prefix(10)) · Load saved transcript")
                }.buttonStyle(.plain).disabled(model.isReadingFile)
            }
            if notes.isEmpty && meetings.isEmpty && !model.archive.isLoading && !model.notebook.isLoading && model.archive.errorText == nil && model.notebook.errorText == nil {
                WhisperEmptyState(icon: "folder", title: "No other matching files", message: "Try another search or load older meetings. Files you've already selected are listed above.", isCard: false, compact: true)
            }
            if model.isReadingFile || model.archive.isLoading { ProgressView("Reading meeting files…").font(.caption) }
            if let error = model.archive.errorText {
                Text(error).font(.caption).foregroundStyle(.red)
                Button("Retry meeting library") { Task { await model.archive.load(includeWithoutSummary: true) } }.frame(minHeight: 44)
            }
            if model.archive.canLoadMore {
                Button("Load older meetings") { Task { await model.archive.load(more: true, includeWithoutSummary: true) } }.font(.caption).frame(minHeight: 44).disabled(model.archive.isLoading)
            }
            Divider()
        }
    }

    private func matches(_ text: String) -> Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.localizedStandardContains(query) }
    private func row(title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.subheadline); Text(detail).font(.caption2).foregroundStyle(.secondary) }
            Spacer()
        }.frame(minHeight: 50).padding(.vertical, 6)
    }
}
