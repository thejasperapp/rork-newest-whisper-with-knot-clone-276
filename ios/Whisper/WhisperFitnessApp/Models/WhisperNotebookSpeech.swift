import Foundation

nonisolated struct WhisperNotebookSpeech: Decodable, Identifiable, Sendable {
    let id: String
    let meeting_id: String
    let username: String
    let text: String
    let spoken_at: String
}
