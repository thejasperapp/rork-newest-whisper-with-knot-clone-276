import Foundation
import Supabase
import SwiftUI

/// Resolves the Whisper Director role (Whisper media team) AND the Whisper
/// Blogger role from their flags on `whisper_profiles` — one query serves
/// both since they live on the same row. Mirrors the lightweight
/// `WhisperRecruiterService` pattern — a shared `@Observable` singleton that
/// the badge system and the Director workspace consult. Both roles are
/// granted from the admin console (never sold).
@MainActor
@Observable
final class WhisperDirectorService {
    static let shared = WhisperDirectorService()

    private let client = SupabaseService.shared.client
    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    /// True when the signed-in user is a Whisper media team director.
    var isMeDirector: Bool = false

    /// True when the signed-in user is a Whisper blogger.
    var isMeBlogger: Bool = false

    /// User ids that are confirmed directors.
    private var directorCache: Set<String> = []
    /// User ids that are confirmed bloggers.
    private var bloggerCache: Set<String> = []
    /// User ids we have already checked (directors or not) so we don't
    /// re-query the same ids. Kept separate from `directorCache` so a
    /// non-director is never mistaken for a director.
    private var checkedCache: Set<String> = []

    private init() {}

    /// Whether a given user id is a director (cached after first lookup).
    func isDirector(userID: String) -> Bool {
        directorCache.contains(userID.lowercased())
    }

    /// Whether a given user id is a blogger (cached after first lookup).
    func isBlogger(userID: String) -> Bool {
        bloggerCache.contains(userID.lowercased())
    }

    /// Refresh the signed-in user's director status from `whisper_profiles`.
    func refreshMyStatus() async {
        guard isRemote else { return }
        do {
            nonisolated struct Row: Codable, Sendable {
                let is_director: Bool?
                let is_blogger: Bool?
            }
            let rows: [Row] = try await client
                .from("whisper_profiles")
                .select("is_director,is_blogger")
                .eq("user_id", value: currentUID.lowercased())
                .limit(1)
                .execute()
                .value
            isMeDirector = rows.first?.is_director ?? false
            isMeBlogger = rows.first?.is_blogger ?? false
            let id = currentUID.lowercased()
            checkedCache.insert(id)
            if isMeDirector { directorCache.insert(id) }
            if isMeBlogger { bloggerCache.insert(id) }
        } catch {
            isMeDirector = false
            isMeBlogger = false
        }
    }

    /// Batch-fetch director flags for a set of user ids so profile badges
    /// resolve without a per-user round-trip.
    func preload(userIDs: [String]) async {
        let ids = Set(userIDs.map { $0.lowercased() }.filter { !$0.isEmpty })
        let needed = ids.subtracting(checkedCache)
        guard !needed.isEmpty, isRemote else { return }
        do {
            nonisolated struct Row: Codable, Sendable {
                let user_id: String
                let is_director: Bool?
                let is_blogger: Bool?
            }
            let rows: [Row] = try await client
                .from("whisper_profiles")
                .select("user_id,is_director,is_blogger")
                .in("user_id", values: Array(needed))
                .execute()
                .value
            for row in rows {
                if row.is_director == true {
                    directorCache.insert(row.user_id.lowercased())
                }
                if row.is_blogger == true {
                    bloggerCache.insert(row.user_id.lowercased())
                }
            }
            // Mark all requested ids as checked; only true directors/
            // bloggers live in their caches.
            checkedCache.formUnion(needed)
        } catch {
            // Silent — director/blogger badges are non-critical.
        }
    }
}
