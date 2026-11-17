import { useEffect, useMemo, useRef, useState } from "react";
import { WHISPER_BRAND_GRADIENT } from "@/lib/brand";
import { cn } from "@/lib/utils";

interface GradientTypeInProps {
  text: string;
  /** Characters per second while typing. */
  speed?: number;
  /** Whether the line settles to plain ink once typed (default true). */
  settles?: boolean;
  className?: string;
  /** Tag to render — h1/h2/p. */
  as?: "h1" | "h2" | "h3" | "p";
}

/**
 * The Whisper type-in entrance (mirrors iOS `WhisperGradientTypeInText`):
 * the sentence types in wearing THE brand gradient (mint → emerald → indigo)
 * with a soft three-character leading edge, then the whole line settles to
 * the surface's ink. Layout is stable from the first frame — the unrevealed
 * remainder is laid out transparent so wrapping never shifts.
 */
export function GradientTypeIn({
  text,
  speed = 30,
  settles = true,
  className,
  as: Tag = "h2",
}: GradientTypeInProps) {
  const [revealed, setRevealed] = useState<number>(0);
  const [settled, setSettled] = useState<boolean>(false);
  const startRef = useRef<number | null>(null);
  const chars = useMemo(() => Array.from(text), [text]);

  useEffect(() => {
    setRevealed(0);
    setSettled(false);
    startRef.current = null;
    let raf = 0;
    let settleTimer: ReturnType<typeof setTimeout> | null = null;
    const tick = (now: number): void => {
      if (startRef.current === null) startRef.current = now;
      const elapsed = Math.max(0, (now - startRef.current) / 1000 - 0.25);
      const count = Math.min(chars.length, Math.floor(elapsed * speed));
      setRevealed(count);
      if (count < chars.length) {
        raf = requestAnimationFrame(tick);
      } else if (settles) {
        settleTimer = setTimeout(() => setSettled(true), 650);
      }
    };
    raf = requestAnimationFrame(tick);
    return () => {
      cancelAnimationFrame(raf);
      if (settleTimer) clearTimeout(settleTimer);
    };
  }, [chars, speed, settles]);

  const head = chars.slice(0, revealed).join("");
  const edge1 = chars[revealed] ?? "";
  const edge2 = chars[revealed + 1] ?? "";
  const edge3 = chars[revealed + 2] ?? "";
  const rest = chars.slice(Math.min(chars.length, revealed + 3)).join("");

  const gradientStyle: React.CSSProperties = {
    backgroundImage: WHISPER_BRAND_GRADIENT,
    WebkitBackgroundClip: "text",
    backgroundClip: "text",
    color: "transparent",
  };

  return (
    <Tag className={cn("relative", className)} aria-label={text}>
      {/* Settled ink line — fades in over the gradient line. */}
      <span
        aria-hidden
        className="transition-opacity duration-[900ms] ease-in-out"
        style={{ opacity: settled ? 1 : 0 }}
      >
        {text}
      </span>
      {!settled && (
        <span aria-hidden className="absolute inset-0">
          <span style={gradientStyle}>{head}</span>
          <span style={{ ...gradientStyle, opacity: 0.55 }}>{edge1}</span>
          <span style={{ ...gradientStyle, opacity: 0.28 }}>{edge2}</span>
          <span style={{ ...gradientStyle, opacity: 0.12 }}>{edge3}</span>
          <span style={{ color: "transparent" }}>{rest}</span>
        </span>
      )}
    </Tag>
  );
}
