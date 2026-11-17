import Foundation

/// One directed grant for direct Meet invitations only; never an RSVP or a general chat approval.
nonisolated struct WhisperChatMeetPermission: Decodable, Equatable, Identifiable, Sendable {
    enum State: String, Decodable, Sendable {
        case pending, accepted, denied, revoked

        var label: String {
            switch self {
            case .pending: "Awaiting approval"
            case .accepted: "Allowed"
            case .denied: "Denied"
            case .revoked: "Revoked"
            }
        }
    }

    enum Action: String, Encodable, Sendable {
        case request, accept, deny, revoke

        var requiresRollout: Bool { self == .request || self == .accept }
        var resultingState: State? {
            switch self {
            case .request: nil
            case .accept: .accepted
            case .deny: .denied
            case .revoke: .revoked
            }
        }
    }

    let organizerID: UUID
    let recipientID: UUID
    /// Present in list responses only; always identifies the other person.
    let username: String?
    let state: State
    let revision: Int64
    let scope: String

    var id: String { "\(organizerID.uuidString)/\(recipientID.uuidString)" }

    func isValid(for caller: UUID) -> Bool {
        organizerID != recipientID && (organizerID == caller || recipientID == caller)
            && revision > 0 && scope == "chat-meet-invitations-v1"
    }
}
