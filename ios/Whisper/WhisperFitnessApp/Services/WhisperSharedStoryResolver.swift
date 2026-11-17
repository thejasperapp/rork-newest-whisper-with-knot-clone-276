import Foundation
import Supabase

/// Fresh, fail-closed admission for Stories opened outside the Story list. Server RLS still applies.
@MainActor enum WhisperSharedStoryResolver {
    nonisolated private struct Identity: Decodable {
        let id: String
        let user_id: String
        let expires_at: String?
    }

    static func expiry(_ row: WhisperStoryRow) -> Date? {
        parseDate(row.expires_at)
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    static func resolve(id: String) async throws -> WhisperStoryRow? {
        guard let storyID = UUID(uuidString: id) else { return nil }
        let generation = AccountStorage.generation
        let viewer = AccountStorage.currentUserID.lowercased()
        guard UUID(uuidString: viewer) != nil else { return nil }
        let client = SupabaseService.shared.client
        let session = try await client.auth.session
        func checkAccount() throws {
            guard !Task.isCancelled, generation == AccountStorage.generation,
                  viewer == AccountStorage.currentUserID.lowercased(),
                  client.auth.currentSession?.user.id.uuidString.lowercased() == viewer else { throw CancellationError() }
        }
        try checkAccount()
        guard session.user.id.uuidString.lowercased() == viewer else { return nil }
        let identities: [Identity] = try await client.from("whisper_stories").select("id,user_id,expires_at")
            .eq("id", value: storyID.uuidString.lowercased()).gt("expires_at", value: Date().ISO8601Format()).limit(1).execute().value
        try checkAccount()
        guard let identity = identities.first, let end = parseDate(identity.expires_at), end > Date(),
              let authorUUID = UUID(uuidString: identity.user_id) else { return nil }
        let author = authorUUID.uuidString.lowercased()
        let profiles: [WhisperUserRow] = try await client.from("whisper_profiles").select()
            .eq("user_id", value: author).limit(1).execute().value
        try checkAccount()
        guard let profile = profiles.first else { return nil }
        // The existing SECURITY DEFINER helper reads both directions; an RLS-filtered
        // table read cannot establish whether the author has blocked this viewer.
        let blocked: Bool = try await client.rpc("whisper_dating_blocked_between", params: ["a": viewer, "b": author]).execute().value
        try checkAccount()
        guard !blocked else { return nil }
        var follows: Bool = false
        if profile.is_private != false && author != viewer {
            let edges: [WhisperFollowRow] = try await client.from("whisper_follows").select()
                .eq("follower_id", value: viewer).eq("followee_id", value: author).limit(1).execute().value
            try checkAccount()
            follows = !edges.isEmpty
        }
        // Unknown profile privacy does not become public through a forwarded reference.
        guard author == viewer || profile.is_private == false || follows else { return nil }
        let rows: [WhisperStoryRow] = try await client.from("whisper_stories").select()
            .eq("id", value: storyID.uuidString.lowercased()).eq("user_id", value: author)
            .gt("expires_at", value: Date().ISO8601Format()).limit(1).execute().value
        try checkAccount()
        guard let row = rows.first, let expiry = expiry(row), expiry > Date() else { return nil }
        return row
    }
}
