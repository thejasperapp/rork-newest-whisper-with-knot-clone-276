import Foundation

nonisolated struct WhisperNotebookCloudRow: Codable, Sendable {
    let owner_id: String
    let id: String
    let revision: Int
    let operation_id: String
    let document: WhisperNotebookDocument?
    let deleted: Bool
    let updated_at: String
}
