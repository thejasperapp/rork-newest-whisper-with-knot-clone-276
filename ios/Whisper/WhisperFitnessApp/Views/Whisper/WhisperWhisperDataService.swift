import Foundation
import Supabase

// MARK: - Row models (matches Whisper's jasper_* schema)
//
// Coaches need broader read access than the legacy `whisper_client_snapshots`
// blob — they want the same picture the client sees: workouts, sets, PRs,
// diet plan, streaks, sleep, steps, body metrics. Whisper now mirrors all of
// that to per-domain `jasper_*` tables, so we just have to read them.
//
// RLS NOTE — these tables today are owned by the client (`auth.uid() = user_id`).
// For each one below, the project owner needs a policy like:
//
//   create policy "jasper_X coach read"
//     on public.jasper_<table>
//     for select using (
//       exists (
//         select 1 from public.whisper_coach_requests r
//         where r.client_user_id = jasper_<table>.user_id
//           and r.coach_user_id = auth.uid()
//           and r.status = 'active'
//       )
//     );
//
// Until those policies exist this service silently returns empty arrays and
// the coach view falls back to the snapshot blob. No crash, no exception.

/// Named "Jasper" to avoid colliding with the legacy `WhisperWorkoutRow`
/// (whisper_workouts) model in `WhisperBackendService` — this one mirrors
/// the sister app's `jasper_workouts` schema.
nonisolated struct WhisperJasperWorkoutRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let user_id: String
    let started_at: String?
    let ended_at: String?
    let duration_seconds: Int?
    let total_volume_kg: Double?
    let total_sets: Int?
    let notes: String?
    let program_id: String?
}

nonisolated struct WhisperWorkoutSetRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let user_id: String
    let workout_id: String?
    let exercise_name: String?
    let set_index: Int?
    let reps: Int?
    let weight_kg: Double?
    let rpe: Double?
    let is_warmup: Bool?
    let completed_at: String?
}

nonisolated struct WhisperPersonalRecordRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let user_id: String
    let exercise_name: String
    let metric: String
    let value: Double
    let unit: String?
    let achieved_at: String?
}

nonisolated struct WhisperDietPlanRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let user_id: String
    let name: String?
    let dietary_preference: String?
    let goal: String?
    let target_calories: Int?
    let target_protein_g: Double?
    let target_carbs_g: Double?
    let target_fat_g: Double?
    let meals_per_day: Int?
    let is_active: Bool?
    let recorded_on: String?
}

/// Mirrors the shared `public.jasper_nutrition_meals` schema that the
/// Whisper RN app and Whisper both write to. Column names are exact —
/// `calories` / `protein_g` / `carbs_g` / `fat_g` / `eaten_at` — and
/// `source` / `restaurant_*` let Whisper badge rows and dedupe restaurant
/// round-trips.
nonisolated struct WhisperNutritionMealRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let user_id: String
    let name: String?
    let calories: Int?
    /// Legacy Whisper RN column. Always written alongside `calories` by the
    /// iOS/RN apps, but older rows in production may only have this one
    /// populated. Used as a fallback so coach totals never silently drop a
    /// meal whose new-contract `calories` column happens to be null.
    let calories_kcal: Double?
    let protein_g: Double?
    let carbs_g: Double?
    let fat_g: Double?
    let eaten_at: String?
    let source: String?
    let meal_type: String?
    let restaurant_name: String?
    let restaurant_place_id: String?
}

nonisolated struct WhisperBodyMetricRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let user_id: String
    let weight_kg: Double?
    let body_fat_pct: Double?
    let recorded_at: String?
}

nonisolated struct WhisperSleepRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let user_id: String
    let started_at: String?
    let ended_at: String?
    let duration_seconds: Int?
    let rem_seconds: Int?
    let deep_seconds: Int?
    let core_seconds: Int?
    let awake_seconds: Int?
    let quality_score: Double?
}

nonisolated struct WhisperStepsDailyRow: Codable, Sendable, Hashable {
    let user_id: String
    let recorded_on: String
    let steps: Int?
    let distance_m: Double?
}

nonisolated struct WhisperHeartRateDailyRow: Codable, Sendable, Hashable {
    let user_id: String
    let recorded_on: String
    let resting_bpm: Double?
    let avg_bpm: Double?
    let max_bpm: Double?
    let min_bpm: Double?
    let hrv_ms: Double?
}

nonisolated struct WhisperActiveEnergyDailyRow: Codable, Sendable, Hashable {
    let user_id: String
    let recorded_on: String
    let active_energy_kcal: Double?
    let basal_energy_kcal: Double?
    let exercise_minutes: Int?
    let stand_hours: Int?
}

nonisolated struct WhisperStreakRow: Codable, Sendable, Hashable {
    let user_id: String
    let habit_key: String
    let current_streak: Int?
    let longest_streak: Int?
    let last_check_in: String?
}

nonisolated struct WhisperAchievementRow: Codable, Sendable, Hashable {
    let user_id: String
    let key: String
    let title: String?
    let category: String?
    let unlocked_at: String?
}

nonisolated struct WhisperGoalRow: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let user_id: String
    let kind: String?
    let target_value: Double?
    let unit: String?
    let deadline: String?
    let progress: Double?
}

nonisolated struct WhisperReadinessRow: Codable, Sendable, Hashable {
    let user_id: String
    let score: Double?
    let recorded_at: String?
}

nonisolated struct WhisperWaterIntakeRow: Codable, Sendable, Hashable {
    let user_id: String
    let ml: Double?
    let logged_at: String?
}

nonisolated struct WhisperProgressPhotoRow: Codable, Sendable, Hashable {
    let user_id: String
    let storage_path: String?
    let pose: String?
    let note: String?
    let weight_kg: Double?
    let recorded_on: String?
    let visibility: String?
}

/// Mirrors `public.jasper_preferences`. The canonical nutrition target
/// (calories + macros) lives inside `payload_json.nutrition_goals` per the
/// Whisper data contract — it's upserted every time the client retakes the
/// macro survey, edits goals, or saves a diet plan. Coaches should read
/// from here FIRST and only fall back to `jasper_diet_plans` if this row
/// is missing.
/// `payload_json` is a jsonb column, but some older Whisper clients store it
/// as a JSON-encoded string (text inside the jsonb). Per the Whisper contract
/// the coach dashboard must JSON.parse it if it comes back as text — this
/// decoder accepts either shape so we always end up with a real
/// `WhisperPreferencesPayload`.
nonisolated struct WhisperPreferencesRow: Sendable, Hashable {
    let user_id: String
    let weight_unit: String?
    let distance_unit: String?
    let payload_json: WhisperPreferencesPayload?
    /// Server-side updated_at on the row. Whisper repushes this on every macro
    /// survey save, direct goal edit, diet plan save, app foreground, and
    /// auth change — so this timestamp is also the freshness of the goals.
    let updated_at: String?
}

extension WhisperPreferencesRow: Codable {
    enum CodingKeys: String, CodingKey {
        case user_id, weight_unit, distance_unit, payload_json, updated_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.user_id = try c.decode(String.self, forKey: .user_id)
        self.weight_unit = try c.decodeIfPresent(String.self, forKey: .weight_unit)
        self.distance_unit = try c.decodeIfPresent(String.self, forKey: .distance_unit)
        self.updated_at = try c.decodeIfPresent(String.self, forKey: .updated_at)

        // Try object decode first (jsonb returning as object — the common case).
        if let obj = try? c.decodeIfPresent(WhisperPreferencesPayload.self, forKey: .payload_json) {
            self.payload_json = obj
            return
        }
        // Some Whisper builds store payload_json as a JSON-encoded string
        // inside the jsonb column. Decode the string then parse it.
        if let s = try? c.decodeIfPresent(String.self, forKey: .payload_json),
           let data = s.data(using: .utf8),
           let parsed = try? JSONDecoder().decode(WhisperPreferencesPayload.self, from: data) {
            self.payload_json = parsed
            return
        }
        self.payload_json = nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(user_id, forKey: .user_id)
        try c.encodeIfPresent(weight_unit, forKey: .weight_unit)
        try c.encodeIfPresent(distance_unit, forKey: .distance_unit)
        try c.encodeIfPresent(payload_json, forKey: .payload_json)
        try c.encodeIfPresent(updated_at, forKey: .updated_at)
    }
}

nonisolated struct WhisperPreferencesPayload: Codable, Sendable, Hashable {
    let nutrition_goals: WhisperNutritionGoals?
    let macro_survey: WhisperMacroSurvey?
}

/// Tolerant decoder for the canonical nutrition target blob inside
/// `jasper_preferences.payload_json.nutrition_goals`.
///
/// In practice different Whisper builds have written this with slightly
/// different keys — the contract calls for `protein_g/carbs_g/fat_g`, but
/// the iOS Whisper `NutritionGoals` model uses bare `protein/carbs/fat`,
/// and some older rows used `target_*` keys. We accept any of those so
/// the coach card lights up regardless of which client build the macros
/// were saved from.
nonisolated struct WhisperNutritionGoals: Sendable, Hashable {
    let calories: Double?
    let protein_g: Double?
    let carbs_g: Double?
    let fat_g: Double?
}

extension WhisperNutritionGoals: Codable {
    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        func num(_ keys: [String]) -> Double? {
            for k in keys {
                guard let key = DynamicKey(stringValue: k) else { continue }
                if let d = try? c.decodeIfPresent(Double.self, forKey: key), d > 0 { return d }
                if let i = try? c.decodeIfPresent(Int.self,    forKey: key), i > 0 { return Double(i) }
                if let s = try? c.decodeIfPresent(String.self, forKey: key),
                   let d = Double(s), d > 0 { return d }
            }
            return nil
        }
        self.calories = num(["calories", "calorie", "target_calories", "targetCalories", "kcal"])
        self.protein_g = num(["protein_g", "protein", "target_protein_g", "target_protein", "targetProtein", "proteinGrams"])
        self.carbs_g   = num(["carbs_g",   "carbs",   "target_carbs_g",   "target_carbs",   "targetCarbs",   "carbsGrams",   "carbohydrates", "carbohydrates_g"])
        self.fat_g     = num(["fat_g",     "fat",     "target_fat_g",     "target_fat",     "targetFat",     "fatGrams"])
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: DynamicKey.self)
        if let v = calories,  let k = DynamicKey(stringValue: "calories")  { try c.encode(v, forKey: k) }
        if let v = protein_g, let k = DynamicKey(stringValue: "protein_g") { try c.encode(v, forKey: k) }
        if let v = carbs_g,   let k = DynamicKey(stringValue: "carbs_g")   { try c.encode(v, forKey: k) }
        if let v = fat_g,     let k = DynamicKey(stringValue: "fat_g")     { try c.encode(v, forKey: k) }
    }
}

/// Raw inputs the client gave the macro survey — useful for coaches who
/// want to understand HOW the targets were calculated (goal, activity
/// level, body weight).
nonisolated struct WhisperMacroSurvey: Sendable, Hashable {
    let targetCalories: Double?
    let targetProtein: Double?
    let targetCarbs: Double?
    let targetFat: Double?
    let goal: String?
    let activityLevel: String?
    let weightLb: Double?
}

extension WhisperMacroSurvey: Codable {
    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        func num(_ keys: [String]) -> Double? {
            for k in keys {
                guard let key = DynamicKey(stringValue: k) else { continue }
                if let d = try? c.decodeIfPresent(Double.self, forKey: key), d > 0 { return d }
                if let i = try? c.decodeIfPresent(Int.self,    forKey: key), i > 0 { return Double(i) }
                if let s = try? c.decodeIfPresent(String.self, forKey: key),
                   let d = Double(s), d > 0 { return d }
            }
            return nil
        }
        func str(_ keys: [String]) -> String? {
            for k in keys {
                guard let key = DynamicKey(stringValue: k) else { continue }
                if let s = try? c.decodeIfPresent(String.self, forKey: key), !s.isEmpty { return s }
            }
            return nil
        }
        self.targetCalories = num(["targetCalories", "target_calories", "calories", "kcal"])
        self.targetProtein  = num(["targetProtein",  "target_protein",  "target_protein_g",  "protein_g",  "protein"])
        self.targetCarbs    = num(["targetCarbs",    "target_carbs",    "target_carbs_g",    "carbs_g",    "carbs", "carbohydrates"])
        self.targetFat      = num(["targetFat",      "target_fat",      "target_fat_g",      "fat_g",      "fat"])
        self.goal           = str(["goal", "objective"])
        self.activityLevel  = str(["activityLevel", "activity_level", "activity"])
        self.weightLb       = num(["weightLb", "weight_lb", "weightLbs", "weight_lbs"])
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: DynamicKey.self)
        if let v = targetCalories, let k = DynamicKey(stringValue: "targetCalories") { try c.encode(v, forKey: k) }
        if let v = targetProtein,  let k = DynamicKey(stringValue: "targetProtein")  { try c.encode(v, forKey: k) }
        if let v = targetCarbs,    let k = DynamicKey(stringValue: "targetCarbs")    { try c.encode(v, forKey: k) }
        if let v = targetFat,      let k = DynamicKey(stringValue: "targetFat")      { try c.encode(v, forKey: k) }
        if let v = goal,           let k = DynamicKey(stringValue: "goal")           { try c.encode(v, forKey: k) }
        if let v = activityLevel,  let k = DynamicKey(stringValue: "activityLevel")  { try c.encode(v, forKey: k) }
        if let v = weightLb,       let k = DynamicKey(stringValue: "weightLb")       { try c.encode(v, forKey: k) }
    }
}

/// Aggregated read of every `jasper_*` table for one coached client. Each
/// field is independent — a single failing query never breaks the others.
nonisolated struct WhisperWhisperClientData: Sendable {
    var workouts: [WhisperJasperWorkoutRow] = []
    var sets: [WhisperWorkoutSetRow] = []
    var personalRecords: [WhisperPersonalRecordRow] = []
    var activeDietPlan: WhisperDietPlanRow?
    var recentMeals: [WhisperNutritionMealRow] = []
    var bodyMetrics: [WhisperBodyMetricRow] = []
    var sleep: [WhisperSleepRow] = []
    var stepsDaily: [WhisperStepsDailyRow] = []
    var heartRateDaily: [WhisperHeartRateDailyRow] = []
    var activeEnergyDaily: [WhisperActiveEnergyDailyRow] = []
    var streaks: [WhisperStreakRow] = []
    var achievements: [WhisperAchievementRow] = []
    var goals: [WhisperGoalRow] = []
    var latestReadiness: WhisperReadinessRow?
    var waterIntake: [WhisperWaterIntakeRow] = []
    var progressPhotos: [WhisperProgressPhotoRow] = []
    var preferences: WhisperPreferencesRow?
    /// Fallback nutrition goals decoded from the legacy `user_data` blob
    /// (`data_key = "jasper_nutrition_goals"`). iOS Whisper clients push their
    /// `NutritionGoals` struct here — they don't touch `jasper_preferences`.
    var userDataNutritionGoals: WhisperNutritionGoals?
    var fetchedAt: Date = Date()

    /// True when every domain came back empty — usually means RLS policies
    /// for coach reads haven't been applied yet.
    var isCompletelyEmpty: Bool {
        workouts.isEmpty && sets.isEmpty && personalRecords.isEmpty
            && activeDietPlan == nil && recentMeals.isEmpty && bodyMetrics.isEmpty
            && sleep.isEmpty && stepsDaily.isEmpty && heartRateDaily.isEmpty
            && activeEnergyDaily.isEmpty && streaks.isEmpty && achievements.isEmpty
            && goals.isEmpty && latestReadiness == nil && waterIntake.isEmpty
            && progressPhotos.isEmpty && preferences == nil
    }
}

/// Coach-side read service for the `jasper_*` schema. All fetches run in
/// parallel and tolerate empty/missing tables (so onboarding new clients
/// works even before they've synced everything).
@MainActor
@Observable
final class WhisperWhisperDataService {
    static let shared = WhisperWhisperDataService()

    private let client = SupabaseService.shared.client

    var isLoading: Bool = false
    var lastError: String?
    /// Most recent reason `jasper_preferences` failed to surface goals.
    /// Surfaced in the coach UI so RLS / payload / fetch issues are
    /// distinguishable from each other instead of all collapsing into a
    /// generic "snapshot fallback".
    var lastPreferencesDiagnostic: PreferencesDiagnostic = .unknown

    enum PreferencesDiagnostic: Equatable, Sendable {
        case unknown
        case ok
        case noRowVisible
        case rowFoundEmpty
        case fetchError(String)
    }

    private init() {}

    func fetchAll(forClient userID: String) async -> WhisperWhisperClientData {
        isLoading = true
        defer { isLoading = false }

        async let workouts          = fetchList(table: "jasper_workouts",            userID: userID, orderColumn: "started_at",  ascending: false, limit: 50) as [WhisperJasperWorkoutRow]
        async let sets              = fetchList(table: "jasper_workout_sets",        userID: userID, orderColumn: "completed_at", ascending: false, limit: 200) as [WhisperWorkoutSetRow]
        async let prs               = fetchList(table: "jasper_personal_records",    userID: userID, orderColumn: "achieved_at",  ascending: false, limit: 25)  as [WhisperPersonalRecordRow]
        async let activePlan        = fetchActiveDietPlan(userID: userID)
        async let meals             = fetchRecentMeals(userID: userID)
        async let body              = fetchList(table: "jasper_body_metrics",        userID: userID, orderColumn: "recorded_at",  ascending: false, limit: 60)  as [WhisperBodyMetricRow]
        async let sleep             = fetchList(table: "jasper_sleep_sessions",      userID: userID, orderColumn: "started_at",   ascending: false, limit: 30)  as [WhisperSleepRow]
        async let steps             = fetchList(table: "jasper_steps_daily",         userID: userID, orderColumn: "recorded_on",  ascending: false, limit: 30)  as [WhisperStepsDailyRow]
        async let heart             = fetchList(table: "jasper_heart_rate_daily",    userID: userID, orderColumn: "recorded_on",  ascending: false, limit: 30)  as [WhisperHeartRateDailyRow]
        async let energy            = fetchList(table: "jasper_active_energy_daily", userID: userID, orderColumn: "recorded_on",  ascending: false, limit: 30)  as [WhisperActiveEnergyDailyRow]
        async let streaks           = fetchList(table: "jasper_streaks",             userID: userID, orderColumn: nil,            ascending: false, limit: 20)  as [WhisperStreakRow]
        async let achievements      = fetchList(table: "jasper_achievements",        userID: userID, orderColumn: "unlocked_at",  ascending: false, limit: 30)  as [WhisperAchievementRow]
        async let goals             = fetchList(table: "jasper_goals",               userID: userID, orderColumn: "deadline",     ascending: true,  limit: 20)  as [WhisperGoalRow]
        async let readiness         = fetchLatestReadiness(userID: userID)
        async let water             = fetchList(table: "jasper_water_intake",        userID: userID, orderColumn: "logged_at",    ascending: false, limit: 30)  as [WhisperWaterIntakeRow]
        async let photos            = fetchList(table: "jasper_progress_photos",     userID: userID, orderColumn: "recorded_on",  ascending: false, limit: 20)  as [WhisperProgressPhotoRow]
        async let prefs             = fetchPreferences(userID: userID)
        async let userDataGoals     = fetchUserDataNutritionGoals(userID: userID)

        var data = WhisperWhisperClientData()
        data.workouts = await workouts
        data.sets = await sets
        data.personalRecords = await prs
        data.activeDietPlan = await activePlan
        data.recentMeals = await meals
        data.bodyMetrics = await body
        data.sleep = await sleep
        data.stepsDaily = await steps
        data.heartRateDaily = await heart
        data.activeEnergyDaily = await energy
        data.streaks = await streaks
        data.achievements = await achievements
        data.goals = await goals
        data.latestReadiness = await readiness
        data.waterIntake = await water
        data.progressPhotos = await photos
        data.preferences = await prefs
        data.userDataNutritionGoals = await userDataGoals
        data.fetchedAt = Date()

        if data.isCompletelyEmpty {
            lastError = "No Whisper data visible. Coach-read RLS policies on jasper_* tables may not be applied yet."
        } else {
            lastError = nil
        }
        return data
    }

    // MARK: - Generic list fetch

    private func fetchList<Row: Decodable & Sendable>(
        table: String,
        userID: String,
        orderColumn: String?,
        ascending: Bool,
        limit: Int
    ) async -> [Row] {
        do {
            var query = client.from(table).select().eq("user_id", value: userID)
            if let orderColumn {
                let ordered = query.order(orderColumn, ascending: ascending, nullsFirst: false)
                let rows: [Row] = try await ordered.limit(limit).execute().value
                return rows
            }
            let rows: [Row] = try await query.limit(limit).execute().value
            return rows
        } catch {
            // Silently swallow — likely RLS or missing table.
            print("[Whisper] jasper read \(table) error: \(error.localizedDescription)")
            return []
        }
    }

    /// Coach reads meals filtered to the last 48 hours server-side, so the
    /// timezone offset between coach and client can never strand today's rows
    /// outside the slice. Limit is generous (200) for heavy loggers.
    private func fetchRecentMeals(userID: String) async -> [WhisperNutritionMealRow] {
        do {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let cutoff = iso.string(from: Date().addingTimeInterval(-48 * 60 * 60))
            let rows: [WhisperNutritionMealRow] = try await client
                .from("jasper_nutrition_meals")
                .select()
                .eq("user_id", value: userID)
                .gte("eaten_at", value: cutoff)
                .order("eaten_at", ascending: false, nullsFirst: false)
                .limit(200)
                .execute()
                .value
            return rows
        } catch {
            print("[Whisper] jasper read jasper_nutrition_meals error: \(error.localizedDescription)")
            return []
        }
    }

    private func fetchActiveDietPlan(userID: String) async -> WhisperDietPlanRow? {
        do {
            // Prefer most-recently-updated active plan in case the client has
            // historical rows still flagged is_active=true.
            let rows: [WhisperDietPlanRow] = try await client
                .from("jasper_diet_plans")
                .select()
                .eq("user_id", value: userID)
                .eq("is_active", value: true)
                .order("recorded_on", ascending: false, nullsFirst: false)
                .limit(5)
                .execute()
                .value
            return rows.first
        } catch {
            print("[Whisper] active diet plan error: \(error.localizedDescription)")
            return nil
        }
    }

    /// Newest readiness score for a user — also used by the Auto personality
    /// to pick today's ghost, so it stays internal.
    func fetchLatestReadiness(userID: String) async -> WhisperReadinessRow? {
        do {
            let rows: [WhisperReadinessRow] = try await client
                .from("jasper_readiness_scores")
                .select()
                .eq("user_id", value: userID)
                .order("recorded_at", ascending: false, nullsFirst: false)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            print("[Whisper] readiness error: \(error.localizedDescription)")
            return nil
        }
    }

    /// iOS Whisper stores the user's `NutritionGoals` as a base64 blob under
    /// `user_data.data_key = "jasper_nutrition_goals"`. The local model uses
    /// bare keys (`calories` / `protein` / `carbs` / `fat`) which the
    /// tolerant `WhisperNutritionGoals` decoder accepts. RLS: coach must have
    /// read access on `user_data` for the followed client.
    private func fetchUserDataNutritionGoals(userID: String) async -> WhisperNutritionGoals? {
        nonisolated struct Row: Decodable { let data_blob: String? }
        do {
            let rows: [Row] = try await client
                .from("user_data")
                .select("data_blob")
                .eq("user_id", value: userID)
                .eq("data_key", value: "jasper_nutrition_goals")
                .limit(1)
                .execute()
                .value
            guard let b64 = rows.first?.data_blob,
                  let data = Data(base64Encoded: b64),
                  !data.isEmpty else { return nil }
            return try? JSONDecoder().decode(WhisperNutritionGoals.self, from: data)
        } catch {
            print("[Whisper] user_data nutrition goals error: \(error.localizedDescription)")
            return nil
        }
    }

    /// Reads the canonical macro target row. Per Whisper's data contract this
    /// is the single source of truth for the client's current calories +
    /// macros and is upserted on every survey/goal/plan save and every app
    /// foreground. Logs the resolved goal values so a stale dashboard can be
    /// traced to either an RLS gap, a missing payload, or a decode mismatch.
    ///
    /// Uses `select("*")` and drops the `.order()` clause — some Supabase
    /// projects throw on ordering by a column the requester can't see, and
    /// there's only ever one row per user anyway.
    private func fetchPreferences(userID: String) async -> WhisperPreferencesRow? {
        // Pull the raw row and parse manually. Codable on `payload_json` has
        // burned us repeatedly because Whisper builds in the wild write the
        // jsonb cell as: (a) an object, (b) a JSON-encoded string, (c) with
        // varying inner key spellings (`protein_g` vs `protein` vs
        // `target_protein_g` vs `targetProtein`). Manual dig sidesteps every
        // one of those.
        do {
            let resp = try await client
                .from("jasper_preferences")
                .select("*")
                .eq("user_id", value: userID)
                .limit(1)
                .execute()
            let raw = resp.data
            guard let arr = (try? JSONSerialization.jsonObject(with: raw)) as? [[String: Any]],
                  let dict = arr.first else {
                print("[Whisper] jasper_preferences: no row visible for client=\(userID.prefix(8)) — RLS likely blocks coach reads on jasper_preferences. raw=\(String(data: raw, encoding: .utf8)?.prefix(400) ?? "")")
                lastPreferencesDiagnostic = .noRowVisible
                return nil
            }
            let weightUnit = dict["weight_unit"] as? String
            let distanceUnit = dict["distance_unit"] as? String
            let updatedAt = dict["updated_at"] as? String

            // payload_json may be a dict, a JSON-encoded string, or null.
            // Some Whisper builds also nest goals under unexpected keys
            // (`preferences`, `data`, doubly-stringified, etc.), so after
            // checking the canonical paths we fall back to a recursive scan
            // of the entire row for any object shaped like nutrition goals
            // or a macro survey.
            let payload = Self.normalizePayloadJSON(dict["payload_json"])
            let canonicalGoals = Self.extractNutritionGoals(from: payload?["nutrition_goals"])
            let rootGoals = Self.extractNutritionGoals(from: payload)
            let deepGoals = Self.deepFindNutritionGoals(in: dict)
            let goals = [canonicalGoals, rootGoals, deepGoals]
                .compactMap { $0 }
                .first(where: { ($0.calories ?? 0) > 0 })
                ?? canonicalGoals ?? rootGoals ?? deepGoals

            let canonicalSurvey = Self.extractMacroSurvey(from: payload?["macro_survey"])
            let deepSurvey = Self.deepFindMacroSurvey(in: dict)
            let survey = [canonicalSurvey, deepSurvey]
                .compactMap { $0 }
                .first(where: { ($0.targetCalories ?? 0) > 0 })
                ?? canonicalSurvey ?? deepSurvey

            let effectiveGoals = goals
            let parsedPayload = WhisperPreferencesPayload(
                nutrition_goals: effectiveGoals,
                macro_survey: survey
            )
            let row = WhisperPreferencesRow(
                user_id: (dict["user_id"] as? String) ?? userID,
                weight_unit: weightUnit,
                distance_unit: distanceUnit,
                payload_json: (effectiveGoals != nil || survey != nil) ? parsedPayload : nil,
                updated_at: updatedAt
            )

            print("[Whisper] jasper_preferences ok client=\(userID.prefix(8)) updated=\(updatedAt ?? "?") goals=\(effectiveGoals?.calories ?? 0)/\(effectiveGoals?.protein_g ?? 0)/\(effectiveGoals?.carbs_g ?? 0)/\(effectiveGoals?.fat_g ?? 0) survey=\(survey?.targetCalories ?? 0)")
            if (effectiveGoals?.calories ?? 0) <= 0 && (survey?.targetCalories ?? 0) <= 0 {
                let s = String(data: raw, encoding: .utf8) ?? ""
                print("[Whisper] jasper_preferences raw (row found, no goals decoded): \(s.prefix(2000))")
                lastPreferencesDiagnostic = .rowFoundEmpty
            } else {
                lastPreferencesDiagnostic = .ok
            }
            return row
        } catch {
            print("[Whisper] jasper_preferences error: \(error.localizedDescription)")
            lastPreferencesDiagnostic = .fetchError(error.localizedDescription)
            return nil
        }
    }

    /// Coerces `payload_json` (which Whisper writes as either an object or a
    /// JSON-encoded string inside jsonb) into a `[String: Any]` dictionary.
    private static func normalizePayloadJSON(_ raw: Any?) -> [String: Any]? {
        if let dict = raw as? [String: Any] { return dict }
        if let s = raw as? String,
           let data = s.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return parsed
        }
        return nil
    }

    /// Reads a positive numeric value out of a jsonb sub-tree under any of
    /// the listed key spellings. Tolerates Int / Double / numeric String.
    private static func num(_ dict: [String: Any]?, _ keys: [String]) -> Double? {
        guard let dict else { return nil }
        for k in keys {
            if let d = dict[k] as? Double, d > 0 { return d }
            if let i = dict[k] as? Int, i > 0 { return Double(i) }
            if let n = dict[k] as? NSNumber {
                let v = n.doubleValue
                if v > 0 { return v }
            }
            if let s = dict[k] as? String, let v = Double(s), v > 0 { return v }
        }
        return nil
    }

    private static func extractNutritionGoals(from raw: Any?) -> WhisperNutritionGoals? {
        let dict = normalizePayloadJSON(raw)
        guard dict != nil else { return nil }
        let cal = num(dict, ["calories", "calorie", "target_calories", "targetCalories", "kcal"])
        let p   = num(dict, ["protein_g", "protein", "target_protein_g", "target_protein", "targetProtein", "proteinGrams"])
        let c   = num(dict, ["carbs_g", "carbs", "target_carbs_g", "target_carbs", "targetCarbs", "carbsGrams", "carbohydrates", "carbohydrates_g"])
        let f   = num(dict, ["fat_g", "fat", "target_fat_g", "target_fat", "targetFat", "fatGrams"])
        if cal == nil && p == nil && c == nil && f == nil { return nil }
        return WhisperNutritionGoals(calories: cal, protein_g: p, carbs_g: c, fat_g: f)
    }

    /// Recursively scans an arbitrary JSON tree for the first sub-object that
    /// looks like a nutrition-goals payload (positive calories + at least one
    /// macro field under any known spelling). Lets us survive Whisper nesting
    /// the goals under unexpected keys without another code change.
    private static func deepFindNutritionGoals(in raw: Any?) -> WhisperNutritionGoals? {
        var best: WhisperNutritionGoals?
        func visit(_ node: Any?) {
            // Strings might be JSON-encoded payloads.
            if let s = node as? String,
               let data = s.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) {
                visit(parsed)
                return
            }
            if let arr = node as? [Any] {
                for item in arr { visit(item) }
                return
            }
            guard let dict = node as? [String: Any] else { return }
            if let g = extractNutritionGoals(from: dict), (g.calories ?? 0) > 0 {
                if best == nil || (best?.calories ?? 0) <= 0 { best = g }
                return
            }
            for (_, v) in dict { visit(v) }
        }
        visit(raw)
        return best
    }

    private static func deepFindMacroSurvey(in raw: Any?) -> WhisperMacroSurvey? {
        var best: WhisperMacroSurvey?
        func visit(_ node: Any?) {
            if let s = node as? String,
               let data = s.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) {
                visit(parsed)
                return
            }
            if let arr = node as? [Any] {
                for item in arr { visit(item) }
                return
            }
            guard let dict = node as? [String: Any] else { return }
            if let s = extractMacroSurvey(from: dict), (s.targetCalories ?? 0) > 0 {
                if best == nil || (best?.targetCalories ?? 0) <= 0 { best = s }
                return
            }
            for (_, v) in dict { visit(v) }
        }
        visit(raw)
        return best
    }

    private static func extractMacroSurvey(from raw: Any?) -> WhisperMacroSurvey? {
        let dict = normalizePayloadJSON(raw)
        guard let dict else { return nil }
        let cal = num(dict, ["targetCalories", "target_calories", "calories", "kcal"])
        let p   = num(dict, ["targetProtein", "target_protein", "target_protein_g", "protein_g", "protein"])
        let c   = num(dict, ["targetCarbs", "target_carbs", "target_carbs_g", "carbs_g", "carbs", "carbohydrates"])
        let f   = num(dict, ["targetFat", "target_fat", "target_fat_g", "fat_g", "fat"])
        let goal = dict["goal"] as? String
        let activity = (dict["activityLevel"] as? String) ?? (dict["activity_level"] as? String)
        let weightLb = num(dict, ["weightLb", "weight_lb", "weightLbs", "weight_lbs"])
        if cal == nil && p == nil && c == nil && f == nil && goal == nil && activity == nil && weightLb == nil {
            return nil
        }
        return WhisperMacroSurvey(
            targetCalories: cal, targetProtein: p, targetCarbs: c, targetFat: f,
            goal: goal, activityLevel: activity, weightLb: weightLb
        )
    }

    // MARK: - Coach helpers

    /// Sets belonging to a single workout (already-fetched sets, filtered locally).
    nonisolated static func sets(for workoutID: String, in all: [WhisperWorkoutSetRow]) -> [WhisperWorkoutSetRow] {
        all.filter { $0.workout_id == workoutID }
            .sorted { ($0.set_index ?? 0) < ($1.set_index ?? 0) }
    }

    /// Returns the weight unit string the client prefers (defaults to kg).
    nonisolated static func weightUnit(_ prefs: WhisperPreferencesRow?) -> String {
        let raw = prefs?.weight_unit?.lowercased() ?? "kg"
        return raw == "lb" || raw == "lbs" ? "lb" : "kg"
    }

    /// Converts a kg value into the client's preferred display unit.
    nonisolated static func formatWeight(kg: Double?, prefs: WhisperPreferencesRow?) -> String {
        guard let kg, kg > 0 else { return "—" }
        let unit = weightUnit(prefs)
        if unit == "lb" {
            return String(format: "%.1f lb", kg * 2.20462)
        }
        return String(format: "%.1f kg", kg)
    }
}
