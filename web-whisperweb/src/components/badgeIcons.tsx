import {
  BadgeCheck,
  CalendarCheck,
  Clapperboard,
  Crown,
  Dumbbell,
  Feather,
  Hand,
  Leaf,
  ShieldCheck,
  ShieldHalf,
  Sparkles,
  ThumbsUp,
} from "lucide-react";

import type { BadgeKind } from "@/lib/badges";
import type { RoleKind } from "@/lib/badgeInfo";

/** Inline glyph for a trust/identity chip, coloured by the caller. */
export function badgeIcon(kind: BadgeKind, size: number): React.ReactNode {
  const s = { width: size, height: size };
  switch (kind) {
    case "coach":
      return <Dumbbell style={s} strokeWidth={2.5} />;
    case "director":
      return <Clapperboard style={s} strokeWidth={2.5} />;
    case "blogger":
      return <Feather style={s} strokeWidth={2.5} />;
    case "teen":
      return <ShieldHalf style={s} strokeWidth={2.5} />;
    case "adult":
      return <ShieldCheck style={s} strokeWidth={2.5} />;
    case "trusted":
      return <ThumbsUp style={s} strokeWidth={2.5} />;
    case "established":
      return <Leaf style={s} strokeWidth={2.5} />;
    case "guardian":
      return <ShieldHalf style={s} strokeWidth={2.5} />;
    case "founding":
      return <Sparkles style={s} strokeWidth={2.5} />;
    case "restricted":
      return <Hand style={s} strokeWidth={2.5} />;
  }
}

/** Inline glyph for the leading role pill. */
export function roleIcon(kind: RoleKind, size: number): React.ReactNode {
  const s = { width: size, height: size };
  switch (kind) {
    case "owner":
      return <Crown style={s} strokeWidth={2.5} />;
    case "admin":
      return <BadgeCheck style={s} strokeWidth={2.5} />;
    case "moderator":
      return <ShieldHalf style={s} strokeWidth={2.5} />;
    case "verified":
      return <BadgeCheck style={s} strokeWidth={2.5} />;
    case "coach":
      return <Dumbbell style={s} strokeWidth={2.5} />;
  }
}
