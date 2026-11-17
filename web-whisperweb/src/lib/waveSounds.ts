import { parsePostMeta, type PostMusic } from "@/lib/postMeta";
import type { WhisperPost } from "@/lib/types";

/**
 * The Sounds system — TikTok / Instagram Reels grammar: EVERY wave carries a
 * sound. Either a catalog track (the preview the creator picked, stored as
 * `meta.music`) or the wave's OWN audio — an "original sound" anyone can
 * reuse. Reuse rides the same `meta.music` wire as tracks with the id
 * `orig:<postID>`, so a wave made with someone's original sound attributes
 * back to them on every platform. Mirrors iOS `WhisperWaveSound` 1:1.
 */
export const ORIGINAL_SOUND_PREFIX = "orig:";

const VIDEO_RE = /\.(mp4|mov|webm|m4v)(\?|$)/i;

function isVideoUrl(u: string): boolean {
  return VIDEO_RE.test(u);
}

/** A wave's own audio as a reusable sound. */
export function originalSound(post: WhisperPost, username: string): PostMusic {
  const media = post.media_urls ?? [];
  const video = media.find(isVideoUrl) ?? null;
  const still = media.find((u) => !isVideoUrl(u)) ?? null;
  return {
    id: `${ORIGINAL_SOUND_PREFIX}${post.id.toLowerCase()}`,
    title: "Original sound",
    artist: username,
    artworkURL: still,
    previewURL: video,
  };
}

/** The sound a wave wears: its picked track, else its own original sound. */
export function soundForPost(post: WhisperPost, username: string): PostMusic {
  const music = parsePostMeta(post.caption)?.music;
  if (music && music.title) {
    return {
      id: music.id ?? `track:${music.title.toLowerCase()}-${music.artist.toLowerCase()}`,
      title: music.title,
      artist: music.artist,
      artworkURL: music.artworkURL ?? null,
      previewURL: music.previewURL ?? null,
    };
  }
  return originalSound(post, username);
}

export function isOriginalSound(m: PostMusic): boolean {
  return m.id.startsWith(ORIGINAL_SOUND_PREFIX);
}

/** The source wave id for an original sound. */
export function originalSoundPostId(m: PostMusic): string | null {
  return isOriginalSound(m) ? m.id.slice(ORIGINAL_SOUND_PREFIX.length) : null;
}

/** The attribution line: "Original sound · username" or "Title · Artist". */
export function soundLabel(m: PostMusic): string {
  return isOriginalSound(m) ? `Original sound · ${m.artist}` : `${m.title} · ${m.artist}`;
}

/** Every wave in `pool` wearing this sound, pool order kept. */
export function wavesUsingSound(
  sound: PostMusic,
  pool: WhisperPost[],
  usernameFor: (p: WhisperPost) => string
): WhisperPost[] {
  const seen = new Set<string>();
  const out: WhisperPost[] = [];
  for (const p of pool) {
    if (seen.has(p.id)) continue;
    if (soundForPost(p, usernameFor(p)).id === sound.id) {
      seen.add(p.id);
      out.push(p);
    }
  }
  return out;
}

/** Sounds ranked by how many waves in the pool wear them. */
export function trendingSounds(
  pool: WhisperPost[],
  usernameFor: (p: WhisperPost) => string,
  limit = 12
): { sound: PostMusic; count: number }[] {
  const counts = new Map<string, { sound: PostMusic; count: number }>();
  for (const p of pool) {
    const s = soundForPost(p, usernameFor(p));
    const existing = counts.get(s.id);
    if (existing) existing.count += 1;
    else counts.set(s.id, { sound: s, count: 1 });
  }
  return [...counts.values()].sort((a, b) => b.count - a.count).slice(0, limit);
}

// ---------------------------------------------------------------------------
// Saved sounds — TikTok's "Add to Favorites", kept on-device, newest first.

const SAVED_KEY = "whisper.savedSounds.v1";

export function loadSavedSounds(): PostMusic[] {
  try {
    const raw = localStorage.getItem(SAVED_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as unknown;
    return Array.isArray(parsed) ? (parsed as PostMusic[]) : [];
  } catch {
    return [];
  }
}

export function isSoundSaved(m: PostMusic): boolean {
  return loadSavedSounds().some((s) => s.id === m.id);
}

/** Toggle a sound in the favorites list; returns the new saved state. */
export function toggleSavedSound(m: PostMusic): boolean {
  const current = loadSavedSounds();
  const idx = current.findIndex((s) => s.id === m.id);
  let next: PostMusic[];
  let saved: boolean;
  if (idx >= 0) {
    next = current.filter((_, i) => i !== idx);
    saved = false;
  } else {
    next = [m, ...current].slice(0, 60);
    saved = true;
  }
  try {
    localStorage.setItem(SAVED_KEY, JSON.stringify(next));
  } catch {
    // Storage full or blocked — the toggle still applies for this session.
  }
  return saved;
}
