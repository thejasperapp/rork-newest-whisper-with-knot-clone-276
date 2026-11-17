import { memo, useEffect, useRef, useState } from "react";

/**
 * Typewriter-style streaming text — web port of the iOS
 * `WhisperEmberStreamingText`. Reveals characters gradually so Ember's replies
 * feel generated live without needing token streaming on the backend.
 */
function EmberStreamingTextBase({
  text,
  charsPerSecond = 90,
  minCharsToAnimate = 16,
  onFinished,
  className,
}: {
  text: string;
  charsPerSecond?: number;
  minCharsToAnimate?: number;
  onFinished?: () => void;
  className?: string;
}) {
  const [visibleCount, setVisibleCount] = useState<number>(
    text.length < minCharsToAnimate ? text.length : 0
  );
  const finishedRef = useRef<boolean>(false);

  useEffect(() => {
    if (text.length < minCharsToAnimate) {
      setVisibleCount(text.length);
      if (!finishedRef.current) {
        finishedRef.current = true;
        onFinished?.();
      }
      return;
    }
    finishedRef.current = false;
    setVisibleCount(0);
    const interval = 1000 / Math.max(20, charsPerSecond);
    const timer = window.setInterval(() => {
      setVisibleCount((c) => {
        const next = Math.min(text.length, c + 2);
        if (next >= text.length) {
          window.clearInterval(timer);
          if (!finishedRef.current) {
            finishedRef.current = true;
            // Defer so we never call back during render.
            window.setTimeout(() => onFinished?.(), 0);
          }
        }
        return next;
      });
    }, interval);
    return () => window.clearInterval(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [text]);

  return <span className={className}>{text.slice(0, visibleCount)}</span>;
}

export const EmberStreamingText = memo(EmberStreamingTextBase);
