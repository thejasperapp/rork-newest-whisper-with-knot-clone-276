import Foundation

/// Jasper's verdict after reviewing a brand's public Instagram presence.
nonisolated struct WhisperEmberBrandVerdict: Sendable {
    let verified: Bool
    let score: Int
    let summary: String
}

nonisolated enum WhisperEmberBrandCheckError: LocalizedError {
    case unavailable
    case failed

    nonisolated var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Jasper isn't available right now — try again later."
        case .failed:
            return "Jasper couldn't finish the review — try again."
        }
    }
}

/// Jasper's brand background check — researches a company's Instagram
/// (tagged posts, creator collabs, real product mentions) through a
/// web-search-grounded model (Perplexity Sonar via the Rork toolkit proxy)
/// so brands can't lie about recruiting creators on social platforms.
enum WhisperEmberBrandCheck {

    private static var toolkitBase: String {
        let raw = Config.EXPO_PUBLIC_TOOLKIT_URL.isEmpty
            ? "https://toolkit.rork.com"
            : Config.EXPO_PUBLIC_TOOLKIT_URL
        var trimmed = raw
        while trimmed.hasSuffix("/") { trimmed = String(trimmed.dropLast()) }
        return trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)"
    }

    private static let systemPrompt = """
    You are Knot, Whisper's safety companion. Your job is to protect creators and athletes from fake sponsor brands.
    You will be given a company name and their claimed Instagram handle. Research the live web:
    1. Does instagram.com/{handle} appear to be a real, active account belonging to this company?
    2. Do real people tag or mention this company's products in posts (tagged posts, creator collaborations, sponsored content, reviews)?
    3. Is there evidence the company genuinely works with creators/athletes on social platforms?
    Be skeptical — a missing or inactive account, no third-party mentions, or a handle that belongs to someone else should fail verification.
    Respond ONLY with a JSON object, no markdown fences, in exactly this shape:
    {"authentic": true or false, "score": 0-100, "summary": "2-3 plain sentences a creator can read"}
    "authentic" is true only when the Instagram presence is real AND there is evidence of genuine product tags/mentions or creator collaborations. "score" is your 0-100 confidence that this brand is safe for creators.
    """

    /// Runs the live Instagram review. Throws a friendly error on failure.
    static func inspect(
        companyName: String,
        instagram: String,
        website: String?
    ) async throws -> WhisperEmberBrandVerdict {
        let secret = Config.allValues["EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY"] ?? ""
        guard !secret.isEmpty,
              let url = URL(string: "\(toolkitBase)/v2/vercel/v1/chat/completions") else {
            throw WhisperEmberBrandCheckError.unavailable
        }

        let handle = instagram
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "@", with: "")
        guard !handle.isEmpty else { throw WhisperEmberBrandCheckError.failed }

        var lines = [
            "Company name: \(companyName.trimmingCharacters(in: .whitespaces))",
            "Claimed Instagram: instagram.com/\(handle)",
        ]
        if let website, !website.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("Website: \(website.trimmingCharacters(in: .whitespaces))")
        }
        lines.append("Research this brand's Instagram presence and tagged posts now, then return the JSON verdict.")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "perplexity/sonar",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": lines.joined(separator: "\n")],
            ],
            "max_tokens": 600,
            "temperature": 0.2,
        ] as [String: Any])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw WhisperEmberBrandCheckError.failed
        }

        guard let verdict = parseVerdict(content) else {
            throw WhisperEmberBrandCheckError.failed
        }
        return verdict
    }

    /// Pulls the first JSON object out of a model reply (tolerates fences).
    private static func parseVerdict(_ raw: String) -> WhisperEmberBrandVerdict? {
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}"),
              start < end else { return nil }
        let jsonSlice = String(raw[start...end])
        guard let data = jsonSlice.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let rawScore = (dict["score"] as? Int)
            ?? Int((dict["score"] as? Double) ?? 0)
        let summary = (dict["summary"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return WhisperEmberBrandVerdict(
            verified: (dict["authentic"] as? Bool) == true,
            score: min(100, max(0, rawScore)),
            summary: summary.isEmpty
                ? "Jasper couldn't summarize this brand's Instagram presence."
                : String(summary.prefix(1200))
        )
    }
}
