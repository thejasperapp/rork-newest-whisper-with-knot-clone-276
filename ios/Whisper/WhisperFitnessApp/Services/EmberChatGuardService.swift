import Foundation

/// Verdict returned by the Jasper chat-safety classifier. Always nonisolated
/// so it can be passed across actor boundaries (e.g. from a background URL
/// session task into the main-actor strike pipeline).
nonisolated struct WhisperSafetyVerdict: Sendable {
    let severity: WhisperSafetySeverity
    let category: WhisperSafetyCategory
    let reasoning: String

    static let safe = WhisperSafetyVerdict(severity: .none, category: .other, reasoning: "")
}

/// Silent server-side-feel classifier for outbound DMs that cross an
/// adult ↔ minor (3+ year) boundary. Calls GPT-4o-mini with a strict
/// schema so we get back a single typed verdict instead of free-form text.
///
/// IMPORTANT: this is never invoked for adult ↔ adult or teen ↔ teen
/// messages — `WhisperSafetyService.shouldScan(senderUserID:recipientUserID:)`
/// gates every call. The model is told it's looking at a cross-boundary
/// conversation so it can be appropriately conservative.
nonisolated struct EmberChatGuardService: Sendable {

    /// Classifies a single outbound message. Returns `.safe` on any error so
    /// network blips never block the send pipeline.
    func classify(message: String, senderIsAdult: Bool, recipientIsTeen: Bool) async -> WhisperSafetyVerdict {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .safe }
        guard RorkAIProxy.isConfigured else { return .safe }

        let direction = (senderIsAdult && recipientIsTeen)
            ? "an ADULT (18+) writing to a TEEN (under 18)"
            : "a TEEN (under 18) writing to an ADULT (18+)"

        let systemPrompt = """
        You are Jasper's minor-safety classifier inside the Whisper fitness app's DM channel. \
        The message you're reading is \(direction). \
        Classify it for risk to the minor only. Be conservative — when in doubt, flag low.
        Respond with a JSON object matching this exact schema, nothing else:
        {
          "severity": "none" | "low" | "medium" | "high",
          "category": "grooming" | "sexual" | "meetup" | "personalInfo" | "hostile" | "other",
          "reasoning": "<one short sentence, max 200 chars>"
        }
        Severity guide:
        - none: ordinary fitness / social chat
        - low: mildly inappropriate familiarity, off-platform nudging
        - medium: sexual undertone, pushing for personal info / school / address, isolating language
        - high: explicit sexual content, requests for nudes, real-world meetup, grooming patterns
        Never include any extra prose — JSON only.
        """

        var request = RorkAIProxy.chatRequest(timeout: 20)

        let body: [String: Any] = [
            "model": RorkAIProxy.miniChatModel,
            "temperature": 0,
            "response_format": ["type": "json_object"],
            "max_tokens": 200,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": trimmed]
            ]
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return .safe }
        request.httpBody = payload

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { return .safe }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String,
                  let contentData = content.data(using: .utf8),
                  let parsed = try JSONSerialization.jsonObject(with: contentData) as? [String: Any]
            else { return .safe }

            let sevRaw = (parsed["severity"] as? String) ?? "none"
            let catRaw = (parsed["category"] as? String) ?? "other"
            let reasoning = (parsed["reasoning"] as? String) ?? ""

            let severity = WhisperSafetySeverity(rawValue: sevRaw) ?? .none
            let category = WhisperSafetyCategory(rawValue: catRaw) ?? .other
            return WhisperSafetyVerdict(severity: severity, category: category, reasoning: reasoning)
        } catch {
            return .safe
        }
    }
}
