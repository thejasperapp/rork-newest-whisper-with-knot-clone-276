import Foundation
import Observation
import Supabase

@MainActor @Observable
final class WhisperNotebookViewModel {
    private(set) var documents: [WhisperNotebookDocument] = []
    private(set) var recoveries: [WhisperNotebookDocument.Recovery] = []
    private(set) var draft: WhisperNotebookDocument?
    private(set) var answer: WhisperNotebookDocument.Result?
    private(set) var isLoading: Bool = false
    private(set) var isGenerating: Bool = false
    private(set) var hasUnsavedChanges: Bool = false
    var errorText: String?
    var saveError: String?
    private(set) var syncStatus: String = "Checking account saves…"
    private(set) var syncError: String?
    private(set) var isSyncing: Bool = false
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    private var syncToken: UUID = UUID()
    private var syncRequested: Bool = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var generationTask: Task<Void, Never>?
    private var ownerID: String = ""
    private var accountGeneration: UUID = UUID()
    private var operation: UUID = UUID()
    private let editorID: UUID = UUID()

    var isCurrent: Bool {
        AuthenticationService.shared.isSignedIn && ownerID == AccountStorage.currentUserID.lowercased()
            && accountGeneration == AccountStorage.generation
            && SupabaseService.shared.client.auth.currentUser?.id.uuidString.lowercased() == ownerID
    }

    func load() async {
        cancelGeneration()
        syncTask?.cancel(); syncToken = UUID(); isSyncing = false; syncRequested = false
        saveTask?.cancel()
        if hasUnsavedChanges, let draft {
            do { try WhisperNotebookStorage.retainRecovery(draft, editorID: editorID) }
            catch {
                documents = []; recoveries = []; answer = nil
                errorText = "Couldn't preserve unsaved writing. Keep Notebook open and retry."
                return
            }
        }
        WhisperNotebookSyncService.protect(editor: editorID, owner: ownerID, id: nil)
        documents = []; recoveries = []; draft = nil; answer = nil; errorText = nil; saveError = nil; hasUnsavedChanges = false
        ownerID = AccountStorage.currentUserID.lowercased()
        accountGeneration = AccountStorage.generation
        guard isCurrent else { errorText = WhisperNotebookError.accountChanged.localizedDescription; return }
        let owner = ownerID
        let token = accountGeneration
        isLoading = true
        defer { if token == accountGeneration { isLoading = false } }
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                (try WhisperNotebookStorage.load(ownerID: owner), try WhisperNotebookStorage.recoveries(ownerID: owner))
            }.value
            guard isCurrent, token == accountGeneration, !Task.isCancelled else { return }
            documents = loaded.0
            recoveries = loaded.1
            requestSync()
        } catch {
            guard isCurrent, token == accountGeneration else { return }
            errorText = WhisperNotebookError.storage.localizedDescription
        }
    }

    func create(meetingID: String?, title: String, template: WhisperNotebookTemplate = .general, isMeetingWriting: Bool = false) -> String? {
        guard isCurrent, !isLoading, documents.count < 200 else { errorText = WhisperNotebookError.limit.localizedDescription; return nil }
        guard save() else { return nil }
        do {
            var entry = WhisperNotebookDocument.blank(ownerID: ownerID, meetingID: meetingID, title: title)
            entry.templateId = template.rawValue
            entry.isMeetingWriting = isMeetingWriting
            let saved = try WhisperNotebookStorage.save(entry)
            documents.insert(saved, at: 0)
            select(saved.id)
            requestSync()
            return saved.id
        } catch { errorText = WhisperNotebookError.storage.localizedDescription; return nil }
    }

    func openEditor(_ id: String) {
        guard isCurrent else { return }
        select(id)
        guard draft?.id == id else { return }
        WhisperNotebookSyncService.protect(editor: editorID, owner: ownerID, id: id)
    }

    @discardableResult func closeEditor(ifID id: String? = nil) -> Bool {
        if let id, draft?.id != id { return true }
        guard save() else { return false }
        cancelGeneration()
        WhisperNotebookSyncService.protect(editor: editorID, owner: ownerID, id: nil)
        draft = nil; answer = nil
        requestSync()
        return true
    }

    func connectRecording(_ archive: WhisperRecordingArchive) -> String? {
        guard isCurrent, archive.owner_id == ownerID, save() else { return nil }
        do {
            let note = try WhisperNotebookStorage.recordingNote(archive)
            if let index = documents.firstIndex(where: { $0.id == note.id }) { documents[index] = note }
            else { documents.insert(note, at: 0) }
            return note.id
        } catch {
            errorText = "The recording is kept, but its note couldn't open. A deleted note cannot be recreated automatically. Check storage, or create a separate note."
            return nil
        }
    }

    /// Explicit archive selection creates one private snapshot; subsequent uses preserve its edits.
    func useArchivedMeeting(_ meeting: WhisperMeetingRow, recording: WhisperRecordingArchive?) async -> String? {
        guard isCurrent, !isLoading, save() else { return nil }
        let owner = ownerID, generation = accountGeneration, id = meeting.id.lowercased()
        let check: @MainActor () throws -> Void = {
            try Task.checkCancellation()
            guard self.isCurrent, self.ownerID == owner, self.accountGeneration == generation else { throw WhisperNotebookError.accountChanged }
        }
        do {
            if try !WhisperNotebookStorage.load(ownerID: owner, includeDeleted: true).contains(where: { $0.id == id }) {
                let remote: [WhisperNotebookCloudRow] = try await SupabaseService.shared.client.from("whisper_private_notebooks").select().eq("owner_id", value: owner).eq("id", value: id).limit(1).execute().value
                try check()
                if let row = remote.first {
                    guard row.owner_id == owner, row.id == id else { throw WhisperNotebookError.accountChanged }
                    if try !WhisperNotebookStorage.load(ownerID: owner, includeDeleted: true).contains(where: { $0.id == id }) { _ = try WhisperNotebookStorage.applyCloud(row) }
                }
            }
            try check()
            if let existing = try WhisperNotebookStorage.load(ownerID: owner, includeDeleted: true).first(where: { $0.id == id }) {
                guard existing.deletedAt == nil else { errorText = "Your private copy was deleted. The archived original and recordings are still available; create a separate note for new writing."; return nil }
                guard existing.meetingId == meeting.id else { throw WhisperNotebookError.conflict }
                if let index = documents.firstIndex(where: { $0.id == id }) { documents[index] = existing } else { documents.insert(existing, at: 0) }
                return id
            }
            guard let summary = meeting.summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, summary.utf16.count <= 60000 else { throw WhisperNotebookError.limit }
            var note = WhisperNotebookDocument.blank(ownerID: owner, meetingID: meeting.id, title: meeting.title, id: id)
            note.notes = summary; note.revision = 1; note.recapCopiedAt = Date().ISO8601Format(); note.recordingIds = []
            if let recording {
                guard recording.isValid, recording.owner_id == owner, recording.snapshot.meetingId == meeting.id else { throw WhisperNotebookError.storage }
                note.recordingIds = [recording.recording_id]
            }
            let saved = try WhisperNotebookStorage.save(note)
            documents.insert(saved, at: 0)
            return saved.id
        } catch {
            guard isCurrent, generation == accountGeneration else { return nil }
            errorText = "Couldn't open a private copy. Check your connection and note storage, then retry. The archived original is unchanged."
            return nil
        }
    }

    func attachRecording(_ archive: WhisperRecordingArchive, documentID: String) {
        guard isCurrent, archive.isValid, archive.owner_id == ownerID, draft?.id == documentID, draft?.meetingId == archive.snapshot.meetingId, save() else { return }
        var ids = draft?.recordingIds ?? []
        if !ids.contains(archive.recording_id) { ids.append(archive.recording_id) }
        guard ids.count <= 30 else { errorText = "Attach up to 30 recordings to a note."; return }
        draft?.recordingIds = ids
        changed(); _ = save()
    }

    func importTranscript(_ text: String, documentID: String) {
        guard isCurrent, draft?.id == documentID else { return }
        guard draft?.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true else {
            errorText = "This note already has a transcript. Your existing text was kept."; return
        }
        guard text.utf16.count <= 60000 else { errorText = WhisperNotebookError.limit.localizedDescription; return }
        edit(\.transcript, value: text, maximum: 60000)
    }

    func enableSync() {
        guard isCurrent, draft != nil else { return }
        draft?.syncEnabled = true
        changed()
        if save() { requestSync() }
    }

    func requestSync() {
        guard isCurrent else { return }
        guard !isSyncing else { syncRequested = true; return }
        syncRequested = false
        let owner = ownerID, generation = accountGeneration, token = UUID()
        syncToken = token; isSyncing = true; syncError = nil
        syncTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if syncToken == token {
                    isSyncing = false; syncTask = nil
                    refreshSaveMetadata()
                    if syncRequested { syncRequested = false; requestSync() }
                }
            }
            let check: @MainActor () throws -> Void = {
                guard self.isCurrent, self.ownerID == owner, self.accountGeneration == generation, self.syncToken == token, !Task.isCancelled else { throw WhisperNotebookError.accountChanged }
            }
            do {
                let status = try await WhisperNotebookSyncService.sync(owner: owner, assertCurrent: check)
                try check()
                syncStatus = status
                refreshSaveMetadata()
            } catch {
                guard (try? check()) != nil else { return }
                syncError = WhisperNotebookSyncService.message(for: error)
                syncStatus = syncError ?? "Account save needs attention"
            }
        }
    }

    /// Refresh acknowledgment metadata only; never replace live writing or move its cursor.
    func refreshSaveMetadata() {
        guard isCurrent else { return }
        do {
            documents = try WhisperNotebookStorage.load(ownerID: ownerID)
            recoveries = try WhisperNotebookStorage.recoveries(ownerID: ownerID)
            if let current = draft, let stored = documents.first(where: { $0.id == current.id }), current.storageRevision == stored.storageRevision {
                draft?.cloudRevision = stored.cloudRevision
                draft?.syncedStorageRevision = stored.syncedStorageRevision
                draft?.syncEnabled = stored.syncEnabled
            }
        } catch { errorText = "Couldn't refresh saved notes. Your open writing is unchanged." }
    }

    func select(_ id: String) {
        guard isCurrent else { return }
        if draft?.id == id { return }
        guard save() else { return }
        cancelGeneration()
        draft = documents.first { $0.id == id }
        answer = nil; saveError = nil
    }

    func edit(_ key: WritableKeyPath<WhisperNotebookDocument, String>, value: String, maximum: Int, changesSources: Bool = true) {
        guard isCurrent, draft != nil else { return }
        guard value.utf16.count <= maximum else { errorText = "That input is too long (maximum \(maximum) characters). Nothing was pasted; split it into smaller entries."; return }
        if let current = draft, key == \.notes || key == \.transcript {
            let kind = key == \.notes ? "notes" : "transcript"
            draft?.highlights = WhisperNotebookHighlight.rebase(current.highlights ?? [], kind: kind, before: current[keyPath: key], after: value, revision: current.revision + 1)
        }
        draft?[keyPath: key] = value
        if changesSources { draft?.revision += 1 }
        changed()
    }

    private func changed() {
        hasUnsavedChanges = true
        saveError = nil
        if let draft {
            do { try WhisperNotebookStorage.retainRecovery(draft, editorID: editorID) }
            catch { saveError = "Draft recovery is unavailable. Keep this note open until it is saved, or export a copy." }
        }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
            self?.save()
        }
    }

    @discardableResult func save() -> Bool {
        saveTask?.cancel()
        guard hasUnsavedChanges else { return true }
        guard isCurrent, let draft else { saveError = WhisperNotebookError.accountChanged.localizedDescription; return false }
        do {
            let saved = try WhisperNotebookStorage.save(draft)
            self.draft = saved
            if let index = documents.firstIndex(where: { $0.id == saved.id }) { documents[index] = saved }
            else { documents.insert(saved, at: 0) }
            hasUnsavedChanges = false; saveError = nil
            try? WhisperNotebookStorage.clearRecovery(ownerID: ownerID, key: "\(editorID.uuidString)-\(saved.id)")
            if saved.syncEnabled == true { requestSync() }
            return true
        } catch {
            saveError = (error as? WhisperNotebookError)?.localizedDescription ?? WhisperNotebookError.storage.localizedDescription
            return false
        }
    }

    @discardableResult func saveAsCopy() -> Bool {
        guard isCurrent, let draft, documents.count < 200 else { return false }
        do {
            let copy = try WhisperNotebookStorage.save(draft.newCopy(prefix: "Copy · "))
            try? WhisperNotebookStorage.clearRecovery(ownerID: ownerID, key: "\(editorID.uuidString)-\(draft.id)")
            saveTask?.cancel(); cancelGeneration()
            self.draft = copy; documents.insert(copy, at: 0)
            hasUnsavedChanges = false; saveError = nil
            requestSync()
            return true
        } catch { saveError = WhisperNotebookError.storage.localizedDescription; return false }
    }

    func recover(_ recovery: WhisperNotebookDocument.Recovery) -> String? {
        guard isCurrent, recovery.document.ownerId == ownerID, documents.count < 200, save() else { return nil }
        do {
            let latest = try WhisperNotebookStorage.recoveries(ownerID: ownerID).first { $0.id == recovery.id } ?? recovery
            let copy = try WhisperNotebookStorage.save(latest.document.newCopy(prefix: "Recovered · "))
            // The originating editor may still update this recovery; never erase its safety copy.
            recoveries = try WhisperNotebookStorage.recoveries(ownerID: ownerID)
            documents.insert(copy, at: 0); select(copy.id)
            requestSync()
            return copy.id
        } catch { errorText = WhisperNotebookError.storage.localizedDescription; return nil }
    }

    func delete(_ document: WhisperNotebookDocument) {
        guard isCurrent, document.ownerId == ownerID else { return }
        do {
            try WhisperNotebookStorage.delete(document)
            documents.removeAll { $0.id == document.id }
            requestSync()
            if draft?.id == document.id {
                WhisperNotebookSyncService.protect(editor: editorID, owner: ownerID, id: nil)
                saveTask?.cancel(); cancelGeneration(); draft = nil; hasUnsavedChanges = false
            }
        } catch { errorText = (error as? WhisperNotebookError)?.localizedDescription ?? WhisperNotebookError.storage.localizedDescription }
    }

    func generate(question: String? = nil, selectedSources: [WhisperNotebookDocument.Source]? = nil, workflow: WhisperNotebookWorkflow? = nil, previewOnly: Bool = false, frozen: WhisperNotebookDocument? = nil) {
        guard isCurrent, !isGenerating, let snapshot = frozen ?? draft, snapshot.id == draft?.id, snapshot.ownerId == ownerID else { return }
        guard (question?.utf16.count ?? 0) <= 600 else { errorText = "Use up to 600 characters for your question."; return }
        do { _ = try selectedSources ?? snapshot.sources() } catch { errorText = error.localizedDescription; return }
        guard save() else { return }
        errorText = nil; answer = nil
        let token = UUID()
        operation = token
        isGenerating = true
        generationTask = Task { [weak self] in
            guard let self else { return }
            defer { if operation == token { isGenerating = false; generationTask = nil } }
            do {
                let session = try await SupabaseService.shared.client.auth.session
                guard isCurrent, operation == token, session.user.id.uuidString.lowercased() == ownerID else { return }
                let result = try await WhisperNotebookIntelligence.generate(document: snapshot, question: question, toolkitURL: Config.allValues["EXPO_PUBLIC_TOOLKIT_URL"] ?? "https://toolkit.rork.com", secret: Config.allValues["EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY"] ?? "", selectedSources: selectedSources, workflow: workflow)
                guard isCurrent, operation == token, draft?.id == snapshot.id else { return }
                if previewOnly || question != nil { answer = result } else { draft?.enhancement = result; changed() }
            } catch {
                guard isCurrent, operation == token, !Task.isCancelled else { return }
                errorText = (error as? WhisperNotebookError)?.localizedDescription ?? WhisperNotebookError.unavailable.localizedDescription
            }
        }
    }

    func retainInlineDraft(_ result: WhisperNotebookDocument.Result?, isMeetingWriting: Bool = false) {
        guard isCurrent, draft != nil else { return }
        draft?.enhancement = result
        if isMeetingWriting { draft?.isMeetingWriting = true }
        changed()
    }

    func retainHighlight(_ highlight: WhisperNotebookHighlight) {
        guard isCurrent, let draft, highlight.isValid, highlight.revision == draft.revision,
              highlight.matches(highlight.kind == "notes" ? draft.notes : draft.transcript) else { errorText = "Select this passage again; the writing changed or the highlight exceeds 1,200 characters."; return }
        let existing = draft.highlights ?? []
        guard existing.count < 100 else { errorText = "Keep up to 100 highlights per note."; return }
        guard !existing.contains(where: { !$0.stale && $0.kind == highlight.kind && $0.start == highlight.start && $0.end == highlight.end }) else { return }
        self.draft?.highlights = existing + [highlight]; changed(); Haptics.tap()
    }

    func removeHighlight(_ id: String) {
        guard isCurrent else { return }
        draft?.highlights?.removeAll { $0.id == id }; changed()
    }

    func cancelGeneration() {
        operation = UUID(); generationTask?.cancel(); generationTask = nil; isGenerating = false
    }

    func track(_ proposal: WhisperNotebookDocument.Proposal, sources: [WhisperNotebookDocument.Source]) {
        guard isCurrent, let draft, draft.commitments.count < 100 else { return }
        let title = proposal.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        guard !draft.commitments.contains(where: { $0.title.lowercased() == title.lowercased() }) else { errorText = "That follow-up is already tracked."; return }
        self.draft?.commitments.append(.init(id: UUID().uuidString.lowercased(), title: String(title.prefix(300)), owner: String(proposal.owner.prefix(80)), when: String(proposal.when.prefix(80)), done: false, sources: sources.filter { proposal.sourceIds.contains($0.id) }))
        changed()
    }

    /// Saves reviewed output separately and never mutates its source notes.
    @discardableResult func saveBrief(documents snapshots: [WhisperNotebookDocument], result: WhisperNotebookDocument.Result, title: String, writing: String) -> Bool {
        guard isCurrent, save(), !writing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        do {
            guard snapshots.allSatisfy({ $0.ownerId == ownerID }) else { throw WhisperNotebookError.accountChanged }
            let note = WhisperNotebookWorkflow.brief(owner: ownerID, documents: snapshots, result: result, title: title, writing: writing)
            let saved = try WhisperNotebookStorage.save(note)
            documents.insert(saved, at: 0)
            return true
        } catch { errorText = error.localizedDescription; return false }
    }

    @discardableResult func keepEnhancement(_ result: WhisperNotebookDocument.Result, snapshots: [WhisperNotebookDocument]) -> Bool {
        guard isCurrent, snapshots.count == 1, save(), let snapshot = snapshots.first else { return false }
        do {
            try verifySelection(snapshots)
            guard var target = try WhisperNotebookStorage.load(ownerID: ownerID).first(where: { $0.id == snapshot.id }) else { throw WhisperNotebookError.conflict }
            target.enhancement = result
            let saved = try WhisperNotebookStorage.save(target)
            if let index = documents.firstIndex(where: { $0.id == saved.id }) { documents[index] = saved }
            if draft?.id == saved.id { draft = saved }
            if saved.syncEnabled == true { requestSync() }
            return true
        } catch { errorText = error.localizedDescription; return false }
    }

    @discardableResult func trackSelected(_ proposal: WhisperNotebookDocument.Proposal, result: WhisperNotebookDocument.Result, destination: String, snapshots: [WhisperNotebookDocument]) -> Bool {
        guard isCurrent, save() else { return false }
        do {
            try verifySelection(snapshots)
            guard snapshots.contains(where: { $0.id == destination }), var target = try WhisperNotebookStorage.load(ownerID: ownerID).first(where: { $0.id == destination }), target.commitments.count < 100 else { throw WhisperNotebookError.limit }
            let title = proposal.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count <= 300, proposal.owner.count <= 80, proposal.when.count <= 80 else { throw WhisperNotebookError.limit }
            guard !target.commitments.contains(where: { $0.title.lowercased() == title.lowercased() }) else { errorText = "That follow-up is already tracked."; return false }
            target.commitments.append(.init(id: UUID().uuidString.lowercased(), title: title, owner: proposal.owner, when: proposal.when, done: false, sources: result.sources.filter { proposal.sourceIds.contains($0.id) }))
            let saved = try WhisperNotebookStorage.save(target)
            if let index = documents.firstIndex(where: { $0.id == saved.id }) { documents[index] = saved }
            if draft?.id == saved.id { draft = saved }
            if saved.syncEnabled == true { requestSync() }
            return true
        } catch { errorText = error.localizedDescription; return false }
    }

    private func verifySelection(_ snapshots: [WhisperNotebookDocument]) throws {
        guard isCurrent, !snapshots.isEmpty, snapshots.count <= 8 else { throw WhisperNotebookError.accountChanged }
        let current = try WhisperNotebookStorage.load(ownerID: ownerID)
        guard snapshots.allSatisfy({ snapshot in snapshot.ownerId == ownerID && current.contains { $0.id == snapshot.id && $0.storageRevision == snapshot.storageRevision } }) else { throw WhisperNotebookError.conflict }
    }

    func toggleCommitment(_ id: String) {
        guard isCurrent, let index = draft?.commitments.firstIndex(where: { $0.id == id }) else { return }
        draft?.commitments[index].done.toggle()
        changed()
    }
}
