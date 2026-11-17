import Foundation
import SwiftUI

nonisolated struct FoodItem: Identifiable, Codable, Sendable {
    nonisolated var id: String { stableId }
    let stableId: String
    var name: String
    var brand: String
    var barcode: String
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double
    var sugar: Double
    var sodium: Double
    var servingSize: Double
    var servingUnit: String
    var numberOfServings: Double
    var mealType: MealType
    var timestamp: Date
    var icon: String

    var totalCalories: Int { Int(Double(calories) * numberOfServings) }
    var totalProtein: Double { protein * numberOfServings }
    var totalCarbs: Double { carbs * numberOfServings }
    var totalFat: Double { fat * numberOfServings }
    var totalFiber: Double { fiber * numberOfServings }
    var totalSugar: Double { sugar * numberOfServings }
    var totalSodium: Double { sodium * numberOfServings }

    init(
        name: String = "",
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
        self.stableId = UUID().uuidString
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

nonisolated enum MealType: String, CaseIterable, Codable, Identifiable, Sendable {
    case breakfast, lunch, dinner, snack, drink

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        case .snack: return "Snack"
        case .drink: return "Drink"
        }
    }

    var icon: String {
        switch self {
        case .breakfast: return "cup.and.saucer.fill"
        case .lunch: return "leaf.fill"
        case .dinner: return "fork.knife"
        case .snack: return "carrot.fill"
        case .drink: return "cup.and.heat.waves.fill"
        }
    }

    var color: Color {
        switch self {
        case .breakfast: return .orange
        case .lunch: return .green
        case .dinner: return .blue
        case .snack: return .purple
        case .drink: return .cyan
        }
    }
}

struct NutritionGoals: Codable, Sendable {
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var water: Int

    static let `default` = NutritionGoals(
        calories: 2000,
        protein: 150,
        carbs: 250,
        fat: 65,
        water: 8
    )
}

nonisolated struct OpenFoodFactsResponse: Codable, Sendable {
    let status: Int?
    let product: OFFProduct?
}

nonisolated struct OFFProduct: Codable, Sendable {
    let product_name: String?
    let brands: String?
    let nutriments: OFFNutriments?
    let serving_size: String?
    let serving_quantity: Double?
}

nonisolated struct OFFNutriments: Codable, Sendable {
    let energy_kcal_100g: Double?
    let proteins_100g: Double?
    let carbohydrates_100g: Double?
    let fat_100g: Double?
    let fiber_100g: Double?
    let sugars_100g: Double?
    let sodium_100g: Double?

    let energy_kcal_serving: Double?
    let proteins_serving: Double?
    let carbohydrates_serving: Double?
    let fat_serving: Double?
    let fiber_serving: Double?
    let sugars_serving: Double?
    let sodium_serving: Double?

    enum CodingKeys: String, CodingKey {
        case energy_kcal_100g = "energy-kcal_100g"
        case proteins_100g = "proteins_100g"
        case carbohydrates_100g = "carbohydrates_100g"
        case fat_100g = "fat_100g"
        case fiber_100g = "fiber_100g"
        case sugars_100g = "sugars_100g"
        case sodium_100g = "sodium_100g"
        case energy_kcal_serving = "energy-kcal_serving"
        case proteins_serving = "proteins_serving"
        case carbohydrates_serving = "carbohydrates_serving"
        case fat_serving = "fat_serving"
        case fiber_serving = "fiber_serving"
        case sugars_serving = "sugars_serving"
        case sodium_serving = "sodium_serving"
    }
}
