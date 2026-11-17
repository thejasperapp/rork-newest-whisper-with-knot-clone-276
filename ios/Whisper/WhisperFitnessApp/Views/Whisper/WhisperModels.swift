import Foundation
import SwiftUI

/// Local-only models powering the Whisper social shell. These are intentionally
/// lightweight; once we wire the backend, swap fixtures for Supabase-backed rows
/// without touching the views.

nonisolated enum WhisperPostKind: String, Codable, Sendable {
    case photo
    case workout
    case progress
    case grid

    var label: String {
        switch self {
        case .photo:    return "Photo"
        case .workout:  return "Workout"
        case .progress: return "Progress"
        case .grid:     return "Grid"
        }
    }

    var icon: String {
        switch self {
        case .photo:    return "photo"
        case .workout:  return "dumbbell.fill"
        case .progress: return "chart.line.uptrend.xyaxis"
        case .grid:     return "square.grid.2x2"
        }
    }
}

nonisolated struct WhisperPost: Identifiable, Sendable {
    let id: UUID
    let username: String
    var timeAgo: String
    let kind: WhisperPostKind
    let caption: String
    /// Optional system-symbol illustration (mock posts use SF Symbols rather
    /// than network images so the feed renders instantly with no assets).
    let symbol: String
    let accent: Color
    /// Optional Supabase-Storage hosted media URLs. When non-empty, the card
    /// renders the real image(s) instead of the symbol gradient placeholder.
    let mediaURLs: [URL]
    var likes: Int
    var comments: Int
    var liked: Bool
    /// True when this post should live in the swipeable TikTok-style Reels
    /// surface rather than the regular feed/grid. Set at compose time.
    let isReel: Bool
    /// Real wall-clock timestamp when the post was created. Threaded from
    /// the backend (`row.created_at`) so the ranking algorithm can compute
    /// real recency instead of parsing the human-readable `timeAgo` string.
    /// Nil for synthesized / placeholder posts; ranker falls back to
    /// `timeAgo` parsing in that case.
    let createdAt: Date?
    /// Explicit community pick from the composer — rendered as a plain
    /// "in Community" chip, never a hashtag in the caption.
    let communityID: String?
    let communityName: String?
    let authorUserID: String?

    init(
        id: UUID = UUID(),
        username: String,
        timeAgo: String,
        kind: WhisperPostKind,
        caption: String,
        symbol: String,
        accent: Color,
        mediaURLs: [URL] = [],
        likes: Int,
        comments: Int,
        liked: Bool = false,
        isReel: Bool = false,
        createdAt: Date? = nil,
        communityID: String? = nil,
        communityName: String? = nil,
        authorUserID: String? = nil
    ) {
        self.id = id
        self.username = username
        self.timeAgo = timeAgo
        self.kind = kind
        self.caption = caption
        self.symbol = symbol
        self.accent = accent
        self.mediaURLs = mediaURLs
        self.likes = likes
        self.comments = comments
        self.liked = liked
        self.isReel = isReel
        self.createdAt = createdAt
        self.communityID = communityID
        self.authorUserID = authorUserID
        self.communityName = communityName
    }
}

nonisolated struct WhisperStory: Identifiable, Sendable {
    let id: UUID
    let username: String
    let viewed: Bool

    init(id: UUID = UUID(), username: String, viewed: Bool = false) {
        self.id = id
        self.username = username
        self.viewed = viewed
    }
}

nonisolated struct WhisperConversation: Identifiable, Sendable {
    let id: UUID
    let username: String
    let lastMessage: String
    let timeAgo: String
    let unread: Bool

    init(id: UUID = UUID(), username: String, lastMessage: String, timeAgo: String, unread: Bool = false) {
        self.id = id
        self.username = username
        self.lastMessage = lastMessage
        self.timeAgo = timeAgo
        self.unread = unread
    }
}

nonisolated struct WhisperNotification: Identifiable, Sendable {
    enum Kind: Sendable { case like, comment, follow, friend }
    let id: UUID
    let username: String
    let kind: Kind
    let detail: String
    let timeAgo: String

    init(id: UUID = UUID(), username: String, kind: Kind, detail: String, timeAgo: String) {
        self.id = id
        self.username = username
        self.kind = kind
        self.detail = detail
        self.timeAgo = timeAgo
    }
}

extension WhisperPost {
    /// Approximate "x ago" string from an ISO8601 timestamp. Uses the
    /// project-wide tolerant parser (handles fractional seconds + the
    /// `2025-01-01 12:34:56+00` Postgres dialect) so freshly-created
    /// rows don't get stuck on "now".
    nonisolated static func relativeTime(from iso: String?) -> String {
        guard let date = WhisperBackendService.parseISO(iso) else { return "now" }
        return relativeTime(from: date)
    }

    /// Same formatter but driven by a `Date` directly so callers can
    /// pass the value they already have (`tickerNow` re-renders, etc).
    nonisolated static func relativeTime(from date: Date) -> String {
        let secs = Date().timeIntervalSince(date)
        if secs < 5 { return "now" }
        if secs < 60 { return "\(Int(secs))s" }
        if secs < 3600 { return "\(Int(secs / 60))m" }
        if secs < 86_400 { return "\(Int(secs / 3600))h" }
        if secs < 86_400 * 7 { return "\(Int(secs / 86_400))d" }
        if secs < 86_400 * 30 { return "\(Int(secs / (86_400 * 7)))w" }
        return "\(Int(secs / (86_400 * 30)))mo"
    }

    /// If this post's caption starts with the workout-embed prefix, return
    /// the decoded payload. Used by the feed card to render a rich workout
    /// tile (and let viewers save the session to their own Whisper history).
    nonisolated func decodedWorkoutPayload() -> WhisperWorkoutEmbed.Payload? {
        WhisperPost.workoutPayload(from: caption)
    }

    /// The caption text shown to the user — strips the workout-embed
    /// prefix and the web composer's post-meta line (music/location/tagged)
    /// so only the user's typed copy is visible.
    nonisolated var displayCaption: String {
        WhisperPostMeta.strip(from: WhisperPost.stripWorkoutEmbed(from: caption))
    }

    nonisolated static func workoutPayload(from caption: String) -> WhisperWorkoutEmbed.Payload? {
        guard caption.hasPrefix(WhisperWorkoutEmbed.prefix) else { return nil }
        // Embed runs until first newline (or end of string). The JSON itself
        // is single-line because `JSONEncoder` defaults to compact output.
        let body = String(caption.dropFirst(WhisperWorkoutEmbed.prefix.count))
        let line = body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        return WhisperWorkoutEmbed.decode(WhisperWorkoutEmbed.prefix + String(line))
    }

    nonisolated static func stripWorkoutEmbed(from caption: String) -> String {
        guard caption.hasPrefix(WhisperWorkoutEmbed.prefix) else { return caption }
        let body = String(caption.dropFirst(WhisperWorkoutEmbed.prefix.count))
        // Drop the embed JSON line plus any single leading newline.
        if let newlineIdx = body.firstIndex(of: "\n") {
            return String(body[body.index(after: newlineIdx)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    /// Parse a `#RRGGBB` or `RRGGBB` hex string into a SwiftUI Color.
    nonisolated static func color(fromHex hex: String?) -> Color? {
        guard var s = hex?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

/// Curated demo content. Tasteful, fitness-flavored, no lorem ipsum.
@MainActor
enum WhisperFixtures {
    static let stories: [WhisperStory] = [
        .init(username: "you", viewed: false),
        .init(username: "maya", viewed: false),
        .init(username: "devon", viewed: false),
        .init(username: "kira", viewed: false),
        .init(username: "leo", viewed: true),
        .init(username: "ren", viewed: true),
        .init(username: "sage", viewed: true),
        .init(username: "noor", viewed: true)
    ]

    static let posts: [WhisperPost] = [
        .init(
            username: "maya",
            timeAgo: "12m",
            kind: .workout,
            caption: "Morning push day done. PR on incline DB press 🔥",
            symbol: "dumbbell.fill",
            accent: Color(red: 0.96, green: 0.55, blue: 0.32),
            likes: 24, comments: 4
        ),
        .init(
            username: "devon",
            timeAgo: "1h",
            kind: .progress,
            caption: "8 weeks in. Strength up across the board. Trusting the process.",
            symbol: "chart.line.uptrend.xyaxis",
            accent: Color(red: 0.49, green: 0.78, blue: 0.55),
            likes: 88, comments: 11
        ),
        .init(
            username: "kira",
            timeAgo: "3h",
            kind: .photo,
            caption: "Sunrise run before everything got loud.",
            symbol: "sunrise.fill",
            accent: Color(red: 1.0, green: 0.72, blue: 0.42),
            likes: 142, comments: 9
        ),
        .init(
            username: "leo",
            timeAgo: "6h",
            kind: .workout,
            caption: "First 10K under 50 min. Long road from couch to here.",
            symbol: "figure.run",
            accent: Color(red: 0.42, green: 0.62, blue: 0.92),
            likes: 67, comments: 8
        ),
        .init(
            username: "ren",
            timeAgo: "yesterday",
            kind: .progress,
            caption: "Down 12 lbs. Up 30 lbs on the bar. The body listens.",
            symbol: "scalemass.fill",
            accent: Color(red: 0.78, green: 0.50, blue: 0.92),
            likes: 213, comments: 27
        )
    ]

    static let conversations: [WhisperConversation] = [
        .init(username: "maya", lastMessage: "Sent you my push routine 💪", timeAgo: "2m", unread: true),
        .init(username: "devon", lastMessage: "Lifting at 6 tomorrow?", timeAgo: "1h", unread: true),
        .init(username: "kira", lastMessage: "That sunrise pic ❤", timeAgo: "5h"),
        .init(username: "leo", lastMessage: "Splits coming in your DMs", timeAgo: "yesterday"),
        .init(username: "ren", lastMessage: "Reacted 🔥 to your post", timeAgo: "2d")
    ]

    static let notifications: [WhisperNotification] = [
        .init(username: "maya", kind: .like, detail: "liked your workout", timeAgo: "3m"),
        .init(username: "devon", kind: .comment, detail: "Strong work, keep it up.", timeAgo: "12m"),
        .init(username: "kira", kind: .follow, detail: "started following you", timeAgo: "1h"),
        .init(username: "leo", kind: .friend, detail: "accepted your friend request", timeAgo: "yesterday")
    ]

    static let exploreGrid: [WhisperPost] = posts + [
        .init(username: "noor", timeAgo: "2d", kind: .photo,
              caption: "Yoga flow, slow Sunday.",
              symbol: "figure.yoga",
              accent: Color(red: 0.52, green: 0.84, blue: 0.86),
              likes: 54, comments: 3),
        .init(username: "sage", timeAgo: "2d", kind: .workout,
              caption: "Heavy deadlift session.",
              symbol: "figure.strengthtraining.traditional",
              accent: Color(red: 0.91, green: 0.45, blue: 0.55),
              likes: 38, comments: 2),
        .init(username: "ari", timeAgo: "3d", kind: .progress,
              caption: "Sleep up, HRV up.",
              symbol: "moon.stars.fill",
              accent: Color(red: 0.45, green: 0.55, blue: 0.92),
              likes: 19, comments: 1)
    ]
}
