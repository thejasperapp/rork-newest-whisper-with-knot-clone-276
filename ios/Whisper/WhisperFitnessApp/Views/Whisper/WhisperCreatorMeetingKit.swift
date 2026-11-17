import SwiftUI
import Foundation

// MARK: - Creator analytics wire payload (camelCase, web-ready)

/// The live analytics card a creator presents into a meeting — the same
/// numbers Creator Studio renders (score ring, momentum, top posts), shipped
/// over the room's data channel with the same discipline as
/// `WhisperPresentedClient` so the web client can render an identical card.
nonisolated struct WhisperCreatorAnalyticsCard: Codable, Sendable, Hashable {
    /// One top-performing post, carrying enough to render the REAL post row
    /// and to reconstruct a `WhisperPost` for the full-screen detail modal.
    nonisolated struct TopPost: Codable, Sendable, Hashable, Identifiable {
        var id: String
        var caption: String?
        var kind: String?
        var isReel: Bool?
        var symbol: String?
        var accentHex: String?
        var likes: Double?
        var comments: Double?
        var createdAt: String?
        var mediaUrls: [String]?
        var score: Double?
    }

    var id: String
    var username: String?
    var imageUrl: String?
    var score: Double?
    var followers: Double?
    var followerDelta: Double?
    var engagementPct: Double?
    var posts30: Double?
    var likes30: Double?
    var comments30: Double?
    var reels: Double?
    var photos: Double?
    var verdict: String?
    var topPosts: [TopPost]?
    /// Bumped on every re-broadcast carrying fresher data so viewers accept
    /// the update instead of ignoring it as a heartbeat.
    var rev: Double?
    var presenterUserId: String
    var presenterName: String

    nonisolated static func decode(fromAny dict: [String: Any]) -> WhisperCreatorAnalyticsCard? {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(WhisperCreatorAnalyticsCard.self, from: data)
    }

    nonisolated func encodeToDict() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    /// Wire-safe copy. Two silent killers used to make every RECEIVER drop
    /// the share while the presenter still saw their own card:
    /// 1. Non-finite numbers (NaN/∞ — e.g. engagement computed against 0
    ///    followers) make `JSONEncoder` throw, collapsing the broadcast into
    ///    an empty dict nobody can decode.
    /// 2. A presenter id from legacy local storage that drifts from the
    ///    Supabase auth uid every guard compares against.
    /// This clamps every Double to finite-or-nil and re-stamps the presenter
    /// identity with the room's authoritative uid.
    nonisolated func wireSafe(presenterUserId: String, presenterName: String) -> WhisperCreatorAnalyticsCard {
        func fin(_ value: Double?) -> Double? {
            guard let value, value.isFinite else { return nil }
            return value
        }
        var copy = self
        if !presenterUserId.isEmpty { copy.presenterUserId = presenterUserId }
        if !presenterName.isEmpty { copy.presenterName = presenterName }
        copy.score = fin(score)
        copy.followers = fin(followers)
        copy.followerDelta = fin(followerDelta)
        copy.engagementPct = fin(engagementPct)
        copy.posts30 = fin(posts30)
        copy.likes30 = fin(likes30)
        copy.comments30 = fin(comments30)
        copy.reels = fin(reels)
        copy.photos = fin(photos)
        copy.rev = fin(rev)
        copy.topPosts = topPosts?.map { top in
            var item = top
            item.likes = fin(top.likes)
            item.comments = fin(top.comments)
            item.score = fin(top.score)
            return item
        }
        return copy
    }
}

// MARK: - Kit — live numbers, Jasper context, post reconstruction

/// Creator features inside meetings: builds the live analytics payload with
/// the exact client-side math Creator Studio uses, feeds Jasper a grounded
/// analytics context, and reconstructs real `WhisperPost`s from the wire so
/// top posts open in the true post detail screen.
@MainActor
enum WhisperCreatorMeetingKit {

    private struct Numbers {
        let me: String
        let score: Int
        let followers: Int
        let delta: Int
        let engagementPct: Double
        let posts30: Int
        let likes30: Int
        let comments30: Int
        let reels: Int
        let photos: Int
        let verdict: String
        let ranked: [(row: WhisperPostRow, score: Double)]
    }

    private static var cachedContext: (text: String, at: Date)?

    /// Maps a raw backend row to the model the ranking algorithm scores —
    /// byte-for-byte the Creator Studio mapping.
    private static func post(fromRow row: WhisperPostRow, fallback me: String) -> WhisperPost {
        WhisperPost(
            id: UUID(uuidString: row.id) ?? UUID(),
            username: row.username ?? me,
            timeAgo: WhisperPost.relativeTime(from: row.created_at),
            kind: WhisperPostKind(rawValue: row.kind ?? "") ?? .photo,
            caption: row.caption,
            symbol: row.symbol ?? WhisperPostKind(rawValue: row.kind ?? "")?.icon ?? "sparkles",
            accent: WhisperPost.color(fromHex: row.accent_hex) ?? Color.gray,
            mediaURLs: (row.media_urls ?? []).compactMap { URL(string: $0) },
            likes: row.likes_count ?? 0,
            comments: row.comments_count ?? 0,
            liked: false,
            isReel: row.is_reel ?? false,
            createdAt: WhisperBackendService.parseISO(row.created_at)
        )
    }

    /// Fetches my posts + follower count and computes the dashboard numbers
    /// (creator score, engagement, momentum, ranked posts). Nil = no posts.
    private static func computeNumbers() async -> Numbers? {
        let backend = WhisperBackendService.shared
        await backend.fetchMyPosts()
        let me = WhisperUserService.shared.me?.username
            ?? AuthenticationService.shared.currentUser.username
            ?? ""
        let rows = backend.myPosts
        guard !rows.isEmpty else { return nil }
        let followers = await WhisperFollowService.shared.followerCount(forUserID: AccountStorage.currentUserID)

        let mapped: [(row: WhisperPostRow, post: WhisperPost)] = rows.map { ($0, post(fromRow: $0, fallback: me)) }
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        let last30 = mapped.filter { ($0.post.createdAt ?? .distantPast) >= cutoff }
        let likes30 = last30.reduce(0) { $0 + $1.post.likes }
        let comments30 = last30.reduce(0) { $0 + $1.post.comments }
        let engagementPct: Double
        if followers > 0, !last30.isEmpty {
            engagementPct = min(100, (Double(likes30 + comments30) / Double(followers * last30.count)) * 100)
        } else {
            engagementPct = 0
        }

        // Same read-only delta source Creator Studio stamps weekly.
        let deltaKey = "whisper_creator_studio_followers_\(me.lowercased())"
        let lastSnapshot = UserDefaults.standard.integer(forKey: deltaKey)
        let delta = lastSnapshot == 0 ? 0 : followers - lastSnapshot

        let engagement = min(40.0, engagementPct * 8)
        let cadence = min(30.0, Double(last30.count) * 3)
        let audience = min(20.0, Double(followers) / 50)
        let momentum: Double = delta > 0 ? 10 : (delta < 0 ? 0 : 5)
        let score = Int(min(100, engagement + cadence + audience + momentum))

        let verdict: String
        if score >= 75 { verdict = "On fire — the algorithm loves this pace." }
        else if score >= 50 { verdict = "Solid momentum. One more post this week pushes higher." }
        else if score >= 25 { verdict = "Warming up — consistency is your fastest lever." }
        else { verdict = "Post something today to wake the algorithm up." }

        let ranked = mapped
            .map { (row: $0.row, score: WhisperAlgorithmService.score(for: $0.post)) }
            .sorted { $0.score > $1.score }

        return Numbers(
            me: me,
            score: score,
            followers: followers,
            delta: delta,
            engagementPct: engagementPct,
            posts30: last30.count,
            likes30: likes30,
            comments30: comments30,
            reels: mapped.filter { $0.post.isReel }.count,
            photos: mapped.filter { !$0.post.isReel }.count,
            verdict: verdict,
            ranked: ranked
        )
    }

    /// Builds the broadcast payload from live data. Nil when the creator has
    /// no posts yet (the tools sheet shows an honest empty state instead).
    static func buildCard(presenterUserId: String, presenterName: String) async -> WhisperCreatorAnalyticsCard? {
        guard let n = await computeNumbers() else { return nil }
        let tops: [WhisperCreatorAnalyticsCard.TopPost] = n.ranked.prefix(3).map { entry in
            WhisperCreatorAnalyticsCard.TopPost(
                id: entry.row.id,
                caption: entry.row.caption,
                kind: entry.row.kind,
                isReel: entry.row.is_reel,
                symbol: entry.row.symbol,
                accentHex: entry.row.accent_hex,
                likes: Double(entry.row.likes_count ?? 0),
                comments: Double(entry.row.comments_count ?? 0),
                createdAt: entry.row.created_at,
                mediaUrls: entry.row.media_urls,
                score: entry.score
            )
        }
        return WhisperCreatorAnalyticsCard(
            id: UUID().uuidString.lowercased(),
            username: n.me,
            imageUrl: WhisperUserService.shared.me?.profile_image_url,
            score: Double(n.score),
            followers: Double(n.followers),
            followerDelta: Double(n.delta),
            engagementPct: n.engagementPct,
            posts30: Double(n.posts30),
            likes30: Double(n.likes30),
            comments30: Double(n.comments30),
            reels: Double(n.reels),
            photos: Double(n.photos),
            verdict: n.verdict,
            topPosts: tops,
            rev: Date().timeIntervalSince1970 * 1000,
            presenterUserId: presenterUserId,
            presenterName: presenterName
        )
    }

    /// The asker's live analytics as a grounded text block for the in-meeting
    /// Jasper. Cached briefly so rapid-fire questions don't refetch.
    static func jasperContext() async -> String? {
        if let cached = cachedContext, Date().timeIntervalSince(cached.at) < 180 {
            return cached.text
        }
        guard let n = await computeNumbers() else { return nil }
        var lines: [String] = ["=== LIVE CREATOR ANALYTICS (the asker's own, fresh this moment — ground any content, growth, or analytics answer in these real numbers; name their actual posts) ==="]
        lines.append("Creator score \(n.score)/100 · followers \(n.followers) (\(n.delta >= 0 ? "+" : "")\(n.delta) this week) · engagement \(String(format: "%.1f", n.engagementPct))% · posts 30d \(n.posts30) · likes 30d \(n.likes30) · comments 30d \(n.comments30)")
        lines.append("Formats: \(n.reels) reels · \(n.photos) posts")
        for entry in n.ranked.prefix(5) {
            let caption = entry.row.caption.isEmpty ? "(media post)" : String(entry.row.caption.prefix(60))
            lines.append("- \((entry.row.is_reel ?? false) ? "reel" : "post") · \(entry.row.likes_count ?? 0) likes · \(entry.row.comments_count ?? 0) comments · \(WhisperPost.relativeTime(from: entry.row.created_at)) · \(caption)")
        }
        let text = lines.joined(separator: "\n")
        cachedContext = (text, Date())
        return text
    }

    /// Rebuilds the REAL post model from the wire so a top post opens in the
    /// true full-screen post detail (live comments and likes — the ids are
    /// real posts).
    static func post(from top: WhisperCreatorAnalyticsCard.TopPost, username: String) -> WhisperPost {
        WhisperPost(
            id: UUID(uuidString: top.id) ?? UUID(),
            username: username,
            timeAgo: WhisperPost.relativeTime(from: top.createdAt),
            kind: WhisperPostKind(rawValue: top.kind ?? "") ?? .photo,
            caption: top.caption ?? "",
            symbol: top.symbol ?? WhisperPostKind(rawValue: top.kind ?? "")?.icon ?? "sparkles",
            accent: WhisperPost.color(fromHex: top.accentHex) ?? Color.gray,
            mediaURLs: (top.mediaUrls ?? []).compactMap { URL(string: $0) },
            likes: Int(top.likes ?? 0),
            comments: Int(top.comments ?? 0),
            liked: false,
            isReel: top.isReel ?? false,
            createdAt: WhisperBackendService.parseISO(top.createdAt)
        )
    }
}
