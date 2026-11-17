import SwiftUI

struct RecruiterClientProfileView: View {
    let prospect: WhisperRecruiterService.ProspectRow
    var focusJasper: Bool = false
    @State private var showingJasperFirst: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var model: RecruiterClientViewModel = RecruiterClientViewModel()
    @State private var archive: WhisperNotebookArchiveViewModel = WhisperNotebookArchiveViewModel()
    @State private var showMeetings: Bool = false
    @State private var meetingSearch: String = ""
    @State private var confirmReload: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                if !model.isCurrent { Text("Your account changed. Reopen this person.") }
                else if !model.isLoaded {
                    if model.isBusy { ProgressView("Loading private profile…") }
                    else { Button("Retry private profile") { Task { await model.load(id: prospect.id) } } }
                } else {
                    if focusJasper || showingJasperFirst { memorySection; answerSection }
                    else { Section { Button("Ask Jasper about this", systemImage: "sparkles") { showingJasperFirst = true } } }
                    contactSection
                    followUpSection
                    if !focusJasper && !showingJasperFirst { memorySection }
                    Section { RecruiterPromotionRecordsView() }
                    if !focusJasper && !showingJasperFirst { answerSection }
                    Section("Recorded stage history") {
                        if model.client.stageHistory.isEmpty { Text("Earlier stage dates weren’t recorded. New moves are tracked separately from edits.").font(.caption).foregroundStyle(.secondary) }
                        ForEach(model.client.stageHistory) { entry in
                            LabeledContent(WhisperRecruiterService.stageLabel(entry.stage), value: WhisperBackendService.parseISO(entry.at)?.formatted(date: .abbreviated, time: .shortened) ?? entry.at)
                        }
                    }
                    Section { RecruiterTeamPipelineView(prospect: prospect) }
                }
                if let error = model.errorText { Section { Text(error).foregroundStyle(.red); Text("Your unsaved draft is still here.").font(.caption); Button("Reload saved profile…") { confirmReload = true } } }
                if let notice = model.notice { Section { Text(notice).foregroundStyle(.secondary) } }
            }
            .navigationTitle("Private relationship")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await model.save(id: prospect.id) } }.disabled(!model.isLoaded || model.isBusy || !model.isCurrent) } }
            .task { await model.load(id: prospect.id) }
            .onDisappear { model.operation?.cancel() }
            .confirmationDialog("Discard this unsaved draft and reload?", isPresented: $confirmReload) { Button("Reload saved profile", role: .destructive) { Task { await model.load(id: prospect.id) } } }
            .sheet(isPresented: $showMeetings) { meetingPicker }
        }
    }
    private var contactSection: some View {
        Section {
            TextField("Email", text: $model.client.email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
            TextField("Phone", text: $model.client.phone).keyboardType(.phonePad)
            TextField("Contact preferences", text: $model.client.preferences, axis: .vertical).lineLimit(2...5)
            TextField("Relationship notes", text: $model.client.relationshipNotes, axis: .vertical).lineLimit(3...8)
        } header: { Label("Only you", systemImage: "lock") } footer: { Text("Your relationship notebook for this creator or coach. People keeps the private details and follow-ups; Pipeline tracks progress. Team cards are separate, reviewed snapshots. Saving here never publishes them or sends these fields to Jasper.") }
        .disabled(model.isBusy)
    }
    private var followUpSection: some View {
        Section("Next conversation") {
            TextField("Next follow-up", text: $model.client.followUp, axis: .vertical)
            Toggle("Follow-up has a due date", isOn: Binding(get: { !model.client.followUpDue.isEmpty }, set: { model.client.followUpDue = $0 ? WhisperRecruiterService.dueDateString(Date()) : "" }))
            if !model.client.followUpDue.isEmpty {
                DatePicker("Due", selection: Binding(get: { WhisperRecruiterService.parseDueDate(model.client.followUpDue) ?? Date() }, set: { model.client.followUpDue = WhisperRecruiterService.dueDateString($0) }), displayedComponents: .date)
            }
            Toggle("Next meeting planned", isOn: Binding(get: { !model.client.nextMeetingAt.isEmpty }, set: { model.client.nextMeetingAt = $0 ? Date().ISO8601Format() : "" }))
            if !model.client.nextMeetingAt.isEmpty {
                DatePicker("Meeting", selection: Binding(get: { WhisperBackendService.parseISO(model.client.nextMeetingAt) ?? Date() }, set: { model.client.nextMeetingAt = $0.ISO8601Format() }))
                Text("A private planning date, not an invitation or calendar event.").font(.caption).foregroundStyle(.secondary)
            }
        }.disabled(model.isBusy)
    }
    private var memorySection: some View {
        Section {
            Button("Choose linked meetings · \(model.client.meetingIds.count)/8") { showMeetings = true }.disabled(model.isBusy)
            ForEach(model.client.meetingIds, id: \.self) { id in
                HStack {
                    Text(archive.meetings.first { $0.id == id }?.title ?? "Linked meeting").font(.subheadline)
                    Spacer()
                    Button("Unlink") { model.toggleMeeting(id) }.font(.caption)
                }
            }
            Toggle("Allow cloud AI for these selected meetings", isOn: Binding(get: { !model.scope.isEmpty && model.approvedScope == model.scope }, set: { model.approvedScope = $0 ? model.scope : ""; if !$0 { model.operation?.cancel(); model.answer = nil } }))
            ForEach(["Before-meeting refresher", "What did we promise them?", "Suggest follow-ups and profile updates"], id: \.self) { prompt in
                Button(prompt) { model.ask(prompt, name: name) }.disabled(!canAsk)
            }
            TextField("Ask about this relationship…", text: $model.question, axis: .vertical).lineLimit(2...4)
            Button("Ask Jasper") { model.ask(model.question, name: name) }.disabled(!canAsk || model.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if model.isBusy { ProgressView() }
        } header: { Text("Meeting memory") } footer: { Text("Save to keep these links. Jasper reads only selected saved speech and original notes, with labeled excerpts for long transcripts. Linking never grants meeting access or includes recordings.") }
    }
    @ViewBuilder private var answerSection: some View {
        if let answer = model.answer {
            Section("Answer and evidence") {
                JasperMeetingAnswerView(answer: answer)
                Text("Suggestions only fill your draft. Review, edit, then Save to apply.").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(answer.result.actions.enumerated()), id: \.offset) { _, action in
                    Button("Review follow-up: \(action.title)") { model.client.followUp = action.title; model.notice = "Choose a due date. Suggested timing: \(action.when)" }
                }
                ForEach(Array(answer.result.sections.flatMap(\.items).enumerated()), id: \.offset) { _, item in
                    Button("Review note: \(item.text)") {
                        let evidence = item.sourceIds.compactMap { id in answer.sources.first { $0.id == id } }.map { "\($0.meetingTitle) (\($0.spokenAt))" }.joined(separator: "; ")
                        model.client.relationshipNotes += "\n\(item.text)\nSource: \(evidence)"
                    }
                }
                if !answer.sources.isEmpty { Button("Keep answer with first cited meeting") { Task { await model.keepAnswer() } }.disabled(model.isBusy) }
            }.disabled(model.isBusy)
        }
    }
    private var name: String { prospect.prospect_display_name ?? prospect.prospect_username ?? "this creator or coach" }
    private var canAsk: Bool { !model.isBusy && !model.scope.isEmpty && model.scope == model.approvedScope }
    private var meetingPicker: some View {
        NavigationStack {
            List {
                Section("Select up to eight · \(model.client.meetingIds.count) selected") {
                    ForEach(archive.meetings.filter { meetingSearch.isEmpty || $0.title.localizedStandardContains(meetingSearch) }) { meeting in
                        Button { model.toggleMeeting(meeting.id) } label: {
                            HStack { VStack(alignment: .leading) { Text(meeting.title); Text(WhisperBackendService.parseISO(meeting.created_at ?? "")?.formatted(date: .abbreviated, time: .omitted) ?? "Date unavailable").font(.caption).foregroundStyle(.secondary) }; Spacer(); if model.client.meetingIds.contains(meeting.id) { Image(systemName: "checkmark.circle.fill") } }
                        }.disabled(!model.client.meetingIds.contains(meeting.id) && model.client.meetingIds.count >= 8)
                    }
                    if archive.isLoading { ProgressView() }
                    if let error = archive.errorText { Text(error); Button("Retry") { Task { await archive.load(includeWithoutSummary: true) } } }
                    if archive.canLoadMore { Button("Older meetings") { Task { await archive.load(more: true, includeWithoutSummary: true) } }.disabled(archive.isLoading) }
                }
            }
            .searchable(text: $meetingSearch, prompt: "Search loaded meetings")
            .navigationTitle("Linked meetings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showMeetings = false } } }
            .task { await archive.load(includeWithoutSummary: true) }
        }
    }
}
