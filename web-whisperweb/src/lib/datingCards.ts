import { supabase } from "@/lib/supabase";
import { resolveMeetingRoomId } from "@/lib/meetings";

/**
 * Speed dating — the saved dating card, the wire it rides in meetings,
 * and the compatibility verdict. Mirrors iOS `WhisperSpeedDating` exactly
 * (same question ids, same wire shape) so cards flow web ↔ iOS.
 */

export interface DatingCardQuestion {
  id: string;
  label: string;
  placeholder: string;
}

/** The five saved prompts — identical ids/labels on iOS. */
export const DATING_CARD_QUESTIONS: DatingCardQuestion[] = [
  { id: "looking", label: "What are you looking for?", placeholder: "Something real, something casual, new people…" },
  { id: "interests", label: "Your interests & passions", placeholder: "Lifting, cooking, live music, trail runs…" },
  { id: "dealbreakers", label: "Non-negotiables", placeholder: "Kindness, ambition, no smokers…" },
  { id: "firstDate", label: "Your ideal first date", placeholder: "Coffee and a long walk, tacos, climbing…" },
  { id: "funFact", label: "A fun fact about you", placeholder: "I've been to 14 countries…" },
];

export type DatingCardAnswers = Record<string, string>;

const localKey = (userId: string): string => `whisper-dating-card:${userId}`;

/** Instant local read — the wire + judge run off this. */
export function loadDatingCardLocal(userId: string): DatingCardAnswers {
  try {
    const raw = localStorage.getItem(localKey(userId));
    if (!raw) return {};
    const parsed = JSON.parse(raw) as unknown;
    if (!parsed || typeof parsed !== "object") return {};
    const out: DatingCardAnswers = {};
    DATING_CARD_QUESTIONS.forEach((q) => {
      const v = (parsed as Record<string, unknown>)[q.id];
      if (typeof v === "string" && v.trim()) out[q.id] = v.trim().slice(0, 240);
    });
    return out;
  } catch {
    return {};
  }
}

export function hasDatingCard(answers: DatingCardAnswers): boolean {
  return DATING_CARD_QUESTIONS.some((q) => (answers[q.id] ?? "").trim().length > 0);
}

/** Cloud pull (best-effort) — merges the saved row into local storage. */
export async function syncDatingCardFromCloud(userId: string): Promise<DatingCardAnswers> {
  try {
    const { data } = await supabase
      .from("whisper_dating_cards")
      .select("answers")
      .eq("user_id", userId)
      .maybeSingle();
    const answers = (data?.answers ?? null) as Record<string, unknown> | null;
    if (answers && typeof answers === "object") {
      const clean: DatingCardAnswers = {};
      DATING_CARD_QUESTIONS.forEach((q) => {
        const v = answers[q.id];
        if (typeof v === "string" && v.trim()) clean[q.id] = v.trim().slice(0, 240);
      });
      if (Object.keys(clean).length > 0) {
        localStorage.setItem(localKey(userId), JSON.stringify(clean));
        return clean;
      }
    }
  } catch {
    // Table not migrated yet — the local copy still powers everything.
  }
  return loadDatingCardLocal(userId);
}

/** Saves locally ALWAYS + upserts to Supabase best-effort. */
export async function saveDatingCard(userId: string, answers: DatingCardAnswers): Promise<void> {
  const clean: DatingCardAnswers = {};
  DATING_CARD_QUESTIONS.forEach((q) => {
    const v = (answers[q.id] ?? "").trim();
    if (v) clean[q.id] = v.slice(0, 240);
  });
  try {
    localStorage.setItem(localKey(userId), JSON.stringify(clean));
  } catch {
    // Storage blocked — the cloud copy still saves below.
  }
  try {
    await supabase
      .from("whisper_dating_cards")
      .upsert({ user_id: userId, answers: clean, updated_at: new Date().toISOString() });
  } catch {
    // Honest degradation: device-local until the migration runs.
  }
}

// ─── The wire — one participant's card in a speed-date room ─────────────

export interface DatingCardWire {
  userId: string;
  username: string;
  answers: DatingCardAnswers;
}

/** Flat payload (question ids as keys) — identical shape on iOS. */
export function datingCardWirePayload(
  userId: string,
  username: string,
  answers: DatingCardAnswers
): Record<string, unknown> {
  return { userId, username, ...answers };
}

export function decodeDatingCardWire(data: unknown): DatingCardWire | null {
  const d = (data ?? null) as Record<string, unknown> | null;
  if (!d || typeof d.userId !== "string" || !d.userId) return null;
  const username = typeof d.username === "string" && d.username ? d.username : "someone";
  const answers: DatingCardAnswers = {};
  DATING_CARD_QUESTIONS.forEach((q) => {
    const v = d[q.id];
    if (typeof v === "string" && v.trim()) answers[q.id] = v.trim().slice(0, 240);
  });
  return { userId: d.userId, username, answers };
}

/** Labeled context block for the judge prompt. */
export function datingCardContext(label: string, answers: DatingCardAnswers): string {
  const lines = DATING_CARD_QUESTIONS.filter((q) => (answers[q.id] ?? "").trim()).map(
    (q) => `- ${q.label} ${answers[q.id]}`
  );
  return lines.length > 0 ? `${label}:\n${lines.join("\n")}` : `${label}: (no card shared)`;
}

// ─── Speed-date room flags ──────────────────────────────────────────────

export function mintSpeedDateCode(): string {
  const chunk = (): string => Math.random().toString(36).slice(2, 6).padEnd(4, "0");
  return `wsp-${chunk()}-${chunk()}`;
}

/** Primes a room for speed-date mode under BOTH id forms (code + uuid). */
export function markSpeedDateRoom(code: string): void {
  try {
    sessionStorage.setItem(`whisper-speed-date:${code}`, "1");
    sessionStorage.setItem(`whisper-speed-date:${resolveMeetingRoomId(code)}`, "1");
  } catch {
    // sessionStorage blocked — guests still activate off the wire.
  }
}

export function isSpeedDateRoom(idOrCode: string): boolean {
  try {
    return (
      sessionStorage.getItem(`whisper-speed-date:${idOrCode}`) === "1" ||
      sessionStorage.getItem(`whisper-speed-date:${resolveMeetingRoomId(idOrCode)}`) === "1"
    );
  } catch {
    return false;
  }
}

// ─── The verdict ────────────────────────────────────────────────────────

export interface DatingVerdict {
  score: number;
  verdict: string;
  sparks: string[];
  askNext: string;
  byName: string;
  /** Blind-date recap: one honest thing to watch (optional). */
  flag?: string;
  /** Blind-date recap: the first message to send after the date (optional). */
  opener?: string;
}

/** Parses Jasper's SCORE/VERDICT/SPARK/ASK reply with defensive fallbacks. */
export function parseDatingVerdict(raw: string, byName: string): DatingVerdict | null {
  const text = raw.trim();
  if (!text) return null;
  const scoreMatch = text.match(/SCORE:\s*(\d{1,3})/i) ?? text.match(/\b(\d{1,3})\s*(?:%|\/\s*100)/);
  if (!scoreMatch) return null;
  const score = Math.max(0, Math.min(100, parseInt(scoreMatch[1], 10)));
  const verdict = /VERDICT:\s*(.+)/i.exec(text)?.[1]?.trim() ?? "";
  const sparks: string[] = [];
  const sparkRe = /SPARK:\s*(.+)/gi;
  let m: RegExpExecArray | null = sparkRe.exec(text);
  while (m && sparks.length < 3) {
    const spark = m[1]?.trim();
    if (spark) sparks.push(spark);
    m = sparkRe.exec(text);
  }
  const askNext = /ASK:\s*(.+)/i.exec(text)?.[1]?.trim() ?? "";
  const flag = /FLAG:\s*(.+)/i.exec(text)?.[1]?.trim();
  const opener = /OPENER:\s*(.+)/i.exec(text)?.[1]?.trim();
  return {
    score,
    verdict: verdict || "A promising match — keep talking.",
    sparks,
    askNext,
    byName,
    ...(flag ? { flag } : {}),
    ...(opener ? { opener } : {}),
  };
}
