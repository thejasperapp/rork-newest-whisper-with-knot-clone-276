import Foundation
import Supabase

// MARK: - Supabase schema (run once in SQL editor)
//
// create table if not exists public.leaderboard_entries (
//   user_id text primary key,
//   username text not null unique,
//   steps_week int not null default 0,
//   workouts_week int not null default 0,
//   active_minutes_week int not null default 0,
//   week_id int not null,
//   updated_at timestamptz not null default now()
// );
// create index if not exists leaderboard_steps_idx
//   on public.leaderboard_entries (week_id, steps_week desc);
// create index if not exists leaderboard_workouts_idx
//   on public.leaderboard_entries (week_id, workouts_week desc);
// alter table public.leaderboard_entries enable row level security;
// create policy "read all" on public.leaderboard_entries
//   for select using (true);
// create policy "anon insert" on public.leaderboard_entries
//   for insert with check (true);
// create policy "anon update" on public.leaderboard_entries
//   for update using (true);

nonisolated struct LeaderboardEntryRow: Codable, Sendable, Identifiable {
    let user_id: String
    let username: String
    let steps_week: Int
    let workouts_week: Int
    let active_minutes_week: Int
    let week_id: Int
    let updated_at: String?

    nonisolated var id: String { user_id }
}

nonisolated struct LeaderboardUpsertPayload: Codable, Sendable {
    let user_id: String
    let username: String
    let steps_week: Int
    let workouts_week: Int
    let active_minutes_week: Int
    let week_id: Int
}

nonisolated struct UsernameCheckRow: Codable, Sendable {
    let username: String
}

nonisolated struct UsernameReservationRow: Codable, Sendable {
    let username: String
    let user_id: String
}

enum LeaderboardMetric: String, CaseIterable, Identifiable {
    case steps, workouts, activeMinutes
    var id: String { rawValue }
    var title: String {
        switch self {
        case .steps: return "Steps"
        case .workouts: return "Workouts"
        case .activeMinutes: return "Active Min"
        }
    }
    var icon: String {
        switch self {
        case .steps: return "figure.walk"
        case .workouts: return "dumbbell.fill"
        case .activeMinutes: return "flame.fill"
        }
    }
}

@Observable
@MainActor
final class LeaderboardService {
    static let shared = LeaderboardService()

    var entries: [LeaderboardEntryRow] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var currentMetric: LeaderboardMetric = .steps

    private let client = SupabaseService.shared.client
    private let usernameKey = "leaderboard_username"
    private let lastSyncKey = "leaderboard_last_sync"

    static var currentWeekId: Int {
        let cal = Calendar(identifier: .iso8601)
        let week = cal.component(.weekOfYear, from: Date())
        let year = cal.component(.yearForWeekOfYear, from: Date())
        return year * 100 + week
    }

    var savedUsername: String? {
        AccountStorage.string(forKey: usernameKey)
    }

    /// Pulls the user's reserved username from Supabase and caches it locally.
    /// Used to detect legacy users (signed up before usernames were required)
    /// — if this returns nil, the username gate should be presented.
    @discardableResult
    func hydrateUsernameFromSupabase() async -> String? {
        let userID = AccountStorage.currentUserID
        guard userID != "guest", !userID.hasPrefix("local_") else { return savedUsername }
        // Already cached locally? Trust it.
        if let cached = savedUsername, !cached.isEmpty { return cached }
        do {
            // Primary source of truth for Whisper: `whisper_profiles.username`.
            // This is the canonical row the web app reads, with permissive public
            // RLS, so it resolves the real handle even when the legacy `profiles`
            // row is hidden by restrictive RLS or still carries the "user" placeholder.
            nonisolated struct WhisperProfileUsernameRow: Decodable, Sendable { let username: String? }
            let whisperRows: [WhisperProfileUsernameRow] = try await client
                .from("whisper_profiles")
                .select("username")
                .eq("user_id", value: userID)
                .limit(1)
                .execute()
                .value
            if let name = whisperRows.first?.username, !name.isEmpty {
                AccountStorage.set(name, forKey: usernameKey)
                return name
            }
            // Fallback: `profiles.username` on the user's Supabase auth row.
            nonisolated struct ProfileUsernameRow: Decodable, Sendable { let username: String? }
            let profileRows: [ProfileUsernameRow] = try await client
                .from("profiles")
                .select("username")
                .eq("id", value: userID)
                .limit(1)
                .execute()
                .value
            if let name = profileRows.first?.username, !name.isEmpty {
                AccountStorage.set(name, forKey: usernameKey)
                return name
            }
            // Secondary: dedicated reservation table.
            let rows: [UsernameReservationRow] = try await client
                .from("usernames")
                .select("username,user_id")
                .eq("user_id", value: userID)
                .limit(1)
                .execute()
                .value
            if let name = rows.first?.username, !name.isEmpty {
                AccountStorage.set(name, forKey: usernameKey)
                // Backfill profile row.
                await writeUsernameToProfile(name)
                return name
            }
            // Fall back to leaderboard_entries for users from before the usernames table existed.
            let entries: [UsernameCheckRow] = try await client
                .from("leaderboard_entries")
                .select("username")
                .eq("user_id", value: userID)
                .limit(1)
                .execute()
                .value
            if let legacy = entries.first?.username, !legacy.isEmpty {
                AccountStorage.set(legacy, forKey: usernameKey)
                // Backfill the reservation so the username is locked to this account.
                await reserveUsername(legacy)
                return legacy
            }
            return nil
        } catch {
            return savedUsername
        }
    }

    /// Updates `profiles.username` so the user's profile row carries the
    /// chosen handle (and Supabase admin views can see it next to the rest of
    /// the user's account data).
    private func writeUsernameToProfile(_ username: String) async {
        let userID = AccountStorage.currentUserID
        guard userID != "guest", !userID.hasPrefix("local_") else { return }
        nonisolated struct ProfileUsernamePatch: Encodable, Sendable {
            let username: String
            let updated_at: String
        }
        let patch = ProfileUsernamePatch(
            username: username,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        do {
            _ = try await client
                .from("profiles")
                .update(patch)
                .eq("id", value: userID)
                .execute()
        } catch {
            // Silent — the dedicated `usernames` table is still the
            // uniqueness source of truth.
        }
    }

    func setUsername(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        guard trimmed.count >= 3 && trimmed.count <= 20 else { return nil }
        let allowed = CharacterSet.lowercaseLetters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: "_."))
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        AccountStorage.set(trimmed, forKey: usernameKey)
        return trimmed
    }

    func isUsernameAvailable(_ username: String) async -> Bool {
        let normalized = username.lowercased()
        let currentUser = AccountStorage.currentUserID
        do {
            // Primary check: the dedicated reservations table. Case-insensitive
            // via the lower(username) unique index in Supabase.
            let reserved: [UsernameReservationRow] = try await client
                .from("usernames")
                .select("username,user_id")
                .ilike("username", pattern: normalized)
                .limit(1)
                .execute()
                .value
            if let row = reserved.first {
                // Available only if the existing reservation belongs to this user.
                return row.user_id == currentUser
            }
            // Fallback check against leaderboard_entries for legacy rows that
            // pre-date the usernames table.
            let rows: [UsernameCheckRow] = try await client
                .from("leaderboard_entries")
                .select("username")
                .ilike("username", pattern: normalized)
                .limit(1)
                .execute()
                .value
            return rows.isEmpty
        } catch {
            return true // fail-open so users aren't blocked offline
        }
    }

    /// Reserves the username in `public.usernames` so no one else can claim it.
    /// Safe to call repeatedly — the row is upserted on user_id, and a
    /// case-insensitive unique index protects against collisions.
    @discardableResult
    func reserveUsername(_ username: String) async -> Bool {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return false }
        let owner = AccountStorage.currentUserID; let epoch = AccountStorage.generation
        let payload = UsernameReservationRow(username: trimmed, user_id: owner)
        do {
            try WhisperChatMediaService.checkAccount(owner, generation: epoch)
            try await client
                .from("usernames")
                .upsert(payload, onConflict: "user_id")
                .execute()
            // Mirror onto the profile row so the username is visible inline
            // with the rest of the user's data.
            try WhisperChatMediaService.checkAccount(owner, generation: epoch)
            await writeUsernameToProfile(trimmed)
            try WhisperChatMediaService.checkAccount(owner, generation: epoch)
            nonisolated struct SocialUsernamePatch: Encodable { let username: String }
            try await client.from("whisper_profiles").update(SocialUsernamePatch(username: trimmed)).eq("user_id", value: owner).execute()
            try WhisperChatMediaService.checkAccount(owner, generation: epoch)
            // Keep the in-memory profile in sync so UI reflects it immediately.
            var profile = AuthenticationService.shared.currentUser
            if profile.username != trimmed {
                profile.username = trimmed
                AuthenticationService.shared.currentUser = profile
                AuthenticationService.shared.saveCurrentUser()
            }
            return true
        } catch {
            return false
        }
    }

    func syncStats(steps: Int, workouts: Int, activeMinutes: Int) async {
        guard let username = savedUsername, !username.isEmpty else { return }
        let payload = LeaderboardUpsertPayload(
            user_id: AccountStorage.currentUserID,
            username: username,
            steps_week: steps,
            workouts_week: workouts,
            active_minutes_week: activeMinutes,
            week_id: Self.currentWeekId
        )
        do {
            try await client
                .from("leaderboard_entries")
                .upsert(payload, onConflict: "user_id")
                .execute()
            AccountStorage.set(Date().timeIntervalSince1970, forKey: lastSyncKey)
        } catch {
            // silent — leaderboard is non-critical
        }
    }

    func fetchTop(metric: LeaderboardMetric, limit: Int = 100) async {
        isLoading = true
        errorMessage = nil
        currentMetric = metric

        let orderColumn: String
        switch metric {
        case .steps: orderColumn = "steps_week"
        case .workouts: orderColumn = "workouts_week"
        case .activeMinutes: orderColumn = "active_minutes_week"
        }

        let bots = Self.generatedBotRows()

        do {
            let rows: [LeaderboardEntryRow] = try await client
                .from("leaderboard_entries")
                .select()
                .eq("week_id", value: Self.currentWeekId)
                .order(orderColumn, ascending: false)
                .limit(limit)
                .execute()
                .value
            entries = Self.merged(real: rows, bots: bots, metric: metric, limit: limit)
            await UserVerificationService.shared.preload(usernames: entries.map { $0.username })
        } catch {
            // Even if Supabase is unreachable, surface bots so the leaderboard
            // never looks empty.
            entries = Self.merged(real: [], bots: bots, metric: metric, limit: limit)
            if entries.isEmpty {
                errorMessage = "Couldn't load the leaderboard. Check back in a moment."
            }
        }
        isLoading = false
    }

    // MARK: - Bot leaderboard population

    /// Static, realistic-looking bot users so the leaderboard never feels empty.
    /// Their weekly stats deterministically grow each day inside the current week
    /// (resetting on Monday alongside the real leaderboard), giving the illusion
    /// of an active community.
    private struct LeaderboardBot: Sendable {
        let userID: String
        let username: String
        let stepsPerDay: Int
        let workoutCadence: Int // 1 = every day, 2 = every other day
        let activeMinutesPerDay: Int
    }

    private static let bots: [LeaderboardBot] = [
        .init(userID: "bot_emma_r", username: "emma.runs",    stepsPerDay: 12300, workoutCadence: 1, activeMinutesPerDay: 65),
        .init(userID: "bot_marcus", username: "marcus.lifts", stepsPerDay:  8400, workoutCadence: 1, activeMinutesPerDay: 70),
        .init(userID: "bot_lila_h", username: "lila.h",       stepsPerDay: 10100, workoutCadence: 2, activeMinutesPerDay: 55),
        .init(userID: "bot_devon_", username: "devon.fit",    stepsPerDay:  9300, workoutCadence: 2, activeMinutesPerDay: 50),
        .init(userID: "bot_sophiak", username: "sophia.k",    stepsPerDay: 11500, workoutCadence: 1, activeMinutesPerDay: 60),
        .init(userID: "bot_jt_park", username: "jt.park",     stepsPerDay:  7800, workoutCadence: 2, activeMinutesPerDay: 45),
        .init(userID: "bot_aria_w", username: "aria.w",       stepsPerDay: 13200, workoutCadence: 1, activeMinutesPerDay: 75),
        .init(userID: "bot_caleb_t", username: "caleb.t",     stepsPerDay:  6900, workoutCadence: 2, activeMinutesPerDay: 40),
        .init(userID: "bot_nia_b",  username: "nia.b",        stepsPerDay: 10800, workoutCadence: 1, activeMinutesPerDay: 58),
        .init(userID: "bot_finn_o", username: "finn.olsen",   stepsPerDay:  8600, workoutCadence: 2, activeMinutesPerDay: 48),
        .init(userID: "bot_iris_v", username: "iris.v",       stepsPerDay:  9700, workoutCadence: 1, activeMinutesPerDay: 52),
        .init(userID: "bot_owen_d", username: "owen.d",       stepsPerDay: 11900, workoutCadence: 2, activeMinutesPerDay: 68)
    ]

    /// Days elapsed in the current ISO week (Mon = 1, ... Sun = 7).
    private static var daysIntoWeek: Int {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2 // Monday
        let wd = cal.component(.weekday, from: Date()) // 1 = Sun, 2 = Mon, …
        // Map: Mon(2)->1, Tue(3)->2, …, Sat(7)->6, Sun(1)->7
        return wd == 1 ? 7 : wd - 1
    }

    private static func generatedBotRows() -> [LeaderboardEntryRow] {
        let days = max(1, daysIntoWeek)
        let weekID = currentWeekId
        return bots.map { bot in
            let steps = bot.stepsPerDay * days
            let workouts: Int
            if bot.workoutCadence <= 1 {
                workouts = days
            } else {
                workouts = Int(ceil(Double(days) / Double(bot.workoutCadence)))
            }
            let active = bot.activeMinutesPerDay * days
            return LeaderboardEntryRow(
                user_id: bot.userID,
                username: bot.username,
                steps_week: steps,
                workouts_week: workouts,
                active_minutes_week: active,
                week_id: weekID,
                updated_at: nil
            )
        }
    }

    private static func merged(
        real: [LeaderboardEntryRow],
        bots: [LeaderboardEntryRow],
        metric: LeaderboardMetric,
        limit: Int
    ) -> [LeaderboardEntryRow] {
        // Avoid duplicate bot rows if any ever made it into Supabase.
        let realIDs = Set(real.map(\.user_id))
        let filteredBots = bots.filter { !realIDs.contains($0.user_id) }
        let combined = real + filteredBots
        let sorted = combined.sorted { lhs, rhs in
            switch metric {
            case .steps: return lhs.steps_week > rhs.steps_week
            case .workouts: return lhs.workouts_week > rhs.workouts_week
            case .activeMinutes: return lhs.active_minutes_week > rhs.active_minutes_week
            }
        }
        return Array(sorted.prefix(limit))
    }
}
