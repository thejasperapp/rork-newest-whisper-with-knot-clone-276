import SwiftUI
import UIKit

struct WhisperNotebookQuestionsView: View {
    let model: WhisperNotebookViewModel
    let documents: [WhisperNotebookDocument]
    var isActive: Bool = true
    @State private var questions: WhisperNotebookQuestionsViewModel = WhisperNotebookQuestionsViewModel()
    @State private var workflow: WhisperNotebookWorkflow = .ask
    @State private var question: String = ""
    @State private var consent: Bool = false
    @State private var writing: String = ""
    @State private var title: String = "Combined brief"
    @State private var saved: Bool = false
    @State private var resultContext: String = ""
    @State private var proposal: WhisperNotebookDocument.Proposal?
    @State private var destination: String = ""
    @State private var reviewTitle: String = ""
    @State private var reviewOwner: String = ""
    @State private var reviewWhen: String = ""

    private var signature: String { documents.map { "\($0.id):\($0.storageRevision)" }.joined(separator: "|") }
    private var context: String { "\(signature):\(workflow.rawValue):\(question)" }
    private var resultCurrent: Bool { resultContext == context && !blocked }
    private var validation: String? {
        do { _ = try WhisperNotebookIntelligence.selectionSources(owner: AccountStorage.currentUserID.lowercased(), documents: documents); return nil }
        catch { return error.localizedDescription }
    }
    private var blocked: Bool { !model.isCurrent || model.hasUnsavedChanges || model.saveError != nil || !isActive }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
            HStack {
                Label("Jasper", systemImage: "sparkle").font(.headline)
                Spacer()
                Text("\(documents.count) selected · private").font(.caption).foregroundStyle(.secondary)
            }
            Text("Only these notes. Never your entire notebook.").font(.caption).foregroundStyle(.secondary)
            Picker("Jasper task", selection: $workflow) {
                ForEach(WhisperNotebookWorkflow.allCases.filter { $0 != .highlights && ($0 != .enhance || documents.count == 1) }) { task in
                    Text(task.title).tag(task)
                }
            }.pickerStyle(.menu).frame(minHeight: 44)
            if workflow == .followups { trackedItems }
            TextField(workflow == .ask ? "What would you like to know?" : "Optional direction for this draft…", text: $question, axis: .vertical)
                .lineLimit(2...5).textFieldStyle(.roundedBorder)
            Text("\(question.count)/600 · Up to 8 notes and 24,000 source characters").font(.caption2).foregroundStyle(.secondary)
            DisclosureGroup("Review selected sources") {
                ForEach(documents) { document in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(document.displayTitle).font(.subheadline.weight(.semibold))
                        Text(document.notes).font(.caption).textSelection(.enabled)
                        if !document.transcript.isEmpty { Text("Supplied transcript").font(.caption.weight(.semibold)); Text(document.transcript).font(.caption).textSelection(.enabled) }
                    }.padding(.vertical, 8)
                }
            }.font(.caption)
            if let validation { Text(validation).font(.caption).foregroundStyle(.secondary) }
            if blocked { Text("Finish saving the open writing before using Jasper.").font(.caption).foregroundStyle(.secondary) }
            Toggle("Allow cloud AI to read this selected writing and supplied transcripts \(workflow == .enhance ? "and this note’s format preferences " : "")for this request using Cloud Credits. Explicitly copied meeting notes are included. No recording bytes or unselected archive notes are sent.", isOn: $consent)
                .font(.caption).disabled(blocked || validation != nil)
            if questions.answer != nil { Text("Generating again replaces this temporary draft. Save or copy any edits you want to keep first.").font(.caption).foregroundStyle(.secondary) }
            Button {
                guard model.save(), consent, !blocked else { return }
                guard workflow != .enhance || documents.count == 1 else { return }
                questions.ask(documents: documents, question: question, workflow: workflow)
                consent = false
            } label: {
                Label(questions.isGenerating ? "Reading selected sources…" : "\(workflow.title) with Jasper", systemImage: "sparkle")
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 46)
            }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                .disabled(blocked || validation != nil || !consent || (workflow == .ask && question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || question.count > 600 || questions.isGenerating)
            if questions.isGenerating { Button("Stop") { questions.reset() }.frame(minHeight: 44) }
            if let error = questions.errorText { Text(error).font(.footnote) }
            if let answer = questions.answer, model.isCurrent { resultView(answer) }
        }
        .onChange(of: signature) { _, _ in invalidate(); if documents.count != 1 && workflow == .enhance { workflow = .summarize } }
        .onChange(of: title) { _, _ in saved = false }
        .onChange(of: writing) { _, _ in saved = false }
        .onChange(of: workflow) { _, _ in invalidate() }
        .onChange(of: question) { _, _ in invalidate() }
        .onChange(of: blocked) { _, _ in invalidate() }
        .onChange(of: questions.answer) { _, result in
            if let result { resultContext = context; writing = WhisperNotebookWorkflow.writing(result); title = workflow == .summarize ? "Combined brief" : "\(workflow.title) · selected notes"; saved = false }
        }
        .onDisappear { invalidate() }
        .sheet(isPresented: Binding(get: { proposal != nil }, set: { if !$0 { proposal = nil } })) { reviewSheet }
    }

    private var trackedItems: some View {
        DisclosureGroup("Already tracked by you") {
            ForEach(documents) { document in
                VStack(alignment: .leading, spacing: 8) {
                    Text(document.displayTitle).font(.subheadline.weight(.semibold))
                    if document.commitments.isEmpty { Text("No tracked items").font(.caption).foregroundStyle(.secondary) }
                    ForEach(document.commitments) { item in
                        Text("\(item.done ? "Completed" : "Open") · \(item.title) · \(item.owner.isEmpty ? "Unassigned" : item.owner) · \(item.when.isEmpty ? "No date" : item.when)").font(.caption)
                    }
                }.padding(.vertical, 8)
            }
        }.font(.subheadline)
    }

    private func resultView(_ answer: WhisperNotebookDocument.Result) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("\(resultCurrent ? "AI draft" : "Previous draft · not the current request") · \(questions.sources.map(\.displayTitle).joined(separator: " · ")). Original source snapshots retained; check citations.").font(.caption).foregroundStyle(.secondary)
            if answer.insufficient { Text("There isn’t enough evidence in the selected notes.").font(.subheadline) }
            ForEach(answer.sections, id: \.title) { section in
                VStack(alignment: .leading, spacing: 12) {
                    Text(section.title).font(.system(.title3, design: .serif))
                    ForEach(section.items, id: \.text) { item in
                        Text(item.text).font(.subheadline).textSelection(.enabled)
                        citations(item.sourceIds, answer: answer)
                    }
                }
            }
            if workflow == .enhance, documents.count == 1 {
                Button("Keep enhanced version in this note") { _ = model.keepEnhancement(answer, snapshots: questions.sources) }
                    .frame(minHeight: 44).disabled(!resultCurrent)
            }
            ForEach(answer.actions, id: \.title) { action in
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    Text("Suggested · not tracked").font(.caption).foregroundStyle(.secondary)
                    Text(action.title).font(.subheadline.weight(.semibold))
                    Text("\(action.owner.isEmpty ? "Unassigned" : action.owner) · \(action.when.isEmpty ? "No date stated" : action.when)").font(.caption)
                    citations(action.sourceIds, answer: answer)
                    Button("Review & track") {
                        destination = ""; reviewTitle = action.title; reviewOwner = action.owner; reviewWhen = action.when; proposal = action
                    }.frame(minHeight: 44).disabled(!resultCurrent)
                }
            }
            if !answer.insufficient {
                DisclosureGroup("Edit & save a separate draft") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Draft title", text: $title).accessibilityLabel("Combined draft title")
                        TextEditor(text: $writing).frame(minHeight: 220).accessibilityLabel("Editable combined draft")
                        Text("A new private note includes source snapshots and original note references, with account saving queued. Nothing is sent to attendees.").font(.caption).foregroundStyle(.secondary)
                        Button("Save as new note") { saved = model.saveBrief(documents: questions.sources, result: answer, title: title, writing: writing) }
                            .frame(minHeight: 44).disabled(blocked || title.count > 160 || writing.count > 30000 || writing.isEmpty || saved)
                        Button("Copy draft") { UIPasteboard.general.string = writing; Haptics.tap() }.frame(minHeight: 44)
                        if saved { Text("New note saved locally; account confirmation is pending. Originals are unchanged.").font(.caption) }
                        if let error = model.errorText { Text(error).font(.caption).foregroundStyle(.red) }
                    }.padding(.top, 12)
                }.font(.subheadline)
            }
        }
    }

    private func citations(_ ids: [String], answer: WhisperNotebookDocument.Result) -> some View {
        ForEach(ids, id: \.self) { id in
            if let source = answer.sources.first(where: { $0.id == id }) {
                let document = sourceDocument(id)
                DisclosureGroup("Source \(id) · \(document?.displayTitle ?? "Note")") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(source.text).textSelection(.enabled)
                        Text("Saved revision \(document?.storageRevision ?? 0) · Original selection kept").foregroundStyle(.secondary)
                    }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                }.font(.caption).frame(minHeight: 44)
            }
        }
    }

    private var reviewSheet: some View {
        NavigationStack {
            Form {
                Section("Destination note") {
                    Picker("Track in", selection: $destination) {
                        Text("Choose a note…").tag("")
                        ForEach(documents) { Text($0.displayTitle).tag($0.id) }
                    }
                }
                Section("Review before tracking") {
                    TextField("Follow-up", text: $reviewTitle, axis: .vertical)
                    TextField("Owner (optional)", text: $reviewOwner)
                    TextField("Timing (optional)", text: $reviewWhen)
                    Text("No message, invitation or project task is sent.").font(.caption)
                }
                if let error = model.errorText { Text(error).font(.caption).foregroundStyle(.red) }
                Button("Track in chosen note") {
                    guard let proposal, let result = questions.answer else { return }
                    let edited = WhisperNotebookDocument.Proposal(title: reviewTitle, owner: reviewOwner, when: reviewWhen, sourceIds: proposal.sourceIds)
                    if model.trackSelected(edited, result: result, destination: destination, snapshots: questions.sources) { self.proposal = nil }
                }.disabled(blocked || destination.isEmpty || reviewTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reviewTitle.count > 300 || reviewOwner.count > 80 || reviewWhen.count > 80)
            }
            .navigationTitle("Review follow-up").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { proposal = nil } } }
        }
    }
    private func invalidate() { questions.cancelPending(); consent = false; proposal = nil }
    private func sourceDocument(_ id: String) -> WhisperNotebookDocument? {
        guard let prefix = id.split(separator: "-").first, let number = Int(prefix.dropFirst()), number > 0, number <= questions.sources.count else { return nil }
        return questions.sources[number - 1]
    }
}
