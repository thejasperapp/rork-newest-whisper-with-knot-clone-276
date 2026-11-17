import { memo, useEffect, useRef, useState } from "react";

/**
 * Continuously-scrolling single-line text — a web port of the iOS
 * `WhisperMarqueeText`. When the text overflows its container it duplicates
 * the string and slides left forever; otherwise it renders statically.
 */
function MarqueeTextBase({
  text,
  className,
  speed = 28,
  style,
}: {
  text: string;
  className?: string;
  /** Pixels per second the text travels when scrolling. */
  speed?: number;
  style?: React.CSSProperties;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const measureRef = useRef<HTMLSpanElement>(null);
  const [scroll, setScroll] = useState<boolean>(false);
  const [duration, setDuration] = useState<number>(8);

  useEffect(() => {
    const container = containerRef.current;
    const measure = measureRef.current;
    if (!container || !measure) return;
    const textWidth = measure.scrollWidth;
    const containerWidth = container.clientWidth;
    const needs = textWidth > containerWidth + 1;
    setScroll(needs);
    if (needs) {
      const gap = 28;
      setDuration(Math.max(4, (textWidth + gap) / Math.max(speed, 1)));
    }
  }, [text, speed]);

  return (
    <div
      ref={containerRef}
      className={className}
      style={{ overflow: "hidden", position: "relative", ...style }}
    >
      {scroll ? (
        <div
          className="marquee-track"
          style={{ ["--marquee-duration" as string]: `${duration}s` }}
        >
          <span style={{ paddingRight: 28 }}>{text}</span>
          <span style={{ paddingRight: 28 }}>{text}</span>
        </div>
      ) : (
        <span className="block truncate">{text}</span>
      )}
      {/* Hidden measuring copy so we always know the natural text width. */}
      <span
        ref={measureRef}
        aria-hidden
        style={{
          position: "absolute",
          top: 0,
          left: 0,
          visibility: "hidden",
          whiteSpace: "nowrap",
          pointerEvents: "none",
        }}
      >
        {text}
      </span>
    </div>
  );
}

export const MarqueeText = memo(MarqueeTextBase);

/** Animated audio equalizer bars (mirrors iOS `WhisperEqualizerBars`). */
function EqualizerBarsBase({
  color = "currentColor",
  bars = 3,
  size = 13,
}: {
  color?: string;
  bars?: number;
  size?: number;
}) {
  const delays = [0, 0.18, 0.36, 0.1, 0.28];
  const durations = [0.78, 0.62, 0.9, 0.7, 0.82];
  return (
    <span
      className="inline-flex items-center"
      style={{ height: size, gap: size * 0.16 }}
      aria-hidden
    >
      {Array.from({ length: bars }).map((_, i) => (
        <span
          key={i}
          className="eq-bar"
          style={{
            width: size * 0.22,
            height: size * 0.95,
            background: color,
            animationDelay: `${delays[i % delays.length]}s`,
            animationDuration: `${durations[i % durations.length]}s`,
          }}
        />
      ))}
    </span>
  );
}

export const EqualizerBars = memo(EqualizerBarsBase);
