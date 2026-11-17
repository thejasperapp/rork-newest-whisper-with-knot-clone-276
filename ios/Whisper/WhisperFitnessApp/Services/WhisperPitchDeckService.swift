import Foundation
import Supabase

/// Generates, caches, and persists Jasper's recruiter pitch decks.
/// Generation rides the same toolkit chat rail as meeting notes; storage
/// rides whisper_meeting_decks (supabase/pitch-decks.sql) with a local
/// UserDefaults cache so decks work before the migration runs. The JSON
/// wire shape matches the web app exactly.
@MainActor
final class WhisperPitchDeckService {
    static let shared = WhisperPitchDeckService()
    private let client = SupabaseService.shared.client
    private init() {}

    private static func cacheKey(_ meetingID: String) -> String {
        "whisper_meeting_deck:\(meetingID)"
    }

    // MARK: - Generation

    /// Build the deck from the meeting transcript — one AI call. Returns nil
    /// when there isn't enough conversation or the model can't produce a
    /// valid deck, so callers keep whatever they already have.
    func generate(
        meetingID: String,
        meetingTitle: String,
        prospectHint: String?,
        isDraft: Bool
    ) async -> WhisperPitchDeck? {
        let transcript = await WhisperMeetingService.shared.fetchTranscriptPlain(meetingID: meetingID)
        guard transcript.count >= 200 else { return nil }

        let recruiterName = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? "the host"

        let toolkitURL = Config.allValues["EXPO_PUBLIC_TOOLKIT_URL"] ?? "https://toolkit.rork.com"
        let secret = Config.allValues["EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY"] ?? ""
        guard !secret.isEmpty,
              let url = URL(string: "\(toolkitURL)/v2/vercel/v1/chat/completions") else { return nil }

        let system = "You are Knot, Whisper's recruiting strategist. You silently listened to a live recruiter–prospect meeting on Whisper. Whisper placements: coach (verified fitness coach selling monthly coaching, keeps 90%), creator (verified content creator paid from the WPP ad-revenue pool + escrowed sponsorships), athlete (verified athlete who gets discovered + sponsored). You now build the recruiter a CLOSE DECK — a pitch plan grounded ONLY in what was actually said in the transcript. Never invent quotes or facts. Respond with STRICT JSON only — no markdown, no commentary."

        let prompt = """
        Meeting: "\(String(meetingTitle.prefix(120)))".
        The recruiter (the pitch side) is "\(recruiterName)" — their transcript lines are the pitch. Everyone else is the prospect side.\(prospectHint.map { " The prospect being recruited is likely \"\($0)\"." } ?? "")

        TRANSCRIPT (speakers labelled):
        \(String(transcript.suffix(16000)))

        Return JSON EXACTLY like:
        {"prospectName":"display name of the prospect","placement":"coach|creator|athlete","headline":"one-line pitch angle for the close, max 95 chars","interests":["3-5 things the prospect actually cares about, in their words"],"keyMoments":[{"quote":"short faithful quote (max 140 chars)","speaker":"who said it","note":"why it matters for the close (max 90 chars)","kind":"interest|objection|signal"}],"slides":[{"title":"slide title","bullets":["2-4 short bullets"]}],"closePlan":[{"step":"imperative step","detail":"one sentence of how/why"}],"closeRate":{"withPlan":72,"withoutPlan":38,"why":"1-2 honest sentences explaining both numbers"},"impactMoments":[{"quote":"the recruiter's own line that landed","why":"what it did (max 85 chars)"}],"nextSteps":[{"action":"concrete action","when":"e.g. Tonight, Thursday 4pm, within 48h"}]}

        Rules: 3-5 keyMoments (mix kinds; at least one objection when one exists). 2-3 slides. 3-5 closePlan steps ordered. impactMoments: 1-3 picked ONLY from the recruiter's own lines — the moments that visibly moved the prospect; if nothing landed, return one honest entry saying so in "why". 2-4 nextSteps. closeRate: honest integers 0-100 — withPlan reflects real signal strength, never flattery; withoutPlan assumes no follow-through. Quotes must be short and faithful to the transcript.
        """

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "openai/gpt-4o",
            "max_tokens": 1500,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": prompt],
            ],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let raw = message["content"] as? String else { return nil }

        guard var deck = Self.parseDeck(raw) else { return nil }
        deck.v = 1
        deck.meetingId = meetingID
        deck.meetingTitle = meetingTitle
        deck.generatedAt = Date().timeIntervalSince1970 * 1000
        deck.draft = isDraft ? true : nil

        cache(deck, meetingID: meetingID)
        if !isDraft {
            await persist(deck, meetingID: meetingID)
        }
        return deck
    }

    /// Tolerant parse of the model output — mirrors the web's parseDeck.
    nonisolated private static func parseDeck(_ raw: String) -> WhisperPitchDeck? {
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}"), start < end,
              let data = String(raw[start...end]).data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        func str(_ v: Any?, _ max: Int = 400) -> String {
            guard let s = v as? String else { return "" }
            return String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(max))
        }
        func clamp100(_ v: Any?) -> Int {
            let n = (v as? NSNumber)?.doubleValue ?? Double(str(v, 8)) ?? 0
            guard n.isFinite else { return 0 }
            return Swift.max(0, Swift.min(100, Int(n.rounded())))
        }
        func strList(_ v: Any?, _ maxItems: Int, _ maxLen: Int = 160) -> [String] {
            guard let arr = v as? [Any] else { return [] }
            return arr.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { String($0.prefix(maxLen)) }
                .prefix(maxItems)
                .map { $0 }
        }

        let placementRaw = str(o["placement"], 20).lowercased()
        let placement = (placementRaw == "coach" || placementRaw == "athlete") ? placementRaw : "creator"
        let headline = str(o["headline"], 140)
        let prospectName = str(o["prospectName"], 60)
        guard !headline.isEmpty else { return nil }

        let moments: [WhisperPitchDeck.Moment] = ((o["keyMoments"] as? [Any]) ?? []).compactMap { item in
            guard let m = item as? [String: Any] else { return nil }
            let quote = str(m["quote"], 200)
            guard !quote.isEmpty else { return nil }
            let kindRaw = str(m["kind"], 20).lowercased()
            let kind = (kindRaw == "objection" || kindRaw == "signal") ? kindRaw : "interest"
            return WhisperPitchDeck.Moment(
                quote: quote,
                speaker: str(m["speaker"], 40).isEmpty ? "speaker" : str(m["speaker"], 40),
                note: str(m["note"], 140),
                kind: kind
            )
        }.prefix(6).map { $0 }

        let slides: [WhisperPitchDeck.Slide] = ((o["slides"] as? [Any]) ?? []).compactMap { item in
            guard let s = item as? [String: Any] else { return nil }
            let title = str(s["title"], 90)
            let bullets = strList(s["bullets"], 4, 140)
            guard !title.isEmpty, !bullets.isEmpty else { return nil }
            return WhisperPitchDeck.Slide(title: title, bullets: bullets)
        }.prefix(4).map { $0 }

        let closePlan: [WhisperPitchDeck.Step] = ((o["closePlan"] as? [Any]) ?? []).compactMap { item in
            guard let s = item as? [String: Any] else { return nil }
            let step = str(s["step"], 110)
            guard !step.isEmpty else { return nil }
            return WhisperPitchDeck.Step(step: step, detail: str(s["detail"], 200))
        }.prefix(6).map { $0 }

        guard !moments.isEmpty || !slides.isEmpty || !closePlan.isEmpty else { return nil }

        let rate = o["closeRate"] as? [String: Any] ?? [:]
        let impact: [WhisperPitchDeck.Impact] = ((o["impactMoments"] as? [Any]) ?? []).compactMap { item in
            guard let s = item as? [String: Any] else { return nil }
            let quote = str(s["quote"], 200)
            guard !quote.isEmpty else { return nil }
            return WhisperPitchDeck.Impact(quote: quote, why: str(s["why"], 140))
        }.prefix(4).map { $0 }

        let nextSteps: [WhisperPitchDeck.NextStep] = ((o["nextSteps"] as? [Any]) ?? []).compactMap { item in
            guard let s = item as? [String: Any] else { return nil }
            let action = str(s["action"], 120)
            guard !action.isEmpty else { return nil }
            let when = str(s["when"], 40)
            return WhisperPitchDeck.NextStep(action: action, when: when.isEmpty ? "Soon" : when)
        }.prefix(5).map { $0 }

        return WhisperPitchDeck(
            v: 1,
            meetingId: "",
            meetingTitle: "",
            prospectName: prospectName.isEmpty ? "the prospect" : prospectName,
            placement: placement,
            headline: headline,
            interests: strList(o["interests"], 5, 110),
            keyMoments: moments,
            slides: slides,
            closePlan: closePlan,
            closeRate: WhisperPitchDeck.CloseRate(
                withPlan: clamp100(rate["withPlan"]),
                withoutPlan: clamp100(rate["withoutPlan"]),
                why: str(rate["why"], 320)
            ),
            impactMoments: impact,
            nextSteps: nextSteps,
            generatedAt: Date().timeIntervalSince1970 * 1000,
            draft: nil,
            sample: nil
        )
    }

    // MARK: - Storage

    private func cache(_ deck: WhisperPitchDeck, meetingID: String) {
        if let data = try? JSONEncoder().encode(deck) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey(meetingID))
        }
    }

    private func cached(_ meetingID: String) -> WhisperPitchDeck? {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey(meetingID)) else { return nil }
        return try? JSONDecoder().decode(WhisperPitchDeck.self, from: data)
    }

    /// Best-effort database persist — the table may not be migrated yet;
    /// the local cache still carries the deck either way.
    private func persist(_ deck: WhisperPitchDeck, meetingID: String) async {
        guard let uid = client.auth.currentUser?.id.uuidString.lowercased() else { return }
        struct Row: Encodable {
            let meeting_id: String
            let recruiter_id: String
            let prospect_name: String?
            let deck: WhisperPitchDeck
            let updated_at: String
        }
        let row = Row(
            meeting_id: meetingID,
            recruiter_id: uid,
            prospect_name: deck.prospectName,
            deck: deck,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        _ = try? await client
            .from("whisper_meeting_decks")
            .upsert(row, onConflict: "meeting_id,recruiter_id")
            .execute()
    }

    /// The recruiter's stored deck for a meeting — cache first, then the
    /// database copy (which re-primes the cache).
    func load(meetingID: String) async -> WhisperPitchDeck? {
        if let hit = cached(meetingID) { return hit }
        guard let uid = client.auth.currentUser?.id.uuidString.lowercased() else { return nil }
        struct Row: Decodable { let deck: WhisperPitchDeck }
        let rows: [Row]? = try? await client
            .from("whisper_meeting_decks")
            .select("deck")
            .eq("meeting_id", value: meetingID)
            .eq("recruiter_id", value: uid)
            .limit(1)
            .execute()
            .value
        guard let deck = rows?.first?.deck else { return nil }
        cache(deck, meetingID: meetingID)
        return deck
    }
}
