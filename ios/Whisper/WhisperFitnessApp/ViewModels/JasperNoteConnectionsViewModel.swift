import Foundation
import Observation

@MainActor @Observable final class JasperNoteConnectionsViewModel {
    var title: String = "My note excerpt"
    var text: String = ""
    var meetingIDs: [String] = []
    var approved: Bool = false
    var reviewed: Bool = false
    var destination: String = ""
    private(set) var notes: [WhisperNotebookDocument] = []
    private(set) var origin: WhisperNotebookDocument?
    private(set) var answer: JasperMeetingAnswer?
    private(set) var isAsking: Bool = false
    private(set) var isSaving: Bool = false
    private(set) var saved: Bool = false
    var errorText: String?
    private let owner = AccountStorage.currentUserID.lowercased()
    private let generation = AccountStorage.generation
    @ObservationIgnored private var task: Task<Void, Never>?
    private var epoch: Int = 0
    private var requestID: String?
    private var isCurrent: Bool { owner == AccountStorage.currentUserID.lowercased() && generation == AccountStorage.generation }
    var canAsk: Bool { approved && !isAsking && !isSaving && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf16.count <= 8000 && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.utf16.count <= 160 && !meetingIDs.isEmpty && meetingIDs.count <= 7 }

    func loadNotes() {
        guard isCurrent else { return }
        do { notes = try WhisperNotebookStorage.load(ownerID: owner).filter { $0.deletedAt == nil && !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }; errorText = nil }
        catch { errorText = "Saved private writing could not load. You can retry or paste an excerpt." }
    }
    func chooseNote(_ id: String) {
        invalidate()
        origin = notes.first { $0.id == id }
        if let origin { title = origin.displayTitle; text = origin.notes }
    }
    private func cancelRemote() {
        guard let id = requestID else { return }; requestID = nil
        Task {
            do { let _: [String: Bool] = try await JasperMeetingService.request("cancel", owner: owner, body: ["id": id]) }
            catch { if isCurrent { errorText = "Cancellation could not reach Jasper. Submitted work may finish; temporary results expire after 24 hours." } }
        }
    }
    func invalidate() { epoch += 1; task?.cancel(); cancelRemote(); approved = false; reviewed = false; answer = nil; saved = false; destination = "" }
    func editText(_ value: String) { invalidate(); origin = nil; text = value }
    func toggleMeeting(_ id: String) {
        guard !isSaving else { return }; invalidate()
        if meetingIDs.contains(id) { meetingIDs.removeAll { $0 == id } }
        else if meetingIDs.count < 7 { meetingIDs.append(id) }
    }
    private func checkOrigin(_ snapshot: WhisperNotebookDocument?) throws {
        guard let snapshot else { return }
        let current = try WhisperNotebookStorage.load(ownerID: owner).first { $0.id == snapshot.id && $0.deletedAt == nil }
        guard current?.revision == snapshot.revision, current?.notes == snapshot.notes else { throw WhisperNotebookError.invalidResult }
    }
    func ask() {
        guard isCurrent, canAsk else { return }
        cancelRemote()
        let id = UUID().uuidString.lowercased()
        let version = epoch, selected = meetingIDs, note = JasperMeetingAnswer.NoteContext(title: title, text: text), original = origin
        isAsking = true; errorText = nil; answer = nil; reviewed = false; saved = false
        task = Task {
            defer { isAsking = false; task = nil }
            do {
                try checkOrigin(original); try Task.checkCancellation()
                requestID = id
                let value: JasperMeetingAnswer = try await JasperMeetingService.request("ask", owner: owner, body: ["requestId": id, "question": "Find useful connections between my note and these selected meetings. Highlight related decisions, possible links and things worth clarifying.", "mode": "connections", "consent": true, "meetingIds": selected, "noteContext": ["title": note.title, "text": note.text]])
                try Task.checkCancellation(); try checkOrigin(original)
                guard isCurrent, epoch == version, value.noteContext?.text == note.text else { return }
                let ids = Set(value.sources.map(\.id))
                guard value.sources.count <= 160, value.sources.reduce(note.text.utf16.count, { $0 + $1.text.utf16.count }) <= 24000,
                      value.result.actions.isEmpty, value.result.sections.flatMap(\.items).count <= 5,
                      value.result.sections.flatMap(\.items).allSatisfy({ item in
                          guard let quote = item.noteQuote, quote.utf16.count >= 3, quote.utf16.count <= 600 else { return false }
                          return note.text.contains(quote) && !item.sourceIds.isEmpty && item.sourceIds.allSatisfy { ids.contains($0) }
                      }) else { throw WhisperNotebookError.invalidResult }
                answer = value
            } catch { if requestID == id { cancelRemote() }; if isCurrent, epoch == version, !Task.isCancelled { errorText = "The connection search could not be verified or the note changed. Review your selection and try again. \(error.localizedDescription)" } }
        }
    }
    func keep() async {
        guard isCurrent, reviewed, !isSaving, !destination.isEmpty, let answer else { return }
        isSaving = true; defer { isSaving = false }
        do {
            struct Saved: Decodable { let saved: Bool }
            let result: Saved = try await JasperMeetingService.request("keep", owner: owner, body: ["id": answer.id, "meetingId": destination])
            guard isCurrent else { return }; saved = result.saved; if saved { requestID = nil }
        } catch { if isCurrent { errorText = error.localizedDescription } }
    }
    func discard() async {
        guard isCurrent, !isSaving, let answer else { return }
        isSaving = true; defer { isSaving = false }
        do {
            let _: [String: Bool] = try await JasperMeetingService.request("clear", owner: owner, body: ["ids": [answer.id]])
            guard isCurrent else { return }; requestID = nil; self.answer = nil; reviewed = false
        } catch { if isCurrent { errorText = error.localizedDescription } }
    }
}
