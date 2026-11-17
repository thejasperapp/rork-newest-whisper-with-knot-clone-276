import { memo, useEffect, useState } from "react";

import { cn } from "@/lib/utils";

interface TraceLogoProps {
  /** Rendered width in px. Height scales with the wordmark aspect (~0.62). */
  size?: number;
  className?: string;
  /**
   * Trace the OUTLINE of the W instead of the filled glyph — the refresh
   * indicator's grammar (just the W's edge in the open space).
   */
  outline?: boolean;
  /**
   * When set (0…1), the reveal is driven by this value instead of the
   * looping animation — the pull-to-refresh distance draws the W in.
   */
  progress?: number;
}

/**
 * The brand W as a pure outline, built once from the filled PNG: the glyph is
 * stamped around a small radius and the original knocked back out, leaving
 * the edge band — the REAL looped-script W's outline, not a stand-in. Cached
 * as a data URL for the session; resolves to the filled mark while loading.
 */
let outlinePromise: Promise<string | null> | null = null;
let outlineUrl: string | null = null;

function buildOutline(): Promise<string | null> {
  if (outlinePromise) return outlinePromise;
  outlinePromise = new Promise<string | null>((resolve) => {
    const img = new Image();
    img.onload = () => {
      try {
        const targetWidth = 480;
        const scale = targetWidth / Math.max(1, img.naturalWidth);
        const w = targetWidth;
        const h = Math.round(img.naturalHeight * scale);
        const canvas = document.createElement("canvas");
        canvas.width = w;
        canvas.height = h;
        const ctx = canvas.getContext("2d");
        if (!ctx) {
          resolve(null);
          return;
        }
        const band = 7;
        for (let step = 0; step < 16; step++) {
          const angle = (step / 16) * Math.PI * 2;
          ctx.drawImage(img, Math.cos(angle) * band, Math.sin(angle) * band, w, h);
        }
        ctx.globalCompositeOperation = "destination-out";
        ctx.drawImage(img, 0, 0, w, h);
        ctx.globalCompositeOperation = "source-over";
        outlineUrl = canvas.toDataURL("image/png");
        resolve(outlineUrl);
      } catch {
        resolve(null);
      }
    };
    img.onerror = () => resolve(null);
    img.src = "/whisper-logo.png";
  });
  return outlinePromise;
}

/**
 * Brand-mark trace animation — a pixel-identical match to the iOS
 * `WhisperTraceLogo`: a soft ghost copy of the wordmark sits behind a
 * foreground copy that is revealed left-to-right via an animated mask, so it
 * reads as a pen tracing the looped "W". Loops while mounted unless a
 * `progress` drives the reveal.
 */
function TraceLogoBase({ size = 220, className, outline = false, progress }: TraceLogoProps) {
  const height = size * 0.62;
  const [src, setSrc] = useState<string>(outline && outlineUrl ? outlineUrl : "/whisper-logo.png");

  useEffect(() => {
    if (!outline) {
      setSrc("/whisper-logo.png");
      return;
    }
    let alive = true;
    void buildOutline().then((url) => {
      if (alive && url) setSrc(url);
    });
    return () => {
      alive = false;
    };
  }, [outline]);

  const manual = typeof progress === "number";
  const clamped = manual ? Math.min(1, Math.max(0, progress)) : 1;

  return (
    <div
      className={cn("relative", className)}
      style={{ width: size, height }}
      aria-hidden
    >
      <img
        src={src}
        alt=""
        draggable={false}
        className={cn(
          "whisper-logo absolute inset-0 h-full w-full select-none object-contain",
          outline ? "opacity-[0.16]" : "opacity-[0.1]"
        )}
      />
      <img
        src={src}
        alt=""
        draggable={false}
        className={cn(
          "whisper-logo absolute inset-0 h-full w-full select-none object-contain",
          !manual && "animate-trace"
        )}
        style={
          manual
            ? { clipPath: `inset(0 ${Math.round((1 - clamped) * 100)}% 0 0)` }
            : undefined
        }
      />
    </div>
  );
}

export const TraceLogo = memo(TraceLogoBase);
