import type { WhisperPost } from "@/lib/types";
import { stripPostMeta } from "@/lib/postMeta";
import { stripWorkoutEmbed } from "@/lib/workout";

/**
 * Produce the human-readable caption for a post, with every embed marker
 * stripped (post-meta header, workout payload, etc.). This guarantees a shared
 * post preview never leaks raw `::whisper-…::` JSON — including workout posts,
 * whose caption begins with the workout embed line.
 */
export function cleanPostCaption(caption: string | null | undefined): string {
  let text = stripPostMeta(caption);
  text = stripWorkoutEmbed(text);
  return text.trim();
}

/**
 * Web port of the iOS `WhisperSharedPostEmbed`. Encodes a post into a DM body
 * so the recipient sees a rich preview card (and we can deep-link back to the
 * author). Wire-compatible with the iOS `::whisper-sharedpost-v1::` format.
 */
const PREFIX = "::whisper-sharedpost-v1::";

export interface SharedPostPayload {
  postID: string;
  username: string;
  caption: string;
  kindRaw: string;
  symbol: string;
  accentHex: string | null;
  mediaURL: string | null;
  isVideo: boolean;
  likes: number;
  comments: number;
  /**
   * True when the shared post is a WAVE — the receiver opens it in the
   * full-screen Waves player instead of a post surface. Optional so older
   * embeds keep decoding (same field iOS writes).
   */
  isReel?: boolean;
}

export function encodeSharedPost(p: SharedPostPayload): string {
  return PREFIX + JSON.stringify(p);
}

export function decodeSharedPost(
  body: string | null | undefined
): SharedPostPayload | null {
  const t = body ?? "";
  if (!t.startsWith(PREFIX)) return null;
  try {
    const json = t.slice(PREFIX.length);
    const p = JSON.parse(json) as SharedPostPayload;
    if (!p.postID) return null;
    return p;
  } catch {
    return null;
  }
}

/**
 * Extracts a shared/quoted-post embed from anywhere within a caption (the quote
 * line is appended after any post-meta line). Returns the decoded payload plus
 * the caption with the embed line removed, so the visible text stays clean.
 */
export function extractSharedPost(caption: string | null | undefined): {
  payload: SharedPostPayload | null;
  rest: string;
} {
  const text = caption ?? "";
  if (!text.includes(PREFIX)) return { payload: null, rest: text };
  const lines = text.split("\n");
  const kept: string[] = [];
  let payload: SharedPostPayload | null = null;
  for (const line of lines) {
    const idx = line.indexOf(PREFIX);
    if (idx >= 0 && !payload) {
      const decoded = decodeSharedPost(line.slice(idx));
      if (decoded) {
        payload = decoded;
        const before = line.slice(0, idx).trim();
        if (before) kept.push(before);
        continue;
      }
    }
    kept.push(line);
  }
  return { payload, rest: kept.join("\n").trim() };
}

/** Build a share payload from a feed post + its author username. */
export function payloadFromPost(
  post: WhisperPost,
  username: string
): SharedPostPayload {
  const media = post.media_urls ?? [];
  return {
    postID: post.id,
    username,
    caption: cleanPostCaption(post.caption).slice(0, 280),
    kindRaw: post.kind ?? "photo",
    symbol: post.symbol ?? "sparkles",
    accentHex: post.accent_hex,
    mediaURL: media[0] ?? null,
    isVideo: post.is_reel ?? false,
    likes: post.likes_count ?? 0,
    comments: post.comments_count ?? 0,
    isReel: post.is_reel ?? false,
  };
}
