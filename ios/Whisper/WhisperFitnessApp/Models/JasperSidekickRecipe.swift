import Foundation

/// Saved Sidekick prompts. Each runs through the same consented, cited `/ask` route; nothing bypasses scope approval.
nonisolated struct JasperSidekickRecipe: Identifiable, Sendable, Hashable {
    enum Scope: Sendable { case meeting, library }

    let id: String
    let title: String
    let hint: String
    let question: String
    let scope: Scope
    /// Runs the bounded transcript scan instead of an ordinary question.
    var isScan: Bool = false

    static let all: [JasperSidekickRecipe] = [
        JasperSidekickRecipe(id: "catch-up", title: "What did I miss?", hint: "Catch up on the conversation so far", question: "Catch me up on this meeting so far. What matters now? Distinguish decisions from proposals.", scope: .meeting),
        JasperSidekickRecipe(id: "decisions", title: "Decisions so far", hint: "What was decided vs. still open", question: "Which decisions were actually made so far, and which questions remain open?", scope: .meeting),
        JasperSidekickRecipe(id: "sound-smart", title: "Make me sound smart", hint: "Two thoughtful contributions", question: "Suggest two concise, thoughtful contributions I could make right now, grounded in what has been discussed. Distinguish supported facts from suggestions.", scope: .meeting),
        JasperSidekickRecipe(id: "suggest-questions", title: "Suggest questions", hint: "Follow-ups worth asking", question: "Suggest three useful follow-up questions I could ask, grounded in unresolved points so far. Label them as questions, not meeting facts.", scope: .meeting),
        JasperSidekickRecipe(id: "explain", title: "Explain the jargon", hint: "Terms and concepts, briefly", question: "Briefly explain any technical terms, acronyms or concepts mentioned in this meeting that someone might not know. Keep meeting facts cited and general explanations labeled.", scope: .meeting),
        JasperSidekickRecipe(id: "next-steps", title: "Recap next steps", hint: "Draft follow-ups for review", question: "Recap the next steps discussed so far as drafts for review. Do not invent an owner or a due date.", scope: .meeting),
        JasperSidekickRecipe(id: "follow-up-email", title: "Draft follow-up email", hint: "Short, cited, ready to review", question: "Draft a short follow-up email summarizing the decisions and next steps from this meeting for my review. Cite the discussion and do not invent owners, dates or commitments.", scope: .meeting),
        JasperSidekickRecipe(id: "organize", title: "Organize transcript", hint: "Highlights, decisions, key numbers", question: "Organize this meeting’s transcript and highlight the decisions, key numbers and follow-ups using my focus preferences.", scope: .meeting, isScan: true),
        JasperSidekickRecipe(id: "recent", title: "Summarize my recent meetings", hint: "Decisions, open questions, follow-ups", question: "Summarize my recent meetings: the main decisions, open questions and follow-ups, with dates.", scope: .library),
        JasperSidekickRecipe(id: "open-loops", title: "Find my open follow-ups", hint: "Commitments without a close", question: "Which follow-ups and commitments from my meetings still look open? Cite where each came from and do not assume anything was completed.", scope: .library),
        JasperSidekickRecipe(id: "changed", title: "What's changed?", hint: "Compare across meetings over time", question: "What changed or conflicts across these meetings over time? Use source dates and do not invent consensus.", scope: .library),
    ]

    static func recipes(forMeeting meeting: Bool) -> [JasperSidekickRecipe] {
        all.filter { $0.scope == (meeting ? .meeting : .library) }
    }
}
