import Foundation
import Observation
import Supabase

@MainActor @Observable
final class WhisperMeetingSidekickViewModel {
    let notebook = WhisperNotebookViewModel()
    let archive = WhisperNotebookArchiveViewModel()
    var tab: String = "Notes"
    var range: String = "all"
    var question: String = ""
    var filesOpen: Bool = false
    var includeWriting: Bool = true
    var selectedSpeech: Set<String> = []
    private(set) var files: [WhisperSidekickFile] = []
    private(set) var rows: [WhisperNotebookSpeech] = []
    private(set) var isComplete: Bool = false
    private(set) var turns: [WhisperSidekickTurn] = []
    private(set) var isGenerating: Bool = false
    private(set) var isReadingFile: Bool = false
    var errorText: String?
    var transcriptError: String?
    var notice: String?
    var pending: Pending?
    private var approved: Bool = false
    private var loaded: Bool = false
    private var isLoadingLibrary: Bool = false
    private let owner = AccountStorage.currentUserID.lowercased()
    private let generation = AccountStorage.generation
    private var operation = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?

    init(isArchived: Bool = false) {
        if isArchived { tab = "Ask Jasper"; range = "all" }
    }

    struct Pending {
        let question: String
        let workflow: WhisperNotebookWorkflow
        let sources: [WhisperNotebookDocument.Source]
        let scope: String
        let meetingID: String
        let title: String
        let noteID: String?
        let writingRevision: Int
    }

    var isCurrent: Bool {
        AuthenticationService.shared.isSignedIn && owner == AccountStorage.currentUserID.lowercased() && generation == AccountStorage.generation
        && SupabaseService.shared.client.auth.currentUser?.id.uuidString.lowercased() == owner
    }

    private func check() throws {
        try Task.checkCancellation()
        guard isCurrent else { throw WhisperNotebookError.accountChanged }
    }

    func load() async {
        guard !loaded, !isLoadingLibrary, isCurrent else { return }
        isLoadingLibrary = true
        defer { isLoadingLibrary = false }
        if notebook.draft == nil { await notebook.load() }
        guard !Task.isCancelled, isCurrent else { return }
        await archive.load(includeWithoutSummary: true)
        guard !Task.isCancelled, isCurrent else { return }
        loaded = notebook.errorText == nil && archive.errorText == nil
    }

    func refresh(meetingID: String) async {
        do {
            let speech = try await readSpeech(meetingID: meetingID)
            try check()
            rows = Array(speech.prefix(200).reversed()); isComplete = speech.count <= 200; transcriptError = nil
        } catch {
            guard isCurrent, !Task.isCancelled else { rows = []; return }
            transcriptError = "Saved speech is delayed or unavailable. Reconnect and retry; your call stays connected."
        }
    }

    private func readSpeech(meetingID: String) async throws -> [WhisperNotebookSpeech] {
        try check()
        let session = try await SupabaseService.shared.client.auth.session
        try check()
        guard session.user.id.uuidString.lowercased() == owner else { throw WhisperNotebookError.accountChanged }
        let speech: [WhisperNotebookSpeech] = try await SupabaseService.shared.client.from("whisper_meeting_transcripts").select("id,meeting_id,username,text,spoken_at").eq("meeting_id", value: meetingID).order("spoken_at", ascending: false).order("id", ascending: false).limit(201).execute().value
        try check()
        guard speech.allSatisfy({ $0.meeting_id.lowercased() == meetingID.lowercased() }) else { throw WhisperNotebookError.invalidResult }
        return speech
    }

    func openWriting(meetingID: String, title: String) {
        guard isCurrent else { return }
        if let note = notebook.documents.first(where: { $0.meetingId == meetingID && $0.isMeetingWriting == true }) ?? notebook.documents.first(where: { $0.meetingId == meetingID && $0.enhancement == nil }) { notebook.openEditor(note.id) }
        else if let id = notebook.create(meetingID: meetingID, title: title, isMeetingWriting: true) { notebook.openEditor(id) }
    }

    func addNote(_ note: WhisperNotebookDocument) {
        guard isCurrent, note.ownerId == owner, note.deletedAt == nil else { return }
        do { try add(.note(note)) } catch { errorText = error.localizedDescription }
    }

    func addMeeting(_ meeting: WhisperMeetingRow) async {
        guard !isReadingFile, isCurrent else { return }
        isReadingFile = true
        defer { isReadingFile = false }
        do {
            let speech = try await readSpeech(meetingID: meeting.id)
            guard speech.count <= 200 else { errorText = "This transcript exceeds 200 passages. Choose a shorter saved excerpt from Notebook. Nothing was shortened or sent."; return }
            try add(.speech(meetingID: meeting.id, title: meeting.title, rows: Array(speech.reversed()), label: "selected past transcript", owner: owner))
        } catch { if isCurrent { errorText = error.localizedDescription } }
    }

    private func add(_ file: WhisperSidekickFile) throws {
        try check()
        guard !files.contains(where: { $0.id == file.id }) else { return }
        guard files.count < 6 else { throw WhisperNotebookError.tooLong }
        files.append(file); pending = nil
    }

    func removeFile(_ id: String) { files.removeAll { $0.id == id }; pending = nil }

    func prepare(_ text: String, workflow: WhisperNotebookWorkflow = .ask, meetingID: String, title: String) {
        guard !isGenerating, isCurrent else { return }
        errorText = nil; notice = nil; tab = "Ask Jasper"
        do {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf16.count <= 600 else { throw WhisperNotebookError.tooLong }
            guard turns.count < 12 else { errorText = "Keep useful answers, then clear the conversation to continue."; return }
            guard notebook.save() else { errorText = "Resolve the writing save error before asking Jasper."; return }
            var context: [WhisperSidekickFile] = []
            if range != "none" {
                guard transcriptError == nil else { errorText = "Refresh saved speech, or choose Writing & files only."; return }
                let boundary = Date().addingTimeInterval(-300)
                func spokenDate(_ value: String) -> Date {
                    let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) ?? .distantPast
                }
                guard range != "all" || isComplete else { errorText = "Earlier speech is outside this window. Choose recent or selected speech."; return }
                guard range != "recent" || isComplete || spokenDate(rows.first?.spoken_at ?? "") <= boundary else { errorText = "Five minutes exceeds the loaded window. Select specific passages instead."; return }
                guard range != "selected" || selectedSpeech.isSubset(of: Set(rows.map(\.id))) else { errorText = "Selected speech left the live window. Select it again."; return }
                let chosen = rows.filter { range == "all" || (range == "recent" ? spokenDate($0.spoken_at) >= boundary : selectedSpeech.contains($0.id)) }
                guard !chosen.isEmpty else { errorText = "No confirmed speech in this range yet. Choose Writing & files only to work with your notes, or wait for speech."; return }
                context.append(try .speech(meetingID: meetingID, title: title, rows: chosen, label: range == "recent" ? "last 5 minutes, saved speech" : range == "all" ? "transcript so far" : "selected speech", owner: owner))
            }
            if includeWriting, let draft = notebook.draft, !draft.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft.transcript.isEmpty { context.append(try .note(draft)) }
            context += files
            let request = Pending(question: text, workflow: workflow, sources: try WhisperSidekickFile.combine(context), scope: context.map(\.title).joined(separator: " · "), meetingID: meetingID, title: title, noteID: notebook.draft?.id, writingRevision: notebook.draft?.revision ?? 0)
            tab = "Ask Jasper"
            if approved { send(request) } else { pending = request }
        } catch { errorText = error.localizedDescription }
    }

    func approve() { guard let pending else { return }; approved = true; send(pending) }

    private func send(_ request: Pending) {
        guard !isGenerating, isCurrent else { return }
        pending = nil; isGenerating = true; let token = UUID(); operation = token
        task = Task { [weak self] in
            guard let self else { return }
            defer { if operation == token { isGenerating = false; task = nil } }
            do {
                try check()
                let result = try await WhisperNotebookIntelligence.generate(document: .blank(ownerID: owner, meetingID: request.meetingID, title: request.title), question: request.question, toolkitURL: Config.allValues["EXPO_PUBLIC_TOOLKIT_URL"] ?? "https://toolkit.rork.com", secret: Config.allValues["EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY"] ?? "", selectedSources: request.sources, workflow: request.workflow)
                try check(); guard operation == token else { return }
                let frozen = WhisperNotebookDocument.Result(insufficient: result.insufficient, sections: result.sections, actions: result.actions, revision: request.writingRevision, generatedAt: result.generatedAt, sources: result.sources)
                turns.append(.init(id: UUID(), question: request.question, scope: request.scope, result: frozen, noteID: request.noteID, isEnhancement: request.workflow == .enhance)); if question.trimmingCharacters(in: .whitespacesAndNewlines) == request.question.trimmingCharacters(in: .whitespacesAndNewlines) { question = "" }
            } catch { if isCurrent, operation == token, !Task.isCancelled { errorText = "Jasper couldn't finish. Your writing is unchanged; try again." } }
        }
    }

    func keepWithWriting(_ turn: WhisperSidekickTurn) {
        guard isCurrent, let id = turn.noteID, notebook.draft?.id == id, notebook.save() else { errorText = "Reopen the original writing and finish saving before keeping this enhancement."; return }
        notebook.retainInlineDraft(turn.result, isMeetingWriting: true)
        if notebook.save() { tab = "Notes" }
    }

    func cancel() { operation = UUID(); task?.cancel(); task = nil; isGenerating = false }
    func clearConversation() { cancel(); turns = []; pending = nil }

    func keep(_ turn: WhisperSidekickTurn, writing: String, meetingID: String, title: String) -> Bool {
        do {
            try check()
            guard !writing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, writing.utf16.count <= 60000 else { throw WhisperNotebookError.tooLong }
            guard try WhisperNotebookStorage.load(ownerID: owner).count < 200 else { throw WhisperNotebookError.limit }
            guard !turns.contains(where: { $0.id == turn.id && $0.isKept }) else { return true }
            var note = WhisperNotebookDocument.blank(ownerID: owner, meetingID: meetingID, title: "\(title) · Jasper")
            note.notes = writing; note.enhancement = turn.result
            _ = try WhisperNotebookStorage.save(note)
            if let index = turns.firstIndex(where: { $0.id == turn.id }) { turns[index].isKept = true }
            notebook.requestSync()
            notice = "Kept privately in Notebook. Account saving queued; nothing sent to attendees."
            return true
        } catch { errorText = error.localizedDescription; return false }
    }
}
