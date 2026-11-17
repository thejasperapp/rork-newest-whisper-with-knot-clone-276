import SwiftUI

struct WhisperNotebookArchiveView: View {
    let model: WhisperNotebookViewModel
    let meetingID: String?
    let adding: Bool
    let canChoose: Bool
    let onChoose: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var archive: WhisperNotebookArchiveViewModel = WhisperNotebookArchiveViewModel()
    @State private var backTransition: WhisperBackAction = WhisperBackAction()
    @State private var search: String = ""
    @State private var preview: WhisperMeetingRow?
    @State private var recording: WhisperRecordingArchive?
    @State private var attach: Bool = true
    @State private var isOpening: Bool = false
    @State private var importTask: Task<Void, Never>?

    private var filtered: [WhisperMeetingRow] {
        guard archive.isCurrent else { return [] }
        return archive.meetings.filter { search.isEmpty || $0.title.localizedStandardContains(search) || ($0.summary ?? "").localizedStandardContains(search) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let preview, archive.isCurrent {
                        Button("All archived notes", systemImage: "arrow.left") { backTransition.perform { self.preview = nil; recording = nil; model.errorText = nil } }.frame(minHeight: 44).disabled(isOpening)
                        Text(preview.title).font(.system(.largeTitle, design: .serif))
                        Text("\(String((preview.ended_at ?? preview.created_at ?? "").prefix(10))) · AI-generated meeting note").font(.caption).foregroundStyle(.secondary)
                        WhisperNotebookRecordingSourcesView(meetingID: preview.id, onRecordingChange: { recording = $0 }).id(preview.id)
                        Text(preview.summary ?? "").font(.body).textSelection(.enabled)
                        if let recording {
                            Toggle("Attach this recording · \(recording.title)", isOn: $attach).font(.subheadline)
                        }
                        Text("Use in Notebook saves a private, editable copy and \(adding ? "adds it to your selection" : "opens it for writing"). Existing edits and attachments are kept. No transcript, upload or AI request is automatic.").font(.caption).foregroundStyle(.secondary)
                        Button {
                            guard !isOpening else { return }
                            isOpening = true; model.errorText = nil
                            let chosen = attach ? recording : nil
                            importTask = Task {
                                let id = await model.useArchivedMeeting(preview, recording: chosen)
                                isOpening = false
                                guard !Task.isCancelled, archive.isCurrent, let id else { return }
                                onChoose(id); dismiss()
                            }
                        } label: {
                            Label(isOpening ? "Opening private copy…" : adding ? "Use in Notebook · add to selection" : "Use in Notebook", systemImage: "sparkle").frame(maxWidth: .infinity, minHeight: 46)
                        }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).disabled(!canChoose || isOpening || !model.isCurrent)
                        if let error = model.errorText { Text(error).font(.caption).foregroundStyle(.red) }
                    } else {
                        Text("Meeting-generated notes, ready to revisit with Jasper.").font(.system(.title2, design: .serif))
                        Text("Shared originals stay unchanged. Choose only the notes you want to work with.").font(.subheadline).foregroundStyle(.secondary)
                        HStack { Image(systemName: "magnifyingglass"); TextField("Search notes archive", text: $search) }.frame(minHeight: 44)
                        LazyVStack(spacing: 0) {
                            ForEach(filtered) { meeting in
                                Button { backTransition.captureLocalPredecessor(); preview = meeting; recording = nil; attach = true; model.errorText = nil } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: "doc.text").foregroundStyle(WhisperBrandGradient.rose)
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(meeting.title).font(.headline)
                                            Text("\(String((meeting.ended_at ?? meeting.created_at ?? "").prefix(10))) · Generated from meeting\(meeting.id == meetingID ? " · This meeting" : "")").font(.caption).foregroundStyle(.secondary)
                                            Text(meeting.summary ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        }
                                        Spacer(minLength: 0)
                                    }.frame(maxWidth: .infinity, minHeight: 64, alignment: .leading).padding(.vertical, 14).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Divider()
                            }
                        }
                        if archive.isLoading { ProgressView("Opening notes archive…") }
                        if let error = archive.errorText {
                            Text(error).font(.caption).foregroundStyle(.secondary)
                            Button("Retry archive") { Task { await archive.load(meetingID: meetingID) } }.frame(minHeight: 44)
                        }
                        if filtered.isEmpty, !archive.isLoading, archive.errorText == nil { WhisperEmptyState(icon: "note.text", title: search.isEmpty ? "No generated notes yet" : "No matching notes", message: "Only loaded pages are included. Load older notes to search further.", isCard: false) }
                        if archive.canLoadMore { Button("Load older meeting notes") { Task { await archive.load(more: true) } }.frame(minHeight: 44).disabled(archive.isLoading) }
                    }
                }.padding(.horizontal, 16).padding(.vertical, 20)
            }
            .whisperEdgeBack(isEnabled: !isOpening, revealPresentation: preview == nil, controller: backTransition) {
                backTransition.perform { if preview != nil { preview = nil; recording = nil; model.errorText = nil } else { dismiss() } }
            }
            .navigationTitle("Notes archive").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.disabled(isOpening) } }
            .task { await archive.load(meetingID: meetingID) }
        }
        .interactiveDismissDisabled(isOpening)
        .presentationContentInteraction(.scrolls)
        .onDisappear { importTask?.cancel() }
    }
}
