import { jasperRead, jasperToken, jasperMe } from "@/lib/jasperConnect";
import { coachDashboard, friendlyCoachMessage } from "@/lib/jasperCoachConnect";

/**
 * Web port of the iOS `WhisperEmberAtlas` — Jasper Intelligence's awareness
 * bundle. Appended to every turn's context so the web brain is the EXACT
 * same brain as iOS: identity + live app state + the full Whisper app map +
 * the JASPER ACTIONS grammar (all 14 kinds, modal surfaces, rules), plus the
 * standing Jasper Connect briefing, the live diet auto-pull, and the coach
 * client enrichment (one-call dashboard through the coach token).
 *
 * The briefing text blocks are transcribed VERBATIM from iOS — both apps
 * must speak the same grammar.
 */

// MARK: - Identity (verbatim from iOS)

export function jasperIdentityBlock(): string {
  return `IDENTITY — your name is Knot, Whisper's built-in assistant. Ember and Jasper Intelligence are retired assistant names; always introduce yourself as Knot, including when older conversation history uses those names. Jasper is the separate connected fitness app, not your name. If asked who you are: "I'm Knot, your assistant inside Whisper."
WORLD — Whisper is a SOCIAL platform first: feed posts, communities, DMs, live meetings, coaching businesses, creators, and recruiting. It partners with the Jasper fitness app for health data. Meet the user where their question lives — social, business, or fitness — and never assume every question is about workouts.
FORMAT — every answer must be beautiful and glanceable:
- Meaty answers (plans, comparisons, how-tos, 3+ facts): structure them — short "## " section headings, "- " bullets, numbered steps for sequences, **bold** key names and numbers inline.
- Training or nutrition plans, EVERY time: a "## " heading per day or section, "- " bullets with the **exercise or meal name in bold** plus its numbers (sets×reps, rest, grams), and a one-line progression note at the end.
- Simple answers: 1-3 warm sentences, no scaffolding.
- Never a wall of text — break anything long into sections or bullets.
FOLLOW-UPS — after your prose (and after any other fenced block), end EVERY reply with exactly one fenced block:
\`\`\`followups
["Short question 1?", "Short question 2?"]
\`\`\`
containing 2-4 follow-up prompts (max 8 words each, phrased in the user's voice) they might naturally tap next — grounded in what THIS answer actually covered, spanning whichever Whisper surfaces fit (posting, messaging, meetings, clients, recruiting, communities, training) — never fitness-only unless the answer was. Never mention or explain this block in prose.`;
}

// MARK: - App map (route ids Jasper can open/link — same ids as iOS)

interface AppMapEntry {
  route: string;
  arg?: string;
  title: string;
  blurb: string;
  /** Web navigation target ("" = handled as a panel by the action host). */
  path: string;
}

export const JASPER_APP_MAP: AppMapEntry[] = [
  { route: "feed", title: "Home feed", blurb: "The main Whisper feed of posts.", path: "/" },
  { route: "reels", title: "Reels", blurb: "Short-form video feed.", path: "/reels" },
  { route: "messages", title: "Messages", blurb: "DM inbox and threads.", path: "/messages" },
  { route: "explore", title: "Explore", blurb: "Search people, posts, and communities.", path: "/search" },
  { route: "profile", title: "My profile", blurb: "The user's own profile.", path: "/profile" },
  { route: "activity", title: "Activity", blurb: "Notifications and follows.", path: "/notifications" },
  { route: "composer", title: "Post composer", blurb: "Whisper's REAL post composer.", path: "/compose" },
  { route: "ember_chat", title: "Knot", blurb: "This full-screen assistant.", path: "/ember" },
  { route: "meetings", title: "Meetings", blurb: "Live private video meetings.", path: "/meetings" },
  { route: "meeting_sidekick", arg: "question", title: "Meeting Sidekick", blurb: "The private meeting library assistant: searches the user's saved meeting transcripts and original notes with dated citations (what was said, decided, asked or promised), and also answers general questions with labeled knowledge. arg = the question to prefill; the user reviews and sends it.", path: "/notebook?view=jasper&q=" },
  { route: "calendar", title: "Calendar", blurb: "Scheduled meetings and events.", path: "/calendar" },
  { route: "settings", title: "Settings", blurb: "Account settings incl. Sync with Jasper.", path: "/settings" },
  { route: "coach_clients", title: "Coach Studio", blurb: "The coach's client roster with live Jasper dashboards.", path: "/coach" },
  { route: "coach_programs", title: "Coach Studio — programs", blurb: "The coach studio: training programs AND diet plans read live off the coach's own Jasper API, one-tap marketplace publishing, with a native-review notice while connected meal generation is paused. Builders open full screen.", path: "/coach?tab=programs" },
  { route: "recipes", title: "Jasper recipes", blurb: "The shared recipe library — recipes save into Jasper's Nutrition → Recipes and read back live.", path: "" },
  { route: "water", title: "Water tracker", blurb: "Jasper's animated water cup — tapping the glass logs 250 ml cups straight into Jasper.", path: "" },
  { route: "my_coaches", title: "My coaches", blurb: "Coaches the user works with.", path: "/coaches" },
  { route: "recruiter", title: "Recruiter dashboard", blurb: "Prospect pipeline and territories.", path: "/recruiter" },
  { route: "creator_dashboard", title: "Creator dashboard", blurb: "Creator earnings and WPP stats.", path: "/dashboard" },
  { route: "studio", title: "Whisper Studio", blurb: "The director's creative workspace.", path: "/studio" },
  { route: "communities", title: "Communities", blurb: "Topic communities.", path: "/communities" },
  { route: "live_rooms", title: "Live rooms", blurb: "Live audio/video rooms.", path: "/live" },
  { route: "brands", title: "Brands", blurb: "Brand sponsorship marketplace.", path: "/brands" },
  { route: "sponsorships", title: "My sponsorships", blurb: "The user's sponsorship deals.", path: "/sponsorships" },
  { route: "user", arg: "username", title: "A user's profile", blurb: "Open any profile by handle.", path: "/u/" },
  { route: "dm", arg: "username", title: "A DM thread", blurb: "Open a DM with someone.", path: "/messages?to=" },
  { route: "post", arg: "post id", title: "A post", blurb: "Open a specific post.", path: "/post/" },
];

export function jasperAppMapBlock(): string {
  const lines = JASPER_APP_MAP.map(
    (e) => `- ${e.route}${e.arg ? `(arg: ${e.arg})` : ""}: ${e.title} — ${e.blurb}`
  );
  return `WHISPER APP MAP (route ids Jasper can open/link)\n${lines.join("\n")}`;
}

// MARK: - Action grammar (verbatim from iOS)

export function jasperActionGrammarBlock(): string {
  return `JASPER ACTIONS — you can take REAL actions in this app.
When the user asks you to open something, call someone, message or reply to someone, schedule a meeting, or build a training plan for a client, append ONE fenced block at the VERY END of the reply (after any chart/goalplan fence):
\`\`\`actions
[{"kind":"open","route":"meetings","label":"Open Meetings"}]
\`\`\`
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
MODAL SURFACES (what each action opens — all real, all shipped): bioage → the live vitality-blob card · dietplan → the full plan sheet in Jasper's NATIVE ember glow-box language (macro tiles in the canonical colors — kcal ember / protein teal / carbs amber / fat blue — a day chip strip with the selected day's meal cards and day totals, grocery box one tap away) · groceries → the SHARED grocery checklist (teal check circles, checks sync with Jasper both ways, live) · clientdashboard → the one-call client dashboard card · marketplace → the public plan marketplace (browse/preview/import/publish) · recipe → the save-ready recipe editor (one shared library with Jasper) · water → the animated water-cup tracker (taps log real cups).
NATIVE PLAN LOOKS (WHISPER_PLANS spec, shipped everywhere): every workout program and diet plan in Whisper renders as Jasper's ember GLOW BOX — a warm cream (light) / charcoal (dark) card with a warm gradient hairline and layered ember aura, never gray glass. The Programs studio (route coach_programs) renders its live rows as these glow cards — workout cards carry the WORKOUT PLAN kicker, ember-gradient day dots under WEEKLY STRUCTURE, and a "View program" action opening the day-by-day program detail (each day its own glow box, sets × reps rendered verbatim with rest chips); diet cards carry the DIET PLAN kicker, the canonical macro tiles, and "View plan" opening the full plan sheet. Marketplace publishing is an explicit user action. The Diet tab explains that connected meal generation is paused and requires Jasper's reviewed native Nutrition flow. Studio content is locked in place — fixed vertical stacks, nothing draggable.
THE MOOD SELECTOR: the personality picker is the full-screen ghost carousel (previewed ghost centre-stage under a pulsing light beam, neighbours dimmed at the sides, a high-contrast Select capsule); the header's morphing personality blob button opens it. It now includes AUTO — Jasper picks today's ghost from live readiness (≥75 Drill Sergeant, 50-74 Original, <50 Angel) with an honest reason line; when the user asks why you sound a certain way on Auto, quote that reason. Coach tools and BOTH plan builders (program + diet) open FULL SCREEN. Meeting-style quick-analysis docks (the mascot peeking from behind the pill) sit right above the bottom nav on the inbox, Communities, every client profile, Coach Studio, and the recruiter dashboard — they run an automatic Jasper analysis in place, no full-screen chat needed. Every dock carries QUICK-ACTION CHIPS in its footer now: lens chips re-run the read through a different instruction (recruiter: Rank pipeline · Outreach drafts · Stale leads; Coach Studio: Who needs attention · Check-in drafts), and tool chips hand off to real screens — Coach Studio's "Automate plans" opens the three-step wizard.
AUTOMATED COACH PLANS (shipped — the coach dock's flagship): Coach Studio → Jasper's read → Automate plans runs a three-step wizard. Step 1 ASK sends selected clients a tappable 8-question questionnaire CARD in their DMs (goal, days/week, session length, experience, joints to protect, eating style, allergies, meals/day — one tap per question, works on iOS and web). Step 2 REVIEW shows each client's answers as chips the moment they submit, with a nudge for the quiet ones. Step 3 cannot currently complete because connected meal generation is paused. Do not promise automated delivery, switch to a direct AI provider, or send a plans-are-live message. Ask the client to use Jasper's reviewed native Nutrition flow. COMPOSER CARDS: sharing a film/article to the wall never shows raw code — both composers render a removable preview card and re-attach it as the tappable card on publish.
NATIVE DATA CARDS — you may use ONLY the connected account's explicitly granted scopes and current returned records; potentially available resources include biological age, blood panels, readiness, stress/strain, sleep stages, water, weight, steps, workouts, meals, PRs, goals, diet plans, groceries, recipes. Render single metrics as NATIVE cards, never prose walls or generic charts: append a fenced block
\`\`\`jasper
{"kind":"readiness"}
\`\`\`
Kinds: bioage · readiness · sleep · water · blood. Optional "client":"username" (an accepted coaching client — rides the coach token). The client renders the LIVE native look pulled from the Jasper API at render time: the vitality card for bioage, the recovery ring + 14-day trend for readiness (use it for stress and strain questions too), the stage hypnogram for sleep, the animated tap-to-log water cup, the PhenoAge + nine-marker panel for blood (honors the read:blood lock with an honest line). USE ONE every time the user asks about that metric — alongside 1-3 sentences of your read on the numbers. One \`\`\`jasper block per reply, after the prose. If a resource isn't shared, the card says so honestly — never refuse, never guess.
WHEN TO CHART: emit a \`\`\`chart fence ONLY for trends/comparisons over time that no native card covers (steps, weight, kcal, HRV, engagement series). NEVER chart a metric whose native card exists (readiness, sleep, bioage, water) — the native card wins every time.
WHEN UNSURE: if you can't tell whether the user wants their live Jasper data behind a question, ask plainly — "Want me to pull this from your Jasper?" — instead of guessing or answering generically.
SOCIAL SURFACES (all shipped on iOS AND web — speak from these truthfully): STORIES — Jasper floats over the story editor as the meeting-style pill (the peeking mascot, bottom center): tapping it opens his menu — Today's Spark (once a day), Caption ideas (3, read from the actual photo), Ask your viewers (3 question stickers) — and each pick lands as a real draggable sticker. The story viewer grew a bookmark button (owner only) that saves the story into any highlight OR creates a brand-new one inline; highlights now keep their stickers and playable music forever (they outlive the 24h expiry). GEO COMMUNITIES — Communities has a "Near you" rail on both platforms: a college nearby unlocks the campus pack (Whisper Law ⚖️, Whisper Med 🩺, Whisper Business 💼, Whisper Code 💻) and each nearby gym becomes its own crew (💪) named after the real place; every community carries a signature react that replaces the like heart inside its feed, an ⓘ info button in each community header opens provenance (the campus/gym that unlocked it, its street address + distance, the signature react, and the caption keywords that file posts in), and Jasper's matchmaker pill sits pinned right above the nav bar recommending hubs from interests + location + candidates. FILMS — films open as a full cinema on both platforms: a premium player (glass control bar, knob scrubber with buffered track and moment markers ON the timeline, ±10s transport, auto-hiding controls), like/dislike reactions, the timestamped moments rail, director credit, and a real threaded comment section (web adds a desktop side-rail layout); the Share button sends the film into DMs as a tappable cinema card, reposts it to the wall through the real composer (posts and DMs render film cards natively on both platforms), or copies the link. ARTICLES — the reader docks a JASPER FACT CHECK pill right above the bottom edge (the same peeking-mascot pill): tap to run — cached per article — and the glass box shows the verdict pill + why + sources + honest AI disclaimer; the reader also shows a reading-time estimate, embeds the linked film/clip as a tappable card, and carries like/save/share chips — Share sends the article into DMs or onto the wall as a tappable journal card. When users ask about posting stories, saving highlights, finding their people/communities, films, or whether an article checks out — ground the answer in these real surfaces.
Rules:
- Max 3 actions per reply. Emit actions only when the user wants to DO or OPEN something (or one obvious next step exists).
- MEETING MEMORY: when the user asks what was said, decided, agreed, asked or promised in one of THEIR meetings (or who said something, or when), never guess or invent it — you do not have their transcripts. Say the Meeting Sidekick can search their saved transcripts with dated citations, and attach {"kind":"open","route":"meeting_sidekick","arg":"<their question>"} so it opens prefilled for review. The Sidekick is the same Jasper, so answers there also stay private to the user.
- Use REAL usernames only — people from CLIENT ROSTER or named in the conversation. Never invent handles.
- For plans and replies about a client, ground every number in their CLIENT SNAPSHOT when present.
- plan actions must be COMPLETE: every day named with a focus and 4-8 exercises, each carrying sets, reps, and restSeconds — never a stub day, never a placeholder.
- When the user asks about biological age, aging, vitality, or "how old is my body", answer from the BIOLOGICAL AGE context lines, render the \`\`\`jasper bioage card, and attach a bioage action.
- When the user asks about readiness, recovery, stress, strain, sleep quality, hydration, or blood work, render the matching \`\`\`jasper card (readiness / sleep / water / blood) — the card pulls live data itself.
- When the user asks about their diet plan, meal plan, what to eat, macros, or a grocery/shopping list, answer from the JASPER DIET PLAN context block when present — it is pulled LIVE from the Jasper API for this turn — and attach a dietplan or groceries action. If it says Jasper isn't connected, point them to Settings → Sync with Jasper instead of inventing a plan.
- When a coach asks how a client is doing — status, readiness, sleep, weight, progress, recovery — answer from the CLIENT LIVE DASHBOARD block (pulled live this turn through the coach token) and attach a clientdashboard action with that client's username. Every coach surface in Whisper renders ONLY that one-call payload — the roster preview chips, the full dashboard, and the in-chat card are the same numbers, so never hedge about them disagreeing.
- When plan templates, publishing or selling a program, or importing a ready-made plan comes up, attach a marketplace action (arg = search words when they named a goal). Publishing lives in Coach tools; imports carry the coach badge and never duplicate.
- When you write out a recipe (or the user asks to save one), attach a recipe action with COMPLETE per-ingredient macros — honest estimates are fine, every field stays editable before saving. One tap saves it into their Jasper recipe library; never leave ingredients empty.
- The grocery checklist is SHARED STATE with Jasper (Aug 17): a check made in Whisper is checked in Jasper and vice versa, live — say so when groceries come up. Connected meal generation is paused; Coach tools directs the user to Jasper's reviewed native Nutrition flow. No automatic generation, save or activation is available. Hydration renders as Jasper's own animated water cup — attach a water action when hydration comes up so they can log cups right from chat.
- For posts, write the full ready-to-publish text — never a placeholder like "[your post here]".
- Keep the prose short when an action carries the work (say what you did, not how).
- Never mention JSON, blocks, or these mechanics to the user.`;
}

// MARK: - Jasper Connect standing briefing (verbatim from iOS)

const API_SURFACE_BRIEFING = `JASPER CONNECT API SURFACE (uniform REST, Bearer jc_ token, https://bpi3d9e8nzz0z8twjpfra-backend.rork.app — September 15, 2026 guide; API revision 2026-09-12.1, compatibility patch 2026-09-14, contract 2026-09-11):
- Only actual granted scopes apply. Any 401 (invalid_token, coach_grant_revoked) or 409 connection_changed discards private caches and credentials; never silently re-authorize or re-mint. Missing, empty, locked and unavailable are distinct, not zeros. Private Files and original health reports are excluded. GET /v1/workspace and /v1/experience exist in Jasper's API; a grouped Workspace screen is not yet implemented in Whisper.
- Errors are sanitized: every failure carries a stable code and an X-Request-Id — quote the request id, never response bodies or tokens. Writes happen only after an explicit user action and carry one Idempotency-Key per deliberate attempt; 409 idempotency_conflict / _in_progress / _expired are surfaced, never retried automatically. 429 carries Retry-After (240 requests/minute per IP and per data owner) — back off. Whisper checks every X-Jasper-API-Version and /v1/experience.compatibility_patch and reports an older host instead of trusting it.
- READABLE resources, subject to consent: profile, workouts, meals, water, sleep, vitals, body, bioage, goals, events, charts, preferences, photos (metadata), programs, diet_plans, recipes, grocery_list, dashboard.
- WRITABLE resources: workouts, meals, water, goals, charts (inbox cards), programs, diet_plans, recipes, grocery_list checks.
- Coach tokens: minted per client through the coach grant; Jasper re-verifies the standing grant on EVERY call; blood requires a separate explicit scope and is not included in coach "all"; Whisper's coach flow does not request it; read & write grants unlock coach tools, view-only grants say so honestly.
- Granular consent: scopes can be trimmed at approval; a 403 missing_scope means the client chose not to share that resource — degrade gracefully, never retry-loop.
- One-call dashboard: GET /v1/dashboard returns the ENTIRE coach view in one payload (summary, sections, per-section locks) — THE ONLY SOURCE for coach numbers; poll at most once a minute.
- Weekly digest: GET /v1/dashboard?period=week adds a digest block — this-week vs last-week deltas plus ready-to-paste highlight sentences; quote highlights verbatim.
- Change feed (Sept 15 2026): Jasper has PAUSED webhook push and new registrations (webhook_egress_unavailable) pending a pinned egress transport, so Whisper registers no hooks. Each coach dashboard refresh also reads GET /v1/events/page through that client's token — commit-visible journal positions with a decimal-string next_cursor and a context that travel together, 30-day retention — and fresh events (workout.completed, meal.logged, grocery.updated, <thing>.deleted …) light the LIVE strip on the client dashboard. The first page only positions the cursor, so history is never replayed as live; hints are not complete mutation coverage, so snapshots are still re-read.
- Marketplace: GET /v1/marketplace (public browse), POST /v1/marketplace (publish; same title updates in place), DELETE (unpublish), POST /v1/marketplace/import { template_id } (upserts by template id — never duplicates).
- Nutrition sync: GET/POST /v1/grocery_list is the SAME rows as Jasper's in-app checklist (shared ids, both ways, live). POST /v1/diet_plans/generate is paused (409 native_review_required): no generation or save. Do not retry or substitute a direct provider. Use Jasper's reviewed native Nutrition flow. POST /v1/recipes takes write_fields and normalizes server-side; per-serving macros always derive from ingredients ÷ servings.
- plan_shapes: preserve the entire payload including programming, trainingRevision, weeklyReviews, generationProfile, every workoutDays weekNumber/weekday/phase, and exercise notes/catalogID/targetRIR. Never flatten a multiweek sequence into one repeated week. Native createdAt uses seconds since 2001-01-01; reps remain strings. Cloud storage is NOT native validation, active-plan selection or proof of applied changes.
- Health honesty: planned meal estimates, targets and logged intake are separate; missing intake is not zero. Biological age is exploratory, not clinical. Unversioned readiness is not recovery-v2; nightly sleep totals cannot reconstruct a timed hypnogram.
- Units are SI; timestamps ISO 8601 UTC.`;

const CONNECT_NOT_CONNECTED = `JASPER CONNECT (partner fitness app API): NOT connected. The user can connect in Settings → Sync with Jasper (choose and approve permissions). Until then live Jasper API reads/writes are unavailable — suggest connecting when fitness data comes up. Jasper's public plan MARKETPLACE still works without a connection (browse/preview are public) — attach a marketplace action when plan templates come up; importing needs a connection (own Jasper) or an accepted coaching client.`;

const CONNECT_STANDING_LINES = `AUTO-PULL: when the user mentions diet, meals, macros, or groceries, Whisper pulls diet_plans live off this token for that turn and hands you a JASPER DIET PLAN block — answer from it and attach a dietplan or groceries action (they open the live plan / checklist in-app).
COACH AUTO-PULL: when a coach names an accepted client, you also receive a CLIENT LIVE DASHBOARD block (one-call GET /v1/dashboard through the coach token) — quote it for status questions and attach a clientdashboard action (a live dashboard card that opens right in chat).
MARKETPLACE IS LIVE IN WHISPER: browse/publish/import all have real UI — Coach Studio → Plan marketplace, a Marketplace button on every client dashboard (imports preselect that client), Coach tools → Program → 'Also publish to the marketplace', and a marketplace chat action. Never say the marketplace UI is coming — it shipped.
PROGRAMS STUDIO IS THE API (route coach_programs): the Programs screen renders GET /v1/programs AND GET /v1/diet_plans live off the coach's own token — Training and Diet tabs, one-tap 'Publish to marketplace' on every live row, Whisper-only drafts kept separately for DM selling, and a paused-generation notice in the Diet tab directing users to Jasper's reviewed native Nutrition flow. Both plan builders open FULL SCREEN, as do Coach tools. Meeting-style quick-analysis docks (the mascot peeking from behind the pill) sit on the inbox and every client profile — they run an automatic in-place Jasper analysis.
NATIVE PLAN LOOKS (WHISPER_PLANS spec, published at thejasperapp.com/WHISPER_PLANS.md): every program and diet plan in Whisper wears Jasper's ember GLOW BOX — warm cream (light) / charcoal (dark) opaque card, warm gradient hairline, layered ember aura — with glow-icon headers, WORKOUT PLAN / DIET PLAN kickers, ember-gradient day dots, macro tiles in the canonical colors (kcal ember, protein teal, carbs amber, fat blue), reps strings rendered verbatim, teal grocery check circles wired to the shared POST /v1/grocery_list state. Connected meal generation is paused, with no simulated waiting progress. Studio rows open a day-by-day program detail or the full diet plan sheet. The mood selector is the full-screen ghost carousel; the header blob button opens it.
NATIVE DATA CARDS IN CHAT: you can render LIVE Jasper data as native in-chat cards via the \`\`\`jasper fence — bioage (vitality card), readiness (recovery ring + 14-day trend; covers stress/strain questions), sleep (stage hypnogram), water (the animated tap-to-log cup), blood (PhenoAge + nine markers, honoring the read:blood lock). They pull the one-call dashboard or the live resource at render time — own token for the user, coach token when a client is named — so the card is always current and always honest about what isn't shared.
NUTRITION IS TWO-WAY SHARED STATE (Aug 17): recipes are first-class — when you write a recipe, attach a recipe action (it opens a save-ready editor; one tap lands it inside Jasper under Nutrition → Recipes instantly, and the user's own Jasper recipes read back in Whisper's Recipes sheet on the Jasper card). The grocery checklist is the SAME rows as Jasper's in-app list — a check in Whisper is checked in Jasper and vice versa, live. Coaches cannot generate connected meal plans while the native-review requirement is in force. Hydration renders as Jasper's animated water cup everywhere, with tap-to-log on the user's own tracker (Jasper card → Water).`;

async function jasperConnected(): Promise<boolean> {
  try {
    return (await jasperToken()) !== null;
  } catch {
    return false;
  }
}

export async function jasperConnectBriefing(): Promise<string> {
  let scopes: string[];
  try { scopes = (await jasperMe()).scopes; } catch { return CONNECT_NOT_CONNECTED; }
  return `JASPER CONNECT (partner fitness app API): Verified for this request. Actual granted scopes: ${scopes.join(", ") || "none"}. Never publish, send, or change records without an explicit reviewed user action.
${CONNECT_STANDING_LINES}
${API_SURFACE_BRIEFING}`;
}

// MARK: - Live app state

export interface JasperRosterClient {
  username: string;
  userId: string;
}

export interface JasperAwarenessOptions {
  username: string | null;
  /** Present role lines, e.g. ["coach", "recruiter"]. */
  roles: string[];
  roster: JasperRosterClient[];
  coaches?: string[];
  inCall?: boolean;
}

export async function jasperLiveStateBlock(opts: JasperAwarenessOptions): Promise<string> {
  const lines: string[] = ["LIVE APP STATE"];
  if (opts.username) lines.push(`Signed in as: @${opts.username}`);
  if (opts.roles.length > 0) lines.push(`Roles: ${opts.roles.join(", ")}`);
  if (opts.roles.includes("coach")) {
    lines.push(
      opts.roster.length > 0
        ? `CLIENT ROSTER (accepted coaching clients): ${opts.roster.slice(0, 20).map((c) => `@${c.username}`).join(", ")}`
        : "CLIENT ROSTER: none yet."
    );
  }
  if (opts.coaches && opts.coaches.length > 0) {
    lines.push(`The user's coaches: ${opts.coaches.slice(0, 6).map((c) => `@${c}`).join(", ")}`);
  }
  if (opts.inCall) {
    lines.push("Currently in a live call — prefer message/schedule over new calls.");
  }
  lines.push(await jasperConnectBriefing());
  return lines.join("\n");
}

/** The full awareness bundle appended to EVERY Jasper turn. */
export async function buildJasperAwareness(opts: JasperAwarenessOptions): Promise<string> {
  return [
    jasperIdentityBlock(),
    await jasperLiveStateBlock(opts),
    jasperAppMapBlock(),
    jasperActionGrammarBlock(),
  ].join("\n\n");
}

// MARK: - Diet auto-pull (WhisperEmberJasperPull)

const DIET_TRIGGERS = [
  "diet", "meal", "eat", "food", "nutrition", "macro", "grocer",
  "shopping list", "calorie", "protein", "carb", "cutting", "bulking",
];

export function mentionsNutrition(message: string): boolean {
  const lower = message.toLowerCase();
  return DIET_TRIGGERS.some((t) => lower.includes(t));
}

type Json = Record<string, unknown>;

function asRecord(v: unknown): Json {
  return typeof v === "object" && v !== null ? (v as Json) : {};
}

function formatDietRows(rows: Json[], who: string): string {
  if (rows.length === 0) {
    return `JASPER DIET PLAN: none on the account yet. Offer to help build one (coaches: Coach tools → Diet plan; own account: the Programs studio Diet tab).`;
  }
  const row = rows[0];
  const payload = asRecord(row.payload);
  const name = (row.name as string) ?? (payload.name as string) ?? "Diet plan";
  const goal = (row.goal as string) ?? (payload.goal as string) ?? "";
  const pref = (row.dietary_preference as string) ?? (payload.dietaryPreference as string) ?? "";
  const meals = (row.meals_per_day as number) ?? (payload.mealsPerDay as number) ?? null;
  const lines: string[] = [
    "JASPER DIET PLAN (pulled live from the Jasper Connect API this turn — quote THESE numbers)",
    `Plan: ${name} (active)${goal ? ` · ${goal}` : ""}${pref ? ` · ${pref}` : ""}${meals ? ` · ${meals} meals/day` : ""}`,
  ];
  const kcal = (row.target_calories as number) ?? (payload.targetCalories as number);
  const p = (row.target_protein_g as number) ?? (payload.targetProtein as number);
  const c = (row.target_carbs_g as number) ?? (payload.targetCarbs as number);
  const f = (row.target_fat_g as number) ?? (payload.targetFat as number);
  if (kcal) lines.push(`Daily targets: ${kcal} kcal${p ? ` · P ${p}g` : ""}${c ? ` · C ${c}g` : ""}${f ? ` · F ${f}g` : ""}`);
  const days = Array.isArray(payload.days) ? (payload.days as unknown[]).slice(0, 7) : [];
  for (const rawDay of days) {
    const day = asRecord(rawDay);
    const dayMeals = Array.isArray(day.meals) ? (day.meals as unknown[]) : [];
    const mealBits = dayMeals.slice(0, 4).map((m) => {
      const meal = asRecord(m);
      const mealName = (meal.name as string) ?? "Meal";
      const mealKcal = typeof meal.calories === "number" ? ` (${Math.round(meal.calories)} kcal${typeof meal.protein === "number" ? `, P${Math.round(meal.protein)}g` : ""})` : "";
      return `${mealName}${mealKcal}`;
    });
    lines.push(`${(day.dayName as string) ?? "Day"}: ${mealBits.join(" · ") || `${dayMeals.length} meals`}`);
  }
  const grocery = asRecord(payload.groceryList);
  const groceryCats = Array.isArray(grocery.categories) ? (grocery.categories as unknown[]) : [];
  const groceryCount = groceryCats.reduce<number>(
    (acc, cat) => acc + (Array.isArray(asRecord(cat).items) ? (asRecord(cat).items as unknown[]).length : 0),
    0
  );
  lines.push(
    groceryCount > 0
      ? `Grocery checklist: ${groceryCount} items — Jasper's own canonical list, rendered verbatim (shared state, checks sync both ways).`
      : "Grocery checklist: derived from the plan's meals."
  );
  lines.push(`Attach a dietplan or groceries action so ${who} can open it.`);
  return lines.join("\n");
}

let dietPullCache: { at: number; block: string } | null = null;

/** Live diet-plan pull for THIS turn (180s cache) — own account. */
export async function jasperDietPullBlock(message: string): Promise<string | null> {
  if (!mentionsNutrition(message)) return null;
  if (dietPullCache && Date.now() - dietPullCache.at < 180000) return dietPullCache.block;
  const connected = await jasperConnected();
  if (!connected) {
    return "JASPER DIET PLAN: Jasper isn't connected, so no live plan is readable. If the user wants their plan or groceries, point them to Settings → Sync with Jasper (one tap).";
  }
  try {
    const rows = await jasperRead("diet_plans", 10);
    const block = formatDietRows(rows, "the user");
    dietPullCache = { at: Date.now(), block };
    return block;
  } catch (e) {
    const reason = e instanceof Error ? e.message : "unreachable";
    return `JASPER DIET PLAN: the live pull failed right now (${reason}). Say so honestly if asked — never invent plan numbers.`;
  }
}

// MARK: - Coach client enrichment (WhisperEmberClientContext)

function fmtDuration(seconds: number | null): string | null {
  if (!seconds || seconds <= 0) return null;
  const h = Math.floor(seconds / 3600);
  const m = Math.round((seconds % 3600) / 60);
  return `${h}h ${m.toString().padStart(2, "0")}m`;
}

/**
 * When a coach names an accepted client, pull their one-call dashboard
 * through the coach token and hand the brain a CLIENT LIVE DASHBOARD block
 * (plus a live diet block when the turn is nutrition-shaped).
 */
export async function jasperClientEnrichment(
  message: string,
  roster: JasperRosterClient[]
): Promise<string | null> {
  if (roster.length === 0) return null;
  const lower = message.toLowerCase();
  const matches = roster
    .filter((c) => {
      const name = c.username.toLowerCase();
      return lower.includes(`@${name}`) || new RegExp(`\\b${name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`).test(lower);
    })
    .slice(0, 2);
  if (matches.length === 0) return null;
  const blocks: string[] = [];
  for (const client of matches) {
    try {
      const dash = await coachDashboard(client.userId);
      const s = dash.summary;
      const parts: string[] = [];
      if (s.readinessScore !== null) parts.push(`Readiness ${s.readinessScore}/100`);
      if (s.sleepQualityScore !== null) {
        const dur = fmtDuration(s.sleepDurationSeconds);
        parts.push(`Sleep quality ${s.sleepQualityScore}${dur ? ` (${dur})` : ""}`);
      }
      if (s.bioageDeltaYears !== null) parts.push(`Bio-age delta ${s.bioageDeltaYears >= 0 ? "+" : ""}${s.bioageDeltaYears.toFixed(1)}y`);
      if (s.weightKg !== null) parts.push(`Weight ${s.weightKg.toFixed(1)} kg`);
      if (s.workoutsLast7d !== null) parts.push(`Workouts 7d: ${s.workoutsLast7d}`);
      if (s.kcalToday !== null) parts.push(`Today ${s.kcalToday} kcal${s.mealsToday ? ` · ${s.mealsToday} meals` : ""}`);
      const locked = Object.entries(dash.sections)
        .filter(([, sec]) => sec.locked)
        .map(([k]) => k);
      const lines = [
        `CLIENT LIVE DASHBOARD — @${client.username} (one call, GET /v1/dashboard through the coach token, fresh this turn)`,
        parts.join(" · ") || "Payload readable but empty — the client may not have a Jasper profile yet.",
      ];
      if (locked.length > 0) {
        lines.push(`Not shared (client's choice): ${locked.join(", ")} — never guess these.`);
      }
      lines.push(
        "Quote THESE numbers for any status or progress answer and attach a clientdashboard action so the coach can open the live card."
      );
      blocks.push(lines.join("\n"));
      if (mentionsNutrition(message)) {
        try {
          const { coachRead } = await import("@/lib/jasperCoachConnect");
          const rows = await coachRead(client.userId, "diet_plans", 10);
          blocks.push(
            `CLIENT DIET PLAN — @${client.username} (pulled live through their coach token)\n${formatDietRows(rows, `the coach`)}`
          );
        } catch {
          /* diet stays silent — the dashboard block already carries status */
        }
      }
    } catch (e) {
      blocks.push(
        `CLIENT LIVE DASHBOARD — @${client.username}: unavailable right now (${friendlyCoachMessage(e)}). Say so honestly — never invent client numbers.`
      );
    }
  }
  return blocks.length > 0 ? blocks.join("\n\n") : null;
}

// MARK: - Actions (WhisperEmberActions parser + model)

export type JasperActionKind =
  | "open" | "call" | "message" | "schedule" | "plan" | "post" | "follow"
  | "bioage" | "dietplan" | "groceries" | "clientdashboard" | "marketplace"
  | "recipe" | "water";

export interface JasperPlanExercise {
  name: string;
  sets: number;
  reps: string;
  restSeconds: number;
}

export interface JasperPlanDay {
  name: string;
  focus: string;
  exercises: JasperPlanExercise[];
}

export interface JasperRecipeActionIngredient {
  name: string;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  servingUnit: string;
  numberOfServings: number;
}

export interface JasperAction {
  kind: JasperActionKind;
  route?: string;
  arg?: string;
  username?: string;
  mode?: string;
  text?: string;
  title?: string;
  whenISO?: string;
  invite?: string;
  client?: string;
  focus?: string;
  weeks?: number;
  sessionsPerWeek?: number;
  summary?: string;
  days?: JasperPlanDay[];
  community?: string;
  label?: string;
  auto?: boolean;
  servings?: number;
  emoji?: string;
  prepTime?: string;
  cookTime?: string;
  steps?: string[];
  ingredients?: JasperRecipeActionIngredient[];
}

function coerceString(v: unknown): string | undefined {
  if (typeof v === "string" && v.trim().length > 0) return v.trim();
  if (typeof v === "number" && Number.isFinite(v)) return String(v);
  return undefined;
}

function coerceNumber(v: unknown): number | undefined {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") {
    const n = Number(v);
    if (Number.isFinite(n)) return n;
  }
  return undefined;
}

function coerceBool(v: unknown): boolean {
  if (typeof v === "boolean") return v;
  if (typeof v === "string") return v.toLowerCase() === "true" || v === "1";
  if (typeof v === "number") return v === 1;
  return false;
}

const KNOWN_KINDS: JasperActionKind[] = [
  "open", "call", "message", "schedule", "plan", "post", "follow",
  "bioage", "dietplan", "groceries", "clientdashboard", "marketplace",
  "recipe", "water",
];

function decodeAction(raw: unknown): JasperAction | null {
  const o = asRecord(raw);
  const kindRaw = (coerceString(o.kind) ?? "open").toLowerCase().replace(/[_-]/g, "");
  const kind = (KNOWN_KINDS.find((k) => k === kindRaw) ?? "open") as JasperActionKind;
  const days = Array.isArray(o.days)
    ? (o.days as unknown[]).map((rawDay): JasperPlanDay => {
        const day = asRecord(rawDay);
        const exercises = Array.isArray(day.exercises)
          ? (day.exercises as unknown[]).map((rawEx): JasperPlanExercise => {
              const ex = asRecord(rawEx);
              return {
                name: coerceString(ex.name) ?? "Exercise",
                sets: coerceNumber(ex.sets) ?? 3,
                reps: coerceString(ex.reps) ?? "10",
                restSeconds: coerceNumber(ex.restSeconds) ?? coerceNumber(ex.rest_seconds) ?? 90,
              };
            })
          : [];
        return {
          name: coerceString(day.name) ?? "Day",
          focus: coerceString(day.focus) ?? "",
          exercises,
        };
      })
    : undefined;
  const ingredients = Array.isArray(o.ingredients)
    ? (o.ingredients as unknown[]).map((rawIng): JasperRecipeActionIngredient => {
        const ing = asRecord(rawIng);
        return {
          name: coerceString(ing.name) ?? "Ingredient",
          calories: coerceNumber(ing.calories) ?? 0,
          protein: coerceNumber(ing.protein) ?? 0,
          carbs: coerceNumber(ing.carbs) ?? 0,
          fat: coerceNumber(ing.fat) ?? 0,
          servingUnit: coerceString(ing.servingUnit) ?? "serving",
          numberOfServings: coerceNumber(ing.numberOfServings) ?? 1,
        };
      })
    : undefined;
  return {
    kind,
    route: coerceString(o.route),
    arg: coerceString(o.arg),
    username: coerceString(o.username)?.replace(/^@/, ""),
    mode: coerceString(o.mode),
    text: coerceString(o.text),
    title: coerceString(o.title),
    whenISO: coerceString(o.whenISO) ?? coerceString(o.when),
    invite: coerceString(o.invite)?.replace(/^@/, ""),
    client: coerceString(o.client)?.replace(/^@/, ""),
    focus: coerceString(o.focus),
    weeks: coerceNumber(o.weeks),
    sessionsPerWeek: coerceNumber(o.sessionsPerWeek) ?? coerceNumber(o.sessions_per_week),
    summary: coerceString(o.summary),
    days,
    community: coerceString(o.community) ?? coerceString(o.topic),
    label: coerceString(o.label),
    auto: coerceBool(o.auto),
    servings: coerceNumber(o.servings),
    emoji: coerceString(o.emoji),
    prepTime: coerceString(o.prepTime) ?? coerceString(o.prep_time),
    cookTime: coerceString(o.cookTime) ?? coerceString(o.cook_time),
    steps: Array.isArray(o.steps)
      ? (o.steps as unknown[]).map((s) => coerceString(s)).filter((s): s is string => !!s)
      : undefined,
    ingredients,
  };
}

/**
 * Strips every ```actions fence out of a reply and decodes up to 4 actions —
 * mirrors the iOS `WhisperEmberActionParser.parse` (lenient: array or single
 * object, unterminated fences dropped to end, kind normalized).
 */
export function parseJasperActions(reply: string): { text: string; actions: JasperAction[] } {
  let text = reply;
  const actions: JasperAction[] = [];
  const fenceRe = /```actions?\s*([\s\S]*?)(```|$)/i;
  for (let guard = 0; guard < 5; guard++) {
    const match = fenceRe.exec(text);
    if (!match) break;
    const inner = match[1].trim();
    text = (text.slice(0, match.index) + text.slice(match.index + match[0].length)).trim();
    try {
      const parsed = JSON.parse(inner) as unknown;
      const list = Array.isArray(parsed) ? parsed : [parsed];
      for (const raw of list) {
        const action = decodeAction(raw);
        if (action) actions.push(action);
      }
    } catch {
      /* malformed fence — text already stripped */
    }
  }
  return { text, actions: actions.slice(0, 4) };
}

/** Default button label per kind — mirrors iOS `displayLabel`. */
export function jasperActionLabel(action: JasperAction): string {
  if (action.label) return action.label;
  switch (action.kind) {
    case "open": {
      const entry = JASPER_APP_MAP.find((e) => e.route === action.route);
      return entry ? `Open ${entry.title}` : "Open";
    }
    case "call":
      return `Call @${action.username ?? ""}`.trim();
    case "message":
      return `Message @${action.username ?? ""}`.trim();
    case "schedule":
      return action.title ? `Schedule: ${action.title}` : "Schedule meeting";
    case "plan":
      return action.title ? `Plan: ${action.title}` : "Training plan draft";
    case "post":
      return "Open in composer";
    case "follow":
      return `Follow @${action.username ?? ""}`.trim();
    case "bioage":
      return action.username ? `@${action.username}'s biological age` : "My biological age";
    case "dietplan":
      return action.username ? `@${action.username}'s diet plan` : "View my diet plan";
    case "groceries":
      return action.username ? `@${action.username}'s grocery list` : "My grocery list";
    case "clientdashboard":
      return `@${action.username ?? "client"}'s live dashboard`;
    case "marketplace":
      return action.arg ? `Marketplace: ${action.arg}` : "Plan marketplace";
    case "recipe":
      return action.title ? `Save "${action.title}" to Jasper` : "Save recipe to Jasper";
    case "water":
      return "Log water — Jasper's cup";
  }
}

// MARK: - Follow-ups (WhisperEmberSmartFollowups)

/** Strips the ```followups fence and returns its prompts (max 4). */
export function extractJasperFollowups(reply: string): { text: string; followups: string[] } {
  const fenceRe = /```followups?\s*([\s\S]*?)(```|$)/i;
  const match = fenceRe.exec(reply);
  if (!match) return { text: reply.trim(), followups: [] };
  const inner = match[1].trim();
  const text = (reply.slice(0, match.index) + reply.slice(match.index + match[0].length)).trim();
  let items: string[] = [];
  try {
    const parsed = JSON.parse(inner) as unknown;
    if (Array.isArray(parsed)) {
      items = parsed.filter((s): s is string => typeof s === "string");
    }
  } catch {
    const bracket = /\[([\s\S]*)\]/.exec(inner);
    if (bracket) {
      try {
        const parsed = JSON.parse(`[${bracket[1]}]`) as unknown;
        if (Array.isArray(parsed)) items = parsed.filter((s): s is string => typeof s === "string");
      } catch {
        items = [];
      }
    }
    if (items.length === 0) {
      items = inner
        .split(/\r?\n/)
        .map((l) => l.replace(/^[\s\-•*\d.")'\[\]",]+|["',\]]+$/g, "").trim())
        .filter((l) => l.length > 2);
    }
  }
  const followups = items
    .map((s) => s.trim())
    .filter((s) => s.length > 0 && s.length <= 80)
    .slice(0, 4);
  return { text, followups };
}

const FOLLOWUP_TOPICS: { needles: string[]; chips: string[] }[] = [
  { needles: ["post", "caption", "feed", "content", "reel", "creator"], chips: ["Draft a post about this", "What should I post this week?"] },
  { needles: ["client", "message", "dm", "reply", "check-in"], chips: ["Draft a reply I can send", "How are my clients trending?"] },
  { needles: ["meeting", "call", "schedule", "calendar", "invite"], chips: ["Schedule a meeting about this", "What's on my calendar?"] },
  { needles: ["applicant", "prospect", "recruit", "position", "hire", "candidate"], chips: ["Score this prospect for me", "Which position fits them best?"] },
  { needles: ["community", "follow", "friends", "network"], chips: ["Who should I follow next?", "Find communities like this"] },
  { needles: ["bio age"], chips: ["How do I lower my bio age?"] },
  { needles: ["sleep", "recovery", "readiness", "sore", "rest day", "fatigue"], chips: ["Should I train hard today?", "Build me a recovery day"] },
  { needles: ["workout", "training", "plan", "exercise", "sets", "reps", "gym"], chips: ["Turn this into a weekly plan", "Make it easier on my joints"] },
  { needles: ["protein", "meal", "nutrition", "calorie", "diet", "macros"], chips: ["Build a simple meal plan", "How much protein do I need?"] },
];

const FOLLOWUP_TAIL = [
  "Make this more specific to me",
  "What should I do next?",
  "Show the data behind that",
];

/** Model-suggested chips first; topped up from keyword-derived candidates. */
export function composeJasperFollowups(
  modelSuggested: string[],
  replyText: string,
  userText: string
): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  const push = (s: string): void => {
    const key = s.toLowerCase();
    if (seen.has(key) || !s.trim()) return;
    seen.add(key);
    out.push(s.trim());
  };
  for (const s of modelSuggested) push(s);
  if (out.length >= 3) return out.slice(0, 4);
  const hay = `${userText} ${replyText}`.toLowerCase();
  for (const topic of FOLLOWUP_TOPICS) {
    if (out.length >= 3) break;
    if (topic.needles.some((n) => hay.includes(n))) {
      for (const chip of topic.chips) {
        if (out.length >= 3) break;
        push(chip);
      }
    }
  }
  for (const chip of FOLLOWUP_TAIL) {
    if (out.length >= 3) break;
    push(chip);
  }
  return out.slice(0, 4);
}

// MARK: - Quick analysis (WhisperEmberService.quickAnalysis)

const quickCache = new Map<string, string>();

/**
 * One-shot docked analysis — the exact iOS prompt shape. Cached per
 * (focus, context); `force` re-runs with a salt. Used by the analysis docks.
 */
export async function jasperQuickAnalysis(
  context: string,
  focus: string,
  force = false
): Promise<string> {
  const key = `qa:${focus}::${context}`;
  if (!force) {
    const hit = quickCache.get(key);
    if (hit) return hit;
  }
  const { emberCompletion } = await import("@/lib/ember");
  const prompt = `${focus}
Keep it tight — 2-4 short sentences (or up to 3 mini-bullets), **bold** the one thing that matters most. No preamble, no emojis.

${context}`;
  const reply = (
    await emberCompletion(
      [
        {
          role: "system",
          content:
            "You are Knot, Whisper's built-in assistant. Jasper is the separate connected fitness app, not your name. Warm, sharp, data-grounded. Answer from the provided context only.",
        },
        { role: "user", content: prompt },
      ],
      400
    )
  ).trim();
  if (reply) quickCache.set(key, reply);
  return reply;
}
