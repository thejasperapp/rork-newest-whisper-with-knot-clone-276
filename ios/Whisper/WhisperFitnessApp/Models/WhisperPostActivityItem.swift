import Foundation

/// A real engagement event; quote and like events from one person keep distinct identities.
nonisolated struct WhisperPostActivityItem: Identifiable, Sendable {
    let id: String
    let profile: WhisperUserRow
    let createdAt: Date?
    let quotePostID: String?
    let excerpt: String?
    var isQuote: Bool { quotePostID != nil }
}
