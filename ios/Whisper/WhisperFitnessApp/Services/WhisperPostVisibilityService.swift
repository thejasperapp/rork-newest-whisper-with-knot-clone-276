import Foundation
import Supabase

/// Defense-in-depth for original posts opened outside the feed. Server RLS still applies.
@MainActor enum WhisperPostVisibilityService {
    static func visible(_ rows: [WhisperPostRow]) async throws -> [WhisperPostRow] {
        guard !rows.isEmpty else { return [] }
        let generation = AccountStorage.generation
        let viewer = AccountStorage.currentUserID.lowercased()
        let client = SupabaseService.shared.client
        let authorIDs = Array(Set(rows.map { $0.user_id.lowercased() }))
        let profiles: [WhisperUserRow] = try await client.from("whisper_profiles").select()
            .in("user_id", values: authorIDs).execute().value
        let privateIDs = profiles.filter { $0.is_private == true && $0.user_id.lowercased() != viewer }.map(\.user_id)
        var following: Set<String> = []
        if !privateIDs.isEmpty, UUID(uuidString: viewer) != nil {
            let edges: [WhisperFollowRow] = try await client.from("whisper_follows").select()
                .eq("follower_id", value: viewer).in("followee_id", values: privateIDs).execute().value
            following = Set(edges.map { $0.followee_id.lowercased() })
        }
        guard !Task.isCancelled, generation == AccountStorage.generation else { throw CancellationError() }
        let byID = Dictionary(profiles.map { ($0.user_id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        return rows.filter { row in
            let author = row.user_id.lowercased()
            return WhisperProfileVisibilityPolicy.canView(viewerID: viewer, authorID: author,
                resolved: byID[author] != nil, isPrivate: byID[author]?.is_private,
                following: following.contains(author), blocked: WhisperBlockService.shared.isBlocked(userID: author))
        }
    }
}
