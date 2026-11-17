import SwiftUI

struct WhisperNotebookView: View {
    let meetingID: String?
    let meetingTitle: String
    let noteID: String?
    let sharedRecap: AnyView?
    let onClose: (() -> Void)?
    let liveMeetingID: String?
    @State private var externalContext: WhisperNotebookContext?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: WhisperNotebookViewModel = WhisperNotebookViewModel()
    @State private var archiveModel: WhisperRecordingArchiveViewModel = WhisperRecordingArchiveViewModel()
    @State private var selectedIDs: [String] = []
    @State private var expandedDocumentID: String?
    @State private var mediaID: String?
    @State private var mediaMeetingID: String?
    @State private var mediaTitle: String = ""
    @State private var activeArchive: WhisperRecordingArchive?
    @State private var backTransition: WhisperBackAction = WhisperBackAction()
    @State private var showFocus: Bool = false
    @State private var selecting: Bool = false
    @State private var handledNote: Bool = false
    @State private var query: String = ""
    @State private var folder: String = ""
    @State private var recordingsOnly: Bool = false
    @State private var toolsOpen: Bool = false
    @State private var showSharedRecap: Bool = false
    @State private var showNotesArchive: Bool = false
    @State private var mediaAttachmentIDs: [String]?
    @State private var recordingRefreshID: UUID = UUID()
    @State private var deletion: WhisperNotebookDocument?

    init(meetingID: String? = nil, meetingTitle: String = "", noteID: String? = nil, sharedRecap: AnyView? = nil, onClose: (() -> Void)? = nil, liveMeetingID: String? = nil) {
        self.meetingID = meetingID; self.meetingTitle = meetingTitle; self.noteID = noteID
        self.sharedRecap = sharedRecap; self.onClose = onClose; self.liveMeetingID = liveMeetingID
    }
    private var picked: [WhisperNotebookDocument] {
        guard model.isCurrent else { return [] }
        return selectedIDs.compactMap { id in model.documents.first { $0.id == id } }
    }
    private var entries: [WhisperNotebookEntry] {
        guard model.isCurrent else { return [] }
        return WhisperNotebookEntry.build(notes: model.documents, archives: archiveModel.isCurrent ? archiveModel.archives : [], query: query, folder: folder, recordingsOnly: recordingsOnly)
    }
    private var folders: [String] { Array(Set(model.documents.map(\.folder).filter { !$0.isEmpty })).sorted() }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if !AuthenticationService.shared.isSignedIn {
                            ContentUnavailableView("Sign in to open Notebook", systemImage: "lock", description: Text("Private writing and recordings stay hidden until your account is signed in."))
                        } else {
                            library.frame(height: showFocus ? 0 : nil).clipped().opacity(showFocus ? 0 : 1).allowsHitTesting(!showFocus).accessibilityHidden(showFocus)
                            focusCanvas.frame(height: showFocus ? nil : 0).clipped().opacity(showFocus ? 1 : 0).allowsHitTesting(showFocus).accessibilityHidden(!showFocus)
                            recoverySection
                            if let error = model.errorText { Text(error).font(.footnote).foregroundStyle(.red) }
                            if toolsOpen, model.isCurrent { notebookTools }
                        }
                    }
                    .frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
                    .padding(.horizontal, 16).padding(.bottom, 24)
                }
                .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
                .whisperRefreshable {
                    guard AuthenticationService.shared.isSignedIn else { return }
                    recordingRefreshID = UUID()
                    model.requestSync()
                    await archiveModel.load()
                }
                .safeAreaInset(edge: .bottom) {
                    if model.isCurrent, selectedIDs.count > 1 {
                        Button {
                            guard model.save() else { return }
                            if !showFocus { backTransition.captureLocalPredecessor(); showFocus = true }
                            else { withAnimation { scroll.scrollTo("selection-jasper", anchor: .top) } }
                        } label: {
                            HStack { Image(systemName: "sparkle"); Text(showFocus ? "Jasper · \(selectedIDs.count) selected" : "Work with \(selectedIDs.count) selected notes"); Spacer(); Image(systemName: "arrow.up.right") }
                                .font(.subheadline.weight(.semibold)).padding(.horizontal, 18).frame(minHeight: 48)
                        }.buttonStyle(.plain).background(.regularMaterial, in: Capsule()).padding(.horizontal, 16).padding(.vertical, 8)
                    }
                }
            }
            .background(WhisperTheme.surface(colorScheme))
            .navigationTitle("Notebook").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(showFocus ? "Notes & recordings" : "Close") { goBack() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Notes archive", systemImage: "archivebox") { if model.save() { showNotesArchive = true } }
                        Button("New note", systemImage: "square.and.pencil") { create() }.disabled(!model.isCurrent || model.isLoading)
                        Button("Refresh", systemImage: "arrow.clockwise") { refresh() }
                        Button("Storage & sync", systemImage: "lock.icloud") { toolsOpen.toggle() }
                        if sharedRecap != nil { Button("Shared meeting recap", systemImage: "person.2") { showSharedRecap = true } }
                        if let note = model.draft { Button("Delete this note", systemImage: "trash", role: .destructive) { if model.save() { deletion = model.draft ?? note } } }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Notebook options")
                }
            }
            .task(id: "\(AuthenticationService.shared.currentUser.userID):\(AuthenticationService.shared.isSignedIn):\(AccountStorage.generation)") {
                externalContext = nil; selectedIDs = []; expandedDocumentID = nil; mediaID = nil; activeArchive = nil; showFocus = false; selecting = false; handledNote = false
                deletion = nil; query = ""; folder = ""; toolsOpen = false; showSharedRecap = false; showNotesArchive = false; mediaAttachmentIDs = nil
                archiveModel.stop(); archiveModel = WhisperRecordingArchiveViewModel()
                async let recordings: Void = archiveModel.load()
                await model.load()
                guard !Task.isCancelled else { return }
                openRequestedNote(); _ = await recordings; openRequestedNote()
            }
            .onChange(of: model.documents.map(\.id)) { _, _ in openRequestedNote() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled { do { try await Task.sleep(for: .seconds(20)) } catch { return }; model.requestSync() }
            }
            .confirmationDialog("Delete this note?", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
                if let deletion {
                    Button("Delete note", role: .destructive) {
                        guard model.save() else { return }
                        model.delete(deletion)
                        if !model.documents.contains(where: { $0.id == deletion.id }) {
                            selectedIDs.removeAll { $0 == deletion.id }
                            if expandedDocumentID == deletion.id { _ = model.closeEditor(ifID: deletion.id); expandedDocumentID = nil }
                        }
                        self.deletion = nil
                    }
                }
                Button("Cancel", role: .cancel) { deletion = nil }
            } message: { Text("Writing and follow-ups will be removed. Synced deletion reaches your other devices. Recordings stay available.") }
        }
        .onDisappear { archiveModel.stop() }
        .sheet(isPresented: $showNotesArchive) {
            WhisperNotebookArchiveView(model: model, meetingID: meetingID, adding: selecting, canChoose: !selecting || selectedIDs.count < 8) { id in
                if selecting { if !selectedIDs.contains(id) { toggle(id) } }
                else { open(id) }
            }.id(AccountStorage.generation)
        }
        .sheet(isPresented: $showSharedRecap) { sharedRecap?.environment(\.whisperInsideMeetingNotebook, true) }
        .whisperEdgeBack(requiresDecision: true, revealPresentation: !showFocus, controller: backTransition) { goBack() }
        .interactiveDismissDisabled(model.hasUnsavedChanges)
        .tint(WhisperTheme.ink(colorScheme))
    }

    private func goBack() {
        guard model.save() else { return }
        if showFocus { backTransition.perform { showFocus = false } }
        else { guard model.closeEditor() else { return }; backTransition.perform { if let onClose { onClose() } else { dismiss() } } }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Room for your next thought.").font(.system(.largeTitle, design: .serif)).padding(.top, 12)
            Text("Open a note to focus. Select a few to connect ideas.").font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search notes & recordings", text: $query)
                Button(selecting ? "Done" : "Select") { if model.save() { selecting.toggle() } }.frame(minHeight: 44)
                Button { create() } label: { Image(systemName: "square.and.pencil").frame(width: 44, height: 44) }.accessibilityLabel("New note")
            }.font(.subheadline)
            Button { if model.save() { showNotesArchive = true } } label: {
                Label("Notes archive · from meetings", systemImage: "archivebox").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain).font(.subheadline.weight(.medium))
            Picker("Browse", selection: $recordingsOnly) { Text("Notes & recordings").tag(false); Text("All recordings").tag(true) }.pickerStyle(.segmented)
            if !folders.isEmpty {
                Picker("Folder", selection: $folder) { Text("All folders").tag(""); ForEach(folders, id: \.self) { Text($0).tag($0) } }.pickerStyle(.menu)
            }
            if meetingID != nil { Text("\(meetingTitle.isEmpty ? "Meeting" : meetingTitle) · matching entries are marked below. Choose notes to set your context.").font(.caption).foregroundStyle(.secondary) }
            if !selectedIDs.isEmpty {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) { Text("\(selectedIDs.count) selected").font(.subheadline.weight(.semibold)); Text(picked.map(\.displayTitle).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                    Spacer(); Button("Clear") { guard model.closeEditor() else { return }; selectedIDs = []; expandedDocumentID = nil }.frame(minHeight: 44)
                }
            }
            if model.isLoading { ProgressView("Opening notebook…") }
            LazyVStack(spacing: 0) { ForEach(entries) { entry in entryRow(entry); Divider() } }
            if entries.isEmpty, !model.isLoading, model.errorText == nil { WhisperEmptyState(icon: "note.text", title: query.isEmpty ? "A little space to think" : "No matching notes", message: "Start a private note. Available recording backups appear alongside your writing.", isCard: false) }
            if archiveModel.isLoading { ProgressView("Checking recording backups…").font(.caption) }
            if let error = archiveModel.errorText { Text(error).font(.caption).foregroundStyle(.secondary); Button("Retry recordings") { refresh() }.frame(minHeight: 44) }
            if archiveModel.canLoadMore { Button("Load older recordings") { Task { await archiveModel.load(more: true) } }.frame(minHeight: 44).disabled(archiveModel.isLoading) }
            if model.errorText != nil, expandedDocumentID == nil { Button("Retry notes") { Task { await model.load() } }.frame(minHeight: 44) }
        }
    }
    private func entryRow(_ entry: WhisperNotebookEntry) -> some View {
        Button {
            if let note = entry.note { if selecting { toggle(note.id) } else { open(note.id) } }
            else if let archive = entry.archive {
                guard model.closeEditor() else { return }
                if !showFocus { backTransition.captureLocalPredecessor() }
                externalContext = nil; selectedIDs = []; expandedDocumentID = nil; mediaID = archive.recording_id; mediaAttachmentIDs = nil; mediaMeetingID = archive.snapshot.meetingId; mediaTitle = archive.title; activeArchive = archive; showFocus = true
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selecting && entry.note != nil ? (selectedIDs.contains(entry.id) ? "checkmark.circle.fill" : "circle") : entry.archive == nil && (entry.note?.recordingIds?.isEmpty ?? true) ? "doc.text" : "waveform")
                    .font(.title3).foregroundStyle(WhisperBrandGradient.rose).frame(width: 28, height: 30)
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.title).font(.headline).lineLimit(2)
                    Text(entry.preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    Text("\(String(entry.date.prefix(10)))\(meetingID != nil && entry.meetingID == meetingID ? " · Matching meeting" : "")").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, minHeight: 68, alignment: .leading).padding(.vertical, 14).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selectedIDs.contains(entry.id) ? .isSelected : [])
    }

    private var focusCanvas: some View {
        VStack(alignment: .leading, spacing: 14) {
            if selectedIDs.count > 1 {
                Text("Working with \(selectedIDs.count) notes").font(.system(.largeTitle, design: .serif))
                Text(picked.map(\.displayTitle).joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
            }
            if selectedIDs.count == 1, model.draft?.id == expandedDocumentID, model.isCurrent {
                TextField("Untitled note", text: Binding(get: { model.draft?.title ?? "" }, set: { model.edit(\.title, value: $0, maximum: 160, changesSources: false) }), axis: .vertical)
                    .font(.system(.largeTitle, design: .serif)).accessibilityLabel("Note title")
            }
            if let liveMeetingID, selectedIDs.count == 1 {
                WhisperNotebookLiveTranscriptView(meetingID: liveMeetingID, onChoose: { externalContext = $0 }).id("\(liveMeetingID):\(AccountStorage.generation)")
            }
            if selectedIDs.count == 1, model.draft?.recapCopiedAt != nil { Text("Private copy of a meeting-generated note · shared original unchanged").font(.caption).foregroundStyle(.secondary) }
            if let mediaID, model.isCurrent {
                Text("Recording sources · \(mediaTitle)\(selectedIDs.count > 1 ? " · playback only, not AI context" : "")").font(.caption).foregroundStyle(.secondary)
                WhisperNotebookRecordingSourcesView(meetingID: mediaMeetingID, recordingID: mediaID, attachmentIDs: mediaAttachmentIDs, refreshID: recordingRefreshID, onRecordingChange: { activeArchive = $0 }, onImportTranscript: expandedDocumentID == mediaID && selectedIDs.count == 1 ? { text in model.importTranscript(text, documentID: mediaID) } : nil, onAttach: expandedDocumentID == mediaID && selectedIDs.count == 1 ? { archive in
                    model.attachRecording(archive, documentID: mediaID); mediaAttachmentIDs = model.draft?.recordingIds
                } : nil, onContext: selectedIDs.count == 1 ? { externalContext = $0 } : nil)
                    .id("\(mediaID):\(AccountStorage.generation)")
            }
            if let id = expandedDocumentID, selectedIDs.count == 1 {
                if !model.documents.contains(where: { $0.id == id }) { Text("This note is no longer listed. Your open writing is kept for export or recovery; deleted notes are never recreated.").font(.caption) }
                WhisperNotebookEditorView(model: model, documentID: id, onCollapse: {
                    if let copy = model.draft, copy.id != id { open(copy.id) }
                    else if model.closeEditor() { expandedDocumentID = nil; selectedIDs = []; showFocus = false }
                }, isMeetingCanvas: true, usesSelectionJasper: true, externalContext: externalContext, onClearExternal: { externalContext = nil }).id(id)
            } else if selectedIDs.isEmpty, mediaID != nil {
                Text(mediaTitle).font(.system(.title, design: .serif))
                Text("Playback needs no note. Start writing explicitly, or create a separate note if the original was deleted.").font(.subheadline).foregroundStyle(.secondary)
                Button("Start writing for this recording") { if let activeArchive, let id = model.connectRecording(activeArchive) { open(id) } }.frame(minHeight: 44).disabled(activeArchive?.state != "ready")
                Button("Create a separate note") { create() }.frame(minHeight: 44)
            }
            if !selectedIDs.isEmpty {
                Button("Add another meeting note from archive") { if model.save() { selecting = true; showNotesArchive = true } }.font(.caption).frame(minHeight: 44).disabled(selectedIDs.count >= 8)
            }
            Group {
                WhisperNotebookQuestionsView(model: model, documents: picked, isActive: showFocus && selectedIDs.count > 1 && picked.count == selectedIDs.count).id(AccountStorage.generation).id("selection-jasper")
                    .frame(height: selectedIDs.count < 2 ? 0 : nil).clipped().opacity(selectedIDs.count < 2 ? 0 : 1).allowsHitTesting(selectedIDs.count > 1).accessibilityHidden(selectedIDs.count < 2)
            }
        }
    }
    @ViewBuilder private var recoverySection: some View {
        if model.isCurrent, !model.recoveries.isEmpty {
            DisclosureGroup("Unsaved writing found") {
                ForEach(model.recoveries) { recovery in Button("Recover: \(recovery.document.displayTitle)") { if let id = model.recover(recovery) { open(id) } }.frame(minHeight: 44) }
                Text("Recovery creates a separate copy; existing writing stays untouched.").font(.caption).foregroundStyle(.secondary)
            }.font(.subheadline)
        }
    }
    private var notebookTools: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.isSyncing ? "Syncing…" : model.syncStatus).font(.caption)
            Text("Notes save privately to your account with local recovery. Existing notes join account saving after checking other devices. Recording backup needs its original permission and browser. Nothing is sent to attendees or Jasper automatically. Wait for account confirmation before removing local copies.").font(.caption).foregroundStyle(.secondary)
            Button("Refresh private sync") { model.requestSync() }.frame(minHeight: 44)
        }
    }
    private func open(_ id: String) {
        guard model.save() else { return }
        if !showFocus { backTransition.captureLocalPredecessor() }
        model.openEditor(id)
        guard let note = model.draft, note.id == id else { return }
        externalContext = nil; expandedDocumentID = id; selectedIDs = [id]; selecting = false; showFocus = true
        mediaID = id; mediaAttachmentIDs = note.recordingIds; mediaMeetingID = note.meetingId; mediaTitle = note.displayTitle; Haptics.tap()
    }
    private func toggle(_ id: String) {
        guard model.save() else { return }
        externalContext = nil
        var next = selectedIDs
        if next.contains(id) { next.removeAll { $0 == id } }
        else { guard next.count < 8 else { model.errorText = "Choose up to eight notes."; return }; next.append(id) }
        if next.count == 1, let only = next.first { model.openEditor(only); guard model.draft?.id == only else { return }; expandedDocumentID = only
            if let note = model.draft { mediaID = note.id; mediaAttachmentIDs = note.recordingIds; mediaMeetingID = note.meetingId; mediaTitle = note.displayTitle }
        }
        else { guard model.closeEditor() else { return }; expandedDocumentID = nil }
        selectedIDs = next; Haptics.tap()
    }
    private func openRequestedNote() {
        guard !handledNote, let noteID, model.isCurrent else { return }
        if model.documents.contains(where: { $0.id == noteID }) { open(noteID); handledNote = expandedDocumentID == noteID }
        else if let archive = archiveModel.archives.first(where: { $0.recording_id == noteID }), model.closeEditor() {
            selectedIDs = []; expandedDocumentID = nil; mediaID = archive.recording_id; mediaAttachmentIDs = nil; mediaMeetingID = archive.snapshot.meetingId; mediaTitle = archive.title; activeArchive = archive; showFocus = true; handledNote = true
        }
    }
    private func create() { if let id = model.create(meetingID: liveMeetingID, title: "") { open(id) } }
    private func refresh() { recordingRefreshID = UUID(); model.requestSync(); Task { await archiveModel.load() } }
}
