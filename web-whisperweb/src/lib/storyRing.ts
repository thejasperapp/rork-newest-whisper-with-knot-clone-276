/**
 * The Whisper story ring — the green gradient identity for unseen stories.
 * A pure mint→emerald→forest sweep (no indigo/ember), wrapped back to the
 * first stop so the conic gradient has no seam. Matches `WhisperIGRing`
 * on iOS 1:1.
 */
export const WHISPER_STORY_RING =
  "conic-gradient(from 210deg at 50% 50%, #9BE8C4, #34D399, #0E9F76, #047857, #2BD48A, #9BE8C4)";

/** Tailwind arbitrary-value class carrying the same gradient (post headers). */
export const WHISPER_STORY_RING_TW =
  "bg-[conic-gradient(from_210deg,#9BE8C4,#34D399,#0E9F76,#047857,#2BD48A,#9BE8C4)]";

/** Dimmed ring once every story is seen. */
export const SEEN_STORY_RING = "hsl(var(--muted-foreground) / 0.4)";
