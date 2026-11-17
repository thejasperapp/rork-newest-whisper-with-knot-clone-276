import { useState } from "react";
import { Info } from "lucide-react";
import { BadgeInfoSheet } from "@/components/BadgeInfoSheet";
import { cn } from "@/lib/utils";
import type { WhisperLiarBadge, WhisperProfile } from "@/lib/types";

export function ProfileBadgeRow({ profile, className }: { profile: WhisperProfile; liar?: WhisperLiarBadge | null; className?: string }) {
  const [open, setOpen] = useState(false);
  const roles = [profile.is_coach && "Coach", profile.is_recruiter && "Recruiter", profile.is_director && "Director", profile.is_blogger && "Writer", profile.account_type === "creator" && "Creator", profile.professional_category].filter((value): value is string => typeof value === "string" && value.length > 0);
  return <div className={cn("flex items-center gap-2 text-sm text-muted-foreground", className)}>
    {roles.length > 0 && <p>{Array.from(new Set(roles)).join(" · ")}</p>}
    <button onClick={() => setOpen(true)} aria-label="About identity indicators" className="flex min-h-11 min-w-11 items-center justify-center rounded-full hover:bg-secondary"><Info className="h-4 w-4" /></button>
    <BadgeInfoSheet open={open} onOpenChange={setOpen} />
  </div>;
}
