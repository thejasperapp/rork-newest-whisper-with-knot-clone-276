import Foundation
import SwiftUI

/// Shared, single source of truth for nutrition meals + goals + water across
/// the whole app (Whisper nutrition tab, Whisper map embeds, Jasper chat,
/// widgets). Any view that wants live macro state reads from
/// `NutritionStore.shared`, and any caller that mutates state posts through
/// `addMeal` / `removeMeal` / `setGoals`, which:
///
///  1. Updates the in-memory state immediately (so SwiftUI re-renders).
///  2. Persists to AccountStorage (per-user namespaced).
///  3. Posts `NutritionStore.didChange` so legacy NutritionViewModel
///     instances reload from disk.
///  4. Syncs to the shared App Group defaults so widgets refresh.
@Observable
@MainActor
final class NutritionStore {
    static let shared = NutritionStore()

    nonisolated static let didChange = Notification.Name("WhisperNutritionDidChange")
    nonisolated static let mealsKey = "jasper_nutrition_meals"
    nonisolated static let goalsKey = "jasper_nutrition_goals"
    nonisolated static let waterKey = "jasper_nutrition_water"
    nonisolated static let waterDateKey = "jasper_nutrition_water_date"

    var meals: [FoodItem] = []
    var goals: NutritionGoals = .default
    var waterCount: Int = 0

    private init() {
        load()
    }

    // MARK: - Derived

    var todayMeals: [FoodItem] {
        let cal = Calendar.current
        return meals.filter { cal.isDateInToday($0.timestamp) }
    }

    var totalCalories: Int { todayMeals.reduce(0) { $0 + $1.totalCalories } }
    var totalProtein: Double { todayMeals.reduce(0) { $0 + $1.totalProtein } }
    var totalCarbs: Double { todayMeals.reduce(0) { $0 + $1.totalCarbs } }
    var totalFat: Double { todayMeals.reduce(0) { $0 + $1.totalFat } }

    var caloriesRemaining: Int { max(0, goals.calories - totalCalories) }
    var proteinRemaining: Double { max(0, goals.protein - totalProtein) }
    var carbsRemaining: Double { max(0, goals.carbs - totalCarbs) }
    var fatRemaining: Double { max(0, goals.fat - totalFat) }

    // MARK: - Mutations

    func addMeal(_ item: FoodItem) {
        meals.append(item)
        persist()
        announce()
        Task { await WhisperNutritionRemoteService.shared.pushMeal(item) }
    }

    /// Local-only append. Callers that need to await the cloud push themselves
    /// (e.g. the map embed surfacing a sync-failed toast) use this and then
    /// call `WhisperNutritionRemoteService.shared.pushMeal` directly.
    func addMealLocalOnly(_ item: FoodItem) {
        meals.append(item)
        persist()
        announce()
    }

    func updateMeal(_ item: FoodItem) {
        if let i = meals.firstIndex(where: { $0.stableId == item.stableId }) {
            meals[i] = item
            persist()
            announce()
            Task { await WhisperNutritionRemoteService.shared.pushMeal(item) }
        }
    }

    func removeMeal(_ item: FoodItem) {
        meals.removeAll { $0.stableId == item.stableId }
        persist()
        announce()
        Task { await WhisperNutritionRemoteService.shared.deleteMeal(stableId: item.stableId) }
    }

    /// Pulls today's per-row meals from `jasper_nutrition_meals` and merges
    /// anything not already present locally. Used so Jasper sees meals logged
    /// from the sister Whisper RN app, and so a fresh sign-in pulls cloud meals.
    func refreshFromWhisper() async {
        let remote = await WhisperNutritionRemoteService.shared.fetchToday()
        guard !remote.isEmpty else { return }
        let existing = Set(meals.map { $0.stableId })
        var added = false
        for item in remote where !existing.contains(item.stableId) {
            meals.append(item)
            added = true
        }
        if added {
            persist()
            announce()
        }
    }

    func setGoals(_ g: NutritionGoals) {
        goals = g
        persist()
        announce()
    }

    func setWater(_ count: Int) {
        waterCount = max(0, count)
        persist()
        announce()
    }

    /// Reload from disk. Called by NutritionViewModel after it receives the
    /// `didChange` notification from another component.
    func reloadFromDisk() {
        load()
    }

    // MARK: - Persistence

    private func load() {
        if let data = AccountStorage.data(forKey: Self.mealsKey),
           let decoded = try? JSONDecoder().decode([FoodItem].self, from: data) {
            meals = decoded
        } else {
            meals = []
        }
        if let data = AccountStorage.data(forKey: Self.goalsKey),
           let decoded = try? JSONDecoder().decode(NutritionGoals.self, from: data) {
            goals = decoded
        } else {
            goals = .default
        }
        let savedDate = AccountStorage.string(forKey: Self.waterDateKey) ?? ""
        let today = Self.dateString(Date())
        waterCount = (savedDate == today) ? AccountStorage.integer(forKey: Self.waterKey) : 0
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(meals) {
            AccountStorage.set(data, forKey: Self.mealsKey)
        }
        if let data = try? JSONEncoder().encode(goals) {
            AccountStorage.set(data, forKey: Self.goalsKey)
        }
        AccountStorage.set(waterCount, forKey: Self.waterKey)
        AccountStorage.set(Self.dateString(Date()), forKey: Self.waterDateKey)
        syncWidget()
    }

    private func syncWidget() {
        guard let shared = UserDefaults(suiteName: "group.com.mydailywhisper.whisper") else { return }
        shared.set(totalCalories, forKey: "widget_nutritionCalories")
        shared.set(totalProtein, forKey: "widget_nutritionProtein")
        shared.set(totalCarbs, forKey: "widget_nutritionCarbs")
        shared.set(totalFat, forKey: "widget_nutritionFat")
        shared.set(goals.calories, forKey: "widget_nutritionGoalCalories")
        shared.set(goals.protein, forKey: "widget_nutritionGoalProtein")
        shared.set(goals.carbs, forKey: "widget_nutritionGoalCarbs")
        shared.set(goals.fat, forKey: "widget_nutritionGoalFat")
        shared.set(waterCount, forKey: "widget_nutritionWater")
    }

    private func announce() {
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    nonisolated private static func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
