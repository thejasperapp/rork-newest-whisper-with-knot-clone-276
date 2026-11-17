import Foundation

nonisolated struct WhisperSidekickTurn: Identifiable, Sendable {
    let id: UUID
    let question: String
    let scope: String
    let result: WhisperNotebookDocument.Result
    var isKept: Bool = false
    var noteID: String? = nil
    var isEnhancement: Bool = false

    var writing: String {
        let sections = result.sections.map { section in
            "\(section.title)\n\(section.items.map { "\($0.text) [\($0.sourceIds.joined(separator: ", "))]" }.joined(separator: "\n\n"))"
        }.joined(separator: "\n\n")
        let actions = result.actions.map { "\($0.title) — \($0.owner.isEmpty ? "Unassigned" : $0.owner) · \($0.when.isEmpty ? "No date stated" : $0.when) [\($0.sourceIds.joined(separator: ", "))]" }.joined(separator: "\n")
        return sections + (actions.isEmpty ? "" : "\n\nSuggested follow-ups\n\(actions)")
    }
}
