import Foundation
import SwiftUI
import Combine

@Observable
class NutritionViewModel {
    var meals: [FoodItem] = []
    var goals: NutritionGoals = .default
    var waterCount: Int = 0
    var isLoading: Bool = false
    var errorMessage: String?
    var scannedFood: FoodItem?
    var showScanner: Bool = false
    var showAddFood: Bool = false
    var showFoodDetail: Bool = false
    var showGoalsEditor: Bool = false
    var showPhotoAnalysis: Bool = false
    var selectedFood: FoodItem?
    var selectedMealTypeFilter: MealType?
    var loggingStreak: Int = 0
    var showCelebration: Bool = false
    var celebrationTitle: String = ""
    var celebrationMessage: String = ""
    var celebrationIcon: String = "party.popper.fill"

    @ObservationIgnored private var didChangeObserver: NSObjectProtocol?

    var todayMeals: [FoodItem] {
        let cal = Calendar.current
        return meals.filter { cal.isDateInToday($0.timestamp) }
    }

    var totalCalories: Int { todayMeals.reduce(0) { $0 + $1.totalCalories } }
    var totalProtein: Double { todayMeals.reduce(0) { $0 + $1.totalProtein } }
    var totalCarbs: Double { todayMeals.reduce(0) { $0 + $1.totalCarbs } }
    var totalFat: Double { todayMeals.reduce(0) { $0 + $1.totalFat } }
    var totalFiber: Double { todayMeals.reduce(0) { $0 + $1.totalFiber } }
    var totalSugar: Double { todayMeals.reduce(0) { $0 + $1.totalSugar } }
    var totalSodium: Double { todayMeals.reduce(0) { $0 + $1.totalSodium } }

    var calorieProgress: Double { min(Double(totalCalories) / max(Double(goals.calories), 1), 1.0) }
    var proteinProgress: Double { min(totalProtein / max(goals.protein, 1), 1.0) }
    var carbsProgress: Double { min(totalCarbs / max(goals.carbs, 1), 1.0) }
    var fatProgress: Double { min(totalFat / max(goals.fat, 1), 1.0) }

    var caloriesRemaining: Int { max(0, goals.calories - totalCalories) }
    var proteinRemaining: Double { max(0, goals.protein - totalProtein) }
    var carbsRemaining: Double { max(0, goals.carbs - totalCarbs) }
    var fatRemaining: Double { max(0, goals.fat - totalFat) }

    var macroCaloriesFromProtein: Double { totalProtein * 4 }
    var macroCaloriesFromCarbs: Double { totalCarbs * 4 }
    var macroCaloriesFromFat: Double { totalFat * 9 }

    var proteinPercentage: Double {
        let total = macroCaloriesFromProtein + macroCaloriesFromCarbs + macroCaloriesFromFat
        guard total > 0 else { return 0 }
        return macroCaloriesFromProtein / total * 100
    }
    var carbsPercentage: Double {
        let total = macroCaloriesFromProtein + macroCaloriesFromCarbs + macroCaloriesFromFat
        guard total > 0 else { return 0 }
        return macroCaloriesFromCarbs / total * 100
    }
    var fatPercentage: Double {
        let total = macroCaloriesFromProtein + macroCaloriesFromCarbs + macroCaloriesFromFat
        guard total > 0 else { return 0 }
        return macroCaloriesFromFat / total * 100
    }

    func mealsForType(_ type: MealType) -> [FoodItem] {
        todayMeals.filter { $0.mealType == type }
    }

    func caloriesForType(_ type: MealType) -> Int {
        mealsForType(type).reduce(0) { $0 + $1.totalCalories }
    }

    init() {
        loadStreak()
        Task { @MainActor in
            self.syncFromStore()
        }
        didChangeObserver = NotificationCenter.default.addObserver(
            forName: NutritionStore.didChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncFromStore()
            }
        }
    }

    deinit {
        if let observer = didChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    @MainActor
    private func syncFromStore() {
        let store = NutritionStore.shared
        meals = store.meals
        goals = store.goals
        waterCount = store.waterCount
    }

    func addMeal(_ item: FoodItem) {
        Task { @MainActor in
            NutritionStore.shared.addMeal(item)
            self.syncFromStore()
            self.checkMilestones()
            self.updateLoggingStreak()
        }
    }

    func updateMeal(_ item: FoodItem) {
        Task { @MainActor in
            NutritionStore.shared.updateMeal(item)
            self.syncFromStore()
        }
    }

    func deleteMeal(_ item: FoodItem) {
        Task { @MainActor in
            NutritionStore.shared.removeMeal(item)
            self.syncFromStore()
        }
    }

    func lookupBarcode(_ barcode: String) async {
        isLoading = true
        errorMessage = nil
        do {
            if let food = try await OpenFoodFactsService.shared.fetchProduct(barcode: barcode) {
                scannedFood = food
                showFoodDetail = true
            } else {
                errorMessage = "Product not found. Try adding it manually."
            }
        } catch {
            errorMessage = "Failed to look up product. Check your connection."
        }
        isLoading = false
    }

    /// Kept for backwards compatibility — callers that mutate `goals` /
    /// `waterCount` directly and then call `saveData()` are still supported.
    func saveData() {
        Task { @MainActor in
            NutritionStore.shared.setGoals(self.goals)
            NutritionStore.shared.setWater(self.waterCount)
            self.syncFromStore()
            self.syncToCloud()
        }
    }

    /// Legacy entry point — no-op now that NutritionStore owns the widget sync.
    func syncToSharedDefaults() {
        Task { @MainActor in
            self.syncFromStore()
        }
    }

    private func syncToCloud() {
        let userID = AccountStorage.currentUserID
        guard userID != "guest" else { return }
        Task {
            await CloudKitService.shared.saveUserDataBlob(userID: userID, key: "nutritionMeals", storageKey: NutritionStore.mealsKey)
            await CloudKitService.shared.saveUserDataBlob(userID: userID, key: "nutritionGoals", storageKey: NutritionStore.goalsKey)
        }
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func checkMilestones() {
        let today = dateString(Date())
        let mealCount = todayMeals.count

        if mealCount == 3 && totalCalories > 0 {
            celebrateOnce(key: "meals_3_\(today)",
                          title: "3 Meals Logged!",
                          message: "You're staying consistent with your fueling — Jasper sees the work.",
                          icon: "fork.knife")
        }
        if totalProtein >= goals.protein && goals.protein > 0 {
            celebrateOnce(key: "protein_goal_celebrated_\(today)",
                          title: "Protein Smashed!",
                          message: "You hit your daily protein goal. Muscles thank you.",
                          icon: "bolt.fill")
        }
        if totalCarbs >= goals.carbs && goals.carbs > 0 {
            celebrateOnce(key: "carbs_goal_celebrated_\(today)",
                          title: "Carbs Crushed!",
                          message: "Energy locked in — you've reached your carbs goal for today.",
                          icon: "leaf.fill")
        }
        if totalFat >= goals.fat && goals.fat > 0 {
            celebrateOnce(key: "fat_goal_celebrated_\(today)",
                          title: "Healthy Fats Done!",
                          message: "You hit your daily fats target. Hormones balanced.",
                          icon: "drop.triangle.fill")
        }
        if totalCalories >= goals.calories && goals.calories > 0 {
            celebrateOnce(key: "calories_goal_celebrated_\(today)",
                          title: "Calorie Goal Hit!",
                          message: "You've fueled your day. Keep showing up like this.",
                          icon: "flame.fill")
        }
        if waterCount >= goals.water && goals.water > 0 {
            celebrateOnce(key: "water_goal_celebrated_\(today)",
                          title: "Hydration Goal!",
                          message: "You hit your water goal — your body is thanking you.",
                          icon: "drop.fill")
        }
    }

    private func celebrateOnce(key: String, title: String, message: String, icon: String) {
        guard !AccountStorage.bool(forKey: key) else { return }
        AccountStorage.set(true, forKey: key)
        triggerCelebration(title: title, message: message, icon: icon)
    }

    private func triggerCelebration(title: String, message: String, icon: String) {
        celebrationTitle = title
        celebrationMessage = message
        celebrationIcon = icon
        showCelebration = true
    }

    private func updateLoggingStreak() {
        let today = dateString(Date())
        let lastLogDate = AccountStorage.string(forKey: "nutrition_last_log_date") ?? ""
        let yesterday = dateString(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())

        if lastLogDate == today {
            return
        } else if lastLogDate == yesterday {
            loggingStreak += 1
        } else if lastLogDate.isEmpty {
            loggingStreak = 1
        } else {
            loggingStreak = 1
        }

        AccountStorage.set(today, forKey: "nutrition_last_log_date")
        AccountStorage.set(loggingStreak, forKey: "nutrition_logging_streak")

        if loggingStreak == 7 {
            triggerCelebration(title: "7-Day Streak!", message: "A full week of logging. This is how transformations start.", icon: "flame.fill")
        } else if loggingStreak == 30 {
            triggerCelebration(title: "30-Day Streak!", message: "A full month of consistency. Jasper is so proud of you.", icon: "star.fill")
        }
    }

    private func loadStreak() {
        loggingStreak = AccountStorage.integer(forKey: "nutrition_logging_streak")
        let lastLogDate = AccountStorage.string(forKey: "nutrition_last_log_date") ?? ""
        let today = dateString(Date())
        let yesterday = dateString(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        if lastLogDate != today && lastLogDate != yesterday {
            loggingStreak = 0
        }
    }
}
