import Foundation

nonisolated struct WhisperPendingSpeech: Codable, Identifiable, Sendable {
    let id: String
    let meeting_id: String
    let user_id: String
    let username: String
    let text: String
    let spoken_at: String
}
