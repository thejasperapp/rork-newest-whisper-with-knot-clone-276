import Foundation
import Supabase
import UIKit

// MARK: - Supabase schema (run once in SQL editor)
//
// -- Athlete application form rows.
// create table if not exists public.whisper_athlete_applications (
//   id uuid primary key default gen_random_uuid(),
//   user_id uuid not null references auth.users(id) on delete cascade,
//   username text not null,
//   email text,
//   full_name text not null,
//   sport text not null default '',
//   level text not null default '',           -- amateur | collegiate | semi-pro | pro | masters
//   team text not null default '',
//   prs text not null default '',             -- freeform PR list
//   bio text not null default '',
//   social text,
//   status text not null default 'pending' check (status in ('pending','approved','denied')),
//   created_at timestamptz not null default now()
// );
// alter table public.whisper_athlete_applications enable row level security;
// create policy "waa read own" on public.whisper_athlete_applications
//   for select using (auth.uid() = user_id);
// create policy "waa insert own" on public.whisper_athlete_applications
//   for insert with check (auth.uid() = user_id);
//
// -- is_athlete flag mirrors is_coach. Owner flips to true after review.
// alter table public.whisper_profiles
//   add column if not exists is_athlete boolean not null default false;
// alter table public.profiles
//   add column if not exists is_athlete boolean not null default false;

nonisolated struct WhisperAthleteApplicationInsert: Codable, Sendable {
    let user_id: String
    let username: String
    let email: String?
    let full_name: String
    let sport: String
    let level: String
    let team: String
    let prs: String
    let bio: String
    let social: String?
}

nonisolated struct WhisperAthleteApplicationRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let user_id: String
    let username: String
    let status: String
    let created_at: String?
}

/// Tracks Whisper Athlete special-account status — the counterpart to
/// `WhisperCoachService`. Athletes get a labeled "Athlete" role on their
/// profile (NOT a badge chip — special account type instead) and unlock
/// athlete-only surfaces (stat sheet, meet countdown, scouting filter).
@MainActor
@Observable
final class WhisperAthleteService {
    static let shared = WhisperAthleteService()

    /// Mailbox the application form forwards to. Owner reviews + flips
    /// `is_athlete = true` once approved.
    static let reviewEmail = "yourfriend@thejasperapp.com"

    private let client = SupabaseService.shared.client

    /// True once the local user has been promoted to an Athlete by an admin.
    var isMeAthlete: Bool = false
    /// True once an application has been submitted and is awaiting review.
    var hasPendingApplication: Bool = false
    /// True when the latest application was approved but the annual badge
    /// payment hasn't been completed yet (is_athlete is still false).
    var hasApprovedApplication: Bool = false
    /// Cached athlete flag by user ID, keyed lowercased.
    var athleteByUserID: [String: Bool] = [:]
    /// Cached athlete flag by lowercased username.
    var athleteByUsername: [String: Bool] = [:]
    var lastError: String?
    var lastReviewEmailBody: String?
    var didCopyReviewEmail: Bool = false
    /// One-shot celebration trigger after promotion.
    var shouldCelebrateApproval: Bool = false

    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    private let pendingKey = "whisper.athlete.pending"
    private let celebratedKey = "whisper.athlete.celebrated"

    private init() {
        hasPendingApplication = AccountStorage.bool(forKey: pendingKey)
    }

    // MARK: - Status

    func refreshMyStatus() async {
        guard isRemote else { isMeAthlete = false; return }
        if let flag = await fetchAthleteFlag(userID: currentUID) {
            isMeAthlete = flag
            athleteByUserID[currentUID.lowercased()] = flag
            if flag {
                hasPendingApplication = false
                AccountStorage.set(false, forKey: pendingKey)
                let celebrated = AccountStorage.bool(forKey: celebrationKey())
                if !celebrated { shouldCelebrateApproval = true }
            } else {
                AccountStorage.set(false, forKey: celebrationKey())
            }
        }
        await refreshPendingApplication()
    }

    func isAthlete(userID: String) -> Bool {
        athleteByUserID[userID.lowercased()] ?? false
    }

    func isAthlete(username: String) -> Bool {
        athleteByUsername[username.lowercased()] ?? false
    }

    @discardableResult
    func ensureAthleteStatus(userID: String) async -> Bool {
        let key = userID.lowercased()
        if let cached = athleteByUserID[key] { return cached }
        let flag = await fetchAthleteFlag(userID: userID) ?? false
        athleteByUserID[key] = flag
        return flag
    }

    @discardableResult
    func ensureAthleteStatus(username: String) async -> Bool {
        let key = username.lowercased()
        if let cached = athleteByUsername[key] { return cached }
        guard isRemote else {
            athleteByUsername[key] = false
            return false
        }
        let flag = await fetchAthleteFlag(username: username) ?? false
        athleteByUsername[key] = flag
        return flag
    }

    func ensureAthleteStatuses(usernames: [String]) async {
        let unique = Set(usernames.map { $0.lowercased() }).filter { !$0.isEmpty }
        let pending = unique.filter { athleteByUsername[$0] == nil }
        await withTaskGroup(of: (String, Bool).self) { group in
            for name in pending {
                group.addTask {
                    let flag = await self.fetchAthleteFlag(username: name) ?? false
                    return (name, flag)
                }
            }
            for await (name, flag) in group {
                athleteByUsername[name] = flag
            }
        }
    }

    func ensureAthleteStatuses(userIDs: [String]) async {
        let unique = Set(userIDs.map { $0.lowercased() })
            .filter { !$0.isEmpty && $0 != "guest" && !$0.hasPrefix("local_") }
        let pending = unique.filter { athleteByUserID[$0] == nil }
        guard !pending.isEmpty else { return }
        await withTaskGroup(of: (String, Bool).self) { group in
            for id in pending {
                group.addTask {
                    let flag = await self.fetchAthleteFlag(userID: id) ?? false
                    return (id, flag)
                }
            }
            for await (id, flag) in group {
                athleteByUserID[id] = flag
            }
        }
    }

    nonisolated private struct AthleteFlagRow: Decodable, Sendable {
        let is_athlete: Bool?
    }

    private func fetchAthleteFlag(username: String) async -> Bool? {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var any: Bool? = nil
        do {
            let row: AthleteFlagRow = try await client
                .from("profiles")
                .select("is_athlete")
                .ilike("username", pattern: trimmed)
                .limit(1)
                .single()
                .execute()
                .value
            if let v = row.is_athlete { any = (any ?? false) || v }
        } catch { }
        do {
            let row: AthleteFlagRow = try await client
                .from("whisper_profiles")
                .select("is_athlete")
                .ilike("username", pattern: trimmed)
                .limit(1)
                .single()
                .execute()
                .value
            if let v = row.is_athlete { any = (any ?? false) || v }
        } catch { }
        return any
    }

    private func fetchAthleteFlag(userID: String) async -> Bool? {
        guard !userID.isEmpty, userID != "guest", !userID.hasPrefix("local_") else { return nil }
        var any: Bool? = nil
        do {
            let row: AthleteFlagRow = try await client
                .from("whisper_profiles")
                .select("is_athlete")
                .eq("user_id", value: userID)
                .single()
                .execute()
                .value
            if let v = row.is_athlete { any = (any ?? false) || v }
        } catch { }
        do {
            let row: AthleteFlagRow = try await client
                .from("profiles")
                .select("is_athlete")
                .eq("id", value: userID)
                .single()
                .execute()
                .value
            if let v = row.is_athlete { any = (any ?? false) || v }
        } catch { }
        return any
    }

    func markCelebrated() {
        shouldCelebrateApproval = false
        AccountStorage.set(true, forKey: celebrationKey())
    }

    private func celebrationKey() -> String {
        "\(celebratedKey).\(currentUID.lowercased())"
    }

    // MARK: - Application

    private func refreshPendingApplication() async {
        guard isRemote else { return }
        do {
            let rows: [WhisperAthleteApplicationRow] = try await client
                .from("whisper_athlete_applications")
                .select("id,user_id,username,status,created_at")
                .eq("user_id", value: currentUID)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            let pending = rows.first?.status == "pending"
            hasPendingApplication = pending
            AccountStorage.set(pending, forKey: pendingKey)
            hasApprovedApplication = rows.first?.status == "approved"
        } catch { }
    }

    @discardableResult
    func submitApplication(
        fullName: String,
        email: String,
        sport: String,
        level: String,
        team: String,
        prs: String,
        bio: String,
        social: String
    ) async -> Bool {
        guard isRemote else {
            lastError = "Sign in to Whisper first to apply."
            return false
        }
        let username = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "you"
        let payload = WhisperAthleteApplicationInsert(
            user_id: currentUID,
            username: username,
            email: email.isEmpty ? nil : email,
            full_name: fullName,
            sport: sport,
            level: level,
            team: team,
            prs: prs,
            bio: bio,
            social: social.isEmpty ? nil : social
        )
        var insertOK = false
        do {
            try await client.from("whisper_athlete_applications").insert(payload).execute()
            insertOK = true
            hasPendingApplication = true
            AccountStorage.set(true, forKey: pendingKey)
            lastError = nil
        } catch {
            let msg = error.localizedDescription.lowercased()
            if msg.contains("relation") && msg.contains("does not exist") {
                lastError = "Athlete application table missing. Owner: run the WhisperAthleteService SQL block once."
            } else {
                lastError = "Couldn't save your application: \(error.localizedDescription)"
            }
            print("[Whisper] athlete apply error: \(error)")
        }
        await openReviewMail(
            username: username,
            fullName: fullName,
            email: email,
            sport: sport,
            level: level,
            team: team,
            prs: prs,
            bio: bio,
            social: social
        )
        return insertOK
    }

    private func openReviewMail(
        username: String,
        fullName: String,
        email: String,
        sport: String,
        level: String,
        team: String,
        prs: String,
        bio: String,
        social: String
    ) async {
        let subject = "Whisper athlete application — @\(username)"
        let body = """
        New athlete application from Whisper

        Username: @\(username)
        Full name: \(fullName)
        Email: \(email)
        Sport: \(sport)
        Level: \(level)
        Team / Affiliation: \(team)
        Social: \(social)

        Personal records
        ----------------
        \(prs)

        Bio
        ---
        \(bio)

        Reviewer actions
        ----------------
        1. Find the row in Supabase → whisper_athlete_applications.
        2. If approved, in SQL editor run:
           update public.whisper_profiles set is_athlete = true where user_id = '<uuid>';
           update public.profiles set is_athlete = true where id = '<uuid>';
           update public.whisper_athlete_applications set status = 'approved' where id = '<row id>';
        3. If denied, set status = 'denied'.
        """
        lastReviewEmailBody = "To: \(Self.reviewEmail)\nSubject: \(subject)\n\n" + body
        UIPasteboard.general.string = lastReviewEmailBody
        didCopyReviewEmail = true

        let shortBody = """
        New athlete application from @\(username) (\(fullName)).
        Sport: \(sport) · Level: \(level)
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
