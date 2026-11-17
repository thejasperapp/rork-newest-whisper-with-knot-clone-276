import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { ArrowRight, BadgeCheck, Dumbbell, Trophy } from "lucide-react";

import { Avatar } from "@/components/Avatar";
import { SealBadge } from "@/components/SealBadge";
import { fetchCoachRate, formatCents } from "@/lib/coachPay";
import { fetchFeaturedProfileByUsername } from "@/lib/featured";
import type { WhisperProfile } from "@/lib/types";

const TIER_COLORS: Record<number, string> = {
  1: "#ef4444",
  2: "#eab308",
  3: "#22c55e",
};

export type SpotlightKind = "coach" | "athlete" | "creator";

const KIND_META: Record<
  SpotlightKind,
  { label: string; accent: string; accentText: string }
> = {
  coach: { label: "Verified Coach", accent: "#fa7321", accentText: "text-orange-500" },
  athlete: { label: "Verified Athlete", accent: "#e11d48", accentText: "text-rose-600" },
  creator: { label: "Verified Creator", accent: "#0ea5e9", accentText: "text-sky-500" },
};

function KindSeal({ kind }: { kind: SpotlightKind }) {
  if (kind === "coach") {
    return (
      <SealBadge size={17} solid="#fa7321" shadowColor="#fa7321" title="Verified Coach">
        <Dumbbell style={{ width: 8, height: 8 }} strokeWidth={3} />
      </SealBadge>
    );
  }
  if (kind === "athlete") {
    return (
      <SealBadge
        size={17}
        colors={["#fb7185", "#e11d48"]}
        shadowColor="#e11d48"
        title="Verified Athlete"
      >
        <Trophy style={{ width: 8, height: 8 }} strokeWidth={3} />
      </SealBadge>
    );
  }
  return (
    <SealBadge
      size={17}
      colors={["#38bdf8", "#0284c7"]}
      shadowColor="#0ea5e9"
      title="Verified Creator"
    >
      <BadgeCheck style={{ width: 8, height: 8 }} strokeWidth={3} />
    </SealBadge>
  );
}

/**
 * Rich spotlight result for in-app search — a compact take on the public
 * "Hudson" template, shared by coaches, athletes, and creators. Pulls the
 * member's admin-curated featured card (photo, tier, discipline, chips)
 * when one exists, plus a coach's live monthly rate.
 */
export function CoachSearchCard({
  profile,
  kind = "coach",
}: {
  profile: WhisperProfile;
  kind?: SpotlightKind;
}) {
  const meta = KIND_META[kind];
  const spotlight = useQuery({
    queryKey: ["featured-by-username", profile.username],
    queryFn: () => fetchFeaturedProfileByUsername(profile.username),
    staleTime: 60_000,
    retry: false,
  });
  const rate = useQuery({
    queryKey: ["coach-rate", profile.user_id],
    queryFn: () => fetchCoachRate(profile.user_id),
    staleTime: 60_000,
    retry: false,
    enabled: kind === "coach",
  });

  const s = spotlight.data ?? null;
  const r = rate.data ?? null;
  const priced =
    kind === "coach" &&
    Boolean(r?.active && r.acceptingPayments && r.monthlyPriceCents);
  const photo = s?.photo_url || profile.profile_image_url || "";
  const blurb = s?.paragraphs[0] ?? profile.bio ?? "";
  const tier = kind === "coach" ? (s?.tier ?? null) : null;

  return (
    <Link
      to={`/u/${profile.username}`}
      className="block overflow-hidden rounded-2xl border border-border bg-card transition-colors hover:bg-secondary/40"
    >
      <div className="flex gap-3.5 p-3.5">
        {/* Photo panel */}
        <div className="h-24 w-20 shrink-0 overflow-hidden rounded-xl bg-secondary">
          {photo ? (
            <img
              src={photo}
              alt={profile.username}
              loading="lazy"
              className="h-full w-full object-cover object-top"
            />
          ) : (
            <div className="flex h-full w-full items-center justify-center">
              <Avatar name={profile.username} size={44} />
            </div>
          )}
        </div>

        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-1.5">
            <p className="truncate text-[15.5px] font-extrabold">
              {profile.display_name || profile.username}
            </p>
            <KindSeal kind={kind} />
          </div>
          <p className="truncate text-[12.5px] text-muted-foreground">
            @{profile.username}
          </p>

          <div className="mt-1.5 flex flex-wrap items-center gap-1.5">
            {tier !== null && (
              <span className="inline-flex items-center gap-1.5 rounded-full border border-border px-2 py-0.5 text-[11px] font-bold">
                <span
                  className="inline-block h-2 w-2 rounded-full"
                  style={{ backgroundColor: TIER_COLORS[tier] ?? TIER_COLORS[1] }}
                />
                Tier {tier}
              </span>
            )}
            {s?.discipline && (
              <span className="rounded-full border border-border px-2 py-0.5 text-[11px] font-semibold">
                {s.discipline}
              </span>
            )}
            {priced && (
              <span className="rounded-full bg-orange-500/10 px-2 py-0.5 text-[11px] font-extrabold text-orange-600">
                {formatCents(r!.monthlyPriceCents!)}/mo
              </span>
            )}
          </div>

          {blurb && (
            <p className="mt-1.5 line-clamp-2 text-[12.5px] leading-snug text-muted-foreground">
              {blurb}
            </p>
          )}
        </div>
      </div>

      <div className="flex items-center justify-between border-t border-border/60 px-3.5 py-2">
        <span
          className={`text-[11px] font-black uppercase tracking-[0.14em] ${meta.accentText}`}
        >
          {meta.label}
        </span>
        <span className="flex items-center gap-1 text-[12.5px] font-bold">
          View profile
          <ArrowRight className="h-3.5 w-3.5" />
        </span>
      </div>
    </Link>
  );
}
