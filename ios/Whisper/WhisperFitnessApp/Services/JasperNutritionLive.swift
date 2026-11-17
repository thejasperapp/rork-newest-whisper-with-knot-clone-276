import Foundation
import SwiftUI

// MARK: - Shared grocery state (WHISPER_CONNECT.md Aug 17 2026 — facts 15)

/// The active diet plan's checklist as SHARED STATE — `GET /v1/grocery_list`
/// returns every item with a stable id and a `checked` flag, and
/// `POST /v1/grocery_list {items:[{id,checked}]}` checks items off. These are
/// the SAME rows the Jasper app's own checklist reads and writes: a check-off
/// in Whisper shows up in Jasper (and vice versa); every change emits
/// `grocery.updated` on the events feed (deduped ~30s).
nonisolated struct JasperSharedGrocery: Equatable {
    nonisolated struct Item: Equatable, Identifiable {
        /// Stable per plan — encodes plan + category + name. Cache from GET.
        let id: String
        let name: String
        let quantity: String
        let usedInMeals: Int
        var checked: Bool
    }

    nonisolated struct Category: Equatable, Identifiable {
        let name: String
        var items: [Item]
        var id: String { name.lowercased() }
    }

    let planID: String?
    let planName: String
    var categories: [Category]

    var itemCount: Int { categories.reduce(0) { $0 + $1.items.count } }
    var checkedCount: Int { categories.reduce(0) { $0 + $1.items.filter(\.checked).count } }

    /// `{ ok, plan: {id, name}, item_count, checked_count,
    ///    categories: [{ name, items: [{ id, name, quantity, used_in_meals, checked }] }] }`
    /// Lenient on value types, strict on structure. Nil = no active plan / no list.
    static func parse(_ data: Data) -> JasperSharedGrocery? {
        guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (body["ok"] as? Bool) != false else { return nil }
        let plan = body["plan"] as? [String: Any]
        let rawCategories = (body["categories"] as? [[String: Any]]) ?? []
        let categories: [Category] = rawCategories.compactMap { cat in
            guard let name = cat["name"] as? String else { return nil }
            let items: [Item] = ((cat["items"] as? [[String: Any]]) ?? []).compactMap { raw in
                guard let itemName = raw["name"] as? String, !itemName.isEmpty else { return nil }
                let id = (raw["id"] as? String) ?? itemName.lowercased()
                let quantity = (raw["quantity"] as? String)
                    ?? (raw["quantity"] as? NSNumber).map { "\($0)" }
                    ?? ""
                let used = (raw["used_in_meals"] as? NSNumber)?.intValue
                    ?? (raw["usedInMeals"] as? NSNumber)?.intValue
                    ?? 1
                let checked = (raw["checked"] as? NSNumber)?.boolValue
                    ?? (raw["checked"] as? Bool)
                    ?? false
                return Item(id: id, name: itemName, quantity: quantity,
                            usedInMeals: used, checked: checked)
            }
            return items.isEmpty ? nil : Category(name: name, items: items)
        }
        guard !categories.isEmpty else { return nil }
        return JasperSharedGrocery(
            planID: (plan?["id"] as? String) ?? ((plan?["id"] as? NSNumber).map { "\($0)" }),
            planName: (plan?["name"] as? String) ?? "Diet plan",
            categories: categories)
    }
}

// MARK: - Recipes (facts 14 — first-class resource, GET/POST/DELETE /v1/recipes)

/// One ingredient — a standard loggable food. Macros describe ONE serving of
/// the ingredient; `numberOfServings` is how much the WHOLE recipe uses.
nonisolated struct JasperRecipeIngredient: Equatable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var servingUnit: String
    var numberOfServings: Double

    init(id: UUID = UUID(), name: String, calories: Double = 0, protein: Double = 0,
         carbs: Double = 0, fat: Double = 0, servingUnit: String = "serving",
         numberOfServings: Double = 1) {
        self.id = id
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.servingUnit = servingUnit
        self.numberOfServings = max(0, numberOfServings)
    }

    var totalCalories: Double { calories * numberOfServings }
    var totalProtein: Double { protein * numberOfServings }
    var totalCarbs: Double { carbs * numberOfServings }
    var totalFat: Double { fat * numberOfServings }

    /// Human amount line — "2 × scoop" / "1 × cup".
    var amountLabel: String {
        let count = numberOfServings == numberOfServings.rounded()
            ? String(Int(numberOfServings)) : String(numberOfServings)
        return servingUnit.isEmpty ? count : "\(count) × \(servingUnit)"
    }

    static func parse(_ raw: [String: Any]) -> JasperRecipeIngredient? {
        guard let name = raw["name"] as? String, !name.isEmpty else { return nil }
        func number(_ key: String) -> Double { (raw[key] as? NSNumber)?.doubleValue ?? 0 }
        return JasperRecipeIngredient(
            name: name,
            calories: number("calories"),
            protein: number("protein"),
            carbs: number("carbs"),
            fat: number("fat"),
            servingUnit: (raw["servingUnit"] as? String) ?? (raw["serving_unit"] as? String) ?? "serving",
            numberOfServings: (raw["numberOfServings"] as? NSNumber)?.doubleValue
                ?? (raw["number_of_servings"] as? NSNumber)?.doubleValue
                ?? 1)
    }

    var payloadDict: [String: Any] {
        [
            "name": name,
            "calories": calories,
            "protein": protein,
            "carbs": carbs,
            "fat": fat,
            "servingUnit": servingUnit.isEmpty ? "serving" : servingUnit,
            "numberOfServings": max(0.1, numberOfServings),
        ]
    }
}

/// A saved recipe — ONE shared object between Whisper and Jasper. Per-serving
/// macros are DERIVED (totals ÷ servings), never stored — the render contract.
nonisolated struct JasperRecipe: Equatable, Identifiable {
    let id: String
    var name: String
    var emoji: String
    var servings: Int
    var note: String
    var steps: [String]
    var prepTime: String?
    var cookTime: String?
    var sourceURL: String?
    var sourceApp: String?
    var createdAt: Date?
    var ingredients: [JasperRecipeIngredient]

    /// Per-serving macros derived live — `count` overrides the stored yield
    /// (the servings stepper re-derives, never reads a stored number).
    func perServing(_ count: Int? = nil) -> (kcal: Double, protein: Double, carbs: Double, fat: Double) {
        let divisor = Double(max(1, count ?? servings))
        let kcal = ingredients.reduce(0.0) { $0 + $1.totalCalories }
        let protein = ingredients.reduce(0.0) { $0 + $1.totalProtein }
        let carbs = ingredients.reduce(0.0) { $0 + $1.totalCarbs }
        let fat = ingredients.reduce(0.0) { $0 + $1.totalFat }
        return (kcal / divisor, protein / divisor, carbs / divisor, fat / divisor)
    }

    /// Lenient row parse (snake_case API rows AND the app's camelCase shape).
    static func parse(row: [String: Any]) -> JasperRecipe? {
        guard let name = row["name"] as? String, !name.isEmpty else { return nil }
        let id = (row["client_id"] as? String) ?? (row["id"] as? String) ?? UUID().uuidString
        let ingredients = ((row["ingredients"] as? [[String: Any]]) ?? [])
            .compactMap { JasperRecipeIngredient.parse($0) }
        let servings = (row["servings"] as? NSNumber)?.intValue ?? 1
        return JasperRecipe(
            id: id,
            name: name,
            emoji: (row["emoji"] as? String) ?? "🍽️",
            servings: max(1, servings),
            note: (row["note"] as? String) ?? "",
            steps: (row["steps"] as? [String]) ?? [],
            prepTime: (row["prep_time"] as? String) ?? (row["prepTime"] as? String),
            cookTime: (row["cook_time"] as? String) ?? (row["cookTime"] as? String),
            sourceURL: (row["source_url"] as? String) ?? (row["sourceURL"] as? String),
            sourceApp: (row["source_app"] as? String),
            createdAt: jasperConnectDate(row["created_at"] ?? row["dateCreated"]),
            ingredients: ingredients)
    }
}

/// Editable recipe draft — the composer's working copy. Prefillable from a
/// Jasper Intelligence `recipe` action or a DM recipe card.
nonisolated struct JasperRecipeDraft: Hashable {
    nonisolated struct Ingredient: Hashable, Identifiable {
        let id: UUID
        var name: String
        var calories: String
        var protein: String
        var carbs: String
        var fat: String
        var servingUnit: String
        var numberOfServings: String

        init(id: UUID = UUID(), name: String = "", calories: String = "",
             protein: String = "", carbs: String = "", fat: String = "",
             servingUnit: String = "serving", numberOfServings: String = "1") {
            self.id = id
            self.name = name
            self.calories = calories
            self.protein = protein
            self.carbs = carbs
            self.fat = fat
            self.servingUnit = servingUnit
            self.numberOfServings = numberOfServings
        }

        var parsed: JasperRecipeIngredient? {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return JasperRecipeIngredient(
                id: id,
                name: trimmed,
                calories: Double(calories) ?? 0,
                protein: Double(protein) ?? 0,
                carbs: Double(carbs) ?? 0,
                fat: Double(fat) ?? 0,
                servingUnit: servingUnit.trimmingCharacters(in: .whitespaces),
                numberOfServings: Double(numberOfServings) ?? 1)
        }
    }

    var name: String = ""
    var emoji: String = ""
    var servings: Int = 2
    var prepTime: String = ""
    var cookTime: String = ""
    var note: String = ""
    var sourceURL: String = ""
    var steps: [String] = []
    var ingredients: [Ingredient] = [Ingredient()]
    /// Set when editing an existing recipe — re-POSTing the same client_id
    /// updates in place (upsert).
    var upsertID: String? = nil

    var parsedIngredients: [JasperRecipeIngredient] { ingredients.compactMap(\.parsed) }

    var isSendable: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !parsedIngredients.isEmpty
    }

    /// Live per-serving preview (totals ÷ servings — the render contract).
    var perServing: (kcal: Double, protein: Double, carbs: Double, fat: Double) {
        let divisor = Double(max(1, servings))
        let parsed = parsedIngredients
        return (parsed.reduce(0.0) { $0 + $1.totalCalories } / divisor,
                parsed.reduce(0.0) { $0 + $1.totalProtein } / divisor,
                parsed.reduce(0.0) { $0 + $1.totalCarbs } / divisor,
                parsed.reduce(0.0) { $0 + $1.totalFat } / divisor)
    }

    /// POST /v1/recipes body — write_fields exactly; the worker builds the
    /// decode-safe app payload server-side (never construct `payload` here).
    func postBody() -> [String: Any] {
        var body: [String: Any] = [
            "client_id": upsertID ?? UUID().uuidString.lowercased(),
            "name": name.trimmingCharacters(in: .whitespaces),
            "servings": max(1, servings),
            "ingredients": parsedIngredients.map(\.payloadDict),
        ]
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespaces)
        if !trimmedEmoji.isEmpty { body["emoji"] = trimmedEmoji }
        let cleanSteps = steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !cleanSteps.isEmpty { body["steps"] = cleanSteps }
        if !prepTime.trimmingCharacters(in: .whitespaces).isEmpty { body["prep_time"] = prepTime }
        if !cookTime.trimmingCharacters(in: .whitespaces).isEmpty { body["cook_time"] = cookTime }
        if !note.trimmingCharacters(in: .whitespaces).isEmpty { body["note"] = note }
        if !sourceURL.trimmingCharacters(in: .whitespaces).isEmpty { body["source_url"] = sourceURL }
        return body
    }

    /// Editing an existing recipe — seed the draft from the shared object.
    init() {}

    init(recipe: JasperRecipe) {
        name = recipe.name
        emoji = recipe.emoji
        servings = recipe.servings
        prepTime = recipe.prepTime ?? ""
        cookTime = recipe.cookTime ?? ""
        note = recipe.note
        sourceURL = recipe.sourceURL ?? ""
        steps = recipe.steps
        upsertID = recipe.id
        ingredients = recipe.ingredients.map { ing in
            func text(_ v: Double) -> String {
                v == v.rounded() ? String(Int(v)) : String(v)
            }
            return Ingredient(id: ing.id, name: ing.name,
                              calories: text(ing.calories), protein: text(ing.protein),
                              carbs: text(ing.carbs), fat: text(ing.fat),
                              servingUnit: ing.servingUnit,
                              numberOfServings: text(ing.numberOfServings))
        }
        if ingredients.isEmpty { ingredients = [Ingredient()] }
    }
}

// MARK: - Diet-plan generation (facts 16 — POST /v1/diet_plans/generate)

/// Request for Jasper's OWN generator over the API: macro targets OR a
/// profile (Mifflin-St Jeor computes them exactly like the app — goal adjusts
/// kcal, protein 1.8-2.2 g/kg by goal, fat 25% of kcal).
nonisolated struct JasperDietGenRequest {
    nonisolated struct Profile {
        var age: Int
        var gender: String
        var weightLbs: Double
        var heightInches: Double
        var activityLevel: String
    }

    var goal: String
    var dietaryPreference: String
    var allergies: [String]
    var mealsPerDay: Int
    var targetCalories: Int?
    var targetProtein: Int?
    var targetCarbs: Int?
    var targetFat: Int?
    var profile: Profile?
    var save: Bool

    func body() -> [String: Any] {
        var out: [String: Any] = [
            "goal": goal,
            "dietary_preference": dietaryPreference,
            "meals_per_day": mealsPerDay,
            "save": save,
        ]
        if !allergies.isEmpty { out["allergies"] = allergies }
        if let profile {
            out["profile"] = [
                "age": profile.age,
                "gender": profile.gender,
                "weight_lbs": profile.weightLbs,
                "height_inches": profile.heightInches,
                "activity_level": profile.activityLevel,
            ] as [String: Any]
        } else {
            if let targetCalories { out["target_calories"] = targetCalories }
            if let targetProtein { out["target_protein_g"] = targetProtein }
            if let targetCarbs { out["target_carbs_g"] = targetCarbs }
            if let targetFat { out["target_fat_g"] = targetFat }
        }
        return out
    }

    /// Jasper's fixed diet-goal vocabulary (plan_shapes).
    nonisolated static let goals = [
        "Aggressive Fat Loss", "Fat Loss", "Maintain Weight", "Lean Bulk", "Muscle Gain",
    ]

    /// Jasper's fixed dietary-preference vocabulary (plan_shapes).
    nonisolated static let preferences = [
        "No Preference", "High Protein", "Keto", "Vegetarian", "Vegan",
        "Pescatarian", "Mediterranean", "Paleo", "Gluten Free", "Dairy Free",
    ]

    nonisolated static let activityLevels = [
        "Sedentary", "Lightly Active", "Moderately Active", "Very Active", "Extremely Active",
    ]
}

/// Parsed generator answer: `{ ok, generated, saved, plan: {…, payload} }`.
/// `postBody` is the ready `POST /v1/diet_plans` body for the preview → send
/// flow — the payload rides VERBATIM (byte-exact plan_shapes).
nonisolated struct JasperDietGenResult {
    nonisolated struct MealPreview: Equatable {
        let name: String
        let type: String
        let kcal: Int
    }

    nonisolated struct DayPreview: Equatable, Identifiable {
        let dayName: String
        let meals: [MealPreview]
        var id: String { dayName }
        var kcal: Int { meals.reduce(0) { $0 + $1.kcal } }
    }

    let generated: Bool
    let saved: Bool
    let planName: String
    let goal: String?
    let preference: String?
    let targetCalories: Int?
    let targetProtein: Int?
    let targetCarbs: Int?
    let targetFat: Int?
    let groceryItemCount: Int
    let days: [DayPreview]
    let clientID: String?
    let postBody: [String: Any]

    static func parse(_ data: Data) -> JasperDietGenResult? {
        guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (body["ok"] as? Bool) != false,
              let plan = body["plan"] as? [String: Any] else { return nil }
        let payload = (plan["payload"] as? [String: Any]) ?? plan
        func planInt(_ rowKey: String, _ payloadKey: String) -> Int? {
            (plan[rowKey] as? NSNumber)?.intValue ?? (payload[payloadKey] as? NSNumber)?.intValue
        }
        let name = (plan["name"] as? String) ?? (payload["name"] as? String) ?? "Diet plan"
        let clientID = (plan["client_id"] as? String) ?? (payload["id"] as? String)
        let goal = (plan["goal"] as? String) ?? (payload["goal"] as? String)
        let preference = (plan["dietary_preference"] as? String)
            ?? (payload["dietaryPreference"] as? String)
        let days: [DayPreview] = ((payload["days"] as? [[String: Any]]) ?? []).compactMap { day in
            guard let dayName = day["dayName"] as? String else { return nil }
            let meals: [MealPreview] = ((day["meals"] as? [[String: Any]]) ?? []).compactMap { meal in
                guard let mealName = meal["name"] as? String else { return nil }
                return MealPreview(name: mealName,
                                   type: (meal["mealType"] as? String) ?? "Meal",
                                   kcal: (meal["calories"] as? NSNumber)?.intValue ?? 0)
            }
            return DayPreview(dayName: dayName, meals: meals)
        }
        let groceryCount = ((payload["groceryList"] as? [String: Any])?["itemCount"] as? NSNumber)?.intValue ?? 0
        let targetCalories = planInt("target_calories", "targetCalories")
        let targetProtein = planInt("target_protein_g", "targetProtein")
        let targetCarbs = planInt("target_carbs_g", "targetCarbs")
        let targetFat = planInt("target_fat_g", "targetFat")

        // Ready POST /v1/diet_plans body — the payload rides verbatim.
        var post: [String: Any] = [
            "client_id": clientID ?? UUID().uuidString.lowercased(),
            "name": name,
            "is_active": true,
            "payload": payload,
        ]
        if let goal { post["goal"] = goal }
        if let preference { post["dietary_preference"] = preference }
        if let targetCalories { post["target_calories"] = targetCalories }
        if let targetProtein { post["target_protein_g"] = targetProtein }
        if let targetCarbs { post["target_carbs_g"] = targetCarbs }
        if let targetFat { post["target_fat_g"] = targetFat }
        if let meals = (plan["meals_per_day"] as? NSNumber)?.intValue { post["meals_per_day"] = meals }

        return JasperDietGenResult(
            generated: (body["generated"] as? Bool) ?? true,
            saved: (body["saved"] as? Bool) ?? false,
            planName: name,
            goal: goal,
            preference: preference,
            targetCalories: targetCalories,
            targetProtein: targetProtein,
            targetCarbs: targetCarbs,
            targetFat: targetFat,
            groceryItemCount: groceryCount,
            days: days,
            clientID: clientID,
            postBody: post)
    }
}

// MARK: - Own-token API (rides the stored jc_ Connect token)

extension JasperConnectClient {
    /// GET /v1/grocery_list — the SAME checklist state Jasper renders in-app.
    func sharedGroceryList(planID: String? = nil) async throws -> JasperSharedGrocery? {
        var query: [URLQueryItem] = []
        if let planID { query.append(URLQueryItem(name: "plan_id", value: planID)) }
        let data = try await dataRequest(path: "/v1/grocery_list", query: query,
                                         method: "GET", payload: nil)
        return JasperSharedGrocery.parse(data)
    }

    /// POST /v1/grocery_list — checks converge in Jasper within the same state.
    func setGroceryChecks(planID: String?, changes: [(id: String, checked: Bool)]) async throws {
        guard !changes.isEmpty else { return }
        var body: [String: Any] = [
            "items": changes.map { ["id": $0.id, "checked": $0.checked] as [String: Any] },
        ]
        if let planID { body["plan_id"] = planID }
        _ = try await dataRequest(path: "/v1/grocery_list", method: "POST", payload: body)
    }

    /// GET /v1/recipes — the user's saved recipe library (one shared object
    /// with Jasper's Nutrition → Recipes).
    func recipeLibrary() async throws -> [JasperRecipe] {
        let data = try await read("recipes", limit: 100)
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let rows = (body?["data"] as? [[String: Any]]) ?? []
        return rows.compactMap { JasperRecipe.parse(row: $0) }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    /// POST /v1/recipes — appears in Jasper under Nutrition → Recipes
    /// instantly; per-serving macros computed server-side; upsert by client_id.
    @discardableResult
    func saveRecipe(_ draft: JasperRecipeDraft) async throws -> String {
        let body = draft.postBody()
        let receipt = try await post("recipes", body)
        return receipt.clientID ?? (body["client_id"] as? String) ?? ""
    }

    /// DELETE /v1/<resource>?id=… on the own token (recipes, water rows).
    func deleteRow(resource: String, id: String) async throws {
        _ = try await dataRequest(path: "/v1/\(resource)",
                                  query: [URLQueryItem(name: "id", value: id)],
                                  method: "DELETE", payload: nil)
    }

    /// POST /v1/diet_plans/generate on the OWN token — Jasper's generator
    /// writing into the user's own Jasper. 15-60s; generous timeout.
    func generateOwnDietPlan(_ request: JasperDietGenRequest) async throws -> JasperDietGenResult {
        let data = try await dataRequest(path: "/v1/diet_plans/generate", method: "POST",
                                         payload: request.body(), timeout: 150)
        guard let result = JasperDietGenResult.parse(data) else {
            throw JasperConnectError.server("Jasper generated a plan but the answer didn't parse — try again.")
        }
        return result
    }
}
