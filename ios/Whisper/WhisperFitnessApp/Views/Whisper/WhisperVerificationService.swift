import Foundation
import Supabase

// MARK: - Supabase schema (run once in SQL editor)
//
// create table if not exists public.whisper_verification_requests (
//   id uuid primary key default gen_random_uuid(),
//   user_id uuid not null references auth.users(id) on delete cascade,
//   username text not null,
//   email text,
//   full_name text not null,
//   category text not null,            -- creator | coach | brand | athlete | media | public_figure | other
//   reason text not null default '',
//   links text,                        -- newline-separated profile/portfolio links
//   id_url text,                       -- optional Storage URL to ID upload (manual review)
//   followers int not null default 0,
//   status text not null default 'pending' check (status in ('pending','approved','denied')),
//   review_note text,
//   reviewed_by uuid,
//   reviewed_at timestamptz,
//   created_at timestamptz not null default now(),
//   unique (user_id, status)           -- only one pending row per user
// );
// alter table public.whisper_verification_requests enable row level security;
//
// -- Server-side flag that records whether the user has already seen the
// -- verified welcome celebration sheet. Once non-null, the app NEVER
// -- re-shows the celebration on relaunch, even after sign-out/sign-in
// -- or local UserDefaults wipes.
// alter table public.whisper_profiles
//   add column if not exists verified_welcomed_at timestamptz;
// drop policy if exists "wvr read own" on public.whisper_verification_requests;
// create policy "wvr read own" on public.whisper_verification_requests
//   for select using (
//     auth.uid() = user_id
//     or exists (select 1 from public.profiles p
//                where p.id = auth.uid()
//                  and (p.is_moderator = true or p.is_admin = true or p.is_owner = true))
//   );
// drop policy if exists "wvr insert own" on public.whisper_verification_requests;
// create policy "wvr insert own" on public.whisper_verification_requests
//   for insert with check (auth.uid() = user_id);
// drop policy if exists "wvr update mod" on public.whisper_verification_requests;
// create policy "wvr update mod" on public.whisper_verification_requests
//   for update using (
//     exists (select 1 from public.profiles p
//             where p.id = auth.uid()
//               and (p.is_moderator = true or p.is_admin = true or p.is_owner = true))
//   );

nonisolated struct WhisperVerificationRequestRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let user_id: String
    let username: String
    let email: String?
    let full_name: String
    let category: String
    let reason: String
    let links: String?
    let id_url: String?
    let followers: Int?
    let status: String
    let review_note: String?
    let reviewed_by: String?
    let reviewed_at: Date?
    let created_at: Date?
}

nonisolated struct WhisperVerificationInsert: Codable, Sendable {
    let user_id: String
    let username: String
    let email: String?
    let full_name: String
    let category: String
    let reason: String
    let links: String?
    let followers: Int
    let status: String
}

nonisolated struct WhisperVerificationStatusUpdate: Codable, Sendable {
    let status: String
    let review_note: String?
    let reviewed_by: String?
    let reviewed_at: Date?
}

nonisolated struct WhisperVerifiedFlagUpdate: Codable, Sendable {
    let is_verified: Bool
}

nonisolated struct WhisperVerifiedWelcomeRow: Decodable, Sendable {
    let verified_welcomed_at: String?
}

nonisolated struct WhisperVerifiedWelcomeUpdate: Encodable, Sendable {
    let verified_welcomed_at: String
}

/// Verification application + admin dashboard service. Mirrors the Coach
/// pipeline: users submit an application row, mods/admins/owner review it
/// in-app, approval flips `profiles.is_verified = true` so the blue check
/// lights up everywhere `UserVerificationService` reads from.
@MainActor
@Observable
final class WhisperVerificationService {
    static let shared = WhisperVerificationService()

    private let client = SupabaseService.shared.client

    /// Latest application row for the current user (any status).
    var myLatest: WhisperVerificationRequestRow?
    /// All pending applications (mod/admin/owner view).
    var pending: [WhisperVerificationRequestRow] = []
    /// Recent decisions (mod/admin/owner view).
    var recentDecisions: [WhisperVerificationRequestRow] = []
    var lastError: String?
    var isLoading: Bool = false
    /// Set to true exactly once when the user's verification application is
    /// approved. The settings/inbox views observe this and present
    /// `WhisperVerifiedWelcomeView`. Cleared via `markCelebrated()` after
    /// the user dismisses the sheet (persisted per-user).
    var shouldCelebrateApproval: Bool = false

    /// Stores the set of user IDs that have already seen the verified
    /// celebration sheet, as a JSON-encoded array of lowercased UID strings.
    ///
    /// The key intentionally lives OUTSIDE the `whisper.*` / `jasper.*` /
    /// `ember.*` namespaces because `AccountStorage.wipeAllAccountData` —
    /// invoked on every sign-in (including same-user sign-ins after a brief
    /// logout) — wipes everything matching those prefixes. The previous
    /// `whisper.verified.celebrated` key was getting nuked on every sign-in,
    /// which is why the celebration kept re-firing.
    ///
    /// Storing the set of UIDs (instead of a single bool) handles the
    /// multi-account case cleanly: account A is in the set, account B is
    /// not, so signing into B once still triggers their celebration.
    private let celebratedUIDsKey = "app.celebrated.verified.uids.v1"

    /// Reads the persisted set of celebrated UIDs.
    private func celebratedUIDs() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: celebratedUIDsKey),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(arr)
    }

    /// Resolves the current user's UID, preferring the Supabase session
    /// (lowercased for stability) and falling back to `AccountStorage`.
    private func currentUIDLowered() -> String? {
        if let id = SupabaseService.shared.client.auth.currentUser?.id.uuidString {
            return id.lowercased()
        }
        let acct = AccountStorage.currentUserID
        if acct != "guest" && !acct.isEmpty { return acct.lowercased() }
        return nil
    }

    /// Called by the welcome sheet once the user has seen the celebration.
    /// Persists their UID in the celebrated set so the sheet won't reappear.
    func markCelebrated() {
        shouldCelebrateApproval = false
        if let uid = currentUIDLowered() {
            var set = celebratedUIDs()
            set.insert(uid)
            if let data = try? JSONEncoder().encode(Array(set)) {
                UserDefaults.standard.set(data, forKey: celebratedUIDsKey)
                UserDefaults.standard.synchronize()
            }
        }
        Task { await writeServerWelcomed() }
    }

    var hasPendingApplication: Bool {
        myLatest?.status == "pending"
    }

    var lastDecisionStatus: String? { myLatest?.status }

    private init() {}

    // MARK: - My application

    func refreshMyStatus() async {
        guard let uid = SupabaseService.shared.client.auth.currentUser?.id.uuidString else { return }
        do {
            let rows: [WhisperVerificationRequestRow] = try await client
                .from("whisper_verification_requests")
                .select()
                .eq("user_id", value: uid)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            myLatest = rows.first
            evaluateCelebration()
        } catch {
            // Table likely missing — surface in lastError only on submit.
        }
    }

    /// Trips `shouldCelebrateApproval` the first time we observe an
    /// approved verification application for the current user. Persisted
    /// server-side (via `whisper_profiles.verified_welcomed_at`) AND
    /// locally so the sheet only ever fires once across all devices.
    private func evaluateCelebration() {
        let approved = (myLatest?.status == "approved")
            || WhisperVerifiedPerks.isVerified(username: LeaderboardService.shared.savedUsername
                ?? AuthenticationService.shared.currentUser.username
                ?? "")
        guard approved else { return }
        guard let uid = currentUIDLowered() else { return }
        Task { @MainActor in
            // Server flag wins: if `verified_welcomed_at` is set, never
            // re-fire even if local UserDefaults got wiped.
            let serverWelcomed = await self.fetchServerWelcomed()
            if serverWelcomed {
                // Mirror into the local set so subsequent launches don't
                // need the network round-trip.
                var set = self.celebratedUIDs()
                set.insert(uid)
                if let data = try? JSONEncoder().encode(Array(set)) {
                    UserDefaults.standard.set(data, forKey: self.celebratedUIDsKey)
                }
                return
            }
            if !self.celebratedUIDs().contains(uid) {
                self.shouldCelebrateApproval = true
            }
        }
    }

    /// Fetches the server-side `verified_welcomed_at` flag. Returns true
    /// when the column is non-null. On any error (column missing,
    /// network, etc.) returns false so the local fallback takes over.
    private func fetchServerWelcomed() async -> Bool {
        guard let uid = SupabaseService.shared.client.auth.currentUser?.id.uuidString else {
            return false
        }
        do {
            let row: WhisperVerifiedWelcomeRow = try await client
                .from("whisper_profiles")
                .select("verified_welcomed_at")
                .eq("user_id", value: uid)
                .single()
                .execute()
                .value
            return (row.verified_welcomed_at?.isEmpty == false)
        } catch {
            return false
        }
    }

    /// Stamps `verified_welcomed_at = now()` on the user's
    /// whisper_profiles row so the celebration NEVER fires again on any
    /// device.
    private func writeServerWelcomed() async {
        guard let uid = SupabaseService.shared.client.auth.currentUser?.id.uuidString else { return }
        let iso = ISO8601DateFormatter().string(from: Date())
        do {
            try await client
                .from("whisper_profiles")
                .update(WhisperVerifiedWelcomeUpdate(verified_welcomed_at: iso))
                .eq("user_id", value: uid)
                .execute()
        } catch {
            // Column may not exist yet — local fallback still protects us.
        }
    }

    /// Submit a new verification application. Returns true if the row was
    /// written. Will refuse if the user already has a pending row.
    func submit(
        fullName: String,
        email: String?,
        category: String,
        reason: String,
        links: String?,
        followers: Int
    ) async -> Bool {
        lastError = nil
        guard let uid = SupabaseService.shared.client.auth.currentUser?.id.uuidString,
              let username = (LeaderboardService.shared.savedUsername
                              ?? AuthenticationService.shared.currentUser.username),
              !username.isEmpty else {
            lastError = "You need to be signed in with a username to apply."
            return false
        }
        if hasPendingApplication {
            lastError = "You already have an application under review."
            return false
        }
        let payload = WhisperVerificationInsert(
            user_id: uid,
            username: username,
            email: email,
            full_name: fullName,
            category: category,
            reason: reason,
            links: links,
            followers: followers,
            status: "pending"
        )
        do {
            try await client
                .from("whisper_verification_requests")
                .insert(payload)
                .execute()
            await refreshMyStatus()
            return true
        } catch {
            lastError = "Couldn't submit. (\(error.localizedDescription))"
            return false
        }
    }

    // MARK: - Mod dashboard

    func loadDashboard() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let pendingRows: [WhisperVerificationRequestRow] = try await client
                .from("whisper_verification_requests")
                .select()
                .eq("status", value: "pending")
                .order("created_at", ascending: false)
                .limit(200)
                .execute()
                .value
            pending = pendingRows

            let recent: [WhisperVerificationRequestRow] = try await client
                .from("whisper_verification_requests")
                .select()
                .in("status", values: ["approved", "denied"])
                .order("reviewed_at", ascending: false)
                .limit(50)
                .execute()
                .value
            recentDecisions = recent
        } catch {
            lastError = "Dashboard fetch failed (\(error.localizedDescription))"
        }
    }

    /// Approve a verification request. The blue check is a paid badge
    /// (annual) — approval only stamps the row as `approved`, which fires
    /// the Supabase trigger emailing the applicant an activation link.
    /// The Stripe webhook flips `profiles.is_verified` once they pay.
    func approve(_ row: WhisperVerificationRequestRow, note: String? = nil) async -> Bool {
        let me = SupabaseService.shared.client.auth.currentUser?.id.uuidString
        do {
            try await client
                .from("whisper_verification_requests")
                .update(WhisperVerificationStatusUpdate(
                    status: "approved",
                    review_note: note,
                    reviewed_by: me,
                    reviewed_at: Date()
                ))
                .eq("id", value: row.id)
                .execute()
            await UserVerificationService.shared.refresh(username: row.username)
            await loadDashboard()
            return true
        } catch {
            lastError = "Approval failed (\(error.localizedDescription))"
            return false
        }
    }

    func deny(_ row: WhisperVerificationRequestRow, note: String? = nil) async -> Bool {
        let me = SupabaseService.shared.client.auth.currentUser?.id.uuidString
        do {
            try await client
                .from("whisper_verification_requests")
                .update(WhisperVerificationStatusUpdate(
                    status: "denied",
                    review_note: note,
                    reviewed_by: me,
                    reviewed_at: Date()
                ))
                .eq("id", value: row.id)
                .execute()
            await loadDashboard()
            return true
        } catch {
            lastError = "Decline failed (\(error.localizedDescription))"
            return false
        }
    }

    /// Manually revoke a user's verified status. Mods/admins/owner only.
    func revoke(userID: String, username: String) async -> Bool {
        do {
            try await client
                .from("profiles")
                .update(WhisperVerifiedFlagUpdate(is_verified: false))
                .eq("id", value: userID)
                .execute()
            await UserVerificationService.shared.refresh(username: username)
            return true
        } catch {
            lastError = "Revoke failed (\(error.localizedDescription))"
            return false
        }
    }
}

/// Canonical perks granted to verified users. Kept centralized so the
/// application screen can describe them and the rest of the app can branch
/// on `WhisperVerifiedPerks.isVerified(...)` without recomputing.
@MainActor
enum WhisperVerifiedPerks {
    /// 1.6× algorithmic boost in Discover + main feed (see `WhisperAlgorithmService`).
    static let algorithmBoost: Double = 1.6
    /// Verified users surface above non-verified accounts inside the
    /// "Trending posts" rail when scores are close.
    static let trendingNudge: Double = 1.25
    /// Push notification priority hint. The fanout function reads this
    /// flag to bump verified accounts' notifications to time-sensitive
    /// when the OS supports it.
    static let pushTimeSensitive: Bool = true

    /// Standard character cap for whispers and replies. Mirrors Threads'
    /// default ceiling so the field stops feeling unbounded.
    static let regularCharacterLimit: Int = 500
    /// Long-form ceiling unlocked once a user is verified. Roughly 3× the
    /// standard cap — enough for full essays, recap threads, and lyric
    /// breakdowns without forcing the user to chain multiple parts.
    static let verifiedCharacterLimit: Int = 1500

    /// Character cap to apply to a composer field for the given username.
    /// Verified, moderator, admin, and owner badges all unlock the
    /// long-form ceiling; everyone else sees the standard cap.
    static func characterLimit(username: String) -> Int {
        isVerified(username: username) ? verifiedCharacterLimit : regularCharacterLimit
    }

    static func isVerified(username: String) -> Bool {
        let badge = UserVerificationService.shared.badge(forUsername: username)
        return badge == .verified || badge == .moderator || badge == .admin || badge == .owner
    }

    /// Human-readable perks list rendered on the application screen.
    static let perks: [String] = [
        "Blue verified check next to your name across feed, comments, DMs, and stories.",
        "1.6× algorithmic boost — your posts surface to more new viewers in Discover.",
        "Priority placement in the Trending Posts rail when scores are close.",
        "Time-sensitive push notifications so your followers see new posts faster.",
        "Eligibility to be featured as a Suggested account to new signups.",
        "Verified-only DM filter — you can choose to only receive DMs from other verified accounts.",
        "Long-form whispers — your character limit jumps from 500 to 1,500 across posts, replies, and threads.",
        "Early access to new Whisper features as they roll out."
    ]
}
