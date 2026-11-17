/**
 * Optional rich metadata attached to a post (music, location, tagged people,
 * poll). Stored the same way as the workout embed: a single prefix + one line
 * of compact JSON at the very start of the caption, with the user's visible
 * copy following on subsequent lines. This keeps everything in the existing
 * `caption` column — no schema change required.
 */
const META_PREFIX = "::whisper-postmeta-v1::";

export interface PostMusic {
  id: string;
  title: string;
  artist: string;
  artworkURL: string | null;
  previewURL: string | null;
}

export interface PostPoll {
  question: string | null;
  options: string[];
}

export interface PostMeta {
  music?: PostMusic | null;
  location?: string | null;
  tagged?: string[];
  poll?: PostPoll | null;
  /** Instagram-style "hide like and view counts" flag for grid posts. */
  hideCounts?: boolean;
  /** Accessibility alt text describing the post's media for screen readers. */
  altText?: string;
  /** Instagram-style "turn off commenting" — hides every comment affordance. */
  commentsOff?: boolean;
  /**
   * A wave's COVER frame (the one the creator picked in the composer) as a
   * public image URL — every grid/mosaic/shelf tile shows this instead of
   * the video's first frame. Mirrors iOS `WhisperPostMeta.cover`.
   */
  cover?: string | null;
  /**
   * Instagram's "Also share to feed" for a wave — when true the wave ALSO
   * rides the ranked feed as a reel-in-feed card (still a wave everywhere
   * else: the player, the profile Waves grid, Discover). Mirrors iOS
   * `WhisperPostMeta.feed`.
   */
  feed?: boolean;
}

/** Whether a wave opted into the feed ("Also share to feed"). */
export function waveSharedToFeed(caption: string | null | undefined): boolean {
  return parsePostMeta(caption)?.feed === true;
}

/** The cover image URL for a wave, when its caption carries one. */
export function waveCoverUrl(caption: string | null | undefined): string | undefined {
  const cover = parsePostMeta(caption)?.cover;
  return cover && cover.trim() ? cover : undefined;
}

/** True when the meta object actually carries something worth encoding. */
export function hasMeta(meta: PostMeta): boolean {
  return (
    !!meta.music ||
    !!meta.location ||
    (meta.tagged?.length ?? 0) > 0 ||
    (meta.poll?.options.filter((o) => o.trim()).length ?? 0) >= 2 ||
    meta.hideCounts === true ||
    !!meta.altText ||
    meta.commentsOff === true ||
    !!meta.cover ||
    meta.feed === true
  );
}

/** Encode meta + caption into a single caption string for storage. */
export function encodePostMeta(meta: PostMeta, caption: string): string {
  const clean: PostMeta = {};
  if (meta.music) clean.music = meta.music;
  if (meta.location) clean.location = meta.location;
  if (meta.tagged && meta.tagged.length > 0) clean.tagged = meta.tagged;
  if (meta.poll && meta.poll.options.filter((o) => o.trim()).length >= 2) {
    clean.poll = {
      question: meta.poll.question?.trim() || null,
      options: meta.poll.options.map((o) => o.trim()).filter(Boolean),
    };
  }
  if (meta.hideCounts === true) clean.hideCounts = true;
  if (meta.altText?.trim()) clean.altText = meta.altText.trim();
  if (meta.commentsOff === true) clean.commentsOff = true;
  if (meta.cover?.trim()) clean.cover = meta.cover.trim();
  if (meta.feed === true) clean.feed = true;
  if (!hasMeta(clean)) return caption;
  return `${META_PREFIX}${JSON.stringify(clean)}\n${caption}`;
}

/** Decode the meta payload from a caption, or null if there isn't one. */
export function parsePostMeta(caption: string | null | undefined): PostMeta | null {
  if (!caption || !caption.startsWith(META_PREFIX)) return null;
  const body = caption.slice(META_PREFIX.length);
  const line = body.split("\n", 1)[0] ?? "";
  try {
    const obj = JSON.parse(line) as PostMeta;
    return obj;
  } catch {
    return null;
  }
}

/** The visible caption text with the meta embed line removed. */
export function stripPostMeta(caption: string | null | undefined): string {
  if (!caption) return "";
  if (!caption.startsWith(META_PREFIX)) return caption;
  const body = caption.slice(META_PREFIX.length);
  const nl = body.indexOf("\n");
  return nl >= 0 ? body.slice(nl + 1).trim() : "";
}
