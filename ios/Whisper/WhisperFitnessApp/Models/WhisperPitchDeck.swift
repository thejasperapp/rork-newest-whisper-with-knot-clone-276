import Foundation

/// Jasper's recruiter pitch deck — the close plan he drafts while quietly
/// listening to a recruiter–prospect meeting. The JSON shape is shared
/// VERBATIM with the web app (lib/pitchDeck.ts), so decks written by either
/// platform open on both. Stored per (meeting, recruiter) in
/// whisper_meeting_decks (supabase/pitch-decks.sql) with a local cache so
/// the feature works before the migration runs.
nonisolated struct WhisperPitchDeck: Codable, Sendable, Equatable {
    struct Moment: Codable, Sendable, Equatable {
        var quote: String
        var speaker: String
        /// Why the moment matters for the close — the margin note.
        var note: String
        /// interest | objection | signal
        var kind: String
    }

    struct Slide: Codable, Sendable, Equatable {
        var title: String
        var bullets: [String]
    }

    struct Step: Codable, Sendable, Equatable {
        var step: String
        var detail: String
    }

    struct Impact: Codable, Sendable, Equatable {
        var quote: String
        var why: String
    }

    struct NextStep: Codable, Sendable, Equatable {
        var action: String
        var when: String
    }

    struct CloseRate: Codable, Sendable, Equatable {
        var withPlan: Int
        var withoutPlan: Int
        var why: String
    }

    var v: Int?
    var meetingId: String
    var meetingTitle: String
    var prospectName: String
    /// coach | creator | athlete
    var placement: String
    var headline: String
    var interests: [String]
    var keyMoments: [Moment]
    var slides: [Slide]
    var closePlan: [Step]
    var closeRate: CloseRate
    var impactMoments: [Impact]
    var nextSteps: [NextStep]
    /// Epoch milliseconds — matches the web's Date.now() stamp.
    var generatedAt: Double
    var draft: Bool?
    var sample: Bool?

    var placementLabel: String {
        switch placement {
        case "coach": return "Coach lane"
        case "athlete": return "Athlete lane"
        default: return "Creator lane"
        }
    }

    var generatedDate: Date { Date(timeIntervalSince1970: generatedAt / 1000) }
}

extension WhisperPitchDeck {
    /// The sample deck — a realistic close plan for a fictional prospect so
    /// recruiters can read the exact formatting before their first real
    /// meeting deck lands. Identical content to the web sample.
    static let sampleDeck = WhisperPitchDeck(
        v: 1,
        meetingId: "sample",
        meetingTitle: "Intro call — Maya Torres",
        prospectName: "Maya Torres",
        placement: "creator",
        headline: "Own your name while you're still playing — verified, sponsored, and paid from day one.",
        interests: [
            "Growing her volleyball audience past Instagram",
            "Getting paid without feeling like she's selling out",
            "Sponsorships that don't look sketchy",
            "Short content she can film between classes",
            "A coaching lane after graduation",
        ],
        keyMoments: [
            Moment(
                quote: "I have like twelve thousand followers but I've never made a dollar off any of it.",
                speaker: "maya",
                note: "The money gap — WPP pays from real ad spend.",
                kind: "signal"
            ),
            Moment(
                quote: "Brands DM me and I just… don't answer. It feels sketchy.",
                speaker: "maya",
                note: "Escrowed sponsorships remove the sketch.",
                kind: "interest"
            ),
            Moment(
                quote: "I don't want to post cringe. My teammates would roast me.",
                speaker: "maya",
                note: "Objection: brand safety — she keeps her voice.",
                kind: "objection"
            ),
            Moment(
                quote: "Wait — verified athletes actually get discovered by recruiters on here?",
                speaker: "maya",
                note: "She lit up at discovery. Lead with the athlete lane.",
                kind: "signal"
            ),
        ],
        slides: [
            Slide(title: "Why Whisper, why now", bullets: [
                "Verified athlete badge — earned, never bought",
                "Sponsors come to HER through escrowed deals, no sketchy DMs",
                "WPP: real ad dollars shared with creators every month",
            ]),
            Slide(title: "The 30-day runway", bullets: [
                "Week 1: verify + first three posts",
                "Weeks 2–3: two reels a week, teammates cameo",
                "Week 4: first sponsorship pitch with her media kit",
            ]),
        ],
        closePlan: [
            Step(
                step: "Send the athlete-verification link tonight",
                detail: "While the discovery excitement is fresh — she said “actually get discovered?” out loud."
            ),
            Step(
                step: "Intro her to one verified athlete",
                detail: "Social proof kills the “is this sketchy” objection faster than any pitch."
            ),
            Step(
                step: "Set the follow-up for Thursday",
                detail: "She has practice Tuesday and Wednesday — Thursday afternoon is her window."
            ),
            Step(
                step: "Bring one real sponsorship example",
                detail: "Show the escrow flow with numbers, not promises."
            ),
        ],
        closeRate: CloseRate(
            withPlan: 78,
            withoutPlan: 31,
            why: "She has the audience, the drive, and two live buying signals — but the sketchy-brand-DM scar means trust must be built through proof, not pressure. Run the proof-first plan and she signs; wing it and the objection wins."
        ),
        impactMoments: [
            Impact(
                quote: "You'd be verified as an athlete — that badge can't be bought, it's earned.",
                why: "Her posture changed — this reframed Whisper as legitimacy, not another app."
            ),
            Impact(
                quote: "The money doesn't come from posting more. It comes from ad revenue you already generate.",
                why: "Answered the sell-out fear in one line — she repeated it back."
            ),
        ],
        nextSteps: [
            NextStep(action: "DM the verification link + one athlete profile", when: "Tonight"),
            NextStep(action: "Follow-up call", when: "Thursday 4pm"),
            NextStep(action: "Prep the sponsorship walkthrough", when: "Before Thursday"),
        ],
        generatedAt: 1756137600000,
        draft: nil,
        sample: true
    )
}
