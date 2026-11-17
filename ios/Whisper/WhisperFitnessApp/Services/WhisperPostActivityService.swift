import Foundation
import Supabase

/// Reads activity only after fresh original-post admission. No counts are inferred from feed caches.
@MainActor enum WhisperPostActivityService {
    nonisolated struct Like: Decodable, Sendable {
        let user_id: String
        let created_at: String?
    }
    nonisolated struct Page: Sendable {
        let items: [WhisperPostActivityItem]
        let consumed: Int
        let hasMore: Bool
    }
    private static var client: SupabaseClient { SupabaseService.shared.client }
    static let pageSize: Int = 25

    static func original(_ postID: String) async throws -> WhisperPost? {
        let owner = AccountStorage.currentUserID; let epoch = AccountStorage.generation
        try WhisperChatMediaService.checkAccount(owner, generation: epoch)
        guard let row = try await WhisperBackendService.shared.loadReferencedPost(postID: postID) else { return nil }
        guard try await unblocked(row.user_id, viewer: owner), canOpenCommunity(row) else { return nil }
        let profile = await WhisperUserService.shared.fetchByUserID(row.user_id)
        try WhisperChatMediaService.checkAccount(owner, generation: epoch)
        return WhisperRootView.mapRowToPost(row, fallbackUsername: profile?.username)
    }
    static func likes(_ postID: String, offset: Int) async throws -> Page {
        let owner = AccountStorage.currentUserID; let epoch = AccountStorage.generation
        guard try await original(postID) != nil else { throw URLError(.noPermissionsToReadFile) }
        try WhisperChatMediaService.checkAccount(owner, generation: epoch)
        let rows: [Like] = try await client.from("whisper_post_likes").select("user_id,created_at")
            .eq("post_id", value: postID).order("created_at", ascending: false).order("user_id", ascending: true)
            .range(from: offset, to: offset + pageSize - 1).execute().value
        try WhisperChatMediaService.checkAccount(owner, generation: epoch)
        let profiles = try await admittedProfiles(rows.map(\.user_id), viewer: owner)
        try WhisperChatMediaService.checkAccount(owner, generation: epoch)
        let items = rows.compactMap { row -> WhisperPostActivityItem? in
            guard let profile = profiles[row.user_id.lowercased()] else { return nil }
            return WhisperPostActivityItem(id: "like:\(row.user_id.lowercased())", profile: profile, createdAt: date(row.created_at), quotePostID: nil, excerpt: nil)
        }
        return Page(items: items, consumed: rows.count, hasMore: rows.count == pageSize)
    }
    static func quotes(_ postID: String, offset: Int) async throws -> Page {
        let owner = AccountStorage.currentUserID; let epoch = AccountStorage.generation
        guard let id = UUID(uuidString: postID), try await original(postID) != nil else { throw URLError(.noPermissionsToReadFile) }
        try WhisperChatMediaService.checkAccount(owner, generation: epoch)
        // Caption search narrows the candidates; only an exact decoded reference is a quote.
        let candidates: [WhisperPostRow] = try await client.from("whisper_posts").select()
            .ilike("caption", pattern: "%\(id.uuidString.lowercased())%")
            .order("created_at", ascending: false).order("id", ascending: true)
            .range(from: offset, to: offset + pageSize - 1).execute().value
        try WhisperChatMediaService.checkAccount(owner, generation: epoch)
        let matching = candidates.filter { row in
            let quote = WhisperContentEmbedParser.parse(row.caption ?? "").quote
            return quote?.postID.lowercased() == postID.lowercased() && quote?.commentID == nil && canOpenCommunity(row)
        }
        let visible = try await WhisperPostVisibilityService.visible(matching)
        try WhisperChatMediaService.checkAccount(owner, generation: epoch)
        let profiles = try await admittedProfiles(visible.map(\.user_id), viewer: owner)
        try WhisperChatMediaService.checkAccount(owner, generation: epoch)
        let items = visible.compactMap { row -> WhisperPostActivityItem? in
            guard let profile = profiles[row.user_id.lowercased()] else { return nil }
            let text = WhisperContentPreview.text(row.caption, fallback: "Post", limit: 500)
            return WhisperPostActivityItem(id: "quote:\(row.id.lowercased())", profile: profile, createdAt: date(row.created_at), quotePostID: row.id, excerpt: String(text.prefix(500)))
        }
        return Page(items: items, consumed: candidates.count, hasMore: candidates.count == pageSize)
    }
    static func followerCount(_ userID: String) async -> Int? {
        let owner = AccountStorage.currentUserID; let epoch = AccountStorage.generation
        do {
            try WhisperChatMediaService.checkAccount(owner, generation: epoch)
            let response = try await client.from("whisper_follows").select("followee_id", head: true, count: .exact).eq("followee_id", value: userID).execute()
            try WhisperChatMediaService.checkAccount(owner, generation: epoch)
            return response.count
        } catch { return nil }
    }
    private static func admittedProfiles(_ ids: [String], viewer: String) async throws -> [String: WhisperUserRow] {
        guard !ids.isEmpty else { return [:] }
        let epoch = AccountStorage.generation
        let rows: [WhisperUserRow] = try await client.from("whisper_profiles").select().in("user_id", values: Array(Set(ids))).execute().value
        var result: [String: WhisperUserRow] = [:]
        // Bound bilateral checks to five in flight. An unavailable check fails the page closed.
        for start in stride(from: 0, to: rows.count, by: 5) {
            let slice = Array(rows[start..<min(rows.count, start + 5)])
            let admitted = try await withThrowingTaskGroup(of: WhisperUserRow?.self) { group in
                for row in slice {
                    group.addTask { @MainActor in
                        try WhisperChatMediaService.checkAccount(viewer, generation: epoch)
                        return try await unblocked(row.user_id, viewer: viewer) ? row : nil
                    }
                }
                var values: [WhisperUserRow] = []
                for try await value in group { if let value { values.append(value) } }
                return values
            }
            try WhisperChatMediaService.checkAccount(viewer, generation: epoch)
            for row in admitted { result[row.user_id.lowercased()] = row }
        }
        return result
    }
    private static func unblocked(_ author: String, viewer: String) async throws -> Bool {
        if author.lowercased() == viewer.lowercased() { return true }
        let blocked: Bool = try await client.rpc("whisper_dating_blocked_between", params: ["a": viewer.lowercased(), "b": author.lowercased()]).execute().value
        return !blocked
    }
    private static func canOpenCommunity(_ row: WhisperPostRow) -> Bool {
        row.community_id != "jasper-circle" || JasperConnectClient.shared.connection != nil
    }
    static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let format = ISO8601DateFormatter(); format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = format.date(from: raw) { return date }
        format.formatOptions = [.withInternetDateTime]; return format.date(from: raw)
    }
}
