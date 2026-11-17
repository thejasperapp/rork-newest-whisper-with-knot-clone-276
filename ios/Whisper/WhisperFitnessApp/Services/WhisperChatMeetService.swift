import Foundation
import Supabase

/// Uses protected RPCs only: never falls back to the legacy broadly readable calendar writes.
@MainActor
enum WhisperChatMeetService {
    /// Client release hold is lifted; server activation, consent and authorization still apply.
    static let holdsNewInvitations: Bool = false

    nonisolated struct ScheduleRequest: Codable, Sendable {
        let operation_id: String
        let conversation_kind: String
        let peer_id: String?
        let group_id: String?
        let title: String
        let starts_at: String
        let ends_at: String
        let timezone: String
    }
    nonisolated enum Failure: LocalizedError, Equatable {
        case activationPending, invitationUnavailable, notAllowed
        case serviceUpdate, unavailable, changedAccount, invalidResponse, clientRolloutHold
        case permissionConflict, transactionContention, permissionRevoked, conversationUnavailable
        case invalidPermissionRequest, requestRateLimited, datingConsentRequired
        var errorDescription: String? {
            switch self {
            case .clientRolloutHold: "Scheduling, new permission requests and acceptance are paused in this version. You can still review, deny or revoke existing permissions."
            case .permissionConflict: "This permission changed or its revision is no longer current. Refresh and review it before choosing again."
            case .transactionContention: "Meet is busy with another change. Please wait a moment before retrying."
            case .permissionRevoked: "This permission was denied or revoked. It can't be accepted again, and another request won't reset it."
            case .conversationUnavailable: "Meet permission isn't available for these accounts. Account eligibility and blocks are checked by the server."
            case .invalidPermissionRequest: "This permission request isn't valid. Reopen the conversation and try again."
            case .requestRateLimited: "You've reached the limit of 20 new Meet permission requests in the past day. Please try later."
            case .datingConsentRequired: "Both people must currently choose Again for the same latest date recorded by Whisper. A previous match or chat message doesn't qualify."
            case .activationPending: "Meet invitations are installed but not yet activated. The rollout is still pending. Please check again later."
            case .invitationUnavailable: "This invitation isn't available to this account."
            case .notAllowed: "Meet couldn't authorize this action. Current invitation permission and chat eligibility are required."
            case .serviceUpdate: "Meet couldn't resolve a required service function. Please try again after the service is updated."
            case .invalidResponse: "Couldn't verify Meet's latest response. Keep this request and check again."
            case .unavailable: "Couldn't confirm this meeting. Check your connection and try again."
            case .changedAccount: "Your account changed. Reopen this meeting from the current account."
            }
        }
    }

    static func schedule(_ request: ScheduleRequest) async throws -> WhisperChatMeetInvitation {
        guard !holdsNewInvitations else { throw Failure.clientRolloutHold }
        guard UUID(uuidString: request.operation_id) != nil,
              ["direct", "dating", "group"].contains(request.conversation_kind) else { throw Failure.unavailable }
        if request.conversation_kind == "group" {
            guard request.peer_id == nil, UUID(uuidString: request.group_id ?? "") != nil else { throw Failure.unavailable }
        } else {
            guard request.group_id == nil, UUID(uuidString: request.peer_id ?? "") != nil else { throw Failure.unavailable }
        }
        return try await call("whisper_chat_meet_schedule", params: request)
    }
    static func load(eventID: String) async throws -> WhisperChatMeetInvitation {
        guard UUID(uuidString: eventID) != nil else { throw Failure.invitationUnavailable }
        return try await call("whisper_chat_meet_get", params: ["event_id": eventID], expectedEventID: eventID)
    }
    static func respond(eventID: String, status: String) async throws -> WhisperChatMeetInvitation {
        guard UUID(uuidString: eventID) != nil else { throw Failure.invitationUnavailable }
        guard ["going", "declined"].contains(status) else { throw Failure.unavailable }
        return try await call("whisper_chat_meet_respond", params: ["event_id": eventID, "response_status": status], expectedEventID: eventID)
    }

    /// Organizer recovery is server-owned. A successful retry HTTP response alone is not delivery confirmation.
    static func retry(eventID: String) async throws -> WhisperChatMeetInvitation {
        guard UUID(uuidString: eventID) != nil else { throw Failure.invitationUnavailable }
        let generation = AccountStorage.generation
        let owner = AccountStorage.currentUserID
        _ = try await perform("whisper_chat_meet_retry", params: ["event_id": eventID])
        guard generation == AccountStorage.generation, owner == AccountStorage.currentUserID else { throw Failure.changedAccount }
        try Task.checkCancellation()
        return try await load(eventID: eventID)
    }

    /// Reads are not rollout-gated. The RPC returns an array, including both directions.
    static func permissions() async throws -> [WhisperChatMeetPermission] {
        guard let caller = UUID(uuidString: AccountStorage.currentUserID) else { throw Failure.changedAccount }
        let data = try await perform("whisper_chat_meet_permissions", params: [String: String]())
        guard let rows = try? JSONDecoder().decode([WhisperChatMeetPermission].self, from: data),
              rows.allSatisfy({ $0.isValid(for: caller) && $0.username != nil }),
              Set(rows.map(\.id)).count == rows.count else { throw Failure.invalidResponse }
        return rows
    }

    /// Recipient actions must use the recipient's own session and a server-returned Int64 revision.
    static func permission(peerID: UUID, action: WhisperChatMeetPermission.Action, expectedRevision: Int64?) async throws -> WhisperChatMeetPermission {
        if action.requiresRollout && holdsNewInvitations { throw Failure.clientRolloutHold }
        guard let caller = UUID(uuidString: AccountStorage.currentUserID), caller != peerID else { throw Failure.invalidPermissionRequest }
        if action != .request {
            guard let expectedRevision, expectedRevision > 0 else { throw Failure.permissionConflict }
        }
        let payload = PermissionRequest(peer_id: peerID.uuidString.lowercased(), action: action,
                                        expected_revision: action == .request ? nil : expectedRevision)
        let data = try await perform("whisper_chat_meet_permission", params: payload)
        guard let row = try? JSONDecoder().decode(WhisperChatMeetPermission.self, from: data), row.isValid(for: caller),
              row.organizerID == (action == .request ? caller : peerID),
              row.recipientID == (action == .request ? peerID : caller),
              action.resultingState == nil || row.state == action.resultingState,
              expectedRevision == nil || action == .request || row.revision >= (expectedRevision ?? 0) else { throw Failure.invalidResponse }
        return row
    }

    nonisolated private struct PermissionRequest: Encodable, Sendable {
        let peer_id: String
        let action: WhisperChatMeetPermission.Action
        // Synthesized encoding omits nil for request; never invent an initial revision.
        let expected_revision: Int64?
    }

    nonisolated private struct RPCFailure: Decodable { let code: String?; let message: String? }

    /// Match the documented SQLSTATE/message pair; other 55000 errors are not proof of rollout state.
    nonisolated static func failure(code: String?, message: String?) -> Failure {
        if code == "55000", message == "chat_meet_activation_pending" { return .activationPending }
        if code == "42501", message == "invitation_unavailable" { return .invitationUnavailable }
        if code == "40001", message == "permission_conflict" { return .permissionConflict }
        if code == "40001", message == "chat_meet_retry_transaction" { return .transactionContention }
        if code == "42501", message == "permission_revoked" { return .permissionRevoked }
        if code == "42501", message == "conversation_unavailable" { return .conversationUnavailable }
        if code == "42501", message == "dating_consent_required" { return .datingConsentRequired }
        if code == "22023", message == "invalid_permission_request" { return .invalidPermissionRequest }
        if code == "P0001", message == "request_rate_limited" { return .requestRateLimited }
        if code == "42501" { return .notAllowed }
        if code == "PGRST202" || code == "42883" { return .serviceUpdate }
        return .unavailable
    }

    private static func call<P: Encodable & Sendable>(_ name: String, params: P, expectedEventID: String? = nil) async throws -> WhisperChatMeetInvitation {
        let owner = AccountStorage.currentUserID.lowercased()
        let data = try await perform(name, params: params)
        guard let result = try? JSONDecoder().decode(WhisperChatMeetInvitation.self, from: data),
              UUID(uuidString: result.eventID) != nil, WhisperMeetingInvitation.isIdentity(result.meetingID),
              expectedEventID == nil || result.eventID.lowercased() == expectedEventID?.lowercased(),
              result.invitees.contains(where: { $0.userID.lowercased() == owner }),
              result.invitees.allSatisfy({ UUID(uuidString: $0.userID) != nil && ($0.status == nil || $0.status == "going" || $0.status == "declined") }),
              Set(result.invitees.map { $0.userID.lowercased() }).count == result.invitees.count else { throw Failure.invalidResponse }
        return result
    }

    private static func perform<P: Encodable & Sendable>(_ name: String, params: P) async throws -> Data {
        let generation = AccountStorage.generation
        let owner = AccountStorage.currentUserID.lowercased()
        let client = SupabaseService.shared.client
        do {
            let session = try await client.auth.session
            guard generation == AccountStorage.generation, session.user.id.uuidString.lowercased() == owner else { throw Failure.changedAccount }
            try Task.checkCancellation()
            guard let base = URL(string: SupabaseService.supabaseURL) else { throw Failure.unavailable }
            var request = URLRequest(url: base.appendingPathComponent("rest/v1/rpc").appendingPathComponent(name))
            request.httpMethod = "POST"; request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(SupabaseService.supabaseAnonKey, forHTTPHeaderField: "apikey")
            // Pin the authenticated snapshot: the shared SDK may switch users while this request is suspended.
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(params)
            // Only explicit transaction-lock contention is replayable automatically. Keep identical
            // bytes, operation ID, revision and authenticated owner across at most three attempts.
            for attempt in 0..<3 {
                try Task.checkCancellation()
                guard generation == AccountStorage.generation, owner == AccountStorage.currentUserID.lowercased(),
                      client.auth.currentSession?.user.id.uuidString.lowercased() == owner else { throw Failure.changedAccount }
                let (data, response) = try await URLSession.shared.data(for: request)
                try Task.checkCancellation()
                guard generation == AccountStorage.generation, owner == AccountStorage.currentUserID.lowercased(),
                      client.auth.currentSession?.user.id.uuidString.lowercased() == owner else { throw Failure.changedAccount }
                if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) { return data }
                let responseFailure = try? JSONDecoder().decode(RPCFailure.self, from: data)
                let mapped = failure(code: responseFailure?.code, message: responseFailure?.message)
                guard mapped == .transactionContention, attempt < 2 else { throw mapped }
                let delay = (attempt == 0 ? 250 : 700) + Int.random(in: 0...150)
                try await Task.sleep(for: .milliseconds(delay))
            }
            throw Failure.transactionContention
        } catch is CancellationError { throw CancellationError() }
        catch let error as Failure { throw error }
        catch {
            try Task.checkCancellation()
            throw Failure.unavailable
        }
    }
}
