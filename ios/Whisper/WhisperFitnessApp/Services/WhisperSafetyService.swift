import Foundation
import SwiftUI
import Supabase

// MARK: - Supabase schema (run once in SQL editor)
//
// -- Mirror the user's age band on profiles so other clients can render the
// -- Teen / 18+ chips without ever needing to read raw DOB. The column is
// -- recomputed client-side whenever the profile syncs and is one of:
// --   'teen'    — under 18
// --   'adult'   — 18 or older (self-attested)
// --   null      — unknown (no DOB on file yet)
// alter table public.profiles
//     add column if not exists age_band text;
//
// -- Self-attested 18+ flag. Flipped on once the user confirms in the safety
// -- sheet. Independent from age_band so a 14-year-old can never accidentally
// -- get the adult-verified chip just by changing their DOB.
// alter table public.profiles
//     add column if not exists is_adult_attested boolean not null default false;
//
// -- Public safety strike log. Inserted by Jasper's chat guard when a DM that
// -- crosses an adult ↔ minor boundary (3+ year gap) is flagged.
// create table if not exists public.whisper_safety_strikes (
//     id uuid primary key default gen_random_uuid(),
//     target_user_id uuid not null,
//     target_username text,
//     reporter_user_id uuid,
//     other_user_id uuid,
//     category text not null,        -- grooming | sexual | meetup | personal_info | hostile | other
//     severity text not null,        -- low | medium | high
//     excerpt text,                  -- first 280 chars of the message
//     reasoning text,                -- model's short explanation
//     created_at timestamptz not null default now()
// );
// create index if not exists whisper_safety_strikes_target_idx
//     on public.whisper_safety_strikes (target_user_id, created_at desc);
// alter table public.whisper_safety_strikes enable row level security;
// drop policy if exists "safety strikes insert" on public.whisper_safety_strikes;
// create policy "safety strikes insert" on public.whisper_safety_strikes
//     for insert with check (auth.uid() is not null);
// -- Only mods/admins/owners can read strikes; regular users cannot see who
// -- has been flagged or what was logged about them.
// drop policy if exists "safety strikes mod read" on public.whisper_safety_strikes;
// create policy "safety strikes mod read" on public.whisper_safety_strikes
//     for select using (
//         exists (
//             select 1 from public.profiles p
//             where p.id = auth.uid()
//               and (p.is_moderator = true or p.is_admin = true or p.is_owner = true)
//         )
//     );
//
// -- Materialized safety-watch flag per user. Auto-set by the strike pipeline
// -- once a user accumulates ≥3 medium+ strikes in 30 days. Visible only to
// -- mods/admins/owner — never rendered publicly.
// create table if not exists public.whisper_safety_flags (
//     user_id uuid primary key,
//     username text,
//     reason text,
//     strike_count int not null default 0,
//     last_strike_at timestamptz,
//     created_at timestamptz not null default now()
// );
// alter table public.whisper_safety_flags enable row level security;
// drop policy if exists "safety flags mod read" on public.whisper_safety_flags;
// create policy "safety flags mod read" on public.whisper_safety_flags
//     for select using (
//         exists (
//             select 1 from public.profiles p
//             where p.id = auth.uid()
//               and (p.is_moderator = true or p.is_admin = true or p.is_owner = true)
//         )
//     );
// drop policy if exists "safety flags write" on public.whisper_safety_flags;
// create policy "safety flags write" on public.whisper_safety_flags
//     for all using (auth.uid() is not null) with check (auth.uid() is not null);

/// Coarse age classification used by every safety check. Never carries the
/// raw DOB — only the band — so it can be cached and synced without leaking
/// minor users' birthdays.
nonisolated enum WhisperAgeBand: String, Codable, Sendable {
    case teen      // under 18
    case adult     // 18 or older
    case unknown   // no DOB on file
}

nonisolated struct WhisperAgeRow: Decodable, Sendable {
    let id: String
    let username: String?
    let age_band: String?
    let is_adult_attested: Bool?
    let is_dm_restricted: Bool?
    let created_at: Date?
    let helpful_report_count: Int?
    let is_trusted_member: Bool?
}

nonisolated struct WhisperSafetyFlagRow: Codable, Sendable, Identifiable {
    let user_id: String
    let username: String?
    let reason: String?
    let strike_count: Int?
    let last_strike_at: Date?
    let created_at: Date?

    var id: String { user_id }
}

/// Central safety service: maintains age bands for the social graph, decides
/// when an outbound DM needs an Jasper scan, records strikes, and surfaces
/// the moderator-only "Safety Watch" flag.
@Observable
@MainActor
final class WhisperSafetyService {
    static let shared = WhisperSafetyService()

    /// Auto-apply the Safety Watch flag once a user crosses this many
    /// medium+ strikes in the rolling window.
    static let watchThreshold: Int = 3
    /// Helpful confirmed reports required for the Community Guardian chip.
    static let guardianThreshold: Int = 3
    static let watchWindow: TimeInterval = 60 * 60 * 24 * 30
    /// Minimum age gap before an adult ↔ minor message is scanned.
    static let minScanAgeGapYears: Int = 3
    /// An account must be at least this old to earn the Established Member chip.
    static let establishedMinAge: TimeInterval = 60 * 60 * 24 * 30
    /// Accounts created before this date wear the Founding Member chip.
    static let foundingCutoff: Date = Date(timeIntervalSince1970: 1_780_876_800) // 2026-06-08

    private let client = SupabaseService.shared.client

    // user_id (lowercased) -> age band
    private(set) var ageBandByUserID: [String: WhisperAgeBand] = [:]
    // user_id (lowercased) -> self-attested 18+
    private(set) var adultAttestedByUserID: [String: Bool] = [:]
    // user_id (lowercased) -> automated DM restriction flag (public)
    private(set) var dmRestrictedByUserID: [String: Bool] = [:]
    // user_id (lowercased) -> profile created_at
    private(set) var createdAtByUserID: [String: Date] = [:]
    // user_id (lowercased) -> count of moderator-confirmed helpful reports
    private(set) var helpfulReportsByUserID: [String: Int] = [:]
    // user_id (lowercased) -> server-maintained trusted-member flag
    private(set) var trustedByUserID: [String: Bool] = [:]
    // user_id (lowercased) -> safety watch row (mod-only)
    private(set) var watchByUserID: [String: WhisperSafetyFlagRow] = [:]
    // username (lowercased) -> watch row (mod-only)
    private(set) var watchByUsername: [String: WhisperSafetyFlagRow] = [:]

    private var ageInFlight: Set<String> = []

    private init() {}

    // MARK: - Age band lookup

    func ageBand(forUserID raw: String) -> WhisperAgeBand {
        ageBandByUserID[raw.lowercased()] ?? .unknown
    }

    func isTeen(userID raw: String) -> Bool {
        ageBand(forUserID: raw) == .teen
    }

    func isAdult(userID raw: String) -> Bool {
        ageBand(forUserID: raw) == .adult
    }

    func isAdultAttested(userID raw: String) -> Bool {
        adultAttestedByUserID[raw.lowercased()] ?? false
    }

    func isDMRestricted(userID raw: String) -> Bool {
        dmRestrictedByUserID[raw.lowercased()] ?? false
    }

    func createdAt(forUserID raw: String) -> Date? {
        createdAtByUserID[raw.lowercased()]
    }

    /// Public Established Member chip — account ≥30 days old, zero medium+
    /// strikes, no active DM restriction. We treat the absence of a watch
    /// row as "clean" because watch rows are only created at the strike
    /// threshold.
    func isEstablishedMember(userID raw: String) -> Bool {
        let key = raw.lowercased()
        guard let created = createdAtByUserID[key] else { return false }
        guard Date().timeIntervalSince(created) >= Self.establishedMinAge else { return false }
        if dmRestrictedByUserID[key] == true { return false }
        if watchByUserID[key] != nil { return false }
        return true
    }

    /// Public Founding Member chip — account created before `foundingCutoff`.
    func isFoundingMember(userID raw: String) -> Bool {
        guard let created = createdAtByUserID[raw.lowercased()] else { return false }
        return created < Self.foundingCutoff
    }

    /// Public Community Guardian chip — account has at least
    /// `guardianThreshold` moderator-confirmed helpful reports and no active
    /// DM restriction or watch flag.
    func isCommunityGuardian(userID raw: String) -> Bool {
        let key = raw.lowercased()
        if dmRestrictedByUserID[key] == true { return false }
        if watchByUserID[key] != nil { return false }
        return (helpfulReportsByUserID[key] ?? 0) >= Self.guardianThreshold
    }

    /// Public Trusted Member chip — server-maintained flag set when an account
    /// is long-standing, has positive social signal, and a clean safety
    /// record. Suppressed while the user is under any restriction.
    func isTrustedMember(userID raw: String) -> Bool {
        let key = raw.lowercased()
        if dmRestrictedByUserID[key] == true { return false }
        if watchByUserID[key] != nil { return false }
        return trustedByUserID[key] ?? false
    }

    /// Bulk-load age bands for a set of user ids. Cached after the first hit.
    func preloadAgeBands(userIDs: [String]) async {
        let normalized = Set(userIDs
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && ageBandByUserID[$0] == nil && !ageInFlight.contains($0) })
        guard !normalized.isEmpty else { return }
        ageInFlight.formUnion(normalized)
        defer { ageInFlight.subtract(normalized) }

        do {
            let rows: [WhisperAgeRow] = try await client
                .from("profiles")
                .select("id,username,age_band,is_adult_attested,is_dm_restricted,created_at,helpful_report_count,is_trusted_member")
                .in("id", values: Array(normalized))
                .execute()
                .value
            var band = ageBandByUserID
            var attested = adultAttestedByUserID
            var restricted = dmRestrictedByUserID
            var created = createdAtByUserID
            var helpful = helpfulReportsByUserID
            var trusted = trustedByUserID
            for row in rows {
                let key = row.id.lowercased()
                if let raw = row.age_band, let parsed = WhisperAgeBand(rawValue: raw) {
                    band[key] = parsed
                } else {
                    band[key] = .unknown
                }
                attested[key] = row.is_adult_attested ?? false
                restricted[key] = row.is_dm_restricted ?? false
                if let c = row.created_at { created[key] = c }
                helpful[key] = row.helpful_report_count ?? 0
                trusted[key] = row.is_trusted_member ?? false
            }
            for key in normalized where band[key] == nil {
                band[key] = .unknown
            }
            ageBandByUserID = band
            adultAttestedByUserID = attested
            dmRestrictedByUserID = restricted
            createdAtByUserID = created
            helpfulReportsByUserID = helpful
            trustedByUserID = trusted
        } catch {
            // Silent — safety is non-critical for rendering.
        }
    }

    // MARK: - Sync local user's age band to Supabase

    /// Called by `AuthenticationService` whenever the profile is saved. Derives
    /// the band from `dateOfBirth` and writes it to the `profiles` row so other
    /// clients can render Teen / 18+ chips without ever reading the raw DOB.
    func syncOwnAgeBand(userID: String, dateOfBirth: Date?) async {
        guard !userID.isEmpty, userID != "guest", !userID.hasPrefix("local_") else { return }
        let band = Self.band(forDOB: dateOfBirth)
        nonisolated struct BandUpdate: Encodable {
            let age_band: String?
        }
        do {
            _ = try await client
                .from("profiles")
                .update(BandUpdate(age_band: band == .unknown ? nil : band.rawValue))
                .eq("id", value: userID)
                .execute()
            ageBandByUserID[userID.lowercased()] = band
        } catch {
            // Column probably missing — surface in logs but don't break sign-in.
            print("[Safety] age_band sync failed: \(error.localizedDescription)")
        }
    }

    /// Stamps the self-attested 18+ flag. Caller is expected to gate this
    /// behind an explicit confirmation sheet.
    func attestAdult(userID: String) async -> Bool {
        guard !userID.isEmpty, userID != "guest" else { return false }
        nonisolated struct AdultUpdate: Encodable {
            let is_adult_attested: Bool
        }
        do {
            _ = try await client
                .from("profiles")
                .update(AdultUpdate(is_adult_attested: true))
                .eq("id", value: userID)
                .execute()
            adultAttestedByUserID[userID.lowercased()] = true
            return true
        } catch {
            print("[Safety] adult attest failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Scan decision

    /// Returns true if an outbound DM should be sent through the Jasper chat
    /// guard. We only scan when one side is a teen, the other is an adult,
    /// and the bands differ — never adult↔adult or teen↔teen.
    func shouldScan(senderUserID: String, recipientUserID: String) -> Bool {
        let s = ageBand(forUserID: senderUserID)
        let r = ageBand(forUserID: recipientUserID)
        guard s != .unknown, r != .unknown else { return false }
        return (s == .adult && r == .teen) || (s == .teen && r == .adult)
    }

    // MARK: - Strike recording

    nonisolated struct StrikeInsert: Codable, Sendable {
        let target_user_id: String
        let target_username: String?
        let reporter_user_id: String?
        let other_user_id: String?
        let category: String
        let severity: String
        let excerpt: String?
        let reasoning: String?
    }

    /// Records a single safety strike for the adult side of a flagged DM.
    /// Strikes against minors are intentionally not recorded — the system is
    /// designed to protect the under-18 user, not punish them.
    func recordStrike(
        targetUserID: String,
        targetUsername: String?,
        otherUserID: String,
        category: WhisperSafetyCategory,
        severity: WhisperSafetySeverity,
        excerpt: String,
        reasoning: String
    ) async {
        guard !targetUserID.isEmpty else { return }
        let generation = AccountStorage.generation
        guard client.auth.currentUser?.id.uuidString.lowercased() == targetUserID.lowercased() else { return }
        nonisolated struct Signal: Encodable, Sendable {
            let p_kind: String
            let p_reason: String
            let p_target_id: String
            let p_details: String
        }
        do {
            let receipt: UUID = try await client.rpc("whisper_submit_report", params: Signal(
                p_kind: "dm", p_reason: "AI review signal — not a finding",
                p_target_id: targetUserID,
                p_details: "Unreviewed AI signal. Category: \(category.rawValue). Excerpt: \(String(excerpt.prefix(280))). Reasoning: \(String(reasoning.prefix(400)))"
            )).execute().value
            guard generation == AccountStorage.generation else { return }
            _ = receipt
        } catch {
            // A failed optional signal never becomes a penalty or a local restriction.
        }
    }

    nonisolated struct StrikeCountRow: Decodable, Sendable {
        let id: String
        let severity: String
        let created_at: Date
    }

    private func evaluateWatch(forUserID userID: String, username: String?) async {
        let since = Date().addingTimeInterval(-Self.watchWindow)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        do {
            let rows: [StrikeCountRow] = try await client
                .from("whisper_safety_strikes")
                .select("id,severity,created_at")
                .eq("target_user_id", value: userID)
                .gte("created_at", value: iso.string(from: since))
                .execute()
                .value
            let serious = rows.filter { $0.severity == "medium" || $0.severity == "high" }.count
            guard serious >= Self.watchThreshold else { return }
            await applyWatch(userID: userID, username: username, strikeCount: serious, lastStrike: rows.first?.created_at)
        } catch {
            // silent
        }
    }

    nonisolated struct WatchUpsert: Codable, Sendable {
        let user_id: String
        let username: String?
        let reason: String
        let strike_count: Int
        let last_strike_at: Date?
    }

    private func applyWatch(userID: String, username: String?, strikeCount: Int, lastStrike: Date?) async {
        let reason = "Auto-flagged after \(strikeCount) medium+ Jasper chat-safety strikes in the last 30 days."
        let payload = WatchUpsert(
            user_id: userID,
            username: username,
            reason: reason,
            strike_count: strikeCount,
            last_strike_at: lastStrike
        )
        do {
            try await client
                .from("whisper_safety_flags")
                .upsert(payload, onConflict: "user_id")
                .execute()
            // Refresh local cache (mod-only — fetch will succeed only for mods).
            await refreshWatch(userID: userID)
        } catch {
            // silent
        }
        // Public escalation: flip the DM-restricted flag so the orange
        // "Limited" chip appears for every viewer, not just mods.
        await applyDMRestriction(userID: userID)
    }

    nonisolated struct RestrictedUpdate: Encodable {
        let is_dm_restricted: Bool
    }

    private func applyDMRestriction(userID: String) async {
        do {
            _ = try await client
                .from("profiles")
                .update(RestrictedUpdate(is_dm_restricted: true))
                .eq("id", value: userID)
                .execute()
            dmRestrictedByUserID[userID.lowercased()] = true
        } catch {
            // silent — column may be missing on older schemas
        }
    }

    // MARK: - Safety watch (mod-only visibility)

    /// Reads `whisper_safety_flags` for a batch of users. Will silently return
    /// no rows when the viewer isn't a mod/admin/owner (RLS rejects the read).
    func preloadWatchFlags(userIDs: [String], usernames: [String]) async {
        let ids = Set(userIDs.map { $0.lowercased() }.filter { !$0.isEmpty })
        let names = Set(usernames.map { $0.lowercased() }.filter { !$0.isEmpty })
        guard !ids.isEmpty || !names.isEmpty else { return }
        do {
            if !ids.isEmpty {
                let rows: [WhisperSafetyFlagRow] = try await client
                    .from("whisper_safety_flags")
                    .select("user_id,username,reason,strike_count,last_strike_at,created_at")
                    .in("user_id", values: Array(ids))
                    .execute()
                    .value
                var byID = watchByUserID
                var byName = watchByUsername
                for r in rows {
                    byID[r.user_id.lowercased()] = r
                    if let n = r.username?.lowercased(), !n.isEmpty { byName[n] = r }
                }
                watchByUserID = byID
                watchByUsername = byName
            }
            if !names.isEmpty {
                let rows: [WhisperSafetyFlagRow] = try await client
                    .from("whisper_safety_flags")
                    .select("user_id,username,reason,strike_count,last_strike_at,created_at")
                    .in("username", values: Array(names))
                    .execute()
                    .value
                var byID = watchByUserID
                var byName = watchByUsername
                for r in rows {
                    byID[r.user_id.lowercased()] = r
                    if let n = r.username?.lowercased(), !n.isEmpty { byName[n] = r }
                }
                watchByUserID = byID
                watchByUsername = byName
            }
        } catch {
            // RLS likely rejected — viewer isn't a mod. Silent.
        }
    }

    func refreshWatch(userID: String) async {
        do {
            let rows: [WhisperSafetyFlagRow] = try await client
                .from("whisper_safety_flags")
                .select("user_id,username,reason,strike_count,last_strike_at,created_at")
                .eq("user_id", value: userID)
                .limit(1)
                .execute()
                .value
            if let r = rows.first {
                watchByUserID[r.user_id.lowercased()] = r
                if let n = r.username?.lowercased() { watchByUsername[n] = r }
            }
        } catch {
            // silent
        }
    }

    /// True when the viewer is a mod/admin/owner AND the user wears a watch flag.
    /// Public callers gate badge rendering through this so it's never shown to
    /// rank-and-file users.
    func canSeeWatchBadge() -> Bool {
        let me = (LeaderboardService.shared.savedUsername
                  ?? AuthenticationService.shared.currentUser.username
                  ?? "").lowercased()
        guard !me.isEmpty else { return false }
        let badge = UserVerificationService.shared.badge(forUsername: me)
        return badge == .moderator || badge == .admin || badge == .owner
    }

    func watchRow(forUsername raw: String) -> WhisperSafetyFlagRow? {
        guard canSeeWatchBadge() else { return nil }
        return watchByUsername[raw.lowercased()]
    }

    func watchRow(forUserID raw: String) -> WhisperSafetyFlagRow? {
        guard canSeeWatchBadge() else { return nil }
        return watchByUserID[raw.lowercased()]
    }

    // MARK: - DOB → band helper

    /// Pure helper used by `syncOwnAgeBand`. Anyone without a DOB lands in
    /// `.unknown` until they complete onboarding.
    nonisolated static func band(forDOB dob: Date?) -> WhisperAgeBand {
        guard let dob else { return .unknown }
        let years = Calendar.current.dateComponents([.year], from: dob, to: Date()).year ?? 0
        return years >= 18 ? .adult : .teen
    }
}

/// Categories the Jasper chat guard classifies into. Kept narrow so the model
/// doesn't drift into general "rude message" territory — this is specifically
/// for safety across an adult ↔ minor age boundary.
nonisolated enum WhisperSafetyCategory: String, Codable, Sendable {
    case grooming         // attempts to build inappropriate emotional / romantic relationship
    case sexual           // sexual content / requests
    case meetup           // pushing for in-person meetup, address, school name
    case personalInfo     // probing for phone, address, school, social handles
    case hostile          // bullying, threats, doxxing
    case other
}

nonisolated enum WhisperSafetySeverity: String, Codable, Sendable {
    case none
    case low
    case medium
    case high
}
