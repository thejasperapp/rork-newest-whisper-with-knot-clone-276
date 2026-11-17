import Foundation
import Supabase
import UIKit

// MARK: - Supabase schema (run once in SQL editor)
//
// -- Coach application form rows. Owner reviews in Supabase Dashboard.
// create table if not exists public.whisper_coach_applications (
//   id uuid primary key default gen_random_uuid(),
//   user_id uuid not null references auth.users(id) on delete cascade,
//   username text not null,
//   email text,
//   full_name text not null,
//   credentials text not null default '',
//   specialties text[] not null default '{}',
//   experience_years int not null default 0,
//   bio text not null default '',
//   website text,
//   social text,
//   status text not null default 'pending' check (status in ('pending','approved','denied')),
//   created_at timestamptz not null default now()
// );
// alter table public.whisper_coach_applications enable row level security;
// create policy "wca read own" on public.whisper_coach_applications
//   for select using (auth.uid() = user_id);
// create policy "wca insert own" on public.whisper_coach_applications
//   for insert with check (auth.uid() = user_id);
//
// -- Add an is_coach flag to whisper_profiles so the app can render the badge
// -- + unlock coach-only features. Owner flips this to true after reviewing
// -- the application in Supabase. (Or use service-role to update.)
// alter table public.whisper_profiles
//   add column if not exists is_coach boolean not null default false;
// alter table public.whisper_profiles
//   add column if not exists coach_tier text;
//
// -- Server-side flag that tracks whether the user has already seen the
// -- coach welcome celebration sheet. Once non-null, the app NEVER
// -- re-shows the celebration on relaunch, even after sign-out/sign-in
// -- or AccountStorage wipes.
// alter table public.whisper_profiles
//   add column if not exists coach_welcomed_at timestamptz;
//
// -- Mirror into public.profiles so feeds/inbox can also surface the badge
// -- using the same `profiles` lookup.
// alter table public.profiles
//   add column if not exists is_coach boolean not null default false;

nonisolated struct WhisperCoachApplicationInsert: Codable, Sendable {
    let user_id: String
    let username: String
    let email: String?
    let full_name: String
    let credentials: String
    let specialties: [String]
    let experience_years: Int
    let bio: String
    let website: String?
    let social: String?
}

nonisolated struct WhisperCoachApplicationRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let user_id: String
    let username: String
    let status: String
    let created_at: String?
}

/// Tracks coach status for the current user, lets users apply to become a
/// coach, and exposes per-user `isCoach(userID:)` lookups so the rest of the
/// app can render the verified-coach badge.
@MainActor
@Observable
final class WhisperCoachService {
    static let shared = WhisperCoachService()

    /// Email address that the application form is forwarded to. The form
    /// inserts a row into Supabase AND opens a prefilled mailto link to
    /// this address so the owner always gets a copy without needing any
    /// Edge Function plumbing.
    static let reviewEmail = "yourfriend@thejasperapp.com"

    private let client = SupabaseService.shared.client

    /// True once the local user has been promoted to a coach by an admin.
    var isMeCoach: Bool = false
    /// True once an application has been submitted and is awaiting review.
    var hasPendingApplication: Bool = false
    /// True when the latest application was approved but the annual badge
    /// payment hasn't been completed yet (is_coach is still false). The
    /// Settings view uses this to surface the badge activation paywall.
    var hasApprovedApplication: Bool = false
    /// Cached coach flag for any user we've looked up (avatars/rows render
    /// the verified-coach badge by reading this map).
    var coachByUserID: [String: Bool] = [:]
    /// Same as `coachByUserID` but keyed by lowercased username so views that
    /// only have a `@username` (post header, moderation sheet, comments) can
    /// surface the verified-coach badge without an extra round-trip.
    var coachByUsername: [String: Bool] = [:]
    var lastError: String?
    /// Latest application body, copied to the clipboard so the user can paste
    /// it into any email/messaging app if mailto: silently fails (no Mail
    /// account configured, URL too long, etc.). UI surfaces this as a banner.
    var lastReviewEmailBody: String?
    var didCopyReviewEmail: Bool = false
    /// Set to true exactly once when an admin promotes the user to a coach.
    /// The settings/inbox views observe this and present the
    /// `WhisperCoachWelcomeView` celebration sheet. Cleared via
    /// `markCelebrated()` after the user dismisses the sheet.
    var shouldCelebrateApproval: Bool = false

    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    /// Local persistence so the pending banner survives an app relaunch even
    /// if the realtime fetch hasn't completed yet.
    private let pendingKey = "whisper.coach.pending"
    /// Stores the set of UIDs that have already seen the coach-welcome
    /// celebration sheet, JSON-encoded as `[String]`.
    ///
    /// Lives OUTSIDE the `whisper.*` / `jasper.*` / `ember.*` namespaces on
    /// purpose: `AccountStorage.wipeAllAccountData` wipes every key matching
    /// those prefixes on every sign-in (including same-user sign-ins after
    /// a brief logout), which is what caused the celebration to keep
    /// firing on every launch.
    private let celebratedUIDsKey = "app.celebrated.coach.uids.v1"

    /// Reads the persisted celebrated-UIDs set.
    private func celebratedUIDs() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: celebratedUIDsKey),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(arr)
    }

    /// Resolves the current user's UID, preferring the Supabase session
    /// (lowercased) and falling back to AccountStorage.
    private func currentUIDLowered() -> String? {
        if let id = SupabaseService.shared.client.auth.currentUser?.id.uuidString {
            return id.lowercased()
        }
        let acct = AccountStorage.currentUserID
        if acct != "guest" && !acct.isEmpty { return acct.lowercased() }
        return nil
    }

    /// Writes (or removes) the current UID in the celebrated set.
    private func setCelebrated(_ celebrated: Bool) {
        guard let uid = currentUIDLowered() else { return }
        var set = celebratedUIDs()
        if celebrated { set.insert(uid) } else { set.remove(uid) }
        if let data = try? JSONEncoder().encode(Array(set)) {
            UserDefaults.standard.set(data, forKey: celebratedUIDsKey)
            UserDefaults.standard.synchronize()
        }
    }

    private init() {
        hasPendingApplication = AccountStorage.bool(forKey: pendingKey)
    }

    // MARK: - Status

    /// Refreshes `isMeCoach` from `whisper_profiles.is_coach`. Silently no-ops
    /// for guests or when the column is missing (older schema).
    func refreshMyStatus() async {
        guard isRemote else { isMeCoach = false; return }
        if let flag = await fetchCoachFlag(userID: currentUID) {
            let previously = isMeCoach
            isMeCoach = flag
            coachByUserID[currentUID.lowercased()] = flag
            // Once approved, clear the "under review" banner so Settings
            // flips to Coach Studio immediately.
            if flag {
                hasPendingApplication = false
                AccountStorage.set(false, forKey: pendingKey)
                // First time we see is_coach=true for this user → trigger
                // the welcome celebration. Local celebrated set is checked
                // FIRST so already-welcomed coaches skip the network
                // round-trip this used to fire on every refresh.
                let uidLower = currentUIDLowered() ?? ""
                if !uidLower.isEmpty, !celebratedUIDs().contains(uidLower) {
                    // Server flag wins: if `coach_welcomed_at` is set, never
                    // re-fire even when local UserDefaults got wiped.
                    if await fetchServerWelcomed() {
                        setCelebrated(true)
                    } else {
                        shouldCelebrateApproval = true
                    }
                }
                _ = previously
            } else {
                // Demoted (or never approved) → allow celebration to fire
                // again if they ever get re-approved.
                setCelebrated(false)
            }
        }
        await refreshPendingApplication()
    }

    /// Checks whether `userID` is a coach. Cached after first lookup; the
    /// cache is reset whenever the owning service is recreated.
    func isCoach(userID: String) -> Bool {
        coachByUserID[userID.lowercased()] ?? false
    }

    /// Username variant — returns the cached coach flag for a `@username`.
    /// Call `ensureCoachStatus(username:)` first to warm the cache.
    func isCoach(username: String) -> Bool {
        coachByUsername[username.lowercased()] ?? false
    }

    /// Async variant that warms the cache for a given user. Cheap to call —
    /// returns the cached value when present.
    @discardableResult
    func ensureCoachStatus(userID: String) async -> Bool {
        let key = userID.lowercased()
        if let cached = coachByUserID[key] { return cached }
        let flag = await fetchCoachFlag(userID: userID) ?? false
        coachByUserID[key] = flag
        return flag
    }

    /// Warms the username-keyed cache. Looks up `is_coach` from
    /// `public.profiles` (and falls back to `whisper_profiles`) using the
    /// canonical username. Safe to call repeatedly — cached after first hit.
    @discardableResult
    func ensureCoachStatus(username: String) async -> Bool {
        let key = username.lowercased()
        if let cached = coachByUsername[key] { return cached }
        guard isRemote else {
            coachByUsername[key] = false
            return false
        }
        let flag = await fetchCoachFlag(username: username) ?? false
        coachByUsername[key] = flag
        return flag
    }

    /// Warms many usernames at once. Used by the feed / inbox so coach badges
    /// appear in the first render. Batched — the old implementation fired two
    /// Supabase round-trips PER username; this resolves any number of handles
    /// in two chunked queries (one per profile table).
    func ensureCoachStatuses(usernames: [String]) async {
        let unique = Set(usernames.map { $0.lowercased() }).filter { !$0.isEmpty }
        let pending = Array(unique.filter { coachByUsername[$0] == nil })
        guard !pending.isEmpty else { return }
        // Cache misses as false up-front so concurrent callers don't re-fetch
        // the same names; hits flip to true below.
        for name in pending { coachByUsername[name] = false }
        let chunks: [[String]] = stride(from: 0, to: pending.count, by: 40).map {
            Array(pending[$0..<min($0 + 40, pending.count)])
        }
        for chunk in chunks {
            // `ilike` without wildcards = case-insensitive exact match, so the
            // or-filter batch behaves identically to the old per-name lookups.
            let orFilter = chunk.map { "username.ilike.\($0)" }.joined(separator: ",")
            do {
                let rows: [CoachFlagNameRow] = try await client
                    .from("whisper_profiles")
                    .select("username,is_coach")
                    .or(orFilter)
                    .execute()
                    .value
                for row in rows where row.is_coach == true {
                    coachByUsername[row.username.lowercased()] = true
                }
            } catch { /* missing table / column — ignore */ }
            do {
                let rows: [CoachFlagNameRow] = try await client
                    .from("profiles")
                    .select("username,is_coach")
                    .or(orFilter)
                    .execute()
                    .value
                for row in rows where row.is_coach == true {
                    coachByUsername[row.username.lowercased()] = true
                }
            } catch { /* missing table / column — ignore */ }
        }
    }

    /// Bulk variant for user IDs — used by the inbox after threads load so
    /// all coach badges render in the first frame. Batched: two `.in()`
    /// queries total instead of two round-trips per user (an inbox with 50
    /// threads used to fire 100 requests here).
    func ensureCoachStatuses(userIDs: [String]) async {
        let unique = Set(userIDs.map { $0.lowercased() })
            .filter { !$0.isEmpty && $0 != "guest" && !$0.hasPrefix("local_") }
        let pending = Array(unique.filter { coachByUserID[$0] == nil })
        guard !pending.isEmpty else { return }
        for id in pending { coachByUserID[id] = false }
        do {
            let rows: [CoachFlagWPRow] = try await client
                .from("whisper_profiles")
                .select("user_id,is_coach")
                .in("user_id", values: pending)
                .execute()
                .value
            for row in rows where row.is_coach == true {
                coachByUserID[row.user_id.lowercased()] = true
            }
        } catch { /* missing table / column — ignore */ }
        do {
            let rows: [CoachFlagPRow] = try await client
                .from("profiles")
                .select("id,is_coach")
                .in("id", values: pending)
                .execute()
                .value
            for row in rows where row.is_coach == true {
                coachByUserID[row.id.lowercased()] = true
            }
        } catch { /* missing table / column — ignore */ }
    }

    nonisolated private struct CoachFlagRow: Decodable, Sendable {
        let is_coach: Bool?
    }

    nonisolated private struct CoachFlagWPRow: Decodable, Sendable {
        let user_id: String
        let is_coach: Bool?
    }

    nonisolated private struct CoachFlagPRow: Decodable, Sendable {
        let id: String
        let is_coach: Bool?
    }

    nonisolated private struct CoachFlagNameRow: Decodable, Sendable {
        let username: String
        let is_coach: Bool?
    }

    nonisolated private struct CoachWelcomeRow: Decodable, Sendable {
        let coach_welcomed_at: String?
    }

    nonisolated private struct CoachWelcomeUpdate: Encodable, Sendable {
        let coach_welcomed_at: String
    }

    /// Fetches the server-side `coach_welcomed_at` flag. Returns true if
    /// the user has already been welcomed on the server (i.e. the column
    /// is non-null). On any error (column missing, network, etc.) returns
    /// false so the local fallback takes over.
    private func fetchServerWelcomed() async -> Bool {
        guard isRemote else { return false }
        do {
            let row: CoachWelcomeRow = try await client
                .from("whisper_profiles")
                .select("coach_welcomed_at")
                .eq("user_id", value: currentUID)
                .single()
                .execute()
                .value
            return (row.coach_welcomed_at?.isEmpty == false)
        } catch {
            return false
        }
    }

    /// Stamps `coach_welcomed_at = now()` on the user's whisper_profiles
    /// row so the celebration NEVER fires again on any device.
    private func writeServerWelcomed() async {
        guard isRemote else { return }
        let iso = ISO8601DateFormatter().string(from: Date())
        do {
            try await client
                .from("whisper_profiles")
                .update(CoachWelcomeUpdate(coach_welcomed_at: iso))
                .eq("user_id", value: currentUID)
                .execute()
        } catch {
            // Column may not exist yet — local fallback still protects us.
        }
    }

    private func fetchCoachFlag(username: String) async -> Bool? {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var any: Bool? = nil
        do {
            let row: CoachFlagRow = try await client
                .from("profiles")
                .select("is_coach")
                .ilike("username", pattern: trimmed)
                .limit(1)
                .single()
                .execute()
                .value
            if let v = row.is_coach { any = (any ?? false) || v }
        } catch {
            // missing row / column — ignore
        }
        do {
            let row: CoachFlagRow = try await client
                .from("whisper_profiles")
                .select("is_coach")
                .ilike("username", pattern: trimmed)
                .limit(1)
                .single()
                .execute()
                .value
            if let v = row.is_coach { any = (any ?? false) || v }
        } catch {
            // missing row / column — ignore
        }
        return any
    }

    private func fetchCoachFlag(userID: String) async -> Bool? {
        guard !userID.isEmpty, userID != "guest", !userID.hasPrefix("local_") else { return nil }
        // Check BOTH whisper_profiles AND public.profiles — if either has
        // is_coach=true, the user is approved. This way, flipping the flag
        // in either table is enough.
        var any: Bool? = nil
        do {
            let row: CoachFlagRow = try await client
                .from("whisper_profiles")
                .select("is_coach")
                .eq("user_id", value: userID)
                .single()
                .execute()
                .value
            if let v = row.is_coach { any = (any ?? false) || v }
        } catch {
            // missing row / column — ignore
        }
        do {
            let row: CoachFlagRow = try await client
                .from("profiles")
                .select("is_coach")
                .eq("id", value: userID)
                .single()
                .execute()
                .value
            if let v = row.is_coach { any = (any ?? false) || v }
        } catch {
            // missing row / column — ignore
        }
        return any
    }

    /// Called by the welcome sheet once the user has seen the celebration.
    /// Persists a per-user flag so the sheet won't reappear on relaunch.
    func markCelebrated() {
        shouldCelebrateApproval = false
        setCelebrated(true)
        Task { await writeServerWelcomed() }
    }

    // MARK: - Application

    private func refreshPendingApplication() async {
        guard isRemote else { return }
        do {
            let rows: [WhisperCoachApplicationRow] = try await client
                .from("whisper_coach_applications")
                .select("id,user_id,username,status,created_at")
                .eq("user_id", value: currentUID)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            let pending = rows.first?.status == "pending"
            hasPendingApplication = pending
            AccountStorage.set(pending, forKey: pendingKey)
            // Track approved-but-not-paid so the activation paywall can surface.
            hasApprovedApplication = rows.first?.status == "approved"
        } catch {
            // Keep whatever local value we have.
        }
    }

    /// Submits the coach application. Inserts a row into Supabase AND opens
    /// a prefilled mailto: URL so the review inbox receives a copy without
    /// any server plumbing required.
    @discardableResult
    func submitApplication(
        fullName: String,
        email: String,
        credentials: String,
        specialties: [String],
        experienceYears: Int,
        bio: String,
        website: String,
        social: String
    ) async -> Bool {
        guard isRemote else {
            lastError = "Sign in to Whisper first to apply."
            return false
        }
        let username = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"
        let payload = WhisperCoachApplicationInsert(
            user_id: currentUID,
            username: username,
            email: email.isEmpty ? nil : email,
            full_name: fullName,
            credentials: credentials,
            specialties: specialties,
            experience_years: experienceYears,
            bio: bio,
            website: website.isEmpty ? nil : website,
            social: social.isEmpty ? nil : social
        )
        var insertOK = false
        do {
            try await client.from("whisper_coach_applications").insert(payload).execute()
            insertOK = true
            hasPendingApplication = true
            AccountStorage.set(true, forKey: pendingKey)
            lastError = nil
        } catch {
            let msg = error.localizedDescription.lowercased()
            if msg.contains("relation") && msg.contains("does not exist") {
                lastError = "Application table missing. Owner: run the WhisperCoachService SQL block once."
            } else {
                lastError = "Couldn't save your application: \(error.localizedDescription)"
            }
            print("[Whisper] coach apply error: \(error)")
        }
        // Always open the mailto fallback so the review inbox gets it even
        // if the Supabase insert failed. Also copy the body to the clipboard
        // so the user can paste into any email client if Mail isn't set up.
        await openReviewMail(
            username: username,
            fullName: fullName,
            email: email,
            credentials: credentials,
            specialties: specialties,
            experienceYears: experienceYears,
            bio: bio,
            website: website,
            social: social
        )
        return insertOK
    }

    private func openReviewMail(
        username: String,
        fullName: String,
        email: String,
        credentials: String,
        specialties: [String],
        experienceYears: Int,
        bio: String,
        website: String,
        social: String
    ) async {
        let subject = "Whisper coach application — @\(username)"
        let body = """
        New coach application from Whisper

        Username: @\(username)
        Full name: \(fullName)
        Email: \(email)
        Experience: \(experienceYears) years
        Specialties: \(specialties.joined(separator: ", "))
        Website: \(website)
        Social: \(social)

        Credentials / certifications
        ---------------------------
        \(credentials)

        Why they want to coach
        ----------------------
        \(bio)

        Reviewer actions
        ----------------
        1. Find the row in Supabase → whisper_coach_applications.
        2. If approved, in SQL editor run:
           update public.whisper_profiles set is_coach = true where user_id = '<uuid>';
           update public.profiles set is_coach = true where id = '<uuid>';
           update public.whisper_coach_applications set status = 'approved' where id = '<row id>';
        3. If denied, set status = 'denied'.
        """
        // 1) Always stash the body + copy to clipboard so the user has a
        //    fallback regardless of Mail availability.
        lastReviewEmailBody = "To: \(Self.reviewEmail)\nSubject: \(subject)\n\n" + body
        UIPasteboard.general.string = lastReviewEmailBody
        didCopyReviewEmail = true

        // 2) Try mailto: with a short body (some clients drop long URLs).
        let shortBody = """
        New coach application from @\(username) (\(fullName)).
        Email: \(email)
        Full details copied to clipboard — paste below.
        """
        let allowed = CharacterSet.urlQueryAllowed
        let subjectEnc = subject.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let bodyEnc = shortBody.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let urlStr = "mailto:\(Self.reviewEmail)?subject=\(subjectEnc)&body=\(bodyEnc)"
        if let url = URL(string: urlStr) {
            await UIApplication.shared.open(url)
        }
    }
}
