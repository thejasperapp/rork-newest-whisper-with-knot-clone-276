import Foundation

/// Builds the "Useful follow-ups" chips under a Jasper answer. The brain's
/// own suggestions (parsed from the reply's followups fence) always come
/// first; when it offered too few, smart extras are derived from what THIS
/// exchange actually covered — across ALL of Whisper's surfaces (posting,
/// messaging, meetings, clients, recruiting, communities) plus the Jasper
/// fitness partnership. Whisper is a social app first, so the chips are
/// never fitness-only unless the answer was.
enum WhisperEmberSmartFollowups {

    /// Merges the model's suggestions with derived ones into 2-4 chips.
    static func compose(modelSuggested: [String], replyText: String, userText: String) -> [String] {
        var out: [String] = []
        for s in modelSuggested {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if !out.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                out.append(trimmed)
            }
        }
        if out.count >= 3 { return Array(out.prefix(4)) }
        for candidate in derived(replyText: replyText, userText: userText) {
            guard out.count < 3 else { break }
            if !out.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
                out.append(candidate)
            }
        }
        return Array(out.prefix(4))
    }

    /// Topic-matched suggestions grounded in the exchange's own wording,
    /// ordered social-first. Generic prompts only pad the tail.
    private static func derived(replyText: String, userText: String) -> [String] {
        let hay = (userText + " " + replyText).lowercased()
        var picks: [String] = []

        func add(_ needles: [String], _ suggestions: [String]) {
            guard needles.contains(where: { hay.contains($0) }) else { return }
            picks.append(contentsOf: suggestions)
        }

        add(["post", "caption", "feed", "content", "reel", "creator"],
            ["Draft a post about this", "What should I post this week?"])
        add(["client", "message", "dm", "reply", "check in", "check-in"],
            ["Draft a reply I can send", "How are my clients trending?"])
        add(["meeting", "call", "schedule", "calendar", "invite"],
            ["Schedule a meeting about this", "What's on my calendar?"])
        add(["applicant", "prospect", "recruit", "position", "hire", "candidate"],
            ["Score this prospect for me", "Which position fits them best?"])
        add(["community", "communities", "follow", "friends", "network"],
            ["Who should I follow next?", "Find communities like this"])
        add(["bio age", "biological age"],
            ["How do I lower my bio age?"])
        add(["sleep", "recovery", "readiness", "sore", "rest day", "fatigue"],
            ["Should I train hard today?", "Build me a recovery day"])
        add(["workout", "training", "plan", "exercise", "sets", "reps", "gym"],
            ["Turn this into a weekly plan", "Make it easier on my joints"])
        add(["protein", "meal", "nutrition", "calorie", "diet", "macros"],
            ["Build a simple meal plan", "How much protein do I need?"])

        picks.append(contentsOf: [
            "Make this more specific to me",
            "What should I do next?",
            "Show the data behind that"
        ])
        return picks
    }
}
