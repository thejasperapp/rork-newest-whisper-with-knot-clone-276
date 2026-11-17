import Foundation
import Supabase

/// Tracks Whisper One membership so the black "+" badge renders next to
/// member usernames everywhere badges appear (feed, profiles, comments).
///
/// Membership is stored on `whisper_profiles.is_one` — the Stripe webhook in
/// the Cloudflare backend flips it when a Whisper One subscription becomes
/// active or lapses. This service just caches those flags per user id and
/// username so `WhisperBadgeKind.active(...)` can consult it synchronously.
@MainActor
@Observable
final class WhisperOneService {
    static let shared = WhisperOneService()

    private let client = SupabaseService.shared.client

    /// Lowercased user_id -> membership flag. `false` entries mark users we
    /// already looked up so we never refetch them.
    private(set) var memberByUserID: [String: Bool] = [:]
    /// Lowercased username -> membership flag.
    private(set) var memberByUsername: [String: Bool] = [:]

    private init() {}

    nonisolated private struct Row: Decodable, Sendable {
        let user_id: String
        let username: String?
        let is_one: Bool?
    }

    /// True when the user id belongs to an active Whisper One member.
    func isOne(userID: String?) -> Bool {
        guard let userID, !userID.isEmpty else { return false }
        return memberByUserID[userID.lowercased()] ?? false
    }

    /// True when the username belongs to an active Whisper One member.
    func isOne(username: String?) -> Bool {
        guard let username, !username.isEmpty else { return false }
        return memberByUsername[username.lowercased()] ?? false
    }

    /// Batch-hydrates membership flags for the given user ids and usernames.
    /// Only unknown keys hit the network; failures degrade to "no badge".
    func preload(userIDs: [String] = [], usernames: [String] = []) async {
        let newIDs = Array(Set(
            userIDs
                .map { $0.lowercased() }
                .filter { !$0.isEmpty && $0 != "guest" && !$0.hasPrefix("local_") && memberByUserID[$0] == nil }
        ))
        let newNames = Array(Set(
            usernames
                .map { $0.lowercased() }
                .filter { !$0.isEmpty && memberByUsername[$0] == nil }
        ))
        guard !newIDs.isEmpty || !newNames.isEmpty else { return }

        // Mark everything requested as known-false first so a failed round
        // trip doesn't cause a refetch storm on every recomposition.
        for id in newIDs { memberByUserID[id] = false }
        for name in newNames { memberByUsername[name] = false }

        if !newIDs.isEmpty {
            do {
                let rows: [Row] = try await client
                    .from("whisper_profiles")
                    .select("user_id,username,is_one")
                    .in("user_id", values: newIDs)
                    .execute()
                    .value
                apply(rows)
            } catch {
                print("[WhisperOne] preload by id failed: \(error.localizedDescription)")
            }
        }
        if !newNames.isEmpty {
            do {
                let rows: [Row] = try await client
                    .from("whisper_profiles")
                    .select("user_id,username,is_one")
                    .in("username", values: newNames)
                    .execute()
                    .value
                apply(rows)
            } catch {
                print("[WhisperOne] preload by username failed: \(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    func refreshCurrentMembership() async -> Bool {
        let owner = AccountStorage.currentUserID
        let generation = AccountStorage.generation
        guard client.auth.currentUser?.id.uuidString.lowercased() == owner.lowercased() else { return false }
        do {
            let row: Row = try await client.from("whisper_profiles").select("user_id,username,is_one")
                .eq("user_id", value: owner).single().execute().value
            guard !Task.isCancelled, generation == AccountStorage.generation else { return false }
            apply([row])
            return true
        } catch { return false }
    }

    private func apply(_ rows: [Row]) {
        for row in rows {
            let flag = row.is_one ?? false
            memberByUserID[row.user_id.lowercased()] = flag
            if let name = row.username?.lowercased(), !name.isEmpty {
                memberByUsername[name] = flag
            }
        }
    }
}
