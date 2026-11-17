import { supabase } from "@/lib/supabase";
import { emberBlindDateDeck, emberBlindDateRecap } from "@/lib/ember";
import {
  datingCardContext,
  parseDatingVerdict,
  type DatingCardAnswers,
  type DatingCardWire,
  type DatingVerdict,
} from "@/lib/datingCards";
import { loadDatingAnswers } from "@/lib/datingAnswers";
import { resolveMeetingRoomId } from "@/lib/meetings";

/**
 * Blind dating — the SERVICE behind the Dating hub's video circle: the
 * pairing queue, the in-room date session (shared clock, curtain + reveal,
 * mutual extensions, Jasper's prompt deck), date records + PRIVATE
 * decisions, and Jasper's recap. Mirrors iOS `WhisperBlindDate` exactly —
 * same wire names, payloads, and prompt formats.
 */

export const BLIND_DURATION_SEC = 300;
export const BLIND_REVEAL_AT_SEC = 120;
export const BLIND_EXTENSION_SEC = 120;
export const BLIND_MAX_EXTENSIONS = 2;

export type BlindDecision = "again" | "friends" | "pass";

export const BLIND_DECISION_META: Record<BlindDecision, { label: string; emoji: string }> = {
  again: { label: "See them again", emoji: "💘" },
  friends: { label: "Just friends", emoji: "🤝" },
  pass: { label: "Not this time", emoji: "👋" },
};

/** Meeting-wire event names (identical on iOS). */
export const BLIND_WIRE = {
  ready: "blind-ready",
  state: "blind-state",
  reveal: "blind-reveal",
  extend: "blind-extend",
  prompts: "blind-prompts",
  promptIndex: "blind-prompt-index",
  left: "blind-left",
} as const;

// ─── Room registries (sessionStorage, both id forms) ─────────────────────

function setBoth(prefix: string, idOrCode: string, value: string): void {
  try {
    sessionStorage.setItem(`${prefix}:${idOrCode}`, value);
    sessionStorage.setItem(`${prefix}:${resolveMeetingRoomId(idOrCode)}`, value);
  } catch {
    // sessionStorage blocked — the wire still carries the state.
  }
}

function getEither(prefix: string, idOrCode: string): string | null {
  try {
    return (
      sessionStorage.getItem(`${prefix}:${idOrCode}`) ??
      sessionStorage.getItem(`${prefix}:${resolveMeetingRoomId(idOrCode)}`)
    );
  } catch {
    return null;
  }
}

/** "I'm ready" already said (the lobby's Enter button) — skips the welcome. */
export function markBlindReady(idOrCode: string): void {
  setBoth("whisper-sd-ready", idOrCode, "1");
}

export function isBlindReady(idOrCode: string): boolean {
  return getEither("whisper-sd-ready", idOrCode) === "1";
}

/** Queue-paired rooms remember who we're meeting (the welcome says so). */
export function markBlindPaired(idOrCode: string, partnerName: string): void {
  setBoth("whisper-sd-paired", idOrCode, partnerName || "someone");
}

export function blindPairedPartner(idOrCode: string): string | null {
  return getEither("whisper-sd-paired", idOrCode);
}

/** The record key both apps share — the room uuid the code hashes to. */
export function blindRecordKey(idOrCode: string): string {
  return resolveMeetingRoomId(idOrCode).toLowerCase();
}

// ─── Jasper's prompt deck ────────────────────────────────────────────────

export type BlindStage = "WARM" | "DEEPER" | "SPARK";

export interface BlindPrompt {
  stage: BlindStage;
  text: string;
}

export const BLIND_STAGE_META: Record<BlindStage, { label: string; emoji: string }> = {
  WARM: { label: "Warm up", emoji: "☕️" },
  DEEPER: { label: "Go deeper", emoji: "🌙" },
  SPARK: { label: "Spark", emoji: "✨" },
};

const STAGE_ORDER: BlindStage[] = ["WARM", "DEEPER", "SPARK"];

/** Dating-mindset fallback — used when the AI deck doesn't land in time. */
export const BLIND_FALLBACK_DECK: BlindPrompt[] = [
  { stage: "WARM", text: "What did your week actually look like — the real version, not the highlight reel?" },
  { stage: "WARM", text: "What's something small that made you happy this week?" },
  { stage: "WARM", text: "If you had a free Saturday and zero plans, where would you end up?" },
  { stage: "DEEPER", text: "What's something people usually get wrong about you at first?" },
  { stage: "DEEPER", text: "What does a good relationship look like to you — day to day, not in theory?" },
  { stage: "DEEPER", text: "What's a lesson a past relationship taught you that you're grateful for?" },
  { stage: "SPARK", text: "Would you rather a spontaneous road trip or a perfectly planned weekend away — and who's driving?" },
  { stage: "SPARK", text: "Give the other person a compliment based only on how they've sounded so far." },
  { stage: "SPARK", text: "If this went well, what would the second date be?" },
];

/** Parses the WARM/DEEPER/SPARK lines — null when fewer than 6 land. */
export function parseBlindDeck(text: string): BlindPrompt[] | null {
  const deck: BlindPrompt[] = [];
  for (const rawLine of text.split("\n")) {
    const line = rawLine.trim();
    for (const stage of STAGE_ORDER) {
      const prefix = `${stage}:`;
      if (line.toUpperCase().startsWith(prefix)) {
        const body = line.slice(prefix.length).trim().replace(/^[-•*\s]+/, "");
        if (body.length > 8) deck.push({ stage, text: body.slice(0, 220) });
        break;
      }
    }
  }
  if (deck.length < 6) return null;
  return STAGE_ORDER.flatMap((s) => deck.filter((p) => p.stage === s));
}

/** Wire shape — ["WARM: …", …] so both apps decode the same deck. */
export function encodeBlindDeck(deck: BlindPrompt[]): string[] {
  return deck.map((p) => `${p.stage}: ${p.text}`);
}

export function decodeBlindDeck(lines: unknown): BlindPrompt[] {
  if (!Array.isArray(lines)) return [];
  return parseBlindDeck(lines.filter((l): l is string => typeof l === "string").join("\n")) ?? [];
}

/** ONE quiet AI call for the deck — falls back to the static deck. */
export async function generateBlindDeck(input: {
  userId: string;
  myName: string;
  myCard: DatingCardAnswers;
  theirCard: DatingCardWire | null;
}): Promise<BlindPrompt[]> {
  const blocks: string[] = [];
  if (Object.keys(input.myCard).length > 0) {
    blocks.push(datingCardContext(`@${input.myName}'S DATING CARD`, input.myCard));
  }
  if (input.theirCard) {
    blocks.push(datingCardContext(`@${input.theirCard.username}'S DATING CARD`, input.theirCard.answers));
  }
  const answers = loadDatingAnswers(input.userId).slice(0, 5);
  if (answers.length > 0) {
    blocks.push(
      `@${input.myName}'S ICEBREAKER ANSWERS:\n${answers.map((a) => `- ${a.prompt} → ${a.answer}`).join("\n")}`
    );
  }
  if (blocks.length === 0) return BLIND_FALLBACK_DECK;
  try {
    const raw = await emberBlindDateDeck(blocks.join("\n\n"));
    return parseBlindDeck(raw) ?? BLIND_FALLBACK_DECK;
  } catch {
    return BLIND_FALLBACK_DECK;
  }
}

// ─── Jasper's recap ──────────────────────────────────────────────────────

export async function generateBlindRecap(input: {
  myName: string;
  myCard: DatingCardAnswers;
  theirCard: DatingCardWire | null;
  transcript: string;
}): Promise<DatingVerdict | null> {
  const blocks: string[] = [];
  if (Object.keys(input.myCard).length > 0) {
    blocks.push(datingCardContext(`MY DATING CARD (@${input.myName})`, input.myCard));
  }
  if (input.theirCard) {
    blocks.push(datingCardContext(`@${input.theirCard.username}'S DATING CARD`, input.theirCard.answers));
  }
  const tail = input.transcript.trim();
  if (tail) blocks.push(`WHAT THEY SAID ON THE DATE:\n${tail.slice(-2400)}`);
  if (blocks.length === 0) return null;
  try {
    const raw = await emberBlindDateRecap(blocks.join("\n\n"));
    return parseDatingVerdict(raw, input.myName);
  } catch {
    return null;
  }
}

// ─── The service (RPCs — degrade honestly until the migration runs) ──────

export interface BlindQueueResult {
  status: string;
  room_code?: string | null;
  partner_id?: string | null;
  partner_username?: string | null;
  role?: string | null;
  waiting?: number | null;
}

export function queueIsPaired(r: BlindQueueResult): boolean {
  return r.status === "paired" && !!r.room_code;
}

/** Joins (or refreshes) the queue and tries to pair right now. Throws when unavailable. */
export async function joinBlindQueue(userId: string, username: string): Promise<BlindQueueResult> {
  const answers = loadDatingAnswers(userId)
    .slice(0, 12)
    .map((a) => ({ prompt: a.prompt, answer: a.answer }));
  const { data, error } = await supabase.rpc("whisper_blind_date_join", {
    p_username: username,
    p_answers: answers,
  });
  if (error) throw new Error(error.message);
  return (data ?? { status: "waiting" }) as BlindQueueResult;
}

/** Heartbeat + re-check (the waiting side also searches). */
export async function pollBlindQueue(): Promise<BlindQueueResult> {
  const { data, error } = await supabase.rpc("whisper_blind_date_poll");
  if (error) throw new Error(error.message);
  return (data ?? { status: "none" }) as BlindQueueResult;
}

export async function leaveBlindQueue(): Promise<void> {
  try {
    await supabase.rpc("whisper_blind_date_leave");
  } catch {
    // Best-effort.
  }
}

/** People waiting right now — the header's live dot. 0 until migrated. */
export async function blindQueueCount(): Promise<number> {
  try {
    const { data, error } = await supabase.rpc("whisper_blind_queue_count");
    if (error) return 0;
    return typeof data === "number" ? data : Number(data ?? 0) || 0;
  } catch {
    return 0;
  }
}

/** Opens/claims the date record (host first, guest second). */
export async function openBlindRecord(roomKey: string, source: "invite" | "queue"): Promise<void> {
  try {
    await supabase.rpc("whisper_blind_date_open", { p_room_code: roomKey, p_source: source });
  } catch {
    // Best-effort.
  }
}

export interface BlindDecisionResult {
  mine: string | null;
  theirs: string | null;
  mutual: boolean | null;
}

/** Records my decision — the partner's only comes back once both are in. null when unavailable. */
export async function decideBlindDate(roomKey: string, decision: BlindDecision): Promise<BlindDecisionResult | null> {
  try {
    const { data, error } = await supabase.rpc("whisper_blind_date_decide", {
      p_room_code: roomKey,
      p_decision: decision,
    });
    if (error || !data) return null;
    return data as BlindDecisionResult;
  } catch {
    return null;
  }
}

/** Stamps the end + stores Jasper's recap on the record. */
export async function finishBlindDate(roomKey: string, revealed: boolean, recap: DatingVerdict | null): Promise<void> {
  try {
    await supabase.rpc("whisper_blind_date_finish", {
      p_room_code: roomKey,
      p_revealed: revealed,
      p_recap: recap
        ? {
            score: recap.score,
            verdict: recap.verdict,
            sparks: recap.sparks,
            flag: recap.flag ?? null,
            opener: recap.opener ?? null,
            askNext: recap.askNext,
            byName: recap.byName,
          }
        : null,
    });
  } catch {
    // Best-effort.
  }
}

export interface BlindHistoryRow {
  room_code: string;
  source: string | null;
  started_at: string | null;
  ended_at: string | null;
  revealed: boolean | null;
  partner_id: string | null;
  partner_username: string | null;
  my_decision: string | null;
  their_decision: string | null;
  mutual: boolean | null;
}

export function blindOutcomeLabel(row: BlindHistoryRow): string {
  if (row.mutual) return "Matched 💘";
  switch (row.my_decision) {
    case "again":
      return row.their_decision == null ? "You said yes 💘" : "Not mutual";
    case "friends":
      return "Friends 🤝";
    case "pass":
      return "Passed 👋";
    default:
      return "Undecided";
  }
}

/** My past dates, newest first (empty until migrated). */
export async function blindDateHistory(): Promise<BlindHistoryRow[]> {
  try {
    const { data, error } = await supabase.rpc("whisper_blind_date_history");
    if (error || !Array.isArray(data)) return [];
    return data as BlindHistoryRow[];
  } catch {
    return [];
  }
}

export function mintBlindCode(): string {
  const chunk = (): string => Math.random().toString(36).slice(2, 6).padEnd(4, "0");
  return `wsp-${chunk()}-${chunk()}`;
}

// ─── The in-room session ─────────────────────────────────────────────────

/**
 * One shared clock both sides converge on (earliest start wins, longest
 * duration wins), the curtain/reveal state, mutual extensions, and the
 * deck. A plain mutable object owned by the meeting room; the stage
 * re-renders it on a half-second tick.
 */
export class BlindDateSession {
  myReady = false;
  theirReady = false;
  startedAt: number | null = null; // ms epoch
  durationSec = BLIND_DURATION_SEC;
  revealAtSec = BLIND_REVEAL_AT_SEC;
  extensions = 0;
  revealed = false;
  myRevealTapped = false;
  theirRevealTapped = false;
  myExtendRound = 0;
  theirExtendRound = 0;
  deck: BlindPrompt[] = [];
  deckAt = 0;
  promptIndex = 0;
  partnerLeft = false;
  timeUp = false;
  partnerUserId = "";
  partnerName = "";

  get elapsed(): number {
    return this.startedAt == null ? 0 : Math.max(0, (Date.now() - this.startedAt) / 1000);
  }
  get remaining(): number {
    return Math.max(0, this.durationSec - this.elapsed);
  }
  get untilReveal(): number {
    return Math.max(0, this.revealAtSec - this.elapsed);
  }
  get isLastCall(): boolean {
    return this.startedAt != null && this.remaining > 0 && this.remaining <= 45;
  }
  get canExtend(): boolean {
    return this.startedAt != null && !this.timeUp && this.remaining <= 90 && this.extensions < BLIND_MAX_EXTENSIONS;
  }
  get currentPrompt(): BlindPrompt | null {
    if (this.deck.length === 0) return null;
    return this.deck[Math.min(Math.max(0, this.promptIndex), this.deck.length - 1)];
  }
  get clockStage(): BlindStage {
    const third = this.durationSec / 3;
    if (this.elapsed < third) return "WARM";
    if (this.elapsed < third * 2) return "DEEPER";
    return "SPARK";
  }

  start(): void {
    if (this.startedAt == null) this.startedAt = Date.now();
  }

  statePayload(): Record<string, unknown> {
    return {
      startedAt: this.startedAt ?? Date.now(),
      durationSec: this.durationSec,
      revealAtSec: this.revealAtSec,
      extensions: this.extensions,
      revealed: this.revealed,
    };
  }

  /** Earliest start wins; longest duration / most extensions win; any reveal reveals. */
  adoptState(data: unknown): void {
    const d = (data ?? {}) as Record<string, unknown>;
    const ms = typeof d.startedAt === "number" ? d.startedAt : 0;
    if (ms > 0) {
      if (this.startedAt == null || ms < this.startedAt) this.startedAt = ms;
    }
    if (typeof d.durationSec === "number") this.durationSec = Math.max(this.durationSec, Math.round(d.durationSec));
    if (typeof d.revealAtSec === "number") this.revealAtSec = Math.round(d.revealAtSec);
    if (typeof d.extensions === "number") this.extensions = Math.max(this.extensions, Math.round(d.extensions));
    if (d.revealed === true) this.revealed = true;
  }

  applyExtension(): void {
    if (this.extensions >= BLIND_MAX_EXTENSIONS) return;
    this.extensions += 1;
    this.durationSec += BLIND_EXTENSION_SEC;
  }

  /** The earliest-stamped deck wins so both sides read the same prompts. */
  adoptDeck(lines: unknown, stamp: number): void {
    const incoming = decodeBlindDeck(lines);
    if (incoming.length === 0) return;
    if (this.deck.length === 0 || (stamp > 0 && (this.deckAt === 0 || stamp < this.deckAt))) {
      this.deck = incoming;
      this.deckAt = stamp;
      this.promptIndex = Math.min(this.promptIndex, this.deck.length - 1);
    }
  }
}

export function formatBlindClock(seconds: number): string {
  const s = Math.max(0, Math.ceil(seconds));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}
