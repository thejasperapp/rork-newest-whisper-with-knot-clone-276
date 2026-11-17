import Foundation
import Supabase

/// Live moderation — the iOS twin of the web's live moderation layer and
/// the client face of `supabase/live-v2.sql` + `live-v3-hardening.sql`:
///
///   • Channel-level MODS and BANS (per host — a mod moderates every live
///     that host runs; a ban keeps someone out of the whole channel).
///   • Per-room TIMEOUTS (short cool-downs).
///   • Per-room BANNED WORDS (host-set list checked before every send).
///   • GO-LIVE ALERTS fanned out to followers when a host starts a live.
///
/// Client checks give instant, friendly feedback; the database policies
/// from live-v3 are the real wall, so nothing depends on client goodwill.
@MainActor
@Observable
final class WhisperLiveModerationService {
    static let shared = WhisperLiveModerationService()

    private var client: SupabaseClient { SupabaseService.shared.client }

    nonisolated struct ModRow: Codable, Sendable, Hashable {
        let host_id: String
        let mod_user_id: String
        let mod_username: String
    }

    nonisolated struct BanRow: Codable, Sendable, Hashable {
        let host_id: String
        let banned_user_id: String
        let banned_username: String
    }

    nonisolated struct TimeoutRow: Codable, Sendable, Hashable {
        let room_id: String
        let user_id: String
        let username: String
        let until: String
    }

    private(set) var mods: [ModRow] = []
    private(set) var bans: [BanRow] = []
    private(set) var timeouts: [TimeoutRow] = []
    private(set) var bannedWords: [String] = []
    /// Room the current state belongs to — refresh() swaps it atomically.
    private(set) var loadedRoomID: String?

    private init() {}

    // MARK: - Load

    /// Everything the room needs to enforce + render moderation. Missing
    /// tables (live-v2 not run yet) degrade to empty lists silently.
    func refresh(hostID: String, roomID: String) async {
        async let modsReq: [ModRow]? = try? client
            .from("whisper_live_moderators")
            .select("host_id, mod_user_id, mod_username")
            .eq("host_id", value: hostID)
            .execute()
            .value
        async let bansReq: [BanRow]? = try? client
            .from("whisper_live_bans")
            .select("host_id, banned_user_id, banned_username")
            .eq("host_id", value: hostID)
            .execute()
            .value
        async let timeoutsReq: [TimeoutRow]? = try? client
            .from("whisper_live_timeouts")
            .select("room_id, user_id, username, until")
            .eq("room_id", value: roomID)
            .gt("until", value: ISO8601DateFormatter().string(from: Date()))
            .execute()
            .value
        struct WordsRow: Codable { let banned_words: [String]? }
        async let wordsReq: [WordsRow]? = try? client
            .from("whisper_live_rooms")
            .select("banned_words")
            .eq("id", value: roomID)
            .limit(1)
            .execute()
            .value

        let (m, b, t, w) = await (modsReq, bansReq, timeoutsReq, wordsReq)
        mods = m ?? []
        bans = b ?? []
        timeouts = t ?? []
        bannedWords = w?.first?.banned_words ?? []
        loadedRoomID = roomID
    }

    // MARK: - Checks

    func isMod(_ userID: String) -> Bool {
        mods.contains { $0.mod_user_id.lowercased() == userID.lowercased() }
    }

    func isBanned(_ userID: String) -> Bool {
        bans.contains { $0.banned_user_id.lowercased() == userID.lowercased() }
    }

    /// Active timeout expiry for a user, if any.
    func timeoutUntil(_ userID: String) -> Date? {
        let iso = ISO8601DateFormatter()
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for row in timeouts where row.user_id.lowercased() == userID.lowercased() {
            let date = isoFrac.date(from: row.until) ?? iso.date(from: row.until)
            if let date, date > Date() { return date }
        }
        return nil
    }

    /// Why a message can't be sent right now — nil when it's clean.
    /// Mirrors the web room's send gate word for word.
    func blockReason(body: String, userID: String) -> String? {
        if isBanned(userID) {
            return "You're banned from this channel."
        }
        if let until = timeoutUntil(userID) {
            let secs = max(1, Int(until.timeIntervalSinceNow))
            let mins = secs / 60
            return mins >= 1
                ? "You're timed out for \(mins)m \(secs % 60)s."
                : "You're timed out for \(secs)s."
        }
        let lower = body.lowercased()
        if let hit = bannedWords.first(where: { !$0.isEmpty && lower.contains($0) }) {
            return "\"\(hit)\" isn't allowed in this chat."
        }
        return nil
    }

    // MARK: - Actions (host + mods; RLS enforces)

    func timeout(roomID: String, userID: String, username: String, minutes: Int) async -> Bool {
        let until = ISO8601DateFormatter().string(from: Date().addingTimeInterval(TimeInterval(minutes * 60)))
        let payload: [String: AnyJSON] = [
            "room_id": .string(roomID),
            "user_id": .string(userID),
            "username": .string(username),
            "until": .string(until),
        ]
        do {
            try await client
                .from("whisper_live_timeouts")
                .upsert(payload, onConflict: "room_id,user_id")
                .execute()
            timeouts.removeAll { $0.user_id == userID }
            timeouts.append(TimeoutRow(room_id: roomID, user_id: userID, username: username, until: until))
            return true
        } catch {
            return false
        }
    }

    func ban(hostID: String, userID: String, username: String) async -> Bool {
        let payload: [String: AnyJSON] = [
            "host_id": .string(hostID),
            "banned_user_id": .string(userID),
            "banned_username": .string(username),
        ]
        do {
            try await client
                .from("whisper_live_bans")
                .upsert(payload, onConflict: "host_id,banned_user_id")
                .execute()
            if !isBanned(userID) {
                bans.append(BanRow(host_id: hostID, banned_user_id: userID, banned_username: username))
            }
            return true
        } catch {
            return false
        }
    }

    func unban(hostID: String, userID: String) async {
        try? await client
            .from("whisper_live_bans")
            .delete()
            .eq("host_id", value: hostID)
            .eq("banned_user_id", value: userID)
            .execute()
        bans.removeAll { $0.banned_user_id == userID }
    }

    // MARK: - Go-live alerts

    /// Fan out a "went live" alert to the host's followers — capped,
    /// chunked, best-effort; a failure never blocks going live. Mirrors
    /// the web `notifyFollowersLive`, and the unique (room, follower)
    /// index from live-v3 keeps re-flips from double-alerting.
    nonisolated func notifyFollowersLive(
        hostID: String,
        hostUsername: String,
        roomID: String,
        roomName: String
    ) async {
        struct FollowerRow: Codable { let follower_id: String }
        let client = SupabaseService.shared.client
        do {
            let followers: [FollowerRow] = try await client
                .from("whisper_follows")
                .select("follower_id")
                .eq("followee_id", value: hostID)
                .limit(400)
                .execute()
                .value
            let ids = followers.map(\.follower_id).filter { !$0.isEmpty && $0 != hostID }
            guard !ids.isEmpty else { return }
            let rows: [[String: AnyJSON]] = ids.map { fid in
                [
                    "host_id": .string(hostID),
                    "host_username": .string(hostUsername),
                    "room_id": .string(roomID),
                    "room_name": .string(roomName),
                    "follower_id": .string(fid),
                ]
            }
            for start in stride(from: 0, to: rows.count, by: 100) {
                let chunk = Array(rows[start..<min(start + 100, rows.count)])
                do {
                    try await client
                        .from("whisper_live_alerts")
                        .upsert(chunk, onConflict: "room_id,follower_id", ignoreDuplicates: true)
                        .execute()
                } catch {
                    return // table missing or RLS — quietly skip the rest
                }
            }
        } catch {
            // never block going live
        }
    }

    // MARK: - Bell feed (alerts for ME)

    nonisolated struct AlertRow: Codable, Sendable, Identifiable, Hashable {
        let id: String
        let host_id: String
        let host_username: String
        let room_id: String
        let room_name: String
        let created_at: String?
    }

    /// Recent go-live alerts for the signed-in user, newest first —
    /// only rooms that are STILL live survive the filter.
    nonisolated func fetchMyLiveAlerts(userID: String) async -> [AlertRow] {
        let client = SupabaseService.shared.client
        let since = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-6 * 3600))
        do {
            let rows: [AlertRow] = try await client
                .from("whisper_live_alerts")
                .select("id, host_id, host_username, room_id, room_name, created_at")
                .eq("follower_id", value: userID)
                .gte("created_at", value: since)
                .order("created_at", ascending: false)
                .limit(12)
                .execute()
                .value
            guard !rows.isEmpty else { return [] }
            struct LiveRow: Codable { let id: String; let is_live: Bool }
            let roomIDs = Array(Set(rows.map(\.room_id)))
            let liveRows: [LiveRow] = (try? await client
                .from("whisper_live_rooms")
                .select("id, is_live")
                .in("id", values: roomIDs)
                .eq("is_live", value: true)
                .execute()
                .value) ?? []
            let liveSet = Set(liveRows.map(\.id))
            var seenHosts = Set<String>()
            return rows.filter { row in
                guard liveSet.contains(row.room_id) else { return false }
                return seenHosts.insert(row.host_id).inserted
            }
        } catch {
            return []
        }
    }
}
