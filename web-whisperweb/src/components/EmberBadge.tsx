import { memo } from "react";

import { cn } from "@/lib/utils";

/**
 * Ember's avatar — the candle-ghost mascot, mirroring the iOS `EmberMascot`
 * sticker. Rendered as the bare sticker (it already carries its own white
 * outline) so it reads identically on the sidebar and in the chat.
 */
function EmberBadgeBase({
  size = 36,
  className,
}: {
  size?: number;
  className?: string;
}) {
  return (
    <img
      src="/ember-mascot.png"
      alt="Jasper"
      width={size}
      height={size}
      draggable={false}
      className={cn("shrink-0 select-none object-contain", className)}
      style={{
        width: size,
        height: size,
        filter: "drop-shadow(0 3px 8px rgba(244,81,30,0.28))",
      }}
    />
  );
}

export const EmberBadge = memo(EmberBadgeBase);
