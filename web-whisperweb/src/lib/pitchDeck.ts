import { supabase } from "@/lib/supabase";
import { emberCompletion } from "@/lib/ember";

/**
 * Jasper's recruiter pitch deck — the close plan he drafts while quietly
 * listening to a recruiter–prospect meeting. The JSON shape is shared
 * verbatim with iOS (WhisperPitchDeck.swift) so decks written by either
 * platform open on both. Stored per (meeting, recruiter) in
 * whisper_meeting_decks (supabase/pitch-decks.sql) with a local cache so
 * the feature works before the migration runs.
 */

export type DeckMomentKind = "interest" | "objection" | "signal";

export interface PitchDeckMoment {
  quote: string;
  speaker: string;
  /** Why this moment matters for the close — the margin note. */
  note: string;
  kind: DeckMomentKind;
}

export interface PitchDeckSlide {
  title: string;
  bullets: string[];
}

export interface PitchDeckStep {
  step: string;
  detail: string;
}

export interface PitchDeckImpact {
  quote: string;
  why: string;
}

export interface PitchDeckNextStep {
  action: string;
  when: string;
}

export interface JasperPitchDeck {
  v: number;
  meetingId: string;
  meetingTitle: string;
  prospectName: string;
  placement: "coach" | "creator" | "athlete";
  /** The one-line pitch angle for the close. */
  headline: string;
  /** What the prospect actually cares about, from their own words. */
  interests: string[];
  /** Highlighted key moments from the transcript. */
  keyMoments: PitchDeckMoment[];
  /** The pitch plan — real deck slides. */
  slides: PitchDeckSlide[];
  /** The ordered close plan. */
  closePlan: PitchDeckStep[];
  /** Honest close odds: run the plan vs wing it. */
  closeRate: { withPlan: number; withoutPlan: number; why: string };
  /** The recruiter's own highest-impact moments from the call. */
  impactMoments: PitchDeckImpact[];
  nextSteps: PitchDeckNextStep[];
  generatedAt: number;
  draft?: boolean;
  sample?: boolean;
}

const DECK_SYSTEM =
  "You are Jasper, Whisper's recruiting strategist. You silently listened to a live recruiter–prospect meeting on Whisper. Whisper placements: coach (verified fitness coach selling monthly coaching, keeps 90%), creator (verified content creator paid from the WPP ad-revenue pool + escrowed sponsorships), athlete (verified athlete who gets discovered + sponsored). You now build the recruiter a CLOSE DECK — a pitch plan grounded ONLY in what was actually said in the transcript. Never invent quotes or facts. Respond with STRICT JSON only — no markdown, no commentary.";

function deckPrompt(input: {
  meetingTitle: string;
  recruiterUsername: string;
  prospectHint: string | null;
  transcript: string;
}): string {
  return `Meeting: "${input.meetingTitle.slice(0, 120)}".
The recruiter (the pitch side) is "${input.recruiterUsername || "the host"}" — their transcript lines are the pitch. Everyone else is the prospect side.${
    input.prospectHint ? ` The prospect being recruited is likely "${input.prospectHint}".` : ""
  }

TRANSCRIPT (speakers labelled):
${input.transcript}

Return JSON EXACTLY like:
{"prospectName":"display name of the prospect","placement":"coach|creator|athlete","headline":"one-line pitch angle for the close, max 95 chars","interests":["3-5 things the prospect actually cares about, in their words"],"keyMoments":[{"quote":"short faithful quote (max 140 chars)","speaker":"who said it","note":"why it matters for the close (max 90 chars)","kind":"interest|objection|signal"}],"slides":[{"title":"slide title","bullets":["2-4 short bullets"]}],"closePlan":[{"step":"imperative step","detail":"one sentence of how/why"}],"closeRate":{"withPlan":72,"withoutPlan":38,"why":"1-2 honest sentences explaining both numbers"},"impactMoments":[{"quote":"the recruiter's own line that landed","why":"what it did (max 85 chars)"}],"nextSteps":[{"action":"concrete action","when":"e.g. Tonight, Thursday 4pm, within 48h"}]}

Rules: 3-5 keyMoments (mix kinds; at least one objection when one exists). 2-3 slides. 3-5 closePlan steps ordered. impactMoments: 1-3 picked ONLY from the recruiter's own lines — the moments that visibly moved the prospect; if nothing landed, return one honest entry saying so in "why". 2-4 nextSteps. closeRate: honest integers 0-100 — withPlan reflects real signal strength, never flattery; withoutPlan assumes no follow-through. Quotes must be short and faithful to the transcript.`;
}

function clamp100(v: unknown): number {
  const n = typeof v === "number" ? v : Number(v);
  if (!Number.isFinite(n)) return 0;
  return Math.max(0, Math.min(100, Math.round(n)));
}

function str(v: unknown, max = 400): string {
  return typeof v === "string" ? v.trim().slice(0, max) : "";
}

function strList(v: unknown, maxItems: number, maxLen = 160): string[] {
  return Array.isArray(v)
    ? v
        .filter((s): s is string => typeof s === "string" && s.trim().length > 0)
        .map((s) => s.trim().slice(0, maxLen))
        .slice(0, maxItems)
    : [];
}

/** Tolerant parse — returns null when the model output isn't a usable deck. */
function parseDeck(raw: string): Omit<JasperPitchDeck, "meetingId" | "meetingTitle" | "generatedAt" | "v"> | null {
  try {
    const start = raw.indexOf("{");
    const end = raw.lastIndexOf("}");
    if (start < 0 || end <= start) return null;
    const o = JSON.parse(raw.slice(start, end + 1)) as Record<string, unknown>;
    const placementRaw = String(o.placement ?? "").toLowerCase();
    const placement: JasperPitchDeck["placement"] =
      placementRaw === "coach" || placementRaw === "athlete" ? placementRaw : "creator";
    const headline = str(o.headline, 140);
    const prospectName = str(o.prospectName, 60) || "the prospect";
    if (!headline) return null;

    const moments: PitchDeckMoment[] = Array.isArray(o.keyMoments)
      ? (o.keyMoments as unknown[])
          .map((m) => {
            const mm = m as Record<string, unknown>;
            const kindRaw = String(mm.kind ?? "").toLowerCase();
            return {
              quote: str(mm.quote, 200),
              speaker: str(mm.speaker, 40) || "speaker",
              note: str(mm.note, 140),
              kind: (kindRaw === "objection" || kindRaw === "signal" ? kindRaw : "interest") as DeckMomentKind,
            };
          })
          .filter((m) => m.quote.length > 0)
          .slice(0, 6)
      : [];

    const slides: PitchDeckSlide[] = Array.isArray(o.slides)
      ? (o.slides as unknown[])
          .map((s) => {
            const ss = s as Record<string, unknown>;
            return { title: str(ss.title, 90), bullets: strList(ss.bullets, 4, 140) };
          })
          .filter((s) => s.title.length > 0 && s.bullets.length > 0)
          .slice(0, 4)
      : [];

    const closePlan: PitchDeckStep[] = Array.isArray(o.closePlan)
      ? (o.closePlan as unknown[])
          .map((s) => {
            const ss = s as Record<string, unknown>;
            return { step: str(ss.step, 110), detail: str(ss.detail, 200) };
          })
          .filter((s) => s.step.length > 0)
          .slice(0, 6)
      : [];

    const rate = (o.closeRate ?? {}) as Record<string, unknown>;
    const impact: PitchDeckImpact[] = Array.isArray(o.impactMoments)
      ? (o.impactMoments as unknown[])
          .map((s) => {
            const ss = s as Record<string, unknown>;
            return { quote: str(ss.quote, 200), why: str(ss.why, 140) };
          })
          .filter((s) => s.quote.length > 0)
          .slice(0, 4)
      : [];

    const nextSteps: PitchDeckNextStep[] = Array.isArray(o.nextSteps)
      ? (o.nextSteps as unknown[])
          .map((s) => {
            const ss = s as Record<string, unknown>;
            return { action: str(ss.action, 120), when: str(ss.when, 40) || "Soon" };
          })
          .filter((s) => s.action.length > 0)
          .slice(0, 5)
      : [];

    if (moments.length === 0 && slides.length === 0 && closePlan.length === 0) return null;

    return {
      prospectName,
      placement,
      headline,
      interests: strList(o.interests, 5, 110),
      keyMoments: moments,
      slides,
      closePlan,
      closeRate: {
        withPlan: clamp100(rate.withPlan),
        withoutPlan: clamp100(rate.withoutPlan),
        why: str(rate.why, 320),
      },
      impactMoments: impact,
      nextSteps,
    };
  } catch {
    return null;
  }
}

/**
 * Build the deck from the meeting transcript — one AI call. Returns null
 * when there isn't enough conversation or the model can't produce a valid
 * deck, so callers keep whatever they already have.
 */
export async function generatePitchDeck(input: {
  meetingId: string;
  meetingTitle: string;
  transcript: string;
  recruiterUsername: string;
  prospectHint?: string | null;
  draft?: boolean;
}): Promise<JasperPitchDeck | null> {
  const transcript = input.transcript.trim();
  if (transcript.length < 200) return null;
  const raw = await emberCompletion(
    [
      { role: "system", content: DECK_SYSTEM },
      {
        role: "user",
        content: deckPrompt({
          meetingTitle: input.meetingTitle,
          recruiterUsername: input.recruiterUsername,
          prospectHint: input.prospectHint ?? null,
          transcript: transcript.slice(-16000),
        }),
      },
    ],
    1500
  );
  if (!raw) return null;
  const parsed = parseDeck(raw);
  if (!parsed) return null;
  return {
    v: 1,
    meetingId: input.meetingId,
    meetingTitle: input.meetingTitle,
    generatedAt: Date.now(),
    ...(input.draft ? { draft: true } : {}),
    ...parsed,
  };
}

const deckKey = (meetingId: string): string => `whisper_meeting_deck:${meetingId}`;

/** Local cache — makes the deck instant and migration-independent. */
export function loadCachedDeck(meetingId: string): JasperPitchDeck | null {
  try {
    const raw = localStorage.getItem(deckKey(meetingId));
    if (!raw) return null;
    const deck = JSON.parse(raw) as JasperPitchDeck;
    return deck && typeof deck.headline === "string" ? deck : null;
  } catch {
    return null;
  }
}

/**
 * Persist the deck — local cache always; database best-effort (the table
 * may not be migrated yet, and drafts stay local-only by design).
 */
export async function savePitchDeck(deck: JasperPitchDeck): Promise<void> {
  try {
    localStorage.setItem(deckKey(deck.meetingId), JSON.stringify(deck));
  } catch {
    /* storage unavailable */
  }
  if (deck.draft || deck.sample) return;
  try {
    const { data } = await supabase.auth.getUser();
    const uid = data.user?.id;
    if (!uid) return;
    await supabase.from("whisper_meeting_decks").upsert(
      {
        meeting_id: deck.meetingId,
        recruiter_id: uid,
        prospect_name: deck.prospectName,
        deck,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "meeting_id,recruiter_id" }
    );
  } catch {
    /* table missing or offline — the local cache still has it */
  }
}

/** Load the recruiter's stored deck for a meeting (DB first, cache fallback). */
export async function fetchPitchDeck(
  meetingId: string,
  recruiterId: string
): Promise<JasperPitchDeck | null> {
  try {
    const { data, error } = await supabase
      .from("whisper_meeting_decks")
      .select("deck")
      .eq("meeting_id", meetingId)
      .eq("recruiter_id", recruiterId)
      .maybeSingle();
    if (!error) {
      const deck = (data as { deck?: JasperPitchDeck } | null)?.deck ?? null;
      if (deck && typeof deck.headline === "string") {
        try {
          localStorage.setItem(deckKey(meetingId), JSON.stringify(deck));
        } catch {
          /* storage unavailable */
        }
        return deck;
      }
    }
  } catch {
    /* table missing — fall through to cache */
  }
  return loadCachedDeck(meetingId);
}

/**
 * The sample deck — a realistic close plan for a fictional prospect so
 * recruiters (hi @dyl) can read the exact formatting before their first
 * real meeting deck lands.
 */
export const SAMPLE_PITCH_DECK: JasperPitchDeck = {
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
    {
      quote: "I have like twelve thousand followers but I've never made a dollar off any of it.",
      speaker: "maya",
      note: "The money gap — WPP pays from real ad spend.",
      kind: "signal",
    },
    {
      quote: "Brands DM me and I just… don't answer. It feels sketchy.",
      speaker: "maya",
      note: "Escrowed sponsorships remove the sketch.",
      kind: "interest",
    },
    {
      quote: "I don't want to post cringe. My teammates would roast me.",
      speaker: "maya",
      note: "Objection: brand safety — she keeps her voice.",
      kind: "objection",
    },
    {
      quote: "Wait — verified athletes actually get discovered by recruiters on here?",
      speaker: "maya",
      note: "She lit up at discovery. Lead with the athlete lane.",
      kind: "signal",
    },
  ],
  slides: [
    {
      title: "Why Whisper, why now",
      bullets: [
        "Verified athlete badge — earned, never bought",
        "Sponsors come to HER through escrowed deals, no sketchy DMs",
        "WPP: real ad dollars shared with creators every month",
      ],
    },
    {
      title: "The 30-day runway",
      bullets: [
        "Week 1: verify + first three posts",
        "Weeks 2–3: two reels a week, teammates cameo",
        "Week 4: first sponsorship pitch with her media kit",
      ],
    },
  ],
  closePlan: [
    {
      step: "Send the athlete-verification link tonight",
      detail: "While the discovery excitement is fresh — she said \u201Cactually get discovered?\u201D out loud.",
    },
    {
      step: "Intro her to one verified athlete",
      detail: "Social proof kills the \u201Cis this sketchy\u201D objection faster than any pitch.",
    },
    {
      step: "Set the follow-up for Thursday",
      detail: "She has practice Tuesday and Wednesday — Thursday afternoon is her window.",
    },
    {
      step: "Bring one real sponsorship example",
      detail: "Show the escrow flow with numbers, not promises.",
    },
  ],
  closeRate: {
    withPlan: 78,
    withoutPlan: 31,
    why: "She has the audience, the drive, and two live buying signals — but the sketchy-brand-DM scar means trust must be built through proof, not pressure. Run the proof-first plan and she signs; wing it and the objection wins.",
  },
  impactMoments: [
    {
      quote: "You'd be verified as an athlete — that badge can't be bought, it's earned.",
      why: "Her posture changed — this reframed Whisper as legitimacy, not another app.",
    },
    {
      quote: "The money doesn't come from posting more. It comes from ad revenue you already generate.",
      why: "Answered the sell-out fear in one line — she repeated it back.",
    },
  ],
  nextSteps: [
    { action: "DM the verification link + one athlete profile", when: "Tonight" },
    { action: "Follow-up call", when: "Thursday 4pm" },
    { action: "Prep the sponsorship walkthrough", when: "Before Thursday" },
  ],
  generatedAt: 1756137600000,
  sample: true,
};
