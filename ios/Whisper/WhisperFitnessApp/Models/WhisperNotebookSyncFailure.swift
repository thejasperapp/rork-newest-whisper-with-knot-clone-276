import Foundation

/// Sanitized account-save failure, with no database details or private writing.
nonisolated struct WhisperNotebookSyncFailure: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}
