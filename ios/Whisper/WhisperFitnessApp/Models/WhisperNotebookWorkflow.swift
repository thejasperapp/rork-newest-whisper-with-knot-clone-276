import Foundation

/// Explicit task semantics shared by one-note and multi-note Jasper requests.
nonisolated enum WhisperNotebookWorkflow: String, CaseIterable, Identifiable, Sendable {
    case ask, enhance, summarize, compare, followups, highlights
    var id: String { rawValue }
    var title: String {
        switch self {
        case .highlights: "Find key points"
        case .ask: "Ask"
        case .enhance: "Enhance"
        case .summarize: "Summarize"
        case .compare: "Compare"
        case .followups: "Follow-ups"
        }
    }
    var instruction: String {
        switch self {
        case .highlights: "Suggest up to 5 key passages. Each item text must be a VERBATIM continuous quote from exactly one cited source. Do not paraphrase or add quotation marks. Return no actions."
        case .ask: "Answer the question in an Answer section. Return no actions."
        case .enhance: "Enhance selected writing without replacing it. Organize supported decisions and open questions; distinguish proposals from decisions."
        case .summarize: "Create a combined brief across ALL selected notes. Identify themes, decisions and unresolved questions. Return no actions. Do not invent agreement."
        case .compare: "Compare ALL selected notes: agreements, conflicts, changes and unresolved questions. Identify notes by their M source prefix. Do not infer chronology or consensus without evidence. Return no actions."
        case .followups: "Propose source-supported action items in actions. Draft a concise follow-up message in a Follow-up draft section, with cited sentences. Do not claim anything was sent or assign owners or timing absent from sources."
        }
    }
    static func writing(_ result: WhisperNotebookDocument.Result) -> String {
        result.sections.map { section in
            section.title + "\n" + section.items.map { "\($0.text) [\($0.sourceIds.joined(separator: ", "))]" }.joined(separator: "\n\n")
        }.joined(separator: "\n\n")
    }
    static func brief(owner: String, documents: [WhisperNotebookDocument], result: WhisperNotebookDocument.Result, title: String, writing: String) -> WhisperNotebookDocument {
        var note = WhisperNotebookDocument.blank(ownerID: owner, title: title)
        let references = documents.enumerated().map { index, document in
            "M\(index + 1): \(document.displayTitle) · note \(document.id) · saved revision \(document.storageRevision)"
        }.joined(separator: "\n")
        let passages = result.sources.map { "[\($0.id)] \($0.text)" }.joined(separator: "\n\n")
        note.notes = "\(writing)\n\nSource notes (snapshot)\n\(references)\n\nSupplied passages\n\(passages)"
        note.enhancement = .init(insufficient: result.insufficient, sections: result.sections, actions: result.actions, revision: 0, generatedAt: result.generatedAt, sources: result.sources)
        return note
    }
}
