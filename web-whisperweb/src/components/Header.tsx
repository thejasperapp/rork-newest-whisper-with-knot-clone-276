import { memo } from "react";
import { Link } from "react-router-dom";
import { Search, Bell } from "lucide-react";

import { useUnreadActivity } from "@/hooks/useUnreadActivity";

interface HeaderProps {
  /** Page name shown in the centered floating pill. */
  title: string;
  /** Optional element pinned to the floating left slot (e.g. a back button). */
  left?: React.ReactNode;
  /** Optional element overriding the right slot. Defaults to activity + search. */
  right?: React.ReactNode;
  /** Hide the default floating search button (e.g. on the Search page). */
  hideSearch?: boolean;
  /** Hide the activity bell (e.g. on the Notifications page itself). */
  hideBell?: boolean;
}

/**
 * "Invisible" floating header. The bar itself is transparent and reserves only
 * its own row so content never overlaps — the only visible chrome is a centered
 * glass name pill plus floating circular activity + search buttons, à la Threads.
 */
function HeaderBase({
  title,
  left,
  right,
  hideSearch = false,
  hideBell = false,
}: HeaderProps) {
  const unread = useUnreadActivity();

  return (
    <div className="pointer-events-none sticky top-0 z-30 flex h-14 items-center justify-center rounded-b-[22px] border-b border-border/60 bg-background/80 px-3 backdrop-blur-sm">
      {left && (
        <div className="pointer-events-auto absolute left-3">{left}</div>
      )}

      <span className="glass pointer-events-auto rounded-full border border-border/60 px-5 py-1.5 text-[15px] font-bold tracking-tight shadow-sm">
        {title}
      </span>

      {right ?? (
        <div className="pointer-events-auto absolute right-3 flex items-center gap-2">
          {!hideBell && (
            <Link
              to="/notifications"
              aria-label="Activity"
              className="glass relative flex h-10 w-10 items-center justify-center rounded-full border border-border/60 text-foreground shadow-sm transition-transform active:scale-90"
            >
              <Bell className="h-[19px] w-[19px]" />
              {unread > 0 && (
                <span className="absolute -right-0.5 -top-0.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-primary px-1 text-[10px] font-bold text-primary-foreground">
                  {unread > 9 ? "9+" : unread}
                </span>
              )}
            </Link>
          )}
          {!hideSearch && (
            <Link
              to="/search"
              aria-label="Search"
              className="glass flex h-10 w-10 items-center justify-center rounded-full border border-border/60 text-foreground shadow-sm transition-transform active:scale-90 lg:hidden"
            >
              <Search className="h-[20px] w-[20px]" />
            </Link>
          )}
        </div>
      )}
    </div>
  );
}

export const Header = memo(HeaderBase);
