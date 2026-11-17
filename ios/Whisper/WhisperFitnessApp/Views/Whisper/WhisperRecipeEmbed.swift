import SwiftUI

/// Recipe card sent via `/recipe <dish>` slash command. Jasper generates
/// the recipe via `EmberWebSearchService.searchRecipe` and packs the
/// summary + ingredients + steps + macro estimate into a DM embed.
nonisolated enum WhisperRecipeEmbed {
    static let prefix = "::whisper-recipe-v1::"

    nonisolated struct Payload: Codable, Sendable, Hashable, Identifiable {
        let id: String
        let title: String
        let summary: String
        let prepTime: String?
        let cookTime: String?
        let servings: Int?
        let ingredients: [String]
        let steps: [String]
        let calories: Int?
        let protein: Double?
        let carbs: Double?
        let fat: Double?
    }

    nonisolated static func encode(_ p: Payload) -> String {
        guard let data = try? JSONEncoder().encode(p),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return prefix + json
    }

    nonisolated static func decode(_ body: String) -> Payload? {
        guard body.hasPrefix(prefix) else { return nil }
        let json = String(body.dropFirst(prefix.count))
        guard let data = json.data(using: .utf8),
              let p = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return p
    }
}

struct WhisperRecipeInlineCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let payload: WhisperRecipeEmbed.Payload
    let mine: Bool
    var onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "fork.knife")
                            .font(.caption.weight(.bold))
                        Text(payload.title)
                            .font(.subheadline.weight(.bold))
                            .lineLimit(2)
                    }
                    Text(payload.summary)
                        .font(.caption)
                        .lineLimit(3)
                        .opacity(0.85)
                    HStack(spacing: 6) {
                        if let t = payload.totalTimeLabel {
                            chip(icon: "clock", text: t)
                        }
                        if let s = payload.servings {
                            chip(icon: "person.2.fill", text: "\(s) servings")
                        }
                        if let cal = payload.calories {
                            chip(icon: "flame.fill", text: "\(cal) cal")
                        }
                    }
                    Text("Tap to view recipe")
                        .font(.caption2.weight(.bold))
                        .opacity(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            WhisperRecipeSaveButton(payload: payload, compact: true)
                .background((mine ? Color.white : Color.black).opacity(0.10), in: Capsule())
        }
        .padding(14)
        .frame(width: 260, alignment: .leading)
        .foregroundStyle(mine ? WhisperTheme.surface(colorScheme) : WhisperTheme.ink(colorScheme))
        .background(
            mine ? WhisperTheme.ink(colorScheme) : WhisperTheme.card(colorScheme),
            in: .rect(cornerRadius: 18)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(mine ? Color.clear : WhisperTheme.hairline(colorScheme), lineWidth: 1)
        }
    }

    private func chip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2.weight(.bold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((mine ? Color.white : Color.black).opacity(0.08), in: Capsule())
    }
}

extension WhisperRecipeEmbed.Payload {
    var totalTimeLabel: String? {
        switch (prepTime, cookTime) {
        case (let p?, let c?): return "\(p) + \(c)"
        case (let p?, nil):    return p
        case (nil, let c?):    return c
        default:               return nil
        }
    }
}

struct WhisperRecipeDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let payload: WhisperRecipeEmbed.Payload
    /// Optional hook so the DM thread can send the recipe's ingredients
    /// back into the chat as a collaborative grocery list embed.
    var onAddToGroceryList: (([String]) -> Void)?

    @State private var logged = false
    @State private var groceryAdded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(payload.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                    Text(payload.summary)
                        .font(.subheadline)
                        .foregroundStyle(WhisperTheme.muted(colorScheme))

                    if payload.calories != nil || payload.protein != nil {
                        macroRow
                    }

                    if !payload.ingredients.isEmpty {
                        section(title: "Ingredients") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(payload.ingredients, id: \.self) { line in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("•").foregroundStyle(WhisperTheme.muted(colorScheme))
                                        Text(line)
                                            .font(.subheadline)
                                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                                    }
                                }
                            }
                        }
                    }

                    if !payload.steps.isEmpty {
                        section(title: "Steps") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(payload.steps.enumerated()), id: \.offset) { idx, step in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("\(idx + 1).")
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(WhisperTheme.muted(colorScheme))
                                        Text(step)
                                            .font(.subheadline)
                                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                                    }
                                }
                            }
                        }
                    }

                    if let cal = payload.calories, cal > 0 {
                        Button {
                            Haptics.success()
                            let food = FoodItem(
                                name: payload.title,
                                brand: "Recipe via Jasper",
                                calories: cal,
                                protein: payload.protein ?? 0,
                                carbs: payload.carbs ?? 0,
                                fat: payload.fat ?? 0,
                                mealType: defaultMeal(),
                                timestamp: Date(),
                                icon: "fork.knife"
                            )
                            NutritionStore.shared.addMeal(food)
                            Task { await NutritionStore.shared.refreshFromWhisper() }
                            withAnimation(.spring(response: 0.3)) { logged = true }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: logged ? "checkmark" : "plus")
                                Text(logged ? "Logged to Whisper" : "Log to my macros")
                                    .font(.subheadline.weight(.bold))
                            }
                            .foregroundStyle(WhisperTheme.surface(colorScheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(logged ? Color.green : WhisperTheme.ink(colorScheme), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(logged)
                    }

                    if !payload.ingredients.isEmpty, let onAddToGroceryList {
                        Button {
                            Haptics.success()
                            onAddToGroceryList(payload.ingredients)
                            withAnimation(.spring(response: 0.3)) { groceryAdded = true }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: groceryAdded ? "checkmark" : "cart.badge.plus")
                                Text(groceryAdded ? "Sent to chat" : "Add to grocery list")
                                    .font(.subheadline.weight(.bold))
                            }
                            .foregroundStyle(WhisperTheme.ink(colorScheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(WhisperTheme.card(colorScheme), in: Capsule())
                            .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                        .disabled(groceryAdded)
                    }

                    WhisperRecipeSaveButton(payload: payload)
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                        .background(WhisperTheme.card(colorScheme), in: Capsule())
                        .overlay { Capsule().strokeBorder(WhisperTheme.hairline(colorScheme), lineWidth: 1) }
                }
                .padding(20)
            }
            .background(WhisperTheme.surface(colorScheme))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(WhisperTheme.ink(colorScheme))
                }
            }
        }
    }

    private var macroRow: some View {
        HStack(spacing: 8) {
            if let c = payload.calories { tag("\(c) cal", "flame.fill", .orange) }
            if let p = payload.protein { tag("\(Int(p))p", "bolt.fill", .red) }
            if let c = payload.carbs   { tag("\(Int(c))c", "leaf.fill", .yellow) }
            if let f = payload.fat     { tag("\(Int(f))f", "drop.fill", .blue) }
        }
    }

    private func tag(_ text: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption.weight(.bold))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(color.opacity(0.12), in: Capsule())
        .foregroundStyle(color)
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(WhisperTheme.ink(colorScheme))
            content()
        }
    }

    private func defaultMeal() -> MealType {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 4..<10:  return .breakfast
        case 10..<15: return .lunch
        case 15..<21: return .dinner
        default:      return .snack
        }
    }
}
