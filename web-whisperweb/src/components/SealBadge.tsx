import { memo, useId } from "react";

/**
 * Scalloped "seal" silhouette approximating Apple's `seal.fill` SF Symbol, on a
 * 100×100 viewBox. Generated once with gentle quadratic scallops so every
 * Whisper trust badge shares one cohesive silhouette — exactly like the iOS
 * badge set where only the colour and inner glyph change.
 */
function buildSealPath(lobes = 12, rOuter = 49, rValley = 40): string {
  const cx = 50;
  const cy = 50;
  const pts: { x: number; y: number }[] = [];
  for (let i = 0; i < lobes; i++) {
    const a = (i / lobes) * Math.PI * 2 - Math.PI / 2;
    pts.push({ x: cx + rOuter * Math.cos(a), y: cy + rOuter * Math.sin(a) });
  }
  let d = `M ${pts[0]!.x.toFixed(2)} ${pts[0]!.y.toFixed(2)}`;
  for (let i = 1; i <= lobes; i++) {
    const cur = pts[i % lobes]!;
    const va = ((i - 0.5) / lobes) * Math.PI * 2 - Math.PI / 2;
    const vx = cx + rValley * Math.cos(va);
    const vy = cy + rValley * Math.sin(va);
    d += ` Q ${vx.toFixed(2)} ${vy.toFixed(2)} ${cur.x.toFixed(2)} ${cur.y.toFixed(2)}`;
  }
  return `${d} Z`;
}

const SEAL_PATH = buildSealPath();

interface SealBadgeProps {
  size: number;
  /** Gradient stops (top → bottom). Ignored when `solid` is set. */
  colors?: string[];
  /** Solid fill colour, overrides the gradient (used by the coach seal). */
  solid?: string;
  shadowColor?: string;
  title?: string;
  /** Centered white glyph (icon or short text). */
  children?: React.ReactNode;
}

function SealBadgeBase({
  size,
  colors,
  solid,
  shadowColor,
  title,
  children,
}: SealBadgeProps) {
  const gid = useId();
  const fill = solid ?? `url(#${gid})`;
  return (
    <span
      title={title}
      aria-label={title}
      className="relative inline-flex shrink-0 items-center justify-center"
      style={{ width: size, height: size }}
    >
      <svg
        viewBox="0 0 100 100"
        className="absolute inset-0 h-full w-full"
        style={
          shadowColor
            ? { filter: `drop-shadow(0 1px 1.5px ${shadowColor}66)` }
            : undefined
        }
      >
        {!solid && colors && (
          <defs>
            <linearGradient id={gid} x1="0" y1="0" x2="0" y2="1">
              {colors.map((c, i) => (
                <stop
                  key={c + i}
                  offset={colors.length === 1 ? 0 : i / (colors.length - 1)}
                  stopColor={c}
                />
              ))}
            </linearGradient>
          </defs>
        )}
        <path d={SEAL_PATH} fill={fill} />
      </svg>
      <span
        className="relative z-10 flex items-center justify-center font-black leading-none text-white"
        style={{ fontSize: size * 0.42 }}
      >
        {children}
      </span>
    </span>
  );
}

export const SealBadge = memo(SealBadgeBase);
