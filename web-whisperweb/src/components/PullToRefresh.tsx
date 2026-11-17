import { memo, useEffect, useRef, useState } from "react";

import { TraceLogo } from "@/components/TraceLogo";
import { cn } from "@/lib/utils";

interface PullToRefreshProps {
  onRefresh: () => Promise<unknown>;
  children: React.ReactNode;
}

const THRESHOLD = 72;
const MAX_PULL = 120;

/**
 * Touch pull-to-refresh that mirrors the iOS Whisper experience: pulling down
 * from the top reveals the traced-"W" indicator in a floating disc, and
 * releasing past the threshold triggers a refresh.
 *
 * The touch listeners are attached natively as **non-passive** so we can call
 * `preventDefault()` during an active pull — React's synthetic touch handlers
 * are registered passively and silently ignore `preventDefault`, which let the
 * browser's own overscroll swallow the gesture. Pointer devices fall back to
 * standard scrolling.
 */
function PullToRefreshBase({ onRefresh, children }: PullToRefreshProps) {
  const [pull, setPull] = useState<number>(0);
  const [refreshing, setRefreshing] = useState<boolean>(false);
  const [animating, setAnimating] = useState<boolean>(true);

  const containerRef = useRef<HTMLDivElement>(null);
  const startY = useRef<number>(0);
  const active = useRef<boolean>(false);
  const pullRef = useRef<number>(0);
  const refreshingRef = useRef<boolean>(false);

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;

    const scrollTop = (): number =>
      window.scrollY || document.documentElement.scrollTop || 0;

    const onTouchStart = (e: TouchEvent): void => {
      if (refreshingRef.current) return;
      if (scrollTop() > 0) return;
      startY.current = e.touches[0]!.clientY;
      active.current = true;
      setAnimating(false);
    };

    const onTouchMove = (e: TouchEvent): void => {
      if (!active.current || refreshingRef.current) return;
      const dy = e.touches[0]!.clientY - startY.current;
      if (dy <= 0) {
        pullRef.current = 0;
        setPull(0);
        return;
      }
      // We're at the top and pulling down — own the gesture.
      if (e.cancelable) e.preventDefault();
      const next = Math.min(MAX_PULL, dy * 0.5);
      pullRef.current = next;
      setPull(next);
    };

    const onTouchEnd = (): void => {
      if (!active.current) return;
      active.current = false;
      setAnimating(true);
      if (pullRef.current >= THRESHOLD && !refreshingRef.current) {
        refreshingRef.current = true;
        setRefreshing(true);
        setPull(THRESHOLD);
        void Promise.resolve(onRefresh()).finally(() => {
          refreshingRef.current = false;
          setRefreshing(false);
          pullRef.current = 0;
          setPull(0);
        });
      } else {
        pullRef.current = 0;
        setPull(0);
      }
    };

    el.addEventListener("touchstart", onTouchStart, { passive: true });
    el.addEventListener("touchmove", onTouchMove, { passive: false });
    el.addEventListener("touchend", onTouchEnd, { passive: true });
    el.addEventListener("touchcancel", onTouchEnd, { passive: true });
    return () => {
      el.removeEventListener("touchstart", onTouchStart);
      el.removeEventListener("touchmove", onTouchMove);
      el.removeEventListener("touchend", onTouchEnd);
      el.removeEventListener("touchcancel", onTouchEnd);
    };
  }, [onRefresh]);

  const progress = Math.min(1, pull / THRESHOLD);
  const showIndicator = pull > 4 || refreshing;
  const offset = refreshing ? THRESHOLD : pull;

  return (
    <div ref={containerRef} className="relative">
      {showIndicator && (
        <div
          className="pointer-events-none absolute inset-x-0 top-0 z-20 flex justify-center"
          style={{
            transform: `translateY(${offset - 30}px)`,
            opacity: refreshing ? 1 : progress,
          }}
        >
          {/* JUST THE W — the brand mark as a pure outline in the open space
              where a spinner would sit. No disc, no shadow, no spin: it traces
              in with the pull and keeps tracing on a loop while refreshing. */}
          <div className={cn("flex h-[44px] items-center justify-center", refreshing && "opacity-100")}>
            <TraceLogo size={44} outline progress={refreshing ? undefined : progress} />
          </div>
        </div>
      )}

      <div
        style={{
          transform: `translateY(${offset}px)`,
          transition: animating ? "transform 0.25s ease-out" : "none",
        }}
      >
        {children}
      </div>
    </div>
  );
}

export const PullToRefresh = memo(PullToRefreshBase);
