import SwiftUI
import os

/// Incremental, memory-only presentation cache. It never authorizes content or
/// persists another person's posts; its lifetime belongs to the account's Home.
@MainActor @Observable
final class WhisperFeedProjection {
    private(set) var posts: [WhisperPost] = []
    @ObservationIgnored private var generation: UUID = AccountStorage.generation
    @ObservationIgnored private var previousRows: [WhisperPostRow] = []
    @ObservationIgnored private var previousNames: [String: String] = [:]
    @ObservationIgnored private var previousLikes: Set<String> = []
    @ObservationIgnored private var minute: Int = -1
    @ObservationIgnored private var previousBans: Set<String> = []
    @ObservationIgnored private var previousMutes: [String: Date] = [:]
    @ObservationIgnored private var mapped: [String: (row: WhisperPostRow, post: WhisperPost)] = [:]

    func update(rows: [WhisperPostRow], names: [String: String], likedIDs: Set<String>, forceRank: Bool = false) {
        if generation != AccountStorage.generation {
            generation = AccountStorage.generation
            previousRows = []; previousNames = [:]; previousLikes = []; mapped = [:]; posts = []; minute = -1
        }
        let interval = WhisperPerformance.signposter.beginInterval("FeedProjection")
        defer { WhisperPerformance.signposter.endInterval("FeedProjection", interval) }
        let moderation = WhisperModerationService.shared
        let mutes = moderation.activeMutes.filter { $0.value > Date() }
        let moderationChanged = previousBans != moderation.bannedUsers || previousMutes != mutes
        previousBans = moderation.bannedUsers; previousMutes = mutes
        let currentMinute = Int(Date().timeIntervalSince1970 / 60)
        let contentChanged = rows != previousRows || names != previousNames || currentMinute != minute
        guard contentChanged || likedIDs != previousLikes || forceRank || moderationChanged else { return }
        if !contentChanged && !forceRank && !moderationChanged {
            // A heart-state response must not sort the feed under the reader.
            posts = posts.map { post in
                var result = post
                result.liked = likedIDs.contains(post.id.uuidString.lowercased())
                return result
            }
            previousLikes = likedIDs
            return
        }
        var next: [String: (row: WhisperPostRow, post: WhisperPost)] = [:]
        let models: [WhisperPost] = rows.compactMap { row in
            guard let id = UUID(uuidString: row.id) else { return nil }
            let name = names[row.user_id] ?? row.username ?? "user"
            if let cached = mapped[row.id], cached.row == row, cached.post.username == name {
                var post = cached.post
                if currentMinute != minute, let date = post.createdAt {
                    post.timeAgo = WhisperPost.relativeTime(from: date)
                }
                post.liked = likedIDs.contains(row.id.lowercased())
                next[row.id] = (row, post)
                return post
            }
            let cached = mapped[row.id]
            let date = cached?.row.created_at == row.created_at ? cached?.post.createdAt : WhisperBackendService.parseISO(row.created_at)
            let kind = WhisperPostKind(rawValue: row.kind ?? "") ?? .photo
            let post = WhisperPost(
                id: id, username: name, timeAgo: date.map { WhisperPost.relativeTime(from: $0) } ?? "now",
                kind: kind, caption: row.caption, symbol: row.symbol ?? kind.icon,
                accent: WhisperPost.color(fromHex: row.accent_hex) ?? Color(red: 0.5, green: 0.5, blue: 0.5),
                mediaURLs: (row.media_urls ?? []).compactMap(URL.init(string:)),
                likes: row.likes_count ?? 0, comments: row.comments_count ?? 0,
                liked: likedIDs.contains(row.id.lowercased()), isReel: row.is_reel ?? false,
                createdAt: date, communityID: row.community_id, communityName: row.community_name,
                authorUserID: row.user_id
            )
            next[row.id] = (row, post)
            return post
        }
        mapped = next
        previousRows = rows; previousNames = names; previousLikes = likedIDs; minute = currentMinute
        if forceRank || posts.isEmpty {
            posts = WhisperAlgorithmService.rank(models)
        } else {
            // Enrichment, likes, seen-state and clock changes must never reorder
            // already displayed rows. New arrivals join at the end until refresh.
            let byID = Dictionary(models.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let existingIDs = Set(posts.map(\.id))
            let retained = posts.compactMap { byID[$0.id] }
            let arrivals = models.filter { !existingIDs.contains($0.id) }
            let visible = (retained + arrivals).filter { !moderation.isBanned($0.username) }
            posts = visible.filter { !moderation.isMuted($0.username) }
                + visible.filter { moderation.isMuted($0.username) }
        }
    }
}
