import { memo } from "react";
import { Plus } from "lucide-react";

import { SealBadge } from "./SealBadge";

/**
 * Whisper One "+" badge — the ink-black seal shown next to a member's name.
 * Unlike the blue/orange verified seals this is a membership marker, not a
 * verification: solid black with a white plus. The white drop shadow is
 * invisible on light surfaces but gives a soft halo in dark mode so the
 * black seal never disappears.
 */
function OneBadgeBase({ size = 14 }: { size?: number }) {
  return (
    <SealBadge
      size={size + 2}
      solid="#0b0b0d"
      shadowColor="#ffffff"
      title="Whisper One"
    >
      <Plus
        style={{ width: size * 0.55, height: size * 0.55 }}
        strokeWidth={3.5}
      />
    </SealBadge>
  );
}

export const OneBadge = memo(OneBadgeBase);
