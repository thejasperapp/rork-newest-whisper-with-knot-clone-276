import Foundation

extension WhisperRecipeEmbed.Payload {
    /// Card macros are estimates per serving. The same editable prefill is
    /// used from the compact card and expanded recipe, never a meal log.
    var jasperRecipeDraft: JasperRecipeDraft {
        var draft = JasperRecipeDraft()
        draft.name = title
        draft.servings = max(1, servings ?? 2)
        draft.prepTime = prepTime ?? ""
        draft.cookTime = cookTime ?? ""
        draft.note = summary + "\n\nNutrition is estimated per serving. The prefilled total is divided evenly among ingredients, not measured for each ingredient. Review ingredient nutrition before changing quantities or logging."
        draft.steps = steps
        let count = max(1, ingredients.count)
        let servingCount = Double(draft.servings)
        func split(_ perServing: Double?) -> String {
            guard let perServing, perServing.isFinite, perServing > 0 else { return "" }
            return String((perServing * servingCount / Double(count) * 100).rounded() / 100)
        }
        draft.ingredients = ingredients.map { line in
            JasperRecipeDraft.Ingredient(
                name: line, calories: split(calories.map(Double.init)),
                protein: split(protein), carbs: split(carbs), fat: split(fat),
                servingUnit: "item", numberOfServings: "1")
        }
        if draft.ingredients.isEmpty { draft.ingredients = [JasperRecipeDraft.Ingredient()] }
        return draft
    }
}
