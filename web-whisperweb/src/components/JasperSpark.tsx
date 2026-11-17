import { useId } from "react";

import { cn } from "@/lib/utils";

/**
 * Jasper's presence mark in chat surfaces — a small four-point spark wearing
 * the brand gradient (rose → live orange → amber), breathing gently. This is
 * the iOS round-85 grammar: no mascot, no candle, no app icon — the spark
 * leads the /jasper pill, the private-answer card, and shared Jasper cards.
 */
export function JasperSpark({
  size = 16,
  breathing = true,
  className,
}: {
  size?: number;
  /** The slow scale/opacity breath (off for static places like list rows). */
  breathing?: boolean;
  className?: string;
}) {
  const id = useId();
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      aria-hidden="true"
      className={cn("shrink-0", breathing && "jasper-spark-breathe", className)}
    >
      <defs>
        <linearGradient id={id} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#F22659" />
          <stop offset="0.55" stopColor="#FF7340" />
          <stop offset="1" stopColor="#FFA94D" />
        </linearGradient>
      </defs>
      {/* Four-point spark — soft concave sides, a small satellite dot */}
      <path
        d="M12 2.6c.9 4.7 2.8 6.6 7.4 7.4-4.6.9-6.5 2.8-7.4 7.4-.9-4.6-2.8-6.5-7.4-7.4 4.6-.8 6.5-2.7 7.4-7.4Z"
        fill={`url(#${id})`}
      />
      <circle cx="19" cy="18.5" r="1.9" fill={`url(#${id})`} opacity="0.9" />
    </svg>
  );
}
