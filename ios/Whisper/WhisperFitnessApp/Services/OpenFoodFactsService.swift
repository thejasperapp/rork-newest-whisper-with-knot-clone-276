import Foundation

nonisolated final class OpenFoodFactsService: Sendable {
    static let shared = OpenFoodFactsService()

    func fetchProduct(barcode: String) async throws -> FoodItem? {
        let urlString = "https://world.openfoodfacts.org/api/v2/product/\(barcode).json"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("WhisperFitnessApp/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }

        let decoded = try JSONDecoder().decode(OpenFoodFactsResponse.self, from: data)
        guard let product = decoded.product, decoded.status == 1 else { return nil }

        let hasServingData = product.nutriments?.energy_kcal_serving != nil
        let servingQty = product.serving_quantity ?? 100.0
        let servingUnit = parseServingUnit(product.serving_size)
        let servingSizeValue = parseServingSize(product.serving_size) ?? servingQty

        let calories: Int
        let protein: Double
        let carbs: Double
        let fat: Double
        let fiber: Double
        let sugar: Double
        let sodium: Double

        if hasServingData, let n = product.nutriments {
            calories = Int(n.energy_kcal_serving ?? 0)
            protein = n.proteins_serving ?? 0
            carbs = n.carbohydrates_serving ?? 0
            fat = n.fat_serving ?? 0
            fiber = n.fiber_serving ?? 0
            sugar = n.sugars_serving ?? 0
            sodium = (n.sodium_serving ?? 0) * 1000
        } else if let n = product.nutriments {
            let factor = servingQty / 100.0
            calories = Int((n.energy_kcal_100g ?? 0) * factor)
            protein = (n.proteins_100g ?? 0) * factor
            carbs = (n.carbohydrates_100g ?? 0) * factor
            fat = (n.fat_100g ?? 0) * factor
            fiber = (n.fiber_100g ?? 0) * factor
            sugar = (n.sugars_100g ?? 0) * factor
            sodium = (n.sodium_100g ?? 0) * factor * 1000
        } else {
            return nil
        }

        return FoodItem(
            name: product.product_name ?? "Unknown Product",
            brand: product.brands ?? "",
            barcode: barcode,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: fiber,
            sugar: sugar,
            sodium: sodium,
            servingSize: servingSizeValue,
            servingUnit: servingUnit,
            numberOfServings: 1,
            mealType: suggestMealType()
        )
    }

    private func parseServingSize(_ serving: String?) -> Double? {
        guard let serving else { return nil }
        let pattern = /(\d+\.?\d*)/
        if let match = serving.firstMatch(of: pattern) {
            return Double(match.1)
        }
        return nil
    }

    private func parseServingUnit(_ serving: String?) -> String {
        guard let serving else { return "g" }
        let lowered = serving.lowercased()
        if lowered.contains("ml") { return "ml" }
        if lowered.contains("oz") { return "oz" }
        if lowered.contains("cup") { return "cup" }
        if lowered.contains("tbsp") { return "tbsp" }
        if lowered.contains("piece") { return "piece" }
        return "g"
    }

    private func suggestMealType() -> MealType {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return .breakfast
        case 11..<15: return .lunch
        case 15..<17: return .snack
        default: return .dinner
        }
    }
}
