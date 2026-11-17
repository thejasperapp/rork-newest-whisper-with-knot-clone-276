import { memo } from "react";
import { Check } from "lucide-react";
import { cn } from "@/lib/utils";
import { SealBadge } from "@/components/SealBadge";
import type { WhisperLiarBadge, WhisperProfile } from "@/lib/types";

interface UserBadgesProps {
  profile?: WhisperProfile | null;
  /** Compatibility only: legacy reputation labels are never rendered. */
  liar?: WhisperLiarBadge | null;
  size?: number;
  className?: string;
  maxChips?: number;
}

/** Exactly one ID-bound identity/staff marker; never a reputation or membership score. */
function UserBadgesBase({ profile, size = 15, className }: UserBadgesProps) {
  const tier = profile?.is_owner ? "Owner" : profile?.is_admin ? "Admin" : profile?.is_moderator ? "Moderator" : profile?.is_verified ? "Verified identity" : null;
  if (!tier) return null;
  const colors = tier === "Owner" ? ["#ffc74d", "#f7734d", "#d9408c", "#735ef2"] : tier === "Admin" ? ["#ffd54a", "#f5b21f"] : tier === "Moderator" ? ["#eef0f5", "#b3b7c2", "#dce0e8"] : ["#4aa8ff", "#2f86f0"];
  return <span className={cn("inline-flex items-center", className)} aria-label={`${tier}. Not a guarantee of safety or accuracy.`}>
    <SealBadge size={size + 2} colors={colors} shadowColor={colors[0]} title={`${tier} — not a guarantee of safety or accuracy`}>
      <Check style={{ width: size * 0.5, height: size * 0.5 }} strokeWidth={3.5} />
    </SealBadge>
  </span>;
}
export const UserBadges = memo(UserBadgesBase);
