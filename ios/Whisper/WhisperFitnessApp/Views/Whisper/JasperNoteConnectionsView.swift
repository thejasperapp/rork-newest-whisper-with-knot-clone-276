import SwiftUI

struct JasperNoteConnectionsView: View {
    var initialNote: JasperMeetingAnswer.NoteContext? = nil
    @State private var didLoadInitialNote: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var model: JasperNoteConnectionsViewModel = JasperNoteConnectionsViewModel()
    @State private var archive: WhisperNotebookArchiveViewModel = WhisperNotebookArchiveViewModel()
    @State private var showMeetings: Bool = false
    @State private var search: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Connect the dots", systemImage: "link").font(.title2.weight(.semibold))
                        Text("Bring one note and choose up to seven meetings. Jasper highlights possible links, prior decisions and contradictions—not automatic facts or edits.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    selection.disabled(model.isSaving)
                    if model.isAsking { HStack { ProgressView(); Text("Looking for connections…").font(.caption); Spacer(); Button("Stop") { model.invalidate() }.frame(minHeight: 44) } }
                    if let error = model.errorText { Text(error).font(.caption).foregroundStyle(.red) }
                    if let answer = model.answer { result(answer) }
                }.padding(.horizontal, 16).padding(.vertical, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Find connections").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(model.isSaving) } }
            .sheet(isPresented: $showMeetings) { meetingPicker }
            .task { model.loadNotes(); if !didLoadInitialNote, let initialNote { model.title = initialNote.title; model.editText(initialNote.text); didLoadInitialNote = true } }
            .onDisappear { model.invalidate() }
        }
    }
    private var selection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Saved private writing", selection: Binding(get: { model.origin?.id ?? "" }, set: { model.chooseNote($0) })) {
                Text("Paste or write an excerpt").tag("")
                ForEach(model.notes) { note in Text(note.displayTitle).tag(note.id) }
            }.font(.subheadline)
            Button("Refresh saved writing") { model.loadNotes() }.font(.caption).frame(minHeight: 44)
            TextField("Note title", text: Binding(get: { model.title }, set: { model.invalidate(); model.title = $0 })).textFieldStyle(.roundedBorder)
            Text("Writing to analyze").font(.caption.weight(.semibold))
            TextEditor(text: Binding(get: { model.text }, set: { model.editText($0) }))
                .font(.subheadline).frame(height: 160).padding(8).background(.quaternary, in: .rect(cornerRadius: 14))
                .accessibilityLabel("Writing to analyze")
            Text("\(model.text.utf16.count.formatted()) / 8,000 characters. Editing this excerpt does not edit your saved note.").font(.caption).foregroundStyle(.secondary)
            Button("Choose meetings · \(model.meetingIDs.count)/7", systemImage: "calendar") { showMeetings = true }.buttonStyle(.bordered).controlSize(.large)
            ForEach(model.meetingIDs, id: \.self) { id in
                HStack { Text(archive.meetings.first { $0.id == id }?.title ?? "Selected meeting").font(.caption); Spacer(); Button("Remove") { model.toggleMeeting(id) }.font(.caption).frame(minHeight: 44) }
            }
            Toggle(isOn: Binding(get: { model.approved }, set: { if $0 { model.approved = true } else { model.invalidate() } })) {
                Text("Allow cloud AI for this writing and these \(model.meetingIDs.count) selected meetings").font(.caption)
            }
            Text("No other notes or recordings. Temporary answers expire after 24 hours unless kept. Nothing is sent to attendees.").font(.caption2).foregroundStyle(.secondary)
            Button("Analyze selected context") { model.ask() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.canAsk)
        }
    }
    private func result(_ answer: JasperMeetingAnswer) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
            JasperMeetingAnswerView(answer: answer)
            if !answer.result.insufficient {
                Toggle("I’ve reviewed these suggested connections and quotes", isOn: $model.reviewed).font(.caption).disabled(model.isSaving || model.saved)
                Picker("Keep privately with", selection: $model.destination) {
                    Text("Choose a meeting").tag("")
                    ForEach(sourceMeetings(answer)) { meeting in Text(meeting.name).tag(meeting.id) }
                }.font(.caption).disabled(model.isSaving || model.saved)
                Button(model.saved ? "Connections kept privately" : "Keep reviewed connections") { Task { await model.keep() } }
                    .buttonStyle(.bordered).controlSize(.large).disabled(!model.reviewed || model.destination.isEmpty || model.isSaving || model.saved)
            }
            if !model.saved { Button("Dismiss connections") { Task { await model.discard() } }.frame(minHeight: 44).disabled(model.isSaving) }
        }
    }
    private func sourceMeetings(_ answer: JasperMeetingAnswer) -> [JasperMeetingLibrary.Folder] {
        var seen: Set<String> = []
        return answer.sources.compactMap { source in seen.insert(source.meetingId).inserted ? .init(id: source.meetingId, name: source.meetingTitle) : nil }
    }
    private var meetingPicker: some View {
        NavigationStack {
            List {
                Section("Choose 1–7 meetings · \(model.meetingIDs.count) selected") {
                    ForEach(archive.meetings.filter { search.isEmpty || $0.title.localizedStandardContains(search) || model.meetingIDs.contains($0.id) }) { meeting in
                        Button { model.toggleMeeting(meeting.id) } label: {
                            HStack {
                                VStack(alignment: .leading) { Text(meeting.title); Text(String((meeting.created_at ?? "").prefix(10))).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Image(systemName: model.meetingIDs.contains(meeting.id) ? "checkmark.circle.fill" : "circle")
                            }
                        }.disabled(!model.meetingIDs.contains(meeting.id) && model.meetingIDs.count >= 7)
                    }
                    if archive.isLoading { ProgressView() }
                    if let error = archive.errorText { Text(error); Button("Retry") { Task { await archive.load(includeWithoutSummary: true) } } }
                    if archive.canLoadMore { Button("Older meetings") { Task { await archive.load(more: true, includeWithoutSummary: true) } }.disabled(archive.isLoading) }
                }
            }
            .searchable(text: $search, prompt: "Search loaded meetings")
            .navigationTitle("Selected meetings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showMeetings = false } } }
            .task { if archive.meetings.isEmpty { await archive.load(includeWithoutSummary: true) } }
        }
    }
}
