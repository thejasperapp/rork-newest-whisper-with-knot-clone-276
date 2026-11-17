/**
 * Web port of the iOS `WhisperStorySticker` / `WhisperStoryMetadata`. These
 * interactive overlays (text, polls, sliders, ask-me questions, location
 * pills, @mentions, music chips, GIFs, photos) are stored as JSON in the
 * `whisper_stories.metadata` column. The JSON keys mirror Swift's Codable
 * property names 1:1 so a story authored on iOS renders identically on web
 * and vice-versa.
 */

export type StoryStickerKind =
  | "text"
  | "poll"
  | "slider"
  | "question"
  | "location"
  | "mention"
  | "music"
  | "gif"
  | "sticker"
  | "photo"
  | "hashtag"
  | "countdown"
  /** A shared wave — Instagram's "Add reel to your story" card; tap opens the wave. */
  | "wave"
  /** A shared grid POST — Instagram's "Add post to your story" card; tap opens the post. */
  | "post";

export interface StorySticker {
  id: string;
  kind: StoryStickerKind;
  /** Normalized centre (0…1) on the canvas. */
  x: number;
  y: number;
  scale: number;
  /** Rotation in radians (matches SwiftUI `.rotationEffect(.radians)`). */
  rotation: number;

  // Text / question
  text?: string | null;
  color?: string | null;
  background?: string | null;
  /** Text style index (0 plain, 1 pill, 2 outline, 3 glow, 4 box, 5 mono). */
  style?: number | null;

  // Poll
  pollOptions?: string[] | null;

  // Slider
  sliderEmoji?: string | null;

  // Music
  musicTitle?: string | null;
  musicArtist?: string | null;
  musicArtwork?: string | null;

  // Location / mention
  label?: string | null;
  latitude?: number | null;
  longitude?: number | null;

  // GIF / animated sticker / photo cover
  imageURL?: string | null;
  /** Optional shared-card geometry authored by newer iOS clients. */
  mediaAspectRatio?: number | null;
  cardWidthFraction?: number | null;
  mediaCount?: number | null;
  /** Photo sticker mask — rect (default) · circle · heart · star · squircle. */
  shape?: string | null;
  /** `wave` — the shared post id (lowercase uuid). */
  postID?: string | null;
  /** `wave` — the wave's video URL (muted loop inside the card). */
  videoURL?: string | null;

  // Q&A re-share
  answer?: string | null;
  responderUsername?: string | null;
}

/** Preserve new shared cards' photo ratio, with unchanged sizing for legacy stories. */
export function sharedPostCardSize(sticker: StorySticker, stageWidth: number): { width: number; height: number } {
  const aspect = sticker.mediaAspectRatio;
  const fraction = sticker.cardWidthFraction;
  if (typeof aspect !== "number" || !Number.isFinite(aspect) || aspect <= 0 ||
      typeof fraction !== "number" || !Number.isFinite(fraction) || !Number.isFinite(stageWidth) || stageWidth <= 0) {
    return { width: 250, height: 312 };
  }
  const width = stageWidth * Math.min(0.94, Math.max(0.3, fraction));
  const height = width / aspect;
  const factor = Math.min(1, (stageWidth * 16 / 9 * 0.72) / height);
  return { width: width * factor, height: height * factor };
}

export interface StoryMetadata {
  stickers: StorySticker[];
  referenceStageWidth?: number;
}

/** Decode the raw `metadata` column into a typed sticker list. */
export function decodeStoryMetadata(raw: string | null | undefined): StoryMetadata {
  if (!raw) return { stickers: [] };
  try {
    const parsed = JSON.parse(raw) as { stickers?: unknown; referenceStageWidth?: unknown };
    const list = Array.isArray(parsed.stickers) ? parsed.stickers : [];
    const stickers: StorySticker[] = list
      .filter((s): s is StorySticker => !!s && typeof s === "object")
      .map((s) => ({
        ...s,
        id: s.id ?? crypto.randomUUID(),
        x: typeof s.x === "number" ? s.x : 0.5,
        y: typeof s.y === "number" ? s.y : 0.5,
        scale: typeof s.scale === "number" ? s.scale : 1,
        rotation: typeof s.rotation === "number" ? s.rotation : 0,
      }));
    const width = parsed.referenceStageWidth;
    return { stickers, ...(typeof width === "number" && Number.isFinite(width) && width >= 100 && width <= 4096 ? { referenceStageWidth: width } : {}) };
  } catch {
    return { stickers: [] };
  }
}

/** Encode stickers for the `metadata` column. Returns null when empty. */
export function encodeStoryMetadata(stickers: StorySticker[], referenceStageWidth?: number): string | null {
  if (stickers.length === 0) return null;
  return JSON.stringify({ stickers, ...(referenceStageWidth && Number.isFinite(referenceStageWidth) && referenceStageWidth >= 100 && referenceStageWidth <= 4096 ? { referenceStageWidth } : {}) });
}

/** Sticker kinds that respond to a tap in the viewer. */
export function isTappableSticker(kind: StoryStickerKind): boolean {
  return (
    kind === "poll" ||
    kind === "slider" ||
    kind === "question" ||
    kind === "mention" ||
    kind === "location" ||
    kind === "wave" ||
    kind === "post"
  );
}

/** The Instagram photo-sticker mask cycle (same order as iOS). */
export const PHOTO_SHAPES = ["rect", "circle", "heart", "star", "squircle"] as const;
export type PhotoShape = (typeof PHOTO_SHAPES)[number];

export function nextPhotoShape(current: string | null | undefined): PhotoShape {
  const i = PHOTO_SHAPES.indexOf((current ?? "rect") as PhotoShape);
  return PHOTO_SHAPES[(Math.max(0, i) + 1) % PHOTO_SHAPES.length];
}

/**
 * CSS clip-path for a photo shape — traced to match the iOS Shape paths
 * (heart: two-lobe bezier; star: 5 points, inner ratio 0.5). Paths are in
 * a 160×160 box, the sticker's rendered size.
 */
export function photoShapeClipPath(shape: string | null | undefined): string | undefined {
  switch (shape) {
    case "circle":
      return "circle(50% at 50% 50%)";
    case "squircle":
      return "inset(0 round 35%)";
    case "star": {
      const pts: string[] = [];
      for (let i = 0; i < 10; i++) {
        const r = i % 2 === 0 ? 50 : 25;
        const a = (i * Math.PI) / 5 - Math.PI / 2;
        pts.push(`${(50 + r * Math.cos(a)).toFixed(2)}% ${(50 + r * Math.sin(a)).toFixed(2)}%`);
      }
      return `polygon(${pts.join(", ")})`;
    }
    case "heart":
      return "path('M 80 147.2 C 35.2 121.6 6.4 92.8 6.4 57.6 C 6.4 9.6 57.6 3.2 80 38.4 C 102.4 3.2 153.6 9.6 153.6 57.6 C 153.6 92.8 124.8 121.6 80 147.2 Z')";
    default:
      return undefined;
  }
}

/** A bundled Jasper sticker reference (`jasper-sticker://name`). */
export function jasperStickerName(raw: string): string | null {
  const prefix = "jasper-sticker://";
  if (!raw.startsWith(prefix)) return null;
  const name = raw.slice(prefix.length);
  return name || null;
}
