import Foundation
import Observation

@MainActor @Observable final class JasperMeetingsViewModel {
    private(set) var library: JasperMeetingLibrary?
    private(set) var isLoading: Bool = false
    private(set) var isSaving: Bool = false
    private(set) var isAsking: Bool = false
    private(set) var isScanning: Bool = false
    private(set) var answers: [JasperMeetingAnswer] = []
    private(set) var savedIDs: Set<String> = []
    var errorText: String?
    let owner = AccountStorage.currentUserID.lowercased()
    private let generation = AccountStorage.generation
    @ObservationIgnored private var askTask: Task<Void, Never>?
    var isCurrent: Bool { owner == AccountStorage.currentUserID.lowercased() && generation == AccountStorage.generation }

    func load() async {
        guard isCurrent, !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        do { let value: JasperMeetingLibrary = try await JasperMeetingService.request("library", owner: owner); guard isCurrent else { return }; library = value; errorText = nil }
        catch { if isCurrent, !Task.isCancelled { errorText = error.localizedDescription } }
    }
    @discardableResult func change(_ fields: [String: Any]) async -> Bool {
        guard isCurrent, !isSaving, let library else { return false }
        isSaving = true; defer { isSaving = false }
        do {
            var body = fields; body["revision"] = library.revision
            let value: JasperMeetingLibrary = try await JasperMeetingService.request("library", owner: owner, body: body)
            guard isCurrent else { return false }; self.library = value; errorText = nil; return true
        } catch { if isCurrent { errorText = error.localizedDescription }; return false }
    }
    /// `allowKnowledge: false` keeps an answer to meeting evidence only; scans and note connections are always evidence-only.
    func ask(_ question: String, meetingID: String?, folderID: String?, scan: Bool, recordingContext: [String: Any]? = nil, meetingIDs: [String]? = nil, noteContext: JasperMeetingAnswer.NoteContext? = nil, allowKnowledge: Bool = true) {
        guard isCurrent, !isAsking, !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, question.utf16.count <= 600 else { return }
        if answers.count >= 20 { errorText = "Keep useful answers, then clear this conversation to continue."; return }
        isAsking = true; isScanning = scan; errorText = nil
        let knowledgeAllowed = allowKnowledge && !scan && noteContext == nil
        askTask = Task {
            defer { isAsking = false; isScanning = false; askTask = nil }
            do {
                var body: [String: Any] = ["question": question, "mode": noteContext != nil ? "connections" : scan ? "scan" : "ask", "consent": true]
                if !knowledgeAllowed { body["knowledge"] = false }
                if let meetingIDs { body["meetingIds"] = meetingIDs }
                if let noteContext { body["noteContext"] = ["title": noteContext.title, "text": noteContext.text] }
                if let meetingID { body["meetingId"] = meetingID }
                if let folderID { body["folderId"] = folderID }
                if let recordingContext { body["recordingContext"] = recordingContext }
                let answer: JasperMeetingAnswer = try await JasperMeetingService.request("ask", owner: owner, body: body)
                try Task.checkCancellation(); guard isCurrent else { return }
                let ids = Set(answer.sources.map(\.id))
                let items = answer.result.sections.flatMap(\.items)
                // Knowledge items must be uncited and only appear where allowed; every other item must cite real returned sources.
                guard answer.sources.count <= 160, answer.sources.reduce(answer.noteContext?.text.utf16.count ?? 0, { $0 + $1.text.utf16.count }) <= 24000,
                      items.allSatisfy({ item in item.isKnowledge ? (knowledgeAllowed && item.sourceIds.isEmpty && item.noteQuote == nil) : (!item.sourceIds.isEmpty && item.sourceIds.allSatisfy { ids.contains($0) }) }),
                      answer.result.actions.allSatisfy({ !$0.sourceIds.isEmpty && $0.sourceIds.allSatisfy { ids.contains($0) } }) else { throw WhisperNotebookError.invalidResult }
                if let note = answer.noteContext {
                    guard answer.result.sections.flatMap(\.items).allSatisfy({ item in
                        guard let quote = item.noteQuote, quote.utf16.count >= 3, quote.utf16.count <= 600 else { return false }
                        return note.text.contains(quote)
                    }) else { throw WhisperNotebookError.invalidResult }
                }
                answers.append(answer)
            } catch { if isCurrent, !Task.isCancelled { errorText = error.localizedDescription } }
        }
    }
    func stop() { askTask?.cancel() }
    func clear() {
        guard !isAsking, isCurrent else { return }
        let ids = answers.map(\.id)
        Task {
            do { let _: [String: Bool] = try await JasperMeetingService.request("clear", owner: owner, body: ["ids": ids]); if isCurrent { answers = [] } }
            catch { if isCurrent { errorText = error.localizedDescription } }
        }
    }
    func eraseAnswers() async -> Bool {
        guard isCurrent else { return false }
        do { let _: [String: Bool] = try await JasperMeetingService.request("erase-answers", owner: owner, body: ["confirm": true]); guard isCurrent else { return false }; answers = []; savedIDs = []; return true }
        catch { if isCurrent { errorText = error.localizedDescription }; return false }
    }
    func keep(_ answer: JasperMeetingAnswer, meetingID: String) async {
        guard isCurrent, !isSaving else { return }
        isSaving = true; defer { isSaving = false }
        do {
            struct Saved: Decodable { let saved: Bool }
            let result: Saved = try await JasperMeetingService.request("keep", owner: owner, body: ["id": answer.id, "meetingId": meetingID])
            guard isCurrent, result.saved else { return }; savedIDs.insert(answer.id); errorText = nil
        } catch { if isCurrent { errorText = error.localizedDescription } }
    }
}
