/**
 * Local "Delete conversation" store. Whisper DMs are shared rows in
 * `whisper_messages`, so deleting them server-side would also wipe the other
 * person's copy. Instead — mirroring the iOS "Delete for me" behaviour, which
 * persists hidden state to `UserDefaults` — we record a per-conversation
 * timestamp in `localStorage`. A conversation stays hidden until a message
 * newer than that timestamp arrives, at which point it reappears (standard
 * messaging-app behaviour).
 */

const STORAGE_KEY = "whisper:deletedConversations:v1";

type DeletedMap = Record<string, string>;

function read(): DeletedMap {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return {};
    const parsed = JSON.parse(raw) as unknown;
    return parsed && typeof parsed === "object" ? (parsed as DeletedMap) : {};
  } catch {
    return {};
  }
}

function write(map: DeletedMap): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(map));
  } catch {
    // Ignore quota / private-mode errors — deletion is best-effort local state.
  }
}

/** Marks a conversation as deleted as of now (or a given last-message date). */
export function markConversationDeleted(
  otherUserId: string,
  asOf?: string | null
): void {
  const map = read();
  map[otherUserId] = asOf ?? new Date().toISOString();
  write(map);
}

/** Removes the hidden flag so the conversation shows again. */
export function clearConversationDeleted(otherUserId: string): void {
  const map = read();
  if (otherUserId in map) {
    delete map[otherUserId];
    write(map);
  }
}

/**
 * True when the conversation should be hidden: it was deleted and no message
 * newer than the deletion timestamp has arrived since.
 */
export function isConversationHidden(
  otherUserId: string,
  lastDate: string | null | undefined
): boolean {
  const map = read();
  const deletedAt = map[otherUserId];
  if (!deletedAt) return false;
  if (!lastDate) return true;
  return new Date(lastDate).getTime() <= new Date(deletedAt).getTime();
}
