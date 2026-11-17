/**
 * Private icebreaker answers — saved when you ANSWER, never posted.
 * They quietly tune the For-you match sort; sharing to the hub is a
 * separate explicit choice. Mirrors iOS `WhisperDatingAnswers` exactly
 * (same storage shape) so the answering grammar matches across apps.
 */

export interface PrivateDatingAnswer {
  prompt: string;
  answer: string;
  /** Unix seconds — matches the iOS `at` timestamp. */
  at: number;
}

const key = (userId: string): string => `whisper-dating-answers:${userId.toLowerCase()}`;

/** Every saved answer, newest first. */
export function loadDatingAnswers(userId: string): PrivateDatingAnswer[] {
  try {
    const raw = localStorage.getItem(key(userId));
    if (!raw) return [];
    const parsed = JSON.parse(raw) as unknown;
    if (!Array.isArray(parsed)) return [];
    return parsed
      .filter(
        (x): x is PrivateDatingAnswer =>
          !!x &&
          typeof (x as PrivateDatingAnswer).prompt === "string" &&
          (x as PrivateDatingAnswer).prompt.length > 0 &&
          typeof (x as PrivateDatingAnswer).answer === "string" &&
          (x as PrivateDatingAnswer).answer.length > 0
      )
      .map((x) => ({ ...x, at: typeof x.at === "number" ? x.at : 0 }))
      .sort((a, b) => b.at - a.at);
  } catch {
    return [];
  }
}

export function datingAnswerFor(userId: string, prompt: string): string | null {
  const found = loadDatingAnswers(userId).find(
    (a) => a.prompt.toLowerCase() === prompt.toLowerCase()
  );
  return found?.answer ?? null;
}

/** Upserts by prompt (newest first), capped at 24 entries. */
export function saveDatingAnswer(userId: string, prompt: string, answer: string): void {
  const trimmed = answer.trim();
  if (!trimmed) return;
  const rest = loadDatingAnswers(userId).filter(
    (a) => a.prompt.toLowerCase() !== prompt.toLowerCase()
  );
  const next: PrivateDatingAnswer[] = [
    { prompt, answer: trimmed.slice(0, 280), at: Math.floor(Date.now() / 1000) },
    ...rest,
  ].slice(0, 24);
  try {
    localStorage.setItem(key(userId), JSON.stringify(next));
  } catch {
    // Storage blocked — the answer simply won't persist on this device.
  }
}
