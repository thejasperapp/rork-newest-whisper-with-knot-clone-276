/**
 * Device-local registry of dating chats — powers the 💘 inbox filter and
 * cupid Jasper's date tools in DM threads. Peers land here automatically
 * when you say hi from the Dating hub; the tools row can unmark a chat.
 * Mirrors iOS `WhisperDatingContacts`.
 */

const key = (userId: string): string => `whisper-dating-peers:${userId}`;

export function datingPeers(userId: string): Set<string> {
  try {
    const raw = localStorage.getItem(key(userId));
    if (!raw) return new Set();
    const arr = JSON.parse(raw) as unknown;
    return new Set(Array.isArray(arr) ? arr.filter((x): x is string => typeof x === "string") : []);
  } catch {
    return new Set();
  }
}

export function isDatingPeer(userId: string, peerId: string): boolean {
  return datingPeers(userId).has(peerId);
}

export function markDatingPeer(userId: string, peerId: string): void {
  if (!userId || !peerId || userId === peerId) return;
  const set = datingPeers(userId);
  if (set.has(peerId)) return;
  set.add(peerId);
  try {
    localStorage.setItem(key(userId), JSON.stringify([...set]));
  } catch {
    // Storage blocked — the filter simply won't remember this chat.
  }
}

/** Flips a chat in/out of the dating inbox; returns the NEW state. */
export function toggleDatingPeer(userId: string, peerId: string): boolean {
  const set = datingPeers(userId);
  const next = !set.has(peerId);
  if (next) set.add(peerId);
  else set.delete(peerId);
  try {
    localStorage.setItem(key(userId), JSON.stringify([...set]));
  } catch {
    // Storage blocked.
  }
  return next;
}
