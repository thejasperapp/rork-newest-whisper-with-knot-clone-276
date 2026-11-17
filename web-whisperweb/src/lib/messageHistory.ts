import type { WhisperMessage } from "./types";

export const RECENT_MESSAGE_LIMIT = 100;
export const OLDER_MESSAGE_LIMIT = 50;
export interface MessageCursor { createdAt: string | null; id: string }
export interface MessagePage { messages: WhisperMessage[]; next: MessageCursor | null }

// Only server-generated UUIDs/timestamps may be interpolated into PostgREST's
// compound filter grammar. Never interpolate message bodies or search text.
export function beforeMessage(cursor: MessageCursor): string {
  if (!/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(cursor.id) ||
      (cursor.createdAt !== null && !/^\d{4}-\d\d-\d\dT[\d:.]+(?:Z|[+-]\d\d:\d\d)$/.test(cursor.createdAt))) {
    throw new Error("Invalid history continuation. Reopen this conversation.");
  }
  return cursor.createdAt === null
    ? `and(created_at.is.null,id.lt.${cursor.id})`
    : `created_at.lt.${cursor.createdAt},and(created_at.eq.${cursor.createdAt},id.lt.${cursor.id}),created_at.is.null`;
}

export function messagePage(rows: WhisperMessage[], limit: number): MessagePage {
  // Query order is newest first, with a sentinel row. The cursor is based on
  // raw rows, not rendered bubbles (which can collapse embeds or hide rows).
  const messages = rows.slice(0, limit);
  const last = messages[messages.length - 1];
  return {
    messages: messages.reverse(),
    next: rows.length > limit && last ? { createdAt: last.created_at, id: last.id } : null,
  };
}

export function uniqueHistory(pages: MessagePage[]): WhisperMessage[] {
  const rows = new Map<string, WhisperMessage>();
  // The recent page is authoritative if pages overlap during a refresh.
  for (const page of [...pages].reverse()) for (const row of page.messages) rows.set(row.id, row);
  return [...rows.values()].sort((a, b) => {
    // Normalize to microsecond precision rather than rounding to milliseconds.
    const stamp = (value: string | null) => value === null ? Number.NEGATIVE_INFINITY : Date.parse(value);
    const delta = stamp(a.created_at) - stamp(b.created_at);
    if (delta !== 0 && !Number.isNaN(delta)) return delta;
    // Date.parse already includes milliseconds; compare only the remaining
    // precision so equivalent timestamps with different offsets stay tied.
    const fraction = (value: string | null) => (value?.match(/\.(\d+)/)?.[1] ?? "").padEnd(6, "0").slice(3, 6);
    return fraction(a.created_at).localeCompare(fraction(b.created_at)) || a.id.localeCompare(b.id);
  });
}
