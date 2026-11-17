import Foundation
import Supabase

// MARK: - Rows

nonisolated struct WhisperFilmCommentRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let film_id: String
    let user_id: String
    let body: String
    let reply_to_comment_id: String?
    let created_at: String?
}

nonisolated struct WhisperFilmTimestampRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let film_id: String
    let user_id: String?
    let label: String
    let time_seconds: Int
    let poster_url: String?
    let created_at: String?
}

nonisolated struct WhisperFilmReactions: Sendable, Equatable {
    var likes: Int = 0
    var dislikes: Int = 0
    /// "like" | "dislike" | nil
    var mine: String? = nil
}

/// Lightweight commenter profile hydrated from `whisper_profiles` so film
/// comments show real handles + avatars (the comments table only stores
/// user_id — mirrors the web app's hydration).
nonisolated struct WhisperFilmProfileLite: Codable, Sendable, Hashable {
    let user_id: String
    let username: String?
    let display_name: String?
    let profile_image_url: String?
}

// MARK: - Service

/// Film engagement — reactions (like/dislike), threaded comments, and the
/// timestamp "moments" rail — reading and writing the exact same Supabase
/// tables as the web film page (`whisper_film_reactions`,
/// `whisper_film_comments`, `whisper_film_timestamps`), so both apps stay
/// in perfect sync.
@MainActor
@Observable
final class WhisperFilmEngagementService {
    static let shared = WhisperFilmEngagementService()

    private let client = SupabaseService.shared.client

    var reactionsByFilm: [String: WhisperFilmReactions] = [:]
    var commentsByFilm: [String: [WhisperFilmCommentRow]] = [:]
    var timestampsByFilm: [String: [WhisperFilmTimestampRow]] = [:]
    var profilesByUser: [String: WhisperFilmProfileLite] = [:]
    var lastError: String?

    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    private init() {}

    // MARK: - Full refresh

    func refresh(filmID: String) async {
        async let a: Void = refreshReactions(filmID: filmID)
        async let b: Void = refreshComments(filmID: filmID)
        async let c: Void = refreshTimestamps(filmID: filmID)
        _ = await (a, b, c)
    }

    // MARK: - Reactions

    private nonisolated struct ReactionCountRow: Codable, Sendable {
        let like_count: Int?
        let dislike_count: Int?
    }
    private nonisolated struct MyReactionRow: Codable, Sendable {
        let id: String?
        let weight: String?
    }
    private nonisolated struct ReactionInsert: Codable, Sendable {
        let film_id: String
        let user_id: String
        let weight: String
    }
    private nonisolated struct ReactionUpdate: Codable, Sendable {
        let weight: String
    }

    func refreshReactions(filmID: String) async {
        var result = WhisperFilmReactions()
        do {
            let counts: [ReactionCountRow] = try await client
                .from("whisper_film_reaction_counts")
                .select("like_count,dislike_count")
                .eq("film_id", value: filmID)
                .limit(1)
                .execute()
                .value
            result.likes = counts.first?.like_count ?? 0
            result.dislikes = counts.first?.dislike_count ?? 0
        } catch {
            // View may not exist yet — leave zeros.
        }
        if isRemote {
            do {
                let mine: [MyReactionRow] = try await client
                    .from("whisper_film_reactions")
                    .select("id,weight")
                    .eq("film_id", value: filmID)
                    .eq("user_id", value: currentUID)
                    .limit(1)
                    .execute()
                    .value
                result.mine = mine.first?.weight
            } catch {
                // best-effort
            }
        }
        reactionsByFilm[filmID] = result
    }

    /// Same toggle contract as the web: tapping your current reaction takes
    /// it back; tapping the other side switches it. Optimistic, then a
    /// truth refresh.
    func setReaction(filmID: String, weight: String) async {
        guard isRemote else { return }
        var current = reactionsByFilm[filmID] ?? WhisperFilmReactions()
        let previous = current

        do {
            let existing: [MyReactionRow] = try await client
                .from("whisper_film_reactions")
                .select("id,weight")
                .eq("film_id", value: filmID)
                .eq("user_id", value: currentUID)
                .limit(1)
                .execute()
                .value

            if let row = existing.first, row.weight == weight, let id = row.id {
                // Take back.
                current.mine = nil
                if weight == "like" { current.likes = max(0, current.likes - 1) }
                else { current.dislikes = max(0, current.dislikes - 1) }
                reactionsByFilm[filmID] = current
                try await client.from("whisper_film_reactions")
                    .delete()
                    .eq("id", value: id)
                    .execute()
            } else if let row = existing.first, let id = row.id {
                // Switch sides.
                current.mine = weight
                if weight == "like" {
                    current.likes += 1
                    current.dislikes = max(0, current.dislikes - 1)
                } else {
                    current.dislikes += 1
                    current.likes = max(0, current.likes - 1)
                }
                reactionsByFilm[filmID] = current
                try await client.from("whisper_film_reactions")
                    .update(ReactionUpdate(weight: weight))
                    .eq("id", value: id)
                    .execute()
            } else {
                // First reaction.
                current.mine = weight
                if weight == "like" { current.likes += 1 } else { current.dislikes += 1 }
                reactionsByFilm[filmID] = current
                try await client.from("whisper_film_reactions")
                    .insert(ReactionInsert(film_id: filmID, user_id: currentUID, weight: weight))
                    .execute()
            }
            Analytics.record("film_reaction", ["film_id": filmID, "weight": weight])
        } catch {
            reactionsByFilm[filmID] = previous
            lastError = "Couldn't save your reaction."
        }
    }

    // MARK: - Comments

    private nonisolated struct CommentInsert: Codable, Sendable {
        let film_id: String
        let user_id: String
        let body: String
        let reply_to_comment_id: String?
    }

    func refreshComments(filmID: String) async {
        do {
            let rows: [WhisperFilmCommentRow] = try await client
                .from("whisper_film_comments")
                .select("id,film_id,user_id,body,reply_to_comment_id,created_at")
                .eq("film_id", value: filmID)
                .order("created_at", ascending: true)
                .limit(200)
                .execute()
                .value
            commentsByFilm[filmID] = rows
            await hydrateProfiles(userIDs: rows.map { $0.user_id })
        } catch {
            // Table may not exist yet — keep whatever we had.
        }
    }

    @discardableResult
    func addComment(filmID: String, body: String, replyTo: String?) async -> Bool {
        guard isRemote else { return false }
        let trimmed = String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
        guard !trimmed.isEmpty else { return false }
        do {
            try await client.from("whisper_film_comments")
                .insert(CommentInsert(
                    film_id: filmID,
                    user_id: currentUID,
                    body: trimmed,
                    reply_to_comment_id: replyTo
                ))
                .execute()
            await refreshComments(filmID: filmID)
            Analytics.record("film_comment", ["film_id": filmID])
            return true
        } catch {
            lastError = "Couldn't post that comment."
            return false
        }
    }

    func deleteComment(id: String, filmID: String) async {
        guard isRemote else { return }
        do {
            try await client.from("whisper_film_comments")
                .delete()
                .eq("id", value: id)
                .eq("user_id", value: currentUID)
                .execute()
            commentsByFilm[filmID]?.removeAll { $0.id == id || $0.reply_to_comment_id == id }
        } catch {
            lastError = "Couldn't delete that comment."
        }
    }

    /// Root comments newest-first; replies conversation-order under parents.
    func threadedComments(filmID: String) -> [(root: WhisperFilmCommentRow, replies: [WhisperFilmCommentRow])] {
        let rows = commentsByFilm[filmID] ?? []
        let roots = rows.filter { $0.reply_to_comment_id == nil }
            .sorted { ($0.created_at ?? "") > ($1.created_at ?? "") }
        return roots.map { root in
            let replies = rows.filter { $0.reply_to_comment_id == root.id }
                .sorted { ($0.created_at ?? "") < ($1.created_at ?? "") }
            return (root, replies)
        }
    }

    // MARK: - Timestamps

    func refreshTimestamps(filmID: String) async {
        do {
            let rows: [WhisperFilmTimestampRow] = try await client
                .from("whisper_film_timestamps")
                .select("id,film_id,user_id,label,time_seconds,poster_url,created_at")
                .eq("film_id", value: filmID)
                .order("time_seconds", ascending: true)
                .limit(60)
                .execute()
                .value
            timestampsByFilm[filmID] = rows
        } catch {
            // best-effort
        }
    }

    // MARK: - Profiles

    private var hydratedProfileIDs = Set<String>()

    private func hydrateProfiles(userIDs: [String]) async {
        let missing = Set(userIDs).subtracting(hydratedProfileIDs)
        guard !missing.isEmpty else { return }
        hydratedProfileIDs.formUnion(missing)
        do {
            let rows: [WhisperFilmProfileLite] = try await client
                .from("whisper_profiles")
                .select("user_id,username,display_name,profile_image_url")
                .in("user_id", values: Array(missing))
                .execute()
                .value
            for row in rows {
                profilesByUser[row.user_id] = row
            }
        } catch {
            // Comments still render with the fallback handle.
        }
    }

    func handle(for userID: String) -> String {
        profilesByUser[userID]?.username
            ?? profilesByUser[userID]?.display_name
            ?? "member"
    }

    // MARK: - Film lookup (article embeds)

    private nonisolated struct FilmRow: Codable, Sendable {
        let id: String
        let director_id: String?
        let title: String
        let synopsis: String?
        let video_url: String
        let poster_url: String?
        let duration_seconds: Int?
        let featured_date: String?
    }

    /// Fetches one published film by id — used by article readers to embed
    /// the linked film / clip.
    func fetchFilm(id: String) async -> WhisperFeedFilm? {
        do {
            let rows: [FilmRow] = try await client
                .from("whisper_films")
                .select("id,director_id,title,synopsis,video_url,poster_url,duration_seconds,featured_date")
                .eq("id", value: id)
                .eq("published", value: true)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { return nil }
            var directorName: String?
            var directorUsername: String?
            if let did = row.director_id {
                await hydrateProfiles(userIDs: [did])
                directorName = profilesByUser[did]?.display_name
                directorUsername = profilesByUser[did]?.username
            }
            return WhisperFeedFilm(
                id: row.id,
                title: row.title,
                synopsis: row.synopsis,
                video_url: row.video_url,
                poster_url: row.poster_url,
                duration_seconds: row.duration_seconds,
                featured_date: row.featured_date,
                director_id: row.director_id,
                director_name: directorName,
                director_username: directorUsername
            )
        } catch {
            return nil
        }
    }
}
