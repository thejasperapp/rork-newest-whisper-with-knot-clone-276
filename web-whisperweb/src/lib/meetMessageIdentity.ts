import type { WhisperMessage } from "@/lib/types";

const prefix = "::whisper-calendar-v1::";
/** A presentation key, never proof of access to an invitation. */
export function meetEventID(body: unknown): string | null {
  if (typeof body !== "string" || !body.startsWith(prefix) || body.length > 32_768) return null;
  try {
    const card: unknown = JSON.parse(body.slice(prefix.length));
    if (!card || typeof card !== "object") return null;
    const value = card as Record<string, unknown>;
    return value.kind === "chat-meet" && typeof value.eventID === "string" && /^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(value.eventID) ? value.eventID.toLowerCase() : null;
  } catch { return null; }
}

/** Collapse repeated deliveries of one event only inside the same directed conversation. */
export function collapseMeetMessages(rows: WhisperMessage[]): WhisperMessage[] {
  const seen = new Set<string>();
  return rows.filter(row => {
    const event = meetEventID(row.body);
    if (!event || typeof row.from_user_id !== "string" || typeof row.to_user_id !== "string"
      || (row.thread_id != null && typeof row.thread_id !== "string")) return true;
    const key = [row.from_user_id, row.to_user_id, row.thread_id ?? "direct", event].map(v => v.toLowerCase()).join("|");
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}
