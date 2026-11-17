import Foundation

nonisolated struct WhisperPushGroupMute: Decodable, Sendable {
    let group_id: String
    let muted: Bool
}
