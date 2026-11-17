import { memo } from "react";

import { cn } from "@/lib/utils";

interface WhisperLogoProps {
  /** Rendered height in px. Width scales with the wordmark aspect (~1.6:1). */
  size?: number;
  className?: string;
  /**
   * "icon" renders the classic looped-script "W" mark.
   * "wordmark" renders the full-length looped-script "whisper" text the
   * user provided — used in the main app header and marketing nav.
   * "script" renders the wordmark as LIVE TYPE in a bolder connected script
   * (Damion) — crisp at every size, ink in light / white in dark with no
   * image inversion, and weighted to sit beside Inter labels (the workspace
   * portals' brand block) without reading as a hairline afterthought.
   */
  variant?: "icon" | "wordmark" | "script";
}

/**
 * Whisper's looped-script brand assets. Black artwork on a transparent
 * background; the `whisper-logo` utility inverts it to white whenever the
 * dark appearance is active so it always reads as ink, matching iOS.
 */
function WhisperLogoBase({ size = 30, className, variant = "icon" }: WhisperLogoProps) {
  if (variant === "script") {
    return (
      <span
        aria-label="Whisper"
        role="img"
        className={cn("whisper-script-wordmark select-none text-foreground", className)}
        style={{ fontSize: size * 1.32, lineHeight: 1, height: size }}
      >
        Whisper
      </span>
    );
  }
  const isWordmark = variant === "wordmark";
  return (
    <img
      src={isWordmark ? "/whisper-wordmark.png" : "/whisper-logo.png"}
      alt="Whisper"
      width={isWordmark ? size * 4 : size * 1.6}
      height={size}
      className={cn("whisper-logo select-none object-contain", className)}
      style={{ height: size, width: "auto" }}
      draggable={false}
    />
  );
}

export const WhisperLogo = memo(WhisperLogoBase);
