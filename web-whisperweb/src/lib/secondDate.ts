/**
 * Second-date scheduler wire (Round 77) — mirrors iOS `WhisperSecondDate`
 * exactly. A proposal rides a DM body as a token both apps render as a rose
 * card; accepting sends a confirm token. Never render the raw token.
 */

export const DATE_INVITE_PREFIX = "::whisper-date-invite-v1::";
export const DATE_CONFIRM_PREFIX = "::whisper-date-confirm-v1::";

export interface SecondDateInvite {
  id: string;
  /** ISO 8601 instant of the date. */
  slot: string;
  title: string;
  /** wsp-xxxx-xxxx Whisper Meet code minted by the proposer. */
  meetCode: string;
  /** Proposer's user id. */
  from: string;
  fromName: string;
}

export interface SecondDateSlot {
  date: Date;
  title: string;
  why: string;
}

/** Jasper's three proposals — same rule as iOS (next evening · Saturday 2pm · four days out 6:30pm). */
export function proposeSecondDateSlots(now: Date = new Date()): SecondDateSlot[] {
  const out: SecondDateSlot[] = [];
  const eveningDay = new Date(now);
  if (now.getHours() >= 17) eveningDay.setDate(eveningDay.getDate() + 1);
  const evening = new Date(eveningDay);
  evening.setHours(19, 30, 0, 0);
  out.push({ date: evening, title: "Dinner & a walk", why: "Soon while the spark's fresh" });

  const probe = new Date(now);
  probe.setDate(probe.getDate() + 1);
  for (let i = 0; i < 8; i++) {
    if (probe.getDay() === 6) {
      const sat = new Date(probe);
      sat.setHours(14, 0, 0, 0);
      if (sat.getTime() > now.getTime()) {
        out.push({ date: sat, title: "Coffee & a wander", why: "Daylight, low pressure" });
        break;
      }
    }
    probe.setDate(probe.getDate() + 1);
  }

  const later = new Date(now);
  later.setDate(later.getDate() + 4);
  later.setHours(18, 30, 0, 0);
  out.push({ date: later, title: "Drinks & a game", why: "Room to plan something fun" });
  return out.sort((a, b) => a.date.getTime() - b.date.getTime());
}

export function mintMeetCode(): string {
  const alphabet = "abcdefghijklmnopqrstuvwxyz0123456789";
  const chunk = (): string =>
    Array.from({ length: 4 }, () => alphabet[Math.floor(Math.random() * alphabet.length)]).join("");
  return `wsp-${chunk()}-${chunk()}`;
}

export function encodeDateInvite(invite: SecondDateInvite): string {
  return DATE_INVITE_PREFIX + JSON.stringify(invite);
}

export function encodeDateConfirm(invite: SecondDateInvite): string {
  return DATE_CONFIRM_PREFIX + JSON.stringify(invite);
}

/** Decode either token → { invite, confirm } or null. */
export function decodeSecondDate(body: string | null | undefined): { invite: SecondDateInvite; confirm: boolean } | null {
  const t = (body ?? "").trim();
  let confirm: boolean;
  let payload: string;
  if (t.startsWith(DATE_INVITE_PREFIX)) {
    confirm = false;
    payload = t.slice(DATE_INVITE_PREFIX.length);
  } else if (t.startsWith(DATE_CONFIRM_PREFIX)) {
    confirm = true;
    payload = t.slice(DATE_CONFIRM_PREFIX.length);
  } else {
    return null;
  }
  try {
    const parsed = JSON.parse(payload) as Partial<SecondDateInvite>;
    if (!parsed || typeof parsed.slot !== "string" || typeof parsed.meetCode !== "string") return null;
    return {
      confirm,
      invite: {
        id: typeof parsed.id === "string" ? parsed.id : crypto.randomUUID(),
        slot: parsed.slot,
        title: typeof parsed.title === "string" ? parsed.title : "Second date",
        meetCode: parsed.meetCode,
        from: typeof parsed.from === "string" ? parsed.from : "",
        fromName: typeof parsed.fromName === "string" ? parsed.fromName : "someone",
      },
    };
  } catch {
    return null;
  }
}

export function isSecondDateToken(body: string | null | undefined): boolean {
  const t = (body ?? "").trim();
  return t.startsWith(DATE_INVITE_PREFIX) || t.startsWith(DATE_CONFIRM_PREFIX);
}

/** Friendly inbox/push line for either token. */
export function secondDatePreviewLine(body: string | null | undefined): string | null {
  const d = decodeSecondDate(body);
  if (!d) return null;
  const when = new Date(d.invite.slot);
  const label = Number.isNaN(when.getTime())
    ? ""
    : when.toLocaleString(undefined, { weekday: "short", hour: "numeric", minute: "2-digit" });
  return d.confirm ? `Second date confirmed 💘 ${label}`.trim() : `Proposed a second date 💘 ${label}`.trim();
}

// ─── Match expiry (Round 77) ─────────────────────────────────────────────

export const MATCH_EXPIRY_DAYS = 7;

export interface MatchExpiryState {
  daysLeft: number;
  faded: boolean;
  /** Chip copy — null while the match is comfortably alive. */
  chip: string | null;
  nudge: boolean;
}

/**
 * Matches fade after 7 quiet days — anchored on the matched token, reset by
 * any real message from either side (tokens don't count). Same rule as iOS.
 */
export function matchExpiryState(matchedAt: Date, lastMessageAt: Date | null, now: Date = new Date()): MatchExpiryState {
  const anchor = Math.max(matchedAt.getTime(), lastMessageAt?.getTime() ?? matchedAt.getTime());
  const elapsedDays = Math.floor((now.getTime() - anchor) / 86_400_000);
  const left = MATCH_EXPIRY_DAYS - elapsedDays;
  const faded = left < 0;
  const daysLeft = Math.max(0, left);
  let chip: string | null = null;
  if (faded) chip = "Faded 💫";
  else if (daysLeft <= 2) chip = daysLeft <= 0 ? "Fades today 💫" : `Fades in ${daysLeft}d 💫`;
  return { daysLeft, faded, chip, nudge: !faded && daysLeft <= 2 };
}
