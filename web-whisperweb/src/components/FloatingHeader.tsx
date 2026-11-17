import { memo } from "react";
import { Link } from "react-router-dom";

interface FloatingHeaderProps {
  /** Page name shown in the centered floating pill. */
  title: React.ReactNode;
  /** Optional element pinned to the floating left slot (e.g. a back button). */
  left?: React.ReactNode;
  /** Optional element overriding the right slot. */
  right?: React.ReactNode;
}

/**
 * FloatingHeader — no bar at all. Just a floating glass title pill centered
 * at the top, floating action buttons on the left/right, and the page content
 * scrolls underneath with proper top padding.
 *
 * The container is pointer-events-none so only the pill and buttons are
 * interactive — the rest of the row is transparent to taps.
 */
function FloatingHeaderBase({ title, left, right }: FloatingHeaderProps) {
  return (
    <div className="social-page-header pointer-events-none sticky top-0 z-30 flex h-14 items-center justify-center px-4">
      {/* Floating left action (back button, etc.) */}
      {left && (
        <div className="pointer-events-auto absolute left-4">
          {left}
        </div>
      )}

      {/* Floating glass title pill */}
      <span className="social-page-title glass pointer-events-auto rounded-full border border-border/40 px-5 py-1.5 text-[15px] font-bold tracking-tight shadow-sm">
        {title}
      </span>

      {/* Floating right actions */}
      {right && (
        <div className="pointer-events-auto absolute right-4 flex items-center gap-2">
          {right}
        </div>
      )}
    </div>
  );
}

/** Circular glass button used in the floating header slots. */
export function FloatingButton({
  children,
  onClick,
  to,
  label,
  className,
  badge,
}: {
  children: React.ReactNode;
  onClick?: () => void;
  to?: string;
  label: string;
  className?: string;
  badge?: React.ReactNode;
}) {
  const base =
    "social-header-action glass flex h-10 w-10 items-center justify-center rounded-full border border-border/40 text-foreground shadow-sm transition-transform active:scale-90";
  const cls = className ? `${base} ${className}` : base;

  if (to) {
    return (
      <Link to={to} className={cls} aria-label={label}>
        {children}
        {badge}
      </Link>
    );
  }
  return (
    <button onClick={onClick} className={cls} aria-label={label}>
      {children}
      {badge}
    </button>
  );
}

export const FloatingHeader = memo(FloatingHeaderBase);
