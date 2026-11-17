import { useId } from "react";

/**
 * The WAVES mark as a standalone glyph — the thick rounded squircle with the
 * rounded play wedge (the iOS tab glyph). `active` fills the wedge with the
 * brand gradient (rose → live orange → amber); otherwise it inherits
 * currentColor like any icon.
 */
export function WavesTabGlyph({
  size = 22,
  active = false,
  className,
}: {
  size?: number;
  active?: boolean;
  className?: string;
}) {
  const gradientId = useId();
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={2.4}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      className={className}
    >
      {active && (
        <defs>
          <linearGradient id={gradientId} x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor="#F22659" />
            <stop offset="0.55" stopColor="#FF7340" />
            <stop offset="1" stopColor="#FFA94D" />
          </linearGradient>
        </defs>
      )}
      <rect x="3" y="3" width="18" height="18" rx="5.5" />
      <path
        d="M10 8.8 15.7 12 10 15.2Z"
        fill={active ? `url(#${gradientId})` : "currentColor"}
        stroke={active ? `url(#${gradientId})` : "currentColor"}
        strokeWidth={1.7}
      />
    </svg>
  );
}
