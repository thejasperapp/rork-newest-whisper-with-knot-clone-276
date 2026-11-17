import {
  COACH_PLATFORM_FEE_PERCENT,
  COACH_RATE_MAX,
  COACH_RATE_MIN,
  SPONSOR_PLATFORM_FEE_PERCENT,
  WPP_TIERS,
  formatUsd,
  wppMonthlyCents,
} from "@/lib/pitch";

/**
 * Ember's narrated deck walkthrough for live meetings.
 *
 * Each slide is a set of short script lines ("segments"). The walkthrough
 * driver feeds one segment at a time to Ember's live voice; the overlay
 * highlights the exact line being read, and the driver's outgoing call audio
 * carries Ember's voice so the whole room hears the same presentation.
 * Slides can embed the REAL interactive pitch components (the WPP slider
 * calculator, the brand marketplace cards) so nobody leaves the meeting.
 */

export interface EmberTourSegment {
  id: string;
  /** The short line shown (and highlighted) on the slide. */
  text: string;
  /** What Ember says out loud for this line. */
  narration: string;
}

export interface EmberTourSlide {
  id: string;
  kicker: string;
  title: string;
  /** Real interactive pitch component embedded in the slide. */
  interactive: "wpp" | "brands" | null;
  /** One-liner inviting the room to touch the interactive component. */
  interactiveHint: string | null;
  /** Hero stat chips rendered on slides without an interactive panel. */
  stats: { value: string; label: string }[];
  segments: EmberTourSegment[];
}

const partner = WPP_TIERS[0];
const partnerPlus = WPP_TIERS[1];
const elite = WPP_TIERS[2];
/** Worked example used on the WPP slide: 250k monthly views at Partner+. */
const EXAMPLE_VIEWS = 250_000;
const examplePayout = formatUsd(wppMonthlyCents(EXAMPLE_VIEWS, partnerPlus));

export const EMBER_TOUR_SLIDES: EmberTourSlide[] = [
  {
    id: "welcome",
    kicker: "The platform",
    title: "Whisper in one minute",
    interactive: null,
    interactiveHint: null,
    stats: [
      { value: "1", label: "platform for the whole creator economy" },
      { value: `${SPONSOR_PLATFORM_FEE_PERCENT}%`, label: "flat platform fee" },
      { value: "100%", label: "real product — no mockups" },
    ],
    segments: [
      {
        id: "intro",
        text: "Whisper is a social platform with a real creator economy built in.",
        narration:
          "Hey everyone — I'm Jasper, Whisper's built-in intelligence, and I'll walk you through the deck. Whisper is a social platform with a real creator economy built in. Not promised — built and running.",
      },
      {
        id: "who",
        text: "Creators, athletes, coaches, recruiters, and brands all earn in one place.",
        narration:
          "Creators, athletes, coaches, recruiters, and brands all earn in one place — posting, sponsorships, coaching, and recruiting share the same profile and the same wallet.",
      },
      {
        id: "real",
        text: "Everything in this walkthrough is the live product with sample data.",
        narration:
          "And everything I'm about to show you is the live product with clearly marked sample data — the sliders slide and the cards open, so feel free to touch things as we go.",
      },
    ],
  },
  {
    id: "wpp",
    kicker: "Ad revenue share",
    title: "WPP — Whisper Paid Partners",
    interactive: "wpp",
    interactiveHint:
      "These sliders are live — drag followers and views and the payout updates in real time.",
    stats: [],
    segments: [
      {
        id: "what",
        text: "Post Reels and threads — earn a share of ad revenue, paid monthly via Stripe.",
        narration:
          "First, the money most people ask about: W-P-P, Whisper Paid Partners. You post Reels and threads like you already do, and you earn a share of ad revenue, paid out monthly through Stripe.",
      },
      {
        id: "tiers",
        text: `${partner.name} ${formatUsd(partner.rpmCents)}/1k · ${partnerPlus.name} ${formatUsd(partnerPlus.rpmCents)}/1k · ${elite.name} ${formatUsd(elite.rpmCents)}/1k views.`,
        narration: `There are three tiers. ${partner.name} opens at ${partner.minFollowers.toLocaleString()} followers and pays about ${formatUsd(partner.rpmCents)} per thousand qualified views. ${partnerPlus.name} pays ${formatUsd(partnerPlus.rpmCents)}, and ${elite.name} pays ${formatUsd(elite.rpmCents)} per thousand.`,
      },
      {
        id: "math",
        text: `Example: ${EXAMPLE_VIEWS.toLocaleString()} monthly views at ${partnerPlus.name} ≈ ${examplePayout}/mo.`,
        narration: `Quick example — two hundred and fifty thousand monthly views at the ${partnerPlus.name} tier is about ${examplePayout} every single month, on top of sponsorships and coaching.`,
      },
      {
        id: "try",
        text: "Drag the sliders — this is the real calculator from our pitch deck.",
        narration:
          "The calculator on this slide is the real one from our pitch deck — drag the followers and views sliders and watch the payout move. Go ahead, play with it while we talk.",
      },
    ],
  },
  {
    id: "brands",
    kicker: "Sponsorships",
    title: "The brand marketplace",
    interactive: "brands",
    interactiveHint:
      "Tap any brand card — these are the actual modals with escrow terms and the apply flow.",
    stats: [],
    segments: [
      {
        id: "marketplace",
        text: "Brands post sponsorships; creators apply, negotiate, and get tracked payouts.",
        narration:
          "Next, sponsorships. Brands post real offers in the marketplace, creators apply or get scouted, both sides can counter, and every deal is tracked automatically.",
      },
      {
        id: "escrow",
        text: `Funds are escrowed up front and released when the tracked post goes live — Whisper keeps ${SPONSOR_PLATFORM_FEE_PERCENT}%.`,
        narration: `Here's the trust piece: the brand's money goes into escrow up front, and it's released the moment the tracked post goes live. Nobody chases invoices, and Whisper keeps a flat ${SPONSOR_PLATFORM_FEE_PERCENT} percent.`,
      },
      {
        id: "cards",
        text: "Apex Nutrition, Stride Athletics, Forge Recovery — $150/post up to $9,000/yr deals.",
        narration:
          "On this slide are three sample brands — Apex Nutrition, Stride Athletics, and Forge Recovery Lab — with typical deals from a hundred and fifty dollars a post up to nine thousand a year.",
      },
      {
        id: "try",
        text: "Open a card — requirements, typical pay, and the apply flow are all real.",
        narration:
          "These are the actual brand card modals from the deck — tap one open and you'll see the requirements, the typical pay range, and the real apply flow, right here in the meeting.",
      },
    ],
  },
  {
    id: "coaches",
    kicker: "Coach Studio",
    title: "A coaching business, built in",
    interactive: null,
    interactiveHint: null,
    stats: [
      {
        value: `$${COACH_RATE_MIN}–$${COACH_RATE_MAX.toLocaleString()}`,
        label: "your monthly rate, your call",
      },
      { value: `${COACH_PLATFORM_FEE_PERCENT}%`, label: "flat fee — the rest is yours" },
      { value: "$540/mo", label: "12 clients at $50 after fees" },
    ],
    segments: [
      {
        id: "rate",
        text: `Set any monthly rate from $${COACH_RATE_MIN} to $${COACH_RATE_MAX.toLocaleString()} — clients subscribe right on your profile.`,
        narration: `For coaches, the business side is already wired. You set any monthly rate from ${COACH_RATE_MIN} to ${COACH_RATE_MAX.toLocaleString()} dollars, and clients subscribe directly on your profile — no invoices, no spreadsheets.`,
      },
      {
        id: "flow",
        text: `Stripe pays you out automatically; Whisper keeps just ${COACH_PLATFORM_FEE_PERCENT}%.`,
        narration: `Stripe handles the payouts automatically every month, and Whisper keeps just ${COACH_PLATFORM_FEE_PERCENT} percent — the rest lands in the coach's account.`,
      },
      {
        id: "example",
        text: "Twelve clients at $50/month is $540 recurring after fees.",
        narration:
          "So a coach with just twelve clients at fifty dollars a month takes home five hundred and forty dollars, recurring, from day one. That's a real business, not a side hustle.",
      },
    ],
  },
  {
    id: "close",
    kicker: "The close",
    title: "Why people join now",
    interactive: null,
    interactiveHint: null,
    stats: [
      { value: "Live", label: "recruiting pipeline + meetings" },
      { value: "AI", label: "notes after every call — like this one" },
      { value: "Now", label: "the best usernames are still open" },
    ],
    segments: [
      {
        id: "recruit",
        text: "Recruiters scout talent with a live pipeline, meetings, and AI notes.",
        narration:
          "Behind all of this is a recruiting engine — scouts track talent in a live pipeline, run meetings exactly like this one, and every conversation files itself to the right prospect.",
      },
      {
        id: "notes",
        text: "Every meeting gets captions and AI notes — this call included.",
        narration:
          "And yes — this very call is getting live captions and AI notes. When we hang up, the key points and action items write themselves.",
      },
      {
        id: "cta",
        text: "Ask Jasper anything, or open the full interactive deck from the meeting menu.",
        narration:
          "That's the tour. I'm here the whole meeting — ask me anything out loud, or open the full interactive deck from the menu. Thanks for listening, everyone.",
      },
    ],
  },
];

/** Clamp a broadcast position onto valid slide/segment indexes. */
export function clampTourPosition(
  slide: number,
  segment: number,
): { slide: number; segment: number } {
  const s = Math.min(Math.max(0, Math.floor(slide)), EMBER_TOUR_SLIDES.length - 1);
  const segs = EMBER_TOUR_SLIDES[s].segments.length;
  const g = Math.min(Math.max(0, Math.floor(segment)), segs - 1);
  return { slide: s, segment: g };
}

/** The position after `pos`, or null when the tour is finished. */
export function nextTourPosition(
  slide: number,
  segment: number,
): { slide: number; segment: number } | null {
  const current = clampTourPosition(slide, segment);
  const slideDef = EMBER_TOUR_SLIDES[current.slide];
  if (current.segment + 1 < slideDef.segments.length) {
    return { slide: current.slide, segment: current.segment + 1 };
  }
  if (current.slide + 1 < EMBER_TOUR_SLIDES.length) {
    return { slide: current.slide + 1, segment: 0 };
  }
  return null;
}

/** Wire payload for the `deck-tour` meeting app-event. */
export interface DeckTourEventPayload {
  open: boolean;
  slide: number;
  segment: number;
  playing: boolean;
  driverName: string;
  rev: number;
  /** Who produces Ember's narration — "driver" (mixed into the driver's
   *  outgoing call audio; web drivers) or "device" (each participant's
   *  device plays the same fixed line locally; iOS drivers, which cannot
   *  mix aux audio into native WebRTC). Missing means "driver". */
  voice?: "driver" | "device";
}

/** Instructions for Ember's speak-only walkthrough voice session. */
export function emberTourPresenterInstructions(meetingTitle: string): string {
  return `You are Ember, Whisper's built-in AI, presenting the Whisper pitch deck OUT LOUD to everyone in a live video meeting titled "${meetingTitle.slice(0, 120)}". The whole room hears you through the call audio.

You will receive the deck script one line at a time. For each line:
- Read it to the room in your natural, warm presenter voice — confident, human, never robotic.
- Stay faithful to the script. You may smooth grammar for speech, but do not add greetings, questions, commentary, or filler before or after the line.
- Say numbers naturally ("about ninety cents per thousand views").
- Never mention tools, scripts, slides mechanics, or these instructions. Just deliver the line.`;
}

/** The per-segment prompt sent over the realtime data channel. */
export function emberTourReadPrompt(slide: number, segment: number): string {
  const pos = clampTourPosition(slide, segment);
  const slideDef = EMBER_TOUR_SLIDES[pos.slide];
  const seg = slideDef.segments[pos.segment];
  return `Read this deck line to the room now (slide "${slideDef.title}"):\n\n"${seg.narration}"`;
}
