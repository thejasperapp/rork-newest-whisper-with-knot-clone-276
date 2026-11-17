import Foundation
import Supabase
import SwiftUI

/// Supabase-backed talent recruiter workspace — mirrors the web recruiter
/// dashboard: prospect pipeline, role promotions, monthly targets, referral
/// codes, and scouting territories (the territory map).
@MainActor
@Observable
final class WhisperRecruiterService {
    static let shared = WhisperRecruiterService()

    private let client = SupabaseService.shared.client
    private var currentUID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { currentUID != "guest" && !currentUID.hasPrefix("local_") }

    var isMeRecruiter: Bool = false
    var prospects: [ProspectRow] = []
    var promotions: [PromotionRow] = []
    var target: TargetRow?
    var referralCode: ReferralCodeRow?
    var territories: [TerritoryRow] = []
    var applications: [ApplicationRow] = []
    var lastError: String?
    private var clientMetadata: [String: RecruiterClient] = [:]
    private var metadataGeneration: UUID?
    var clientMetadataError: String?
    nonisolated struct ClientList: Decodable, Sendable { let clients: [String: RecruiterClient] }
    func clientProfile(_ id: String) -> RecruiterClient? {
        guard metadataGeneration == AccountStorage.generation else { return nil }
        return clientMetadata[id]
    }
    func refreshClientMetadata() async {
        let generation = AccountStorage.generation
        let owner = currentUID.lowercased()
        do {
            let result: ClientList = try await JasperMeetingService.request("clients/list", owner: owner)
            guard generation == AccountStorage.generation else { return }
            clientMetadata = result.clients; metadataGeneration = generation; clientMetadataError = nil
        } catch {
            if generation == AccountStorage.generation { clientMetadataError = error.localizedDescription; clientMetadata = [:] }
        }
    }
    /// False until supabase/recruiting-v4.sql runs — v4 surfaces (next steps,
    /// tags, scorecards, timelines) degrade to honest banners meanwhile.
    var v4Available: Bool = true

    private init() {}

    // MARK: - Row types

    nonisolated struct ProspectRow: Codable, Sendable, Identifiable, Hashable {
        let id: String
        let recruiter_id: String
        let prospect_user_id: String?
        let prospect_username: String?
        let prospect_display_name: String?
        let prospect_image_url: String?
        let source: String?
        let location: String?
        let niche: String?
        let instagram: String?
        let tiktok: String?
        let suggested_role: String?
        var status: String
        var notes: String?
        var shared_notes: String?
        var rating: Int?
        let created_at: String?
        let updated_at: String?
        // v4 — optional so rows decode before recruiting-v4.sql runs.
        var tags: [String]?
        var next_action: String?
        var next_action_due: String?
        var last_touch_at: String?
        var scorecard: [String: Int]?
    }

    /// One timeline touchpoint (whisper_prospect_activities, v4).
    nonisolated struct ActivityRow: Codable, Sendable, Identifiable, Hashable {
        let id: String
        let prospect_id: String
        let recruiter_id: String
        let kind: String
        let body: String
        let created_at: String?
    }

    /// One applicant-questionnaire response (whisper_applicant_responses).
    nonisolated struct ApplicationRow: Codable, Sendable, Identifiable, Hashable {
        let id: String
        let applicant_user_id: String?
        let applicant_name: String?
        let applicant_email: String?
        let best_position: String?
        let potential_score: Int?
        let created_at: String?
    }

    nonisolated struct PromotionRow: Codable, Sendable, Identifiable, Hashable {
        let id: String
        let recruiter_id: String
        let recruiter_username: String?
        let promoted_id: String
        let promoted_username: String
        let role: String
        let notes: String?
        let created_at: String?
    }

    nonisolated struct TargetRow: Codable, Sendable, Identifiable, Hashable {
        let id: String
        let recruiter_id: String
        let period: String
        let target_coach: Int
        let target_athlete: Int
        let target_creator: Int
        let notes: String?
    }

    nonisolated struct ReferralCodeRow: Codable, Sendable, Identifiable, Hashable {
        let id: String
        let recruiter_id: String
        let code: String
        let uses: Int
        let created_at: String?
    }

    nonisolated struct TerritoryRow: Codable, Sendable, Identifiable, Hashable {
        let id: String
        let recruiter_id: String
        let name: String
        let region: String
        let cities: String?
        let notes: String?
        let color: String?
        let created_at: String?
        /// Real GPS pin — set from the claimer's location or wherever they
        /// drop the pin. Optional so rows predating the geo migration decode.
        let latitude: Double?
        let longitude: Double?
    }

    // MARK: - Constants

    nonisolated static let prospectStatuses: [(value: String, label: String)] = [
        ("discovered", "Discovered"), ("contacted", "Contacted"),
        ("interested", "Interested"), ("meeting", "Meeting"),
        ("ready", "Ready"), ("passed", "Passed")
    ]

    /// v4 stage labels — the researched CRM names the web pipeline wears
    /// (same underlying status values, so both apps stay wire-compatible).
    nonisolated static let stageLabels: [(value: String, label: String)] = [
        ("discovered", "Sourced"), ("contacted", "Contacted"),
        ("interested", "In talks"), ("meeting", "Evaluating"),
        ("ready", "Offer")
    ]

    nonisolated static func stageLabel(_ status: String) -> String {
        stageLabels.first { $0.value == status }?.label
            ?? (status == "passed" ? "Passed" : status.capitalized)
    }

    /// The four researched scorecard criteria (1–5 each) — web parity.
    nonisolated static let scorecardCriteria: [(id: String, label: String)] = [
        ("talent", "Talent"), ("drive", "Drive"),
        ("coachability", "Coachability"), ("audience", "Audience")
    ]

    /// Composite 0–100 from whatever criteria are scored; nil when none are.
    nonisolated static func compositeScore(_ scorecard: [String: Int]?) -> Int? {
        guard let scorecard, !scorecard.isEmpty else { return nil }
        let values = scorecard.values.filter { $0 > 0 }
        guard !values.isEmpty else { return nil }
        let avg = Double(values.reduce(0, +)) / Double(values.count)
        return Int((avg / 5.0 * 100).rounded())
    }

    /// Days since an ISO timestamp — drives the pipeline aging dots.
    nonisolated static func daysSince(_ iso: String?) -> Int {
        guard let iso, let date = WhisperBackendService.parseISO(iso) else { return 0 }
        return max(0, Int(Date().timeIntervalSince(date) / 86_400))
    }

    /// Parses a `date` column (yyyy-MM-dd) into a local-midnight Date.
    nonisolated static func parseDueDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        return fmt.date(from: String(raw.prefix(10)))
    }

    nonisolated static func dueDateString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        return fmt.string(from: date)
    }

    nonisolated static func statusColor(_ status: String) -> Color {
        switch status {
        case "contacted": return Color(red: 0.23, green: 0.51, blue: 0.96)
        case "interested": return Color(red: 0.66, green: 0.33, blue: 0.91)
        case "meeting": return Color(red: 0.96, green: 0.62, blue: 0.04)
        case "ready": return Color(red: 0.13, green: 0.77, blue: 0.37)
        case "passed": return Color(red: 0.94, green: 0.27, blue: 0.27)
        default: return Color(red: 0.42, green: 0.45, blue: 0.50)
        }
    }

    nonisolated static let regions: [(value: String, label: String)] = [
        ("northeast", "Northeast"), ("southeast", "Southeast"),
        ("midwest", "Midwest"), ("southwest", "Southwest"),
        ("west", "West Coast"), ("northwest", "Northwest"),
        ("international", "International"), ("other", "Other")
    ]

    nonisolated static func regionColor(_ region: String) -> Color {
        switch region {
        case "northeast": return Color(red: 0.23, green: 0.51, blue: 0.96)
        case "southeast": return Color(red: 0.96, green: 0.62, blue: 0.04)
        case "midwest": return Color(red: 0.13, green: 0.77, blue: 0.37)
        case "southwest": return Color(red: 0.94, green: 0.27, blue: 0.27)
        case "west": return Color(red: 0.66, green: 0.33, blue: 0.91)
        case "northwest": return Color(red: 0.02, green: 0.71, blue: 0.83)
        case "international": return Color(red: 0.93, green: 0.28, blue: 0.60)
        default: return Color(red: 0.42, green: 0.45, blue: 0.50)
        }
    }

    nonisolated static func regionLabel(_ region: String) -> String {
        regions.first { $0.value == region }?.label ?? "Other"
    }

    // MARK: - Refresh

    /// Re-checks whether the signed-in user holds the recruiter role.
    func refreshMyStatus() async {
        guard isRemote else {
            isMeRecruiter = false
            return
        }
        struct Row: Codable { let is_recruiter: Bool? }
        do {
            let rows: [Row] = try await client
                .from("whisper_profiles")
                .select("is_recruiter")
                .eq("user_id", value: currentUID)
                .limit(1)
                .execute()
                .value
            isMeRecruiter = rows.first?.is_recruiter ?? false
        } catch {
            // Column may not exist on older schemas — treat as not a recruiter.
            isMeRecruiter = false
        }
    }

    /// Loads the whole recruiter workspace in parallel.
    func refreshAll() async {
        guard isRemote, isMeRecruiter else { return }
        async let p: Void = refreshProspects()
        async let m: Void = refreshPromotions()
        async let t: Void = refreshTarget()
        async let r: Void = refreshReferralCode()
        async let g: Void = refreshTerritories()
        async let a: Void = refreshApplications()
        async let v: Void = probeV4()
        _ = await (p, m, t, r, g, a, v)
    }

    /// True once recruiting-v4.sql has run — probed by selecting a v4 column.
    func probeV4() async {
        struct Probe: Codable { let tags: [String]? }
        do {
            let _: [Probe] = try await client
                .from("whisper_recruiter_prospects")
                .select("tags")
                .limit(1)
                .execute()
                .value
            v4Available = true
        } catch {
            v4Available = false
        }
    }

    // MARK: - Prospects

    func refreshProspects() async {
        let generation = AccountStorage.generation
        let owner = currentUID
        do {
            let rows: [ProspectRow] = try await client
                .from("whisper_recruiter_prospects")
                .select()
                .eq("recruiter_id", value: currentUID)
                .order("updated_at", ascending: false)
                .execute()
                .value
            guard generation == AccountStorage.generation, owner == currentUID else { return }
            prospects = rows
            await refreshClientMetadata()
        } catch {
            lastError = "Couldn't load prospects: \(error.localizedDescription)"
        }
    }

    func addProspect(
        username: String?,
        displayName: String,
        location: String?,
        niche: String?,
        instagram: String?,
        suggestedRole: String?,
        notes: String?,
        rating: Int?,
        status: String = "discovered"
    ) async -> Bool {
        var payload: [String: AnyJSON] = [
            "recruiter_id": .string(currentUID),
            "prospect_display_name": .string(displayName),
            "status": .string(status)
        ]
        if let username, !username.isEmpty { payload["prospect_username"] = .string(username) }
        if let location, !location.isEmpty { payload["location"] = .string(location) }
        if let niche, !niche.isEmpty { payload["niche"] = .string(niche) }
        if let instagram, !instagram.isEmpty { payload["instagram"] = .string(instagram) }
        if let suggestedRole { payload["suggested_role"] = .string(suggestedRole) }
        if let notes, !notes.isEmpty { payload["notes"] = .string(notes) }
        if let rating { payload["rating"] = .integer(rating) }
        do {
            try await client
                .from("whisper_recruiter_prospects")
                .insert(payload)
                .execute()
            await refreshProspects()
            return true
        } catch {
            lastError = "Couldn't add prospect: \(error.localizedDescription)"
            return false
        }
    }

    func updateProspectNotes(_ prospect: ProspectRow, notes: String?, sharedNotes: String?) async {
        do {
            var payload: [String: AnyJSON] = [
                "updated_at": .string(ISO8601DateFormatter().string(from: Date()))
            ]
            if let notes { payload["notes"] = .string(notes) }
            if let sharedNotes { payload["shared_notes"] = .string(sharedNotes) }
            try await client
                .from("whisper_recruiter_prospects")
                .update(payload)
                .eq("id", value: prospect.id)
                .execute()
            if let idx = prospects.firstIndex(where: { $0.id == prospect.id }) {
                prospects[idx].notes = notes
                prospects[idx].shared_notes = sharedNotes
            }
        } catch {
            lastError = "Couldn't update notes: \(error.localizedDescription)"
        }
    }

    func updateProspectStatus(_ prospect: ProspectRow, status: String) async {
        let owner = currentUID.lowercased()
        let generation = AccountStorage.generation
        guard prospect.recruiter_id.lowercased() == owner else { return }
        do {
            let updated: RecruiterClient = try await JasperMeetingService.request("clients/stage?id=\(prospect.id)", owner: owner, body: ["stage": status, "expectedStage": prospect.status, "expectedUpdatedAt": prospect.updated_at as Any? ?? NSNull()])
            guard generation == AccountStorage.generation else { return }
            clientMetadata[prospect.id] = updated; metadataGeneration = generation
            if let idx = prospects.firstIndex(where: { $0.id == prospect.id }) {
                prospects[idx].status = status
            }
            // Auto-log the stage move on the v4 timeline (best-effort).
            await logActivity(
                prospectID: prospect.id,
                kind: "stage",
                body: "Moved to \(Self.stageLabel(status))"
            )
            await refreshProspects()
        } catch {
            lastError = "Couldn't update prospect: \(error.localizedDescription)"
        }
    }

    // MARK: - v4: next steps, tags, scorecards

    /// Saves the prospect's next step + due date (nil action clears both).
    func updateNextAction(_ prospect: ProspectRow, action: String?, due: Date?) async -> Bool {
        var payload: [String: AnyJSON] = [
            "updated_at": .string(ISO8601DateFormatter().string(from: Date()))
        ]
        if let action, !action.isEmpty {
            payload["next_action"] = .string(action)
            payload["next_action_due"] = due != nil ? .string(Self.dueDateString(due!)) : .null
        } else {
            payload["next_action"] = .null
            payload["next_action_due"] = .null
        }
        do {
            try await client
                .from("whisper_recruiter_prospects")
                .update(payload)
                .eq("id", value: prospect.id)
                .execute()
            if let idx = prospects.firstIndex(where: { $0.id == prospect.id }) {
                prospects[idx].next_action = (action?.isEmpty == false) ? action : nil
                prospects[idx].next_action_due = (action?.isEmpty == false && due != nil)
                    ? Self.dueDateString(due!) : nil
            }
            return true
        } catch {
            lastError = "Next steps need the recruiting-v4 migration — run supabase/recruiting-v4.sql once."
            return false
        }
    }

    func updateTags(_ prospect: ProspectRow, tags: [String]) async {
        let clean = Array(Set(tags.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && $0.count <= 24 })).sorted().prefix(12)
        do {
            try await client
                .from("whisper_recruiter_prospects")
                .update(["tags": AnyJSON.array(clean.map { .string($0) })])
                .eq("id", value: prospect.id)
                .execute()
            if let idx = prospects.firstIndex(where: { $0.id == prospect.id }) {
                prospects[idx].tags = Array(clean)
            }
        } catch {
            lastError = "Tags need the recruiting-v4 migration — run supabase/recruiting-v4.sql once."
        }
    }

    func updateScorecard(_ prospect: ProspectRow, scorecard: [String: Int]) async {
        let object: [String: AnyJSON] = scorecard.mapValues { .integer($0) }
        do {
            try await client
                .from("whisper_recruiter_prospects")
                .update(["scorecard": AnyJSON.object(object)])
                .eq("id", value: prospect.id)
                .execute()
            if let idx = prospects.firstIndex(where: { $0.id == prospect.id }) {
                prospects[idx].scorecard = scorecard
            }
        } catch {
            lastError = "Scorecards need the recruiting-v4 migration — run supabase/recruiting-v4.sql once."
        }
    }

    // MARK: - v4: activity timeline

    func fetchActivities(prospectID: String) async -> [ActivityRow] {
        do {
            let rows: [ActivityRow] = try await client
                .from("whisper_prospect_activities")
                .select()
                .eq("prospect_id", value: prospectID)
                .order("created_at", ascending: false)
                .limit(100)
                .execute()
                .value
            return rows
        } catch {
            return []
        }
    }

    /// Logs one touchpoint and stamps last_touch_at. Best-effort — quietly
    /// no-ops until the v4 migration runs.
    @discardableResult
    func logActivity(prospectID: String, kind: String, body: String) async -> Bool {
        let payload: [String: AnyJSON] = [
            "prospect_id": .string(prospectID),
            "recruiter_id": .string(currentUID),
            "kind": .string(kind),
            "body": .string(String(body.prefix(800)))
        ]
        do {
            try await client
                .from("whisper_prospect_activities")
                .insert(payload)
                .execute()
            let now = ISO8601DateFormatter().string(from: Date())
            try? await client
                .from("whisper_recruiter_prospects")
                .update(["last_touch_at": AnyJSON.string(now), "updated_at": .string(now)])
                .eq("id", value: prospectID)
                .execute()
            if let idx = prospects.firstIndex(where: { $0.id == prospectID }) {
                prospects[idx].last_touch_at = now
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Applications (QR questionnaire inbox)

    func refreshApplications() async {
        do {
            let rows: [ApplicationRow] = try await client
                .from("whisper_applicant_responses")
                .select("id, applicant_user_id, applicant_name, applicant_email, best_position, potential_score, created_at")
                .order("created_at", ascending: false)
                .limit(20)
                .execute()
                .value
            applications = rows
        } catch {
            applications = []
        }
    }

    /// True when an application already has a matching pipeline row.
    func isApplicationInPipeline(_ app: ApplicationRow) -> Bool {
        if let uid = app.applicant_user_id,
           prospects.contains(where: { $0.prospect_user_id == uid }) {
            return true
        }
        if let name = app.applicant_name, !name.isEmpty,
           prospects.contains(where: { ($0.prospect_display_name ?? "").caseInsensitiveCompare(name) == .orderedSame }) {
            return true
        }
        return false
    }

    /// Files an application into the pipeline as an "interested" prospect.
    func addApplicationToPipeline(_ app: ApplicationRow) async -> Bool {
        guard !isApplicationInPipeline(app) else { return true }
        let fit = app.best_position.map { "Best fit: \($0.capitalized)" } ?? ""
        let score = app.potential_score.map { " · potential \($0)/100" } ?? ""
        var payload: [String: AnyJSON] = [
            "recruiter_id": .string(currentUID),
            "prospect_display_name": .string(app.applicant_name ?? "Applicant"),
            "source": .string("application"),
            "status": .string("interested"),
            "notes": .string("Applied via questionnaire. \(fit)\(score)".trimmingCharacters(in: .whitespaces))
        ]
        if let uid = app.applicant_user_id { payload["prospect_user_id"] = .string(uid) }
        if let role = app.best_position { payload["suggested_role"] = .string(role) }
        do {
            try await client
                .from("whisper_recruiter_prospects")
                .insert(payload)
                .execute()
            await refreshProspects()
            return true
        } catch {
            lastError = "Couldn't add that applicant: \(error.localizedDescription)"
            return false
        }
    }

    func deleteProspect(_ prospect: ProspectRow) async {
        do {
            try await client
                .from("whisper_recruiter_prospects")
                .delete()
                .eq("id", value: prospect.id)
                .execute()
            prospects.removeAll { $0.id == prospect.id }
        } catch {
            lastError = "Couldn't delete prospect: \(error.localizedDescription)"
        }
    }

    // MARK: - Promotions

    func refreshPromotions() async {
        do {
            let rows: [PromotionRow] = try await client
                .from("whisper_recruiter_promotions")
                .select()
                .eq("recruiter_id", value: currentUID)
                .order("created_at", ascending: false)
                .execute()
                .value
            promotions = rows
        } catch {
            lastError = "Couldn't load promotions: \(error.localizedDescription)"
        }
    }

    /// Promotes a user to coach/athlete/creator — records the promotion and
    /// flips the profile flag, matching the web behavior.
    func promote(userID: String, username: String, role: String, notes: String?) async -> Bool {
        let myUsername = WhisperUserService.shared.me?.username
            ?? LeaderboardService.shared.savedUsername
            ?? "recruiter"
        var payload: [String: AnyJSON] = [
            "recruiter_id": .string(currentUID),
            "recruiter_username": .string(myUsername),
            "promoted_id": .string(userID),
            "promoted_username": .string(username),
            "role": .string(role)
        ]
        if let notes, !notes.isEmpty { payload["notes"] = .string(notes) }
        do {
            try await client
                .from("whisper_recruiter_promotions")
                .upsert(payload, onConflict: "promoted_id,role")
                .execute()
            let flag = Self.flagColumn(for: role)
            try await client
                .from("whisper_profiles")
                .update([flag: AnyJSON.bool(true)])
                .eq("user_id", value: userID)
                .execute()
            await refreshPromotions()
            return true
        } catch {
            lastError = "Couldn't promote user: \(error.localizedDescription)"
            return false
        }
    }

    /// Removes a promotion and unsets the flag if no other recruiter promoted
    /// this user for the same role.
    func removePromotion(_ promo: PromotionRow) async {
        do {
            try await client
                .from("whisper_recruiter_promotions")
                .delete()
                .eq("id", value: promo.id)
                .eq("recruiter_id", value: currentUID)
                .execute()
            promotions.removeAll { $0.id == promo.id }

            struct IDRow: Codable { let id: String }
            let remaining: [IDRow] = try await client
                .from("whisper_recruiter_promotions")
                .select("id")
                .eq("promoted_id", value: promo.promoted_id)
                .eq("role", value: promo.role)
                .limit(1)
                .execute()
                .value
            if remaining.isEmpty {
                let flag = Self.flagColumn(for: promo.role)
                try await client
                    .from("whisper_profiles")
                    .update([flag: AnyJSON.bool(false)])
                    .eq("user_id", value: promo.promoted_id)
                    .execute()
            }
        } catch {
            lastError = "Couldn't remove promotion: \(error.localizedDescription)"
        }
    }

    nonisolated private static func flagColumn(for role: String) -> String {
        switch role {
        case "coach": return "is_coach"
        case "athlete": return "is_athlete"
        default: return "is_verified"
        }
    }

    // MARK: - Targets

    nonisolated static func currentPeriod() -> String {
        let cal = Calendar.current
        let now = Date()
        return String(format: "%04d-%02d", cal.component(.year, from: now), cal.component(.month, from: now))
    }

    func refreshTarget() async {
        do {
            let rows: [TargetRow] = try await client
                .from("whisper_recruiter_targets")
                .select()
                .eq("recruiter_id", value: currentUID)
                .eq("period", value: Self.currentPeriod())
                .limit(1)
                .execute()
                .value
            target = rows.first
        } catch {
            target = nil
        }
    }

    func saveTarget(coach: Int, athlete: Int, creator: Int) async {
        let payload: [String: AnyJSON] = [
            "recruiter_id": .string(currentUID),
            "period": .string(Self.currentPeriod()),
            "target_coach": .integer(coach),
            "target_athlete": .integer(athlete),
            "target_creator": .integer(creator),
            "updated_at": .string(ISO8601DateFormatter().string(from: Date()))
        ]
        do {
            try await client
                .from("whisper_recruiter_targets")
                .upsert(payload, onConflict: "recruiter_id,period")
                .execute()
            await refreshTarget()
        } catch {
            lastError = "Couldn't save targets: \(error.localizedDescription)"
        }
    }

    /// Promotions made this month, keyed by role — drives target progress.
    func monthPromotionCounts() -> [String: Int] {
        let period = Self.currentPeriod()
        var counts: [String: Int] = [:]
        for p in promotions {
            guard let created = p.created_at, created.hasPrefix(period) else { continue }
            counts[p.role, default: 0] += 1
        }
        return counts
    }

    // MARK: - Referral code

    func refreshReferralCode() async {
        do {
            let rows: [ReferralCodeRow] = try await client
                .from("whisper_referral_codes")
                .select()
                .eq("recruiter_id", value: currentUID)
                .limit(1)
                .execute()
                .value
            if let existing = rows.first {
                referralCode = existing
                return
            }
            // Create one: 3 letters from username + 3 random chars
            let username = WhisperUserService.shared.me?.username
                ?? LeaderboardService.shared.savedUsername
                ?? "WSP"
            let prefix = String(username.uppercased().filter { $0.isLetter }.prefix(3))
            let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
            let suffix = String((0..<3).compactMap { _ in chars.randomElement() })
            let code = (prefix.isEmpty ? "WSP" : prefix) + suffix
            let inserted: [ReferralCodeRow] = try await client
                .from("whisper_referral_codes")
                .insert(["recruiter_id": AnyJSON.string(currentUID), "code": .string(code)])
                .select()
                .execute()
                .value
            referralCode = inserted.first
        } catch {
            referralCode = nil
        }
    }

    // MARK: - Territories

    func refreshTerritories() async {
        do {
            let rows: [TerritoryRow] = try await client
                .from("whisper_recruiter_territories")
                .select()
                .eq("recruiter_id", value: currentUID)
                .order("created_at", ascending: true)
                .execute()
                .value
            territories = rows
        } catch {
            territories = []
        }
    }

    func claimTerritory(
        name: String,
        region: String,
        cities: String?,
        notes: String?,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) async -> Bool {
        var payload: [String: AnyJSON] = [
            "recruiter_id": .string(currentUID),
            "name": .string(name),
            "region": .string(region)
        ]
        if let cities, !cities.isEmpty { payload["cities"] = .string(cities) }
        if let notes, !notes.isEmpty { payload["notes"] = .string(notes) }
        var geoPayload = payload
        if let latitude, let longitude {
            geoPayload["latitude"] = .double(latitude)
            geoPayload["longitude"] = .double(longitude)
        }
        do {
            try await client
                .from("whisper_recruiter_territories")
                .insert(geoPayload)
                .execute()
            await refreshTerritories()
            return true
        } catch {
            // Geo columns may not exist yet (pre-migration project) — retry
            // without them so claiming still works; the pin falls back to
            // the geocoded/regional anchor until the migration runs.
            if latitude != nil {
                do {
                    try await client
                        .from("whisper_recruiter_territories")
                        .insert(payload)
                        .execute()
                    await refreshTerritories()
                    return true
                } catch {
                    lastError = "Couldn't claim territory — run the territories migration first."
                    return false
                }
            }
            lastError = "Couldn't claim territory — run the territories migration first."
            return false
        }
    }

    func releaseTerritory(_ territory: TerritoryRow) async {
        do {
            try await client
                .from("whisper_recruiter_territories")
                .delete()
                .eq("id", value: territory.id)
                .execute()
            territories.removeAll { $0.id == territory.id }
        } catch {
            lastError = "Couldn't release territory: \(error.localizedDescription)"
        }
    }

    // MARK: - Reviews

    nonisolated struct ReviewRow: Codable, Sendable, Identifiable, Hashable {
        let reviewer_id: String
        let rating: Int
        let review: String?
        let created_at: String?
        nonisolated var id: String { reviewer_id }
    }

    nonisolated struct ReviewSummary: Codable, Sendable {
        let reviews: [ReviewRow]
        let reviewCount: Int
        let averageRating: Double?
        let positiveCount: Int
        let negativeCount: Int
    }

    var myReviews: ReviewSummary?

    /// Fetches the signed-in recruiter's own reviews + aggregate rating
    /// from the backend `/recruiter/reviews` endpoint. Mirrors the web
    /// `fetchRecruiterReviews`.
    func refreshMyReviews() async {
        guard isRemote else { return }
        guard let url = URL(string: "\(WhisperBillingBackend.url)/recruiter/reviews?recruiterId=\(currentUID)") else { return }
        do {
            let token = try await client.auth.session.accessToken
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                myReviews = nil
                return
            }
            myReviews = try JSONDecoder().decode(ReviewSummary.self, from: data)
        } catch {
            myReviews = nil
        }
    }

    /// Prospects whose location matches a territory name or one of its cities.
    nonisolated static func prospectCount(for territory: TerritoryRow, prospects: [ProspectRow]) -> Int {
        var needles = [territory.name.lowercased()]
        for city in (territory.cities ?? "").split(separator: ",") {
            let t = city.trimmingCharacters(in: .whitespaces).lowercased()
            if !t.isEmpty { needles.append(t) }
        }
        return prospects.filter { p in
            let loc = (p.location ?? "").lowercased()
            guard !loc.isEmpty else { return false }
            return needles.contains { loc.contains($0) || $0.contains(loc) }
        }.count
    }
}
