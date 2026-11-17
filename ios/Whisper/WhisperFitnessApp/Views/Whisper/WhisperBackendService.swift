import Foundation
import CryptoKit
import Supabase
import UIKit
import os

// MARK: - Supabase schema (run once in SQL editor, see comment block below)
//
// See `WhisperSQL.md` style block at the bottom of this file for the full SQL.

// MARK: - Row types

nonisolated struct WhisperPostRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let user_id: String
    let username: String?
    let kind: String?         // "photo" | "workout" | "progress" | "text"
    let caption: String
    let symbol: String?
    let accent_hex: String?
    let media_count: Int?
    let media_urls: [String]?
    let is_ghost: Bool?
    let is_reel: Bool?
    let likes_count: Int?
    let comments_count: Int?
    let created_at: String?
    /// Explicit community pick from the composer — data, never a hashtag.
    let community_id: String?
    let community_name: String?
}

nonisolated struct WhisperPostInsert: Codable, Sendable {
    let id: String
    let user_id: String
    let username: String
    let kind: String
    let caption: String
    let symbol: String?
    let accent_hex: String?
    let media_count: Int
    let media_urls: [String]?
    let is_ghost: Bool
    let is_reel: Bool
}

/// Fallback insert payload used when the deployed `whisper_posts` table
/// is missing the `kind` column (older schema). Lets posts succeed while
/// the user runs the migration.
nonisolated struct WhisperPostInsertLegacy: Codable, Sendable {
    let id: String
    let user_id: String
    let username: String
    let caption: String
    let symbol: String?
    let accent_hex: String?
    let media_count: Int
    let media_urls: [String]?
    let is_ghost: Bool
}

/// Fallback insert payload used when the deployed `whisper_posts` table
/// is missing the `media_count` column (very old schema). The column has
/// a default of 0 server-side once the migration runs, so dropping it
/// keeps posts working in the meantime.
nonisolated struct WhisperPostInsertNoMediaCount: Codable, Sendable {
    let id: String
    let user_id: String
    let username: String
    let kind: String
    let caption: String
    let symbol: String?
    let accent_hex: String?
    let media_urls: [String]?
    let is_ghost: Bool
}

/// Fallback insert payload used when both `kind` and `media_count` are
/// missing from the deployed schema.
nonisolated struct WhisperPostInsertMinimal: Codable, Sendable {
    let id: String
    let user_id: String
    let username: String
    let caption: String
    let symbol: String?
    let accent_hex: String?
    let media_urls: [String]?
    let is_ghost: Bool
}

nonisolated struct WhisperLikeRow: Codable, Sendable {
    let post_id: String
    let user_id: String
}

nonisolated struct WhisperCommentRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let post_id: String
    let user_id: String
    let username: String
    let body: String
    let created_at: String?
    /// Optional parent comment id — set on replies in a comment thread.
    /// Older schemas without this column decode as `nil` so root-level
    /// comments keep rendering with no migration required.
    let parent_comment_id: String?
    /// Server-maintained like counter (kept in sync by a trigger on
    /// whisper_comment_likes). Optional so older schemas still decode.
    let likes_count: Int?

    nonisolated enum CodingKeys: String, CodingKey {
        case id, post_id, user_id, username, body, created_at, parent_comment_id, likes_count
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.post_id = try c.decode(String.self, forKey: .post_id)
        self.user_id = try c.decode(String.self, forKey: .user_id)
        self.username = (try? c.decodeIfPresent(String.self, forKey: .username)) ?? ""
        self.body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
        self.created_at = try? c.decodeIfPresent(String.self, forKey: .created_at)
        self.parent_comment_id = try? c.decodeIfPresent(String.self, forKey: .parent_comment_id)
        self.likes_count = try? c.decodeIfPresent(Int.self, forKey: .likes_count)
    }
    init(id: String, post_id: String, user_id: String, username: String, body: String, created_at: String?, parent_comment_id: String? = nil, likes_count: Int? = nil) {
        self.id = id
        self.post_id = post_id
        self.user_id = user_id
        self.username = username
        self.body = body
        self.created_at = created_at
        self.parent_comment_id = parent_comment_id
        self.likes_count = likes_count
    }
}

nonisolated struct WhisperCommentInsert: Codable, Sendable {
    let post_id: String
    let user_id: String
    let username: String
    let body: String
}

/// One row in the "who liked this post" list. Surfaced when the user taps
/// the likes counter underneath a post card.
nonisolated struct WhisperLiker: Decodable, Sendable, Identifiable, Hashable {
    let user_id: String
    let username: String
    let display_name: String?
    let profile_image_url: String?
    nonisolated var id: String { user_id }
}

nonisolated struct WhisperCommentLikeRow: Codable, Sendable {
    let comment_id: String
    let user_id: String
}

nonisolated struct WhisperMessageRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let from_user_id: String
    let from_username: String
    let to_user_id: String
    let to_username: String
    let body: String
    let created_at: String?
    /// ISO timestamp the recipient first opened the thread and we marked
    /// this row read. Nil = unread. Column is optional in the schema; the
    /// decoder handles its absence gracefully.
    var read_at: String?
    let thread_id: String?
    let logical_group_message_id: String?
    let conversationKind: WhisperConversationKind
    /// Candidate metadata never establishes provenance, grants or signing authority.
    let notesCard: WhisperNotesCardCandidate?

    init(
        id: String,
        from_user_id: String,
        from_username: String,
        to_user_id: String,
        to_username: String,
        body: String,
        created_at: String?,
        read_at: String? = nil,
        thread_id: String? = nil,
        logical_group_message_id: String? = nil
    ) {
        self.id = id
        self.from_user_id = from_user_id
        self.from_username = from_username
        self.to_user_id = to_user_id
        self.to_username = to_username
        self.body = body
        self.notesCard = nil
        self.created_at = created_at
        self.read_at = read_at
        self.thread_id = thread_id
        self.logical_group_message_id = logical_group_message_id
        self.conversationKind = .resolve(threadID: thread_id, first: from_user_id, second: to_user_id)
    }

    // Decode defensively: if the deployed `whisper_messages` table has
    // had the `from_username` / `to_username` columns dropped (we ship
    // a progressive-drop in `sendMessage`), Postgres returns rows
    // without those keys. The original synthesized decoder would throw
    // and the entire SELECT response failed to decode — wiping the
    // local `conversations` map and making just-sent program / workout
    // messages disappear a moment after they appeared via realtime.
    //
    // Whisper's CoachModeService.sendProgram writes a separate wire shape:
    //   { thread_id, from_user_id, from_username?, to_user_id,
    //     embed: { kind: "program", payload: <GeneratedProgram JSON> } }
    // with NO `body` column. We detect that `embed` here and synthesize
    // the same `::whisper-program-v1::<json>` body string that the rest
    // of Whisper already renders — so program DMs sent from Whisper land
    // in the chat as a real program card with no other plumbing.
    nonisolated enum CodingKeys: String, CodingKey {
        case id, from_user_id, from_username, to_user_id, to_username, body, created_at, embed, read_at, thread_id, logical_group_message_id
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.from_user_id = try c.decode(String.self, forKey: .from_user_id)
        self.to_user_id = try c.decode(String.self, forKey: .to_user_id)
        var decodedBody = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        let fromUsername = (try? c.decodeIfPresent(String.self, forKey: .from_username)) ?? ""
        self.from_username = fromUsername
        self.to_username = (try? c.decodeIfPresent(String.self, forKey: .to_username)) ?? ""
        self.created_at = try c.decodeIfPresent(String.self, forKey: .created_at)
        self.read_at = try? c.decodeIfPresent(String.self, forKey: .read_at)
        self.thread_id = try c.decodeIfPresent(String.self, forKey: .thread_id)
        self.logical_group_message_id = try c.decodeIfPresent(String.self, forKey: .logical_group_message_id)
        self.conversationKind = .resolve(threadID: thread_id, first: from_user_id, second: to_user_id)

        let candidate = try? c.decodeIfPresent(WhisperNotesCardCandidate.self, forKey: .embed)
        self.notesCard = candidate?.deliveryID == UUID(uuidString: id) ? candidate : nil

        // Look for a Whisper-style embed column and convert it into the
        // prefixed body the existing chat / inbox renderers understand.
        // Coach proposals (kind == "coach_proposal") need to override any
        // existing body — Whisper now sets `body = summary` as a fallback,
        // but we want the inline card, not the plain-text bubble.
        // Coach nutrition embeds (program-style, post-Nov-2026) MUST win
        // over the legacy coach_proposal wrapper — same kind name space
        // but a different shape, and we want the new banner not the old
        // generic suggestion card.
        if let wire = try? c.decodeIfPresent(WhisperEmbedWire.CoachMacrosWire.self, forKey: .embed) {
            decodedBody = wire.toWhisperBody(coachUsername: fromUsername)
        } else if let wire = try? c.decodeIfPresent(WhisperEmbedWire.CoachDietPlanWire.self, forKey: .embed) {
            decodedBody = wire.toWhisperBody(coachUsername: fromUsername)
        } else if let wire = try? c.decodeIfPresent(WhisperEmbedWire.CoachProposalWire.self, forKey: .embed) {
            decodedBody = wire.toWhisperBody(coachUsername: fromUsername)
        } else if decodedBody.isEmpty {
            if let wire = try? c.decodeIfPresent(WhisperEmbedWire.ProgramWire.self, forKey: .embed) {
                decodedBody = wire.toWhisperBody(coachUsername: fromUsername)
            } else if let wire = try? c.decodeIfPresent(WhisperEmbedWire.WorkoutWire.self, forKey: .embed) {
                decodedBody = wire.toWhisperBody()
            }
        }
        self.body = decodedBody
    }

    // Explicit encoder — we added a decode-only `embed` case to
    // CodingKeys, which prevents Swift from synthesizing Encodable.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(from_user_id, forKey: .from_user_id)
        try c.encode(from_username, forKey: .from_username)
        try c.encode(to_user_id, forKey: .to_user_id)
        try c.encode(to_username, forKey: .to_username)
        try c.encode(body, forKey: .body)
        try c.encodeIfPresent(created_at, forKey: .created_at)
        try c.encodeIfPresent(read_at, forKey: .read_at)
        try c.encodeIfPresent(thread_id, forKey: .thread_id)
        try c.encodeIfPresent(logical_group_message_id, forKey: .logical_group_message_id)
    }
}

// MARK: - Embed wire decoders (Whisper-side coach DMs)
//
// Whisper writes program/workout DMs into a separate `embed` jsonb column
// rather than the legacy `body` string. These types decode that shape
// and bridge it back into the prefixed-body format the rest of the
// Whisper UI already handles — so we don't have to touch every renderer.

nonisolated enum WhisperEmbedWire {
    enum Keys: String, CodingKey { case kind, payload }

    nonisolated struct ProgramWire: Decodable, Sendable {
        let payload: GeneratedProgram
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            let kind = try c.decode(String.self, forKey: .kind)
            guard kind == "program" else {
                throw DecodingError.dataCorruptedError(
                    forKey: .kind, in: c,
                    debugDescription: "not a program embed (kind=\(kind))"
                )
            }
            self.payload = try c.decode(GeneratedProgram.self, forKey: .payload)
        }
        func toWhisperBody(coachUsername: String) -> String {
            let g = payload
            let days: [WhisperProgramDay] = g.workoutDays.map { d in
                WhisperProgramDay(
                    id: d.id,
                    name: d.dayName,
                    focus: d.focus,
                    exercises: d.exercises.map { ex in
                        WhisperProgramExercise(
                            id: ex.id,
                            name: ex.name,
                            sets: ex.sets,
                            reps: ex.reps,
                            restSeconds: ex.restSeconds,
                            note: ex.notes.isEmpty ? nil : ex.notes
                        )
                    }
                )
            }
            let bridged = WhisperProgramEmbed.Payload(
                id: g.id.uuidString,
                coachUsername: coachUsername,
                title: g.title,
                focus: g.goal.rawValue,
                weeks: g.weeks,
                sessionsPerWeek: g.daysPerWeek,
                summary: g.overview,
                days: days
            )
            guard let data = try? JSONEncoder().encode(bridged),
                  let json = String(data: data, encoding: .utf8) else { return "" }
            return WhisperProgramEmbed.prefix + json
        }
    }

    /// Whisper writes coach-proposal DMs into the `embed` jsonb column as:
    ///   { kind: "coach_proposal", proposal_id, proposal_kind, summary, note? }
    /// We bridge that into the `::whisper-coach-proposal-v1::<json>` body
    /// the existing `WhisperCoachProposalInlineCard` renderer already
    /// handles — so non-program kinds (macros / diet plan / swap / note)
    /// land as tappable cards with deep-link buttons, not plain text.
    nonisolated struct CoachProposalWire: Decodable, Sendable {
        let proposalID: String
        let proposalKind: String
        let summary: String
        let note: String?

        nonisolated enum CoachKeys: String, CodingKey {
            case kind, proposal_id, proposal_kind, summary, note
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CoachKeys.self)
            let kind = try c.decode(String.self, forKey: .kind)
            guard kind == "coach_proposal" else {
                throw DecodingError.dataCorruptedError(
                    forKey: .kind, in: c,
                    debugDescription: "not a coach_proposal embed (kind=\(kind))"
                )
            }
            self.proposalID = try c.decode(String.self, forKey: .proposal_id)
            self.proposalKind = (try? c.decodeIfPresent(String.self, forKey: .proposal_kind)) ?? "note"
            self.summary = (try? c.decodeIfPresent(String.self, forKey: .summary)) ?? ""
            self.note = try? c.decodeIfPresent(String.self, forKey: .note)
        }

        func toWhisperBody(coachUsername: String) -> String {
            let payload = WhisperCoachProposalEmbed.Payload(
                id: proposalID,
                kind: proposalKind,
                coachUsername: coachUsername.isEmpty ? "your coach" : coachUsername,
                summary: summary,
                note: note
            )
            return WhisperCoachProposalEmbed.encode(payload)
        }
    }

    /// Program-style coach macros embed (Nov-2026 contract). Wire shape:
    ///   { kind: "coach_macros", payload: { calories?, protein_g?, carbs_g?, fat_g? } }
    /// All payload fields optional — coach sends only what changes.
    nonisolated struct CoachMacrosWire: Decodable, Sendable {
        let payload: PayloadShape
        nonisolated struct PayloadShape: Decodable, Sendable {
            let calories: Int?
            let protein_g: Double?
            let carbs_g: Double?
            let fat_g: Double?
            let water_cups: Int?
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            let kind = try c.decode(String.self, forKey: .kind)
            guard kind == "coach_macros" else {
                throw DecodingError.dataCorruptedError(
                    forKey: .kind, in: c,
                    debugDescription: "not a coach_macros embed (kind=\(kind))"
                )
            }
            self.payload = try c.decode(PayloadShape.self, forKey: .payload)
        }
        func toWhisperBody(coachUsername: String) -> String {
            let bridged = WhisperCoachMacrosEmbed.Payload(
                id: UUID().uuidString,
                coachUsername: coachUsername.isEmpty ? "your coach" : coachUsername,
                calories: payload.calories,
                protein_g: payload.protein_g,
                carbs_g: payload.carbs_g,
                fat_g: payload.fat_g,
                water_cups: payload.water_cups
            )
            return WhisperCoachMacrosEmbed.encode(bridged)
        }
    }

    /// Program-style coach diet-plan embed (Nov-2026 contract). Wire shape:
    ///   { kind: "coach_diet_plan",
    ///     payload: { name?, calories, protein_g, carbs_g, fat_g } }
    /// `name` defaults to "Coach plan". All macros required.
    nonisolated struct CoachDietPlanWire: Decodable, Sendable {
        let payload: PayloadShape
        nonisolated struct PayloadShape: Decodable, Sendable {
            let name: String?
            let calories: Int
            let protein_g: Double
            let carbs_g: Double
            let fat_g: Double
            let plan_id: String?
            let dietary_preference: String?
            let goal: String?
            let days_count: Int?
            let meals_per_day: Int?
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            let kind = try c.decode(String.self, forKey: .kind)
            guard kind == "coach_diet_plan" else {
                throw DecodingError.dataCorruptedError(
                    forKey: .kind, in: c,
                    debugDescription: "not a coach_diet_plan embed (kind=\(kind))"
                )
            }
            self.payload = try c.decode(PayloadShape.self, forKey: .payload)
        }
        func toWhisperBody(coachUsername: String) -> String {
            let bridged = WhisperCoachDietPlanEmbed.Payload(
                id: UUID().uuidString,
                coachUsername: coachUsername.isEmpty ? "your coach" : coachUsername,
                name: (payload.name?.isEmpty == false ? payload.name! : "Coach plan"),
                calories: payload.calories,
                protein_g: payload.protein_g,
                carbs_g: payload.carbs_g,
                fat_g: payload.fat_g,
                plan_id: payload.plan_id,
                dietary_preference: payload.dietary_preference,
                goal: payload.goal,
                days_count: payload.days_count,
                meals_per_day: payload.meals_per_day
            )
            return WhisperCoachDietPlanEmbed.encode(bridged)
        }
    }

    nonisolated struct WorkoutWire: Decodable, Sendable {
        let payload: WorkoutPayload
        nonisolated struct WorkoutPayload: Decodable, Sendable {
            // Tolerate both Whisper's WorkoutSessionRecord shape and the
            // existing WhisperWorkoutEmbed.Payload shape — every key is
            // optional and we fall back gracefully.
            let id: String?
            let displayName: String?
            let focus: String?
            let durationSeconds: Int?
            let duration: Double?
            let calories: Int?
            let caloriesBurned: Double?
            let exerciseNames: [String]?
            let exercises: [WhisperExerciseLite]?
            let totalSets: Int?
            let date: Double?
            nonisolated struct WhisperExerciseLite: Decodable, Sendable {
                let exerciseName: String?
                let sets: [WhisperSetLite]?
            }
            nonisolated struct WhisperSetLite: Decodable, Sendable {}
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            let kind = try c.decode(String.self, forKey: .kind)
            guard kind == "workout" else {
                throw DecodingError.dataCorruptedError(
                    forKey: .kind, in: c,
                    debugDescription: "not a workout embed (kind=\(kind))"
                )
            }
            self.payload = try c.decode(WorkoutPayload.self, forKey: .payload)
        }
        func toWhisperBody() -> String {
            let p = payload
            let bridged = WhisperWorkoutEmbed.Payload(
                id: p.id ?? UUID().uuidString,
                displayName: p.displayName ?? "Workout",
                focus: p.focus ?? "",
                durationSeconds: p.durationSeconds ?? Int(p.duration ?? 0),
                calories: p.calories ?? Int(p.caloriesBurned ?? 0),
                exerciseNames: p.exerciseNames ?? (p.exercises?.compactMap { $0.exerciseName } ?? []),
                totalSets: p.totalSets ?? (p.exercises?.reduce(0) { $0 + ($1.sets?.count ?? 0) } ?? 0),
                date: p.date ?? Date().timeIntervalSince1970
            )
            guard let data = try? JSONEncoder().encode(bridged),
                  let json = String(data: data, encoding: .utf8) else { return "" }
            return WhisperWorkoutEmbed.prefix + json
        }
    }
}

nonisolated struct WhisperMessageInsert: Codable, Sendable {
    let from_user_id: String
    let from_username: String
    let to_user_id: String
    let to_username: String
    let body: String
}

nonisolated struct WhisperWorkoutRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let user_id: String
    let display_name: String
    let focus: String
    let duration_seconds: Int
    let calories: Int
    let exercises_count: Int
    let performed_at: String
    let created_at: String?
}

nonisolated struct WhisperWorkoutInsert: Codable, Sendable {
    let id: String
    let user_id: String
    let display_name: String
    let focus: String
    let duration_seconds: Int
    let calories: Int
    let exercises_count: Int
    let performed_at: String
}

nonisolated struct WhisperConversationSummary: Identifiable, Sendable, Hashable {
    let otherUserID: String
    let otherUsername: String
    let lastMessage: String
    let lastDate: Date
    /// True when the most recent message in the thread was sent by the
    /// current user. Used by the inbox preview to render "You sent a chart"
    /// vs "@friend sent a chart".
    var lastFromMe: Bool = false
    /// True when the latest inbound message has been read by the current
    /// user (or when there's no inbound — i.e. we sent the last one). Drives
    /// the bold-preview + blue-dot unread indicator in the inbox.
    var lastReadByMe: Bool = true
    var kind: WhisperConversationKind = .direct
    nonisolated var id: String { kind.localKey(peer: otherUserID) }
}

/// Real Supabase-backed posts, likes, comments, and direct messages for
/// Whisper. Falls back gracefully when the user isn't signed in (guest /
/// local mode) — UI still renders fixtures, just nothing persists.
@MainActor
@Observable
final class WhisperBackendService {
    static let shared = WhisperBackendService()

    private let client = SupabaseService.shared.client

    var posts: [WhisperPostRow] = []
    var myPosts: [WhisperPostRow] = []
    private(set) var myPostsLoadedGeneration: UUID?
    private(set) var postsLoadError: String?
    private(set) var myPostsLoadError: String?
    private(set) var deletedPostIDs: Set<String> = []
    private var deletingPostIDs: Set<String> = []

    func ownsPost(_ id: String) -> Bool {
        guard isSignedInRemotely else { return false }
        return (myPosts + posts).contains { $0.id.lowercased() == id.lowercased() && $0.user_id.lowercased() == currentUID.lowercased() }
    }
    var myLikedPostIDs: Set<String> = []
    var commentsByPostID: [String: [WhisperCommentRow]] = [:]
    var commentLoadErrors: [String: String] = [:]
    @ObservationIgnored private var commentFetches: [String: Task<[WhisperCommentRow], Never>] = [:]
    @ObservationIgnored private var commentFetchIDs: [String: UUID] = [:]
    @ObservationIgnored private var commentFetchedAt: [String: Date] = [:]
    /// Comment IDs the current user has liked. Populated alongside
    /// `fetchComments` and updated by `toggleCommentLike` so the heart
    /// icon on each comment row stays in sync.
    var myLikedCommentIDs: Set<String> = []
    /// Mutations to this array must be followed by `cacheWidgetSnapshot()`
    /// — `@Observable`'s macro strips `didSet` observers from tracked
    /// properties, so we sync explicitly at every write site below.
    var threads: [WhisperConversationSummary] = []
    private(set) var inboxHasMore = false
    private(set) var isLoadingInboxPage = false
    private(set) var inboxPageError: String?
    private(set) var inboxRetryOlder = false
    var inboxContinuationID: String { inboxNext?.id ?? "end" }
    @ObservationIgnored private var inboxRows: [WhisperInboxSummaryRow] = []
    @ObservationIgnored private var inboxMutationRows: [String: WhisperMessageRow] = [:]
    @ObservationIgnored private var inboxNext: WhisperHistoryCursor?
    @ObservationIgnored private var inboxPageCount = 1
    @ObservationIgnored private var inboxRevision = UUID()
    @ObservationIgnored private var inboxRequestID = UUID()
    @ObservationIgnored private var inboxTask: Task<Void, Never>?
    @ObservationIgnored private var inboxTaskOlder = false
    @ObservationIgnored private var inboxRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var unsendingInboxIDs: Set<String> = []
    private(set) var historyStates: [String: WhisperHistoryState] = [:]
    @ObservationIgnored private var activeHistoryScopes: [String: (peer: String, kind: WhisperConversationKind)] = [:]
    @ObservationIgnored private var activeGroupHistoryScopes: Set<UUID> = []
    @ObservationIgnored private var historyRequestIDs: [String: UUID] = [:]
    // Only retained while SELECTs are active, including deletes of rows that
    // were outside the currently visible history when the request started.
    @ObservationIgnored private var historyDeletedIDs: Set<String> = []
    @ObservationIgnored private var storedConversations: [String: [WhisperMessageRow]] = [:]
    private(set) var messageRevision: UInt64 = 0
    var conversations: [String: [WhisperMessageRow]] {
        get { _ = messageRevision; return storedConversations }
        set {
            storedConversations = newValue
            messageRevision &+= 1
            threadIndex = [:]
        }
    }
    /// Message IDs the current user has hidden via "Delete for me". The set
    /// is persisted to `UserDefaults` so hidden bubbles stay hidden across
    /// launches. Hiding is purely client-side — the row remains in Supabase
    /// and on the other person's device, mirroring iMessage/IG semantics.
    var locallyDeletedMessageIDs: Set<String> = {
        let arr = (AccountStorage.object(forKey: "whisper_local_deleted_msg_ids") as? [String]) ?? []
        return Set(arr)
    }()
    /// Cached public profiles for every user the current user has a DM
    /// thread with — used by the inbox + thread view to show the correct
    /// avatar image and display name (instead of falling back to the
    /// current user's avatar when the username collides).
    var threadProfiles: [String: WhisperPublicProfile] = [:]
    /// Cached public profiles keyed by `user_id` for every author currently
    /// visible in the feed. Populated alongside `fetchPosts` so the feed +
    /// post cards can render correct usernames and avatars for other users
    /// without firing one network request per row.
    var postAuthorProfiles: [String: WhisperPublicProfile] = [:]
    /// Lowercased-username -> avatar URL string. Mirror of `postAuthorProfiles`
    /// keyed by handle so `WhisperAvatar` (which only knows the username)
    /// can resolve a remote photo for non-current users.
    var authorAvatarURLByUsername: [String: String] = [:]
    /// Lowercased usernames we already attempted an on-demand avatar lookup
    /// for this session — caps `hydrateAvatar(forUsername:)` at one network
    /// round-trip per handle so feeds full of photo-less users don't storm
    /// the backend.
    private var avatarHydrationAttempted: Set<String> = []
    /// User IDs we've already tried to hydrate a profile row for — dedupes
    /// the on-demand username self-heal so each id is fetched at most once
    /// per session.
    private var profileHydrationAttempted: Set<String> = []
    var workouts: [WhisperWorkoutRow] = []
    var lastError: String?
    /// When set, the UI presents a sheet showing this SQL with a one-tap
    /// Copy button. Used for the whisper_messages FK fix that the user
    /// must paste into Supabase → SQL editor once.
    var pendingFixSQL: String?
    var pendingFixTitle: String?
    var isLoadingPosts: Bool = false

    /// Records an error into `lastError` while ignoring `CancellationError`,
    /// which is just SwiftUI tearing down a `.task` when navigation changes
    /// — not a real failure the user needs to see.
    private func record(_ error: Error) {
        if error is CancellationError { return }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        if ns.domain == "Swift.CancellationError" { return }
        let msg = error.localizedDescription
        // Server-side RLS misconfiguration — surfaces as a noisy red banner
        // on every screen. Log it but don't pollute the UI; the user can't
        // fix it from inside the app.
        let lower = msg.lowercased()
        if lower.contains("infinite recursion") || lower.contains("policy for relation") {
            print("[Whisper] suppressed RLS error: \(msg)")
            return
        }
        lastError = msg
    }

    private var currentUID: String { AccountStorage.currentUserID }

    /// Resolves the display username for a row from the backend. Prefers
    /// the stored `row.username`, falls back to the local user's saved
    /// handle when the row belongs to the current user (so a freshly
    /// posted optimistic row never renders the literal "you" to its own
    /// author), and finally falls back to a neutral "user" so we never
    /// surface the placeholder string in the UI.
    func resolvedAuthorUsername(rowUsername: String?, rowUserID: String?) -> String {
        // The web app resolves author usernames by joining `whisper_profiles`
        // on `user_id`, so the canonical Whisper profile is always the source
        // of truth. To match that behavior on iOS, we prefer the cached
        // `whisper_profiles` username over the stored `whisper_posts.username`
        // field, which can be stale if a user changed their handle.
        let placeholders: Set<String> = ["you", "user", ""]
        let myUID = currentUID.lowercased()
        if let rowUID = rowUserID?.lowercased(), !rowUID.isEmpty, rowUID == myUID {
            let me = WhisperUserService.shared.me?.username
                ?? LeaderboardService.shared.savedUsername
                ?? AuthenticationService.shared.currentUser.username
            if let me, !me.isEmpty, !placeholders.contains(me.lowercased()) { return me }
        }
        // Prefer the canonical Whisper profile username (matches web).
        if let rowUID = rowUserID, !rowUID.isEmpty {
            if let cached = cachedUsername(forUserID: rowUID) {
                return cached
            }
            // Self-heal: no cached profile for this author yet — fetch the
            // row once in the background so the next render shows the real
            // handle instead of "user".
            Task { await hydrateProfile(forUserID: rowUID) }
        }
        // Fallback to the stored row username only when the profile hasn't loaded yet.
        if let stored = rowUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
           !stored.isEmpty, !placeholders.contains(stored.lowercased()) {
            return stored
        }
        return "user"
    }

    /// Cached username for a user id, checked across BOTH profile caches
    /// (post authors + DM threads), exact then case-insensitive. Returns
    /// nil when unknown — and kicks off a one-shot background hydration so
    /// the handle appears on the next render.
    func cachedUsername(forUserID userID: String) -> String? {
        let placeholders: Set<String> = ["you", "user", ""]
        if let u = postAuthorProfiles[userID]?.username, !placeholders.contains(u.lowercased()) { return u }
        if let u = threadProfiles[userID]?.username, !placeholders.contains(u.lowercased()) { return u }
        let lower = userID.lowercased()
        for (key, profile) in postAuthorProfiles where key.lowercased() == lower {
            if let u = profile.username, !u.isEmpty, !placeholders.contains(u.lowercased()) { return u }
        }
        for (key, profile) in threadProfiles where key.lowercased() == lower {
            if let u = profile.username, !u.isEmpty, !placeholders.contains(u.lowercased()) { return u }
        }
        Task { await hydrateProfile(forUserID: userID) }
        return nil
    }

    /// On-demand user_id → profile hydration. Fetches the profile row once
    /// per session and merges it into every cache so usernames + avatars
    /// self-heal anywhere a surface only knows the author's id.
    func hydrateProfile(forUserID userID: String) async {
        let key = userID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty, key != "ember", key != "guest", !key.hasPrefix("local") else { return }
        guard !profileHydrationAttempted.contains(key), isRemote else { return }
        profileHydrationAttempted.insert(key)
        let generation = AccountStorage.generation
        // Join the batch before falling back to the single-author recovery path.
        // Capture this ID so a feed-window replacement cannot strand it.
        if posts.contains(where: { $0.user_id.lowercased() == key }) {
            if postEnrichmentTask == nil { schedulePostEnrichment(generation: generation) }
            if let batch = postEnrichmentTask { await batch.value }
            guard generation == AccountStorage.generation, !Task.isCancelled else { return }
            if postAuthorProfiles.keys.contains(where: { $0.lowercased() == key }) { return }
        }
        let map = await fetchPublicProfiles(userIDs: [userID])
        guard generation == AccountStorage.generation, !Task.isCancelled else { return }
        guard !map.isEmpty else { return }
        mergeAuthorProfiles(map, requestedUIDs: [userID])
        for (uid, profile) in map {
            if threadProfiles[uid] == nil { threadProfiles[uid] = profile }
        }
    }

    /// Avatar URL string for a username, resolved from the cached author
    /// profiles populated by `hydrateAuthorProfiles`. Used by `WhisperAvatar`
    /// so non-current users render their real profile photo in the feed.
    func avatarURLString(forUsername username: String) -> String? {
        let key = username.lowercased()
        guard !key.isEmpty else { return nil }
        return authorAvatarURLByUsername[key]
    }

    /// Batch-fetches public profiles for every distinct author in the
    /// current `posts` cache and merges them into `postAuthorProfiles` /
    /// `authorAvatarURLByUsername`. Cheap (one round-trip) and idempotent —
    /// rows already cached are skipped.
    func hydrateAuthorProfiles() async {
        let generation = AccountStorage.generation
        let uids = Set(posts.map { $0.user_id }).subtracting(postAuthorProfiles.keys)
        guard !uids.isEmpty else { return }
        let map = await fetchPublicProfiles(userIDs: Array(uids))
        guard !Task.isCancelled, generation == AccountStorage.generation else { return }
        mergeAuthorProfiles(map, requestedUIDs: uids)
    }

    /// Merges a fetched `[userID: profile]` map into the author caches.
    /// Profiles are stored under BOTH the database id casing and the exact
    /// uid casing the caller requested — Postgres uuid columns normalize to
    /// lowercase while some legacy rows carry mixed-case user_ids, and a
    /// casing mismatch here made `subtracting(postAuthorProfiles.keys)`
    /// treat the row as never-fetched, so certain "random" profiles never
    /// hydrated their username/avatar.
    private func mergeAuthorProfiles(_ map: [String: WhisperPublicProfile], requestedUIDs: Set<String>) {
        guard !map.isEmpty else { return }
        var byLowerUID: [String: WhisperPublicProfile] = [:]
        for (uid, profile) in map {
            postAuthorProfiles[uid] = profile
            byLowerUID[uid.lowercased()] = profile
            if let uname = profile.username?.lowercased(), !uname.isEmpty,
               let url = profile.profile_image_url, !url.isEmpty {
                authorAvatarURLByUsername[uname] = url
            }
        }
        for uid in requestedUIDs where postAuthorProfiles[uid] == nil {
            if let profile = byLowerUID[uid.lowercased()] {
                postAuthorProfiles[uid] = profile
            }
        }
    }

    /// On-demand username → avatar hydration used by `WhisperAvatar` as a
    /// self-heal: whenever an avatar renders with no cached photo URL (the
    /// surface mounted before the batch author hydration ran, or the user
    /// never appeared in the feed), this fetches their public profile row
    /// once per session and merges it into the avatar cache.
    func hydrateAvatar(forUsername username: String) async {
        let key = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty, key != "user", key != "you", key != "ember" else { return }
        guard authorAvatarURLByUsername[key] == nil else { return }
        guard !avatarHydrationAttempted.contains(key) else { return }
        avatarHydrationAttempted.insert(key)
        guard isRemote else { return }

        // Prefer `whisper_profiles` (the canonical Whisper username source) so
        // avatars and display names stay in sync with the web app and don't
        // regress to stale `profiles` rows.
        nonisolated struct WPRow: Codable, Sendable {
            let user_id: String
            let username: String
            let display_name: String?
            let profile_image_url: String?
        }
        var resolved: WhisperPublicProfile?
        do {
            let rows: [WPRow] = try await client
                .from("whisper_profiles")
                .select("user_id,username,display_name,profile_image_url")
                .ilike("username", pattern: key)
                .limit(1)
                .execute()
                .value
            if let row = rows.first {
                resolved = WhisperPublicProfile(
                    id: row.user_id,
                    username: row.username,
                    display_name: row.display_name,
                    profile_image_url: row.profile_image_url,
                    is_verified: nil
                )
            }
        } catch {
            // Fall through to legacy `profiles` lookup below.
        }

        if resolved == nil {
            do {
                let rows: [WhisperPublicProfile] = try await client
                    .from("profiles")
                    .select("id,username,display_name,profile_image_url,is_verified")
                    .ilike("username", pattern: key)
                    .limit(1)
                    .execute()
                    .value
                resolved = rows.first
            } catch {
                return
            }
        }

        guard let profile = resolved else { return }
        if postAuthorProfiles[profile.id] == nil {
            postAuthorProfiles[profile.id] = profile
        }
        if let uname = profile.username?.lowercased(), !uname.isEmpty,
           let url = profile.profile_image_url, !url.isEmpty {
            authorAvatarURLByUsername[uname] = url
        }
    }

    /// Backfills `postAuthorProfiles` with the profile rows for every
    /// distinct comment author in `commentsByPostID[postID]` whose UID is
    /// not already cached. Used after `fetchComments` so any commenter
    /// rendered with a missing `username` is upgraded to their real handle
    /// instead of the generic "user" placeholder.
    func hydrateCommentAuthors(postID: String) async {
        let generation = AccountStorage.generation
        let rows = commentsByPostID[postID] ?? []
        let uids = Set(
            rows
                .map { $0.user_id }
                .filter { !$0.isEmpty && !$0.hasPrefix("local-") }
        ).subtracting(postAuthorProfiles.keys)
        guard !uids.isEmpty else { return }
        let map = await fetchPublicProfiles(userIDs: Array(uids))
        guard !Task.isCancelled, generation == AccountStorage.generation else { return }
        mergeAuthorProfiles(map, requestedUIDs: uids)
    }
    /// Lowercased current UID — Postgres normalizes uuid columns to lowercase,
    /// so all thread keying / `from_user_id == me` comparisons must lowercase
    /// both sides. Without this, a user whose AccountStorage UID has any
    /// uppercase characters ends up grouped into a self-thread (the inbox
    /// shows their own name/avatar and replies disappear into it).
    private var currentUIDLower: String { currentUID.lowercased() }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    /// Whether the user has a real Supabase auth session, gating writes that
    /// the RLS policies require. UI uses this to show the Whisper auth gate.
    var isSignedInRemotely: Bool {
        isRemote && client.auth.currentUser?.id.uuidString.lowercased() == currentUIDLower
    }

    private static let mediaBucket = "whisper-media"
    private var messagesChannel: RealtimeChannelV2?
    private var messagesTask: Task<Void, Never>?
    private var postsChannel: RealtimeChannelV2?
    private var postsTask: Task<Void, Never>?

    /// Deduplicates rapid duplicate sends (same recipient + body within a
    /// short window). Prevents the bubble from appearing twice when the user
    /// double-taps Send before the first request returns.
    private var inFlightSendKeys: Set<String> = []

    /// Shared ISO parsers. Creating an `ISO8601DateFormatter` costs tens of
    /// microseconds — `parseISO` used to build TWO per call and the thread
    /// sort called it twice per comparison, on every render. Foundation's own
    /// `JSONDecoder.iso8601` shares one formatter the same way; they're
    /// immutable after configuration and safe to share across threads.
    nonisolated(unsafe) private static let isoWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Parses Supabase ISO8601 timestamps including fractional seconds. The
    /// default `ISO8601DateFormatter` silently fails on `2025-...Z` strings
    /// that include `.123456` microseconds, which scrambles thread ordering.
    nonisolated static func parseISO(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let d = isoWithFractional.date(from: raw) { return d }
        if let d = isoPlain.date(from: raw) { return d }
        // Postgres can also return `2025-01-01 12:34:56.789+00` — normalize.
        let normalized = raw.replacingOccurrences(of: " ", with: "T")
        return isoWithFractional.date(from: normalized) ?? isoPlain.date(from: normalized)
    }

    /// True for a group-chat fan-out row (`::wg-v1::…`). Group traffic rides
    /// 1:1 rows on the wire but belongs ONLY to the group thread — it must
    /// never surface as a personal message, an inbox row, or an unread dot.
    nonisolated static func isGroupWire(_ body: String) -> Bool {
        body.hasPrefix(WhisperGroupChatService.headerPrefix)
    }

    private init() {
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.invalidateReferencedPosts() }
        }
    }

    // MARK: - Storage (media uploads)

    /// Uploads each JPEG-encoded image to the `whisper-media` bucket under
    /// `<uid>/<postID>/<index>.jpg` and returns public URL strings.
    func uploadMedia(datas: [Data], postID: String) async -> [String] {
        guard isRemote, !datas.isEmpty else { return [] }
        let owner = currentUID
        let generation = AccountStorage.generation
        var urls: [String] = []
        for (idx, raw) in datas.enumerated() {
            guard !Task.isCancelled, generation == AccountStorage.generation, currentUID == owner else { return [] }
            let jpeg = await Task.detached(priority: .userInitiated) {
                UIImage(data: raw)?.jpegData(compressionQuality: 0.82)
            }.value
            guard let jpeg, !Task.isCancelled, generation == AccountStorage.generation, currentUID == owner else { return [] }
            let path = "\(owner)/\(postID)/\(idx).jpg"
            do {
                _ = try await client.storage
                    .from(Self.mediaBucket)
                    .upload(
                        path,
                        data: jpeg,
                        options: FileOptions(
                            cacheControl: "3600",
                            contentType: "image/jpeg",
                            upsert: true
                        )
                    )
                let publicURL = try client.storage
                    .from(Self.mediaBucket)
                    .getPublicURL(path: path)
                guard !Task.isCancelled, generation == AccountStorage.generation, currentUID == owner else { return [] }
                urls.append(publicURL.absoluteString)
            } catch {
                guard generation == AccountStorage.generation else { return [] }
                record(error)
                return []
            }
        }
        return urls
    }

    /// Dedicated alpha-preserving Story cutout path; ordinary photos remain JPEG.
    func uploadStoryCutout(_ png: Data, id: UUID) async -> String? {
        guard isRemote, png.count <= 12_000_000, png.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else { return nil }
        let owner = currentUID
        let generation = AccountStorage.generation
        guard UUID(uuidString: owner) != nil, !Task.isCancelled else { return nil }
        let path = "\(owner)/story-cutouts/\(id.uuidString.lowercased()).png"
        do {
            _ = try await client.storage.from(Self.mediaBucket).upload(path, data: png, options: FileOptions(cacheControl: "3600", contentType: "image/png", upsert: false))
            guard !Task.isCancelled, generation == AccountStorage.generation, currentUID == owner else { return nil }
            return try client.storage.from(Self.mediaBucket).getPublicURL(path: path).absoluteString
        } catch { return nil }
    }

    /// Uploads a single video file (mp4 / mov) to the same `whisper-media`
    /// bucket so it can be streamed back via `WhisperVideoView`. Returns the
    /// public URL for the uploaded asset, or `nil` if the upload fails.
    func uploadVideo(data: Data, postID: String, fileExtension: String = "mp4") async -> String? {
        guard isRemote, !data.isEmpty else { return nil }
        let ext = fileExtension.lowercased()
        let contentType: String
        switch ext {
        case "mov":  contentType = "video/quicktime"
        case "m4v":  contentType = "video/x-m4v"
        default:     contentType = "video/mp4"
        }
        let path = "\(currentUID.lowercased())/\(postID)/video.\(ext)"
        do {
            _ = try await client.storage
                .from(Self.mediaBucket)
                .upload(
                    path,
                    data: data,
                    options: FileOptions(
                        cacheControl: "3600",
                        contentType: contentType,
                        upsert: true
                    )
                )
            let publicURL = try client.storage
                .from(Self.mediaBucket)
                .getPublicURL(path: path)
            return publicURL.absoluteString
        } catch {
            record(error)
            return nil
        }
    }

    /// Uploads a recorded voice memo (or other small audio blob) to the
    /// same `whisper-media` bucket so it can be linked from a comment body.
    /// Returns the public URL on success.
    func uploadAudio(data: Data, postID: String, fileExtension: String = "m4a") async -> String? {
        guard isRemote, !data.isEmpty else { return nil }
        let ext = fileExtension.lowercased()
        let contentType: String
        switch ext {
        case "mp3": contentType = "audio/mpeg"
        case "wav": contentType = "audio/wav"
        case "caf": contentType = "audio/x-caf"
        default:    contentType = "audio/mp4"
        }
        let path = "\(currentUID)/\(postID)/audio.\(ext)"
        do {
            _ = try await client.storage
                .from(Self.mediaBucket)
                .upload(
                    path,
                    data: data,
                    options: FileOptions(
                        cacheControl: "3600",
                        contentType: contentType,
                        upsert: true
                    )
                )
            let publicURL = try client.storage
                .from(Self.mediaBucket)
                .getPublicURL(path: path)
            return publicURL.absoluteString
        } catch {
            record(error)
            return nil
        }
    }

    // MARK: - Posts

    /// Set after a successful first-page refresh — powers `fetchPostsIfStale`.
    private var lastPostsFetch: Date?
    @ObservationIgnored private var postFetches: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var postEnrichmentTask: Task<Void, Never>?
    private var postEnrichmentID: UUID = UUID()
    private var needsPostEnrichment: Bool = false
    private var feedNext: WhisperHistoryCursor?
    private var feedPageRevision = UUID()
    @ObservationIgnored private var feedMoreTask: Task<Void, Never>?
    private(set) var isLoadingMorePosts = false
    private(set) var morePostsError: String?
    var hasMorePosts: Bool { feedNext != nil }
    var feedContinuationID: String { feedNext?.id ?? "end" }
    private var lastMyPostsFetch: Date?
    private var lastThreadsFetch: Date?
    @ObservationIgnored private var ownPostFetches: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var ownPostsCacheTask: Task<Void, Never>?
    private var ownPostsWindowLimit = 0
    // Some installations retain the optional legacy author column; others use
    // canonical profiles only. Learn column support, never retry permission failures.
    private var feedUsernameColumnSupported: Bool?
    private static let feedColumns = "id,user_id,kind,caption,symbol,accent_hex,media_count,media_urls,is_ghost,is_reel,likes_count,comments_count,created_at,community_id,community_name"
    @ObservationIgnored private var threadFetch: Task<Void, Never>?
    private(set) var hasLoadedThreads: Bool = false
    private(set) var threadsLoadError: String?
    private(set) var isLoadingThreads: Bool = false

    /// Screen `.task` entry point: refetches only when the cached feed is
    /// missing or older than `maxAge`, so tab hops don't refetch every time.
    func fetchPostsIfStale(maxAge: TimeInterval = 60) async {
        if let last = lastPostsFetch, Date().timeIntervalSince(last) < maxAge { return }
        await fetchPosts()
    }

    /// Waves owns a separate raw cursor; filtering and personalization must
    /// never determine continuation or consume Home's paging state.
    func fetchReelPage(before: WhisperHistoryCursor? = nil) async throws -> (rows: [WhisperPostRow], next: WhisperHistoryCursor?) {
        guard isRemote else { throw CancellationError() }
        let generation = AccountStorage.generation
        let rows = try await readFeedRows(limit: WhisperFeedPaging.pageSize + 1,
            generation: generation, before: before, reelsOnly: true)
        let page = WhisperFeedPaging.page(rows)
        let visible = try await WhisperPostVisibilityService.visible(page.rows)
        guard generation == AccountStorage.generation, !Task.isCancelled else { throw CancellationError() }
        let uids = Set(visible.map(\.user_id)).subtracting(postAuthorProfiles.keys)
        if !uids.isEmpty {
            let profiles = await fetchPublicProfiles(userIDs: Array(uids))
            guard generation == AccountStorage.generation, !Task.isCancelled else { throw CancellationError() }
            mergeAuthorProfiles(profiles, requestedUIDs: uids)
        }
        schedulePostLikes(postIDs: visible.map(\.id))
        return (visible.filter { !deletedPostIDs.contains($0.id.lowercased()) }, page.next)
    }

    /// Revalidate the loaded Waves IDs on foreground/re-entry without moving
    /// pages or guessing at missed deletes from INSERT-only catch-up.
    func reconcileReelRows(_ current: [WhisperPostRow]) async throws -> [WhisperPostRow] {
        let generation = AccountStorage.generation
        let ids = Array(Set(current.map(\.id))).filter { UUID(uuidString: $0) != nil }
        var verified: [WhisperPostRow] = []
        for start in stride(from: 0, to: ids.count, by: 100) {
            let batch = Array(ids[start..<min(start + 100, ids.count)])
            let rows: [WhisperPostRow] = try await client.from("whisper_posts").select()
                .in("id", values: batch).eq("is_reel", value: true).execute().value
            guard generation == AccountStorage.generation, !Task.isCancelled else { throw CancellationError() }
            verified.append(contentsOf: rows)
        }
        let visible = try await WhisperPostVisibilityService.visible(verified)
        guard generation == AccountStorage.generation, !Task.isCancelled else { throw CancellationError() }
        let byID = Dictionary(visible.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        return current.compactMap { deletedPostIDs.contains($0.id.lowercased()) ? nil : byID[$0.id.lowercased()] }
    }

    func fetchPosts() async {
        guard isRemote, !Task.isCancelled else { return }
        // Every entry point shares the same first page. Older pages are owned
        // by visible scrolling, not a speculative launch/background download.
        let limit = WhisperFeedPaging.pageSize
        if let task = postFetches[limit] { await task.value; return }
        let generation = AccountStorage.generation
        feedPageRevision = UUID()
        feedMoreTask?.cancel(); feedMoreTask = nil; isLoadingMorePosts = false
        morePostsError = nil
        let task = Task { await self.loadPosts(limit: limit, generation: generation) }
        postFetches[limit] = task
        isLoadingPosts = true
        await task.value
        if postFetches[limit] == task {
            postFetches[limit] = nil
            isLoadingPosts = !postFetches.isEmpty
        }
    }

    private func readFeedRows(limit: Int, generation: UUID, before: WhisperHistoryCursor? = nil, reelsOnly: Bool = false) async throws -> [WhisperPostRow] {
        let includeUsername = feedUsernameColumnSupported != false
        let columns = Self.feedColumns + (includeUsername ? ",username" : "")
        do {
            var query = client.from("whisper_posts").select(columns)
            if reelsOnly { query = query.eq("is_reel", value: true) }
            if let before {
                guard let filter = before.beforeFilter else { throw CancellationError() }
                query = query.or(filter)
            }
            let response: PostgrestResponse<[WhisperPostRow]> = try await query
                .order("created_at", ascending: false, nullsFirst: false)
                .order("id", ascending: false).limit(limit).execute()
            try Task.checkCancellation()
            guard generation == AccountStorage.generation else { throw CancellationError() }
            if includeUsername { feedUsernameColumnSupported = true }
            WhisperPerformance.logger.debug("Feed response bytes=\(response.data.count) rows=\(response.value.count)")
            return response.value
        } catch let error as PostgrestError where includeUsername
            && (error.code == "42703" || error.code == "PGRST204")
            && error.message.lowercased().contains("username") {
            try Task.checkCancellation()
            guard generation == AccountStorage.generation else { throw CancellationError() }
            feedUsernameColumnSupported = false
            return try await readFeedRows(limit: limit, generation: generation, before: before, reelsOnly: reelsOnly)
        }
    }

    private func loadPosts(limit: Int, generation: UUID) async {
        guard !Task.isCancelled, generation == AccountStorage.generation else { return }
        let interval = WhisperPerformance.Span("FeedReadToPublish")
        let firstContent = WhisperPerformance.Span("FeedFirstContent")
        defer { interval.finish(); firstContent.finish() }
        do {
            // Keep useful content visible while refreshing. Do not immediately
            // re-download the first page as part of a larger ranking window.
            let rows = try await readFeedRows(limit: limit + 1, generation: generation)
            let page = WhisperFeedPaging.page(rows)
            await publishFeedRows(page.rows, generation: generation)
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            feedNext = page.next
            firstContent.finish(completed: true)
            lastPostsFetch = Date()
            postsLoadError = nil
            interval.finish(completed: true)
        } catch {
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            postsLoadError = "Your feed couldn't refresh. Check your connection and try again."
            record(error)
        }
    }

    func loadMorePosts(retry: Bool = false) async {
        guard isRemote, !Task.isCancelled, postFetches.isEmpty,
              let cursor = feedNext, retry || morePostsError == nil else { return }
        if let feedMoreTask { await feedMoreTask.value; return }
        let generation = AccountStorage.generation
        let revision = feedPageRevision
        let task = Task {
            do {
                let rows = try await self.readFeedRows(limit: WhisperFeedPaging.pageSize + 1, generation: generation, before: cursor)
                guard !Task.isCancelled, generation == AccountStorage.generation, revision == self.feedPageRevision else { return }
                let page = WhisperFeedPaging.page(rows)
                let ranked = Self.rankFeed(page.rows, following: WhisperFollowService.shared.following)
                self.posts = WhisperFeedPaging.append(ranked, to: self.posts, deleted: self.deletedPostIDs)
                self.feedNext = page.next
                self.morePostsError = nil
                self.schedulePostEnrichment(generation: generation)
            } catch {
                guard !Task.isCancelled, generation == AccountStorage.generation, revision == self.feedPageRevision else { return }
                self.morePostsError = "More posts couldn't load just now."
            }
        }
        feedMoreTask = task; isLoadingMorePosts = true
        await task.value
        if feedMoreTask == task { feedMoreTask = nil; isLoadingMorePosts = false }
    }

    private func publishFeedRows(_ rows: [WhisperPostRow], generation: UUID) async {
        guard !Task.isCancelled, generation == AccountStorage.generation else { return }
        // Following affects ranking only, not authorization. Home refreshes it
        // separately; do not block useful posts on follower-count requests.
        let following = WhisperFollowService.shared.following
        let ranked = await Task.detached(priority: .userInitiated) {
            Self.rankFeed(rows, following: following)
        }.value
        guard !Task.isCancelled, generation == AccountStorage.generation else { return }
        posts = ranked.filter { !deletedPostIDs.contains($0.id.lowercased()) }
        postsLoadError = nil
        schedulePostEnrichment(generation: generation)
    }

    private func schedulePostEnrichment(generation: UUID) {
        schedulePostLikes(postIDs: posts.map(\.id))
        needsPostEnrichment = true
        guard postEnrichmentTask == nil else { return }
        let operation = UUID(); postEnrichmentID = operation
        postEnrichmentTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.postEnrichmentID == operation { self.postEnrichmentTask = nil } }
            while self.needsPostEnrichment {
                guard generation == AccountStorage.generation, !Task.isCancelled else { return }
                self.needsPostEnrichment = false
                await self.hydrateAuthorProfiles()
            }
        }
    }

    /// The Whisper home-feed algorithm — MUST stay in sync with the web's
    /// `lib/feedAlgorithm.ts` (identical constants on both apps):
    ///   score = recencyDecay × engagement × followBoost × freshKicker
    ///   • recencyDecay = e^(-ageHours / 20), floored at 0.02 so strong old
    ///     posts can still surface
    ///   • engagement  = 1 + 0.6·ln(1 + likes + 2.5·comments)
    ///   • followBoost = 1.45 when the viewer follows the author
    ///   • freshKicker = 1.2 for posts under 90 minutes old
    /// then a diversity pass keeps any single author from occupying more
    /// than 2 consecutive slots.
    nonisolated static func rankFeed(
        _ rows: [WhisperPostRow],
        following: Set<String>
    ) -> [WhisperPostRow] {
        guard rows.count > 2 else { return rows }
        let now = Date()

        func score(_ row: WhisperPostRow) -> Double {
            let created = Self.parseISO(row.created_at) ?? now
            let ageHours = max(0, now.timeIntervalSince(created) / 3600)
            let recency = max(0.02, exp(-ageHours / 20))
            let likes = Double(row.likes_count ?? 0)
            let comments = Double(row.comments_count ?? 0)
            let engagement = 1 + 0.6 * log(1 + max(0, likes + 2.5 * comments))
            let follow = following.contains(row.user_id.lowercased()) ? 1.45 : 1.0
            let fresh = ageHours < 1.5 ? 1.2 : 1.0
            return recency * engagement * follow * fresh
        }

        var pool = rows
            .map { (row: $0, value: score($0)) }
            .sorted { $0.value > $1.value }

        var out: [WhisperPostRow] = []
        out.reserveCapacity(pool.count)
        var lastAuthor = ""
        var runLength = 0
        while !pool.isEmpty {
            var pick = 0
            if runLength >= 2,
               let alt = pool.firstIndex(where: { $0.row.user_id.lowercased() != lastAuthor }) {
                pick = alt
            }
            let chosen = pool.remove(at: pick).row
            let author = chosen.user_id.lowercased()
            if author == lastAuthor {
                runLength += 1
            } else {
                runLength = 1
                lastAuthor = author
            }
            out.append(chosen)
        }
        return out
    }

    /// Fetches a single post row by id and merges it into the in-memory
    /// `posts` cache so any view (e.g. Jasper's profile) that resolves a
    /// row by id from the cache picks it up immediately. Returns the row
    /// if found.
    @discardableResult
    func fetchPost(postID: String) async -> WhisperPostRow? {
        guard isRemote else { return nil }
        let generation = AccountStorage.generation
        do {
            let row: WhisperPostRow = try await client
                .from("whisper_posts")
                .select()
                .eq("id", value: postID)
                .single()
                .execute()
                .value
            guard !Task.isCancelled, generation == AccountStorage.generation else { return nil }
            guard try await WhisperPostVisibilityService.visible([row]).isEmpty == false else { return nil }
            guard !Task.isCancelled, generation == AccountStorage.generation, !deletedPostIDs.contains(postID.lowercased()) else { return nil }
            if let index = posts.firstIndex(where: { $0.id.lowercased() == row.id.lowercased() }) {
                posts[index] = row
            } else {
                posts.insert(row, at: 0)
            }
            // Make sure the author's public profile is available so the
            // username/avatar resolve to the real values, not "user".
            if postAuthorProfiles[row.user_id] == nil,
               let profile = await fetchPublicProfile(userID: row.user_id) {
                guard !Task.isCancelled, generation == AccountStorage.generation else { return nil }
                postAuthorProfiles[row.user_id] = profile
                if let uname = profile.username?.lowercased(), !uname.isEmpty,
                   let url = profile.profile_image_url, !url.isEmpty {
                    authorAvatarURLByUsername[uname] = url
                }
            }
            schedulePostLikes(postIDs: [row.id])
            return row
        } catch {
            return nil
        }
    }

    // Memory-only original resolution. Never inserts an original into the feed.
    @ObservationIgnored private var referencedRows: [String: (row: WhisperPostRow, accessed: Date)] = [:]
    @ObservationIgnored private var referencedRequests: [String: Task<WhisperPostRow?, Error>] = [:]
    @ObservationIgnored private var referenceScope = ""
    @ObservationIgnored private var referenceRevision = UUID()

    private func currentReferenceScope() -> String {
        "\(AccountStorage.generation)|\(WhisperBlockService.shared.blockedUserIDs.sorted())|\(WhisperFollowService.shared.following.sorted())"
    }

    func invalidateReferencedPosts() {
        referenceRevision = UUID()
        referencedRequests.values.forEach { $0.cancel() }
        referencedRequests.removeAll()
        referencedRows.removeAll()
        referenceScope = currentReferenceScope()
    }

    func cachedReferencedPost(postID: String) -> WhisperPostRow? {
        if referenceScope != currentReferenceScope() { invalidateReferencedPosts() }
        let key = postID.lowercased()
        guard !deletedPostIDs.contains(key), let entry = referencedRows[key],
              Date().timeIntervalSince(entry.accessed) < 120 else {
            referencedRows.removeValue(forKey: key)
            return nil
        }
        return entry.row
    }

    func loadReferencedPost(postID: String) async throws -> WhisperPostRow? {
        guard isRemote else { throw URLError(.notConnectedToInternet) }
        let key = postID.lowercased()
        if let row = cachedReferencedPost(postID: key) { return row }
        let revision = referenceRevision
        let epoch = AccountStorage.generation
        let scope = currentReferenceScope()
        let request: Task<WhisperPostRow?, Error>
        if let existing = referencedRequests[key] { request = existing }
        else {
            request = Task {
                let rows: [WhisperPostRow] = try await self.client.from("whisper_posts").select()
                    .eq("id", value: key).limit(1).execute().value
                try Task.checkCancellation()
                let visible = try await WhisperPostVisibilityService.visible(rows)
                guard epoch == AccountStorage.generation, revision == self.referenceRevision,
                      scope == self.currentReferenceScope(), !self.deletedPostIDs.contains(key), !Task.isCancelled else { throw CancellationError() }
                return visible.first
            }
            referencedRequests[key] = request
        }
        let row: WhisperPostRow?
        do { row = try await request.value }
        catch {
            if revision == referenceRevision { referencedRequests.removeValue(forKey: key) }
            throw error
        }
        guard epoch == AccountStorage.generation, revision == referenceRevision,
              scope == currentReferenceScope(), !deletedPostIDs.contains(key) else { throw CancellationError() }
        referencedRequests.removeValue(forKey: key)
        if let row {
            referencedRows[key] = (row, Date())
            if referencedRows.count > 100, let oldest = referencedRows.min(by: { $0.value.accessed < $1.value.accessed })?.key {
                referencedRows.removeValue(forKey: oldest)
            }
            schedulePostLikes(postIDs: [row.id])
        }
        return row
    }

    /// Fetches posts for any user_id. Used by `WhisperUserProfileView` to
    /// render another user's grid.
    func fetchPosts(forUserID userID: String, limit: Int = 60) async -> [WhisperPostRow] {
        (try? await fetchProfilePosts(forUserID: userID, limit: limit)) ?? []
    }

    /// Independent profile chronology. The raw boundary precedes visibility and
    /// format filtering so a Waves-heavy page cannot truncate a profile's list.
    func fetchProfilePostPage(forUserID userID: String, before: WhisperHistoryCursor? = nil) async throws -> (rows: [WhisperPostRow], next: WhisperHistoryCursor?) {
        guard isRemote, UUID(uuidString: userID) != nil else { throw CancellationError() }
        let generation = AccountStorage.generation
        var query = client.from("whisper_posts").select()
            .eq("user_id", value: userID)
        if let before {
            guard let filter = before.beforeFilter else { throw CancellationError() }
            query = query.or(filter)
        }
        let rows: [WhisperPostRow] = try await query
            .order("created_at", ascending: false, nullsFirst: false).order("id", ascending: false)
            .limit(WhisperFeedPaging.pageSize + 1).execute().value
        try Task.checkCancellation()
        guard generation == AccountStorage.generation else { throw CancellationError() }
        let page = WhisperFeedPaging.page(rows)
        let visible = try await WhisperPostVisibilityService.visible(page.rows)
        guard generation == AccountStorage.generation, !Task.isCancelled else { throw CancellationError() }
        let confirmed = visible.filter { !deletedPostIDs.contains($0.id.lowercased()) }
        schedulePostLikes(postIDs: confirmed.map(\.id))
        return (confirmed, page.next)
    }

    /// Throwing read for profile surfaces that must distinguish empty from failed.
    func fetchProfilePosts(forUserID userID: String, limit: Int = 60) async throws -> [WhisperPostRow] {
        guard isRemote else { throw URLError(.notConnectedToInternet) }
        let generation = AccountStorage.generation
        let rows: [WhisperPostRow] = try await client.from("whisper_posts").select()
            .eq("user_id", value: userID).order("created_at", ascending: false)
            .limit(limit).execute().value
        try Task.checkCancellation()
        guard generation == AccountStorage.generation else { throw CancellationError() }
        schedulePostLikes(postIDs: rows.map(\.id))
        return rows
    }

    /// Fetches posts the current user has commented on, plus the user's
    /// own latest comment on each (Threads-style "Replies" tab). Returns
    /// (post, my latest comment) pairs sorted by most-recent-reply.
    func fetchPostsIRepliedTo(limit: Int = 60) async -> [(post: WhisperPostRow, myComment: WhisperCommentRow)] {
        (try? await fetchRepliedPosts(userID: currentUID, limit: limit)) ?? []
    }

    func fetchRepliedPosts(userID: String, limit: Int = 60) async throws -> [(post: WhisperPostRow, myComment: WhisperCommentRow)] {
        guard isRemote else { return [] }
        let generation = AccountStorage.generation
        do {
            let myComments: [WhisperCommentRow] = try await client
                .from("whisper_post_comments")
                .select()
                .eq("user_id", value: userID)
                .order("created_at", ascending: false)
                .limit(limit * 3)
                .execute()
                .value
            // 2. Reduce to latest comment per post_id.
            var latestByPost: [String: WhisperCommentRow] = [:]
            var orderedPostIDs: [String] = []
            for c in myComments where latestByPost[c.post_id] == nil {
                latestByPost[c.post_id] = c
                orderedPostIDs.append(c.post_id)
            }
            let trimmed = Array(orderedPostIDs.prefix(limit))
            guard !trimmed.isEmpty else { return [] }
            // 3. Fetch the matching posts in one round-trip.
            let postRows: [WhisperPostRow] = try await client
                .from("whisper_posts")
                .select()
                .in("id", values: trimmed)
                .execute()
                .value
            let postsByID: [String: WhisperPostRow] = Dictionary(uniqueKeysWithValues: postRows.map { ($0.id, $0) })
            guard !Task.isCancelled, generation == AccountStorage.generation else { return [] }
            schedulePostLikes(postIDs: postRows.map(\.id))
            // Preserve newest-reply order.
            return trimmed.compactMap { id in
                guard let p = postsByID[id], let c = latestByPost[id] else { return nil }
                return (p, c)
            }
        } catch {
            throw error
        }
    }

    /// Fetches just the current user's posts directly by `user_id`. Avoids
    /// any RLS edge-case where a freshly-inserted row isn't surfaced via the
    /// global feed query (e.g. realtime hasn't propagated yet).
    func fetchMyPostsIfStale(maxAge: TimeInterval = 60) async {
        if let lastMyPostsFetch, Date().timeIntervalSince(lastMyPostsFetch) < maxAge { return }
        await fetchMyPosts()
    }

    func fetchMyPosts(limit: Int = 100) async {
        guard isRemote else { myPosts = []; return }
        if let task = ownPostFetches[limit] { await task.value; return }
        let generation = AccountStorage.generation
        let owner = currentUID
        let task = Task { await self.loadMyPosts(limit: limit, owner: owner, generation: generation) }
        ownPostFetches[limit] = task
        await task.value
        if ownPostFetches[limit] == task { ownPostFetches[limit] = nil }
    }

    private func loadMyPosts(limit: Int, owner: String, generation: UUID) async {
        guard !Task.isCancelled, generation == AccountStorage.generation else { return }
        if myPosts.isEmpty, myPostsLoadedGeneration == nil {
            let cached = await WhisperDisplayCache.load([WhisperPostRow].self, key: WhisperDisplayCache.ownPostsKey)
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            if let cached, myPosts.isEmpty, myPostsLoadedGeneration == nil {
                myPosts = Array(cached.filter { $0.user_id.lowercased() == owner.lowercased()
                    && !deletedPostIDs.contains($0.id.lowercased()) }.prefix(40))
            }
        }
        do {
            let rows: [WhisperPostRow] = try await client
                .from("whisper_posts")
                .select()
                .eq("user_id", value: owner)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            // A slower initial small read must not shrink an already-published
            // full owner window from a concurrently mounted profile.
            guard limit >= ownPostsWindowLimit else { return }
            ownPostsWindowLimit = limit
            myPosts = rows.filter { !deletedPostIDs.contains($0.id.lowercased()) }
            myPostsLoadedGeneration = generation
            if limit >= 100 { lastMyPostsFetch = Date() }
            myPostsLoadError = nil
            schedulePostLikes(postIDs: rows.map(\.id))
            // Merge into the global posts cache so the feed sees them too.
            for row in rows where !deletedPostIDs.contains(row.id.lowercased()) && !posts.contains(where: { $0.id == row.id }) {
                posts.insert(row, at: 0)
            }
            let snapshot = Array(myPosts.prefix(40))
            ownPostsCacheTask?.cancel()
            ownPostsCacheTask = Task {
                await WhisperDisplayCache.save(snapshot, key: WhisperDisplayCache.ownPostsKey,
                    owner: owner, generation: generation)
            }
        } catch {
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            myPostsLoadError = "Your posts couldn't load. Check your connection and try again."
            record(error)
        }
    }

    /// An authenticated read distinguishes an absent publication from a failed confirmation request.
    func reelPublication(postID: String, owner: String) async throws -> WhisperPostRow? {
        let generation = AccountStorage.generation
        guard isRemote, currentUID.lowercased() == owner.lowercased() else { throw CancellationError() }
        let rows: [WhisperPostRow] = try await client.from("whisper_posts").select()
            .eq("id", value: postID).eq("user_id", value: owner).limit(1).execute().value
        guard generation == AccountStorage.generation else { throw CancellationError() }
        if let row = rows.first {
            if !posts.contains(where: { $0.id == row.id }) { posts.insert(row, at: 0) }
            if !myPosts.contains(where: { $0.id == row.id }) { myPosts.insert(row, at: 0) }
            NotificationCenter.default.post(name: Notification.Name("WhisperWavePublished"), object: nil)
        }
        return rows.first
    }

    /// Uploads an immutable video using the same bounded-memory transfer as Waves.
    func uploadVideo(file: URL, postID: String, uploader: WhisperWaveUploadService, progress: @escaping @MainActor @Sendable (Double) -> Void = { _ in }) async throws -> String {
        let ext = file.pathExtension.lowercased()
        guard ["mp4", "mov", "m4v"].contains(ext) else { throw CocoaError(.fileReadCorruptFile) }
        let type = ext == "mov" ? "video/quicktime" : (ext == "m4v" ? "video/x-m4v" : "video/mp4")
        return try await uploadReel(file: file, path: "\(currentUID.lowercased())/\(postID)/video.\(ext)", uploader: uploader, contentType: type, progress: progress)
    }

    /// Uploads a finished immutable reel without loading the whole video into memory.
    func uploadReel(file: URL, path: String, uploader: WhisperWaveUploadService, contentType: String = "video/mp4", bucket: String = "whisper-media", progress: @escaping @MainActor @Sendable (Double) -> Void) async throws -> String {
        let owner = currentUID.lowercased()
        let generation = AccountStorage.generation
        guard isRemote, path.hasPrefix("\(owner)/") else { throw CancellationError() }
        let publicURL = try client.storage.from(bucket).getPublicURL(path: path)
        guard var components = URLComponents(url: publicURL, resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        if let host = components.host, host.hasSuffix(".supabase.co"), !host.hasSuffix(".storage.supabase.co") {
            components.host = String(host.dropLast(".supabase.co".count)) + ".storage.supabase.co"
        }
        components.path = "/storage/v1/upload/resumable"
        components.query = nil
        guard let endpoint = components.url else { throw URLError(.badURL) }
        try await uploader.upload(file: file, path: path, endpoint: endpoint, contentType: contentType, bucket: bucket, token: { [self] in
            guard generation == AccountStorage.generation, currentUID.lowercased() == owner else { throw CancellationError() }
            let session = try await client.auth.session
            guard generation == AccountStorage.generation, session.user.id.uuidString.lowercased() == owner else { throw CancellationError() }
            return session.accessToken
        }, progress: progress)
        guard generation == AccountStorage.generation else { throw CancellationError() }
        return publicURL.absoluteString
    }

    @discardableResult
    func createPost(
        kind: String,
        caption: String,
        symbol: String?,
        accentHex: String?,
        mediaCount: Int,
        isGhost: Bool,
        mediaDatas: [Data] = [],
        videoData: Data? = nil,
        videoExtension: String = "mp4",
        isReel: Bool = false,
        communityID: String? = nil,
        communityName: String? = nil,
        postID: String? = nil,
        uploadedVideoURL: String? = nil,
        attempt: WhisperWavePostAttempt? = nil,
        beforeInsert: (@MainActor () async throws -> Void)? = nil
    ) async -> WhisperPostRow? {
        attempt?.phase = .preparing
        attempt?.message = nil
        guard isRemote else { attempt?.message = "Sign in to publish your wave."; return nil }
        let id = postID ?? UUID().uuidString
        let owner = currentUID
        let generation = AccountStorage.generation
        if postID != nil {
            do {
                let existing: [WhisperPostRow] = try await client.from("whisper_posts").select().eq("id", value: id).eq("user_id", value: owner).limit(1).execute().value
                guard generation == AccountStorage.generation else { return nil }
                if let row = existing.first { return row }
            } catch {
                lastError = "Couldn't check whether this wave already posted. Retry when connected."
                return nil
            }
        }
        if let uploadedVideoURL {
            let prefix = try? client.storage.from(Self.mediaBucket).getPublicURL(path: "\(owner.lowercased())/").absoluteString
            guard let prefix, uploadedVideoURL.hasPrefix(prefix), uploadedVideoURL.hasSuffix(".mp4") else {
                attempt?.message = "The uploaded video doesn't belong to this account. Please retry."
                return nil
            }
        }
        guard !isReel || videoData?.isEmpty == false || uploadedVideoURL != nil else {
            lastError = "Choose a playable video before posting this wave."
            return nil
        }
        // Never let a stale local cache stamp "you" onto a post — hydrate
        // the reserved username from Supabase first, and prefer the live
        // whisper_profiles row if we have one.
        let hydrated = await LeaderboardService.shared.hydrateUsernameFromSupabase()
        let username = WhisperUserService.shared.me?.username
            ?? LeaderboardService.shared.savedUsername
            ?? hydrated
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"
        guard !Task.isCancelled, currentUID == owner, generation == AccountStorage.generation else { return nil }
        // 1) Upload any attached media first so we can persist URLs alongside the row.
        var urls: [String] = mediaDatas.isEmpty
            ? []
            : await uploadMedia(datas: mediaDatas, postID: id)
        guard currentUID == owner, generation == AccountStorage.generation else { return nil }
        guard urls.count == mediaDatas.count else {
            lastError = "An attachment couldn't upload. Nothing was published; please retry."
            return nil
        }
        if let uploadedVideoURL { urls.append(uploadedVideoURL) }
        if let videoData {
            guard let videoURL = await uploadVideo(data: videoData, postID: "\(id)-\(UUID().uuidString)", fileExtension: videoExtension) else {
                lastError = "The video didn't finish uploading. Your wave has not been posted. Please retry."
                return nil
            }
            urls.append(videoURL)
        }
        guard currentUID == owner, generation == AccountStorage.generation else { return nil }
        let finalMediaCount = urls.isEmpty ? mediaCount : urls.count

        // Build a flexible payload as a dictionary so we can progressively
        // drop any column the deployed `whisper_posts` table is missing.
        // Older schemas may be missing any of: username, kind, media_count,
        // media_urls, symbol, accent_hex, is_ghost.
        var payload: [String: AnyJSON] = [
            "id": .string(id),
            "user_id": .string(currentUID),
            "username": .string(username),
            "kind": .string(kind),
            "caption": .string(caption),
            "symbol": symbol.map { .string($0) } ?? .null,
            "accent_hex": accentHex.map { .string($0) } ?? .null,
            "media_count": .integer(finalMediaCount),
            "media_urls": .array(urls.map { .string($0) }),
            "is_ghost": .bool(isGhost),
            "is_reel": .bool(isReel)
        ]
        if let communityID, !communityID.isEmpty {
            payload["community_id"] = .string(communityID)
            payload["community_name"] = .string(communityName ?? communityID)
        }

        // Try insert, on missing-column errors strip that column and retry.
        // Required columns (id, user_id, caption) are never dropped.
        let droppable: Set<String> = Set([
            "username", "kind", "symbol", "accent_hex",
            "media_count", "media_urls", "is_ghost", "is_reel",
            "community_id", "community_name"
        ]).subtracting(isReel ? ["media_urls", "is_reel", "is_ghost"] : [])
        var droppedColumns: [String] = []
        do { try await beforeInsert?() }
        catch { attempt?.message = "Couldn't save publication recovery on this device. Free some storage and retry; nothing was posted."; return nil }

        for _ in 0..<8 {
            guard currentUID == owner, generation == AccountStorage.generation else { return nil }
            do {
                attempt?.phase = .submitting
                let inserted: [WhisperPostRow] = try await client
                    .from("whisper_posts")
                    .insert(payload)
                    .select()
                    .execute()
                    .value
                guard currentUID == owner, generation == AccountStorage.generation else { return nil }
                if let row = inserted.first {
                    attempt?.phase = .published
                    if !posts.contains(where: { $0.id == row.id }) { posts.insert(row, at: 0) }
                    if !myPosts.contains(where: { $0.id == row.id }) { myPosts.insert(row, at: 0) }
                    if isReel { NotificationCenter.default.post(name: Notification.Name("WhisperWavePublished"), object: nil) }
                    // Successful insert — no banner, even if columns were dropped.
                    // Schema heads-ups are noisy and the user already sees the post.
                    lastError = nil
                    if !droppedColumns.isEmpty {
                        print("[Whisper] createPost succeeded after dropping columns: \(droppedColumns)")
                    }
                    Analytics.record("post_created", [
                        "kind": kind,
                        "is_reel": isReel ? "1" : "0",
                        "media_count": String(finalMediaCount)
                    ])
                    // Fire-and-forget mention fanout — never blocks the post.
                    let mentionsKind: WhisperMentionsService.SourceType = isReel ? .reel : .post
                    let authorID = currentUID
                    let authorName = username
                    let postID = row.id
                    let captionCopy = caption
                    Task { @MainActor in
                        await WhisperMentionsService.shared.record(
                            sourceType: mentionsKind,
                            sourceID: postID,
                            body: captionCopy,
                            authorID: authorID,
                            authorUsername: authorName
                        )
                    }
                    return row
                }
                await fetchPosts()
                return posts.first(where: { $0.id == id })
            } catch {
                let msg = error.localizedDescription
                // PostgREST schema-cache errors look like:
                //   Could not find the 'username' column of 'whisper_posts' in the schema cache
                guard let column = Self.missingColumnName(in: msg),
                      droppable.contains(column),
                      payload[column] != nil else {
                    let code = (error as? PostgrestError)?.code ?? "unknown"
                    if ["42501", "23514", "23502", "23503", "PGRST204", "42703"].contains(code) { attempt?.phase = .rejected }
                    let message = code == "42501" ? "The server denied permission to publish. Save your draft; account permissions need checking." : "The server couldn't save this wave (\(code)). Your edit is retained for retry."
                    attempt?.message = message
                    lastError = message
                    WhisperErrorService.shared.report(message)
                    Analytics.record("post_failed", ["reason": code])
                    print("[Whisper] createPost failed code=\(code)")
                    return nil
                }
                payload.removeValue(forKey: column)
                droppedColumns.append(column)
                continue
            }
        }

        attempt?.phase = .rejected
        attempt?.message = "Publishing requires a server update. Save your draft; nothing was posted."
        lastError = "Post failed: too many missing columns in whisper_posts. Please run the migration SQL."
        WhisperErrorService.shared.report("Couldn't post — schema migration required.")
        Analytics.record("post_failed", ["reason": "schema_columns_missing"])
        return nil
    }

    /// Deletes a post owned by the current user. Returns true on success.
    /// Removes the row from `whisper_posts` (RLS ensures only the owner can
    /// delete) and prunes it from the local caches so the UI updates without
    /// a refetch.
    @discardableResult
    func deletePost(postID: String) async -> Bool {
        guard isSignedInRemotely, deletingPostIDs.insert(postID.lowercased()).inserted else { return false }
        let generation = AccountStorage.generation
        let owner = currentUID
        defer { if generation == AccountStorage.generation { deletingPostIDs.remove(postID.lowercased()) } }
        do {
            let removed: [WhisperPostRow] = try await client.from("whisper_posts").delete()
                .eq("id", value: postID).eq("user_id", value: owner).select().execute().value
            guard generation == AccountStorage.generation, !Task.isCancelled else { return false }
            guard removed.contains(where: { $0.id.lowercased() == postID.lowercased() && $0.user_id.lowercased() == owner.lowercased() }) else {
                lastError = "This post is no longer available or you don't have permission to delete it."
                return false
            }
            WhisperDisplayCache.invalidate(key: WhisperDisplayCache.ownPostsKey)
            lastMyPostsFetch = nil
            deletedPostIDs.insert(postID.lowercased())
            referencedRows.removeValue(forKey: postID.lowercased())
            posts.removeAll { $0.id.lowercased() == postID.lowercased() }
            myPosts.removeAll { $0.id == postID }
            myLikedPostIDs.remove(postID)
            commentsByPostID.removeValue(forKey: postID)
            lastError = nil
            return true
        } catch {
            guard generation == AccountStorage.generation, !Task.isCancelled else { return false }
            lastError = "Couldn't delete this post. Check your connection and try again."
            print("[Whisper] post deletion failed")
            return false
        }
    }

    /// Deterministic UUID-shaped thread id for a pair of users. Produces the
    /// same value for `(a,b)` and `(b,a)` so both sides land in the same
    /// conversation row. Derived from SHA-256 of the sorted lowercase UUIDs.
    nonisolated static func deterministicThreadID(_ a: String, _ b: String) -> String {
        let lo = a.lowercased()
        let hi = b.lowercased()
        let key = lo < hi ? "\(lo)|\(hi)" : "\(hi)|\(lo)"
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        // Format the first 32 hex chars as 8-4-4-4-12.
        let h = Array(hex.prefix(32))
        func s(_ r: Range<Int>) -> String { String(h[r]) }
        return "\(s(0..<8))-\(s(8..<12))-\(s(12..<16))-\(s(16..<20))-\(s(20..<32))"
    }

    /// Parses the missing column name out of a PostgREST schema-cache error.
    nonisolated private static func missingColumnName(in message: String) -> String? {
        // Match patterns like:
        //   Could not find the 'username' column of 'whisper_posts'
        //   could not find 'media_count' column
        let lower = message.lowercased()
        guard lower.contains("could not find") && lower.contains("column") else { return nil }
        // Extract the first single-quoted token.
        guard let start = message.firstIndex(of: "'") else { return nil }
        let afterStart = message.index(after: start)
        guard let end = message[afterStart...].firstIndex(of: "'") else { return nil }
        return String(message[afterStart..<end])
    }

    // MARK: - Likes

    @ObservationIgnored private var postLikesTask: Task<Void, Never>?
    @ObservationIgnored private var pendingPostLikeIDs: Set<String> = []
    @ObservationIgnored private var activePostLikeIDs: Set<String> = []
    @ObservationIgnored private var likeMutationRevisions: [String: UUID] = [:]
    @ObservationIgnored private var pendingLikeMutations: Set<String> = []
    @ObservationIgnored private var postLikesFetchedAt: [String: Date] = [:]

    /// Covers cards opened from independent search/community/activity loaders.
    func ensurePostLikeLoaded(postID: String) {
        let key = postID.lowercased()
        if let date = postLikesFetchedAt[key], Date().timeIntervalSince(date) < 60 { return }
        schedulePostLikes(postIDs: [key])
    }

    /// Batch only loaded post identities, not the account's lifetime like history.
    /// Successful subsets merge without erasing likes on another retained surface.
    func schedulePostLikes(postIDs: [String]) {
        guard isRemote else { return }
        let ids = Set(postIDs.compactMap { UUID(uuidString: $0)?.uuidString.lowercased() })
        pendingPostLikeIDs.formUnion(ids.subtracting(activePostLikeIDs))
        guard postLikesTask == nil, !pendingPostLikeIDs.isEmpty else { return }
        let generation = AccountStorage.generation
        let owner = currentUID
        postLikesTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == AccountStorage.generation { self.postLikesTask = nil; self.activePostLikeIDs = [] }
            }
            while !self.pendingPostLikeIDs.isEmpty {
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                let batch = Set(self.pendingPostLikeIDs.sorted().prefix(150))
                self.pendingPostLikeIDs.subtract(batch)
                self.activePostLikeIDs = batch
                let revisions = self.likeMutationRevisions
                let busyAtStart = self.pendingLikeMutations
                do {
                    let rows: [WhisperLikeRow] = try await self.client.from("whisper_post_likes")
                        .select("post_id,user_id").eq("user_id", value: owner)
                        .in("post_id", values: Array(batch)).limit(batch.count).execute().value
                    guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                    let safe = batch.filter { !busyAtStart.contains($0) && !self.pendingLikeMutations.contains($0)
                        && revisions[$0] == self.likeMutationRevisions[$0] && !self.deletedPostIDs.contains($0) }
                    let loadedLikes = Set(rows.map { $0.post_id.lowercased() }).intersection(safe)
                    let updated = self.myLikedPostIDs.subtracting(safe).union(loadedLikes)
                    if updated != self.myLikedPostIDs { self.myLikedPostIDs = updated }
                    for id in safe { self.postLikesFetchedAt[id] = Date() }
                    if self.postLikesFetchedAt.count > 1000 {
                        self.postLikesFetchedAt = Dictionary(uniqueKeysWithValues: self.postLikesFetchedAt.sorted { $0.value > $1.value }.prefix(750).map { ($0.key, $0.value) })
                    }
                } catch { /* Preserve known state; the next content refresh retries. */ }
                guard generation == AccountStorage.generation else { return }
                self.activePostLikeIDs = []
            }
        }
    }

    /// Toggles a like and returns the resulting liked-state.
    @discardableResult
    func toggleLike(postID: String) async -> Bool {
        guard isRemote, !Task.isCancelled else { return false }
        let postID = postID.lowercased()
        let liked = myLikedPostIDs.contains(postID)
        guard pendingLikeMutations.insert(postID).inserted else { return liked }
        let generation = AccountStorage.generation
        let owner = currentUID
        likeMutationRevisions[postID] = UUID()
        defer { if generation == AccountStorage.generation { pendingLikeMutations.remove(postID) } }
        do {
            if liked {
                try await client.from("whisper_post_likes")
                    .delete()
                    .eq("post_id", value: postID)
                    .eq("user_id", value: owner)
                    .execute()
                guard generation == AccountStorage.generation else { return liked }
                myLikedPostIDs.remove(postID)
                Analytics.record("post_unliked", ["post_id": postID])
            } else {
                let row = WhisperLikeRow(post_id: postID, user_id: owner)
                try await client.from("whisper_post_likes").insert(row).execute()
                guard generation == AccountStorage.generation else { return liked }
                myLikedPostIDs.insert(postID)
                Analytics.record("post_liked", ["post_id": postID])
            }
            return !liked
        } catch {
            return liked
        }
    }

    // MARK: - Comments

    /// Fetches every comment authored as `@ember` across the entire app,
    /// newest first. Powers the public `@ember` profile so every device
    /// sees the same global feed of Jasper's replies (the local tracker is
    /// only a fallback for offline / older rows).
    func fetchEmberCommentsGlobal(limit: Int = 200) async -> [WhisperCommentRow] {
        guard isRemote else { return [] }
        do {
            let rows: [WhisperCommentRow] = try await client
                .from("whisper_post_comments")
                .select()
                .eq("username", value: "ember")
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            return rows
        } catch {
            return []
        }
    }

    /// Resolves a comment under the current session's row-level permissions.
    func postID(forCommentID commentID: String) async -> String? {
        guard isRemote, UUID(uuidString: commentID) != nil else { return nil }
        let generation = AccountStorage.generation
        struct Parent: Decodable { let post_id: String }
        let rows: [Parent]? = try? await client.from("whisper_post_comments")
            .select("post_id").eq("id", value: commentID).limit(1).execute().value
        guard !Task.isCancelled, generation == AccountStorage.generation else { return nil }
        return rows?.first?.post_id
    }

    /// A Waves preview needs one root comment, not the entire thread and its likes.
    /// Keep it separate from the complete comment cache so a preview never truncates a sheet.
    func fetchCommentPreview(postID: String) async -> WhisperCommentRow? {
        guard isRemote, !Task.isCancelled else { return nil }
        let generation = AccountStorage.generation
        do {
            let roots: [WhisperCommentRow] = try await client.from("whisper_post_comments")
                .select().eq("post_id", value: postID).is("parent_comment_id", value: nil)
                .order("created_at", ascending: true).limit(1).execute().value
            guard !Task.isCancelled, generation == AccountStorage.generation else { return nil }
            if let root = roots.first { return root }
            let fallback: [WhisperCommentRow] = try await client.from("whisper_post_comments")
                .select().eq("post_id", value: postID)
                .order("created_at", ascending: true).limit(1).execute().value
            guard !Task.isCancelled, generation == AccountStorage.generation else { return nil }
            return fallback.first
        } catch { return nil }
    }

    func fetchComments(postID: String, maxAge: TimeInterval = 0) async -> [WhisperCommentRow] {
        let key = postID.lowercased()
        guard isRemote, !Task.isCancelled else { return [] }
        if maxAge > 0, let date = commentFetchedAt[key], Date().timeIntervalSince(date) < maxAge {
            return commentsByPostID[key] ?? []
        }
        if let task = commentFetches[key] { return await task.value }
        let generation = AccountStorage.generation
        let operation = UUID()
        let task = Task { await self.loadComments(postID: key, generation: generation) }
        commentFetches[key] = task; commentFetchIDs[key] = operation
        let rows = await task.value
        if commentFetchIDs[key] == operation { commentFetches[key] = nil; commentFetchIDs[key] = nil }
        return generation == AccountStorage.generation ? rows : []
    }

    private func loadComments(postID: String, generation: UUID) async -> [WhisperCommentRow] {
        commentLoadErrors[postID] = nil
        do {
            let rows: [WhisperCommentRow] = try await client
                .from("whisper_post_comments")
                .select()
                .eq("post_id", value: postID)
                .order("created_at", ascending: true)
                .execute()
                .value
            guard !Task.isCancelled, generation == AccountStorage.generation else { return [] }
            // Preserve any local-only synthetic rows (e.g. Jasper `@ember`
            // auto-replies that aren't persisted to the backend) so they
            // don't disappear on the next refresh.
            let preservedLocals = (commentsByPostID[postID] ?? [])
                .filter { $0.id.hasPrefix("local-") }
            commentsByPostID[postID] = rows + preservedLocals
            commentFetchedAt[postID] = Date()
            if commentFetchedAt.count > 64, let oldest = commentFetchedAt.min(by: { $0.value < $1.value })?.key, oldest != postID {
                commentFetchedAt[oldest] = nil; commentsByPostID[oldest] = nil
            }
            await fetchMyLikedComments(postID: postID)
            // Backfill any commenter whose `username` column is null/empty
            // so the UI never has to fall back to the generic "user" label.
            guard !Task.isCancelled, generation == AccountStorage.generation else { return [] }
            await hydrateCommentAuthors(postID: postID)
            return generation == AccountStorage.generation ? rows : []
        } catch {
            guard !Task.isCancelled, generation == AccountStorage.generation else { return [] }
            if commentLoadErrors.count >= 64 { commentLoadErrors.removeAll(keepingCapacity: true) }
            commentLoadErrors[postID] = "Couldn’t refresh comments. Check your connection and try again."
            return commentsByPostID[postID] ?? []
        }
    }

    /// Inserts an in-memory, session-only comment into the local cache for
    /// a post. Used to surface Jasper’s auto-replies (`@ember` mentions)
    /// without persisting them to the backend. Returns the synthetic row.
    @discardableResult
    func appendLocalComment(
        postID: String,
        username: String,
        body: String,
        parentCommentID: String? = nil
    ) -> WhisperCommentRow {
        let row = WhisperCommentRow(
            id: "local-\(UUID().uuidString)",
            post_id: postID,
            user_id: "local-\(username)",
            username: username,
            body: body,
            created_at: ISO8601DateFormatter().string(from: Date()),
            parent_comment_id: parentCommentID,
            likes_count: 0
        )
        var existing = commentsByPostID[postID] ?? []
        existing.append(row)
        commentsByPostID[postID] = existing
        return row
    }

    /// Deletes a comment authored by the current user, plus any local
    /// comments (e.g. Jasper mention replies) the current user can author.
    /// Returns true on success. Local-only synthetic rows (those with an id
    /// starting `local-`) are removed from the in-memory cache without a
    /// network round-trip.
    @discardableResult
    func deleteComment(commentID: String, postID: String) async -> Bool {
        // Local-only row — just prune the cache.
        if commentID.hasPrefix("local-") {
            if var rows = commentsByPostID[postID] {
                rows.removeAll { $0.id == commentID }
                commentsByPostID[postID] = rows
            }
            return true
        }
        guard isRemote else { return false }
        do {
            try await client
                .from("whisper_post_comments")
                .delete()
                .eq("id", value: commentID)
                .eq("user_id", value: currentUID)
                .execute()
            if var rows = commentsByPostID[postID] {
                rows.removeAll { $0.id == commentID }
                commentsByPostID[postID] = rows
            }
            myLikedCommentIDs.remove(commentID)
            lastError = nil
            return true
        } catch {
            lastError = "Couldn't delete comment: \(error.localizedDescription)"
            print("[Whisper] deleteComment error: \(error)")
            return false
        }
    }

    @discardableResult
    func addComment(postID: String, body: String, parentCommentID: String? = nil, commentID: String? = nil) async -> WhisperCommentRow? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isRemote, !trimmed.isEmpty else { return nil }
        let owner = currentUID
        let generation = AccountStorage.generation
        let identifier = commentID ?? UUID().uuidString.lowercased()
        if commentID != nil {
            do {
                let existing: [WhisperCommentRow] = try await client.from("whisper_post_comments").select()
                    .eq("id", value: identifier).eq("post_id", value: postID).eq("user_id", value: owner).limit(1).execute().value
                guard generation == AccountStorage.generation, owner == currentUID, !Task.isCancelled else { return nil }
                if let row = existing.first {
                    let key = postID.lowercased()
                    commentFetches[key]?.cancel()
                    commentFetches[key] = nil; commentFetchIDs[key] = nil
                    var cached = commentsByPostID[key] ?? []
                    if !cached.contains(where: { $0.id.lowercased() == row.id.lowercased() }) { cached.append(row) }
                    commentsByPostID[key] = cached
                    commentFetchedAt[key] = nil
                    lastError = nil
                    Task {
                        guard generation == AccountStorage.generation, owner == currentUID else { return }
                        _ = await fetchComments(postID: key)
                    }
                    return row
                }
            } catch {
                guard generation == AccountStorage.generation else { return nil }
                lastError = "Couldn’t confirm this reply. Please try again when connected."
                return nil
            }
        }
        let hydrated = await LeaderboardService.shared.hydrateUsernameFromSupabase()
        guard generation == AccountStorage.generation, owner == currentUID, !Task.isCancelled else { return nil }
        let username = WhisperUserService.shared.me?.username
            ?? LeaderboardService.shared.savedUsername
            ?? hydrated
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"

        // Use a flexible payload so we can progressively drop any column
        // the deployed `whisper_post_comments` table is missing (most
        // commonly `username`). Required fields are post_id, user_id, body.
        var payload: [String: AnyJSON] = [
            "id": .string(identifier),
            "post_id": .string(postID),
            "user_id": .string(owner),
            "username": .string(username),
            "body": .string(trimmed)
        ]
        if let parentCommentID {
            payload["parent_comment_id"] = .string(parentCommentID)
        }
        let droppable: Set<String> = ["username", "parent_comment_id"]

        for _ in 0..<4 {
            do {
                guard generation == AccountStorage.generation, owner == currentUID, !Task.isCancelled else { return nil }
                let inserted: [WhisperCommentRow] = try await client.from("whisper_post_comments").insert(payload).select().execute().value
                guard generation == AccountStorage.generation, owner == currentUID, !Task.isCancelled else { return nil }
                guard let newRow = inserted.first, newRow.id.lowercased() == identifier.lowercased() else { return nil }
                commentFetches[postID.lowercased()]?.cancel()
                commentFetches[postID.lowercased()] = nil; commentFetchIDs[postID.lowercased()] = nil
                var comments = commentsByPostID[postID.lowercased()] ?? []
                if !comments.contains(where: { $0.id.lowercased() == newRow.id.lowercased() }) { comments.append(newRow) }
                commentsByPostID[postID.lowercased()] = comments
                commentFetchedAt[postID.lowercased()] = nil
                Task {
                    guard generation == AccountStorage.generation else { return }
                    _ = await fetchComments(postID: postID)
                }
                lastError = nil
                if !newRow.id.hasPrefix("local-") {
                    let authorID = owner
                    let authorName = username
                    let commentID = newRow.id
                    let bodyCopy = trimmed
                    Task { @MainActor in
                        guard generation == AccountStorage.generation, owner == currentUID else { return }
                        await WhisperMentionsService.shared.record(
                            sourceType: .comment,
                            sourceID: commentID,
                            body: bodyCopy,
                            authorID: authorID,
                            authorUsername: authorName
                        )
                    }
                }
                Analytics.record("comment_created", ["post_id": postID])
                NotificationCenter.default.post(
                    name: .whisperCommentPosted,
                    object: nil,
                    userInfo: ["postID": postID.lowercased()]
                )
                return newRow
            } catch {
                let msg = error.localizedDescription
                guard let column = Self.missingColumnName(in: msg),
                      droppable.contains(column),
                      payload[column] != nil else {
                    guard generation == AccountStorage.generation, owner == currentUID else { return nil }
                    lastError = "Comment wasn’t sent. Please try again."
                    WhisperErrorService.shared.report("Couldn't send comment. Please try again.")
                    Analytics.record("comment_failed", ["reason": String(msg.prefix(80))])
                    print("[Whisper] addComment error: \(error)")
                    return nil
                }
                payload.removeValue(forKey: column)
                continue
            }
        }
        return nil
    }

    /// Inserts an `@ember` reply as a real Supabase comment so every viewer
    /// of the post sees it (not just the device that triggered the mention).
    /// `user_id` is the asker's UID (RLS requires auth.uid() = user_id), but
    /// `username` is forced to "ember" so the row renders with the Jasper
    /// identity in every client. Returns the persisted row on success.
    @discardableResult
    func addEmberComment(
        postID: String,
        body: String,
        parentCommentID: String? = nil
    ) async -> WhisperCommentRow? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isRemote, !trimmed.isEmpty else { return nil }
        var payload: [String: AnyJSON] = [
            "post_id": .string(postID),
            "user_id": .string(currentUID),
            "username": .string("ember"),
            "body": .string(trimmed)
        ]
        if let parentCommentID {
            payload["parent_comment_id"] = .string(parentCommentID)
        }
        let droppable: Set<String> = ["username", "parent_comment_id"]
        for _ in 0..<4 {
            do {
                try await client.from("whisper_post_comments").insert(payload).execute()
                _ = await fetchComments(postID: postID)
                return commentsByPostID[postID]?.last { !$0.id.hasPrefix("local-") && $0.body == trimmed }
            } catch {
                let msg = error.localizedDescription
                guard let column = Self.missingColumnName(in: msg),
                      droppable.contains(column),
                      payload[column] != nil else {
                    print("[Whisper] addEmberComment error: \(error)")
                    return nil
                }
                payload.removeValue(forKey: column)
                continue
            }
        }
        return nil
    }

    // MARK: - Comment likes & likers

    /// Fetches the users who liked a post by joining `whisper_post_likes`
    /// with `profiles`. Falls back to a username-less list if the join is
    /// blocked (e.g. RLS on profiles for unauth'd guests).
    func fetchPostLikers(postID: String) async -> [WhisperLiker] {
        (try? await loadPostLikers(postID: postID)) ?? []
    }

    func loadPostLikers(postID: String, offset: Int = 0) async throws -> [WhisperLiker] {
        let account = currentUID; let epoch = AccountStorage.generation
        try WhisperChatMediaService.checkAccount(account, generation: epoch)
        do {
            let rows: [WhisperLikeRow] = try await client
                .from("whisper_post_likes")
                .select("post_id,user_id")
                .eq("post_id", value: postID)
                .order("created_at", ascending: false)
                .order("user_id", ascending: true)
                .range(from: offset, to: offset + 49)
                .execute()
                .value
            try WhisperChatMediaService.checkAccount(account, generation: epoch)
            let ids = rows.map { $0.user_id }
            guard !ids.isEmpty else { return [] }
            let profiles = await fetchPublicProfiles(userIDs: ids)
            try WhisperChatMediaService.checkAccount(account, generation: epoch)
            return ids.compactMap { uid in
                guard let p = profiles[uid] else {
                    return WhisperLiker(
                        user_id: uid,
                        username: String(uid.prefix(6)),
                        display_name: nil,
                        profile_image_url: nil
                    )
                }
                return WhisperLiker(
                    user_id: p.id,
                    username: p.username ?? String(uid.prefix(6)),
                    display_name: p.display_name,
                    profile_image_url: p.profile_image_url
                )
            }
        } catch {
            throw error
        }
    }

    /// Pulls the current user's liked-comment ids for a post so the heart
    /// state can be primed on first render.
    private func fetchMyLikedComments(postID: String) async {
        guard isRemote else { return }
        let generation = AccountStorage.generation
        let commentIDs = (commentsByPostID[postID] ?? []).map(\.id).filter { UUID(uuidString: $0) != nil }
        guard !commentIDs.isEmpty else { return }
        do {
            let rows: [WhisperCommentLikeRow] = try await client
                .from("whisper_comment_likes")
                .select("comment_id,user_id")
                .eq("user_id", value: currentUID)
                .in("comment_id", values: commentIDs)
                .execute()
                .value
            guard !Task.isCancelled, generation == AccountStorage.generation else { return }
            let ids = Set(rows.map { $0.comment_id })
            myLikedCommentIDs.subtract(commentIDs)
            myLikedCommentIDs.formUnion(ids)
        } catch {
            // Table missing on older deployments — silent so the UI keeps working.
        }
    }

    /// Toggles a like on a comment. Returns the resulting liked-state.
    @discardableResult
    func toggleCommentLike(commentID: String, postID: String) async -> Bool {
        guard isRemote else { return false }
        let generation = AccountStorage.generation
        let owner = currentUID
        let liked = myLikedCommentIDs.contains(commentID)
        // Optimistic UI update
        if liked { myLikedCommentIDs.remove(commentID) } else { myLikedCommentIDs.insert(commentID) }
        do {
            if liked {
                try await client.from("whisper_comment_likes")
                    .delete()
                    .eq("comment_id", value: commentID)
                    .eq("user_id", value: owner)
                    .execute()
            } else {
                let row = WhisperCommentLikeRow(comment_id: commentID, user_id: owner)
                try await client.from("whisper_comment_likes").insert(row).execute()
            }
            guard generation == AccountStorage.generation, owner == currentUID else { return liked }
            return !liked
        } catch {
            // An old account's failed request must never change the new
            // account's cache, even when both viewed the same comment.
            guard generation == AccountStorage.generation, owner == currentUID else { return liked }
            // Roll back optimistic toggle
            if liked { myLikedCommentIDs.insert(commentID) } else { myLikedCommentIDs.remove(commentID) }
            print("[Whisper] toggleCommentLike error: \(error)")
            return liked
        }
    }

    // MARK: - Direct messages

    func fetchThreadsIfStale(maxAge: TimeInterval = 30) async {
        if let lastThreadsFetch, Date().timeIntervalSince(lastThreadsFetch) < maxAge {
            if WhisperGroupChatService.shared.inboxNeedsRefresh(maxAge: maxAge) {
                await WhisperGroupChatService.shared.fetchInboxSummaries()
            }
            return
        }
        await fetchThreads()
    }

    func historyKey(peer: String, kind: WhisperConversationKind) -> String { "\(kind.rawValue):\(peer.lowercased())" }

    func historyState(peer: String, kind: WhisperConversationKind) -> WhisperHistoryState {
        historyStates[historyKey(peer: peer, kind: kind)] ?? WhisperHistoryState()
    }

    /// Loads one real conversation rather than depending on the global inbox
    /// window. All reads still use the signed-in client's existing RLS rules.
    func fetchConversation(peer: String, kind: WhisperConversationKind, older: Bool = false) async {
        guard isRemote, UUID(uuidString: peer) != nil else { return }
        let key = historyKey(peer: peer, kind: kind)
        var state = historyStates[key] ?? WhisperHistoryState()
        guard !state.isLoading, !older || state.next != nil else { return }
        activeHistoryScopes[key] = (peer, kind)
        if historyRequestIDs.isEmpty { historyDeletedIDs.removeAll() }
        let requestID = UUID(); historyRequestIDs[key] = requestID
        let account = AccountStorage.currentUserID; let generation = AccountStorage.generation
        let me = currentUIDLower; let other = peer.lowercased()
        let belongs: (WhisperMessageRow) -> Bool = { row in
            row.conversationKind == kind && !Self.isGroupWire(row.body) && !WhisperCallSignal.isSignal(row.body)
        }
        var baseline = (conversations[other] ?? []).filter(belongs)
        let cacheRevision = WhisperMessageCache.currentRevision
        state.isLoading = true; state.error = nil; historyStates[key] = state
        defer {
            if historyRequestIDs[key] == requestID {
                historyStates[key]?.isLoading = false
                historyRequestIDs.removeValue(forKey: key)
                if historyRequestIDs.isEmpty { historyDeletedIDs.removeAll() }
            }
        }
        do {
            try WhisperChatMediaService.checkAccount(account, generation: generation)
            if !older, baseline.isEmpty {
                let cached = await WhisperMessageCache.load(scope: key).filter(belongs)
                try WhisperChatMediaService.checkAccount(account, generation: generation)
                guard historyRequestIDs[key] == requestID else { return }
                if !cached.isEmpty {
                    let current = conversations[other] ?? []
                    baseline = WhisperMessageHistory.reconcile(fetched: cached, baseline: [], current: current.filter(belongs), keepingHistory: true)
                    conversations[other] = current.filter { !belongs($0) } + baseline
                    state.hasLoaded = true
                }
            }
            let datingID = WhisperConversationKind.dating.threadID(me, other)
            var clauses = [
                "or(and(from_user_id.eq.\(me),to_user_id.eq.\(other)),and(from_user_id.eq.\(other),to_user_id.eq.\(me)))",
                "or(body.is.null,body.not.like.::wg-v1::%)",
                "or(body.is.null,body.not.like.::whisper-call-%)",
                kind == .dating ? "thread_id.eq.\(datingID)" : "or(thread_id.is.null,thread_id.neq.\(datingID))"
            ]
            if older {
                guard let filter = state.next?.beforeFilter else { return }
                clauses.append("or(\(filter))")
            }
            // One compound parameter; repeated .or() can replace restrictions.
            let query = client.from("whisper_messages").select().or("and(\(clauses.joined(separator: ",")))")
            let limit = older ? WhisperMessageHistory.olderLimit : WhisperMessageHistory.recentLimit
            let rows: [WhisperMessageRow] = try await query
                .order("created_at", ascending: false, nullsFirst: false)
                .order("id", ascending: false).limit(limit + 1).execute().value
            try WhisperChatMediaService.checkAccount(account, generation: generation)
            guard historyRequestIDs[key] == requestID else { return }
            let page = WhisperMessageHistory.page(rows, limit: limit)
            // Refresh older visible rows by ID too: offline deletes/edits cannot
            // be inferred from the latest page or INSERT events alone.
            var confirmed = page.rows
            if !older && state.hasLoaded {
                let newestIDs = Set(page.rows.map(\.id))
                let oldIDs = baseline.filter { !$0.id.hasPrefix("local-") && !newestIDs.contains($0.id) }.map(\.id)
                for start in stride(from: 0, to: oldIDs.count, by: 100) {
                    let ids = Array(oldIDs[start..<min(start + 100, oldIDs.count)])
                    let verified: [WhisperMessageRow] = try await client.from("whisper_messages").select().in("id", values: ids).execute().value
                    try WhisperChatMediaService.checkAccount(account, generation: generation)
                    confirmed.append(contentsOf: verified.filter(belongs))
                }
            }
            try WhisperChatMediaService.checkAccount(account, generation: generation)
            guard historyRequestIDs[key] == requestID else { return }
            let current = conversations[other] ?? []
            let merged = WhisperMessageHistory.reconcile(fetched: confirmed, baseline: baseline, current: current.filter(belongs), keepingHistory: older, deletedIDs: historyDeletedIDs)
            conversations[other] = current.filter { !belongs($0) } + merged
            historyStates[key]?.next = !older && state.hasLoaded && baseline.count > limit ? state.next : page.next
            historyStates[key]?.hasLoaded = true
            historyStates[key]?.error = nil
            recomputeThreadSummariesFromCache(mutation: false)
            Task { await WhisperMessageCache.save(merged, scope: key, owner: account, generation: generation, revision: cacheRevision) }
        } catch {
            guard AccountStorage.generation == generation, historyRequestIDs[key] == requestID, !Task.isCancelled else { return }
            historyStates[key]?.error = older ? "Earlier messages are unavailable for a moment." : "Messages couldn’t refresh just now."
            historyStates[key]?.retryOlder = older
        }
    }

    func closeConversation(peer: String, kind: WhisperConversationKind) {
        let key = historyKey(peer: peer, kind: kind)
        activeHistoryScopes.removeValue(forKey: key)
        historyRequestIDs.removeValue(forKey: key)
        historyStates.removeValue(forKey: key)
        // Older history is a viewing window, not an unbounded memory cache.
        let other = peer.lowercased()
        let current = conversations[other] ?? []
        let scoped = current.filter { $0.conversationKind == kind && !Self.isGroupWire($0.body) }
        let confirmed = scoped.filter { !$0.id.hasPrefix("local-") }.sorted { ($0.created_at ?? "", $0.id) < ($1.created_at ?? "", $1.id) }
        let retained = Set(confirmed.suffix(WhisperMessageHistory.recentLimit).map(\.id))
        conversations[other] = current.filter { $0.conversationKind != kind || Self.isGroupWire($0.body) || $0.id.hasPrefix("local-") || retained.contains($0.id) }
    }

    func groupHistoryState(_ groupID: UUID) -> WhisperHistoryState {
        historyStates["group:\(groupID.uuidString.lowercased())"] ?? WhisperHistoryState()
    }

    /// Page logical messages first; retain all RLS-authorized fanout rows for
    /// each one so receipts, reactions and unsends keep their original identity.
    func fetchGroupConversation(_ groupID: UUID, older: Bool = false) async {
        guard isRemote, !Task.isCancelled else { return }
        let key = "group:\(groupID.uuidString.lowercased())"
        var state = historyStates[key] ?? WhisperHistoryState()
        guard !state.isLoading, !older || state.next != nil else { return }
        activeGroupHistoryScopes.insert(groupID)
        if historyRequestIDs.isEmpty { historyDeletedIDs.removeAll() }
        let request = UUID(); historyRequestIDs[key] = request
        let account = AccountStorage.currentUserID; let generation = AccountStorage.generation
        let belongs: (WhisperMessageRow) -> Bool = { WhisperGroupHistory.belongs($0, to: groupID) }
        var baseline = conversations.values.flatMap { $0 }.filter(belongs)
        let cacheRevision = WhisperMessageCache.currentRevision
        state.isLoading = true; state.error = nil; state.retryOlder = older; historyStates[key] = state
        defer {
            if historyRequestIDs[key] == request {
                historyStates[key]?.isLoading = false
                historyRequestIDs.removeValue(forKey: key)
                if historyRequestIDs.isEmpty { historyDeletedIDs.removeAll() }
            }
        }
        do {
            var mayCache = false
            if !older {
                mayCache = await canRestoreGroupSnapshot(groupID, account: account, generation: generation)
                try WhisperChatMediaService.checkAccount(account, generation: generation)
                guard historyRequestIDs[key] == request else { return }
                if mayCache, baseline.isEmpty {
                    let cached = await WhisperMessageCache.load(scope: key).filter(belongs)
                    try WhisperChatMediaService.checkAccount(account, generation: generation)
                    guard historyRequestIDs[key] == request else { return }
                    if !cached.isEmpty {
                        let current = conversations.values.flatMap { $0 }.filter(belongs)
                        baseline = WhisperMessageHistory.reconcile(fetched: cached, baseline: [], current: current, keepingHistory: true)
                        for row in baseline {
                            let other = row.from_user_id.lowercased() == currentUIDLower ? row.to_user_id.lowercased() : row.from_user_id.lowercased()
                            if conversations[other]?.contains(where: { $0.id == row.id }) != true { conversations[other, default: []].append(row) }
                        }
                        state.hasLoaded = true
                    }
                }
            }
            // A restored snapshot is revalidated through its complete visible
            // range too, including deletions or access loss while offline.
            let target = !older && state.hasLoaded ? baseline.filter { !$0.id.hasPrefix("local-") }.min {
                (Self.parseISO($0.created_at) ?? .distantPast, $0.id) < (Self.parseISO($1.created_at) ?? .distantPast, $1.id)
            } : nil
            var cursor = older ? state.next : nil
            var confirmed: [WhisperMessageRow] = []
            var limit = older ? WhisperMessageHistory.olderLimit : WhisperMessageHistory.recentLimit
            repeat {
                try WhisperChatMediaService.checkAccount(account, generation: generation)
                let envelopes: [WhisperGroupHistoryEnvelope] = try await client.rpc("whisper_group_history_v1",
                    params: WhisperGroupHistoryParams(p_group_id: groupID.uuidString, p_limit: limit,
                        p_before_at: cursor?.createdAt, p_before_id: cursor?.id)).execute().value
                try WhisperChatMediaService.checkAccount(account, generation: generation)
                guard historyRequestIDs[key] == request else { return }
                let page = WhisperGroupHistory.page(envelopes, limit: limit)
                confirmed.append(contentsOf: page.rows.filter(belongs))
                cursor = page.next
                guard !older, let target, let cursor,
                      let at = Self.parseISO(cursor.createdAt), let targetAt = Self.parseISO(target.created_at),
                      (at, cursor.id) > (targetAt, target.id) else { break }
                limit = WhisperMessageHistory.olderLimit
            } while cursor != nil
            try WhisperChatMediaService.checkAccount(account, generation: generation)
            guard historyRequestIDs[key] == request else { return }
            let current = conversations.values.flatMap { $0 }.filter(belongs)
            let merged = WhisperMessageHistory.reconcile(fetched: confirmed, baseline: baseline,
                current: current, keepingHistory: older, deletedIDs: historyDeletedIDs)
            var result = conversations.mapValues { $0.filter { !belongs($0) } }
            let me = currentUIDLower
            for row in merged {
                let other = row.from_user_id.lowercased() == me ? row.to_user_id.lowercased() : row.from_user_id.lowercased()
                guard other != me, !other.isEmpty else { continue }
                result[other, default: []].append(row)
            }
            conversations = result
            historyStates[key]?.next = cursor
            historyStates[key]?.hasLoaded = true
            historyStates[key]?.error = nil
            recomputeThreadSummariesFromCache(mutation: false)
            if mayCache {
                Task { await WhisperMessageCache.save(merged, scope: key, owner: account, generation: generation, revision: cacheRevision) }
            }
        } catch {
            guard AccountStorage.generation == generation, historyRequestIDs[key] == request, !Task.isCancelled else { return }
            historyStates[key]?.error = older ? "Earlier messages are unavailable for a moment." : "Messages couldn’t refresh just now."
            historyStates[key]?.retryOlder = older
        }
    }

    /// A historical delivery is not evidence of current membership. Never
    /// restore group content from disk on an unavailable/failed registry read.
    private func canRestoreGroupSnapshot(_ groupID: UUID, account: String, generation: UUID) async -> Bool {
        do {
            let rows: [WhisperGroupRegistryRow] = try await client.from("whisper_group_threads").select()
                .eq("id", value: groupID.uuidString.lowercased()).limit(1).execute().value
            try WhisperChatMediaService.checkAccount(account, generation: generation)
            let me = account.lowercased()
            let allowed = rows.contains { $0.owner_id.lowercased() == me || $0.member_ids.contains(where: { $0.lowercased() == me }) }
            if !allowed {
                await WhisperMessageDiskStore.shared.remove(owner: me, scope: "group:\(groupID.uuidString.lowercased())")
            }
            return allowed
        } catch { return false }
    }

    func closeGroupConversation(_ groupID: UUID) {
        let key = "group:\(groupID.uuidString.lowercased())"
        activeGroupHistoryScopes.remove(groupID)
        historyRequestIDs.removeValue(forKey: key); historyStates.removeValue(forKey: key)
        let scoped = conversations.values.flatMap { $0 }.filter { WhisperGroupHistory.belongs($0, to: groupID) }
        let retained = Set(WhisperGroupHistory.recent(scoped).map(\.id))
        conversations = conversations.mapValues { rows in
            rows.filter { !WhisperGroupHistory.belongs($0, to: groupID) || retained.contains($0.id) }
        }
    }

    func fetchThreads() async {
        guard isRemote else { return }
        if let threadFetch { await threadFetch.value; return }
        let task = Task {
            async let summaries: Void = self.fetchInboxSummaries()
            async let groups: Void = WhisperGroupChatService.shared.fetchInboxSummaries()
            let generation = AccountStorage.generation
            for scope in Array(self.activeHistoryScopes.values) {
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                await self.fetchConversation(peer: scope.peer, kind: scope.kind)
            }
            for groupID in Array(self.activeGroupHistoryScopes) {
                guard !Task.isCancelled, generation == AccountStorage.generation else { return }
                await self.fetchGroupConversation(groupID)
            }
            _ = await (summaries, groups)
        }
        threadFetch = task; isLoadingThreads = true
        await task.value
        if threadFetch == task { threadFetch = nil; isLoadingThreads = false }
    }

    /// Shared, owner-scoped summary pages. Refresh the loaded page range
    /// atomically so a quiet thread does not disappear on a first-page refresh.
    func fetchInboxSummaries(older: Bool = false) async {
        guard isRemote, !Task.isCancelled else { return }
        let account = AccountStorage.currentUserID
        let generation = AccountStorage.generation
        if let inboxTask {
            let wasOlder = inboxTaskOlder
            await inboxTask.value
            guard !Task.isCancelled, AccountStorage.currentUserID == account,
                  AccountStorage.generation == generation else { return }
            // Older-page callers share the active operation rather than each
            // launching a new page after suspension. A refresh must still
            // refresh the first page if it joined an older-page operation.
            if older || !wasOlder { return }
            await fetchInboxSummaries()
            return
        }
        guard !older || inboxNext != nil else { return }
        let request = UUID(); inboxRequestID = request
        let revision = inboxRevision
        let owner = currentUIDLower
        let initialCursor = older ? inboxNext : nil
        let pages = older ? 1 : inboxPageCount
        let hidden = Array(locallyDeletedMessageIDs.union(unsendingInboxIDs)).filter { UUID(uuidString: $0) != nil }
        isLoadingInboxPage = true; inboxPageError = nil; inboxRetryOlder = older
        let task = Task { @MainActor in
            defer {
                if self.inboxRequestID == request {
                    self.inboxTask = nil
                    self.isLoadingInboxPage = false
                }
            }
            do {
                var result: [WhisperInboxSummaryRow] = []
                var cursor = initialCursor
                for _ in 0..<pages {
                    try WhisperChatMediaService.checkAccount(account, generation: generation)
                    let rows: [WhisperInboxSummaryRow] = try await self.client
                        .rpc("whisper_thread_summaries_v1", params: WhisperInboxSummaryParams(
                            p_before_at: cursor?.createdAt, p_before_id: cursor?.id, p_hidden_ids: hidden))
                        .execute().value
                    try WhisperChatMediaService.checkAccount(account, generation: generation)
                    guard self.inboxRequestID == request, self.inboxRevision == revision, self.currentUIDLower == owner else { return }
                    let page = WhisperInboxPaging.page(rows)
                    result = WhisperInboxPaging.append(page.rows, to: result)
                    cursor = page.next
                    if cursor == nil { break }
                }
                self.inboxRows = older ? WhisperInboxPaging.append(result, to: self.inboxRows) : result
                if older { self.inboxPageCount += 1 }
                // A refreshed range replaces confirmed overlays, but a later
                // page alone cannot acknowledge changes to the first page.
                if !older { self.inboxMutationRows = [:] }
                self.inboxNext = cursor; self.inboxHasMore = cursor != nil
                self.hasLoadedThreads = true
                self.lastThreadsFetch = Date()
                self.recomputeThreadSummariesFromCache(mutation: false)
                let ids = self.inboxRows.map(\.peer_id).filter { self.threadProfiles[$0.lowercased()] == nil }
                let profiles = await self.fetchPublicProfiles(userIDs: ids)
                try WhisperChatMediaService.checkAccount(account, generation: generation)
                guard self.inboxRequestID == request, self.inboxRevision == revision else { return }
                for (id, profile) in profiles { self.threadProfiles[id] = profile }
            } catch {
                guard !Task.isCancelled, self.inboxRequestID == request,
                      self.inboxRevision == revision, AccountStorage.generation == generation else { return }
                self.inboxPageError = older ? "More conversations couldn’t load just now." : "Conversations couldn’t refresh just now."
            }
        }
        inboxTaskOlder = older
        inboxTask = task
        await task.value
    }

    /// SELECTs do not invalidate authority. Only actual local/realtime mutations
    /// do, including updates/deletes outside the cached history window.
    private func invalidateInboxSummaries() {
        inboxRevision = UUID(); inboxRequestID = UUID()
        inboxTask?.cancel(); inboxTask = nil; isLoadingInboxPage = false
        inboxRefreshTask?.cancel()
        let generation = AccountStorage.generation
        inboxRefreshTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard !Task.isCancelled, AccountStorage.generation == generation else { return }
            await self.fetchInboxSummaries()
        }
    }

    /// Coach review must not depend on whichever conversations happen to
    /// have been opened or included in an inbox history window.
    func fetchLatestPlanAnswer(from peer: String) async throws -> WhisperMessageRow? {
        let account = AccountStorage.currentUserID
        let generation = AccountStorage.generation
        let owner = currentUIDLower
        try WhisperChatMediaService.checkAccount(account, generation: generation)
        let rows: [WhisperMessageRow] = try await client.from("whisper_messages")
            .select()
            .eq("from_user_id", value: peer.lowercased())
            .eq("to_user_id", value: owner)
            .eq("thread_id", value: WhisperConversationKind.direct.threadID(owner, peer))
            .like("body", pattern: WhisperPlanQuizAnswersEmbed.prefix + "%")
            .order("created_at", ascending: false)
            .order("id", ascending: false)
            .limit(1).execute().value
        try WhisperChatMediaService.checkAccount(account, generation: generation)
        return rows.first
    }

    private func loadThreads() async {
        guard !Task.isCancelled else { return }
        let account = AccountStorage.currentUserID; let generation = AccountStorage.generation
        let fetchUID = currentUID
        let baseline = conversations
        do {
            // Fetch inbound + outbound concurrently. We keep the success/
            // failure status of EACH query separately — if either one
            // errors (network blip, expired token mid-flight, transient
            // 5xx) we must NOT overwrite the local cache with a partial
            // or empty result set. Doing so wipes every visible message
            // until the next successful fetch, which is exactly the
            // "messages disappear until I tap the composer / restart"
            // bug users were hitting.
            async let inboundResult: Result<[WhisperMessageRow], Error> = {
                do {
                    let v: [WhisperMessageRow] = try await client
                        .from("whisper_messages")
                        .select()
                        .eq("to_user_id", value: fetchUID)
                        .like("body", pattern: "::wg-v1::%")
                        .order("created_at", ascending: false)
                        .limit(1000)
                        .execute()
                        .value
                    return .success(v)
                } catch {
                    return .failure(error)
                }
            }()
            async let outboundResult: Result<[WhisperMessageRow], Error> = {
                do {
                    let v: [WhisperMessageRow] = try await client
                        .from("whisper_messages")
                        .select()
                        .eq("from_user_id", value: fetchUID)
                        .like("body", pattern: "::wg-v1::%")
                        .order("created_at", ascending: false)
                        .limit(1000)
                        .execute()
                        .value
                    return .success(v)
                } catch {
                    return .failure(error)
                }
            }()
            let (inbRes, outRes) = await (inboundResult, outboundResult)
            guard (try? WhisperChatMediaService.checkAccount(account, generation: generation)) != nil else { return }
            // If BOTH queries failed, bail without touching local state.
            // (A single-side failure still gets merged so we don't drop
            // the half we did receive, but we also won't delete threads
            // that only exist on the failed side — see merge below.)
            switch (inbRes, outRes) {
            case (.failure, .failure):
                threadsLoadError = "Messages couldn't load. Pull down to try again."
                return
            default:
                break
            }
            let inb: [WhisperMessageRow] = (try? inbRes.get()) ?? []
            let out: [WhisperMessageRow] = (try? outRes.get()) ?? []
            let inboundFailed = (try? inbRes.get()) == nil
            let outboundFailed = (try? outRes.get()) == nil
            // Strip control-channel call signals — they're not chat content.
            let filtered = (inb + out).filter { !WhisperCallSignal.isSignal($0.body) }
            // Parse once per row, not inside each sort comparison.
            var dates: [String: Date] = [:]
            for row in filtered { dates[row.id] = Self.parseISO(row.created_at) ?? .distantPast }
            let all = filtered.sorted { (dates[$0.id] ?? .distantPast) > (dates[$1.id] ?? .distantPast) }
            var byOther: [String: [WhisperMessageRow]] = [:]
            let me = currentUIDLower
            for row in all {
                let fromLower = row.from_user_id.lowercased()
                let toLower = row.to_user_id.lowercased()
                let other = fromLower == me ? toLower : fromLower
                // Skip self-threads — these show up as a chat with yourself
                // and confuse the inbox (showing your own name/avatar).
                if other == me || other.isEmpty { continue }
                byOther[other, default: []].append(row)
            }
            // Preserve optimistic local rows that the server hasn't returned
            // yet — dedupe by (from_user_id, body) so once the canonical row
            // arrives we drop the placeholder. Without this merge, a freshly
            // sent program / workout could vanish from the chat as soon as
            // this fetch completes (server hasn't surfaced it in the SELECT
            // window yet, or the row decode failed for an unrelated reason).
            //
            // Additionally: if ONE side of the fetch failed, we also keep
            // any cached non-local rows that belong to that side. e.g. if
            // the inbound query errored, we still trust our current cache
            // for incoming messages from each `other` and only refresh
            // outbound ones. This is what prevents the "thread looks empty
            // for 30s after a transient error" flicker.
            for (other, existing) in conversations {
                let fetchedIDs = Set((byOther[other] ?? []).map(\.id))
                let fetchedBodies = Set((byOther[other] ?? []).map { $0.from_user_id.lowercased() + "\u{0}" + $0.conversationKind.rawValue + "\u{0}" + $0.body })
                for row in existing {
                    let rowFromLower = row.from_user_id.lowercased()
                    let alreadyPresent = fetchedIDs.contains(row.id)
                    if alreadyPresent { continue }
                    let isOptimistic = row.id.hasPrefix("local-")
                    let isInbound = rowFromLower != me
                    let isOutbound = rowFromLower == me
                    let dedupedOptimistic = isOptimistic && fetchedBodies.contains(rowFromLower + "\u{0}" + row.conversationKind.rawValue + "\u{0}" + row.body)
                    let keep: Bool
                    if !Self.isGroupWire(row.body) {
                        // Direct history has its own 100/50 authority.
                        keep = true
                    } else if isOptimistic {
                        keep = !dedupedOptimistic
                    } else if isInbound && inboundFailed {
                        keep = true
                    } else if isOutbound && outboundFailed {
                        keep = true
                    } else {
                        keep = false
                    }
                    if keep {
                        dates[row.id] = Self.parseISO(row.created_at) ?? .distantPast
                        byOther[other, default: []].append(row)
                    }
                }
                if byOther[other] != nil {
                    byOther[other]?.sort { ($0.created_at ?? "") < ($1.created_at ?? "") }
                }
            }
            // Reconcile mutations received while SELECT was in flight. An older
            // snapshot must not erase an insert/read receipt or revive an unsend.
            for other in Set(baseline.keys).union(conversations.keys) {
                let before = Dictionary((baseline[other] ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                let current = Dictionary((conversations[other] ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                var merged = Dictionary((byOther[other] ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                for id in before.keys where current[id] == nil { merged.removeValue(forKey: id) }
                for (id, row) in current where before[id] != row {
                    if id.hasPrefix("local-"), merged.values.contains(where: { !$0.id.hasPrefix("local-") && $0.from_user_id.lowercased() == row.from_user_id.lowercased() && $0.conversationKind == row.conversationKind && $0.body == row.body }) { continue }
                    merged[id] = row
                    dates[id] = Self.parseISO(row.created_at) ?? .distantPast
                }
                if !merged.isEmpty { byOther[other] = Array(merged.values) }
                else { byOther.removeValue(forKey: other) }
            }
            // A global 1,000-row window is not authoritative for the history
            // of an open chat. Keep its dedicated window until it reconciles.
            for scope in activeHistoryScopes.values {
                let peer = scope.peer.lowercased()
                let belongs: (WhisperMessageRow) -> Bool = { $0.conversationKind == scope.kind && !Self.isGroupWire($0.body) }
                byOther[peer] = (byOther[peer] ?? []).filter { !belongs($0) } + (conversations[peer] ?? []).filter(belongs)
            }
            for groupID in activeGroupHistoryScopes {
                let belongs: (WhisperMessageRow) -> Bool = { WhisperGroupHistory.belongs($0, to: groupID) }
                for peer in Set(byOther.keys).union(conversations.keys) {
                    byOther[peer] = (byOther[peer] ?? []).filter { !belongs($0) } + (conversations[peer] ?? []).filter(belongs)
                }
            }
            conversations = byOther

            recomputeThreadSummariesFromCache(mutation: false)
            // Prefetch the other users' public profiles so the inbox and
            // thread view can render the correct avatar + display name.
            hasLoadedThreads = true
            threadsLoadError = inboundFailed || outboundFailed ? "Some messages couldn't refresh. Pull down to try again." : nil
            if !inboundFailed && !outboundFailed { lastThreadsFetch = Date() }
            let otherIDs = byOther.keys.filter { threadProfiles[$0] == nil }
            let profiles = await fetchPublicProfiles(userIDs: otherIDs)
            guard (try? WhisperChatMediaService.checkAccount(account, generation: generation)) != nil else { return }
            for (id, p) in profiles { threadProfiles[id] = p }
            cacheWidgetSnapshot()
            for scope in Array(activeHistoryScopes.values) {
                guard AccountStorage.generation == generation, !Task.isCancelled else { return }
                guard activeHistoryScopes[historyKey(peer: scope.peer, kind: scope.kind)] != nil else { continue }
                await fetchConversation(peer: scope.peer, kind: scope.kind)
            }
            for groupID in Array(activeGroupHistoryScopes) {
                guard AccountStorage.generation == generation, !Task.isCancelled else { return }
                guard activeGroupHistoryScopes.contains(groupID) else { continue }
                await fetchGroupConversation(groupID)
            }
        }
    }

    /// Writes a tiny snapshot of Whisper state into the App Group so the
    /// Whisper widgets (and the watch app) can render without needing the
    /// network.
    func cacheWidgetSnapshot() {
        let stories = WhisperStoryService.shared
        let me = (LeaderboardService.shared.savedUsername ?? "").lowercased()
        let storyInfos: [WhisperWidgetSync.StoryAuthorInfo] = stories.storiesByUser()
            .filter { !$0.username.isEmpty && $0.username.lowercased() != me }
            .map { group in
                let url = authorAvatarURLByUsername[group.username.lowercased()]
                    ?? threadProfiles[group.userID]?.profile_image_url
                return WhisperWidgetSync.StoryAuthorInfo(
                    name: group.username,
                    userID: group.userID,
                    avatarURL: url
                )
            }
        // Build avatar URL map keyed by the *other* user_id for each thread.
        var avatarByUID: [String: String] = [:]
        for t in threads.prefix(5) {
            if let url = threadProfiles[t.otherUserID]?.profile_image_url, !url.isEmpty {
                avatarByUID[t.otherUserID] = url
            } else if let url = authorAvatarURLByUsername[t.otherUsername.lowercased()], !url.isEmpty {
                avatarByUID[t.otherUserID] = url
            }
        }
        let follows = WhisperFollowService.shared
        WhisperWidgetSync.write(
            threads: threads,
            threadAvatarURLs: avatarByUID,
            activeStoryAuthors: storyInfos,
            followerCount: follows.followerCount,
            followingCount: follows.followingCount
        )
    }

    /// Replies to an Jasper DM with a real Jasper chat answer. Appends an
    /// `@ember` inbound bubble to the local conversation + thread summary so
    /// the UI updates immediately. No Supabase write — Jasper has no user_id.
    ///
    /// Routes through `WhisperEmberEngine` — the SAME shared brain, health
    /// context and interpreter the full-screen Jasper chat uses — so the Jasper
    /// in a DM is literally the same assistant as the standalone Jasper chat.
    private func handleEmberDMReply(to userText: String) async {
        let account = AccountStorage.currentUserID; let generation = AccountStorage.generation
        var ctx = await WhisperEmberHealthContext.build()
        guard account == AccountStorage.currentUserID, generation == AccountStorage.generation, !Task.isCancelled else { return }
        // Nutrition questions pull the REAL diet plan off the Connect API
        // live — the @ember DM path is the same assistant as the full chat.
        if let dietBlock = await WhisperEmberJasperPull.enrichment(for: userText) {
            ctx = WhisperEmberHealthContext(
                text: "\(ctx.text)\n\n\(dietBlock)",
                series: ctx.series,
                hasWhisperData: ctx.hasWhisperData
            )
        }
        guard account == AccountStorage.currentUserID, generation == AccountStorage.generation else { return }
        // Build running history from the @ember conversation (the optimistic
        // outbound bubble was already appended before this runs).
        let history: [WhisperEmberBrainService.ChatMessage] = (conversations["ember"] ?? [])
            .suffix(10)
            .map { row in
                WhisperEmberBrainService.ChatMessage(
                    role: row.from_user_id.lowercased() == "ember" ? "assistant" : "user",
                    content: row.body
                )
            }
        let reply = await WhisperEmberEngine().respond(
            message: userText,
            context: ctx,
            history: history
        )
        guard account == AccountStorage.currentUserID, generation == AccountStorage.generation, !Task.isCancelled else { return }
        let answer = reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // The engine already tried its tuned fallback. Do not start an
        // unrelated third request that could lose preferences or account scope.
        let body = answer.isEmpty ? "Couldn't reach Jasper just now. Please try again." : answer
        let iso = ISO8601DateFormatter()
        let row = WhisperMessageRow(
            id: "local-ember-\(UUID().uuidString)",
            from_user_id: "ember",
            from_username: "ember",
            to_user_id: currentUID,
            to_username: LeaderboardService.shared.savedUsername ?? "you",
            body: body,
            created_at: iso.string(from: Date())
        )
        var list = conversations["ember"] ?? []
        list.append(row)
        conversations["ember"] = list
        if let idx = threads.firstIndex(where: { $0.otherUserID == "ember" }) {
            threads[idx] = WhisperConversationSummary(
                otherUserID: "ember",
                otherUsername: "ember",
                lastMessage: body,
                lastDate: Date(),
                lastFromMe: false,
                lastReadByMe: true
            )
        } else {
            threads.insert(WhisperConversationSummary(
                otherUserID: "ember",
                otherUsername: "ember",
                lastMessage: body,
                lastDate: Date(),
                lastFromMe: false,
                lastReadByMe: true
            ), at: 0)
        }
        threads.sort { $0.lastDate > $1.lastDate }
        cacheWidgetSnapshot()
    }

    @discardableResult
    func sendMessage(toUserID: String, toUsername: String, body: String, conversationKind: WhisperConversationKind = .direct, requiresConfirmedDelivery: Bool = false, messageID: UUID? = nil, logicalGroupMessageID: UUID? = nil) async -> Bool {
        await sendMessage(toUserID: toUserID, toUsername: toUsername, body: body, embed: nil, conversationKind: conversationKind, requiresConfirmedDelivery: requiresConfirmedDelivery, messageID: messageID, logicalGroupMessageID: logicalGroupMessageID)
    }

    /// Same as `sendMessage(...)` but also writes a JSON object into the
    /// `whisper_messages.embed` jsonb column. Used by v2 coach proposals
    /// (macros / diet_plan / exercise_swap / note) where the embed is the
    /// source of truth for the client and the prefixed `body` is just a
    /// human-readable fallback. The `embed` column is droppable — if the
    /// deployed schema doesn't have it yet the send still succeeds with
    /// body-only.
    @discardableResult
    func sendMessage(
        toUserID: String,
        toUsername: String,
        body: String,
        embed: [String: AnyJSON]?,
        conversationKind: WhisperConversationKind = .direct,
        requiresConfirmedDelivery: Bool = false,
        messageID: UUID? = nil,
        logicalGroupMessageID: UUID? = nil
    ) async -> Bool {
        let senderID = currentUID
        let accountGeneration = AccountStorage.generation
        let stillCurrent = { !Task.isCancelled && AccountStorage.generation == accountGeneration && self.currentUID.lowercased() == senderID.lowercased()
            && self.client.auth.currentUser?.id.uuidString.lowercased() == senderID.lowercased() }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // De-dupe rapid duplicate sends (double-tap on Send, accidental
        // re-entry while the previous request is still inflight).
        let dedupeKey = "\(senderID.lowercased())|\(conversationKind.rawValue)|\(toUserID.lowercased())|\(trimmed)"
        if inFlightSendKeys.contains(dedupeKey) {
            print("[Whisper] Duplicate send suppressed")
            // A pending insert is not a receipt for the share tray's retry ledger.
            return !requiresConfirmedDelivery
        }
        inFlightSendKeys.insert(dedupeKey)
        defer { inFlightSendKeys.remove(dedupeKey) }
        guard !toUserID.isEmpty else {
            lastError = "Can't send: this user has no Supabase account yet."
            return false
        }
        guard isRemote else {
            lastError = "Sign in to Whisper to send messages."
            return false
        }
        // Verify there's an actual Supabase auth session whose JWT uid matches
        // the user_id we're inserting. If not, RLS will reject the insert with
        // a generic error — we want to tell the user up-front.
        let sessionUID: String? = try? await client.auth.session.user.id.uuidString.lowercased()
        if let sessionUID, sessionUID != currentUID.lowercased() {
            lastError = "Auth mismatch: signed-in user (\(sessionUID.prefix(8))…) doesn't match Whisper user (\(currentUID.prefix(8))…). Sign out and back in to fix."
            print("[Whisper] sendMessage auth mismatch: session=\(sessionUID) account=\(currentUID)")
            return false
        }
        if sessionUID == nil {
            lastError = "No Supabase auth session. Sign out of Whisper and sign in again so messages can be sent."
            return false
        }
        // Resolve the sender's username from the strongest source available.
        // Without this, a fresh install / signed-in-but-not-yet-hydrated user
        // would write the literal string "you" into `from_username`, which
        // then renders on the recipient's side as "you sent…".
        guard stillCurrent() else { return false }
        let hydrated = await LeaderboardService.shared.hydrateUsernameFromSupabase()
        guard stillCurrent() else { return false }
        let fromUsername = WhisperUserService.shared.me?.username
            ?? LeaderboardService.shared.savedUsername
            ?? hydrated
            ?? AuthenticationService.shared.currentUser.username
            ?? "user"
        // Flexible payload so we can progressively drop any column
        // the deployed `whisper_messages` table is missing (most commonly
        // `from_username` / `to_username`). Required: from_user_id, to_user_id, body.
        // Deterministic thread id so both users land in the same conversation.
        let threadID = conversationKind.threadID(senderID, toUserID)
        var payload: [String: AnyJSON] = [
            "from_user_id": .string(senderID),
            "from_username": .string(fromUsername),
            "to_user_id": .string(toUserID),
            "to_username": .string(toUsername),
            "thread_id": .string(threadID),
            "body": .string(trimmed)
        ]
        if let embed { payload["embed"] = .object(embed) }
        if let messageID { payload["id"] = .string(messageID.uuidString.lowercased()) }
        if let logicalGroupMessageID { payload["logical_group_message_id"] = .string(logicalGroupMessageID.uuidString.lowercased()) }
        // Any of these can be progressively dropped if the deployed schema
        // doesn't have the column (Postgres reports `column ... does not exist`).
        let droppable: Set<String> = ["from_username", "to_username", "embed"]

        // Call control signals piggyback on whisper_messages but must never
        // render as bubbles. Skip the optimistic-insert / thread-summary path
        // for them so they never appear in the sender's chat as raw JSON.
        let isControlSignal = WhisperCallSignal.isSignal(trimmed)
        // Group fan-out rows ride 1:1 rows but belong to the GROUP thread —
        // they must never touch the recipient's personal inbox row.
        let touchesInbox = !isControlSignal && !Self.isGroupWire(trimmed)
        // Optimistic local insert FIRST so the bubble is in the conversation
        // before the realtime echo can race against it. If the insert later
        // fails we remove the placeholder. This is the only ordering that
        // reliably prevents both "message disappears" and "message duplicates"
        // — the realtime ingestor dedupes against local- prefixed rows.
        let otherKey = toUserID.lowercased()
        let optimisticID = "local-\(UUID().uuidString)"
        var didSend = false
        defer {
            if AccountStorage.generation == accountGeneration {
                if !didSend {
                    conversations[otherKey]?.removeAll { $0.id == optimisticID }
                    if touchesInbox { recomputeThreadSummariesFromCache() }
                }
                if didSend && Self.isGroupWire(trimmed) { WhisperGroupChatService.shared.invalidateInboxSummaries() }
            }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let optimistic = WhisperMessageRow(
            id: optimisticID,
            from_user_id: currentUID,
            from_username: fromUsername,
            to_user_id: toUserID,
            to_username: toUsername,
            body: trimmed,
            created_at: iso.string(from: Date()),
            thread_id: threadID,
            logical_group_message_id: logicalGroupMessageID?.uuidString.lowercased()
        )
        if !isControlSignal {
            var optimisticList = conversations[otherKey] ?? []
            optimisticList.append(optimistic)
            conversations[otherKey] = optimisticList
        }
        if touchesInbox { recomputeThreadSummariesFromCache() }

        // Intercept DMs sent to the synthetic `ember` user — short-circuit
        // the Supabase insert and run an in-app Jasper chat reply instead.
        // This makes Jasper behave like the standalone Jasper assistant but
        // inside the regular DM thread UI.
        if toUserID.lowercased() == "ember" {
            didSend = true
            inFlightSendKeys.remove(dedupeKey)
            Task { await self.handleEmberDMReply(to: trimmed) }
            return true
        }

        for _ in 0..<4 {
            guard stillCurrent() else { return false }
            do {
                if messageID != nil {
                    let confirmed: WhisperMessageRow = try await client.from("whisper_messages")
                        .insert(payload).select().single().execute().value
                    guard stillCurrent() else { return false }
                    cacheConfirmedShare(confirmed, replacing: optimisticID, otherKey: otherKey, touchesInbox: touchesInbox)
                } else {
                    if isControlSignal {
                        try await client.from("whisper_messages").insert(payload).execute()
                    } else {
                        let confirmed: WhisperMessageRow = try await client.from("whisper_messages")
                            .insert(payload).select().single().execute().value
                        guard stillCurrent() else { return false }
                        cacheConfirmedShare(confirmed, replacing: optimisticID, otherKey: otherKey, touchesInbox: touchesInbox)
                    }
                }
                didSend = true
                guard stillCurrent() else { return false }
                lastError = nil
                if !isControlSignal {
                    Analytics.record("dm_sent", ["thread": threadID])
                }
                // Fire-and-forget Jasper chat-safety scan when the DM crosses
                // an adult ↔ minor age boundary. Skips control signals,
                // stickers/GIFs (URL-only bodies), and structured embeds —
                // the classifier has no useful signal on those and every
                // skip saves an LLM call.
                let isURLOnly: Bool = {
                    let t = trimmed
                    guard t.hasPrefix("http://") || t.hasPrefix("https://") else { return false }
                    return !t.contains(" ") && !t.contains("\n")
                }()
                let isStructuredEmbed = trimmed.hasPrefix("::whisper-") || embed != nil
                let isScannable = !isControlSignal && !isURLOnly && !isStructuredEmbed
                if isScannable {
                    let bodyCopy = trimmed
                    let fromID = currentUID
                    let toID = toUserID
                    let toName = toUsername
                    Task.detached {
                        await Self.runSafetyScan(
                            messageBody: bodyCopy,
                            fromUserID: fromID,
                            toUserID: toID,
                            toUsername: toName
                        )
                    }
                    // Mentions fanout — uses the deterministic threadID as
                    // the source id so recipients can deep-link to the chat.
                    let dmThreadID = threadID
                    let dmAuthorID = currentUID
                    let dmAuthorName = fromUsername
                    Task { @MainActor in
                        await WhisperMentionsService.shared.record(
                            sourceType: .dm,
                            sourceID: dmThreadID,
                            body: bodyCopy,
                            authorID: dmAuthorID,
                            authorUsername: dmAuthorName
                        )
                    }
                }
                return true
            } catch {
                guard stillCurrent() else { return false }
                let msg = error.localizedDescription
                if let column = Self.missingColumnName(in: msg),
                   droppable.contains(column),
                   payload[column] != nil {
                    payload.removeValue(forKey: column)
                    continue
                }
                // A response may be lost after commit. Reconcile this exact share, never a similar body.
                if let messageID, !(error is CancellationError) {
                    let rows: [WhisperMessageRow]? = try? await client.from("whisper_messages").select()
                        .eq("id", value: messageID.uuidString.lowercased())
                        .eq("from_user_id", value: senderID).limit(1).execute().value
                    guard stillCurrent() else { return false }
                    if let row = rows?.first,
                       row.id.lowercased() == messageID.uuidString.lowercased(),
                       row.from_user_id.lowercased() == senderID.lowercased(),
                       row.to_user_id.lowercased() == toUserID.lowercased(),
                       row.thread_id?.lowercased() == threadID.lowercased(), row.body == trimmed {
                        didSend = true
                        cacheConfirmedShare(row, replacing: optimisticID, otherKey: otherKey, touchesInbox: touchesInbox)
                        lastError = nil
                        return true
                    }
                }
                // Rollback the optimistic placeholder since we won't be
                // retrying further.
                if var list = conversations[otherKey] {
                    list.removeAll { $0.id == optimisticID }
                    conversations[otherKey] = list
                }
                if requiresConfirmedDelivery {
                    lastError = "Couldn't confirm delivery. Keep sharing open and retry."
                    return false
                }
                // Direct user action — surface the real reason instead of
                // letting `record(…)` silently swallow RLS / recursion errors.
                if error is CancellationError { return false }
                let ns = error as NSError
                let detail = (ns.userInfo["message"] as? String)
                    ?? (ns.userInfo["details"] as? String)
                    ?? (ns.userInfo["hint"] as? String)
                    ?? msg
                let lower = (msg + " " + detail).lowercased()
                if lower.contains("foreign key") || lower.contains("violates foreign key") {
                    // Comprehensive fix: drop EVERY fkey on whisper_messages
                    // (covers both default name & any custom name), reload the
                    // PostgREST schema cache. Uses proper $ dollar-quoting
                    // (the earlier version used a single $ which is invalid
                    // plpgsql and silently failed when pasted).
                    let sql = """
                    -- Run this once in Supabase → SQL editor → Run.
                    -- Removes the auth.users FK from whisper_messages so you
                    -- can DM any user in whisper_profiles, even ones who
                    -- haven't completed full Supabase auth yet.
                    do $
                    declare r record;
                    begin
                      for r in
                        select conname from pg_constraint
                        where conrelid = 'public.whisper_messages'::regclass
                          and contype = 'f'
                      loop
                        execute format('alter table public.whisper_messages drop constraint %I', r.conname);
                      end loop;
                    end $;
                    notify pgrst, 'reload schema';
                    """
                    // Write on MainActor explicitly so the clipboard
                    // actually receives the value (UIPasteboard writes
                    // from background contexts can be dropped silently).
                    await MainActor.run {
                        UIPasteboard.general.string = sql
                    }
                    pendingFixSQL = sql
                    pendingFixTitle = "Fix: @\(toUsername) isn't in auth.users yet"
                    lastError = "@\(toUsername) isn't a Supabase auth user yet. Tap the banner to view & copy the one-time fix SQL."
                } else if lower.contains("relation") && lower.contains("does not exist") {
                    lastError = "`whisper_messages` table is missing. Run the Whisper schema SQL."
                } else if lower.contains("infinite recursion") {
                    lastError = "Supabase RLS recursion on `whisper_messages`. Drop & recreate its policies (see SQL)."
                } else if lower.contains("row-level security") || lower.contains("violates row-level") || lower.contains("new row violates") {
                    lastError = "Message not delivered. A block, messaging restriction, or missing contact permission may prevent this send. Recipients can manage permitted contacts in Settings → Decisions & appeals. A previous message alone is not permission."
                } else {
                    // Show the raw error so we can diagnose anything unusual.
                    lastError = "Send failed [\(ns.code)]: \(detail)"
                }
                WhisperErrorService.shared.report(lower.contains("row-level") || lower.contains("violates row-level") ? "Message not delivered. Check contact permissions in Settings → Decisions & appeals. Blocks and restrictions still apply." : "Couldn't send message. Try again.")
                Analytics.record("dm_failed", ["reason": String(detail.prefix(80))])
                print("[Whisper] sendMessage error full: \(error) | userInfo: \(ns.userInfo)")
                return false
            }
        }
        return false
    }

    /// Reconcile an ID-stable share without duplicating its realtime echo or optimistic row.
    private func cacheConfirmedShare(_ row: WhisperMessageRow, replacing optimisticID: String, otherKey: String, touchesInbox: Bool) {
        var list = conversations[otherKey] ?? []
        list.removeAll { $0.id == optimisticID || $0.id.lowercased() == row.id.lowercased() }
        list.append(row)
        conversations[otherKey] = list
        if touchesInbox {
            inboxMutationRows[row.conversationKind.localKey(peer: otherKey)] = row
            recomputeThreadSummariesFromCache()
        }
    }

    /// PER-THREAD SORTED INDEX CACHE. `messages(with:)` used to filter AND
    /// re-sort the raw rows — parsing two ISO dates per comparison — every
    /// time a view body asked for it, and the open thread asks a dozen times
    /// per render (every keystroke). That was the message-screen lag. The
    /// sorted rows are now built once per data change (cheap signature: row
    /// count · first/last id · read count · hidden count) and served from
    /// memory; observation-ignored so a cache fill inside a body never
    /// re-renders.
    private struct ThreadIndex {
        let signature: String
        let all: [WhisperMessageRow]
        let direct: [WhisperMessageRow]
    }
    @ObservationIgnored private var threadIndex: [String: ThreadIndex] = [:]

    private func threadIndex(for otherUserID: String) -> ThreadIndex {
        let key = otherUserID.lowercased()
        let raw = conversations[key] ?? []
        let hidden = locallyDeletedMessageIDs
        let signature = "\(messageRevision)|\(hidden.hashValue)"
        if let cached = threadIndex[key], cached.signature == signature { return cached }
        // Sort chronologically by parsed date so a placeholder row with a
        // client-local ISO timestamp never jumps around the canonical server
        // row. Strip call-control signals and rows hidden via "Delete for me".
        // Dates are parsed ONCE per row, never per comparison.
        let dated: [(row: WhisperMessageRow, date: Date)] = raw.compactMap { row in
            guard row.from_user_id.lowercased() == currentUIDLower || row.to_user_id.lowercased() == currentUIDLower,
                  !WhisperCallSignal.isSignal(row.body), !hidden.contains(row.id) else { return nil }
            return (row, Self.parseISO(row.created_at) ?? .distantPast)
        }
        let all = dated.sorted { $0.date == $1.date ? $0.row.id < $1.row.id : $0.date < $1.date }.map(\.row)
        let direct = all.filter { !Self.isGroupWire($0.body) }
        let built = ThreadIndex(signature: signature, all: all, direct: direct)
        threadIndex[key] = built
        return built
    }

    /// Every visible row of a conversation, chronological — INCLUDING the
    /// group fan-out rows (the group service reads those out of here).
    func messages(with otherUserID: String) -> [WhisperMessageRow] {
        threadIndex(for: otherUserID).all
    }

    /// The 1:1 conversation only — group fan-out rows excluded. This is what
    /// the DM thread, the inbox peek, and every personal surface should read.
    func directMessages(with otherUserID: String, kind: WhisperConversationKind = .direct) -> [WhisperMessageRow] {
        WhisperMeetMessageIdentity.collapse(threadIndex(for: otherUserID).direct.filter { $0.conversationKind == kind })
    }

    /// Hides a single message on this device only. The Supabase row is left
    /// untouched; the other person still sees the bubble. Use this for
    /// "Delete for me". Hidden IDs persist across launches.
    func hideMessageLocally(_ messageID: String) {
        guard !messageID.isEmpty else { return }
        WhisperMessageCache.invalidate(ids: [messageID])
        locallyDeletedMessageIDs.insert(messageID)
        messageRevision &+= 1
        AccountStorage.set(
            Array(locallyDeletedMessageIDs),
            forKey: "whisper_local_deleted_msg_ids"
        )
        // Refresh the thread summary preview so the inbox doesn't keep
        // showing the just-hidden body as the last message.
        recomputeThreadSummariesFromCache()
    }

    /// Unsends a message the current user sent — deletes the row in Supabase
    /// (RLS policy `wm delete sender` enforces ownership) and removes it from
    /// every local cache so the bubble disappears immediately on this device.
    /// The other device removes its copy via the realtime DELETE channel
    /// (see `startMessagesRealtime`). Optimistic local-only rows are simply
    /// dropped from the cache. Returns `true` when the delete is acknowledged.
    @discardableResult
    func unsendMessage(_ msg: WhisperMessageRow) async -> Bool {
        let generation = AccountStorage.generation
        let meLower = currentUIDLower
        guard msg.from_user_id.lowercased() == meLower else {
            lastError = "You can only unsend messages you sent."
            return false
        }
        let otherKey = (msg.from_user_id.lowercased() == meLower ? msg.to_user_id : msg.from_user_id).lowercased()

        // Exclude in-flight unsends from summary SELECTs until acknowledged.
        unsendingInboxIDs.insert(msg.id)
        defer {
            if AccountStorage.generation == generation, currentUIDLower == meLower {
                unsendingInboxIDs.remove(msg.id)
                invalidateInboxSummaries()
            }
        }
        // Optimistically remove locally so the bubble disappears instantly.
        WhisperMessageCache.invalidate(ids: [msg.id])
        if !historyRequestIDs.isEmpty { historyDeletedIDs.insert(msg.id) }
        if var list = conversations[otherKey] {
            list.removeAll { $0.id == msg.id }
            conversations[otherKey] = list
        }
        recomputeThreadSummariesFromCache()

        // Local-only optimistic row (never reached the server) — nothing to delete.
        if msg.id.hasPrefix("local-") { return true }

        guard isRemote else { return true }
        do {
            try await client.from("whisper_messages")
                .delete()
                .eq("id", value: msg.id)
                .execute()
            guard AccountStorage.generation == generation, currentUIDLower == meLower else { return false }
            inboxRows.removeAll { $0.last_message_id == msg.id }
            inboxMutationRows = inboxMutationRows.filter { $0.value.id != msg.id }
            return true
        } catch {
            guard AccountStorage.generation == generation, currentUIDLower == meLower else { return false }
            // Re-insert so the user sees the failure instead of a silent ghost.
            historyDeletedIDs.remove(msg.id)
            if var list = conversations[otherKey] {
                list.append(msg)
                list.sort { ($0.created_at ?? "") < ($1.created_at ?? "") }
                conversations[otherKey] = list
            }
            recomputeThreadSummariesFromCache()
            lastError = "Couldn't unsend: \(error.localizedDescription)"
            return false
        }
    }

    /// Marks every inbound message from `otherUserID` as read on the
    /// server. Updates the local cache + thread summary immediately so the
    /// inbox dot/bold-preview clears before the network round-trip lands.
    /// Schema requirement: `whisper_messages.read_at timestamptz` plus an
    /// RLS update policy where `auth.uid() = to_user_id`. Falls back
    /// silently if the column / policy isn't deployed yet.
    func markRead(otherUserID: String, kind: WhisperConversationKind = .direct) async {
        let key = otherUserID.lowercased()
        if var rows = conversations[key] {
            let now = ISO8601DateFormatter().string(from: Date())
            var changed = false
            for index in rows.indices where rows[index].id.hasPrefix("local-ember-") && rows[index].to_user_id.lowercased() == currentUIDLower && rows[index].read_at == nil {
                rows[index].read_at = now; changed = true
            }
            if changed { conversations[key] = rows; recomputeThreadSummariesFromCache(); cacheWidgetSnapshot() }
        }
        let ids = WhisperMessageReadScope.unreadIDs(rows: directMessages(with: otherUserID, kind: kind), recipient: currentUIDLower, sender: otherUserID)
        await markMessageIDsRead(ids)
    }

    /// Acknowledge only loaded rows from the viewed conversation, never a sender's other groups.
    func markMessageIDsRead(_ messageIDs: [String]) async {
        guard isRemote, !messageIDs.isEmpty else { return }
        let account = AccountStorage.currentUserID
        let generation = AccountStorage.generation
        let me = currentUIDLower
        let ids = Array(Set(messageIDs.filter { UUID(uuidString: $0) != nil })).sorted()
        let nowISO = ISO8601DateFormatter().string(from: Date())
        for start in stride(from: 0, to: ids.count, by: 100) {
            let batch = Array(ids[start..<min(start + 100, ids.count)])
            for attempt in 0..<2 {
                do {
                    try WhisperChatMediaService.checkAccount(account, generation: generation)
                    let saved: [WhisperMessageRow] = try await client.from("whisper_messages")
                        .update(["read_at": nowISO])
                        .eq("to_user_id", value: me)
                        .in("id", values: batch)
                        .select().execute().value
                    try WhisperChatMediaService.checkAccount(account, generation: generation)
                    let confirmed = Set(saved.filter { $0.read_at != nil }.map(\.id))
                    guard confirmed == Set(batch) else { throw NSError(domain: "ReadReceipt", code: 1) }
                    let byID = Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                    for key in Array(conversations.keys) {
                        guard let rows = conversations[key], rows.contains(where: { confirmed.contains($0.id) }) else { continue }
                        conversations[key] = rows.map { byID[$0.id] ?? $0 }
                    }
                    recomputeThreadSummariesFromCache()
                    cacheWidgetSnapshot()
                    break
                } catch {
                    guard AccountStorage.currentUserID == account, AccountStorage.generation == generation, !Task.isCancelled else { return }
                    if attempt == 0 { try? await Task.sleep(for: .seconds(1)) }
                    else { print("[Whisper] read acknowledgment not confirmed; will retry on next view") }
                }
            }
        }
    }

    /// Publish server-owned summaries plus explicit pending/confirmed local
    /// mutations. Downloaded history is never an inbox or unread authority.
    private func recomputeThreadSummariesFromCache(mutation: Bool = true) {
        if mutation { invalidateInboxSummaries() }
        let hidden = locallyDeletedMessageIDs.union(unsendingInboxIDs)
        var summaries = inboxRows.filter { !hidden.contains($0.last_message_id) }.map { $0.summary(owner: currentUIDLower) }
        for otherKey in conversations.keys where otherKey != currentUIDLower {
            let visible = threadIndex(for: otherKey).direct
            for kind in WhisperConversationKind.allCases {
                // Only pending sends and the local assistant overlay the
                // server authority. History reads cannot erase quiet peers or
                // replace complete unread totals with a 100-row estimate.
                let key = kind.localKey(peer: otherKey)
                var scoped = visible.filter { $0.conversationKind == kind && ($0.id.hasPrefix("local-") || otherKey == "ember") }
                if let overlay = inboxMutationRows[key], !hidden.contains(overlay.id) {
                    scoped.insert(overlay, at: 0)
                }
                scoped.sort { ($0.created_at ?? "", $0.id) < ($1.created_at ?? "", $1.id) }
                guard let last = scoped.last else { continue }
                let fromMe = last.from_user_id.lowercased() == currentUIDLower
                if !last.id.hasPrefix("local-"), let baseline = summaries.first(where: { $0.id == key }),
                   baseline.lastDate > (Self.parseISO(last.created_at) ?? .distantPast) { continue }
                let previousRead = summaries.first(where: { $0.id == key })?.lastReadByMe ?? true
                summaries.removeAll { $0.id == key }
                summaries.append(WhisperConversationSummary(
                    otherUserID: otherKey,
                    otherUsername: fromMe ? last.to_username : last.from_username,
                    lastMessage: last.body,
                    lastDate: Self.parseISO(last.created_at) ?? .distantPast,
                    lastFromMe: fromMe,
                    lastReadByMe: previousRead && !scoped.contains { $0.to_user_id.lowercased() == currentUIDLower && $0.read_at == nil },
                    kind: kind
                ))
            }
        }
        threads = summaries.sorted { $0.lastDate == $1.lastDate ? $0.id < $1.id : $0.lastDate > $1.lastDate }
        cacheWidgetSnapshot()
    }

    // MARK: - Workouts (read directly from existing public.user_data blob)
    //
    // Whisper already mirrors `workoutSessionHistory` (a JSON-encoded
    // `[WorkoutSessionRecord]`) into the `public.user_data` table via
    // `SupabaseSyncService`. Whisper just reads from that same source so we
    // don't have to duplicate workouts into a `whisper_workouts` table.

    nonisolated private struct UserDataRow: Decodable, Sendable {
        let data_key: String
        let data_blob: String?
        let updated_at: String?
    }

    /// Pulls the current user's workouts directly from `public.user_data` and
    /// converts them into `WhisperWorkoutRow` for the existing UI.
    func fetchWorkouts(limit: Int = 200) async {
        guard isRemote else { workouts = []; return }
        // Always make sure the local workout history is mirrored up first so
        // the row exists in `public.user_data`. This is a no-op when there is
        // nothing locally or the blob is unchanged.
        await SupabaseSyncService.shared.pushBlob(
            userID: currentUID,
            storageKey: "workoutSessionHistory"
        )
        var records = await fetchWorkoutRecords(forUserID: currentUID)
        // Fallback: if the cloud blob is empty (first run, or the user is
        // signed in on a brand new device), use the local copy directly so
        // the UI still shows the user's workouts immediately.
        if records.isEmpty,
           let data = AccountStorage.data(forKey: "workoutSessionHistory"),
           let local = try? JSONDecoder().decode([WorkoutSessionRecord].self, from: data) {
            records = local.sorted { $0.date > $1.date }
        }
        let iso = ISO8601DateFormatter()
        workouts = records.prefix(limit).map { r in
            WhisperWorkoutRow(
                id: r.id.uuidString,
                user_id: currentUID,
                display_name: r.displayName,
                focus: r.focus,
                duration_seconds: Int(r.duration),
                calories: Int(r.caloriesBurned),
                exercises_count: r.exercises.count,
                performed_at: iso.string(from: r.date),
                created_at: iso.string(from: r.date)
            )
        }
    }

    /// Reads any user's workout history blob from `public.user_data`.
    /// Returns `[]` for guests, missing rows, or decode failures.
    func fetchWorkoutRecords(forUserID userID: String) async -> [WorkoutSessionRecord] {
        guard userID != "guest", !userID.hasPrefix("local_") else { return [] }
        do {
            let rows: [UserDataRow] = try await client
                .from("user_data")
                .select("data_key,data_blob,updated_at")
                .eq("user_id", value: userID)
                .eq("data_key", value: "workoutSessionHistory")
                .limit(1)
                .execute()
                .value
            guard let b64 = rows.first?.data_blob,
                  let data = Data(base64Encoded: b64),
                  !data.isEmpty else { return [] }
            let decoded = try JSONDecoder().decode([WorkoutSessionRecord].self, from: data)
            return decoded.sorted { $0.date > $1.date }
        } catch {
            print("[Whisper] fetchWorkoutRecords error: \(error)")
            return []
        }
    }

    /// Mirrors the local workouts blob up to Supabase using the existing
    /// `SupabaseSyncService` pipeline (writes the same `workoutSessionHistory`
    /// row Whisper already syncs). Kept for API compatibility — no new tables.
    func syncLocalWorkouts(_ records: [WorkoutSessionRecord]) async {
        guard isRemote else { return }
        await SupabaseSyncService.shared.pushBlob(
            userID: currentUID,
            storageKey: "workoutSessionHistory"
        )
        await fetchWorkouts()
    }

    // MARK: - Public profile lookup (reads existing public.profiles)

    nonisolated struct WhisperPublicProfile: Decodable, Sendable, Hashable {
        let id: String
        let username: String?
        let display_name: String?
        let profile_image_url: String?
        let is_verified: Bool?
    }

    /// Looks up a user's public profile (avatar/username/display name).
    /// Prefers `whisper_profiles` (the canonical Whisper username source with
    /// permissive public-read RLS) so mobile resolves usernames the same way
    /// the web app does. Falls back to the legacy `profiles` table.
    func fetchPublicProfile(userID: String) async -> WhisperPublicProfile? {
        guard userID != "guest", !userID.hasPrefix("local_") else { return nil }
        // Query both tables in parallel so a user with only a Whisper profile
        // still resolves even if the legacy `profiles` lookup fails.
        async let whisperTask: WhisperPublicProfile? = fetchSingleWhisperProfile(userID: userID)
        async let legacyTask: WhisperPublicProfile? = fetchSingleLegacyProfile(userID: userID)
        let (whisper, legacy) = await (whisperTask, legacyTask)
        return whisper ?? legacy
    }

    private func fetchSingleWhisperProfile(userID: String) async -> WhisperPublicProfile? {
        nonisolated struct WPRow: Codable, Sendable {
            let user_id: String
            let username: String
            let display_name: String?
            let profile_image_url: String?
        }
        do {
            let rows: [WPRow] = try await client
                .from("whisper_profiles")
                .select("user_id,username,display_name,profile_image_url")
                .eq("user_id", value: userID)
                .limit(1)
                .execute()
                .value
            if let row = rows.first {
                return WhisperPublicProfile(
                    id: row.user_id,
                    username: row.username,
                    display_name: row.display_name,
                    profile_image_url: row.profile_image_url,
                    is_verified: nil
                )
            }
        } catch {
            // Fall through to legacy below.
        }
        return nil
    }

    private func fetchSingleLegacyProfile(userID: String) async -> WhisperPublicProfile? {
        do {
            let row: WhisperPublicProfile = try await client
                .from("profiles")
                .select("id,username,display_name,profile_image_url,is_verified")
                .eq("id", value: userID)
                .single()
                .execute()
                .value
            return row
        } catch {
            return nil
        }
    }

    /// Bulk variant for feeds/grids — returns a `[userID: profile]` map.
    ///
    /// Queries both `whisper_profiles` and `profiles` in parallel and merges
    /// the results, preferring `whisper_profiles` (the canonical Whisper source)
    /// over the legacy `profiles` table. This fixes the case where a user has
    /// a Whisper profile row but no legacy `profiles` row, which the web app
    /// handles but iOS was missing when the sequential fallback chain failed.
    func fetchPublicProfiles(userIDs: [String]) async -> [String: WhisperPublicProfile] {
        let ids = userIDs.filter { $0 != "guest" && !$0.hasPrefix("local_") }
        guard !ids.isEmpty else { return [:] }

        // Parallel fetch from both sources so a failure in one never hides
        // the other. The canonical Whisper table wins on conflict.
        async let whisperMap = fetchWhisperProfiles(userIDs: ids)
        async let legacyMap = fetchLegacyProfiles(userIDs: ids)
        let (whisper, legacy) = await (whisperMap, legacyMap)

        var merged: [String: WhisperPublicProfile] = [:]
        for id in ids {
            let lower = id.lowercased()
            let profile = whisper[id] ?? whisper[lower] ?? legacy[id] ?? legacy[lower]
            if let profile { merged[id] = profile }
        }

        // If neither direct table returned useful rows, try the SECURITY
        // DEFINER RPC as a last resort (it bypasses RLS and already merges
        // both tables server-side).
        if merged.isEmpty {
            do {
                let rows: [WhisperPublicProfile] = try await client
                    .rpc("whisper_public_profiles", params: ["uids": ids])
                    .execute()
                    .value
                for row in rows { merged[row.id] = row }
            } catch {
                // RPC not installed or failed — leave merged empty.
            }
        }
        return merged
    }

    private func fetchWhisperProfiles(userIDs: [String]) async -> [String: WhisperPublicProfile] {
        nonisolated struct WPRow: Codable, Sendable {
            let user_id: String
            let username: String
            let display_name: String?
            let profile_image_url: String?
        }
        do {
            let rows: [WPRow] = try await client
                .from("whisper_profiles")
                .select("user_id,username,display_name,profile_image_url")
                .in("user_id", values: userIDs)
                .execute()
                .value
            return Dictionary(
                rows.map {
                    ($0.user_id, WhisperPublicProfile(
                        id: $0.user_id,
                        username: $0.username,
                        display_name: $0.display_name,
                        profile_image_url: $0.profile_image_url,
                        is_verified: nil
                    ))
                },
                uniquingKeysWith: { a, _ in a }
            )
        } catch {
            return [:]
        }
    }

    private func fetchLegacyProfiles(userIDs: [String]) async -> [String: WhisperPublicProfile] {
        do {
            let rows: [WhisperPublicProfile] = try await client
                .from("profiles")
                .select("id,username,display_name,profile_image_url,is_verified")
                .in("id", values: userIDs)
                .execute()
                .value
            return Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        } catch {
            return [:]
        }
    }

    // MARK: - Realtime

    /// Subscribes to `whisper_messages` inserts addressed to the current user
    /// and merges them into local state. Idempotent — calling twice is a no-op.
    func startMessagesRealtime() {
        guard isRemote, messagesChannel == nil else { return }
        let uid = currentUID
        let channel = client.realtimeV2.channel("whisper-msgs-\(uid)")
        messagesChannel = channel
        let inbound = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "whisper_messages",
            filter: "to_user_id=eq.\(uid)"
        )
        let outbound = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "whisper_messages",
            filter: "from_user_id=eq.\(uid)"
        )
        // Deletes do not support row-level filters (Postgres realtime only
        // ships primary keys for DELETE), so we subscribe table-wide and
        // filter locally by checking whether the id is in any conversation.
        let deletions = channel.postgresChange(
            DeleteAction.self,
            schema: "public",
            table: "whisper_messages"
        )
        // Updates carry the new `read_at` so the sender's "Seen" pill can
        // appear in realtime when the recipient opens the thread. Filter
        // server-side to our outbound rows since we only need updates to
        // messages we sent.
        let updates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "whisper_messages",
            filter: "from_user_id=eq.\(uid)"
        )
        let channelGeneration = AccountStorage.generation
        let inboundUpdates = channel.postgresChange(UpdateAction.self, schema: "public", table: "whisper_messages", filter: "to_user_id=eq.\(uid)")
        messagesTask = Task { [weak self] in
            await channel.subscribe()
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    for await change in inbound {
                        guard await MainActor.run(body: { AccountStorage.generation == channelGeneration }), !Task.isCancelled else { return }
                        await self?.ingestRealtimeMessage(change)
                    }
                }
                group.addTask { [weak self] in
                    for await change in outbound {
                        guard await MainActor.run(body: { AccountStorage.generation == channelGeneration }), !Task.isCancelled else { return }
                        await self?.ingestRealtimeMessage(change)
                    }
                }
                group.addTask { [weak self] in
                    for await change in deletions {
                        guard await MainActor.run(body: { AccountStorage.generation == channelGeneration }), !Task.isCancelled else { return }
                        await self?.ingestRealtimeDeletion(change)
                    }
                }
                group.addTask { [weak self] in
                    for await change in updates {
                        guard await MainActor.run(body: { AccountStorage.generation == channelGeneration }), !Task.isCancelled else { return }
                        await self?.ingestRealtimeUpdate(change)
                    }
                }
                group.addTask { [weak self] in
                    for await change in inboundUpdates {
                        guard await MainActor.run(body: { AccountStorage.generation == channelGeneration }), !Task.isCancelled else { return }
                        await self?.ingestRealtimeUpdate(change)
                    }
                }
                // Realtime drops during network blips lose everything sent
                // while offline — including CALL INVITES. On every
                // re-subscribe, refetch threads and replay recent call
                // signals so incoming calls still ring after a reconnect
                // (the same recovery the meeting signaling channel uses).
                group.addTask { [weak self, weak channel] in
                    guard let channel else { return }
                    var sawFirstSubscribe = false
                    for await status in channel.statusChange {
                        if Task.isCancelled { return }
                        guard status == .subscribed else { continue }
                        if !sawFirstSubscribe {
                            sawFirstSubscribe = true
                            continue
                        }
                        await self?.fetchThreads()
                        await WhisperGroupChatService.shared.syncRegistry(force: true)
                        await self?.replayRecentCallSignals()
                    }
                }
            }
        }
    }

    /// Handles UPDATE notifications for `whisper_messages` (currently only
    /// `read_at` flips). Mirrors the change into the in-memory conversation
    /// row so the sender's "Seen" pill appears without waiting for the
    /// next `fetchThreads`.
    private func ingestRealtimeUpdate(_ action: UpdateAction) async {
        guard let row = try? action.decodeRecord(as: WhisperMessageRow.self, decoder: JSONDecoder()) else { return }
        let me = currentUIDLower
        let fromLower = row.from_user_id.lowercased()
        let toLower = row.to_user_id.lowercased()
        guard fromLower == me || toLower == me, !Task.isCancelled else { return }
        let other = fromLower == me ? toLower : fromLower
        guard !other.isEmpty, other != me else { return }
        WhisperMessageCache.invalidate(ids: [row.id])
        // Updates outside the downloaded window can change unread totals.
        invalidateInboxSummaries()
        if Self.isGroupWire(row.body) { WhisperGroupChatService.shared.invalidateInboxSummaries() }
        guard var list = conversations[other] else { return }
        guard let idx = list.firstIndex(where: { $0.id == row.id }) else { return }
        list[idx] = row
        conversations[other] = list
        recomputeThreadSummariesFromCache()
        cacheWidgetSnapshot()
    }

    /// Pulls the last ~90s of `whisper_messages` and replays any still-live
    /// call invite signals through `WhisperCallService.handleSignal`. This is
    /// what makes "tap the push to answer" actually work: when the app was
    /// fully backgrounded the realtime channel was paused, so the `invite`
    /// row arrived as a push but never reached the call service. On foreground
    /// we look for invites that don't have a matching terminal signal (accept
    /// from us, or cancel/decline/end from either side) and surface the
    /// incoming-call sheet for them.
    func replayRecentCallSignals() async {
        guard isRemote else { return }
        let generation = AccountStorage.generation
        let uid = currentUID
        let meLower = currentUIDLower
        guard !uid.isEmpty, !meLower.isEmpty else { return }
        // 90s window — long enough to catch a push the user just tapped,
        // short enough to never replay an invite that already rang out.
        let since = Date().addingTimeInterval(-90)
        let sinceISO = ISO8601DateFormatter().string(from: since)
        async let inboundQ: [WhisperMessageRow] = (try? await client
            .from("whisper_messages")
            .select()
            .eq("to_user_id", value: uid)
            .gte("created_at", value: sinceISO)
            .order("created_at", ascending: true)
            .limit(100)
            .execute()
            .value) ?? []
        async let outboundQ: [WhisperMessageRow] = (try? await client
            .from("whisper_messages")
            .select()
            .eq("from_user_id", value: uid)
            .gte("created_at", value: sinceISO)
            .order("created_at", ascending: true)
            .limit(100)
            .execute()
            .value) ?? []
        let (inboundRows, outboundRows) = await (inboundQ, outboundQ)
        guard !Task.isCancelled, generation == AccountStorage.generation, currentUIDLower == meLower else { return }
        let all = (inboundRows + outboundRows).sorted {
            (Self.parseISO($0.created_at) ?? .distantPast) <
            (Self.parseISO($1.created_at) ?? .distantPast)
        }
        // Group signals by call id, remember the most recent kind.
        struct CallTrace {
            var invite: (row: WhisperMessageRow, payload: WhisperCallSignal.Payload)?
            var terminated: Bool = false
        }
        var traces: [String: CallTrace] = [:]
        for row in all {
            guard let p = WhisperCallSignal.decodeCompat(row.body) else { continue }
            var t = traces[p.id] ?? CallTrace()
            switch p.kind {
            case .invite:
                // Only treat as a live invite if it came from someone else.
                if row.from_user_id.lowercased() != meLower {
                    t.invite = (row, p)
                }
            case .accept, .decline, .cancel, .end:
                t.terminated = true
            case .ice:
                break
            }
            traces[p.id] = t
        }
        // Surface any non-terminated invites the call service doesn't know
        // about yet. handleSignal is idempotent for a call we already track.
        for (_, trace) in traces {
            guard !trace.terminated, let invite = trace.invite else { continue }
            WhisperCallService.shared.handleSignal(
                invite.payload,
                fromUserID: invite.row.from_user_id,
                fromUsername: invite.row.from_username,
                currentUID: uid
            )
        }
    }

    func resetMessageAccount() {
        invalidateReferencedPosts()
        stopMessagesRealtime()
        stopPostsRealtime()
        postFetches.values.forEach { $0.cancel() }; postFetches = [:]
        postEnrichmentID = UUID(); postEnrichmentTask?.cancel(); postEnrichmentTask = nil
        needsPostEnrichment = false
        feedPageRevision = UUID(); feedNext = nil
        feedMoreTask?.cancel(); feedMoreTask = nil; isLoadingMorePosts = false; morePostsError = nil
        lastMyPostsFetch = nil; lastThreadsFetch = nil
        ownPostFetches.values.forEach { $0.cancel() }; ownPostFetches = [:]
        ownPostsCacheTask?.cancel(); ownPostsCacheTask = nil; ownPostsWindowLimit = 0
        threadFetch?.cancel(); threadFetch = nil
        inboxRevision = UUID(); inboxRequestID = UUID()
        inboxTask?.cancel(); inboxTask = nil; inboxRefreshTask?.cancel(); inboxRefreshTask = nil
        inboxRows = []; inboxMutationRows = [:]; inboxNext = nil; inboxPageCount = 1; inboxHasMore = false
        isLoadingInboxPage = false; inboxPageError = nil; inboxRetryOlder = false; unsendingInboxIDs = []
        myPostsLoadedGeneration = nil; postsLoadError = nil; myPostsLoadError = nil
        deletedPostIDs = []; deletingPostIDs = []
        posts = []; myPosts = []; myLikedPostIDs = []; myLikedCommentIDs = []
        postLikesTask?.cancel(); postLikesTask = nil
        pendingPostLikeIDs = []; activePostLikeIDs = []; likeMutationRevisions = [:]; pendingLikeMutations = []; postLikesFetchedAt = [:]
        commentFetches.values.forEach { $0.cancel() }
        commentFetches = [:]; commentFetchIDs = [:]; commentFetchedAt = [:]
        commentsByPostID = [:]; commentLoadErrors = [:]; workouts = []; postAuthorProfiles = [:]; authorAvatarURLByUsername = [:]
        avatarHydrationAttempted = []; profileHydrationAttempted = []
        isLoadingPosts = false; lastPostsFetch = nil; lastError = nil
        hasLoadedThreads = false; isLoadingThreads = false; threadsLoadError = nil
        historyRequestIDs = [:]; historyStates = [:]; activeHistoryScopes = [:]; activeGroupHistoryScopes = []; historyDeletedIDs = []
        conversations = [:]; threads = []; threadIndex = [:]; threadProfiles = [:]
        WhisperChatThreadIndex.shared.clear()
        locallyDeletedMessageIDs = Set((AccountStorage.object(forKey: "whisper_local_deleted_msg_ids") as? [String]) ?? [])
    }

    func stopMessagesRealtime() {
        messagesTask?.cancel()
        messagesTask = nil
        if let ch = messagesChannel {
            Task { await ch.unsubscribe() }
        }
        messagesChannel = nil
    }

    /// Handles realtime DELETE notifications from `whisper_messages`.
    /// Postgres only ships the primary key on deletes, so we look the id up
    /// in our in-memory conversations and remove it from whichever thread
    /// owns it. Thread summaries are recomputed to keep inbox previews fresh.
    private func ingestRealtimeDeletion(_ action: DeleteAction) async {
        guard let raw = action.oldRecord["id"] else { return }
        let deletedID: String
        switch raw {
        case .string(let s): deletedID = s
        default: deletedID = String(describing: raw)
        }
        guard !deletedID.isEmpty else { return }
        WhisperMessageCache.invalidate(ids: [deletedID])
        if !historyRequestIDs.isEmpty { historyDeletedIDs.insert(deletedID) }
        for (key, list) in conversations {
            if list.contains(where: { $0.id == deletedID }) {
                conversations[key] = list.filter { $0.id != deletedID }
            }
        }
        inboxRows.removeAll { $0.last_message_id == deletedID }
        inboxMutationRows = inboxMutationRows.filter { $0.value.id != deletedID }
        // Unknown deletes may change unloaded peers and complete unread totals.
        WhisperGroupChatService.shared.invalidateInboxSummaries(removingMessageIDs: [deletedID.lowercased()])
        recomputeThreadSummariesFromCache()
    }

    private func ingestRealtimeMessage(_ action: InsertAction) async {
        guard let row = try? action.decodeRecord(as: WhisperMessageRow.self, decoder: JSONDecoder()) else {
            // Fall back to a fetch if the live row failed to decode.
            await fetchThreads()
            return
        }
        let me = currentUIDLower
        let fromLower = row.from_user_id.lowercased()
        let toLower = row.to_user_id.lowercased()
        guard fromLower == me || toLower == me, !Task.isCancelled else { return }
        let other = fromLower == me ? toLower : fromLower
        if other == me || other.isEmpty { return }
        // Call control signals piggyback on whisper_messages but must never
        // render as bubbles or pop a banner. Route them to the call service
        // and bail before the conversation/thread mutation.
        if let signal = WhisperCallSignal.decodeCompat(row.body) {
            WhisperCallService.shared.handleSignal(
                signal,
                fromUserID: row.from_user_id,
                fromUsername: row.from_username,
                currentUID: currentUID
            )
            return
        }
        var list = conversations[other] ?? []
        // Drop any optimistic placeholder we inserted in `sendMessage` that
        // matches this canonical row, so we don't end up with duplicate
        // bubbles once the realtime echo arrives.
        // Lowercase both sides — Postgres normalizes uuid columns, so a
        // local optimistic row whose `from_user_id` retains uppercase from
        // `AccountStorage.currentUserID` would otherwise fail to match the
        // realtime echo and the bubble would render twice for the sender.
        let rowFromLower = row.from_user_id.lowercased()
        let rowBody = row.body
        list.removeAll { ph in
            ph.id.hasPrefix("local-") &&
            ph.from_user_id.lowercased() == rowFromLower &&
            ph.conversationKind == row.conversationKind && ph.body == rowBody
        }
        if !list.contains(where: { $0.id == row.id }) {
            list.append(row)
            list.sort { ($0.created_at ?? "") < ($1.created_at ?? "") }
            conversations[other] = list
        }
        // Local notification for messages I received (not echoes of my own send).
        if fromLower != me {
            // The arrival is felt in-app too — a soft bump and falling pair.
            if UIApplication.shared.applicationState == .active {
                WhisperFeedback.received()
            }
            WhisperNotificationService.shared.notifyIncomingMessage(
                messageID: row.id,
                fromUsername: row.from_username,
                fromUID: row.from_user_id,
                currentUID: currentUID,
                body: row.body,
                threadID: row.thread_id
            )
        }
        // Refresh thread summary list — group fan-out rows belong to the
        // GROUP thread only and never touch the personal inbox row.
        guard !Self.isGroupWire(row.body) else {
            WhisperGroupChatService.shared.invalidateInboxSummaries()
            await WhisperGroupChatService.shared.syncRegistry()
            return
        }
        inboxMutationRows[row.conversationKind.localKey(peer: other)] = row
        recomputeThreadSummariesFromCache()
    }

    /// Subscribes to `whisper_posts` inserts so the feed updates live.
    func startPostsRealtime() {
        guard isRemote, postsChannel == nil else { return }
        let channel = client.realtimeV2.channel("whisper-posts")
        postsChannel = channel
        let stream = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "whisper_posts"
        )
        let generation = AccountStorage.generation
        postsTask = Task { [weak self] in
            await channel.subscribe()
            for await change in stream {
                guard let self, !Task.isCancelled, generation == AccountStorage.generation else { return }
                if let row = try? change.decodeRecord(as: WhisperPostRow.self, decoder: JSONDecoder()),
                   !self.deletedPostIDs.contains(row.id.lowercased()) {
                    if !self.posts.contains(where: { $0.id == row.id }) {
                        self.posts.insert(row, at: 0)
                    }
                }
            }
        }
    }

    // Return-to-posting alerts are server-owned. A realtime row alone cannot
    // prove the posting gap, interaction evidence or cross-device rate limits.

    func stopPostsRealtime() {
        postsTask?.cancel()
        postsTask = nil
        if let ch = postsChannel {
            Task { await ch.unsubscribe() }
        }
        postsChannel = nil
    }

    // MARK: - Safety scan hook

    /// Detached entry point used by `sendMessage`. Lazily loads the sender +
    /// recipient age bands, decides if a cross-boundary scan is warranted,
    /// and — if the Jasper classifier returns a low/medium/high verdict —
    /// writes a strike against the adult side of the conversation.
    static func runSafetyScan(
        messageBody: String,
        fromUserID: String,
        toUserID: String,
        toUsername: String
    ) async {
        let trimmed = messageBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !fromUserID.isEmpty, !toUserID.isEmpty else { return }

        let safety = await WhisperSafetyService.shared
        await safety.preloadAgeBands(userIDs: [fromUserID, toUserID])

        let senderBand: WhisperAgeBand = await safety.ageBand(forUserID: fromUserID)
        let recipientBand: WhisperAgeBand = await safety.ageBand(forUserID: toUserID)
        // Only scan when one side is adult and the other is teen.
        let senderIsAdult = (senderBand == .adult)
        let recipientIsTeen = (recipientBand == .teen)
        // Never attribute a teen-authored message to its adult recipient.
        guard senderIsAdult && recipientIsTeen else { return }
        let generation = AccountStorage.generation
        guard SupabaseService.shared.client.auth.currentUser?.id.uuidString.lowercased() == fromUserID.lowercased() else { return }

        let guardSvc = EmberChatGuardService()
        let verdict = await guardSvc.classify(
            message: trimmed,
            senderIsAdult: senderIsAdult,
            recipientIsTeen: recipientIsTeen
        )
        guard verdict.severity != .none, verdict.severity != .low else {
            // Low / none never get a row — strikes are reserved for medium+.
            return
        }
        guard generation == AccountStorage.generation else { return }
        // This is a private review signal, never a strike or automatic restriction.
        let adultUserID = fromUserID
        let adultUsername: String? = nil
        let otherUserID = toUserID
        await safety.recordStrike(
            targetUserID: adultUserID,
            targetUsername: adultUsername,
            otherUserID: otherUserID,
            category: verdict.category,
            severity: verdict.severity,
            excerpt: trimmed,
            reasoning: verdict.reasoning
        )
    }
}

/*
 ─────────────────────────────────────────────────────────────────────
 Run this once in your Supabase SQL editor. It is non-destructive —
 every statement uses `if not exists`, so it's safe to re-run and will
 not touch the existing Whisper tables.
 ─────────────────────────────────────────────────────────────────────

 -- POSTS
 create table if not exists public.whisper_posts (
   id uuid primary key default gen_random_uuid(),
   user_id uuid not null references auth.users(id) on delete cascade,
   username text not null,
   kind text not null check (kind in ('photo','workout','progress','text')),
   caption text not null default '',
   symbol text,
   accent_hex text,
   media_count int not null default 0,
   media_urls text[],
   is_ghost boolean not null default false,
   likes_count int not null default 0,
   comments_count int not null default 0,
   created_at timestamptz not null default now()
 );
 -- Add media_urls if upgrading from the original schema
 alter table public.whisper_posts
   add column if not exists media_urls text[];
 create index if not exists whisper_posts_created_idx
   on public.whisper_posts (created_at desc);
 create index if not exists whisper_posts_user_idx
   on public.whisper_posts (user_id, created_at desc);
 alter table public.whisper_posts enable row level security;
 create policy "wp read all" on public.whisper_posts for select using (true);
 create policy "wp insert own" on public.whisper_posts
   for insert with check (auth.uid() = user_id);
 create policy "wp update own" on public.whisper_posts
   for update using (auth.uid() = user_id);
 create policy "wp delete own" on public.whisper_posts
   for delete using (auth.uid() = user_id);

 -- LIKES
 create table if not exists public.whisper_post_likes (
   post_id uuid not null references public.whisper_posts(id) on delete cascade,
   user_id uuid not null references auth.users(id) on delete cascade,
   created_at timestamptz not null default now(),
   primary key (post_id, user_id)
 );
 alter table public.whisper_post_likes enable row level security;
 create policy "wpl read all" on public.whisper_post_likes for select using (true);
 create policy "wpl insert own" on public.whisper_post_likes
   for insert with check (auth.uid() = user_id);
 create policy "wpl delete own" on public.whisper_post_likes
   for delete using (auth.uid() = user_id);

 -- Trigger: keep whisper_posts.likes_count in sync
 create or replace function public.whisper_likes_bump() returns trigger
 language plpgsql as $$
 begin
   if (tg_op = 'INSERT') then
     update public.whisper_posts set likes_count = likes_count + 1 where id = new.post_id;
   elsif (tg_op = 'DELETE') then
     update public.whisper_posts set likes_count = greatest(likes_count - 1, 0) where id = old.post_id;
   end if;
   return null;
 end;
 $$;
 drop trigger if exists whisper_likes_bump_trg on public.whisper_post_likes;
 create trigger whisper_likes_bump_trg
   after insert or delete on public.whisper_post_likes
   for each row execute function public.whisper_likes_bump();

 -- COMMENTS
 create table if not exists public.whisper_post_comments (
   id uuid primary key default gen_random_uuid(),
   post_id uuid not null references public.whisper_posts(id) on delete cascade,
   user_id uuid not null references auth.users(id) on delete cascade,
   username text not null,
   body text not null check (char_length(body) <= 1000),
   created_at timestamptz not null default now()
 );
 create index if not exists whisper_comments_post_idx
   on public.whisper_post_comments (post_id, created_at);
 alter table public.whisper_post_comments enable row level security;
 create policy "wpc read all" on public.whisper_post_comments for select using (true);
 create policy "wpc insert own" on public.whisper_post_comments
   for insert with check (auth.uid() = user_id);
 create policy "wpc delete own" on public.whisper_post_comments
   for delete using (auth.uid() = user_id);

 create or replace function public.whisper_comments_bump() returns trigger
 language plpgsql as $$
 begin
   if (tg_op = 'INSERT') then
     update public.whisper_posts set comments_count = comments_count + 1 where id = new.post_id;
   elsif (tg_op = 'DELETE') then
     update public.whisper_posts set comments_count = greatest(comments_count - 1, 0) where id = old.post_id;
   end if;
   return null;
 end;
 $$;
 drop trigger if exists whisper_comments_bump_trg on public.whisper_post_comments;
 create trigger whisper_comments_bump_trg
   after insert or delete on public.whisper_post_comments
   for each row execute function public.whisper_comments_bump();

 -- DIRECT MESSAGES
 create table if not exists public.whisper_messages (
   id uuid primary key default gen_random_uuid(),
   from_user_id uuid not null references auth.users(id) on delete cascade,
   from_username text not null,
   to_user_id   uuid not null references auth.users(id) on delete cascade,
   to_username  text not null,
   body text not null check (char_length(body) <= 4000),
   created_at timestamptz not null default now()
 );
 create index if not exists whisper_messages_to_idx
   on public.whisper_messages (to_user_id, created_at desc);
 create index if not exists whisper_messages_from_idx
   on public.whisper_messages (from_user_id, created_at desc);
 alter table public.whisper_messages enable row level security;
 create policy "wm read involved" on public.whisper_messages
   for select using (auth.uid() = from_user_id or auth.uid() = to_user_id);
 create policy "wm insert sender" on public.whisper_messages
   for insert with check (auth.uid() = from_user_id);
 create policy "wm delete sender" on public.whisper_messages
   for delete using (auth.uid() = from_user_id);

 -- WORKOUT MIRROR (optional — share workouts as posts cleanly)
 -- The Whisper workout history lives in the client only today. If you want
 -- workouts to be reachable from any device a user signs in on, mirror
 -- them into Supabase here. Whisper reads either source.
 create table if not exists public.whisper_workouts (
   id uuid primary key,
   user_id uuid not null references auth.users(id) on delete cascade,
   display_name text not null,
   focus text not null,
   duration_seconds int not null,
   calories int not null,
   exercises_count int not null default 0,
   performed_at timestamptz not null,
   created_at timestamptz not null default now()
 );
 create index if not exists whisper_workouts_user_idx
   on public.whisper_workouts (user_id, performed_at desc);
 alter table public.whisper_workouts enable row level security;
 create policy "ww read own" on public.whisper_workouts
   for select using (auth.uid() = user_id);
 create policy "ww insert own" on public.whisper_workouts
   for insert with check (auth.uid() = user_id);
 create policy "ww update own" on public.whisper_workouts
   for update using (auth.uid() = user_id);
 create policy "ww delete own" on public.whisper_workouts
   for delete using (auth.uid() = user_id);
*/
