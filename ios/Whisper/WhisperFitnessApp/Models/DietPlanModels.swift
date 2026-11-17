import Foundation
import SwiftUI

nonisolated struct MacroSurveyResult: Codable, Sendable {
    var age: Int
    var gender: MacroGender
    var weightLbs: Double
    var heightInches: Double
    var activityLevel: ActivityLevel
    var goal: DietGoal
    var dietaryPreference: DietaryPreference
    var mealsPerDay: Int
    var allergies: [String]
    var additionalNotes: String

    var weightKg: Double { weightLbs * 0.453592 }
    var heightCm: Double { heightInches * 2.54 }

    var bmr: Double {
        switch gender {
        case .male:
            return 10 * weightKg + 6.25 * heightCm - 5 * Double(age) + 5
        case .female:
            return 10 * weightKg + 6.25 * heightCm - 5 * Double(age) - 161
        }
    }

    var tdee: Double { bmr * activityLevel.multiplier }

    var targetCalories: Int {
        switch goal {
        case .lose:
            return Int(tdee - 500)
        case .maintain:
            return Int(tdee)
        case .gain:
            return Int(tdee + 300)
        case .aggressiveLoss:
            return Int(tdee - 750)
        case .leanBulk:
            return Int(tdee + 200)
        }
    }

    var targetProtein: Double {
        switch goal {
        case .lose, .aggressiveLoss:
            return weightKg * 2.2
        case .maintain:
            return weightKg * 1.8
        case .gain, .leanBulk:
            return weightKg * 2.0
        }
    }

    var targetFat: Double {
        Double(targetCalories) * 0.25 / 9.0
    }

    var targetCarbs: Double {
        let proteinCals = targetProtein * 4
        let fatCals = targetFat * 9
        return (Double(targetCalories) - proteinCals - fatCals) / 4.0
    }
}

nonisolated enum MacroGender: String, Codable, CaseIterable, Sendable {
    case male = "Male"
    case female = "Female"
}

nonisolated enum ActivityLevel: String, Codable, CaseIterable, Sendable {
    case sedentary = "Sedentary"
    case lightlyActive = "Lightly Active"
    case moderatelyActive = "Moderately Active"
    case veryActive = "Very Active"
    case extraActive = "Extra Active"

    var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .lightlyActive: return 1.375
        case .moderatelyActive: return 1.55
        case .veryActive: return 1.725
        case .extraActive: return 1.9
        }
    }

    var description: String {
        switch self {
        case .sedentary: return "Little or no exercise, desk job"
        case .lightlyActive: return "Light exercise 1-3 days/week"
        case .moderatelyActive: return "Moderate exercise 3-5 days/week"
        case .veryActive: return "Hard exercise 6-7 days/week"
        case .extraActive: return "Very hard exercise, physical job"
        }
    }

    var icon: String {
        switch self {
        case .sedentary: return "figure.stand"
        case .lightlyActive: return "figure.walk"
        case .moderatelyActive: return "figure.run"
        case .veryActive: return "figure.highintensity.intervaltraining"
        case .extraActive: return "figure.strengthtraining.traditional"
        }
    }
}

nonisolated enum DietGoal: String, Codable, CaseIterable, Sendable {
    case aggressiveLoss = "Aggressive Fat Loss"
    case lose = "Fat Loss"
    case maintain = "Maintain Weight"
    case leanBulk = "Lean Bulk"
    case gain = "Muscle Gain"

    var icon: String {
        switch self {
        case .aggressiveLoss: return "arrow.down.right.circle.fill"
        case .lose: return "arrow.down.circle.fill"
        case .maintain: return "equal.circle.fill"
        case .leanBulk: return "arrow.up.circle.fill"
        case .gain: return "arrow.up.right.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .aggressiveLoss: return .red
        case .lose: return .orange
        case .maintain: return .blue
        case .leanBulk: return .green
        case .gain: return .purple
        }
    }

    var calorieTip: String {
        switch self {
        case .aggressiveLoss: return "~750 cal deficit · faster results, requires discipline"
        case .lose: return "~500 cal deficit · steady, sustainable fat loss"
        case .maintain: return "Match your TDEE · maintain current weight"
        case .leanBulk: return "~200 cal surplus · minimal fat gain"
        case .gain: return "~300 cal surplus · optimized for muscle growth"
        }
    }
}

nonisolated enum DietaryPreference: String, Codable, CaseIterable, Sendable {
    case noPreference = "No Preference"
    case highProtein = "High Protein"
    case keto = "Keto"
    case vegetarian = "Vegetarian"
    case vegan = "Vegan"
    case pescatarian = "Pescatarian"
    case mediterranean = "Mediterranean"
    case paleo = "Paleo"
    case glutenFree = "Gluten Free"
    case dairyFree = "Dairy Free"
}

nonisolated struct WeeklyDietPlan: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let createdAt: Date
    let targetCalories: Int
    let targetProtein: Double
    let targetCarbs: Double
    let targetFat: Double
    let dietaryPreference: DietaryPreference
    let goal: DietGoal
    let days: [DailyDietPlan]

    init(
        name: String = "",
        targetCalories: Int = 2000,
        targetProtein: Double = 150,
        targetCarbs: Double = 200,
        targetFat: Double = 55,
        dietaryPreference: DietaryPreference = .noPreference,
        goal: DietGoal = .maintain,
        days: [DailyDietPlan] = []
    ) {
        self.id = UUID().uuidString
        self.name = name
        self.createdAt = .now
        self.targetCalories = targetCalories
        self.targetProtein = targetProtein
        self.targetCarbs = targetCarbs
        self.targetFat = targetFat
        self.dietaryPreference = dietaryPreference
        self.goal = goal
        self.days = days
    }
}

nonisolated struct DailyDietPlan: Identifiable, Codable, Sendable {
    let id: String
    let dayName: String
    let meals: [DietMeal]

    var totalCalories: Int { meals.reduce(0) { $0 + $1.calories } }
    var totalProtein: Double { meals.reduce(0) { $0 + $1.protein } }
    var totalCarbs: Double { meals.reduce(0) { $0 + $1.carbs } }
    var totalFat: Double { meals.reduce(0) { $0 + $1.fat } }

    init(dayName: String = "", meals: [DietMeal] = []) {
        self.id = UUID().uuidString
        self.dayName = dayName
        self.meals = meals
    }
}

nonisolated struct DietMeal: Identifiable, Codable, Sendable {
    let id: String
    let mealType: String
    let name: String
    let description: String
    let ingredients: [String]
    let calories: Int
    let protein: Double
    let carbs: Double
    let fat: Double
    let prepTime: String

    init(
        mealType: String = "",
        name: String = "",
        description: String = "",
        ingredients: [String] = [],
        calories: Int = 0,
        protein: Double = 0,
        carbs: Double = 0,
        fat: Double = 0,
        prepTime: String = ""
    ) {
        self.id = UUID().uuidString
        self.mealType = mealType
        self.name = name
        self.description = description
        self.ingredients = ingredients
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.prepTime = prepTime
    }
}

nonisolated struct DietPlanAPIResponse: Codable, Sendable {
    let planName: String?
    let days: [DayResponse]?

    nonisolated struct DayResponse: Codable, Sendable {
        let day: String?
        let meals: [MealResponse]?
    }

    nonisolated struct MealResponse: Codable, Sendable {
        let mealType: String?
        let name: String?
        let description: String?
        let ingredients: [String]?
        let calories: Int?
        let protein: Double?
        let carbs: Double?
        let fat: Double?
        let prepTime: String?

        nonisolated init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mealType = try? container.decodeIfPresent(String.self, forKey: .mealType)
            name = try? container.decodeIfPresent(String.self, forKey: .name)
            description = try? container.decodeIfPresent(String.self, forKey: .description)
            ingredients = try? container.decodeIfPresent([String].self, forKey: .ingredients)
            prepTime = try? container.decodeIfPresent(String.self, forKey: .prepTime)

            if let intVal = try? container.decodeIfPresent(Int.self, forKey: .calories) {
                calories = intVal
            } else if let dVal = try? container.decodeIfPresent(Double.self, forKey: .calories) {
                calories = Int(dVal)
            } else { calories = nil }

            if let dVal = try? container.decodeIfPresent(Double.self, forKey: .protein) {
                protein = dVal
            } else if let iVal = try? container.decodeIfPresent(Int.self, forKey: .protein) {
                protein = Double(iVal)
            } else { protein = nil }

            if let dVal = try? container.decodeIfPresent(Double.self, forKey: .carbs) {
                carbs = dVal
            } else if let iVal = try? container.decodeIfPresent(Int.self, forKey: .carbs) {
                carbs = Double(iVal)
            } else { carbs = nil }

            if let dVal = try? container.decodeIfPresent(Double.self, forKey: .fat) {
                fat = dVal
            } else if let iVal = try? container.decodeIfPresent(Int.self, forKey: .fat) {
                fat = Double(iVal)
            } else { fat = nil }
        }

        private enum CodingKeys: String, CodingKey {
            case mealType, name, description, ingredients, calories, protein, carbs, fat, prepTime
        }
    }
}
