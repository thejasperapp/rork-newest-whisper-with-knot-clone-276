import Foundation

/// Whisper's lightweight ranking algorithm. Used by the Discover (Explore) grid
/// and the main feed to surface the most engaging posts and to amplify
/// verified, moderator, admin, and owner accounts.
///
/// Score recipe per post:
///   base     = log10(1 + likes) * 4 + log10(1 + comments) * 6
///   recency  = exp(-hours / halfLife)            // newer posts win
///   floor    = (likes + comments >= 3)           // gate the badge boost
///   boost    = floor ? badge.algorithmBoost : 1  // verified+ amplified
///   seen     = 0.7 if viewer has already seen it this session, else 1.0
///   final    = (base + recency * 5) * boost * seen
///
/// Verified profiles get a 1.6× multiplier — moderator 1.8×, admin 2.0×,
/// owner 2.4× — applied **once** here. Surface-level rankers (`discoverRank`,
/// `personalizedDiscoverRank`) no longer re-apply a badge nudge so the boost
/// isn't double-counted.
@MainActor
enum WhisperAlgorithmService {

    /// Half-life for the recency curve, in hours.
    static let recencyHalfLife: Double = 18

    /// Minimum (likes + comments) before the verified-tier algorithm boost
    /// engages. Empty verified posts shouldn't crush real engagement.
    static let badgeBoostEngagementFloor: Int = 3

    /// Per-session "already seen" multiplier. After a post has flashed past
    /// the viewer once we ding it 30% so the rail feels alive on refresh.
    static let seenDecayMultiplier: Double = 0.7

    // MARK: Recency

    /// Hours since `post.createdAt` (preferred) or, when missing, a tolerant
    /// parse of the `timeAgo` string. The string-fallback now correctly
    /// understands `mo` (months) and `y` (years) so old posts no longer
    /// score as "fresh".
    static func hoursSinceCreation(_ post: WhisperPost) -> Double {
        if let ts = post.createdAt {
            return max(0, Date().timeIntervalSince(ts) / 3600)
        }
        return hoursAgo(from: post.timeAgo)
    }

    /// Legacy "approximate hours from a human-readable label" parser, kept
    /// around for callers that don't have a real timestamp. Now correctly
    /// handles `mo` (month) and `y` (year) suffixes — previously `2mo`
    /// was treated as 2 hours.
    static func hoursAgo(from label: String) -> Double {
        let lowered = label.lowercased()
        if lowered.contains("just now") || lowered == "now" { return 0 }
        if lowered.contains("yesterday") { return 24 }
        let digits = lowered.filter { $0.isNumber }
        let value = Double(digits) ?? 1
        // Order matters — check longer suffixes first.
        if lowered.contains("mo") { return value * 24 * 30 }
        if lowered.contains("y")  { return value * 24 * 365 }
        if lowered.contains("w")  { return value * 24 * 7 }
        if lowered.contains("d")  { return value * 24 }
        if lowered.contains("h")  { return value }
        if lowered.contains("s")  { return value / 3600.0 }
        if lowered.contains("m")  { return value / 60.0 } // minutes
        return value
    }

    // MARK: Scoring

    /// Score a single post. Badge boost is applied here and *only* here —
    /// downstream rankers should not re-multiply by badge.
    static func score(for post: WhisperPost, seen: Bool = false) -> Double {
        let likes = log10(1 + Double(post.likes)) * 4
        let comments = log10(1 + Double(post.comments)) * 6
        let hours = hoursSinceCreation(post)
        let recency = exp(-hours / recencyHalfLife)
        let badge = UserVerificationService.shared.badge(forUsername: post.username.lowercased())
        let engaged = (post.likes + post.comments) >= badgeBoostEngagementFloor
        let boost = engaged ? badge.algorithmBoost : 1.0
        let seenMul = seen ? seenDecayMultiplier : 1.0
        // Dear-Jasper keyword nudge — user-driven curation. Applied as a
        // small multiplier so it reorders the feed without overpowering
        // organic engagement.
        let dearEmber = WhisperDearEmberService.shared.boost(for: post)
        return (likes + comments + recency * 5) * boost * seenMul * dearEmber
    }

    // MARK: Feed ranking (home)

    /// Home feed ordering. Banned authors are dropped, muted authors sink
    /// to the bottom, and the visible window is sorted by **real
    /// `createdAt` desc** (chronological) — but within the same 6-hour
    /// bucket we use `score` as a tiebreaker so verified creators bubble
    /// above near-simultaneous noise without breaking the timeline feel.
    static func rank(_ posts: [WhisperPost]) -> [WhisperPost] {
        let mod = WhisperModerationService.shared
        let visible = posts.filter { !mod.isBanned($0.username) }
        let seenTracker = WhisperFeedSeenTracker.shared
        // Score once per post, not twice per sort comparison. Keep source order
        // for exact ties so cache enrichment doesn't shuffle equal-ranked cards.
        let scored = visible.enumerated().map { index, post in
            (post: post, index: index, bucket: Int(hoursSinceCreation(post) / 6.0),
             score: score(for: post, seen: seenTracker.hasSeen(post.id)), muted: mod.isMuted(post.username))
        }
        return scored.sorted { lhs, rhs in
            if lhs.muted != rhs.muted { return !lhs.muted }
            if lhs.bucket != rhs.bucket { return lhs.bucket < rhs.bucket }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.index < rhs.index
        }.map(\.post)
    }

    // MARK: Discover ranking

    /// "Discover" ranking — pure engagement-driven; no badge double-count.
    static func discoverRank(_ posts: [WhisperPost]) -> [WhisperPost] {
        let mod = WhisperModerationService.shared
        let seenTracker = WhisperFeedSeenTracker.shared
        return posts
            .filter { !mod.isBanned($0.username) && !mod.isMuted($0.username) }
            .map { (post: $0, score: score(for: $0, seen: seenTracker.hasSeen($0.id))) }
            .sorted { $0.score > $1.score }
            .map(\.post)
    }

    // MARK: Waves ranking

    /// The Waves tab order: `score` (engagement + recency + badge boost + seen
    /// decay) × the viewer's OWN steering from "Your algorithm" (more-of
    /// terms lift matching waves up to 2.25×, less-of sinks them to 0.3×)
    /// × a 0.75 ding for waves already watched this month — so the tab leads
    /// with what you're into, not the newest upload.
    static func wavesRank(_ posts: [WhisperPost]) -> [WhisperPost] {
        let mod = WhisperModerationService.shared
        let visible = posts.filter { !mod.isBanned($0.username) && !mod.isMuted($0.username) }
        let scored: [(WhisperPost, Double)] = visible.map { ($0, wavesScore($0)) }
        return scored.sorted { $0.1 > $1.1 }.map { $0.0 }
    }

    private static func wavesScore(_ post: WhisperPost) -> Double {
        let prefs = WhisperAlgorithmPreferences.shared
        var s = score(for: post, seen: WhisperFeedSeenTracker.shared.hasSeen(post.id))
        s *= prefs.multiplier(for: post)
        if prefs.hasWatched(post.id) { s *= 0.75 }
        return s
    }

    /// Personalized Discover ranking, layered on top of `score`:
    ///   - +40% if the post matches one of the viewer's interests
    ///   - −35% if the viewer already follows the author (Discover surfaces
    ///     NEW voices)
    ///   - +15% if the post has media
    ///   - +10% if the post has a video URL (reels-friendly)
    ///   - +20% if the author is a verified coach
    /// Badge boost is **not** re-applied here — `score` already includes it.
    static func personalizedDiscoverRank(
        _ posts: [WhisperPost],
        interests: [String],
        followingUsernames: Set<String>,
        coachUsernames: Set<String> = []
    ) -> [WhisperPost] {
        let mod = WhisperModerationService.shared
        let normInterests = interests.map { $0.lowercased() }
        let normFollowing = Set(followingUsernames.map { $0.lowercased() })
        let normCoaches = Set(coachUsernames.map { $0.lowercased() })
        return posts
            .filter { !mod.isBanned($0.username) && !mod.isMuted($0.username) }
            .map { (post: $0, score: personalScore($0, interests: normInterests, following: normFollowing, coaches: normCoaches)) }
            .sorted { $0.score > $1.score }
            .map(\.post)
    }

    private static func personalScore(
        _ post: WhisperPost,
        interests: [String],
        following: Set<String>,
        coaches: Set<String>
    ) -> Double {
        let seen = WhisperFeedSeenTracker.shared.hasSeen(post.id)
        var s = score(for: post, seen: seen)
        let lowerCap = post.caption.lowercased()
        let kindLabel = post.kind.label.lowercased()
        let matchesInterest = interests.contains { tag in
            !tag.isEmpty && (lowerCap.contains(tag) || kindLabel.contains(tag))
        }
        if matchesInterest { s *= 1.40 }
        if following.contains(post.username.lowercased()) { s *= 0.65 }
        if !post.mediaURLs.isEmpty { s *= 1.15 }
        if post.mediaURLs.contains(where: { WhisperVideo.isVideo($0) }) { s *= 1.10 }
        if coaches.contains(post.username.lowercased()) { s *= 1.20 }
        s *= WhisperAlgorithmPreferences.shared.multiplier(for: post)
        return s
    }
}
