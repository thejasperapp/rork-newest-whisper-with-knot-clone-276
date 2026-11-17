import Foundation

/// A Social server projection of a signed Teams event; never decoded from writable message metadata.
nonisolated struct WhisperTeamsInvitationCard: Decodable, Sendable {
    let messageId: UUID
    let invitationId: UUID
    let teamId: UUID
    let inviterId: UUID
    let recipientId: UUID
    let version: String
    let teamName: String
    let status: String
    let expiresAt: Int64
    let occurredAt: Int64
    let canOpen: Bool

    static let prefix: String = "::whisper-teams-v1::"
    static func isCandidate(body: String, messageID: String) -> Bool {
        guard let id = UUID(uuidString: messageID) else { return false }
        return body == prefix + id.uuidString.lowercased()
    }
    var statusLabel: String {
        switch status {
        case "pending": "Awaiting review in Teams"
        case "accepted": "Accepted in Teams"
        case "declined": "Declined in Teams"
        case "revoked": "Invitation revoked"
        case "expired": "Invitation expired"
        default: "Status unavailable"
        }
    }
    var isExpired: Bool { expiresAt <= Int64(Date().timeIntervalSince1970 * 1000) }
    var nativeURL: URL? { URL(string: "whisperteams://invitations/" + teamId.uuidString.lowercased()) }
}
