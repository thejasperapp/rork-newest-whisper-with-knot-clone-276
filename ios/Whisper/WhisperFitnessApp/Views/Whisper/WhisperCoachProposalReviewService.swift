import Foundation
import SwiftUI
import Supabase

/// Client-side handler for `jasper://coach-proposal/<id>` deep links. The
/// coach inserts a `whisper_coach_proposals` row from Whisper and links the
/// recipient here. Whisper fetches the row, shows a diff, and on accept
/// applies the patch to its own tables + flips the row to `accepted`.
@MainActor
@Observable
final class WhisperCoachProposalReviewService {
    static let shared = WhisperCoachProposalReviewService()

    /// Sheet binding — set this to surface the review UI on top of
    /// WhisperRootView (and any presented child covers).
    var presentedProposalID: String?

    private let client = SupabaseService.shared.client
    private init() {}

    /// Called from `.onOpenURL`. Parses both `jasper://coach-proposal/<id>`
    /// and `jasper://coach-proposal?id=<id>` shapes.
    func handle(url: URL) -> Bool {
        guard url.scheme?.lowercased() == "jasper",
              url.host?.lowercased() == "coach-proposal" else { return false }

        let pathID = url.pathComponents.dropFirst().first
        let queryID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "id" })?
            .value
        guard let id = (pathID?.isEmpty == false ? pathID : queryID), !id.isEmpty else {
            return false
        }
        presentedProposalID = id
        return true
    }

    /// Fetches a single proposal row. Returns nil if RLS hides it or the
    /// id is unknown.
    func fetch(id: String) async -> WhisperCoachProposalRow? {
        do {
            let rows: [WhisperCoachProposalRow] = try await client
                .from("whisper_coach_proposals")
                .select()
                .eq("id", value: id)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            print("[Whisper] proposal fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Apply (or just record) the client's response. For `macros` we patch
    /// the local diet plan + best-effort update Supabase `jasper_diet_plans`.
    /// Other kinds currently only flip status — Whisper-side fan-out for
    /// workouts/swaps can layer on later.
    @discardableResult
    func respond(to row: WhisperCoachProposalRow, status: String) async -> Bool {
        // Apply patch locally on accept.
        if status == "accepted", row.kind == "macros" {
            applyMacrosLocally(patch: row.patch ?? [:])
            await applyMacrosToSupabase(row: row)
        }

        // Mirror to the receipts ledger so coaches can see status even for
        // v2 (embed-only) proposals. Idempotent upsert — safe for v1 too.
        await WhisperProposalReceiptService.shared.record(
            proposalID: row.id, status: status
        )

        // Write status back. RLS only lets the client_user_id update; the
        // coach previewing their own row will get a benign permission error
        // here, which we surface as a hint.
        struct Update: Encodable { let status: String; let responded_at: String }
        let iso = ISO8601DateFormatter().string(from: Date())
        do {
            try await client
                .from("whisper_coach_proposals")
                .update(Update(status: status, responded_at: iso))
                .eq("id", value: row.id)
                .execute()
            return true
        } catch {
            print("[Whisper] proposal status update failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Replace the latest saved `WeeklyDietPlan`'s macro targets so the
    /// home dashboard and nutrition view immediately reflect the new
    /// numbers. Uses `DietPlanService` so persistence + version-history
    /// snapshotting still runs.
    private func applyMacrosLocally(patch: [String: JSONValue]) {
        let cal = patch["calories"]?.doubleValue.map { Int($0) }
        let protein = patch["protein_g"]?.doubleValue
        let carbs   = patch["carbs_g"]?.doubleValue
        let fat     = patch["fat_g"]?.doubleValue

        let service = DietPlanService()
        guard let latest = service.savedPlans.first else {
            // No saved plan yet — stash the targets as a lightweight
            // override so the dashboard still picks them up.
            CoachMacroOverride.save(calories: cal, protein: protein, carbs: carbs, fat: fat)
            return
        }
        let patched = latest.withMacroOverrides(
            calories: cal, protein: protein, carbs: carbs, fat: fat
        )
        service.savePlan(patched, changeNote: "Coach update")
        CoachMacroOverride.save(calories: cal, protein: protein, carbs: carbs, fat: fat)
    }

    private func applyMacrosToSupabase(row: WhisperCoachProposalRow) async {
        guard let targetID = row.target_id else { return }
        struct PlanUpdate: Encodable {
            let target_calories: Int?
            let target_protein_g: Double?
            let target_carbs_g: Double?
            let target_fat_g: Double?
        }
        let patch = row.patch ?? [:]
        let update = PlanUpdate(
            target_calories: patch["calories"]?.doubleValue.map { Int($0) },
            target_protein_g: patch["protein_g"]?.doubleValue,
            target_carbs_g: patch["carbs_g"]?.doubleValue,
            target_fat_g: patch["fat_g"]?.doubleValue
        )
        do {
            try await client
                .from("jasper_diet_plans")
                .update(update)
                .eq("id", value: targetID)
                .execute()
        } catch {
            print("[Whisper] jasper_diet_plans update failed: \(error.localizedDescription)")
        }
    }
}

/// Lightweight per-user store for coach-applied macro overrides so they
/// stick even when the user has no saved `WeeklyDietPlan` yet. Read by
/// the home/nutrition surfaces that already key on AccountStorage.
enum CoachMacroOverride {
    private static let key = "jasper_coach_macro_override_v1"

    static func save(calories: Int?, protein: Double?, carbs: Double?, fat: Double?) {
        var dict: [String: Double] = [:]
        if let v = calories { dict["calories"] = Double(v) }
        if let v = protein  { dict["protein_g"] = v }
        if let v = carbs    { dict["carbs_g"]   = v }
        if let v = fat      { dict["fat_g"]     = v }
        guard !dict.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        AccountStorage.set(data, forKey: key)
    }
}

extension WeeklyDietPlan {
    /// Returns a copy with macro targets overridden where non-nil. Used
    /// by the coach-proposal review flow so accepting a macros suggestion
    /// updates the user's active plan without losing meals.
    func withMacroOverrides(
        calories: Int? = nil,
        protein: Double? = nil,
        carbs: Double? = nil,
        fat: Double? = nil
    ) -> WeeklyDietPlan {
        // The synthesized memberwise init is suppressed by the custom one
        // in DietPlanModels.swift, so we round-trip through JSON to
        // preserve id + createdAt while overriding the macro fields.
        guard var dict = (try? JSONEncoder().encode(self))
            .flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) else {
            return self
        }
        if let v = calories { dict["targetCalories"] = v }
        if let v = protein  { dict["targetProtein"]  = v }
        if let v = carbs    { dict["targetCarbs"]    = v }
        if let v = fat      { dict["targetFat"]      = v }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let decoded = try? JSONDecoder().decode(WeeklyDietPlan.self, from: data) else {
            return self
        }
        return decoded
    }
}
