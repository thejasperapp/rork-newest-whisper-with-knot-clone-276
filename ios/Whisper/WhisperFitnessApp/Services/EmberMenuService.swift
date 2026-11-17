import Foundation

/// Per-viewer menu generator for the Whisper map embed. Given a restaurant
/// reference (name + optional category + optional city), produces a list of
/// `MenuEntry` items ranked by the viewer's *remaining* daily macros from
/// `NutritionStore.shared`.
///
/// Resolution pipeline:
///   1. **Chain table** — a small hard-coded catalogue of the most common
///      US/UK chains (Chipotle, CAVA, Sweetgreen, Shake Shack, Chick-fil-A,
///      Starbucks, Panera, McDonald's, Subway, Taco Bell, etc.). Hits the
///      cache fastest and is always offline-safe.
///   2. **OpenAI web-grounded fetch** — for unknown / independent places,
///      queries `gpt-4o` with the place name + city for ~6 popular menu
///      items + macro estimates, returned as strict JSON.
///   3. **Cache** — keyed by `placeKey + dayKey` so the same restaurant
///      isn't re-billed within the same calendar day across viewers.
///
/// All ranking happens *after* the fetch, on-device, against the viewer's
/// own goals — so the same restaurant shows different items to different
/// users depending on what they have left for the day.
@MainActor
final class EmberMenuService {
    static let shared = EmberMenuService()

    /// In-memory cache keyed by "<placeKey>:<yyyy-MM-dd>".
    private var cache: [String: [MenuEntry]] = [:]
    private var inflight: [String: Task<[MenuEntry], Never>] = [:]

    private init() {}

    nonisolated struct MenuEntry: Codable, Sendable, Hashable, Identifiable {
        let id: String
        let name: String
        let calories: Int
        let protein: Double
        let carbs: Double
        let fat: Double
        /// Short tagline ("Lean + high protein", "Indulgent", "Light snack").
        let tag: String?

        nonisolated init(id: String = UUID().uuidString,
                         name: String,
                         calories: Int,
                         protein: Double,
                         carbs: Double,
                         fat: Double,
                         tag: String? = nil) {
            self.id = id
            self.name = name
            self.calories = calories
            self.protein = protein
            self.carbs = carbs
            self.fat = fat
            self.tag = tag
        }
    }

    // MARK: - Public

    func menu(for placeName: String, category: String?, city: String?) async -> [MenuEntry] {
        let key = cacheKey(placeName)
        if let hit = cache[key] { return hit }
        if let task = inflight[key] { return await task.value }

        let task = Task { [placeName, category, city] () -> [MenuEntry] in
            // 1. Chain table hit first.
            if let chain = Self.chainMenu(for: placeName) {
                return chain
            }
            // 2. Web-grounded OpenAI fetch.
            if let fetched = try? await Self.fetchFromOpenAI(name: placeName, category: category, city: city) {
                return fetched
            }
            // 3. Generic healthy fallback.
            return Self.genericFallback()
        }
        inflight[key] = task
        let result = await task.value
        inflight.removeValue(forKey: key)
        cache[key] = result
        return result
    }

    /// Macro-aware filter and ranking applied to a menu for a specific viewer.
    nonisolated static func rank(_ menu: [MenuEntry], filter: MenuFilter, remaining: RemainingMacros) -> [MenuEntry] {
        let filtered: [MenuEntry] = menu.filter { item in
            switch filter {
            case .all:        return true
            case .highProtein: return item.protein >= 25
            case .lowCal:     return item.calories <= 500
            case .lowCarb:    return item.carbs <= 30
            }
        }
        // Score: items that fit within remaining macros score lower (better).
        // Penalize overshoots; reward high protein when protein is the biggest gap.
        let proteinGap = remaining.protein
        let calGap = Double(remaining.calories)
        return filtered.sorted { a, b in
            score(a, proteinGap: proteinGap, calGap: calGap) < score(b, proteinGap: proteinGap, calGap: calGap)
        }
    }

    nonisolated private static func score(_ item: MenuEntry, proteinGap: Double, calGap: Double) -> Double {
        // Distance from "remaining" — but never reward going way over.
        let calOver = max(0, Double(item.calories) - calGap) * 1.4
        let proteinShort = max(0, proteinGap - item.protein) * 1.6
        // Slight bias to higher protein in general.
        let proteinBonus = -item.protein * 0.4
        return calOver + proteinShort + proteinBonus
    }

    nonisolated enum MenuFilter: String, CaseIterable, Sendable {
        case all, highProtein, lowCal, lowCarb

        var label: String {
            switch self {
            case .all:         return "Best fit"
            case .highProtein: return "High protein"
            case .lowCal:      return "Low cal"
            case .lowCarb:     return "Low carb"
            }
        }

        var icon: String {
            switch self {
            case .all:         return "sparkles"
            case .highProtein: return "bolt.fill"
            case .lowCal:      return "flame"
            case .lowCarb:     return "leaf"
            }
        }
    }

    nonisolated struct RemainingMacros: Sendable {
        let calories: Int
        let protein: Double
        let carbs: Double
        let fat: Double
    }

    // MARK: - Cache key

    nonisolated private func cacheKey(_ placeName: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let day = f.string(from: Date())
        return "\(placeName.lowercased()):\(day)"
    }

    // MARK: - Chain table

    nonisolated private static func chainMenu(for name: String) -> [MenuEntry]? {
        let lower = name.lowercased()
        if lower.contains("chipotle") {
            return [
                .init(name: "Chicken Burrito Bowl",     calories: 625, protein: 45, carbs: 70, fat: 18, tag: "High protein"),
                .init(name: "Steak Salad Bowl",          calories: 560, protein: 40, carbs: 35, fat: 22, tag: "Low carb"),
                .init(name: "Sofritas Bowl (no rice)",   calories: 410, protein: 18, carbs: 38, fat: 16, tag: "Light"),
                .init(name: "Chicken Quesadilla",        calories: 1100, protein: 55, carbs: 95, fat: 55, tag: "Indulgent"),
                .init(name: "Veggie Tacos (3)",          calories: 480, protein: 18, carbs: 65, fat: 14, tag: "Plant-based")
            ]
        }
        if lower.contains("sweetgreen") {
            return [
                .init(name: "Harvest Bowl",              calories: 705, protein: 35, carbs: 85, fat: 25, tag: "Balanced"),
                .init(name: "Chicken Pesto Parm",        calories: 690, protein: 41, carbs: 47, fat: 36, tag: "High protein"),
                .init(name: "Shroomami",                 calories: 615, protein: 21, carbs: 78, fat: 22, tag: "Plant-based"),
                .init(name: "Guacamole Greens",          calories: 540, protein: 16, carbs: 38, fat: 32, tag: "Veggie"),
                .init(name: "Hummus Crunch (no pita)",   calories: 460, protein: 19, carbs: 42, fat: 18, tag: "Light")
            ]
        }
        if lower.contains("cava") {
            return [
                .init(name: "Greens + Grains Bowl",      calories: 540, protein: 30, carbs: 58, fat: 18, tag: "Balanced"),
                .init(name: "Lentil Avocado Bowl",       calories: 620, protein: 22, carbs: 70, fat: 24, tag: "Plant-based"),
                .init(name: "Spicy Lamb Pita",           calories: 780, protein: 38, carbs: 72, fat: 32, tag: "Indulgent"),
                .init(name: "Falafel Salad",             calories: 480, protein: 18, carbs: 38, fat: 22, tag: "Veggie"),
                .init(name: "Chicken Power Bowl",        calories: 560, protein: 44, carbs: 35, fat: 18, tag: "High protein")
            ]
        }
        if lower.contains("shake shack") || lower.contains("shakeshack") {
            return [
                .init(name: "Single ShackBurger",        calories: 560, protein: 30, carbs: 36, fat: 32, tag: "Indulgent"),
                .init(name: "Chicken Shack",             calories: 540, protein: 32, carbs: 45, fat: 25, tag: "Classic"),
                .init(name: "Hamburger",                 calories: 440, protein: 26, carbs: 33, fat: 23, tag: "Lighter"),
                .init(name: "Crispy Chicken Bites (6)",  calories: 410, protein: 28, carbs: 25, fat: 22, tag: "High protein"),
                .init(name: "Side of Fries",             calories: 470, protein: 6,  carbs: 56, fat: 24, tag: "Treat")
            ]
        }
        if lower.contains("chick-fil-a") || lower.contains("chick fil a") || lower.contains("chickfila") {
            return [
                .init(name: "Grilled Chicken Sandwich",  calories: 390, protein: 28, carbs: 44, fat: 11, tag: "Lean"),
                .init(name: "Spicy Deluxe Sandwich",     calories: 550, protein: 30, carbs: 45, fat: 27, tag: "Indulgent"),
                .init(name: "Grilled Nuggets (8ct)",     calories: 140, protein: 25, carbs: 1,  fat: 3,  tag: "High protein"),
                .init(name: "Cobb Salad (grilled)",      calories: 520, protein: 41, carbs: 27, fat: 27, tag: "Balanced"),
                .init(name: "Market Salad (grilled)",    calories: 330, protein: 26, carbs: 22, fat: 14, tag: "Light")
            ]
        }
        if lower.contains("starbucks") {
            return [
                .init(name: "Egg White & Pepper Bites",  calories: 170, protein: 13, carbs: 11, fat: 8,  tag: "Light"),
                .init(name: "Spinach Feta Wrap",         calories: 290, protein: 14, carbs: 33, fat: 10, tag: "Balanced"),
                .init(name: "Turkey Bacon Sandwich",     calories: 230, protein: 17, carbs: 28, fat: 5,  tag: "Lean"),
                .init(name: "Bacon Gouda Sandwich",      calories: 360, protein: 17, carbs: 31, fat: 18, tag: "Indulgent"),
                .init(name: "Protein Box (eggs)",        calories: 460, protein: 23, carbs: 40, fat: 25, tag: "High protein")
            ]
        }
        if lower.contains("panera") {
            return [
                .init(name: "Green Goddess Cobb",        calories: 530, protein: 41, carbs: 24, fat: 31, tag: "High protein"),
                .init(name: "Modern Greek Salad",        calories: 380, protein: 28, carbs: 18, fat: 22, tag: "Low carb"),
                .init(name: "Mediterranean Bowl",        calories: 560, protein: 18, carbs: 71, fat: 22, tag: "Plant-based"),
                .init(name: "Chicken Avocado Sandwich",  calories: 720, protein: 41, carbs: 56, fat: 34, tag: "Hearty"),
                .init(name: "Broccoli Cheddar Soup",     calories: 360, protein: 12, carbs: 30, fat: 22, tag: "Comfort")
            ]
        }
        if lower.contains("mcdonald") {
            return [
                .init(name: "Egg McMuffin",              calories: 310, protein: 17, carbs: 30, fat: 13, tag: "Lighter"),
                .init(name: "Big Mac",                   calories: 590, protein: 25, carbs: 46, fat: 33, tag: "Indulgent"),
                .init(name: "McDouble",                  calories: 400, protein: 22, carbs: 33, fat: 20, tag: "Classic"),
                .init(name: "Grilled Chicken McWrap",    calories: 360, protein: 30, carbs: 38, fat: 11, tag: "High protein"),
                .init(name: "Side Salad",                calories: 15,  protein: 1,  carbs: 3,  fat: 0,  tag: "Light")
            ]
        }
        if lower.contains("subway") {
            return [
                .init(name: "Turkey 6\" on Wheat",       calories: 280, protein: 19, carbs: 41, fat: 4,  tag: "Lean"),
                .init(name: "Rotisserie Chicken 6\"",    calories: 350, protein: 29, carbs: 45, fat: 6,  tag: "High protein"),
                .init(name: "Steak & Cheese 6\"",        calories: 380, protein: 24, carbs: 41, fat: 12, tag: "Hearty"),
                .init(name: "Veggie Delite 6\"",         calories: 230, protein: 9,  carbs: 44, fat: 3,  tag: "Light"),
                .init(name: "Tuna Salad 6\"",            calories: 470, protein: 19, carbs: 40, fat: 25, tag: "Filling")
            ]
        }
        if lower.contains("taco bell") {
            return [
                .init(name: "Power Menu Bowl (chicken)", calories: 470, protein: 27, carbs: 50, fat: 18, tag: "Balanced"),
                .init(name: "Crunchwrap Supreme",        calories: 530, protein: 16, carbs: 71, fat: 21, tag: "Indulgent"),
                .init(name: "Soft Taco (beef)",          calories: 180, protein: 9,  carbs: 17, fat: 8,  tag: "Light"),
                .init(name: "Black Bean Quesarito",      calories: 620, protein: 18, carbs: 78, fat: 26, tag: "Plant-based"),
                .init(name: "Chalupa Supreme (chicken)", calories: 360, protein: 16, carbs: 30, fat: 19, tag: "Classic")
            ]
        }
        return nil
    }

    nonisolated private static func genericFallback() -> [MenuEntry] {
        [
            .init(name: "Grilled Chicken Plate",   calories: 540, protein: 42, carbs: 48, fat: 18, tag: "High protein"),
            .init(name: "Salmon Bowl",              calories: 620, protein: 36, carbs: 52, fat: 24, tag: "Balanced"),
            .init(name: "House Salad + Protein",    calories: 420, protein: 30, carbs: 22, fat: 20, tag: "Low carb"),
            .init(name: "Veggie Wrap",              calories: 460, protein: 16, carbs: 62, fat: 14, tag: "Plant-based"),
            .init(name: "Pasta of the Day",         calories: 720, protein: 24, carbs: 92, fat: 22, tag: "Indulgent")
        ]
    }

    // MARK: - OpenAI fetch

    nonisolated private static func fetchFromOpenAI(name: String, category: String?, city: String?) async throws -> [MenuEntry] {
        guard RorkAIProxy.isConfigured else { throw URLError(.userAuthenticationRequired) }

        let where_ = city.flatMap { $0.isEmpty ? nil : $0 } ?? "the user's city"
        let cat = category ?? "restaurant"
        let prompt = """
        List six of the most-ordered menu items at "\(name)" (a \(cat) near \(where_)).
        For each item, estimate calories, protein (g), carbs (g), fat (g) for a typical full portion.
        Add a 1-2 word "tag" describing the dietary vibe ("Lean", "High protein", "Indulgent", "Plant-based", "Low carb", "Balanced").
        Respond ONLY with a JSON object (no markdown), shape:
        { "items": [ { "name": "...", "calories": 600, "protein": 35, "carbs": 50, "fat": 22, "tag": "Balanced" } ] }
        """
        var request = RorkAIProxy.chatRequest(timeout: 25)

        let body = OpenAIChatRequest(
            model: RorkAIProxy.chatModel,
            messages: [
                OpenAIChatMessage(role: "system", content: "You are Knot, a fitness coach with deep knowledge of restaurant menus. Return strict JSON only."),
                OpenAIChatMessage(role: "user", content: prompt)
            ],
            max_tokens: 800
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = decoded.choices?.first?.message.content else {
            throw URLError(.zeroByteResource)
        }

        var cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let s = cleaned.firstIndex(of: "{"), let e = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[s...e])
        }
        guard let json = cleaned.data(using: .utf8) else { throw URLError(.cannotDecodeContentData) }

        struct Wrap: Codable { let items: [Item]? }
        struct Item: Codable {
            let name: String?
            let calories: Int?
            let protein: Double?
            let carbs: Double?
            let fat: Double?
            let tag: String?
        }
        let wrap = try JSONDecoder().decode(Wrap.self, from: json)
        let items = (wrap.items ?? []).compactMap { i -> MenuEntry? in
            guard let n = i.name, !n.isEmpty else { return nil }
            return MenuEntry(
                name: n,
                calories: i.calories ?? 0,
                protein: i.protein ?? 0,
                carbs: i.carbs ?? 0,
                fat: i.fat ?? 0,
                tag: i.tag
            )
        }
        return items.isEmpty ? genericFallback() : items
    }
}
