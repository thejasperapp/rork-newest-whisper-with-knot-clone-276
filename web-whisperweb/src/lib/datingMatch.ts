/**
 * The mutual-match wire — 💘 requests and the matched token ride DM
 * bodies, so matches flow web ↔ iOS on the existing message rails
 * (and the push fanout carries the notification for free). Mirrors iOS
 * `WhisperMatchWire` exactly.
 */

export const MATCH_REQUEST_PREFIX = "::whisper-matchreq-v1::";
export const MATCHED_PREFIX = "::whisper-matched-v1::";

export interface MatchToken {
  matched: boolean;
  from: string;
  name: string;
}

export function buildMatchRequest(fromUserId: string, name: string): string {
  return MATCH_REQUEST_PREFIX + JSON.stringify({ from: fromUserId, name });
}

export function buildMatched(fromUserId: string, name: string): string {
  return MATCHED_PREFIX + JSON.stringify({ from: fromUserId, name });
}

export function decodeMatchToken(body: string | null | undefined): MatchToken | null {
  const t = body ?? "";
  let matched: boolean;
  let payload: string;
  if (t.startsWith(MATCH_REQUEST_PREFIX)) {
    matched = false;
    payload = t.slice(MATCH_REQUEST_PREFIX.length);
  } else if (t.startsWith(MATCHED_PREFIX)) {
    matched = true;
    payload = t.slice(MATCHED_PREFIX.length);
  } else {
    return null;
  }
  try {
    const parsed = JSON.parse(payload) as { from?: unknown; name?: unknown };
    if (typeof parsed.from !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(parsed.from)) return null;
    return {
      matched,
      from: parsed.from,
      name: typeof parsed.name === "string" && parsed.name ? parsed.name : "someone",
    };
  } catch {
    return null;
  }
}

/** Friendly inbox preview line for a match token, or null. */
export function matchPreviewLine(body: string | null | undefined): string | null {
  const t = body ?? "";
  if (t.startsWith(MATCH_REQUEST_PREFIX)) return "💘 Wants to match";
  if (t.startsWith(MATCHED_PREFIX)) return "💘 It's a match!";
  return null;
}

// ─── One celebration per thread ─────────────────────────────────────────

const seenKey = (userId: string, peerId: string): string =>
  `whisper-match-seen:${userId.toLowerCase()}:${peerId.toLowerCase()}`;

export function matchCelebrationSeen(userId: string, peerId: string): boolean {
  try {
    return localStorage.getItem(seenKey(userId, peerId)) === "1";
  } catch {
    return true;
  }
}

export function markMatchCelebrationSeen(userId: string, peerId: string): void {
  try {
    localStorage.setItem(seenKey(userId, peerId), "1");
  } catch {
    // Storage blocked — worst case the celebration replays next open.
  }
}
