import Foundation

nonisolated struct JasperMeetingAnswer: Codable, Identifiable, Sendable {
    struct Evidence: Codable, Identifiable, Sendable {
        let id: String
        let meetingId: String
        let meetingTitle: String
        let segmentId: String
        let spokenAt: String
        let speaker: String
        let text: String
        let offset: Int
        let kind: String?
        let recordingId: String?
        let position: Double?
        let timing: String?
        let revision: Int?
    }
    struct NoteContext: Codable, Sendable {
        let title: String
        let text: String
    }
    /// `kind == "knowledge"` marks Jasper's own general knowledge: uncited, labeled, never a meeting fact.
    struct Item: Codable, Sendable {
        var kind: String? = nil
        let text: String
        let sourceIds: [String]
        var noteQuote: String? = nil

        var isKnowledge: Bool { kind == "knowledge" }
    }
    struct Section: Codable, Sendable {
        let title: String
        let items: [Item]
    }
    struct Result: Codable, Sendable {
        let insufficient: Bool
        var related: Bool? = nil
        /// "evidence", "knowledge" or "mixed"; derived client-side when an older server omits it.
        var grounding: String? = nil
        /// Short suggested next questions in the user's voice; empty when the answer was insufficient.
        var followups: [String]? = nil
        let sections: [Section]
        let actions: [WhisperNotebookDocument.Proposal]
    }
    let id: String
    let question: String
    let generatedAt: String
    let scope: String
    let coverage: String
    var partialEvidence: Bool? = nil
    var noteContext: NoteContext? = nil
    let meetingId: String?
    let sources: [Evidence]
    let result: Result

    /// One meeting Jasper actually read, with its earliest cited timestamp.
    struct ReadMeeting: Identifiable, Sendable {
        let id: String
        let title: String
        let date: String
    }
    /// What Jasper read, derived from the returned sources rather than claimed by the model.
    struct Reading: Sendable {
        let passages: Int
        let meetings: [ReadMeeting]
        let notes: Int
        let hasRecording: Bool
    }

    var groundingLabel: String {
        if let grounding = result.grounding { return grounding }
        let items = result.sections.flatMap(\.items)
        let knowledge = items.filter(\.isKnowledge).count
        if knowledge == 0 { return "evidence" }
        return knowledge == items.count && result.actions.isEmpty ? "knowledge" : "mixed"
    }
    var followups: [String] { result.followups ?? [] }
    var reading: Reading {
        var meetings: [String: ReadMeeting] = [:]
        var order: [String] = []
        for source in sources {
            if let current = meetings[source.meetingId] {
                if source.spokenAt < current.date { meetings[source.meetingId] = ReadMeeting(id: source.meetingId, title: source.meetingTitle, date: source.spokenAt) }
            } else {
                meetings[source.meetingId] = ReadMeeting(id: source.meetingId, title: source.meetingTitle, date: source.spokenAt)
                order.append(source.meetingId)
            }
        }
        return Reading(passages: sources.count, meetings: order.compactMap { meetings[$0] }, notes: sources.filter { $0.kind == "summary" }.count, hasRecording: sources.contains { $0.kind == "recording" })
    }
}
