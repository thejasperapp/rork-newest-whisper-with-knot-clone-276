import Foundation

nonisolated struct WhisperFailedChatMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let body: String
}
