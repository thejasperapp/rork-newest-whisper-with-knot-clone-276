import Foundation
import SwiftUI
import MapKit
import CoreLocation

/// Whisper-specific wrapper around `OpenAIService.chat` that powers the
/// Jasper features inside the social app — smart replies in DMs, draft
/// review in the composer, comment summaries, bio writer, etc.
///
/// All entry points return plain `String` (or lightly parsed structures)
/// so the call sites can stay tiny — no streaming, no tool-routing here.
/// The full agentic stack from Whisper stays on the Whisper side.
@Observable
@MainActor
final class WhisperEmberService {
    static let shared = WhisperEmberService()

    /// Cache of generated outputs keyed by feature+input hash so repeat
    /// taps on the same draft / thread don't re-bill OpenAI.
    private var cache: [String: String] = [:]
    private var inflight: Set<String> = []


    private let service = OpenAIService()
    private let webSearch = EmberWebSearchService()

    private init() {}

    // MARK: - Web-grounded answer (shared /ember)

    nonisolated struct WebAnswer: Sendable {
        let answer: String
        let tldr: String?
        let sources: [String]
    }

    /// Deep, source-cited answer for the `/ember` slash command. Falls back
    /// to the basic `ask()` text when the web search fails.
    func webAnswer(_ prompt: String) async -> WebAnswer {
        do {
            let r = try await webSearch.webSearch(query: prompt)
            let answer = (r.answer ?? r.tldr ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !answer.isEmpty {
                return WebAnswer(answer: answer, tldr: r.tldr, sources: r.sources ?? [])
            }
        } catch {
            // fall through to fallback
        }
        let basic = await ask(prompt)
        return WebAnswer(answer: basic, tldr: nil, sources: [])
    }

    // MARK: - Fact check

    /// Cache of fact-check verdicts keyed by post id so the verdict pill
    /// can render instantly the moment the post enters the feed, without
    /// waiting for Jasper to re-run the web search. Populated by the
    /// composer at publish time and read by WhisperPostCard on appear.
    private var factCheckCache: [String: FactCheck] = [:]
    /// Per-post in-flight fact-check Tasks. Multiple callers (composer
    /// pre-warm, feed card scroll-in, profile card re-mount) coalesce onto
    /// the same Task so the model is never billed twice for the same post
    /// and EVERY caller observes the same FactCheck result — fixing the
    /// race where the card would mark a post as "auto-checked" before the
    /// background Task finished, then unmount/remount and silently render
    /// no badge because both the cache AND the local @State were empty.
    private var inflightFactChecks: [String: Task<FactCheck, Never>] = [:]

    /// Pre-warm a fact-check for a post that was just published. Runs the
    /// usual `factCheck(_:)` pipeline in the background and caches the
    /// result keyed by post id. Safe to call multiple times; deduped.
    func prewarmFactCheck(postID: String, caption: String, kind: String = "") {
        guard !caption.isEmpty else { return }
        // Workout posts are personal training logs, not claims to verify.
        // Skip the pre-warm so we don't bill an Jasper call we'll never use.
        if kind.lowercased() == "workout" { return }
        // Only invest a fact-check call on captions that read as factual
        // claims — jokes, photos, casual chatter, and satire are skipped
        // via `looksLikeFactualClaim` (which now folds in satire detection).
        guard WhisperLiarLiarService.looksLikeFactualClaim(caption) else { return }
        Task { _ = await self.factCheckOnce(postID: postID, caption: caption) }
    }

    /// Deterministic single-shot fact-check for a post. Returns the cached
    /// verdict if one exists, otherwise joins (or starts) the in-flight
    /// Task for that post id and awaits its result. Caches on completion.
    /// This is the only path the feed should use — `factCheck(_:)` itself
    /// is fire-and-forget with no dedupe.
    func factCheckOnce(postID: String, caption: String) async -> FactCheck? {
        let key = postID.lowercased()
        if let cached = factCheckCache[key] { return cached }
        guard !caption.isEmpty else { return nil }
        if let existing = inflightFactChecks[key] {
            return await existing.value
        }
        let captionCopy = caption
        let task = Task<FactCheck, Never> { [weak self] in
            guard let self else {
                return FactCheck(verdict: .unverified, summary: "", explanation: "", sources: [])
            }
            return await self.factCheck(captionCopy)
        }
        inflightFactChecks[key] = task
        let result = await task.value
        factCheckCache[key] = result
        inflightFactChecks[key] = nil
        if factCheckCache.count > 600 {
            factCheckCache = Dictionary(uniqueKeysWithValues: factCheckCache.suffix(300).map { ($0.key, $0.value) })
        }
        return result
    }

    /// Returns the pre-warmed verdict for a post if one was cached. Used by
    /// the post card to render the verdict pill on first paint.
    func cachedFactCheck(postID: String) -> FactCheck? {
        factCheckCache[postID.lowercased()]
    }

    /// Stores a fact-check verdict in the cache. Called by the post card
    /// after a live `factCheck(_:)` returns so subsequent re-mounts of the
    /// same post don't re-bill the model.
    func cacheFactCheck(postID: String, result: FactCheck) {
        factCheckCache[postID.lowercased()] = result
        // Cap the cache so a long-running session doesn't grow unbounded.
        if factCheckCache.count > 600 {
            factCheckCache = Dictionary(uniqueKeysWithValues: factCheckCache.suffix(300).map { ($0.key, $0.value) })
        }
    }

    nonisolated struct FactCheck: Sendable {
        let verdict: WhisperFactCheckEmbed.Verdict
        /// Punchy one-liner shown by default in the card.
        let summary: String
        /// Longer multi-sentence explanation revealed on tap.
        let explanation: String
        let sources: [String]
    }

    /// Verifies a claim using Jasper's web research stack. Returns a verdict
    /// pill + short one-line summary + longer explanation + 2-3 source URLs.
    func factCheck(_ claim: String) async -> FactCheck {
        // Belt-and-suspenders: even if a caller bypasses the heuristic gate,
        // bail out fast on obvious satire so we don't slap a verdict pill
        // on a joke post. Returns UNVERIFIED with a friendly note instead.
        if WhisperLiarLiarService.looksLikeSatire(claim) {
            return FactCheck(
                verdict: .unverified,
                summary: "Read as satire — skipping fact-check.",
                explanation: "This reads like a joke or shitpost rather than a serious claim, so Knot isn\u{2019}t going to fact-check it.",
                sources: []
            )
        }
        let prompt = """
        Fact-check this claim made in a fitness/health post: "\(claim)".
        First, decide if the claim is SATIRICAL, sarcastic, a joke, or clearly humorous (not a sincere claim). If so, respond with verdict UNVERIFIED and explanation "Reads as satire — not a sincere claim." — do NOT pick a TRUE/FALSE verdict for jokes.
        Otherwise, decide on a single verdict from this list: TRUE, MOSTLY_TRUE, MISLEADING, FALSE, UNVERIFIED.
        Then write a short 2-3 sentence explanation of why, written like a coach (no AI talk).
        Cite 2-3 reputable source URLs (pubmed, .gov, .edu, mayoclinic, nih, etc.).
        """
        do {
            let r = try await webSearch.webSearch(query: prompt)
            let raw = (r.answer ?? "").lowercased()
            let verdict = WhisperFactCheckEmbed.Verdict.parse(raw)
            let explanation = (r.answer ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let tldr = (r.tldr ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let summary: String = {
                if !tldr.isEmpty { return tldr }
                // Fall back to first sentence of the explanation.
                if let end = explanation.firstIndex(where: { ".!?".contains($0) }) {
                    return String(explanation[...end]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return explanation
            }()
            return FactCheck(
                verdict: verdict,
                summary: summary.isEmpty ? "Couldn't verify this claim with confidence." : summary,
                explanation: explanation.isEmpty ? "Couldn't verify this claim with confidence." : explanation,
                sources: r.sources ?? []
            )
        } catch {
            return FactCheck(verdict: .unverified,
                             summary: "Couldn't reach the research stack.",
                             explanation: "Couldn't reach the research stack right now. Try again in a moment.",
                             sources: [])
        }
    }

    // MARK: - Catch me up (inbox)

    /// One-sentence summary of all unread threads, written as a quick brief.
    func catchMeUp(unread: [(name: String, lastMessage: String)]) async -> String {
        guard !unread.isEmpty else { return "You're all caught up. No unread messages." }
        let snippet = unread.prefix(12).map { "@\($0.name): \($0.lastMessage)" }.joined(separator: "\n")
        let key = "catch:\(snippet.hashValue)"
        return await cached(key: key) {
            let prompt = """
            You summarize a DM inbox for a busy user. Each line below is one chat: the sender's handle, whether it's waiting on the user's reply, and the last message.

            Write a tight, genuinely useful 2-3 sentence briefing:
            1. Lead with who is WAITING ON MY REPLY and what they actually need (be specific — mention the topic, not just the name).
            2. Flag anything time-sensitive: calendar invites, meetings, proposals, deadlines.
            3. Skip chats where I replied last unless something important is pending.
            If nothing needs a reply, say so in one sentence and mention the most interesting recent message.
            Plain text only — no preamble, no bullet points, no quotes, no emojis.

            \(snippet)
            """
            return await self.chat(query: prompt)
        }
    }

    // MARK: - Quick analysis (docked Jasper — inbox, client profiles)

    /// One-shot surface analysis for the docked meeting-style Jasper box.
    /// `focus` is the surface-specific instruction; `context` carries the
    /// live lines. Cached per context so reopening the box is instant;
    /// `force` bypasses the cache for an explicit re-run.
    func quickAnalysis(context: String, focus: String, force: Bool = false) async -> String {
        let key = force ? "qa:\(UUID().uuidString)" : "qa:\(focus.hashValue &+ context.hashValue)"
        return await cached(key: key) {
            let prompt = """
            \(focus)
            Keep it tight — 2-4 short sentences (or up to 3 mini-bullets), **bold** the one thing that matters most. No preamble, no emojis.

            \(context)
            """
            return await self.chat(query: prompt)
        }
    }

    // MARK: - Comments: Jasper pick + misinformation flag

    /// Picks the most helpful comment from a thread. Returns the id of the
    /// winning comment (matching `WhisperCommentRow.id`), or nil if there
    /// isn't a clear pick or the thread is too small.
    func bestComment(_ comments: [WhisperCommentRow]) async -> String? {
        guard comments.count >= 4 else { return nil }
        let body = comments.prefix(40).map { "[\($0.id)] @\($0.username): \($0.body)" }.joined(separator: "\n")
        let key = "pick:\(body.hashValue)"
        let raw = await cached(key: key) {
            let prompt = """
            Pick the single MOST HELPFUL comment in this fitness post thread \
            (clear advice, accurate, kind, specific). Reply with ONLY the id in square brackets, e.g. `[abc-123]`. \
            If nothing stands out, reply `NONE`.

            \(body)
            """
            return await self.chat(query: prompt)
        }
        if raw.uppercased().contains("NONE") { return nil }
        // Pull the id out of `[id]`
        if let open = raw.firstIndex(of: "["),
           let close = raw.firstIndex(of: "]"),
           open < close {
            let id = String(raw[raw.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
            // Validate it actually exists
            if comments.contains(where: { $0.id == id }) { return id }
        }
        return nil
    }

    // MARK: - Bookmarks: auto-categorize

    /// Suggests one of the existing bookmark categories that best fits a
    /// post's caption. Returns nil if no good fit (caller should fall back
    /// to "All").
    func autoCategorize(caption: String, available: [String]) async -> String? {
        let pool = available.filter { $0 != "All" }
        guard !pool.isEmpty, !caption.isEmpty else { return nil }
        let list = pool.joined(separator: ", ")
        let key = "cat:\(caption.hashValue):\(list.hashValue)"
        let raw = await cached(key: key) {
            let prompt = """
            A fitness post has this caption: "\(caption)".
            Choose the BEST matching category from this list (reply with ONLY the exact category name, no punctuation): \(list).
            If none fit, reply NONE.
            """
            return await self.chat(query: prompt)
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.uppercased().contains("NONE") { return nil }
        // Match case-insensitively against the pool
        return pool.first { $0.lowercased() == trimmed.lowercased() }
    }

    // MARK: - Composer: alt-text

    /// Generates a one-sentence accessibility alt-text for an image based
    /// on a short hint or the post caption.
    func altText(for hint: String) async -> String {
        let key = "alt:\(hint.hashValue)"
        return await cached(key: key) {
            let prompt = """
            Write a single-sentence accessibility alt-text (under 140 chars) describing a fitness photo. Context: "\(hint)". No preamble, no quotes.
            """
            return await self.chat(query: prompt)
        }
    }

    // MARK: - Reels / post caption

    /// Suggests an Instagram-style caption + hashtags for a Reel given a
    /// short description of its content.
    func captionForReel(description: String) async -> String {
        let key = "reelcap:\(description.hashValue)"
        return await cached(key: key) {
            let prompt = """
            Write a punchy Instagram-style Reel caption for a fitness video described as: "\(description)". \
            One hook line, then 3-5 relevant hashtags on the next line. Under 220 chars total. No emoji unless natural.
            """
            return await self.chat(query: prompt)
        }
    }

    // MARK: - Generic chat

    /// Ask Jasper anything Whisper-flavored. Used by the `/ember` slash command.
    func ask(_ prompt: String) async -> String {
        await cached(key: "ask:\(prompt.hashValue)") {
            let system = self.whisperSystemPrompt
            let full = "\(system)\n\nUser asked from a Whisper chat: \(prompt)\n\nKeep it under 3 sentences."
            return await self.chat(query: full)
        }
    }

    // MARK: - DM: smart reply chips

    /// 3 short, context-aware reply suggestions for the last N messages.
    /// Returns plain strings (no quotes, no numbering). Empty array on failure.
    func smartReplies(thread: [WhisperMessageRow], mineID: String) async -> [String] {
        guard thread.count >= 1 else { return [] }
        let tail = Array(thread.suffix(6))
        let transcript = tail.map { m in
            let who = m.from_user_id.lowercased() == mineID.lowercased() ? "Me" : "@\(m.from_username)"
            return "\(who): \(m.body)"
        }.joined(separator: "\n")
        // Macro-aware context: when the last incoming message reads like a
        // food/restaurant question ("is sushi okay tonight?", "thinking
        // burritos for dinner"), splice in the viewer's remaining macros
        // so Jasper's reply can ground itself in real numbers.
        let lastBody = (tail.last?.body ?? "").lowercased()
        let foodKeywords = [
            "eat", "meal", "dinner", "lunch", "breakfast", "snack",
            "sushi", "pizza", "burrito", "burger", "salad", "bowl",
            "calorie", "macro", "protein", "carb", "fat", "craving",
            "okay tonight", "order", "restaurant", "food"
        ]
        let isFoodQuestion = foodKeywords.contains(where: { lastBody.contains($0) })
        let macroContext: String
        if isFoodQuestion {
            let store = NutritionStore.shared
            macroContext = """

            Viewer's remaining macros today: \(store.caloriesRemaining) cal, \(Int(store.proteinRemaining))g protein, \(Int(store.carbsRemaining))g carbs, \(Int(store.fatRemaining))g fat. Bias one reply toward fitting those.
            """
        } else {
            macroContext = ""
        }
        let key = "sr:\(transcript.hashValue):\(macroContext.hashValue)"
        let raw = await cached(key: key) {
            let prompt = """
            You are Knot, helping the user reply in a fitness DM. Read this short transcript and propose THREE different short replies the user could send — natural, casual, in their own voice. No emoji unless the prior messages used them. Each reply on its own line, no numbering, no quotes, no preamble.\(macroContext)

            \(transcript)
            """
            return await self.chat(query: prompt)
        }
        let cleaned: [String] = raw
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: " -•*\"'1234567890.")) }
            .filter { !$0.isEmpty && $0.count <= 120 }
        return Array(cleaned.prefix(3))
    }

    // MARK: - Discover: trending topic summaries

    /// One-line AI summaries for the Discover "Trending now" rail. Takes
    /// the top topics with sample captions and returns topicName -> summary.
    /// Single cached model call for the whole batch — failures return an
    /// empty map so callers keep their local snippet fallbacks.
    func trendingSummaries(topics: [(name: String, captions: [String])]) async -> [String: String] {
        guard !topics.isEmpty else { return [:] }
        let body = topics
            .map { "\($0.name):\n\($0.captions.joined(separator: "\n"))" }
            .joined(separator: "\n---\n")
        let key = "trend:\(body.hashValue)"
        let raw = await cached(key: key) {
            let prompt = """
            For each fitness community topic below, write ONE line summarizing what people are actually saying right now based on the sample post captions (max 14 words, plain language, no hashtags, no emojis, no quotes). Reply with exactly one line per topic in the format `TopicName :: summary` and nothing else.

            \(body)
            """
            return await self.chat(query: prompt)
        }
        var map: [String: String] = [:]
        for line in raw.split(whereSeparator: \.isNewline) {
            let parts = line.components(separatedBy: "::")
            guard parts.count >= 2 else { continue }
            let name = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: " `-*\u{2022}"))
            let summary = parts[1...].joined(separator: "::").trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, !summary.isEmpty, summary.count <= 160 {
                map[name] = summary
            }
        }
        return map
    }

    // MARK: - DM: ask about a user

    func summarizeUser(username: String, recentPosts: [WhisperPost]) async -> String {
        let snippet = recentPosts.prefix(15).map { "[\($0.kind.label)] \($0.caption)" }.joined(separator: "\n")
        let key = "user:\(username):\(snippet.hashValue)"
        return await cached(key: key) {
            let prompt = """
            Summarize what's been going on with @\(username) based on their recent Whisper posts. \
            Give 2-3 sentences: training focus, any PRs or wins, vibe. Friendly, like briefing a friend before they text them. \
            If posts are sparse, say so honestly.

            Recent posts:
            \(snippet.isEmpty ? "(no posts available)" : snippet)
            """
            return await self.chat(query: prompt)
        }
    }

    // MARK: - DM: thread summary (for inbox preview)

    func summarizeThread(messages: [WhisperMessageRow], mineID: String) async -> String {
        guard messages.count >= 10 else { return "" }
        let tail = Array(messages.suffix(20))
        let transcript = tail.map { m in
            let who = m.from_user_id.lowercased() == mineID.lowercased() ? "Me" : "@\(m.from_username)"
            return "\(who): \(m.body)"
        }.joined(separator: "\n")
        let key = "thrd:\(transcript.hashValue)"
        return await cached(key: key) {
            let prompt = """
            Summarize this DM thread in ONE short sentence (under 90 chars). Focus on the latest plan or open question. No preamble.

            \(transcript)
            """
            return await self.chat(query: prompt)
        }
    }

    // MARK: - Composer: draft review

    nonisolated struct DraftReview: Sendable {
        let rewrites: [String]
        let hashtags: [String]
        let warning: String?
    }

    func reviewDraft(caption: String, kind: WhisperPostKind) async -> DraftReview {
        let key = "draft:\(kind.rawValue):\(caption.hashValue)"
        let raw = await cached(key: key) {
            let prompt = """
            You are Knot, helping a user polish a fitness post before publishing. \
            The post type is "\(kind.label)". The current caption is:

            "\(caption)"

            Respond in this EXACT plain-text format (no markdown, no extra text):
            REWRITE1: <a hype version, 1 sentence>
            REWRITE2: <a humble version, 1 sentence>
            REWRITE3: <a story version, 1-2 sentences>
            HASHTAGS: <3-5 relevant tags separated by spaces, each starting with #>
            WARNING: <one short flag if the caption overclaims, sounds unsafe, or pushes restrictive diets — otherwise the single word NONE>
            """
            return await self.chat(query: prompt)
        }
        return Self.parseDraftReview(raw)
    }

    nonisolated static func parseDraftReview(_ raw: String) -> DraftReview {
        var rewrites: [String] = []
        var tags: [String] = []
        var warning: String?
        for line in raw.split(whereSeparator: \.isNewline) {
            let l = String(line).trimmingCharacters(in: .whitespaces)
            if let r = l.range(of: "REWRITE1:", options: .caseInsensitive) {
                rewrites.append(String(l[r.upperBound...]).trimmingCharacters(in: .whitespaces))
            } else if let r = l.range(of: "REWRITE2:", options: .caseInsensitive) {
                rewrites.append(String(l[r.upperBound...]).trimmingCharacters(in: .whitespaces))
            } else if let r = l.range(of: "REWRITE3:", options: .caseInsensitive) {
                rewrites.append(String(l[r.upperBound...]).trimmingCharacters(in: .whitespaces))
            } else if let r = l.range(of: "HASHTAGS:", options: .caseInsensitive) {
                tags = String(l[r.upperBound...])
                    .split(whereSeparator: { $0 == " " || $0 == "," })
                    .map { String($0).trimmingCharacters(in: .whitespaces) }
                    .filter { $0.hasPrefix("#") && $0.count > 1 }
            } else if let r = l.range(of: "WARNING:", options: .caseInsensitive) {
                let w = String(l[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !w.isEmpty, w.uppercased() != "NONE" { warning = w }
            }
        }
        return DraftReview(rewrites: rewrites, hashtags: tags, warning: warning)
    }

    // MARK: - Profile bio writer

    func generateBio(seed: String) async -> String {
        let key = "bio:\(seed.hashValue)"
        return await cached(key: key) {
            let prompt = """
            Write a 1-2 sentence Whisper (fitness social app) bio for a user. \
            Tone: confident, specific, not corny. No emojis unless they fit. Under 140 characters.

            Stats / context: \(seed.isEmpty ? "general fitness user" : seed)
            """
            return await self.chat(query: prompt)
        }
    }

    // MARK: - Comments summary

    func summarizeComments(_ comments: [WhisperCommentRow]) async -> String {
        guard comments.count >= 6 else { return "" }
        let body = comments.prefix(60).map { "@\($0.username): \($0.body)" }.joined(separator: "\n")
        let key = "cmts:\(body.hashValue)"
        return await cached(key: key) {
            let prompt = """
            Summarize this comment thread in 1-2 sentences. Lead with what most people are saying or asking. No preamble.

            \(body)
            """
            return await self.chat(query: prompt)
        }
    }

    // MARK: - Nearby restaurants (DM map embed)

    /// Builds a `WhisperMapEmbed.Payload` of nearby restaurants for the
    /// current user's location, with Jasper-generated menu items (with
    /// macro estimates) so the recipient can log a meal from a friend's
    /// suggestion. Falls back to a curated sample list if location is
    /// unavailable.
    func nearbyRestaurantsPayload(searchHint: String = "restaurants") async -> WhisperMapEmbed.Payload {
        // Try to get the user's current location; otherwise fall back.
        var coord: CLLocationCoordinate2D?
        var label = "Nearby"
        var cityName: String?
        if let ctx = try? await EmberLocationService.shared.requestCurrentContext() {
            coord = .init(latitude: ctx.latitude, longitude: ctx.longitude)
            if let city = ctx.city, !city.isEmpty {
                label = city
                cityName = city
            }
        }
        // MKLocalSearch for real venue results when we have a coordinate.
        // We intentionally leave each place's `menu` empty — the receiving
        // device generates a per-viewer menu via `EmberMenuService` so the
        // ranking can use THEIR remaining macros.
        var places: [WhisperMapEmbed.Place] = []
        if let coord {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = "restaurants"
            request.resultTypes = [.pointOfInterest]
            request.region = MKCoordinateRegion(
                center: coord,
                latitudinalMeters: 2000,
                longitudinalMeters: 2000
            )
            let search = MKLocalSearch(request: request)
            if let response = try? await search.start() {
                places = response.mapItems.prefix(6).map { item in
                    let c = item.placemark.coordinate
                    let name = item.name ?? "Restaurant"
                    return WhisperMapEmbed.Place(
                        id: UUID().uuidString,
                        name: name,
                        category: item.pointOfInterestCategory?.rawValue
                            .replacingOccurrences(of: "MKPOICategory", with: ""),
                        lat: c.latitude,
                        lon: c.longitude
                    )
                }
            }
        }
        if places.isEmpty {
            // Curated fallback so the embed is never empty.
            let baseLat = coord?.latitude ?? 37.7749
            let baseLon = coord?.longitude ?? -122.4194
            places = Self.fallbackPlaces(near: (baseLat, baseLon))
            coord = .init(latitude: baseLat, longitude: baseLon)
        }
        let center = coord!
        _ = searchHint
        return WhisperMapEmbed.Payload(
            id: UUID().uuidString,
            title: "Restaurants near \(label)",
            lat: center.latitude,
            lon: center.longitude,
            radiusMeters: 1500,
            places: places,
            city: cityName
        )
    }

    nonisolated private static func fallbackPlaces(near: (Double, Double)) -> [WhisperMapEmbed.Place] {
        let names: [(String, String, Double, Double)] = [
            ("Sweetgreen",      "Salads & bowls",      0.0030, -0.0020),
            ("Chipotle",        "Mexican grill",       -0.0025, 0.0018),
            ("CAVA",            "Mediterranean",       0.0040,  0.0030),
            ("Shake Shack",     "Burgers",            -0.0010, -0.0040),
            ("Tender Greens",   "Healthy plates",      0.0020,  0.0042)
        ]
        return names.map { (n, cat, dlat, dlon) in
            WhisperMapEmbed.Place(
                id: UUID().uuidString,
                name: n,
                category: cat,
                lat: near.0 + dlat,
                lon: near.1 + dlon
            )
        }
    }

    // MARK: - Recipe payload (/recipe slash command)

    /// Builds a `WhisperRecipeEmbed.Payload` for a dish so the user can send
    /// a full recipe card with ingredients, steps, and an inline "Log to my
    /// macros" button. Falls back to a minimal text-only payload if the web
    /// search stack fails.
    func recipePayload(for dish: String) async -> WhisperRecipeEmbed.Payload {
        let trimmed = dish.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "Today's recipe" : trimmed
        if let r = try? await EmberWebSearchService().searchRecipe(for: title, ingredients: []) {
            let est = await Self.estimateMacros(for: title)
            return WhisperRecipeEmbed.Payload(
                id: UUID().uuidString,
                title: r.recipeName ?? title,
                summary: r.summary ?? "A balanced recipe Knot pulled together for you.",
                prepTime: r.prepTime,
                cookTime: r.cookTime,
                servings: r.servings,
                ingredients: r.ingredients ?? [],
                steps: r.steps ?? [],
                calories: est.calories,
                protein: est.protein,
                carbs: est.carbs,
                fat: est.fat
            )
        }
        return WhisperRecipeEmbed.Payload(
            id: UUID().uuidString,
            title: title,
            summary: "Couldn't reach the recipe stack right now — try again in a sec.",
            prepTime: nil, cookTime: nil, servings: nil,
            ingredients: [], steps: [],
            calories: nil, protein: nil, carbs: nil, fat: nil
        )
    }

    nonisolated struct MacroEstimate: Sendable {
        let calories: Int
        let protein: Double
        let carbs: Double
        let fat: Double
    }

    /// Estimate macros for a free-text food description ("chicken burrito
    /// bowl", "slice of pizza", "two scrambled eggs and toast"). Used by
    /// `/log <food>` and the recipe builder.
    nonisolated static func estimateMacros(for foodDescription: String) async -> MacroEstimate {
        guard RorkAIProxy.isConfigured else {
            return MacroEstimate(calories: 400, protein: 25, carbs: 40, fat: 15)
        }
        let prompt = """
        Estimate macros for: "\(foodDescription)" (single typical serving). \
        Respond ONLY with strict JSON: {\"calories\":0,\"protein\":0,\"carbs\":0,\"fat\":0}.
        """
        var request = RorkAIProxy.chatRequest(timeout: 20)
        let body = OpenAIChatRequest(
            model: RorkAIProxy.chatModel,
            messages: [
                OpenAIChatMessage(role: "system", content: "You are a nutrition estimator. Strict JSON only."),
                OpenAIChatMessage(role: "user", content: prompt)
            ],
            max_tokens: 120
        )
        guard let httpBody = try? JSONEncoder().encode(body) else {
            return MacroEstimate(calories: 400, protein: 25, carbs: 40, fat: 15)
        }
        request.httpBody = httpBody
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let decoded = try? JSONDecoder().decode(OpenAIChatResponse.self, from: data),
              let content = decoded.choices?.first?.message.content else {
            return MacroEstimate(calories: 400, protein: 25, carbs: 40, fat: 15)
        }
        var cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let s = cleaned.firstIndex(of: "{"), let e = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[s...e])
        }
        struct Wrap: Codable { let calories: Int?; let protein: Double?; let carbs: Double?; let fat: Double? }
        if let json = cleaned.data(using: .utf8), let w = try? JSONDecoder().decode(Wrap.self, from: json) {
            return MacroEstimate(
                calories: w.calories ?? 400,
                protein: w.protein ?? 25,
                carbs: w.carbs ?? 40,
                fat: w.fat ?? 15
            )
        }
        return MacroEstimate(calories: 400, protein: 25, carbs: 40, fat: 15)
    }

    /// Vision-based macro estimate from an image URL (a meal photo shared in
    /// a DM). Used by the "Log this meal with Jasper" context-menu action.
    nonisolated static func estimateMacros(forImageURL imageURL: URL) async -> (label: String, macros: MacroEstimate)? {
        guard RorkAIProxy.isConfigured else { return nil }

        struct VisionContent: Encodable {
            let type: String
            let text: String?
            let image_url: ImageURL?
            struct ImageURL: Encodable { let url: String }
        }
        struct VisionMessage: Encodable {
            let role: String
            let content: [VisionContent]
        }
        struct VisionRequest: Encodable {
            let model: String
            let messages: [VisionMessage]
            let max_tokens: Int
        }

        let prompt = """
        You see a photo of food. Name the dish in 2-4 words and estimate macros \
        for a single typical serving. Respond ONLY with strict JSON: \
        {\"name\":\"...\",\"calories\":0,\"protein\":0,\"carbs\":0,\"fat\":0}.
        """
        let req = VisionRequest(
            model: RorkAIProxy.chatModel,
            messages: [
                VisionMessage(role: "system", content: [VisionContent(type: "text", text: "You are Knot, a nutrition vision assistant. Strict JSON only.", image_url: nil)]),
                VisionMessage(role: "user", content: [
                    VisionContent(type: "text", text: prompt, image_url: nil),
                    VisionContent(type: "image_url", text: nil, image_url: .init(url: imageURL.absoluteString))
                ])
            ],
            max_tokens: 200
        )
        var request = RorkAIProxy.chatRequest(timeout: 30)
        guard let body = try? JSONEncoder().encode(req) else { return nil }
        request.httpBody = body
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let decoded = try? JSONDecoder().decode(OpenAIChatResponse.self, from: data),
              let content = decoded.choices?.first?.message.content else {
            return nil
        }
        var cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let s = cleaned.firstIndex(of: "{"), let e = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[s...e])
        }
        struct Wrap: Codable { let name: String?; let calories: Int?; let protein: Double?; let carbs: Double?; let fat: Double? }
        guard let json = cleaned.data(using: .utf8),
              let w = try? JSONDecoder().decode(Wrap.self, from: json) else { return nil }
        return (
            w.name ?? "Meal",
            MacroEstimate(
                calories: w.calories ?? 400,
                protein: w.protein ?? 25,
                carbs: w.carbs ?? 40,
                fat: w.fat ?? 15
            )
        )
    }

    // MARK: - Internals

    private var whisperSystemPrompt: String {
        let personality = EmberPersonalityService.shared.promptBlock
        return """
        You are Knot, the in-app coach for a fitness social app called Whisper. \
        You help users craft replies, write captions, summarize threads, and give honest, friendly feedback on workouts and posts. \
        Keep it short, human, and specific. Never say you're an AI. Never use markdown.\(personality)
        """
    }

    /// Live macro snapshot from `NutritionStore` formatted for prompts.
    /// Jasper sees the viewer's day-so-far + remaining goals on every
    /// request so replies can ground themselves in real numbers without
    /// the call site having to opt in.
    nonisolated static func macroSnapshot() -> String {
        // Hop to the main actor synchronously so the snapshot is current.
        return MainActor.assumeIsolated {
            let s = NutritionStore.shared
            return """
            Viewer macros today (Whisper): \(s.totalCalories)/\(s.goals.calories) cal, P \(Int(s.totalProtein))/\(Int(s.goals.protein))g, C \(Int(s.totalCarbs))/\(Int(s.goals.carbs))g, F \(Int(s.totalFat))/\(Int(s.goals.fat))g. Remaining: \(s.caloriesRemaining) cal, \(Int(s.proteinRemaining))g protein, \(Int(s.carbsRemaining))g carbs, \(Int(s.fatRemaining))g fat.
            """
        }
    }

    private func chat(query: String) async -> String {
        // Reconcile with Whisper's per-row meals table before snapshotting
        // so Jasper's macro math reflects anything the Whisper RN app just
        // logged (or anything logged from another device).
        await NutritionStore.shared.refreshFromWhisper()
        let healthContext = Self.macroSnapshot()
        // Team-authored shared rules (Jasper Brain) — the identical block the
        // web app injects, so Jasper's voice matches across platforms.
        let brain = await WhisperJasperBrainService.shared.block()
        let finalQuery = brain.map { "\($0)\n\n\(query)" } ?? query
        do {
            return try await service.chat(query: finalQuery, healthContext: healthContext, maxTokensOverride: 400)
        } catch {
            return ""
        }
    }

    /// In-memory cache + inflight dedup. Falls back to live call.
    private func cached(key: String, fetch: @escaping () async -> String) async -> String {
        if let hit = cache[key] { return hit }
        if inflight.contains(key) {
            // Wait briefly for the inflight call to land, then return whatever is cached.
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(200))
                if let hit = cache[key] { return hit }
            }
            return cache[key] ?? ""
        }
        inflight.insert(key)
        let result = await fetch()
        inflight.remove(key)
        if !result.isEmpty { cache[key] = result }
        return result
    }
}
