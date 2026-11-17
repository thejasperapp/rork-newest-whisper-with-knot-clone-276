import Foundation

/// A committed history decoration, not an action or delivery receipt.
nonisolated struct WhisperKnotReaction: Decodable, Sendable {
    let messageID: UUID
    let emoji: String
    let revision: Int
    let recordedAt: String

    var date: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: recordedAt) ?? ISO8601DateFormatter().date(from: recordedAt)
    }
    var valid: Bool {
        revision > 0 && revision <= 9_007_199_254_740_991 && date != nil &&
            WhisperKnotMessageSkills.normalizedReaction(emoji) == emoji
    }
}
