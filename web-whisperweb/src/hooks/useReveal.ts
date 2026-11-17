import { useEffect, useRef, useState } from "react";

/**
 * useReveal — IntersectionObserver-based scroll reveal.
 * Returns a ref to attach and a boolean that flips to true once the
 * element enters the viewport (once-only by default).
 */
export function useReveal<T extends HTMLElement = HTMLDivElement>(
  options?: { threshold?: number; rootMargin?: string; once?: boolean }
): [React.RefObject<T | null>, boolean] {
  const { threshold = 0.12, rootMargin = "0px 0px -60px 0px", once = true } =
    options ?? {};
  const ref = useRef<T>(null);
  const [visible, setVisible] = useState<boolean>(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            setVisible(true);
            if (once) observer.unobserve(entry.target);
          } else if (!once) {
            setVisible(false);
          }
        }
      },
      { threshold, rootMargin }
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, [threshold, rootMargin, once]);

  return [ref, visible];
}
