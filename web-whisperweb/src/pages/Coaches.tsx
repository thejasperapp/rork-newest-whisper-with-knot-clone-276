import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { ArrowRight, Dumbbell, Search, ShieldCheck } from "lucide-react";

import PublicNav from "@/components/PublicNav";
import PublicFooter from "@/components/PublicFooter";
import { FeaturedProfileCard } from "@/components/FeaturedProfileCard";
import { Reveal } from "@/components/Reveal";
import { PresentationIntro, PresentationLink } from "@/components/Presentation";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { usePageMeta } from "@/hooks/usePageMeta";
import {
  fetchFeaturedProfiles,
  HUDSON_TEMPLATE,
  type FeaturedProfile,
} from "@/lib/featured";

/** Experience tier for a coaching style: 1 = red, 2 = yellow, 3 = green. */
type CoachTier = 1 | 2 | 3;

const TIER_COLORS: Record<CoachTier, string> = {
  1: "#ef4444",
  2: "#eab308",
  3: "#22c55e",
};

const TIER_LABELS: Record<CoachTier, string> = {
  1: "Tier 1",
  2: "Tier 2",
  3: "Tier 3",
};

function TierDot({ tier, size = 10 }: { tier: CoachTier; size?: number }) {
  return (
    <span
      className="inline-block shrink-0 rounded-full"
      style={{
        width: size,
        height: size,
        backgroundColor: TIER_COLORS[tier],
        boxShadow: `0 0 0 3px ${TIER_COLORS[tier]}22`,
      }}
      aria-label={TIER_LABELS[tier]}
    />
  );
}

function CoachSeal({ size = 16 }: { size?: number }) {
  return (
    <Dumbbell size={size} aria-hidden="true" />
  );
}

/** The original hand-built Hudson feature, kept as the founding coach card. */
const HUDSON: FeaturedProfile = HUDSON_TEMPLATE;

export default function Coaches() {
  usePageMeta(
    "Coaches",
    "Meet Whisper's verified coaches — application-reviewed, tiered by experience, coaching real clients through the app."
  );

  const [query, setQuery] = useState<string>("");
  const [tierFilter, setTierFilter] = useState<CoachTier | null>(null);

  const featured = useQuery({
    queryKey: ["featured-profiles", "coach"],
    queryFn: () => fetchFeaturedProfiles("coach"),
    staleTime: 60_000,
  });

  const dynamic = featured.data ?? [];
  // If an admin-managed Hudson card exists it replaces the built-in one.
  const hasHudson = dynamic.some(
    (p) => p.name.trim().toLowerCase() === "hudson"
  );
  const allCoaches: FeaturedProfile[] = hasHudson
    ? dynamic
    : [HUDSON, ...dynamic];

  const coaches = useMemo(() => {
    const q = query.trim().toLowerCase();
    return allCoaches.filter((c) => {
      if (tierFilter !== null && c.tier !== tierFilter) return false;
      if (!q) return true;
      return (
        c.name.toLowerCase().includes(q) ||
        (c.discipline ?? "").toLowerCase().includes(q) ||
        c.chips.some((chip) => chip.toLowerCase().includes(q))
      );
    });
  }, [allCoaches, query, tierFilter]);

  const filtersActive = query.trim().length > 0 || tierFilter !== null;

  return (
    <div className="presentation-page min-h-screen bg-background">
      <PublicNav />

      <main>
        <div className="presentation-container !pb-0">
          <PresentationIntro eyebrow="The people in your corner" title="Find a coach. Start a conversation." description="Different goals need different guidance. Explore coaching styles, meet the person behind the profile, and choose the support that feels right for you.">
            <a href="#coach-directory" className="presentation-link presentation-link-primary">Explore coaches <ArrowRight size={16} /></a>
            <PresentationLink to="/roles/coach">Build your coaching practice</PresentationLink>
          </PresentationIntro>
          <p className="presentation-body mb-8 max-w-2xl">Coach applications are reviewed by a person. A role or tier is not a guarantee of professional competence, safety, or results. Review a coach’s background and plan before committing.</p>
        </div>

        {/* Tier system */}
        <section className="px-4 py-8 sm:px-6 lg:px-8 lg:py-10">
          <Reveal className="mx-auto max-w-4xl rounded-[28px] border border-border bg-card p-6 sm:p-8">
            <h2 className="text-center font-display text-[22px] font-extrabold sm:text-[26px]">
              How coach tiers work
            </h2>
            <p className="mx-auto mt-2 max-w-2xl text-center text-[15px] leading-relaxed text-muted-foreground">
              Each coaching style a coach offers carries its own tier dot. The
              dot shows their experience level in that style — it grows with
              time on the platform, client results, and check-in history.
            </p>
            <Reveal stagger className="mt-6 grid gap-3 sm:grid-cols-3">
              {(
                [
                  [1, "Building experience — newer to coaching this style on Whisper, reviewed and verified like everyone."],
                  [2, "Established — a proven track record of clients and consistent check-ins in this style."],
                  [3, "Elite — deep experience with long-term client results in this style."],
                ] as [CoachTier, string][]
              ).map(([tier, desc]) => (
                <div
                  key={tier}
                  className="rounded-2xl border border-border bg-background p-4"
                >
                  <div className="flex items-center gap-2">
                    <TierDot tier={tier} size={12} />
                    <span className="text-[15px] font-bold">
                      {TIER_LABELS[tier]}
                    </span>
                  </div>
                  <p className="mt-2 text-[13.5px] leading-snug text-muted-foreground">
                    {desc}
                  </p>
                </div>
              ))}
            </Reveal>
          </Reveal>
        </section>

        {/* Featured coaches — the Hudson template, admin-managed */}
        <section id="coach-directory" className="scroll-mt-24 px-4 py-10 sm:px-6 lg:px-8 lg:py-14">
          <div className="mx-auto max-w-5xl">
            {/* Directory search + tier filters */}
            <div className="mb-10 flex flex-col items-center gap-3 sm:flex-row sm:justify-center">
              <div className="flex h-11 w-full max-w-xs items-center gap-2 rounded-full border border-border bg-card px-4">
                <Search className="h-4 w-4 shrink-0 text-muted-foreground" />
                <input
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  aria-label="Search coaches by name or style"
                  placeholder="Search name or style…"
                  className="w-full bg-transparent text-[14px] outline-none placeholder:text-muted-foreground"
                />
              </div>
              <div className="flex gap-2">
                {([1, 2, 3] as CoachTier[]).map((tier) => (
                  <button
                    key={tier}
                    aria-pressed={tierFilter === tier}
                    onClick={() =>
                      setTierFilter((t) => (t === tier ? null : tier))
                    }
                    className={cn(
                      "flex items-center gap-2 rounded-full border px-4 py-2 text-[13px] font-bold transition-colors",
                      tierFilter === tier
                        ? "border-foreground bg-foreground text-background"
                        : "border-border bg-card hover:bg-secondary"
                    )}
                  >
                    <TierDot tier={tier} size={9} />
                    {TIER_LABELS[tier]}
                  </button>
                ))}
              </div>
            </div>

            {coaches.length === 0 && filtersActive ? (
              <div className="rounded-[28px] border border-dashed border-border p-10 text-center">
                <p className="text-[16px] font-semibold">No coaches match.</p>
                <p className="mx-auto mt-1.5 max-w-md text-[14.5px] text-muted-foreground">
                  Try a different name, style, or tier — or clear the filters.
                </p>
                <Button
                  variant="outline"
                  className="mt-5 rounded-full"
                  onClick={() => {
                    setQuery("");
                    setTierFilter(null);
                  }}
                >
                  Clear filters
                </Button>
              </div>
            ) : (
              <div className="space-y-14">
                {coaches.map((coach) => (
                  <Reveal key={coach.id}>
                    <FeaturedProfileCard profile={coach} />
                  </Reveal>
                ))}
              </div>
            )}

            {/* More coming */}
            <div className="mt-6 rounded-[28px] border border-dashed border-border p-8 text-center">
              <p className="text-[16px] font-semibold">
                More coaches are being reviewed right now.
              </p>
              <p className="mx-auto mt-1.5 max-w-xl text-[14.5px] text-muted-foreground">
                Every application goes through a real human review of
                credentials and client history before a coach seal is issued —
                that's why this list grows carefully.
              </p>
            </div>
          </div>
        </section>

        {/* Become a coach CTA */}
        <section className="px-4 py-10 pb-20 sm:px-6 lg:px-8 lg:py-14">
          <Reveal variant="scale" className="mx-auto max-w-3xl rounded-[24px] bg-foreground p-7 text-center text-primary-foreground sm:rounded-[32px] sm:p-14">
            <div className="mx-auto mb-5 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary-foreground/10">
              <ShieldCheck className="h-7 w-7" />
            </div>
            <h2 className="font-display text-[24px] font-extrabold sm:text-[36px]">
              Think you should be on this page?
            </h2>
            <p className="mx-auto mt-4 max-w-xl text-[17px] text-primary-foreground/80">
              Coaching on Whisper is application-based. Submit your credentials
              in the app and, if approved, unlock the Coach Studio for
              $249.99/year.
            </p>
            <div className="mt-8 flex flex-col justify-center gap-3 sm:flex-row">
              <Button
                size="lg"
                className="h-14 rounded-full bg-background px-8 text-[16px] font-semibold text-foreground hover:bg-background/90"
                asChild
              >
                <Link to="/auth?mode=signup">
                  Apply to coach
                  <ArrowRight className="ml-1 h-5 w-5" />
                </Link>
              </Button>
              <Button
                size="lg"
                variant="outline"
                className="h-14 rounded-full border-primary-foreground/30 bg-transparent px-8 text-[16px] font-semibold text-primary-foreground hover:bg-primary-foreground/10 hover:text-primary-foreground"
                asChild
              >
                <Link to="/roles/coach">What Coach unlocks</Link>
              </Button>
            </div>
          </Reveal>
        </section>
      </main>

      <PublicFooter />
    </div>
  );
}
