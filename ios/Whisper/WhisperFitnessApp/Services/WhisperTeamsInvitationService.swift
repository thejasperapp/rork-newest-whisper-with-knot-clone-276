import Foundation
import Supabase

/// Social-owned RPCs only. No Teams command, roster write or automatic acceptance.
@MainActor enum WhisperTeamsInvitationService {
    nonisolated enum Failure: LocalizedError {
        case unavailable
        var errorDescription: String? { "This invitation couldn't be confirmed. It may be unavailable or access may have changed." }
    }
    static func load(message: WhisperMessageRow) async throws -> WhisperTeamsInvitationCard {
        guard WhisperTeamsInvitationCard.isCandidate(body: message.body, messageID: message.id), message.conversationKind == .direct else { throw Failure.unavailable }
        let data = try await perform("whisper_social_teams_card", params: ["p_message_id": message.id])
        let value = try JSONDecoder().decode(WhisperTeamsInvitationCard.self, from: data)
        guard let owner = UUID(uuidString: AccountStorage.currentUserID), value.messageId == UUID(uuidString: message.id), value.inviterId == UUID(uuidString: message.from_user_id),
              value.recipientId == UUID(uuidString: message.to_user_id),
              [value.inviterId, value.recipientId].contains(owner),
              let revision = Int64(value.version), revision > 0,
              ["pending", "accepted", "declined", "revoked", "expired"].contains(value.status),
              value.expiresAt > 0, value.occurredAt > 0, value.teamName.utf16.count <= 120,
              !value.canOpen || (value.status == "pending" && value.recipientId == UUID(uuidString: AccountStorage.currentUserID))
        else { throw Failure.unavailable }
        return value
    }
    static func perform<P: Encodable & Sendable>(_ name: String, params: P) async throws -> Data {
        let owner = AccountStorage.currentUserID.lowercased(), generation = AccountStorage.generation
        let client = SupabaseService.shared.client
        let session = try await client.auth.session
        func check() throws {
            try Task.checkCancellation()
            guard generation == AccountStorage.generation, owner == AccountStorage.currentUserID.lowercased(),
                  session.user.id.uuidString.lowercased() == owner,
                  client.auth.currentSession?.user.id == session.user.id else { throw Failure.unavailable }
        }
        try check()
        guard let base = URL(string: SupabaseService.supabaseURL) else { throw Failure.unavailable }
        var request = URLRequest(url: base.appendingPathComponent("rest/v1/rpc").appendingPathComponent(name))
        request.httpMethod = "POST"; request.timeoutInterval = 15; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseService.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(params)
        let transport = URLSession(configuration: .ephemeral, delegate: WhisperRefuseRedirectDelegate(), delegateQueue: nil)
        defer { transport.invalidateAndCancel() }
        let (data, response) = try await transport.data(for: request)
        try check()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count <= 16_384 else { throw Failure.unavailable }
        return data
    }
}
