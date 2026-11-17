import SwiftUI

struct WhisperNotebookEditorView: View {
    @Bindable var model: WhisperNotebookViewModel
    let documentID: String
    let onCollapse: () -> Void
    var recordingRefreshID: UUID? = nil
    var isMeetingCanvas: Bool = false
    var usesSelectionJasper: Bool = true
    var isSidekick: Bool = false
    var externalContext: WhisperNotebookContext? = nil
    var onClearExternal: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var passageSelection: WhisperNotebookHighlight?
    @State private var organizeOpen: Bool = false
    @State private var showEnhanced: Bool = false
    @State private var transcriptOpen: Bool = false
    @State private var jasperOpen: Bool = false
    @State private var question: String = ""
    @State private var showAIConsent: Bool = false
    @State private var pendingQuestion: String?
    @State private var selectedSource: WhisperNotebookDocument.Source?
    @State private var proposal: WhisperNotebookDocument.Proposal?
    @State private var reviewTitle: String = ""
    @State private var reviewOwner: String = ""
    @State private var reviewWhen: String = ""

    var body: some View {
        Group {
            if let document = model.draft, document.id == documentID, model.isCurrent {
                Group {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Label(model.saveError != nil ? "Couldn't save changes" : model.hasUnsavedChanges ? "Saving…" : document.cloudRevision != nil && document.syncedStorageRevision == document.storageRevision ? "Saved to account" : model.syncError != nil ? "Account save needs attention" : "Waiting for account confirmation", systemImage: "lock")
                                .font(.caption).foregroundStyle(WhisperTheme.muted(colorScheme))
                            Spacer()
                            Menu {
                                ShareLink(item: document.exportText) { Label("Export entire note", systemImage: "square.and.arrow.up") }
                                Button("Organize & format", systemImage: "folder") { organizeOpen.toggle() }
                                Button("Refresh private sync", systemImage: "arrow.clockwise") { model.requestSync() }
                                if document.syncEnabled != true { Button("Save to my account", systemImage: "icloud.and.arrow.up") { model.enableSync() } }
                                if !isMeetingCanvas || isSidekick { Button(isSidekick ? "Finish editing" : "Collapse note", systemImage: "chevron.up") { if model.closeEditor(ifID: documentID) { onCollapse() } } }
                            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                            .accessibilityLabel("Note options")
                        }
                        if let error = model.syncError, document.syncedStorageRevision != document.storageRevision {
                            Text(error).font(.caption).foregroundStyle(.secondary)
                            Button("Retry account save") { model.requestSync() }.font(.caption).frame(minHeight: 44)
                        }
                        if !usesSelectionJasper && (!isMeetingCanvas || organizeOpen) {
                            TextField("Untitled note", text: field(\.title, maximum: 160, changesSources: false), axis: .vertical)
                                .font(.system(.largeTitle, design: .serif)).lineLimit(1...3)
                        }
                        if !isMeetingCanvas {
                            WhisperNotebookRecordingSourcesView(meetingID: document.meetingId, recordingID: document.id, attachmentIDs: document.recordingIds, refreshID: recordingRefreshID, onImportTranscript: { text in model.importTranscript(text, documentID: documentID); transcriptOpen = true })
                        }
                        if organizeOpen {
                            DisclosureGroup("Organize & format", isExpanded: $organizeOpen) {
                            VStack(alignment: .leading, spacing: 14) {
                                TextField("Folder or project", text: field(\.folder, maximum: 80, changesSources: false))
                                TextField("People · names for your own reference", text: field(\.people, maximum: 300, changesSources: false))
                                Picker("Format", selection: field(\.templateId, maximum: 60)) {
                                    ForEach(WhisperNotebookTemplate.allCases) { Text($0.title).tag($0.rawValue) }
                                }
                                TextField("Custom outline preferences (optional)", text: field(\.instructions, maximum: 1000), axis: .vertical)
                                    .lineLimit(2...5)
                                Text("Changing the format never replaces your writing.").font(.caption).foregroundStyle(WhisperTheme.muted(colorScheme))
                            }.font(.subheadline).padding(.top, 12)
                            }.font(.subheadline.weight(.semibold))
                        }
                        if isSidekick, let result = document.enhancement {
                            Picker("Notes version", selection: $showEnhanced) {
                                Text("Original notes").tag(false)
                                Text("Enhanced notes").tag(true)
                            }.pickerStyle(.menu).font(.caption)
                            if showEnhanced {
                                if document.hasStaleEnhancement { Text("Your writing changed after this enhancement. Its original sources are preserved.").font(.caption).foregroundStyle(.secondary) }
                                resultSections(result)
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            if !isSidekick { Text("My notes").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary) }
                            WhisperNotebookTextView(text: field(\.notes, maximum: 60000), kind: "notes", revision: document.revision, highlights: document.highlights ?? [], label: "My original notes", onSelection: { passageSelection = $0 })
                                .frame(height: 250)
                            if document.notes.isEmpty { Text("Write something worth remembering…").font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical, 8)
                            .frame(height: isSidekick && showEnhanced && document.enhancement != nil ? 0 : nil)
                            .opacity(isSidekick && showEnhanced && document.enhancement != nil ? 0 : 1)
                            .clipped()
                            .allowsHitTesting(!isSidekick || !showEnhanced || document.enhancement == nil)
                            .accessibilityHidden(isSidekick && showEnhanced && document.enhancement != nil)
                        if !isSidekick || !document.transcript.isEmpty {
                        DisclosureGroup("Transcript", isExpanded: $transcriptOpen) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("PASTED TRANSCRIPT").font(.caption.weight(.bold)).tracking(1.2)
                                Text("Import the saved recording transcript above, or paste text you have permission to use. Nothing is imported automatically. Speaker labels in pasted text are not verified.")
                                    .font(.footnote).foregroundStyle(WhisperTheme.muted(colorScheme))
                                WhisperNotebookTextView(text: field(\.transcript, maximum: 60000), kind: "transcript", revision: document.revision, highlights: document.highlights ?? [], label: "Pasted transcript", onSelection: { passageSelection = $0 }).frame(height: 230)
                                Text("Jasper reads up to 24,000 characters and 160 passages per entry. Longer text stays saved, but needs splitting before enhancement.")
                                    .font(.caption).foregroundStyle(WhisperTheme.muted(colorScheme))
                            }
                        }
                        }
                        if isSidekick {
                            if let passageSelection {
                                Button("Highlight selected writing") { model.retainHighlight(passageSelection) }.font(.caption).frame(minHeight: 44)
                            }
                        } else {
                            WhisperNotebookInlineJasperView(model: model, selection: passageSelection, externalSources: externalContext?.sources, externalLabel: externalContext?.label, onClearExternal: onClearExternal)
                        }
                        if let highlights = document.highlights, !highlights.isEmpty {
                            DisclosureGroup("Retained highlights · \(highlights.count)") {
                                ForEach(highlights) { item in
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(item.text).font(.subheadline).textSelection(.enabled)
                                            Text("\(item.kind) · \(item.origin)\(item.stale ? " · original quote; writing changed" : "")").font(.caption2).foregroundStyle(.secondary)
                                        }
                                        Spacer(); Button("Remove") { model.removeHighlight(item.id) }.font(.caption).frame(minHeight: 44)
                                    }.padding(.vertical, 6)
                                }
                            }.font(.caption)
                        }
                        if !isSidekick || !document.commitments.isEmpty || !(document.enhancement?.actions.isEmpty ?? true) {
                        DisclosureGroup(isExpanded: $jasperOpen) { jasperSection(document).padding(.top, 12) } label: {
                            Label(isSidekick ? "Next steps" : usesSelectionJasper ? "Saved drafts & tracked items" : "Review with Jasper", systemImage: "sparkle").font(.subheadline.weight(.semibold))
                        }
                        }
                        if let error = model.errorText { Text(error).font(.footnote).foregroundStyle(.red).accessibilityAddTraits(.isStaticText) }
                        if let error = model.saveError {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(error).font(.footnote).foregroundStyle(.red)
                                Button("Try saving again") { model.save() }.frame(minHeight: 44)
                                Button("Save as a new copy") { if model.saveAsCopy() { onCollapse() } }.frame(minHeight: 44)
                            }
                        }
                    }.padding(.vertical, 12)
                }
                .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
                .background(isSidekick ? Color.clear : WhisperTheme.surface(colorScheme))
            } else {
                ContentUnavailableView("Reopen this note", systemImage: "note.text", description: Text(model.saveError ?? "Your notebook belongs to your signed-in account."))
            }
        }
        .onChange(of: model.draft?.enhancement) { _, value in if value != nil { jasperOpen = true; if isSidekick { showEnhanced = true } } }
        .onAppear { if isSidekick && model.draft?.enhancement != nil { showEnhanced = true } }
        .onDisappear { if isSidekick { model.save() } else { model.closeEditor(ifID: documentID) } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.save() } else { model.requestSync() } }
        .onReceive(NotificationCenter.default.publisher(for: WhisperNotebookSyncService.didSync)) { _ in model.refreshSaveMetadata() }
        .confirmationDialog("Send this entry to Jasper?", isPresented: $showAIConsent, titleVisibility: .visible) {
            Button(pendingQuestion == nil ? "Enhance my notes" : "Ask Jasper") { model.generate(question: pendingQuestion) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your notes, pasted transcript, and outline preferences will be processed by cloud AI using Cloud Credits. Your original writing stays unchanged. Nothing is sent to meeting attendees or your team.")
        }
        .sheet(item: $selectedSource) { source in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(source.provenance ?? (source.kind == "notes" ? "Your original notes" : "Pasted transcript")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(source.text).font(.body).textSelection(.enabled)
                        Text("Source snapshot from when this draft was generated. A citation lets you check the text; it doesn't guarantee Jasper interpreted it correctly.").font(.footnote).foregroundStyle(.secondary)
                    }.padding(16)
                }.scrollIndicators(.hidden)
                    .navigationTitle("Source \(source.id)").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { selectedSource = nil } } }
            }.presentationDetents([.medium, .large]).presentationContentInteraction(.scrolls)
        }
        .sheet(isPresented: Binding(get: { proposal != nil }, set: { if !$0 { proposal = nil } })) {
            WhisperNotebookFollowupSheet(title: $reviewTitle, owner: $reviewOwner, when: $reviewWhen) {
                if let proposal, let result = model.draft?.enhancement {
                    let edited = WhisperNotebookDocument.Proposal(title: reviewTitle, owner: reviewOwner, when: reviewWhen, sourceIds: proposal.sourceIds)
                    model.track(edited, sources: result.sources)
                }
                proposal = nil
            }
        }
    }

    private func field(_ key: WritableKeyPath<WhisperNotebookDocument, String>, maximum: Int, changesSources: Bool = true) -> Binding<String> {
        Binding(get: { model.draft?[keyPath: key] ?? "" }, set: { guard model.draft?.id == documentID else { return }; model.edit(key, value: $0, maximum: maximum, changesSources: changesSources) })
    }

    private func jasperSection(_ document: WhisperNotebookDocument) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if !usesSelectionJasper {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkle").font(.title2).foregroundStyle(LinearGradient(colors: WhisperBrandGradient.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                VStack(alignment: .leading, spacing: 4) {
                    Text("From conversation to clarity.").font(.headline)
                    Text("Source-linked drafts. You make the final call.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if model.isGenerating {
                HStack { ProgressView(); Text("Jasper is reading your sources…").font(.footnote); Spacer(); Button("Stop") { model.cancelGeneration() }.frame(minHeight: 44) }
            } else {
                Button { pendingQuestion = nil; showAIConsent = true } label: {
                    Label(document.enhancement == nil ? "Enhance my notes" : "Regenerate draft", systemImage: "sparkle")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 46)
                        .foregroundStyle(WhisperTheme.surface(colorScheme)).background(WhisperTheme.ink(colorScheme), in: Capsule())
                }.buttonStyle(.plain)
            }
            }
            if document.hasStaleEnhancement {
                Label("Your sources or format changed. This draft refers to its original snapshot.", systemImage: "clock.arrow.circlepath").font(.footnote).foregroundStyle(WhisperBrandGradient.accent)
            }
            if let result = document.enhancement {
                if !isSidekick { resultSections(result) }
                if !result.actions.isEmpty {
                    Text("PROPOSED FOLLOW-UPS").font(.caption.weight(.bold)).tracking(1.2)
                    Text("Review the wording, owner and timing before tracking. No messages, invitations or project tasks are sent.").font(.caption).foregroundStyle(.secondary)
                    ForEach(result.actions, id: \.title) { action in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(action.title).font(.subheadline.weight(.semibold))
                            Text("\(action.owner.isEmpty ? "Unassigned" : action.owner) · \(action.when.isEmpty ? "No date stated" : action.when)").font(.caption).foregroundStyle(.secondary)
                            citations(action.sourceIds, in: result.sources)
                            Button("Review & track") {
                                reviewTitle = action.title; reviewOwner = action.owner; reviewWhen = action.when; proposal = action
                            }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                                .disabled(document.hasStaleEnhancement || document.commitments.contains { $0.title.lowercased() == action.title.lowercased() })
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(WhisperTheme.card(colorScheme), in: .rect(cornerRadius: 16))
                    }
                }
            }
            if !document.commitments.isEmpty {
                Text("TRACKED BY YOU").font(.caption.weight(.bold)).tracking(1.2)
                ForEach(document.commitments) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Button { model.toggleCommitment(item.id) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: item.done ? "checkmark.circle.fill" : "circle").font(.title3)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).strikethrough(item.done)
                                    Text("\(item.owner.isEmpty ? "Unassigned" : item.owner) · \(item.when.isEmpty ? "No due date" : item.when)").font(.caption).foregroundStyle(.secondary)
                                }
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }.buttonStyle(.plain).accessibilityLabel("\(item.done ? "Reopen" : "Complete") follow-up: \(item.title)")
                        citations(item.sources.map(\.id), in: item.sources)
                    }
                }
            }
            Divider()
            if !usesSelectionJasper {
            Text("Ask this note").font(.headline)
            TextField("What is still unresolved?", text: $question, axis: .vertical).lineLimit(1...4)
                .onChange(of: question) { _, value in if value.count > 600 { question = String(value.prefix(600)) } }
            Button { pendingQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines); showAIConsent = true } label: { Label("Ask Jasper", systemImage: "arrow.up").frame(minHeight: 44) }
                .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isGenerating)
            if let answer = model.answer { resultSections(answer) }
            }
            Text("Jasper can make mistakes. Check the sources before relying on a draft. Answers search this entry only; they are not team-wide memory.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func resultSections(_ result: WhisperNotebookDocument.Result) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if result.insufficient { Text("There isn't enough information in these sources to answer that reliably.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(result.sections, id: \.title) { section in
                VStack(alignment: .leading, spacing: 12) {
                    Text(section.title).font(.headline)
                    ForEach(section.items, id: \.text) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.text).font(.subheadline).textSelection(.enabled)
                            citations(item.sourceIds, in: result.sources)
                        }
                    }
                }
            }
        }
    }
    private func citations(_ ids: [String], in sources: [WhisperNotebookDocument.Source]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], alignment: .leading, spacing: 4) {
            ForEach(Array(Set(ids)).sorted(), id: \.self) { id in
                Button(id) { selectedSource = sources.first { $0.id == id } }
                    .font(.caption.monospaced().weight(.semibold)).frame(minWidth: 44, minHeight: 44)
                    .background(WhisperTheme.card(colorScheme), in: Capsule())
                    .accessibilityLabel("Read source \(id)")
            }
        }
    }
}
