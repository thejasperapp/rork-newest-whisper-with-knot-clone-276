import { useEffect } from "react";
import { useLocation } from "react-router-dom";

/**
 * Scrolls the window to the top on every route change.
 * Handles both navigation and redirect transitions so users
 * always start at the top of a new page.
 */
export function ScrollToTop() {
  const { pathname, search, hash } = useLocation();

  useEffect(() => {
    // If there's a hash (anchor), let the browser handle it.
    if (hash) return;
    // Use "instant" to avoid a slow scroll animation on route change.
    window.scrollTo({ top: 0, left: 0, behavior: "instant" });
  }, [pathname, search, hash]);

  return null;
}
