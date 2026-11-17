import Foundation
import Supabase

struct EmberWebSearchService: Sendable {

    func searchRecipe(for mealName: String, ingredients: [String]) async throws -> EmberRecipeResult {
        let ingredientList = ingredients.isEmpty ? "" : "\nIngredients: \(ingredients.joined(separator: ", "))"

        let prompt = """
        Find a detailed recipe for: "\(mealName)"\(ingredientList)

        Provide:
        1. Step-by-step cooking instructions
        2. Exact ingredient amounts
        3. Prep time and cook time
        4. Any helpful tips
        5. A YouTube search query that would find a good video tutorial for this recipe

        Respond ONLY with a JSON object (no markdown):
        {
          "recipeName": "name",
          "prepTime": "10 min",
          "cookTime": "20 min",
          "totalTime": "30 min",
          "servings": 2,
          "ingredients": ["1 cup rice", "2 chicken breasts"],
          "steps": ["Step 1 description", "Step 2 description"],
          "tips": ["helpful tip"],
          "youtubeSearchQuery": "search query for youtube",
          "summary": "Brief 2 sentence summary of the dish"
        }
        """

        var request = RorkAIProxy.chatRequest(timeout: 30)

        let body = OpenAIChatRequest(
            model: RorkAIProxy.chatModel,
            messages: [
                OpenAIChatMessage(role: "system", content: "You are a professional chef and recipe expert. Provide accurate, detailed recipes with precise measurements. Always respond with valid JSON only."),
                OpenAIChatMessage(role: "user", content: prompt)
            ],
            max_tokens: 1200
        )

        request.httpBody = try JSONEncoder().encode(body)
        let (data, httpResponse) = try await URLSession.shared.data(for: request)

        guard let http = httpResponse as? HTTPURLResponse, http.statusCode == 200 else {
            throw EmberWebSearchError.apiError
        }

        let response = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = response.choices?.first?.message.content, !content.isEmpty else {
            throw EmberWebSearchError.emptyResponse
        }

        var cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let startIdx = cleaned.firstIndex(of: "{"),
           let endIdx = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[startIdx...endIdx])
        }

        guard let jsonData = cleaned.data(using: .utf8) else {
            throw EmberWebSearchError.parseError
        }

        return try JSONDecoder().decode(EmberRecipeResult.self, from: jsonData)
    }

    /// REAL web search via the Whisper backend (/ai/websearch — OpenAI's
    /// hosted web_search tool): genuinely searches + crawls the live web and
    /// returns cited sources. Nil when the route is unreachable so callers
    /// can fall back to the prompted research path.
    func liveWebSearch(query: String) async -> EmberWebResult? {
        struct Payload: Encodable { let query: String }
        struct SourceRow: Decodable { let title: String?; let url: String? }
        struct Body: Decodable { let answer: String?; let sources: [SourceRow]? }
        guard let token = try? await SupabaseService.shared.client.auth.session.accessToken else {
            return nil
        }
        let hosts = await WhisperBillingBackend.hosts
        for host in hosts {
            guard let url = URL(string: "\(host)/ai/websearch") else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 45
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONEncoder().encode(Payload(query: query))
            guard let (data, response) = try? await URLSession.shared.data(for: req),
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let body = try? JSONDecoder().decode(Body.self, from: data) else { continue }
            let answer = (body.answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else { continue }
            let urls = (body.sources ?? []).compactMap { $0.url }.filter { $0.hasPrefix("http") }
            return EmberWebResult(
                answer: answer,
                tldr: nil,
                category: nil,
                youtubeSearchQuery: nil,
                imageSearchQuery: nil,
                relatedTopics: nil,
                sources: urls
            )
        }
        return nil
    }

    func webSearch(query: String) async throws -> EmberWebResult {
        // REAL search first — live crawl with cited sources. The prompted
        // research below survives only as the fallback when the backend
        // route is unreachable.
        if let live = await liveWebSearch(query: query) { return live }

        let prompt = """
        The user is asking: "\(query)"

        Do a DEEP analysis like a research assistant. Cover:
        1. A direct, comprehensive answer (2–6 short paragraphs or a structured breakdown).
        2. Concrete numbers, comparisons, pros/cons, or step-by-step detail where useful.
        3. Any caveats or context the user should know.
        4. Decide if a visual would help (product, place, food, exercise form, gear, brand, dish). If yes, set `imageSearchQuery` to a clean visual search query; otherwise null.
        5. Decide if a video tutorial would help and set `youtubeSearchQuery` accordingly, otherwise null.
        6. REQUIRED: Always include at least 3 real-world, REPUTABLE source URLs from your knowledge (peer-reviewed studies on pubmed.ncbi.nlm.nih.gov, official .gov / .edu / .org sites, or well-known publications like nih.gov, who.int, mayoclinic.org, hsph.harvard.edu, nature.com, sciencedirect.com, examine.com, healthline.com, nytimes.com). Use FULL https URLs. NEVER leave sources empty — if you don't have a specific URL, use the homepage of a reputable source on the topic. 3–5 sources is ideal.
        7. REQUIRED: Always include 3–5 `relatedTopics` — short follow-up questions or topics the user might want to explore next (each <50 chars).
        8. Write a tight 1-sentence `tldr` (max ~180 chars) — what you'd say out loud as a quick spoken summary.
        9. Pick the single best `category` from this fixed list: research, sleep, stress, workout, food, recovery, cycle, wellness, schedule, general.

        Respond ONLY with a JSON object (no markdown):
        {
          "answer": "detailed multi-paragraph response",
          "tldr": "one-sentence spoken summary",
          "category": "research",
          "youtubeSearchQuery": "YouTube query or null",
          "imageSearchQuery": "visual search query or null",
          "relatedTopics": ["topic 1", "topic 2"],
          "sources": ["https://full.url/one", "https://full.url/two"]
        }
        """

        var request = RorkAIProxy.chatRequest(timeout: 30)

        let body = OpenAIChatRequest(
            model: RorkAIProxy.chatModel,
            messages: [
                OpenAIChatMessage(role: "system", content: "You are Knot, a fitness, nutrition, and wellness research assistant. You think deeply, cite reputable sources with full https URLs, and decide on your own when a visual would help. Always respond with valid JSON only."),
                OpenAIChatMessage(role: "user", content: prompt)
            ],
            // Trimmed from 2200 — answers cap comfortably under 900 tokens
            // and every fact-check/web-search call now bills ~60% less.
            max_tokens: 900
        )

        request.httpBody = try JSONEncoder().encode(body)
        let (data, httpResponse) = try await URLSession.shared.data(for: request)

        guard let http = httpResponse as? HTTPURLResponse, http.statusCode == 200 else {
            throw EmberWebSearchError.apiError
        }

        let response = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = response.choices?.first?.message.content, !content.isEmpty else {
            throw EmberWebSearchError.emptyResponse
        }

        var cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let startIdx = cleaned.firstIndex(of: "{"),
           let endIdx = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[startIdx...endIdx])
        }

        guard let jsonData = cleaned.data(using: .utf8) else {
            throw EmberWebSearchError.parseError
        }

        return try JSONDecoder().decode(EmberWebResult.self, from: jsonData)
    }
}

nonisolated struct EmberRecipeResult: Codable, Sendable {
    let recipeName: String?
    let prepTime: String?
    let cookTime: String?
    let totalTime: String?
    let servings: Int?
    let ingredients: [String]?
    let steps: [String]?
    let tips: [String]?
    let youtubeSearchQuery: String?
    let summary: String?
}

nonisolated struct EmberWebResult: Codable, Sendable {
    let answer: String?
    let tldr: String?
    let category: String?
    let youtubeSearchQuery: String?
    let imageSearchQuery: String?
    let relatedTopics: [String]?
    let sources: [String]?
}

nonisolated enum EmberWebSearchError: Error, LocalizedError, Sendable {
    case apiError
    case emptyResponse
    case parseError

    var errorDescription: String? {
        switch self {
        case .apiError: return "Couldn't search right now. Try again."
        case .emptyResponse: return "No results found."
        case .parseError: return "Couldn't read search results."
        }
    }
}
