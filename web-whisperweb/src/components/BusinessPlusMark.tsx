import { forwardRef } from "react";
import type { LucideProps } from "lucide-react";

/**
 * The Business+ mark — Whisper's W with a plus grown out of its final
 * upstroke, drawn as ONE connected glyph. The plus's left arm starts on
 * the W's last stroke so the two shapes read as a single lockup.
 *
 * Drop-in compatible with lucide icons (size / className / strokeWidth /
 * color), so it slots into nav arrays typed as lucide components.
 */
export const BusinessPlusMark = forwardRef<SVGSVGElement, LucideProps>(
  function BusinessPlusMark({ size = 24, strokeWidth = 2.4, ...rest }, ref) {
    return (
      <svg
        ref={ref}
        width={size}
        height={size}
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth={strokeWidth}
        strokeLinecap="round"
        strokeLinejoin="round"
        aria-hidden="true"
        {...rest}
      >
        {/* The W */}
        <path d="M2.4 6.5 6.1 16.5 9.35 8.2 12.6 16.5 16.4 6.5" />
        {/* The plus — its left arm grows out of the W's final upstroke */}
        <path d="M15.05 10.3h7.15" />
        <path d="M18.6 6.7v7.2" />
      </svg>
    );
  }
);
