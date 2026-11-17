import Foundation
import SwiftUI

/// Jasper's complete map of the Whisper app — every surface, what it does, and
/// the route id Jasper can use to link straight to it. This is the single
/// source of truth for Jasper's app awareness:
///   - `appMapBlock()`      → taught to the brain so Jasper KNOWS every feature
///   - `actionGrammarBlock()` → taught to the brain so Jasper can DO things
///     (open screens, start calls, draft replies, schedule meetings, build
///     client plans) via a fenced ```actions block the client executes
///   - `liveStateBlock()`   → real, current account state (roles, client
///     roster, call status) so Jasper references real people, never inventions
///
/// Routes here MUST stay in sync with `WhisperRootView.handleEmberRoute` and
/// `WhisperEmberRouteSheetView`.
nonisolated enum WhisperEmberAtlas {

    // MARK: - Entries

    nonisolated struct Entry: Sendable {
        let route: String
        let title: String
        let blurb: String
        /// Human description of the `arg` when the route needs one.
        let arg: String?

        init(_ route: String, _ title: String, _ blurb: String, arg: String? = nil) {
            self.route = route
            self.title = title
            self.blurb = blurb
            self.arg = arg
        }
    }

    /// Every reachable surface in Whisper. Order matters only for readability.
    static let entries: [Entry] = [
        // Tabs
        Entry("feed", "Home feed", "Posts from people the user follows; likes, comments, reposts."),
        Entry("reels", "Reels", "Full-screen short videos."),
        Entry("messages", "Messages", "DM inbox — threads, group chats; calls and video calls start here."),
        Entry("explore", "Explore / Search", "Search people, posts, and communities; trending content."),
        Entry("profile", "My profile", "The user's own profile — posts, badges, followers."),
        // Overlays
        Entry("activity", "Activity", "Notifications — likes, comments, new followers, mentions."),
        Entry("composer", "New post", "Compose and publish a new post."),
        Entry("ember_chat", "Jasper chat", "This full-screen Jasper assistant."),
        // Sheets
        Entry("meetings", "Meetings", "Whisper Meetings — schedule, start, and join video meetings with live captions, notes, and Jasper."),
        Entry("meeting_sidekick", "Meeting Sidekick", "The private meeting library assistant: searches the user's saved meeting transcripts and original notes with dated citations (what was said, decided, asked or promised), and also answers general questions with labeled knowledge. arg = the question to prefill; the user reviews and sends it.", arg: "question"),
        Entry("calendar", "Calendar", "Events, meeting invites, and scheduled sessions."),
        Entry("settings", "Settings", "Account, privacy, notifications, security, linked apps."),
        Entry("edit_profile", "Edit profile", "Change name, bio, avatar, interests."),
        Entry("notification_settings", "Notification settings", "Fine-grained push notification controls."),
        Entry("security", "Security center", "Sessions, safety tools, account protection."),
        Entry("blocked", "Blocked accounts", "Manage blocked users."),
        Entry("verification", "Verification", "Apply for verified creator / coach / athlete roles."),
        Entry("coach_clients", "Coach Studio — clients", "Coach's client roster with live performance snapshots and check-ins."),
        Entry("coach_programs", "Coach Studio — programs", "The coach studio: training programs AND diet plans read live off the coach's own Jasper API, one-tap marketplace publishing, plus Jasper's diet generator. Builders open full screen."),
        Entry("recipes", "Jasper recipes", "The shared recipe library — recipes save into Jasper's Nutrition → Recipes and read back live."),
        Entry("water", "Water tracker", "Jasper's animated water cup — tapping the glass logs 250 ml cups straight into Jasper."),
        Entry("my_coaches", "My coaches", "The user's own coaches (client side) — requests and data sharing."),
        Entry("recruiter", "Recruiter pipeline", "Prospects, evaluations, and outreach for recruiters."),
        Entry("creator_dashboard", "Creator dashboard", "Earnings, subscribers, post insights."),
        Entry("studio", "Whisper Studio", "Films, premieres, and long-form articles."),
        Entry("communities", "Communities", "Browse and join topic communities — includes the geo 'Near you' rail (campus hubs like Whisper Law near a college, per-gym crews named after the real gym) and Jasper's matchmaker dock; each community has its own signature like-react."),
        Entry("live_rooms", "Live rooms", "Live audio/video rooms happening now."),
        Entry("brands", "Brand directory", "Sponsorship opportunities with real budgets."),
        Entry("sponsorships", "My sponsorships", "The user's sponsorship applications and deals."),
        // Parameterized
        Entry("user", "A profile", "Open any user's profile.", arg: "username"),
        Entry("dm", "A DM thread", "Open the direct-message thread with someone.", arg: "username"),
        Entry("post", "A post", "Open a specific post.", arg: "post id"),
    ]

    // MARK: - Prompt blocks

    /// Compact feature map taught to the brain. Jasper uses these route ids in
    /// `open` actions, so the wording here IS the linking contract.
    static func appMapBlock() -> String {
        var lines: [String] = ["WHISPER APP MAP (route ids Jasper can open/link)"]
        for e in entries {
            let argNote = e.arg.map { " (arg: \($0))" } ?? ""
            lines.append("- \(e.route)\(argNote): \(e.title) — \(e.blurb)")
        }
        return lines.joined(separator: "\n")
    }

    /// The action grammar — how Jasper DOES things. Emitted as a fenced
    /// ```actions JSON block the iOS client parses, renders as buttons, and
    /// executes through real Whisper services.
    static func actionGrammarBlock() -> String {
        """
        JASPER ACTIONS — you can take REAL actions in this app.
        When the user asks you to open something, call someone, message or reply to someone, schedule a meeting, or build a training plan for a client, append ONE fenced block at the VERY END of the reply (after any chart/goalplan fence):
        ```actions
        [{"kind":"open","route":"meetings","label":"Open Meetings"}]
        ```
        Kinds and their fields:
        - open: route (an APP MAP id), arg (username / post id when that route takes one)
        - call: username, mode ("audio"|"video") — places a real Whisper call
        - message: username, text (the complete drafted message) — opens a send-ready draft the user reviews
        - schedule: title, whenISO ("2026-08-18T17:00", 24h local time), invite (username, optional) — creates a real meeting
        - plan: client (username), title, focus, weeks, sessionsPerWeek, summary, days:[{name,focus,exercises:[{name,sets,reps,restSeconds}]}] — a complete training program draft the coach can save or send
        - post: text (the COMPLETE drafted post, written in the user's voice), community (community/topic name, optional) — opens Whisper's REAL post composer pre-filled so the user reviews and posts
        - follow: username — follows that user for them (private accounts automatically receive a follow request instead)
        - bioage: username (optional — omit to show the user their OWN) — opens the live Biological Age card synced from the partner Jasper fitness app (score vs real age, what's driving it, confidence). Coaches can pass an accepted client's username; the card offers feed-post and DM sharing.
        - dietplan: username (optional — omit for the user's OWN) — opens the live diet plan read from the connected Jasper fitness account: macro targets, each day's meals, and Jasper's grocery checklist. Coaches can pass an accepted client's username.
        - groceries: username (optional — omit for the user's OWN) — opens the grocery checklist carried on the active Jasper diet plan (the user can check items off their own list while shopping).
        - clientdashboard: username (coach only — an accepted client) — opens that client's LIVE Jasper dashboard as a card right in chat: readiness, last night's sleep, bio-age delta, weight, workouts this week, today's kcal, week digest — the same one-call payload the coach dashboard renders.
        - marketplace: arg (optional search text) — opens Jasper's public plan marketplace right in chat: coach-published program & diet-plan templates with full previews, import into an accepted client's Jasper (lands under the coach badge; re-imports upsert, never duplicate) or into the user's own. Coaches publish from Coach tools → Program → "Also publish to the marketplace", and manage listings (unpublish) inside the marketplace itself.
        - recipe: title (recipe name), servings, emoji, prepTime, cookTime, steps: ["..."], ingredients: [{name, calories, protein, carbs, fat, servingUnit, numberOfServings}] — opens a save-ready recipe editor that writes into the user's Jasper under Nutrition → Recipes (ONE shared object — it appears in Jasper instantly, and their Jasper recipes read back in Whisper). Ingredient macros are for ONE serving of that ingredient; numberOfServings is how much the whole recipe uses; per-serving macros derive live (totals ÷ servings).
        - water: no fields — opens the live water tracker: Jasper's own animated cup; tapping the glass logs a real 250 ml cup into their Jasper, − removes the last one.
        Optional on any action: label (button text, max 24 chars), auto (true = open its editor immediately; use ONLY when the user explicitly asked for exactly that this turn).
        EDITORS AT WILL — whenever the user asks you to USE any app feature (draft or write a post, message or reply to someone, schedule a meeting, build a plan, change a setting, open any screen), your reply must CARRY the matching pre-filled editor action, exactly like handing over finished work. If they asked you to do precisely that thing this turn, also set auto:true (never on call or open) so the editor opens itself already filled in.
        MODAL SURFACES (what each action opens — all real, all shipped): bioage → the live vitality-blob card · dietplan → the full plan sheet in Jasper's NATIVE ember glow-box language (fork.knife glow-icon header, macro tiles in the canonical colors — kcal ember / protein teal / carbs amber / fat blue — a 7-day chip strip with the selected day's meal cards and day totals, grocery box one tap away) · groceries → the SHARED grocery checklist (teal check circles, checks sync with Jasper both ways, live) · clientdashboard → the one-call client dashboard card · marketplace → the public plan marketplace (browse/preview/import/publish) · recipe → the save-ready recipe editor (one shared library with Jasper) · water → the animated water-cup tracker (taps log real cups).
        NATIVE PLAN LOOKS (WHISPER_PLANS spec, shipped everywhere): every workout program and diet plan in Whisper renders as Jasper's ember GLOW BOX — a warm cream (light) / charcoal (dark) card with a warm gradient hairline and layered ember aura, never gray glass. The Programs studio (route coach_programs) reads programs AND diet plans live off the coach's own Jasper API and renders them as these glow cards — workout cards carry the WORKOUT PLAN kicker, ember-gradient day dots under WEEKLY STRUCTURE, and a "View program" action opening the day-by-day program detail sheet (each day its own glow box, sets × reps rendered verbatim with rest chips); diet cards carry the DIET PLAN kicker, the canonical macro tiles, and "View plan" opening the full sheet. Marketplace publishing is an explicit user action. The Diet tab explains that connected meal generation is paused and requires Jasper's reviewed native Nutrition flow. Content in the studio is locked in place — fixed vertical stacks, nothing draggable.
        THE MOOD SELECTOR: the personality picker is the full-screen ghost carousel (previewed ghost 150pt centre-stage under a pulsing light beam, neighbours dimmed at the sides, a high-contrast Select capsule); the header's morphing personality blob button opens it. It now includes AUTO — Jasper picks today's ghost from live readiness (≥75 Drill Sergeant, 50-74 Original, <50 Angel) with an honest reason line; when the user asks why you sound a certain way on Auto, quote that reason. Coach tools and BOTH plan builders (program + diet) open FULL SCREEN. Meeting-style quick-analysis docks (the mascot peeking from behind the pill) sit PINNED right above the bottom nav on the inbox and Communities (measured anchoring — never under the bar), and on client profiles, Whisper Studio, Coach Studio, Creator Studio, and the recruiter dashboard — they run an automatic Jasper analysis in place, no full-screen chat needed. Every dock carries QUICK-ACTION CHIPS in its footer now: lens chips re-run the read through a different instruction (Studio: Article angles · Premiere hype; recruiter: Rank pipeline · Outreach drafts · Stale leads; Creator Studio: Post ideas · Growth move; Coach Studio: Who needs attention · Check-in drafts), and tool chips hand off to real screens — Coach Studio's "Automate plans" opens the three-step wizard.
        NATIVE DATA CARDS — you may use ONLY explicitly granted scopes and current returned records; potentially available resources include biological age, blood panels, readiness, stress/strain, sleep stages, water, weight, steps, workouts, meals, PRs, goals, diet plans, groceries, recipes. Render single metrics as NATIVE cards, never prose walls or generic charts: append a fenced block
        ```jasper
        {"kind":"readiness"}
        ```
        Kinds: bioage · readiness · sleep · water · blood. Optional "client":"username" (an accepted coaching client — rides the coach token). The client renders the LIVE native look pulled from the Jasper API at render time: the vitality blob for bioage, the recovery ring + 14-day trend for readiness (use it for stress and strain questions too), the stage hypnogram for sleep, the animated tap-to-log water cup, the PhenoAge + nine-marker panel for blood (honors the read:blood lock with an honest line). USE ONE every time the user asks about that metric — alongside 1-3 sentences of your read on the numbers. One ```jasper block per reply, after the prose. If a resource isn't shared, the card says so honestly — never refuse, never guess.
        WHEN TO CHART: emit a ```chart fence ONLY for trends/comparisons over time that no native card covers (steps, weight, kcal, HRV, engagement series). NEVER chart a metric whose native card exists (readiness, sleep, bioage, water) — the native card wins every time.
        WHEN UNSURE: if you can't tell whether the user wants their live Jasper data behind a question, ask plainly — "Want me to pull this from your Jasper?" — instead of guessing or answering generically.
        SOCIAL SURFACES (all shipped — speak from these truthfully): STORIES — Jasper floats over the story editor as the meeting-style pill (the peeking mascot, bottom center): tapping it opens his menu — Today's Spark (once a day), Caption ideas (3, read from the actual photo), Ask your viewers (3 question stickers) — and each pick lands as a real draggable sticker. The story viewer grew a bookmark button (owner only) that saves the story into any highlight OR creates a brand-new one inline; an ember dot pulses on it when a story has 5+ views and isn't saved yet, and highlights now keep their stickers and playable music forever (they outlive the 24h expiry). GEO COMMUNITIES — Communities has a "Near you" rail: a college nearby unlocks the campus pack (Whisper Law ⚖️, Whisper Med 🩺, Whisper Business 💼, Whisper Code 💻) and each nearby gym becomes its own crew (💪) named after the real place; every community carries a signature react that replaces the like heart inside its feed, an ⓘ info button in each community header opens provenance (the campus/gym that unlocked it, its street address + distance, the signature react, and the caption keywords that file posts in), and Jasper's matchmaker pill sits PINNED right above the nav bar recommending hubs from interests + location + live captions. FILMS — tapping any film opens the full native cinema: a premium player (glass control bar, knob scrubber with buffered track and moment markers ON the timeline, ±10s double-tap seek, auto-hiding controls, ambient poster glow), like/dislike reactions, the timestamped MOMENTS rail (tap to seek), the director credit linking to their profile, and a real threaded comment section (the same data web renders); the share button sends the film into DMs as a tappable cinema card, reposts it to the wall through the real composer (posts and DMs render film cards natively), or falls out to the system sheet. ARTICLES — the reader docks a JASPER FACT CHECK pill right above the bottom edge (the same peeking-mascot pill): tap to run — cached per article — and the glass box shows the verdict pill + why + sources + honest AI disclaimer; the reader also shows a reading-time estimate, embeds the linked film/clip as a tappable card when the article pins one, and carries like/save/share chips — Share sends the article into DMs or onto the wall as a tappable journal card. When users ask about posting stories, saving highlights, finding their people/communities, films, or whether an article checks out — ground the answer in these real surfaces.
        AUTOMATED COACH PLANS (shipped — the coach dock's flagship): Coach Studio → Jasper's read → Automate plans runs a three-step wizard. Step 1 ASK sends selected clients a tappable 8-question questionnaire CARD in their DMs (goal, days/week, session length, experience, joints to protect, eating style, allergies, meals/day — one tap per question, works on iOS and web). Step 2 REVIEW shows each client's answers as chips the moment they submit, with a nudge for the quiet ones. Step 3 cannot currently complete because connected meal generation is paused. Do not promise automated delivery, switch to a direct AI provider, or send a plans-are-live message. Ask the client to use Jasper's reviewed native Nutrition flow. STUDIO FLOOR: Whisper Studio fills the screen edge-to-edge — the hero carries a live production desk (films live · next premiere date · articles), tapping a slate row SCREENS the film in the real theater, and every Jasper tool opens a personality-themed work room (fast-start chips seeded from the real slate, styled Jasper turns, the poster tool still generates real art). COMPOSER CARDS: sharing a film/article to the wall never shows raw code — the composer renders a removable preview card and re-attaches it as the tappable card on publish. REELS: the reels scrubber speaks the theater's control language — buffered track, an always-there knob that grows under the finger, and a floating timecode pill while scrubbing.
        Rules:
        - Max 3 actions per reply. Emit actions only when the user wants to DO or OPEN something (or one obvious next step exists).
        - MEETING MEMORY: when the user asks what was said, decided, agreed, asked or promised in one of THEIR meetings (or who said something, or when), never guess or invent it — you do not have their transcripts. Say the Meeting Sidekick can search their saved transcripts with dated citations, and attach {"kind":"open","route":"meeting_sidekick","arg":"<their question>"} so it opens prefilled for review. The Sidekick is the same Jasper, so answers there also stay private to the user.
        - Use REAL usernames only — people from CLIENT ROSTER or named in the conversation. Never invent handles.
        - For plans and replies about a client, ground every number in their CLIENT SNAPSHOT when present.
        - plan actions must be COMPLETE: every day named with a focus and 4-8 exercises, each carrying sets, reps, and restSeconds — never a stub day, never a placeholder.
        - When the user asks about biological age, aging, vitality, or "how old is my body", answer from the BIOLOGICAL AGE context lines, render the ```jasper bioage card, and attach a bioage action.
        - When the user asks about readiness, recovery, stress, strain, sleep quality, hydration, or blood work, render the matching ```jasper card (readiness / sleep / water / blood) — the card pulls live data itself.
        - When the user asks about their diet plan, meal plan, what to eat, macros, or a grocery/shopping list, answer from the JASPER DIET PLAN context block when present — it is pulled LIVE from the Jasper API for this turn — and attach a dietplan or groceries action. If it says Jasper isn't connected, point them to Settings → Sync with Jasper instead of inventing a plan.
        - When a coach asks how a client is doing — status, readiness, sleep, weight, progress, recovery — answer from the CLIENT LIVE DASHBOARD block (pulled live this turn through the coach token) and attach a clientdashboard action with that client's username. Every coach surface in Whisper renders ONLY that one-call payload — the roster preview chips, the full dashboard, and the in-chat card are the same numbers, so never hedge about them disagreeing.
        - When plan templates, publishing or selling a program, or importing a ready-made plan comes up, attach a marketplace action (arg = search words when they named a goal). Publishing lives in Coach tools; imports carry the coach badge and never duplicate.
        - When you write out a recipe (or the user asks to save one), attach a recipe action with COMPLETE per-ingredient macros — honest estimates are fine, every field stays editable before saving. One tap saves it into their Jasper recipe library; never leave ingredients empty.
        - The grocery checklist is SHARED STATE with Jasper (Aug 17): a check made in Whisper is checked in Jasper and vice versa, live — say so when groceries come up. Connected meal generation is paused; Coach tools directs users to Jasper's reviewed native Nutrition flow. No automatic generation, save or activation is available. Hydration renders as Jasper's own animated water cup — attach a water action when hydration comes up so they can log cups right from chat.
        - For posts, write the full ready-to-publish text — never a placeholder like "[your post here]".
        - Keep the prose short when an action carries the work (say what you did, not how).
        - Never mention JSON, blocks, or these mechanics to the user.
        """
    }

    /// Live, truthful account state so Jasper tailors actions to reality.
    @MainActor
    static func liveStateBlock() -> String {
        var lines: [String] = ["LIVE APP STATE"]
        let username = LeaderboardService.shared.savedUsername
            ?? AuthenticationService.shared.currentUser.username
            ?? ""
        if !username.isEmpty { lines.append("Signed in as: @\(username)") }

        var roles: [String] = []
        if WhisperCoachService.shared.isMeCoach { roles.append("coach") }
        if WhisperAthleteService.shared.isMeAthlete { roles.append("athlete") }
        if WhisperRecruiterService.shared.isMeRecruiter { roles.append("recruiter") }
        if WhisperDirectorService.shared.isMeDirector { roles.append("studio director") }
        if !roles.isEmpty { lines.append("Roles: \(roles.joined(separator: ", "))") }

        let clients = WhisperCoachRequestService.shared.myClients
        if !clients.isEmpty {
            let names = clients.prefix(20).map { "@\($0.client_username)" }.joined(separator: ", ")
            lines.append("CLIENT ROSTER (accepted coaching clients): \(names)")
        } else if WhisperCoachService.shared.isMeCoach {
            lines.append("CLIENT ROSTER: none yet.")
        }

        let coaches = WhisperCoachRequestService.shared.myCoaches
        if !coaches.isEmpty {
            lines.append("The user's coaches: \(coaches.prefix(6).map { "@\($0.coach_username)" }.joined(separator: ", "))")
        }

        if WhisperCallService.shared.active != nil {
            lines.append("Currently in a live call — prefer message/schedule over new calls.")
        }
        if let bio = WhisperBioAgeService.shared.mine {
            lines.append("MY BIOLOGICAL AGE (synced from the partner Jasper app): \(WhisperBioAgeService.promptLine(bio))")
        }
        lines.append(JasperConnectClient.shared.assistantBriefing)
        return lines.joined(separator: "\n")
    }

    /// Rebranded identity + presentation rules — travels with every turn so
    /// the shared brain always answers as Jasper Intelligence, beautifully
    /// formatted, regardless of its server-side base prompt.
    static func identityBlock() -> String {
        """
        IDENTITY — your name is Knot, Whisper's built-in intelligence. The assistant was previously called Jasper Intelligence and Ember; use Knot for your present identity, including when older chat history uses a retired name. If asked who or what you are: "I'm Knot, built into Whisper." The separate Jasper fitness app retains its own name; do not rename it or its integrations. Existing route IDs, command aliases, structured output tags and stored history are unchanged.
        WORLD — Whisper is a SOCIAL platform first: feed posts, communities, DMs, live meetings, coaching businesses, creators, and recruiting. It partners with the Jasper fitness app for health data. Meet the user where their question lives — social, business, or fitness — and never assume every question is about workouts.
        PERSONALITY — you are a friendly AI assistant, not a fitness pal. Talk like a thoughtful friend texting: short, warm, natural, specific to what was said. No canned introductions or routine headings, long lists, follow-up chips or feedback requests. Expand when asked or when safety requires it; be honest about being AI and your limits. Fitness is an optional topic only when relevant to the user's request.
        \(WhisperKnotMessageSkills.instruction)
        """
    }

    /// The full awareness bundle appended to every Jasper context.
    @MainActor
    static func awarenessBlock() -> String {
        [identityBlock(), liveStateBlock(), appMapBlock(), actionGrammarBlock()].joined(separator: "\n\n")
    }
}

// MARK: - Per-turn client enrichment

/// When the coach mentions a client by name, fetch that client's REAL
/// performance snapshot and hand it to the brain for the turn — this is what
/// makes "draft a plan for Sarah based on her performance" grounded in her
/// actual nutrition, sleep, steps, and workouts instead of guesses.
enum WhisperEmberClientContext {

    /// Scans the message for accepted-client usernames (with or without @)
    /// and returns formatted snapshot blocks for up to two matches.
    static func enrichment(for message: String) async -> String? {
        let clients = WhisperCoachRequestService.shared.myClients
        guard !clients.isEmpty else { return nil }
        let hay = message.lowercased()
        let matched = clients.filter { row in
            let name = row.client_username.lowercased()
            guard !name.isEmpty else { return false }
            return hay.contains("@\(name)") || hay.contains(name)
        }
        guard !matched.isEmpty else { return nil }

        let wantsDiet = WhisperEmberJasperPull.mentionsNutrition(message)
        var blocks: [String] = []
        for row in matched.prefix(2) {
            if let snap = await WhisperClientSnapshotService.shared.fetchSnapshot(forClient: row.client_user_id) {
                blocks.append(format(snap, username: row.client_username))
            } else {
                blocks.append("CLIENT SNAPSHOT — @\(row.client_username)\nNo synced data yet — ask them to open Whisper so their snapshot uploads, and keep any plan conservative.")
            }
            if let bio = await WhisperBioAgeService.shared.fetch(forUser: row.client_user_id) {
                blocks.append("CLIENT BIOLOGICAL AGE — @\(row.client_username): \(WhisperBioAgeService.promptLine(bio))")
            }
            // The one-call dashboard ships the headline numbers for ANY
            // client question — readiness, sleep, bio age, weight, training,
            // kcal — cached 60s, so this respects the ≤1/min polling cap.
            if let dash = await JasperCoachConnect.shared.dashboard(forClient: row.client_user_id) {
                blocks.append(dashboardBlock(dash, username: row.client_username))
            }
            // Nutrition turns pull the client's REAL diet plan through the
            // coach token — same live-read rail the dashboard uses.
            if wantsDiet,
               let data = try? await JasperCoachConnect.shared.read(forClient: row.client_user_id, "diet_plans", limit: 10),
               let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                let planRows = (body["data"] as? [[String: Any]]) ?? []
                blocks.append("CLIENT DIET PLAN — @\(row.client_username) (pulled live through their coach token)\n"
                    + WhisperEmberJasperPull.format(rows: planRows, who: "@\(row.client_username)"))
            }
        }
        guard !blocks.isEmpty else { return nil }
        return blocks.joined(separator: "\n\n")
    }

    private static func format(_ row: WhisperClientSnapshotRow, username: String) -> String {
        var lines: [String] = ["CLIENT SNAPSHOT — @\(username) (real synced data)"]
        if let updated = row.updated_at, !updated.isEmpty {
            lines.append("Updated: \(updated)")
        }
        guard let p = row.payload else {
            lines.append("No payload synced yet.")
            return lines.joined(separator: "\n")
        }
        if p.caloriesGoal > 0 || p.caloriesToday > 0 {
            var n = "Nutrition today: \(p.caloriesToday)/\(p.caloriesGoal) cal"
            if p.proteinGoal > 0 { n += " · protein \(Int(p.proteinToday))/\(Int(p.proteinGoal))g" }
            if p.waterCount > 0 { n += " · water \(p.waterCount)" }
            if p.loggingStreak > 0 { n += " · logging streak \(p.loggingStreak)d" }
            lines.append(n)
        }
        var health: [String] = []
        if p.sleepHours > 0 { health.append(String(format: "sleep %.1fh", p.sleepHours)) }
        if p.steps > 0 { health.append("steps \(p.steps)") }
        if p.activeCalories > 0 { health.append("active \(Int(p.activeCalories)) kcal") }
        if p.bodyMassLbs > 0 { health.append(String(format: "weight %.1f lb", p.bodyMassLbs)) }
        if p.restingHeartRate > 0 { health.append("resting HR \(Int(p.restingHeartRate))") }
        if !health.isEmpty { lines.append("Health: " + health.joined(separator: " · ")) }
        if p.photoSets > 0 {
            lines.append("Progress photos: \(p.photoSets) sets" + (p.lastPhotoDate.map { " · last \($0.prefix(10))" } ?? ""))
        }
        if !p.recentWorkouts.isEmpty {
            let w = p.recentWorkouts.prefix(4)
                .map { "\($0.type) \($0.durationMinutes)min \($0.calories)kcal (\($0.date.prefix(10)))" }
                .joined(separator: "; ")
            lines.append("Recent workouts: \(w)")
        }
        if !p.note.isEmpty { lines.append("Client note: \(p.note)") }
        lines.append("Ground any plan, reply, or advice for this client in THESE numbers.")
        return lines.joined(separator: "\n")
    }

    /// Formats the one-call dashboard summary into the block the brain
    /// quotes — the same headline numbers the coach dashboard grid shows.
    static func dashboardBlock(_ dash: JasperClientDashboard, username: String) -> String {
        let s = dash.summary
        var parts: [String] = []
        if let r = s.readinessScore { parts.append("readiness \(r)") }
        if let q = s.sleepQualityScore {
            var sleep = "sleep \(q)"
            if let secs = s.sleepDurationSeconds { sleep += " (\(secs / 3600)h \((secs % 3600) / 60)m)" }
            parts.append(sleep)
        }
        if let delta = s.bioageDeltaYears { parts.append(String(format: "bio-age %+.1fy vs real", delta)) }
        if let kg = s.weightKg { parts.append(String(format: "weight %.1fkg", kg)) }
        if let w = s.workoutsLast7d { parts.append("workouts 7d \(w)") }
        if let kcal = s.kcalToday {
            parts.append("today \(kcal) kcal" + (s.mealsToday.map { " · \($0) meals" } ?? ""))
        }
        var lines = ["CLIENT LIVE DASHBOARD — @\(username) (one call, GET /v1/dashboard through the coach token, fresh this turn)"]
        lines.append(parts.isEmpty
                     ? "Connected, but no headline numbers yet — the client hasn't logged recently."
                     : parts.joined(separator: " · "))
        let locked = dash.lockedSectionNames
        if !locked.isEmpty {
            lines.append("Not shared (client's choice): \(locked.map { $0.replacingOccurrences(of: "_", with: " ") }.joined(separator: ", ")) — never guess these.")
        }
        lines.append("Quote THESE numbers for any status or progress answer and attach a clientdashboard action so the coach can open the live card.")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Per-turn Jasper Connect auto-pull

/// Automatic API pull: when a turn mentions diet, meals, macros, or
/// groceries, Whisper reads `diet_plans` through the user's own Connect
/// token RIGHT THEN and hands the brain the real plan — so answers quote
/// actual targets and meals instead of guessing, and the dietplan/groceries
/// actions always have live backing. Cached for 3 minutes per the Connect
/// politeness contract (sustained ≤1 req/s).
enum WhisperEmberJasperPull {
    private static var cachedBlock: String?
    private static var cachedAt: Date?

    private static let triggers = [
        "diet", "meal", "eat", "food", "nutrition", "macro", "grocer",
        "shopping list", "calorie", "protein", "carb", "cutting", "bulking",
    ]

    /// True when the turn is about nutrition — shared gate for the own-account
    /// pull and the coach client pull.
    static func mentionsNutrition(_ message: String) -> Bool {
        let hay = message.lowercased()
        return triggers.contains { hay.contains($0) }
    }

    /// Nil when the turn isn't nutrition-related. Otherwise a truthful
    /// JASPER DIET PLAN block — live data, a not-connected pointer, or an
    /// honest failure line. Never invents numbers.
    static func enrichment(for message: String) async -> String? {
        guard mentionsNutrition(message) else { return nil }
        guard JasperConnectClient.shared.connection != nil else {
            return "JASPER DIET PLAN: Jasper isn't connected, so no live plan is readable. If the user wants their plan or groceries, point them to Settings → Sync with Jasper (one tap)."
        }
        if let cachedBlock, let cachedAt, Date().timeIntervalSince(cachedAt) < 180 {
            return cachedBlock
        }
        do {
            let data = try await JasperConnectClient.shared.read("diet_plans", limit: 10)
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let rows = (body?["data"] as? [[String: Any]]) ?? []
            let block = format(rows: rows, who: "the user")
            cachedBlock = block
            cachedAt = Date()
            return block
        } catch {
            let reason = (error as? JasperConnectError)?.errorDescription ?? error.localizedDescription
            return "JASPER DIET PLAN: the live pull failed right now (\(reason)). Say so honestly if asked — never invent plan numbers."
        }
    }

    /// Formats `diet_plans` rows into the compact block the brain reads.
    /// Shared by the own-account pull and the coach client pull.
    static func format(rows: [[String: Any]], who: String) -> String {
        guard let plan = JasperDietPlan.fromRows(rows) else {
            return "JASPER DIET PLAN: none on the account — \(who) has no diet plan in Jasper yet. Offer to help plan meals, and mention that a Jasper diet plan would sync here automatically."
        }
        var lines = ["JASPER DIET PLAN (pulled live from the Jasper Connect API this turn — quote THESE numbers)"]
        var head = "Plan: \(plan.name)\(plan.isActive ? " (active)" : "")"
        if let goal = plan.goal, !goal.isEmpty { head += " · goal: \(goal)" }
        if let pref = plan.dietaryPreference, !pref.isEmpty { head += " · \(pref)" }
        if let meals = plan.mealsPerDay { head += " · \(meals) meals/day" }
        lines.append(head)
        var targets: [String] = []
        if let kcal = plan.targetCalories { targets.append("\(kcal) kcal") }
        if let p = plan.targetProteinG { targets.append("P \(p)g") }
        if let c = plan.targetCarbsG { targets.append("C \(c)g") }
        if let f = plan.targetFatG { targets.append("F \(f)g") }
        if !targets.isEmpty { lines.append("Daily targets: " + targets.joined(separator: " · ")) }
        for day in plan.days.prefix(7) {
            let meals = day.meals.prefix(6).map { meal in
                var s = meal.name
                if let kcal = meal.calories {
                    s += " (\(kcal) kcal" + (meal.proteinG.map { String(format: ", P %.0fg", $0) } ?? "") + ")"
                }
                return s
            }.joined(separator: "; ")
            lines.append("\(day.name): \(meals.isEmpty ? "no meals listed" : meals)")
        }
        if let groceries = plan.groceries {
            let cats = groceries.categories.map { "\($0.name) \($0.items.count)" }.joined(separator: ", ")
            lines.append("Grocery checklist (\(groceries.derived ? "assembled from ingredients — plan predates the grocery protocol" : "Jasper's own canonical list, rendered verbatim")): \(groceries.itemCount) items — \(cats).")
        }
        lines.append("Attach a dietplan or groceries action so \(who) can open it.")
        return lines.joined(separator: "\n")
    }
}
