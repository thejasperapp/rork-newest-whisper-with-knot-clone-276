import { memo } from "react";
import { MapPin } from "lucide-react";

import { cn } from "@/lib/utils";
import { EqualizerBars, MarqueeText } from "@/components/MusicMarquee";
import type { ThoughtStyle } from "@/lib/thoughts";

/**
 * IG-Notes thought bubble — the EXACT Kit 4.0 cloud, traced from the Figma
 * file's Union vector (82×48): a rounded body (radius 17.7 at 41pt tall)
 * whose bottom edge carries an INTEGRATED tail bump (r≈3.93 centred 16pt
 * from the left) plus one detached 4pt dot at (21, 46). Flat white fill,
 * no stroke, soft 10%-black shadow. Supports the plain / location / music
 * treatments plus a custom colour + emoji.
 */

function parseHex(raw: string): string | null {
  const s = raw.trim().replace(/^#/, "");
  if (s.length !== 6 && s.length !== 8) return null;
  if (!/^[0-9a-fA-F]+$/.test(s)) return null;
  return `#${s}`;
}

function luminance(hex: string): number {
  const s = hex.replace(/^#/, "").slice(0, 6);
  const v = parseInt(s, 16);
  const r = ((v >> 16) & 0xff) / 255;
  const g = ((v >> 8) & 0xff) / 255;
  const b = (v & 0xff) / 255;
  return 0.299 * r + 0.587 * g + 0.114 * b;
}

// Canvas-based single-line fit check — same 72pt content-width rule as the
// iOS bubble, so short notes collapse to the compact pill on both platforms.
let measureCanvas: HTMLCanvasElement | null = null;
function plainFitsOneLine(text: string, scale: number): boolean {
  if (text.includes("\n")) return false;
  if (typeof document === "undefined") return text.length <= 12;
  measureCanvas ??= document.createElement("canvas");
  const ctx = measureCanvas.getContext("2d");
  if (!ctx) return text.length <= 12;
  ctx.font = `600 ${13 * scale}px -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif`;
  return ctx.measureText(text).width <= 72 * scale;
}

// Kit 4.0 big-emoji note — a note that's JUST an emoji (1–3 pictographs)
// renders it large inside the bubble instead of body-text sized.
function isEmojiOnlyText(raw: string): boolean {
  const s = raw.trim();
  if (!s || Array.from(s).length > 6) return false;
  if (!/\p{Extended_Pictographic}/u.test(s)) return false;
  const stripped = s.replace(
    /[\p{Extended_Pictographic}\u{1F3FB}-\u{1F3FF}\u{FE0F}\u{200D}\u{20E3}\s]/gu,
    ""
  );
  return stripped.length === 0;
}

interface ThoughtBubbleProps {
  text: string;
  style?: ThoughtStyle;
  accent?: string;
  emoji?: string;
  colorHex?: string;
  /** Visual scale — 1.0 ≈ profile size. */
  scale?: number;
  className?: string;
}

function ThoughtBubbleBase({
  text,
  style = "plain",
  accent = "",
  emoji = "",
  colorHex = "",
  scale = 1,
  className,
}: ThoughtBubbleProps) {
  const custom = parseHex(colorHex);
  const isDarkCustom = custom ? luminance(custom) < 0.62 : false;

  let bg: string;
  let fg: string;
  let shadow: string;
  if (custom) {
    bg = `linear-gradient(135deg, ${custom}, ${custom}d1)`;
    fg = isDarkCustom ? "#ffffff" : "#1f1f1f";
    shadow = `${custom}66`;
  } else if (style === "location") {
    bg = "linear-gradient(135deg, #ff3d8c, #ff73b8)";
    fg = "#ffffff";
    shadow = "rgba(255,61,140,0.4)";
  } else if (style === "music") {
    // Kit 4.0: the music note is the SAME white cloud — ink song title,
    // gray artist — not a purple gradient.
    bg = "#ffffff";
    fg = "#0C1014";
    shadow = "rgba(0,0,0,0.14)";
  } else {
    // Kit-exact: flat white, no gradient, no stroke — the shadow does the work.
    bg = "#ffffff";
    fg = "#0C1014";
    shadow = "rgba(0,0,0,0.14)";
  }

  const fontSize = 13 * scale;
  const dotBg = bg;
  // Smart-expandable shape: a short note ("gym?") hugs the word in a compact
  // rounded pill; anything longer expands to the classic 2-line note, whose
  // footprint is the hard MAX — the bubble never grows past the base shape.
  const emojiOnly = style === "plain" && isEmojiOnlyText(text);
  const isCompact =
    style === "plain" && !emojiOnly && plainFitsOneLine(text, scale);
  const bubbleHeight =
    (style === "music" ? 50 : emojiOnly ? 46 : isCompact ? 34 : 48) * scale;
  // Kit proportions: every tail + corner metric derives from the Figma
  // Union's 41pt-tall body so the cloud keeps its exact shape at any size.
  const k = bubbleHeight / 41;
  const cornerRadius = isCompact || emojiOnly ? bubbleHeight / 2 : 17.7 * k;

  return (
    <div
      className={cn("relative inline-flex", className)}
      style={{
        // Kit shadow: one soft 10%-ish black pass — no heavy tinted bloom.
        filter: `drop-shadow(0 ${3 * k}px ${5 * k}px ${shadow}) drop-shadow(0 ${0.5 * k}px ${1 * k}px rgba(0,0,0,0.08))`,
      }}
    >
      {/* Kit-exact tail — an integrated bump ON the bottom edge (its top half
         hides behind the body so the outline reads as one union) plus one
         detached dot below-right, exactly as traced from the Figma vector. */}
      <span
        className="absolute z-0 rounded-full"
        style={{
          width: 7.86 * k,
          height: 7.86 * k,
          left: 12.07 * k,
          bottom: -3.93 * k,
          background: dotBg,
        }}
      />
      <span
        className="absolute z-0 rounded-full"
        style={{
          width: 4 * k,
          height: 4 * k,
          left: 19 * k,
          bottom: -7 * k,
          background: dotBg,
        }}
      />

      <div
        className="relative z-10 flex items-center justify-center"
        style={{
          background: bg,
          color: fg,
          borderRadius: cornerRadius,
          paddingInline: 12 * scale,
          height: bubbleHeight,
          minWidth: (isCompact ? 40 : 52) * scale,
          maxWidth: (style === "plain" ? 108 : style === "music" ? 168 : 150) * scale,
        }}
      >
        {style === "plain" ? (
          <span
            className={cn(
              "text-center font-semibold leading-tight",
              isCompact || emojiOnly ? "whitespace-nowrap" : "line-clamp-2",
            )}
            style={{
              fontSize: emojiOnly ? 26 * scale : fontSize,
              lineHeight: emojiOnly ? 1.1 : undefined,
            }}
          >
            {text}
          </span>
        ) : style === "music" ? (
          <span className="flex min-w-0 flex-col text-left leading-tight">
            <span className="flex items-center" style={{ gap: 6 * scale }}>
              <EqualizerBars color={fg} bars={3} size={fontSize * 0.85} />
              <MarqueeText
                text={text || "Now playing"}
                speed={26}
                className="font-extrabold"
                style={{ fontSize: fontSize - 1, maxWidth: 116 * scale }}
              />
            </span>
            {accent && (
              <MarqueeText
                text={accent}
                speed={18}
                className="font-medium"
                style={{
                  fontSize: fontSize - 4,
                  maxWidth: 116 * scale,
                  marginLeft: fontSize * 0.65 + 6 * scale,
                  // Kit: artist line is secondary gray, 400 weight.
                  color: custom ? undefined : "#6F7680",
                }}
              />
            )}
          </span>
        ) : (
          <span className="flex items-center gap-1.5">
            <MapPin
              className="shrink-0"
              style={{ width: fontSize, height: fontSize }}
              strokeWidth={2.6}
            />
            <span className="flex min-w-0 flex-col text-left leading-tight">
              <span className="truncate font-extrabold" style={{ fontSize }}>
                {text || "Here now"}
              </span>
              {accent && (
                <span
                  className="truncate font-semibold opacity-85"
                  style={{ fontSize: fontSize - 3 }}
                >
                  {accent}
                </span>
              )}
            </span>
          </span>
        )}
      </div>

      {emoji && (
        <span
          className="absolute z-20"
          style={{
            top: -12 * scale,
            left: -10 * scale,
            fontSize: 22 * scale,
            transform: "rotate(14deg)",
            filter: "drop-shadow(0 1px 2px rgba(0,0,0,0.25))",
          }}
        >
          {emoji}
        </span>
      )}
    </div>
  );
}

export const ThoughtBubble = memo(ThoughtBubbleBase);
