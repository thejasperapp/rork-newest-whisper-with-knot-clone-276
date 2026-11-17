import type { PostMusic } from "@/lib/postMeta";

/**
 * Device-local post draft system. The thread composer autosaves everything
 * restorable (caption, community, poll, tags, location, music, audience) as
 * you type, restores it next time the composer opens, and clears it the
 * moment the post publishes — so an accidental close never eats a post.
 *
 * A separate one-shot "prefill" slot lets other surfaces (Ember's post
 * drafts) hand a ready-made caption to the composer.
 */

export interface ComposerDraft {
  caption: string;
  topic: string | null;
  poll: string[] | null;
  tagged: string[];
  location: string | null;
  music: PostMusic | null;
  audience: string;
  savedAt: number;
}

export interface ComposerPrefill {
  caption: string;
  topic?: string | null;
}

const DRAFT_KEY = "whisper_post_draft_v1";
const PREFILL_KEY = "whisper_composer_prefill_v1";

/** True when a draft holds anything worth restoring. */
export function draftHasContent(d: ComposerDraft): boolean {
  return (
    d.caption.trim().length > 0 ||
    !!d.topic ||
    (d.poll?.some((o) => o.trim().length > 0) ?? false) ||
    d.tagged.length > 0 ||
    !!d.location ||
    !!d.music
  );
}

export function loadComposerDraft(): ComposerDraft | null {
  try {
    const raw = localStorage.getItem(DRAFT_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as ComposerDraft;
    if (typeof parsed.caption !== "string") return null;
    return draftHasContent(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

export function saveComposerDraft(draft: Omit<ComposerDraft, "savedAt">): void {
  try {
    const full: ComposerDraft = { ...draft, savedAt: Date.now() };
    if (!draftHasContent(full)) {
      localStorage.removeItem(DRAFT_KEY);
      return;
    }
    localStorage.setItem(DRAFT_KEY, JSON.stringify(full));
  } catch {
    /* storage unavailable */
  }
}

export function clearComposerDraft(): void {
  try {
    localStorage.removeItem(DRAFT_KEY);
  } catch {
    /* storage unavailable */
  }
}

/** Hands a ready-made caption to the next composer that opens (Ember → composer). */
export function setComposerPrefill(prefill: ComposerPrefill): void {
  try {
    localStorage.setItem(PREFILL_KEY, JSON.stringify(prefill));
  } catch {
    /* storage unavailable */
  }
}

/** Reads AND clears the one-shot prefill. */
export function consumeComposerPrefill(): ComposerPrefill | null {
  try {
    const raw = localStorage.getItem(PREFILL_KEY);
    if (!raw) return null;
    localStorage.removeItem(PREFILL_KEY);
    const parsed = JSON.parse(raw) as ComposerPrefill;
    if (typeof parsed.caption !== "string" || !parsed.caption.trim()) return null;
    return parsed;
  } catch {
    return null;
  }
}
