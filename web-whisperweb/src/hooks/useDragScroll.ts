import { useCallback, useRef } from "react";

/**
 * Enables click-and-drag (mouse) horizontal scrolling on a scroll container —
 * mirrors the swipe gesture mobile users get on the iOS carousels. Touch
 * scrolling is left to the browser; this only augments pointer devices.
 */
export function useDragScroll<T extends HTMLElement>() {
  const ref = useRef<T | null>(null);
  const state = useRef({ down: false, moved: false, startX: 0, startLeft: 0 });

  const onMouseDown = useCallback((e: React.MouseEvent) => {
    const el = ref.current;
    if (!el) return;
    state.current = {
      down: true,
      moved: false,
      startX: e.pageX,
      startLeft: el.scrollLeft,
    };
  }, []);

  const onMouseMove = useCallback((e: React.MouseEvent) => {
    const el = ref.current;
    if (!el || !state.current.down) return;
    const dx = e.pageX - state.current.startX;
    if (Math.abs(dx) > 4) state.current.moved = true;
    el.scrollLeft = state.current.startLeft - dx;
  }, []);

  const end = useCallback(() => {
    state.current.down = false;
  }, []);

  /** True if the last interaction was a drag — use to swallow click events. */
  const didDrag = useCallback(() => state.current.moved, []);

  return {
    ref,
    didDrag,
    handlers: {
      onMouseDown,
      onMouseMove,
      onMouseUp: end,
      onMouseLeave: end,
    },
  };
}
