/**
 * Local story seen-state — powers the Instagram-style tray rings (gradient
 * while a group has unseen stories, gray hairline once every story was
 * opened). Mirrors the iOS `WhisperStoryService.seenStoryIDs` behavior.
 */

const KEY = "whisper_story_seen_v1";
const CAP = 900;

export function loadSeenStoryIds(): Set<string> {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return new Set();
    const list = JSON.parse(raw) as unknown;
    return new Set(
      Array.isArray(list) ? (list.filter((x) => typeof x === "string") as string[]) : []
    );
  } catch {
    return new Set();
  }
}

export function markStorySeen(id: string): void {
  if (!id) return;
  try {
    const seen = loadSeenStoryIds();
    if (seen.has(id)) return;
    const list = [...seen, id];
    localStorage.setItem(KEY, JSON.stringify(list.slice(-CAP)));
  } catch {
    // Storage unavailable (private mode) — rings just stay bold.
  }
}
