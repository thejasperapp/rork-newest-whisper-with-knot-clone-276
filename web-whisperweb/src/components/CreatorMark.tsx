import { memo } from "react";

import { cn } from "@/lib/utils";

/**
 * The CREATOR mark — a cursive "C" wearing the Whisper brand gradient that
 * never sits still: the sweep glides through the glyph on a slow loop with a
 * soft bloom behind it (the `creator-mark-sweep` keyframes in index.css).
 * One mark for every creator-post door — the feed composer's creator menu,
 * the + selector, studio buttons. Mirrors `WhisperCreatorMark` on iOS.
 */
function CreatorMarkBase({ size = 22, className }: { size?: number; className?: string }) {
  return (
    <span
      aria-label="Creator posts"
      className={cn("relative inline-flex shrink-0 items-center justify-center", className)}
      style={{ width: size * 1.25, height: size * 1.25 }}
    >
      <span
        aria-hidden
        className="creator-mark-glyph absolute inset-0 flex items-center justify-center blur-[3px] opacity-60"
        style={{ fontSize: size * 1.35, color: "#FF7340" }}
      >
        C
      </span>
      <span
        aria-hidden
        className="creator-mark-glyph creator-mark-sweep relative flex items-center justify-center"
        style={{ fontSize: size * 1.35 }}
      >
        C
      </span>
    </span>
  );
}

export const CreatorMark = memo(CreatorMarkBase);
