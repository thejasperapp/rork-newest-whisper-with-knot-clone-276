import Foundation
import SwiftUI
import Supabase

/// ONE query that hydrates every role/badge the app gates on — coach,
/// athlete, recruiter, brand, verified / moderator / admin / owner —
/// straight from the signed-in user's own `whisper_profiles` row, the single
/// source of truth every promotion writes to (see
/// `supabase/account-status.sql`).
///
/// Seeds the per-role services on load so every existing gate (inbox
/// briefcase, meeting tools, settings studios, badge chips) flips instantly
/// without each service running its own network round-trip. Seeding only
/// UPGRADES (never flips a role off) — the role services keep their own
/// refresh logic as the authoritative downgrade path.
@MainActor
@Observable
final class WhisperAccountStatusService {
    static let shared = WhisperAccountStatusService()

    struct Status: Equatable {
        var isCoach = false
        var isAthlete = false
        var isRecruiter = false
        var isBrand = false
        var isVerified = false
        var isModerator = false
        var isAdmin = false
        var isOwner = false
        var username: String?

        var hasBadge: Bool { isVerified || isModerator || isAdmin || isOwner }
        /// Any promotion that unlocks the inbox briefcase / role tools.
        var hasAnyRole: Bool { isCoach || isAthlete || isRecruiter || isBrand || hasBadge }
        var badge: UserBadge {
            if isOwner { return .owner }
            if isAdmin { return .admin }
            if isModerator { return .moderator }
            if isVerified { return .verified }
            return .none
        }
    }

    private(set) var status = Status()
    private(set) var loadedAt: Date?

    private let client = SupabaseService.shared.client
    @ObservationIgnored private var inFlight: Task<Void, Never>?

    private init() {}

    private nonisolated struct Row: Decodable {
        let username: String?
        let is_coach: Bool?
        let is_athlete: Bool?
        let is_recruiter: Bool?
        let is_brand: Bool?
        let is_verified: Bool?
        let is_moderator: Bool?
        let is_admin: Bool?
        let is_owner: Bool?
    }

    /// Refreshes the unified status (60s freshness unless `force`).
    /// Concurrent callers share one request.
    func resetForCurrentAccount() {
        inFlight?.cancel(); inFlight = nil
        status = Status(); loadedAt = nil
        WhisperCoachService.shared.isMeCoach = false
        WhisperAthleteService.shared.isMeAthlete = false
        WhisperRecruiterService.shared.isMeRecruiter = false
    }

    func refresh(force: Bool = false) async {
        if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < 60 { return }
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { await self.load() }
        inFlight = task
        await task.value
        if inFlight == task { inFlight = nil }
    }

    private func load() async {
        let generation = AccountStorage.generation
        guard let uid = client.auth.currentUser?.id.uuidString else {
            status = Status()
            return
        }
        // Full column set first; pre-migration schemas fall back to the
        // columns that have always existed on whisper_profiles.
        let full = "username,is_coach,is_athlete,is_recruiter,is_brand,is_verified,is_moderator,is_admin,is_owner"
        let legacy = "username,is_coach,is_athlete,is_recruiter"
        var row: Row?
        for columns in [full, legacy] {
            do {
                let rows: [Row] = try await client
                    .from("whisper_profiles")
                    .select(columns)
                    .eq("user_id", value: uid)
                    .limit(1)
                    .execute()
                    .value
                row = rows.first
                break
            } catch {
                continue
            }
        }
        guard !Task.isCancelled, generation == AccountStorage.generation,
              uid.caseInsensitiveCompare(AccountStorage.currentUserID) == .orderedSame,
              let row else { return }
        var next = Status()
        next.username = row.username
        next.isCoach = row.is_coach ?? false
        next.isAthlete = row.is_athlete ?? false
        next.isRecruiter = row.is_recruiter ?? false
        next.isBrand = row.is_brand ?? false
        next.isVerified = row.is_verified ?? false
        next.isModerator = row.is_moderator ?? false
        next.isAdmin = row.is_admin ?? false
        next.isOwner = row.is_owner ?? false
        status = next
        loadedAt = Date()
        seedLegacyServices(next)
    }

    /// Pushes the unified answer into the per-role services so their gates
    /// flip without waiting on their own fetches. Upgrade-only: a `true`
    /// here seeds `true`; a `false` never downgrades a service that already
    /// verified itself (pre-migration rows may lag the role tables).
    private func seedLegacyServices(_ status: Status) {
        if status.isCoach { WhisperCoachService.shared.isMeCoach = true }
        if status.isAthlete { WhisperAthleteService.shared.isMeAthlete = true }
        if status.isRecruiter { WhisperRecruiterService.shared.isMeRecruiter = true }
        if let username = status.username, !username.isEmpty, status.hasBadge {
            UserVerificationService.shared.seed(username: username, badge: status.badge)
        }
    }
}
