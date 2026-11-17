import Foundation

nonisolated struct WhisperNotebookContext: Sendable {
    let sources: [WhisperNotebookDocument.Source]
    let label: String
}
