/**
 * Jasper's matchmaker RESPONSE SYSTEM — the brain answers in a strict
 * grammar (READ / MATCH / MOVE) and the dock renders it as real cards.
 * Anything that doesn't parse falls back to the plain reply. Mirrors iOS
 * `WhisperMatchmakerReply` exactly.
 */

export interface MatchmakerMatch {
  username: string;
  why: string;
  opener: string;
}

export interface MatchmakerParsed {
  read: string | null;
  matches: MatchmakerMatch[];
  move: string | null;
}

/** The strict-format instruction every matchmaker lens ends with. */
export const MATCHMAKER_FORMAT = `Reply in EXACTLY this format and nothing else:
READ: <one honest line about me or the room right now>
MATCH: @username | <why we click — one line grounded in their actual words> | <a say-hi opener in first person, one line, specific>
MATCH: @username | <why> | <opener>
MOVE: <the one concrete thing I should do next — one line>
Use only people who appear in the context. If nobody fits yet, give no MATCH lines and make MOVE the honest next step.`;

function clean(s: string): string {
  return s.trim().replace(/\*\*/g, "").replace(/^["“”\s]+|["“”\s]+$/g, "");
}

/** null when no READ/MATCH/MOVE structure is present — render plain text. */
export function parseMatchmakerReply(text: string): MatchmakerParsed | null {
  let read: string | null = null;
  let move: string | null = null;
  const matches: MatchmakerMatch[] = [];
  for (const rawLine of text.split("\n")) {
    const line = rawLine.trim().replace(/^[*\-•\s]+/, "");
    const upper = line.toUpperCase();
    if (upper.startsWith("READ:")) {
      read = clean(line.slice(5));
    } else if (upper.startsWith("MOVE:")) {
      move = clean(line.slice(5));
    } else if (upper.startsWith("MATCH:")) {
      const parts = line.slice(6).split("|").map(clean);
      const username = (parts[0] ?? "").replace(/@/g, "").replace(/^[*_\s]+|[*_\s]+$/g, "");
      if (!username) continue;
      matches.push({ username, why: parts[1] ?? "", opener: parts[2] ?? "" });
    }
  }
  if (read == null && move == null && matches.length === 0) return null;
  return { read, matches: matches.slice(0, 3), move };
}
