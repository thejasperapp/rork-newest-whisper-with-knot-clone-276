import SwiftUI
import Foundation

// MARK: - Presented client payload (wire format shared with web)

/// The client profile a recruiter presents into a meeting. The JSON shape is
/// shared with the web client (camelCase keys), so either platform can present
/// and both render the same phone-shaped card.
nonisolated struct WhisperPresentedClient: Codable, Sendable, Hashable {
    nonisolated struct Application: Codable, Sendable, Hashable {
        var taken: Bool?
        var potentialScore: Double?
        var confidenceScore: Double?
        var bestPosition: String?
        var status: String?
        var submittedAt: String?
    }

    nonisolated struct ContactEntry: Codable, Sendable, Hashable {
        var date: String?
        var method: String?
        var note: String?
    }

    /// One application question/answer pair broadcast with the card.
    nonisolated struct AnswerPair: Codable, Sendable, Hashable {
        var q: String?
        var a: String?
    }

    nonisolated struct SnapshotWorkout: Codable, Sendable, Hashable {
        var type: String?
        var durationMinutes: Double?
        var calories: Double?
        var date: String?
    }

    /// Compact fitness snapshot broadcast with coach-client presentations —
    /// same camelCase wire shape as the web's `PresentedSnapshot`.
    nonisolated struct Snapshot: Codable, Sendable, Hashable {
        var caloriesToday: Double?
        var caloriesGoal: Double?
        var proteinToday: Double?
        var proteinGoal: Double?
        var carbsToday: Double?
        var carbsGoal: Double?
        var fatToday: Double?
        var fatGoal: Double?
        var waterCups: Double?
        var streak: Double?
        var sleepHours: Double?
        var steps: Double?
        var activeMinutes: Double?
        var restingHeartRate: Double?
        var weightLbs: Double?
        var bodyFatPct: Double?
        var workouts: [SnapshotWorkout]?
    }

    var kind: String?
    var id: String
    var username: String?
    var displayName: String?
    var imageUrl: String?
    var status: String?
    var rating: Int?
    var niche: String?
    var location: String?
    var source: String?
    var instagram: String?
    var tiktok: String?
    var suggestedRole: String?
    var notes: String?
    /// Always encoded (even when empty) — the web card indexes into it.
    var contactLog: [ContactEntry]?
    var addedAt: String?
    var application: Application?
    /// The presented person's Whisper user id (for DM/profile actions).
    var userId: String? = nil
    /// The application Q&A itself — recruiters present the application.
    var applicationAnswers: [AnswerPair]? = nil
    /// Public photos — prospect Instagram grid or client progress shots.
    var photos: [String]? = nil
    /// Coach-client live fitness snapshot (macros, activity, workouts).
    var snapshot: Snapshot? = nil
    /// Bumped on every re-broadcast carrying richer data so viewers accept
    /// the enriched payload instead of ignoring it as a heartbeat.
    var rev: Double? = nil
    var presenterUserId: String
    var presenterName: String

    nonisolated static func decode(fromAny dict: [String: Any]) -> WhisperPresentedClient? {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(WhisperPresentedClient.self, from: data)
    }

    nonisolated func encodeToDict() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }
}

// MARK: - Jasper meeting reply + live prospect read

nonisolated struct WhisperMeetingEmberReply: Sendable {
    let text: String
    let mode: WhisperEmberCoachMode
    let showPitch: Bool
}

/// Jasper's live read on a prospect during a recruiter meeting. Persisted per
/// meeting so the post-call notes can show the full evaluation.
nonisolated struct WhisperProspectEval: Codable, Sendable, Hashable {
    var score: Int
    var placement: String
    var confidence: Int
    var summary: String
    var strengths: [String]
    var concerns: [String]
}

/// One parsed section of the AI meeting notes (**Header** + bullets).
nonisolated struct WhisperMeetingNotesSection: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let paragraphs: [String]
    let bullets: [String]
}

// MARK: - Companion brain

/// Meeting-side AI helpers — the in-call Jasper answer (with personality mode
/// switching + pitch-deck offers), the recruiter's live prospect evaluation,
/// and the notes formatting used by the post-meeting screen. Rides the same
/// toolkit transport as `WhisperMeetingService.generateNotes`.
enum WhisperMeetingCompanion {

    private static let whisperKnowledge: String = """
    === WHISPER KNOWLEDGE (answer product questions from this, truthfully) ===
    Whisper (mydailywhisper.com) is a social platform — thoughts, stories, reels, notes, films, articles, DMs, group chats, communities (public, private groups, Dating) — with a full creator economy built in. Fitness is one slice via the Jasper companion app, never the whole story.
    Surfaces: home feed, Discover, communities & private groups, stories (rings, notes, highlights) & reels, films & articles, live rooms (Stream Manager moderation, viewer GIFTS — hosts keep 70%), Whisper Meet meetings with live captions + per-speaker transcripts + AI notes + Notebook + shared calendar (you are inside one right now), Jasper (you — chat, vision, Imagine image generation, REAL web search with cited sources, fact-checks, pitch decks), coach marketplace with plan tiers, brand sponsorships with the athlete rail, Ads Manager ($5 CPM, prepaid wallet + auto-recharge, public Ad Library), Business+ ($100/mo: team & roles, hiring with auto-matched applications, HQ group, team chat & calendar, present-company-in-meetings), the Recruiting OS (Today → Pipeline → People → Inbox → Insights → Grow), applicant QR questionnaires.
    Monetization: Whisper One membership $14.99/mo or $119.99/yr. Verified badges billed yearly: Coach $249.99, Athlete $99.99, Verified $99.99. Coaches set plan tiers or a monthly rate ($5–$2,000), clients subscribe, Stripe pays out, Whisper keeps a 10% platform fee. Brand sponsorships run through escrow — Whisper keeps 10%. Live gifts: hosts keep 70%. WPP (Whisper Paid Partners) is paid FROM ad revenue: 50% of monthly ad spend becomes the creator pool; a creator's month = min(views × tier RPM, view-share of pool) — Partner 1k+ ≈ $0.90/1k qualified views, Partner+ 10k+ ≈ $1.40, Elite 100k+ ≈ $2.20; months finalize the 1st, $10 minimum cash-out.
    Accounts: personal, creator, business (switchable in Settings). Roles: members, verified creators, coaches, athletes, recruiters, brands, moderators, admins, owner.
    Recruiters: scout talent, run a prospect pipeline (discovered → contacted → interested → meeting → ready → promoted → or passed), share referral codes + QR signup links, collect applicant questionnaires scored 0-100 (potential score, confidence, best-position match across coach/athlete/creator), present client profiles live inside meetings, and promote users into verified roles.
    Pitch decks: interactive decks exist at mydailywhisper.com/pitch for Brands, Creators, Athletes, Coaches, and Recruiters — they render the REAL product with sample data.
    """

    /// Does this question need CURRENT facts from the live web?
    /// Product/personal questions stay on the knowledge blocks.
    nonisolated static func needsLiveWeb(_ q: String) -> Bool {
        let lower = q.lowercased()
        if lower.range(of: #"\b(whisper|jasper|wpp|badge|business\+)\b"#, options: .regularExpression) != nil {
            return false
        }
        return lower.range(
            of: #"\b(latest|news|today|tonight|yesterday|right now|currently|current|price|prices|stock|market|score|scores|schedule|who won|when is|release date|weather|20(2[4-9]|3[0-9])|look up|search the web|google)\b"#,
            options: .regularExpression
        ) != nil
    }

    /// AUTO-ADAPT — while Jasper listens, the DEFAULT personality follows
    /// what's being asked so he's already in the right mode: evidence asks
    /// lean scientist, stressed askers get the guardian, hype asks get the
    /// drill sergeant. The model can still override per its rules.
    nonisolated static func inferMode(
        for question: String,
        fallback: WhisperEmberCoachMode
    ) -> WhisperEmberCoachMode {
        let q = question.lowercased()
        if q.range(of: #"(study|studies|research|evidence|data|numbers|compare|versus|vs\.|why does|how does|mechanism|percent|stat)"#, options: .regularExpression) != nil {
            return .scientist
        }
        if q.range(of: #"(stressed|anxious|overwhelmed|worried|scared|discouraged|burnt out|burned out|nervous|freaking out)"#, options: .regularExpression) != nil {
            return .guardian
        }
        if q.range(of: #"(push me|motivate me|hold me accountable|no excuses|hype me|fire me up)"#, options: .regularExpression) != nil {
            return .drillSergeant
        }
        return fallback
    }

    private static func modeRules(preferred: WhisperEmberCoachMode) -> String {
        // Auto resolves to today's readiness-picked ghost — the meeting brain
        // always receives a CONCRETE personality id.
        let concrete = preferred.resolved
        let autoNote = preferred.isAuto
            ? " (The asker uses AUTO — Jasper picked \(concrete.title) from today's readiness: \(WhisperEmberAutoMood.reason) Quote that reason if asked why you sound this way.)"
            : ""
        return """
        PERSONALITY MODES — the asker's chosen personality is "\(concrete.title)" (\(concrete.rawValue)).\(autoNote) Begin your reply with exactly one line "MODE: <id>". Default to "\(concrete.rawValue)" — stay in their chosen personality unless THIS question clearly calls for a different lens:
        - regular — balanced everyday Jasper.
        - guardian — the asker sounds stressed, discouraged, overwhelmed, or needs reassurance; lead with calm, protective support.
        - scientist — the question wants data, evidence, mechanisms, analysis, numbers, or comparisons; be precise and quantified.
        - drill_sergeant — the asker explicitly wants to be pushed, motivated hard, or held accountable; bring intensity without insults.
        The mode changes your tone, never the facts.
        PITCH DECK — when the question touches Whisper's business model, pricing, monetization, WPP, sponsorships, investor pitch, or presenting Whisper to someone, add the line [[PITCH_DECK]] at the very end so the app offers the interactive deck.
        """
    }

    /// In-call action grammar — the same fenced ```actions protocol the main
    /// Jasper chat uses, scoped to what makes sense mid-meeting. The iOS
    /// client parses the fence into real tappable buttons.
    private static let actionRules: String = """
    IN-APP ACTIONS — you can hand the asker real buttons that act inside Whisper. When they ask to open a screen, message someone, schedule another meeting, or draft a training plan for a client, append ONE fenced block at the VERY END of the reply. This fence is the ONLY code block you may ever emit:
    ```actions
    [{"kind":"open","route":"meetings","label":"Open Meetings"}]
    ```
    Kinds and fields:
    - open: route — one of feed, reels, messages, explore, profile, activity, composer, meetings, calendar, settings, edit_profile, coach_clients, coach_programs, my_coaches, recruiter, creator_dashboard, studio, communities, live_rooms, brands, sponsorships, security, verification, user (arg: username), dm (arg: username), post (arg: post id)
    - message: username, text (the complete drafted message — opens a send-ready draft)
    - schedule: title, whenISO ("2026-08-18T17:00" 24h local), invite (username, optional) — creates a real meeting
    - plan: client (username), title, focus, weeks, sessionsPerWeek, summary, days:[{name,focus,exercises:[{name,sets,reps,restSeconds}]}] — plans must be COMPLETE: every day named with a focus and 4-8 exercises each carrying sets, reps, restSeconds; never a stub day
    - post: text (the complete drafted post), community (community name, optional) — opens the real post composer pre-filled
    - follow: username — follows that user for the asker (private accounts get a follow request)
    - bioage: username (optional — omit for the asker's own) — opens the live Biological Age card synced from the partner Jasper fitness app (score vs real age, drivers, confidence)
    - dietplan: username (optional — omit for the asker's own) — opens the LIVE Jasper diet plan sheet in the native ember glow-box look (macro tiles in the canonical colors — kcal ember / protein teal / carbs amber / fat blue — 7-day chip strip, meal cards, grocery box)
    - groceries: username (optional) — opens the SHARED grocery checklist (teal check circles; checks sync with Jasper both ways, live)
    - clientdashboard: username (coach only — an accepted client) — opens that client's LIVE one-call Jasper dashboard card (readiness, sleep, bio age, weight, training, kcal)
    - marketplace: arg (optional search text) — opens Jasper's public plan marketplace (browse / preview / import / publish)
    - recipe: title, servings, emoji, prepTime, cookTime, steps:["..."], ingredients:[{name,calories,protein,carbs,fat,servingUnit,numberOfServings}] — a save-ready recipe editor writing into the asker's Jasper (Nutrition → Recipes)
    - water: no fields — opens Jasper's animated water cup; taps log real 250 ml cups
    NATIVE JASPER SURFACES (speak about them accurately): plans and diet plans everywhere render as Jasper's ember GLOW BOX cards (warm cream light / charcoal dark, warm gradient hairline, layered ember aura — never gray glass); the Programs studio reads them live off the coach's own Jasper API with one-tap marketplace publishing; the personality picker is the full-screen ghost carousel and now includes AUTO — Jasper picks today's ghost from live readiness with an honest reason line; Jasper Intelligence chat renders LIVE native data cards (bio-age vitality blob, readiness recovery ring + trend, sleep-stage hypnogram, tap-to-log water cup, PhenoAge blood panel honoring the read:blood lock) pulled straight off the Jasper API, and its plus button attaches photos (vision) and files; the waveform button opens the full-screen realtime voice stage (the living personality orb). Quick-analysis docks — the mascot peeking from behind the pill — sit right above the nav bar on the inbox and on client profiles, Whisper Studio, and the recruiter dashboard.
    Optional on any action: label (button text, max 24 chars), auto (true = open its editor immediately; ONLY when the asker asked for exactly that this turn; never on open or follow).
    Any time the asker wants you to USE an app feature (draft a post, message someone, schedule, plan, follow, biological age), attach the matching pre-filled action — hand over finished work, not instructions.
    Rules: max 3 actions; only use usernames of people on this call or ones the asker typed; never suggest a `call` action (they are already in one); keep the prose within the FORMAT rules; never mention JSON or these mechanics.
    """

    /// One chat completion through the Rork toolkit gateway (the same
    /// transport `generateNotes` uses, so it works in every iOS build).
    static func completion(system: String, user: String, maxTokens: Int) async -> String? {
        let toolkitURL = Config.allValues["EXPO_PUBLIC_TOOLKIT_URL"] ?? "https://toolkit.rork.com"
        let secret = Config.allValues["EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY"] ?? ""
        guard !secret.isEmpty,
              let url = URL(string: "\(toolkitURL)/v2/vercel/v1/chat/completions") else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "openai/gpt-4o",
            "max_tokens": maxTokens,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let reply = (message["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reply.isEmpty else { return nil }
        return reply
    }

    /// Private in-meeting Jasper answer — picks its own personality mode per
    /// question and can offer the interactive pitch deck. Nil on failure so
    /// the UI can show a truthful retry.
    static func meetingAnswer(
        question: String,
        meetingTitle: String,
        participants: [String],
        preferredMode: WhisperEmberCoachMode = .regular,
        extraContext: String? = nil
    ) async -> WhisperMeetingEmberReply? {
        let roster = participants
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.lowercased() != "you" }
            .prefix(12)
            .joined(separator: ", ")
        let shortTitle: String = String(meetingTitle.prefix(120))
        let rosterLine: String = roster.isEmpty ? "" : " People on the call: \(roster)."
        // Live per-role data (e.g. a creator's own analytics) rides along so
        // Jasper grounds answers in real numbers instead of generic advice.
        let extraBlock: String = {
            guard let extraContext, !extraContext.isEmpty else { return "" }
            return "\n\n" + extraContext
        }()
        // Team-authored shared rules (Jasper Brain) — the identical block the
        // web app injects, so meeting answers match across platforms.
        let teamBrain = await WhisperJasperBrainService.shared.block()
        let brainBlock: String = teamBrain.map { "\n\n" + $0 } ?? ""
        // AUTO-ADAPT: the default personality follows the question, and
        // live-fact asks get REAL web research grounding before answering.
        let adaptedMode = inferMode(for: question, fallback: preferredMode)
        var findingsBlock = ""
        var sourceURLs: [String] = []
        if needsLiveWeb(question),
           let live = await EmberWebSearchService().liveWebSearch(query: question),
           let liveAnswer = live.answer, !liveAnswer.isEmpty {
            findingsBlock = "\n\nLIVE WEB FINDINGS — you just searched the web for this question; ground your answer in these facts:\n\(String(liveAnswer.prefix(1600)))"
            sourceURLs = Array((live.sources ?? []).prefix(3))
        }
        let system: String = """
        You are Knot, the built-in AI companion inside Whisper. Right now you are inside a live Whisper video meeting titled "\(shortTitle)".\(rosterLine)
        Only the person who asked can see this answer — it is private, like whispering to an assistant during the call.
        FORMAT — every reply must be glanceable and beautifully structured. NEVER send a bare fragment:
        - Even the shortest answer gets dressed: lead with a **bold** phrase ("**Yes** — the deck covers that ✅") so nothing ever renders as one naked word.
        - Trivial answers: that bold lead plus at most one more short sentence.
        - Anything with multiple facts, steps, or numbers: open with ONE short **bold** takeaway sentence, then 2-5 crisp "- " bullets — **bold** the key name or number inside each bullet.
        - Meaty answers (plans, comparisons, multi-part how-tos): short "## " mini-headings with bullets under each — the same grammar as the full Jasper chat.
        - Training plans, EVERY time: "## Day — focus" headings and "- **Exercise** — sets×reps, rest" bullets, with the complete plan action attached.
        - Tasteful emojis are welcome — 1-3 per reply where they add glance value (on the takeaway line or inside bullets), never a spray.
        - Never a wall of text. Stay under ~120 words of prose. The only code block ever allowed is the ```actions fence described below.

        \(whisperKnowledge)\(extraBlock)\(brainBlock)\(findingsBlock)

        \(modeRules(preferred: adaptedMode))

        \(actionRules)
        """
        guard let raw = await completion(system: system, user: question, maxTokens: 500) else {
            return nil
        }
        let (mode, rest) = parseMode(raw, fallback: adaptedMode)
        let showPitch = rest.contains("[[PITCH_DECK]]")
        var text = rest
            .replacingOccurrences(of: "[[PITCH_DECK]]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !sourceURLs.isEmpty {
            text += "\n\nSources: " + sourceURLs.joined(separator: " · ")
        }
        return WhisperMeetingEmberReply(text: text, mode: mode, showPitch: showPitch)
    }

    /// Strips the leading "MODE: <id>" line and maps it to a coach mode.
    /// `fallback` is the user's saved personality — a missing MODE line keeps
    /// their chosen mode instead of silently resetting to Original.
    nonisolated static func parseMode(
        _ raw: String,
        fallback: WhisperEmberCoachMode = .regular
    ) -> (WhisperEmberCoachMode, String) {
        let pattern = "^\\s*MODE:\\s*(regular|guardian|scientist|drill[_ ]?sergeant)\\.?\\s*"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let full = Range(match.range, in: raw),
              let idRange = Range(match.range(at: 1), in: raw) else {
            return (fallback, raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let id = raw[idRange].lowercased().replacingOccurrences(of: " ", with: "_")
        let mode: WhisperEmberCoachMode
        if id == "guardian" { mode = .guardian }
        else if id == "scientist" { mode = .scientist }
        else if id.hasPrefix("drill") { mode = .drillSergeant }
        else { mode = .regular }
        return (mode, String(raw[full.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Jasper's proactive chime-in: silently re-reads the live transcript
    /// and returns ONE short, useful thought about a person in the
    /// conversation — or nil to stay quiet (the common case). Drives the
    /// glowing mascot + thought-cloud "wants to chime in" moment.
    static func chimeThought(
        transcript: String,
        participants: [String],
        meetingTitle: String
    ) async -> String? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 200 else { return nil }
        let tail = String(trimmed.suffix(6000))
        let roster = participants
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.lowercased() != "you" }
            .prefix(12)
            .joined(separator: ", ")
        let rosterLine: String = roster.isEmpty ? "" : " People on the call: \(roster)."
        let system = """
        You are Knot, silently listening inside a live Whisper meeting titled "\(String(meetingTitle.prefix(120)))".\(rosterLine) You may raise your hand ONLY when you have one genuinely useful, specific thought about a PERSON in the conversation — a participant or someone being discussed: a strength worth naming out loud, a caution, a tailored suggestion, or a Whisper opportunity that fits them. Be picky — most of the time you stay silent. Never chime about small talk, logistics, or things already said.
        Respond with STRICT JSON only:
        {"chime": false}
        or
        {"chime": true, "comment": "one sentence, max 26 words, name the person, optionally ONE emoji"}
        """
        let user = "Live meeting transcript (speakers labelled):\n\n\(tail)"
        guard let raw = await completion(system: system, user: user, maxTokens: 120),
              let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}"), start < end,
              let data = String(raw[start...end]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["chime"] as? Bool) == true,
              let comment = (json["comment"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !comment.isEmpty else {
            return nil
        }
        return String(comment.prefix(180))
    }

    /// Scores a prospect from the live meeting transcript — recruiter-side
    /// only. Nil when the model can't produce a valid read so the UI keeps
    /// the previous evaluation.
    static func prospectEvaluation(transcript: String, hint: String?) async -> WhisperProspectEval? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 80 else { return nil }
        let tail = String(trimmed.suffix(9000))
        let system = "You are Knot, Whisper's recruiting analyst, silently listening to a live recruiter–prospect meeting. Whisper placements: coach (verified fitness coach who sells monthly coaching), creator (verified content creator monetized via WPP ad-share + sponsorships), athlete (verified athlete who gets discovered + sponsored). Judge ONLY from the transcript — communication, drive, experience, audience, coachability. The recruiter/host's own lines are filtered out before you see it, so every line is the prospect (or other guests) speaking — score the prospect only, never the recruiter's pitch. Respond with STRICT JSON only, no markdown."
        let hintLine = hint.map { " — the prospect being evaluated is likely \"\($0)\"" } ?? ""
        let user = """
        Live meeting transcript (speakers labelled)\(hintLine):

        \(tail)

        Return JSON exactly like: {"score": 72, "placement": "creator", "confidence": 61, "summary": "one sentence live read", "strengths": ["...","..."], "concerns": ["..."]}
        score = recruiting potential 0-100 (be honest, not generous). placement = best Whisper fit: "coach", "creator", or "athlete". confidence = 0-100 based on how much signal the transcript actually gives. strengths/concerns: 1-3 short phrases each, grounded in what was actually said.
        """
        guard let raw = await completion(system: system, user: user, maxTokens: 420),
              let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}"), start < end,
              let data = String(raw[start...end]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let clamp: (Any?) -> Int = { value in
            let n: Double
            if let d = value as? Double { n = d }
            else if let i = value as? Int { n = Double(i) }
            else if let s = value as? String, let d = Double(s) { n = d }
            else { n = 0 }
            return max(0, min(100, Int(n.rounded())))
        }
        let placementRaw = (json["placement"] as? String ?? "").lowercased()
        let placement = (placementRaw == "coach" || placementRaw == "athlete") ? placementRaw : "creator"
        let summary = (json["summary"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return nil }
        let list: (Any?) -> [String] = { value in
            ((value as? [Any]) ?? [])
                .compactMap { $0 as? String }
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .prefix(3)
                .map { $0 }
        }
        return WhisperProspectEval(
            score: clamp(json["score"]),
            placement: placement,
            confidence: clamp(json["confidence"]),
            summary: summary,
            strengths: list(json["strengths"]),
            concerns: list(json["concerns"])
        )
    }

    // MARK: - Notes formatting + sharing

    /// Turns the markdown-ish AI notes (**Header** + bullets) into structured
    /// sections so the post-meeting screen renders them beautifully.
    nonisolated static func notesSections(_ raw: String) -> [WhisperMeetingNotesSection] {
        struct Builder {
            var title: String
            var paragraphs: [String] = []
            var bullets: [String] = []
        }
        var builders: [Builder] = []
        let headerOnly = try? NSRegularExpression(pattern: "^\\*\\*(.+?)\\*\\*:?\\s*$")
        let headerInline = try? NSRegularExpression(pattern: "^\\*\\*(.+?)\\*\\*:?\\s+(.+)$")
        for line in raw.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            let range = NSRange(t.startIndex..., in: t)
            if let match = headerOnly?.firstMatch(in: t, range: range),
               let titleRange = Range(match.range(at: 1), in: t) {
                builders.append(Builder(title: String(t[titleRange]).trimmingCharacters(in: CharacterSet(charactersIn: ": "))))
                continue
            }
            if let match = headerInline?.firstMatch(in: t, range: range),
               let titleRange = Range(match.range(at: 1), in: t),
               let restRange = Range(match.range(at: 2), in: t) {
                var builder = Builder(title: String(t[titleRange]).trimmingCharacters(in: CharacterSet(charactersIn: ": ")))
                builder.paragraphs.append(String(t[restRange]).replacingOccurrences(of: "**", with: ""))
                builders.append(builder)
                continue
            }
            if builders.isEmpty { builders.append(Builder(title: "Summary")) }
            let clean = t.replacingOccurrences(of: "**", with: "")
            if clean.hasPrefix("- ") || clean.hasPrefix("• ") || clean.hasPrefix("* ") {
                builders[builders.count - 1].bullets.append(String(clean.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            } else {
                builders[builders.count - 1].paragraphs.append(clean)
            }
        }
        return builders
            .filter { !$0.paragraphs.isEmpty || !$0.bullets.isEmpty }
            .enumerated()
            .map { index, builder in
                WhisperMeetingNotesSection(
                    id: "\(index)-\(builder.title)",
                    title: builder.title,
                    paragraphs: builder.paragraphs,
                    bullets: builder.bullets
                )
            }
    }

    /// SF Symbol for a notes section header.
    nonisolated static func sectionIcon(_ title: String) -> String {
        let t = title.lowercased()
        if t.contains("key") { return "sparkles" }
        if t.contains("decision") { return "checkmark.seal.fill" }
        if t.contains("action") { return "checklist" }
        return "doc.text.fill"
    }

    /// The line that opens the transcript block inside a notes message — the
    /// exact marker every client (web + iOS) splits on.
    nonisolated static let notesTranscriptMarker = "— Transcript —"

    /// The plain-text notes message sent through Whisper DMs and email: the
    /// "📋 Meeting notes —" header every client detects, the notes, the room
    /// link, and the FULL "speaker: line" transcript under its marker so the
    /// recipient reads every word without needing access to the room.
    nonisolated static func notesDmText(
        title: String,
        notes: String,
        transcript: String? = nil,
        link: String? = nil
    ) -> String {
        var text = "\u{1F4CB} Meeting notes — \(title)\n\n\(String(notes.trimmingCharacters(in: .whitespacesAndNewlines).prefix(6000)))"
        if let link, !link.isEmpty {
            text += "\n\n\u{1F517} Full notes & transcript: \(link)"
        }
        let lines = (transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !lines.isEmpty {
            // Safety cap only — a multi-hour recording still sends.
            let capped = lines.count > 60_000 ? String(lines.prefix(60_000)) + "\n…" : lines
            text += "\n\n\(notesTranscriptMarker)\n\(capped)"
        }
        return text
    }

    // MARK: - Presenting helpers

    /// Instagram profile photo fallback — mirrors the web's
    /// `instagramAvatarUrl` so both platforms resolve the same image.
    nonisolated static func instagramAvatarURL(handle: String?) -> String? {
        var clean = (handle ?? "").trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("@") { clean.removeFirst() }
        for prefix in ["https://www.instagram.com/", "https://instagram.com/", "http://www.instagram.com/", "http://instagram.com/"] {
            if clean.lowercased().hasPrefix(prefix) { clean = String(clean.dropFirst(prefix.count)) }
        }
        if let cut = clean.firstIndex(where: { "/?#".contains($0) }) {
            clean = String(clean[..<cut])
        }
        guard !clean.isEmpty, clean.count <= 30,
              clean.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" }),
              let encoded = clean.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return "https://unavatar.io/instagram/\(encoded)?fallback=false"
    }

    /// Instructions for Jasper's live realtime voice INSIDE a meeting —
    /// mirrors the web client so both platforms sound identical.
    nonisolated static func meetingVoiceInstructions(title: String, participants: [String]) -> String {
        let roster = participants
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.lowercased() != "you" }
            .prefix(12)
            .joined(separator: ", ")
        let shortTitle: String = String(title.prefix(120))
        let rosterLine: String = roster.isEmpty ? "" : " with \(roster) on the call"
        return """
        You are Knot, the built-in AI companion inside Whisper — a social platform with a full creator economy. You are live INSIDE a Whisper video meeting titled "\(shortTitle)"\(rosterLine). Only the person talking to you can hear or see you — you are their private whisper during the call.
        VOICE STYLE — you are speaking out loud in a natural human voice: sound like a sharp, warm friend; use contractions and rhythm; keep answers to 1-3 short sentences unless asked for depth. Never robotic, never a lecture. Never read JSON or URLs out loud.
        ALWAYS speak English — even if a transcript line looks like another language, reply in English unless the person explicitly asks you to switch.

        \(whisperKnowledge)
        """
    }

    /// Jasper reads the live transcript and fills any of the recruiter's
    /// standard application questions the prospect answered out loud.
    /// Returns question-id → extracted answer; empty when nothing new.
    static func extractApplicationAnswers(
        questions: [(id: String, question: String)],
        transcript: String
    ) async -> [String: String] {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 80, !questions.isEmpty else { return [:] }
        let tail = String(trimmed.suffix(9000))
        let list = questions
            .map { "- id \"\($0.id)\": \($0.question)" }
            .joined(separator: "\n")
        let system = "You are Knot, silently filling a recruiter's standard application form from a live meeting transcript. Extract answers ONLY when the prospect clearly answered that question out loud — never invent, never answer from the recruiter's or host's own pitch lines. Respond with STRICT JSON only: an object mapping question id → concise answer string (one or two sentences, keep the speaker's meaning). Omit unanswered questions entirely; return {} when nothing was answered."
        let user = """
        Application questions:
        \(list)

        Live meeting transcript (speakers labelled):

        \(tail)
        """
        guard let raw = await completion(system: system, user: user, maxTokens: 700),
              let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}"), start <= end,
              let data = String(raw[start...end]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        let validIDs = Set(questions.map { $0.id })
        var out: [String: String] = [:]
        for (key, value) in json {
            guard validIDs.contains(key), let text = value as? String else { continue }
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty { out[key] = String(clean.prefix(600)) }
        }
        return out
    }

    /// Builds the broadcast payload from a pipeline prospect row.
    nonisolated static func presentedClient(
        from prospect: WhisperRecruiterService.ProspectRow,
        presenterUserId: String,
        presenterName: String
    ) -> WhisperPresentedClient {
        WhisperPresentedClient(
            kind: "prospect",
            id: prospect.id,
            username: prospect.prospect_username,
            displayName: prospect.prospect_display_name,
            imageUrl: prospect.prospect_image_url ?? instagramAvatarURL(handle: prospect.instagram),
            status: prospect.status,
            rating: prospect.rating,
            niche: prospect.niche,
            location: prospect.location,
            source: prospect.source,
            instagram: prospect.instagram,
            tiktok: prospect.tiktok,
            suggestedRole: prospect.suggested_role,
            notes: prospect.notes.map { String($0.prefix(800)) },
            contactLog: [],
            addedAt: prospect.created_at,
            application: nil,
            presenterUserId: presenterUserId,
            presenterName: presenterName
        )
    }

    /// Builds the broadcast payload for a coach presenting one of their
    /// active clients — same wire shape as the web's `payloadFromCoachClient`.
    nonisolated static func presentedCoachClient(
        from request: WhisperCoachRequestRow,
        presenterUserId: String,
        presenterName: String
    ) -> WhisperPresentedClient {
        var payload = WhisperPresentedClient(
            kind: "coach-client",
            id: request.id,
            username: request.client_username,
            displayName: nil,
            imageUrl: nil,
            status: "active",
            rating: nil,
            niche: nil,
            location: nil,
            source: nil,
            instagram: nil,
            tiktok: nil,
            suggestedRole: nil,
            notes: request.message.map { String($0.prefix(800)) },
            contactLog: [],
            addedAt: request.created_at,
            application: nil,
            presenterUserId: presenterUserId,
            presenterName: presenterName
        )
        payload.userId = request.client_user_id
        payload.applicationAnswers = []
        payload.photos = []
        return payload
    }

    /// Maps a client's uploaded fitness snapshot into the presentation wire
    /// shape both platforms render (macros, activity, recent workouts).
    nonisolated static func presentationSnapshot(
        from payload: WhisperClientSnapshot
    ) -> WhisperPresentedClient.Snapshot {
        WhisperPresentedClient.Snapshot(
            caloriesToday: Double(payload.caloriesToday),
            caloriesGoal: Double(payload.caloriesGoal),
            proteinToday: payload.proteinToday,
            proteinGoal: payload.proteinGoal,
            carbsToday: payload.carbsToday,
            carbsGoal: payload.carbsGoal,
            fatToday: payload.fatToday,
            fatGoal: payload.fatGoal,
            waterCups: Double(payload.waterCount),
            streak: Double(payload.loggingStreak),
            sleepHours: payload.sleepHours,
            steps: Double(payload.steps),
            activeMinutes: Double(payload.activeMinutes),
            restingHeartRate: payload.restingHeartRate,
            weightLbs: payload.bodyMassLbs,
            bodyFatPct: payload.bodyFatPct,
            workouts: payload.recentWorkouts.map {
                WhisperPresentedClient.SnapshotWorkout(
                    type: $0.type,
                    durationMinutes: Double($0.durationMinutes),
                    calories: Double($0.calories),
                    date: $0.date
                )
            }
        )
    }
}
