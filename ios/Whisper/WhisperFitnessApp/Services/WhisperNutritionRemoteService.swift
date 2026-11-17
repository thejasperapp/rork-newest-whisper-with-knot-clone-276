import Foundation
import Supabase
import SwiftUI

// MARK: - Row payloads
//
// Mirrors the per-row schema the sister Whisper React Native app writes to.
// Inserting from iOS here keeps both apps in sync — when the user logs a
// meal via Whisper (map embed, recipe card, photo-log, Jasper DM, etc.) the
// row lands in `public.jasper_nutrition_meals` so the Whisper app and Jasper
// both see the same totals.

/// Wire shape for `public.jasper_nutrition_meals`. This is the contract
/// agreed with the Whisper RN app — column names are exact (`calories`,
/// `protein_g`, `carbs_g`, `fat_g`, `eaten_at`) and `source` lets Whisper
/// badge rows that came from Whisper and dedupe restaurant round-trips.
nonisolated struct WhisperNutritionMealInsert: Codable, Sendable {
    let id: String
    let user_id: String
    /// Mirrors `id` — the live `jasper_nutrition_meals` table has a NOT NULL
    /// `client_id uuid` column that Whisper RN populates with the same UUID as
    /// the primary key. Without this, every Whisper insert fails the NOT NULL
    /// constraint and silently disappears.
    let client_id: String
    let name: String
    // --- New Whisper contract columns ---
    let calories: Int
    let protein_g: Double
    let carbs_g: Double
    let fat_g: Double
    let eaten_at: String
    let source: String
    /// Lowercase slot string per the Whisper↔Whisper contract:
    /// `breakfast` / `lunch` / `dinner` / `snack` / `drink`. When set,
    /// Whisper groups the row by this verbatim instead of inferring from hour.
    let meal_type: String?
    let restaurant_name: String?
    let restaurant_place_id: String?
    // --- Legacy Whisper RN columns still present on the live table ---
    // These are populated on every existing row in production and are very
    // likely NOT NULL (e.g. `visibility` defaults to 'private' on every row,
    // `calories_kcal`/`logged_at` are filled on every legacy write). If we
    // omit them, Postgres silently rejects the insert. We mirror the values
    // from the new columns so both schemas stay consistent.
    let calories_kcal: Double
    let logged_at: String
    let fiber_g: Double
    let visibility: String
}

/// Origin tag written to the `source` column so Whisper can badge the row
/// ("From Whisper") and skip duplicate inserts when a restaurant card
/// round-trips.
nonisolated enum WhisperMealSource: String, Sendable {
    case whisper
    case whisperRestaurant = "whisper_restaurant"
}

/// Per-row reader/writer for `public.jasper_nutrition_meals`. The Whisper
/// React Native app is the canonical writer; this service lets the iOS
/// Whisper/Jasper surfaces participate in the same source of truth so meals
/// logged from either app appear in both.
@MainActor
@Observable
final class WhisperNutritionRemoteService {
    static let shared = WhisperNutritionRemoteService()

    private let client = SupabaseService.shared.client
    private var lastPullAt: Date?
    private var channel: RealtimeChannelV2?
    private var channelTask: Task<Void, Never>?

    private init() {}

    // MARK: - Realtime

    /// Subscribes to Supabase postgres changes on `jasper_nutrition_meals`
    /// for the current user so meals logged in the sister Whisper RN app
    /// flow into the local `NutritionStore` instantly. Idempotent; safe to
    /// call on every app foreground.
    func startRealtimeSync() {
        guard isRemote, channel == nil else { return }
        let uid = userID
        let ch = client.realtimeV2.channel("jasper-nutrition-\(uid)")
        channel = ch
        let inserts = ch.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "jasper_nutrition_meals",
            filter: "user_id=eq.\(uid)"
        )
        let updates = ch.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "jasper_nutrition_meals",
            filter: "user_id=eq.\(uid)"
        )
        let deletes = ch.postgresChange(
            DeleteAction.self,
            schema: "public",
            table: "jasper_nutrition_meals",
            filter: "user_id=eq.\(uid)"
        )
        channelTask = Task { @MainActor in
            await ch.subscribe()
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in
                    for await _ in inserts { await NutritionStore.shared.refreshFromWhisper() }
                }
                group.addTask { @MainActor in
                    for await _ in updates { await NutritionStore.shared.refreshFromWhisper() }
                }
                group.addTask { @MainActor in
                    for await _ in deletes { await NutritionStore.shared.refreshFromWhisper() }
                }
            }
        }
    }

    func stopRealtimeSync() {
        channelTask?.cancel()
        channelTask = nil
        if let ch = channel {
            Task { await ch.unsubscribe() }
        }
        channel = nil
    }

    private var userID: String { AccountStorage.currentUserID }
    private var isRemote: Bool { userID != "guest" && !userID.hasPrefix("local_") }

    /// Returns the live auth UID from the active Supabase session, which is
    /// what RLS actually checks against. Falls back to `AccountStorage.currentUserID`
    /// if the session can't be fetched. Critical for meal pushes — the local
    /// `AccountStorage` UID can drift out of sync with the session UID after a
    /// password reset, magic-link, or Apple Hide-My-Email rotation, and writes
    /// keyed off the cached value silently fail RLS.
    private func resolvedUID() async -> String? {
        if let session = try? await client.auth.session {
            let live = session.user.id.uuidString.lowercased()
            if WhisperIdentityService.isValidSupabaseUID(live) {
                // Heal cache silently so subsequent local reads match.
                if AccountStorage.currentUserID.lowercased() != live {
                    AccountStorage.currentUserID = live
                }
                return live
            }
        }
        let cached = AccountStorage.currentUserID
        return WhisperIdentityService.isValidSupabaseUID(cached) ? cached.lowercased() : nil
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Writes

    /// Upserts a meal into Supabase so the Whisper app sees it. Safe to call
    /// from any path that adds a meal locally — silent no-op for guest users.
    /// Resolves the user_id from the live auth session (not the cached
    /// `AccountStorage` value) so writes always satisfy RLS.
    @discardableResult
    func pushMeal(
        _ item: FoodItem,
        source: WhisperMealSource = .whisper,
        restaurantName: String? = nil,
        restaurantPlaceID: String? = nil
    ) async -> Bool {
        guard let uid = await resolvedUID() else {
            print("[WhisperNutrition] push skipped — no valid auth UID (cached: \(AccountStorage.currentUserID))")
            return false
        }
        let eatenAtISO = Self.isoFractional.string(from: item.timestamp)
        let payload = WhisperNutritionMealInsert(
            id: item.stableId,
            user_id: uid,
            client_id: item.stableId,
            name: item.name.isEmpty ? "Meal" : item.name,
            calories: item.totalCalories,
            protein_g: item.totalProtein,
            carbs_g: item.totalCarbs,
            fat_g: item.totalFat,
            eaten_at: eatenAtISO,
            source: source.rawValue,
            meal_type: item.mealType.rawValue,
            restaurant_name: restaurantName,
            restaurant_place_id: restaurantPlaceID,
            calories_kcal: Double(item.totalCalories),
            logged_at: eatenAtISO,
            fiber_g: item.totalFiber,
            visibility: "private"
        )
        do {
            _ = try await client
                .from("jasper_nutrition_meals")
                .upsert(payload, onConflict: "id")
                .execute()
            return true
        } catch {
            let msg = String(describing: error).lowercased()
            // Whisper's `meal_type` column may not be live yet on the shared
            // table. Postgres rejects unknown columns with PGRST204 /
            // "could not find the '…' column" — in that case, drop the
            // field and retry so the meal still lands.
            let isMissingMealType = msg.contains("meal_type")
                && (msg.contains("could not find") || msg.contains("pgrst204") || msg.contains("schema cache") || msg.contains("does not exist"))
            if isMissingMealType {
                let fallback = WhisperNutritionMealInsert(
                    id: payload.id,
                    user_id: payload.user_id,
                    client_id: payload.client_id,
                    name: payload.name,
                    calories: payload.calories,
                    protein_g: payload.protein_g,
                    carbs_g: payload.carbs_g,
                    fat_g: payload.fat_g,
                    eaten_at: payload.eaten_at,
                    source: payload.source,
                    meal_type: nil,
                    restaurant_name: payload.restaurant_name,
                    restaurant_place_id: payload.restaurant_place_id,
                    calories_kcal: payload.calories_kcal,
                    logged_at: payload.logged_at,
                    fiber_g: payload.fiber_g,
                    visibility: payload.visibility
                )
                do {
                    _ = try await client
                        .from("jasper_nutrition_meals")
                        .upsert(fallback, onConflict: "id")
                        .execute()
                    print("[WhisperNutrition] pushed meal \(item.stableId) without meal_type (column not in schema yet)")
                    return true
                } catch {
                    print("[WhisperNutrition] push retry-without-meal_type failed for \(item.stableId): \(error)")
                    return false
                }
            }
            print("[WhisperNutrition] push error for meal \(item.stableId) (\(item.name)): \(error)")
            return false
        }
    }

    /// Removes a meal row by id.
    func deleteMeal(stableId: String) async {
        guard let uid = await resolvedUID() else { return }
        do {
            _ = try await client
                .from("jasper_nutrition_meals")
                .delete()
                .eq("id", value: stableId)
                .eq("user_id", value: uid)
                .execute()
        } catch {
            print("[WhisperNutrition] delete error: \(error.localizedDescription)")
        }
    }

    // MARK: - Reads

    /// Pulls today's meal rows from Supabase. Used by Jasper + NutritionStore
    /// to reconcile against the Whisper RN app's writes.
    func fetchToday() async -> [FoodItem] {
        guard let uid = await resolvedUID() else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? Date()
        do {
            let rows: [WhisperNutritionMealRow] = try await client
                .from("jasper_nutrition_meals")
                .select()
                .eq("user_id", value: uid)
                .gte("eaten_at", value: Self.isoFractional.string(from: start))
                .lt("eaten_at", value: Self.isoFractional.string(from: end))
                .order("eaten_at", ascending: false)
                .limit(100)
                .execute()
                .value
            lastPullAt = Date()
            return rows.compactMap { Self.foodItem(from: $0) }
        } catch {
            print("[WhisperNutrition] fetchToday error: \(error.localizedDescription)")
            return []
        }
    }

    /// Today's totals straight from Supabase, bypassing local cache. Used by
    /// Jasper to make sure macro answers reflect what Whisper actually has.
    func fetchTodayTotals() async -> (calories: Int, protein: Double, carbs: Double, fat: Double)? {
        let items = await fetchToday()
        guard !items.isEmpty else { return nil }
        let cal = items.reduce(0) { $0 + $1.totalCalories }
        let p = items.reduce(0.0) { $0 + $1.totalProtein }
        let c = items.reduce(0.0) { $0 + $1.totalCarbs }
        let f = items.reduce(0.0) { $0 + $1.totalFat }
        return (cal, p, c, f)
    }

    nonisolated private static func foodItem(from row: WhisperNutritionMealRow) -> FoodItem? {
        let ts = row.eaten_at.flatMap {
            isoFractional.date(from: $0) ?? isoPlain.date(from: $0)
        } ?? Date()
        // Prefer the explicit slot Whisper now persists in `meal_type`.
        // Fall back to hour-of-day inference if the row pre-dates the column.
        let mt: MealType = {
            if let raw = row.meal_type?.lowercased(),
               let parsed = MealType(rawValue: raw) {
                return parsed
            }
            let hour = Calendar.current.component(.hour, from: ts)
            switch hour {
            case 4..<10:  return .breakfast
            case 10..<15: return .lunch
            case 15..<21: return .dinner
            default:      return .snack
            }
        }()
        // Prefer the new-contract `calories` Int; fall back to legacy
        // `calories_kcal` Double for rows written before the new column
        // existed (or by clients that only filled the legacy field).
        let kcal: Int = {
            if let c = row.calories, c > 0 { return c }
            if let k = row.calories_kcal, k > 0 { return Int(k.rounded()) }
            return 0
        }()
        return FoodItem(
            stableId: row.id,
            name: row.name ?? "Meal",
            calories: kcal,
            protein: row.protein_g ?? 0,
            carbs: row.carbs_g ?? 0,
            fat: row.fat_g ?? 0,
            mealType: mt,
            timestamp: ts
        )
    }
}

// MARK: - FoodItem init preserving stableId

extension FoodItem {
    /// Memberwise-style init that lets callers preserve a stableId pulled in
    /// from Supabase, so the same row round-trips cleanly between Whisper and
    /// Whisper without spawning a new local UUID each time.
    init(
        stableId: String,
        name: String,
        brand: String = "",
        barcode: String = "",
        calories: Int = 0,
        protein: Double = 0,
        carbs: Double = 0,
        fat: Double = 0,
        fiber: Double = 0,
        sugar: Double = 0,
        sodium: Double = 0,
        servingSize: Double = 1,
        servingUnit: String = "serving",
        numberOfServings: Double = 1,
        mealType: MealType = .snack,
        timestamp: Date = .now,
        icon: String = "fork.knife"
    ) {
        self.stableId = stableId
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.sugar = sugar
        self.sodium = sodium
        self.servingSize = servingSize
        self.servingUnit = servingUnit
        self.numberOfServings = numberOfServings
        self.mealType = mealType
        self.timestamp = timestamp
        self.icon = icon
    }
}

// MARK: - Canonical schema (managed by Whisper — do NOT recreate)
//
// Source of truth for the shared `public.jasper_nutrition_meals` table.
// Whisper conforms to this shape; Whisper RN does too. `meal_type` is the
// explicit slot picker — when set, Whisper groups by it verbatim instead of
// inferring from hour-of-day. RLS is owner-write,
// so all DM/restaurant writes must come from the *recipient's* session
// (which is what `pushMeal` does — it always resolves the live auth UID).
/*
create table if not exists public.jasper_nutrition_meals (
  id                  uuid primary key,                                              -- stable per meal, reused on edits
  user_id             uuid not null references auth.users(id) on delete cascade,     -- recipient's auth.uid()
  name                text,
  calories            int4,                                                          -- whole number; never null
  protein_g           numeric,                                                       -- grams; never null (0 if unknown)
  carbs_g             numeric,                                                       -- grams; never null
  fat_g               numeric,                                                       -- grams; never null
  eaten_at            timestamptz not null default now(),                            -- UTC; "today" window filter
  source              text,                                                          -- "whisper" | "whisper_restaurant"
  meal_type           text,                                                          -- "breakfast"|"lunch"|"dinner"|"snack"|"drink" (lowercase, verbatim)
  restaurant_name     text,
  restaurant_place_id text
);
create index if not exists jasper_nutrition_meals_user_eaten_idx
  on public.jasper_nutrition_meals (user_id, eaten_at desc);

alter table public.jasper_nutrition_meals enable row level security;
drop policy if exists "meals read own"   on public.jasper_nutrition_meals;
create policy "meals read own"   on public.jasper_nutrition_meals for select using (auth.uid() = user_id);
drop policy if exists "meals insert own" on public.jasper_nutrition_meals;
create policy "meals insert own" on public.jasper_nutrition_meals for insert with check (auth.uid() = user_id);
drop policy if exists "meals update own" on public.jasper_nutrition_meals;
create policy "meals update own" on public.jasper_nutrition_meals for update using (auth.uid() = user_id);
drop policy if exists "meals delete own" on public.jasper_nutrition_meals;
create policy "meals delete own" on public.jasper_nutrition_meals for delete using (auth.uid() = user_id);

-- One-time: enable realtime so INSERT/UPDATE/DELETE fan out to both apps.
alter publication supabase_realtime add table public.jasper_nutrition_meals;
notify pgrst, 'reload schema';
*/
