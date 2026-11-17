import { useMemo, useRef, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import {
  ArrowUpRight,
  Briefcase,
  BriefcaseBusiness,
  Building2,
  ChevronRight,
  Flame,
  Loader2,
  Medal,
  Pause,
  Play,
  Plus,
  Search,
  Sparkles,
} from "lucide-react";

import { Header } from "@/components/Header";
import { Avatar } from "@/components/Avatar";
import { SealBadge } from "@/components/SealBadge";
import { useAuth } from "@/hooks/useAuth";
import { cn } from "@/lib/utils";
import { openPortal } from "@/lib/portal";
import { supabase } from "@/lib/supabase";
import type { WhisperProfile } from "@/lib/types";
import {
  fetchBrand,
  fetchBrands,
  fetchHiringCounts,
  typicalPayText,
  type BrandProfile,
} from "@/lib/brands";

/**
 * Premium brand carousel — the hero moment of the marketplace card. Plays the
 * brand's showreel video first (muted, looping) when present, then crossfades
 * through the cover image and gallery photos. Tap toggles play/pause on video.
 * Dots indicate the current slide. Falls back to a clean gradient stage when
 * the brand hasn't uploaded any media yet.
 */
function BrandCarousel({ brand }: { brand: BrandProfile }) {
  const [index, setIndex] = useState<number>(0);
  const [playing, setPlaying] = useState<boolean>(true);
  const videoRef = useRef<HTMLVideoElement | null>(null);

  // Build the slide list: video first (if any), then cover, then gallery.
  const hasVideo = !!brand.video_url;
  const imageSlides: string[] = [
    ...(brand.cover_url ? [brand.cover_url] : []),
    ...brand.media_urls,
  ];
  const totalSlides = (hasVideo ? 1 : 0) + imageSlides.length;

  const togglePlay = () => {
    const v = videoRef.current;
    if (!v) return;
    if (v.paused) {
      void v.play();
      setPlaying(true);
    } else {
      v.pause();
      setPlaying(false);
    }
  };

  // When there's no media at all, show a branded gradient stage with the logo.
  if (totalSlides === 0) {
    return (
      <div className="relative aspect-[16/10] w-full overflow-hidden rounded-[16px] bg-gradient-to-br from-foreground/8 via-card to-foreground/5">
        <div className="absolute inset-0 flex items-center justify-center">
          {brand.logo_url ? (
            <img
              src={brand.logo_url}
              alt=""
              className="h-16 w-16 rounded-2xl object-cover opacity-90 shadow-lg"
            />
          ) : (
            <Building2 className="h-9 w-9 text-muted-foreground/40" />
          )}
        </div>
        <div className="absolute inset-x-0 bottom-0 h-20 bg-gradient-to-t from-black/40 to-transparent" />
      </div>
    );
  }

  return (
    <div className="relative aspect-[16/10] w-full overflow-hidden rounded-[16px] bg-black">
      {/* Video slide */}
      {hasVideo && index === 0 && (
        <video
          ref={videoRef}
          src={brand.video_url ?? undefined}
          autoPlay
          muted
          loop
          playsInline
          className="h-full w-full object-cover"
        />
      )}
      {/* Image slides */}
      {imageSlides.length > 0 && (
        <img
          src={imageSlides[Math.max(0, index - (hasVideo ? 1 : 0))]}
          alt=""
          className={`absolute inset-0 h-full w-full object-cover transition-opacity duration-500 ${
            hasVideo && index === 0 ? "opacity-0" : "opacity-100"
          }`}
        />
      )}

      {/* Bottom gradient for legibility */}
      <div className="pointer-events-none absolute inset-x-0 bottom-0 h-24 bg-gradient-to-t from-black/55 to-transparent" />

      {/* Video play/pause control */}
      {hasVideo && index === 0 && (
        <button
          onClick={(e) => {
            e.preventDefault();
            togglePlay();
          }}
          className="absolute bottom-3 right-3 flex h-9 w-9 items-center justify-center rounded-full bg-white/15 backdrop-blur-md transition-transform active:scale-95"
          aria-label={playing ? "Pause" : "Play"}
        >
          {playing ? (
            <Pause className="h-4 w-4 text-white" />
          ) : (
            <Play className="h-4 w-4 text-white" />
          )}
        </button>
      )}

      {/* Slide dots */}
      {totalSlides > 1 && (
        <div className="absolute bottom-3 left-3 flex gap-1.5">
          {Array.from({ length: totalSlides }).map((_, i) => (
            <button
              key={i}
              onClick={(e) => {
                e.preventDefault();
                setIndex(i);
                if (i === 0 && hasVideo) setPlaying(true);
              }}
              className={`h-1.5 rounded-full transition-all ${
                i === index ? "w-5 bg-white" : "w-1.5 bg-white/50"
              }`}
              aria-label={`Slide ${i + 1}`}
            />
          ))}
        </div>
      )}

      {/* Click-to-advance for image-only brands */}
      {!hasVideo && totalSlides > 1 && (
        <button
          onClick={(e) => {
            e.preventDefault();
            setIndex((i) => (i + 1) % totalSlides);
          }}
          className="absolute inset-0 cursor-default"
          aria-label="Next slide"
        />
      )}
    </div>
  );
}

/**
 * Premium brand card — the marketplace centerpiece. Full-bleed carousel on
 * top, brand identity + Ember verification + transparent pay, requirement
 * chips along the bottom — and, when the brand runs Business+ hiring, a
 * mint "Hiring" chip that jumps straight to their application page.
 */
function BrandCard({
  brand,
  hiringCount = 0,
}: {
  brand: BrandProfile;
  hiringCount?: number;
}) {
  const navigate = useNavigate();
  const pay = typicalPayText(brand);
  const slides = [
    ...(brand.cover_url ? [brand.cover_url] : []),
    ...brand.media_urls,
  ];
  return (
    <Link
      to={`/brands/${brand.user_id}`}
      className="group block overflow-hidden rounded-[28px] border border-border bg-card shadow-[0_6px_24px_rgba(0,0,0,0.06)] transition-all hover:-translate-y-0.5 hover:shadow-[0_18px_50px_rgba(0,0,0,0.12)] active:scale-[0.99]"
    >
      <div className="p-2">
        <BrandCarousel brand={brand} />
      </div>

      <div className="px-4 pb-5 pt-3">
        <div className="flex items-start gap-3">
          <div
            className="flex shrink-0 items-center justify-center overflow-hidden rounded-2xl bg-secondary ring-2 ring-card"
            style={{ width: 52, height: 52 }}
          >
            {brand.logo_url ? (
              <img
                src={brand.logo_url}
                alt=""
                className="h-full w-full object-cover"
              />
            ) : (
              <Building2 className="h-5 w-5 text-indigo-500/60" />
            )}
          </div>
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-1.5">
              <p className="truncate text-[17px] font-black tracking-tight">
                {brand.company_name}
              </p>
              <span className="flex h-[18px] w-[18px] shrink-0 items-center justify-center rounded-full bg-indigo-500">
                <Briefcase className="h-2.5 w-2.5 text-white" />
              </span>
            </div>
            <div className="mt-0.5 flex flex-wrap items-center gap-1.5">
              {brand.industry && (
                <span className="text-[12.5px] font-semibold text-muted-foreground">
                  {brand.industry}
                </span>
              )}
              {brand.ember_verified && (
                <span className="inline-flex items-center gap-0.5 rounded-full bg-orange-500/12 px-1.5 py-0.5 text-[10px] font-bold text-orange-500">
                  <Flame className="h-2.5 w-2.5" /> Ember verified
                </span>
              )}
            </div>
          </div>
          <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5" />
        </div>

        {brand.about && (
          <p className="mt-3 line-clamp-2 text-[13px] leading-relaxed text-muted-foreground">
            {brand.about}
          </p>
        )}

        {pay && (
          <div className="mt-3 flex items-center gap-1.5 rounded-xl bg-emerald-500/8 px-3 py-2">
            <span className="text-[13px] font-bold text-emerald-600">
              Typically pays {pay}
            </span>
          </div>
        )}

        <div className="mt-3 flex flex-wrap items-center gap-1.5">
          {hiringCount > 0 && (
            <button
              onClick={(e) => {
                e.preventDefault();
                navigate(
                  `/work-with/${brand.user_id}?co=${encodeURIComponent(brand.company_name)}`
                );
              }}
              className="inline-flex items-center gap-1 rounded-full bg-emerald-600 px-2.5 py-1 text-[11px] font-black text-white transition-transform active:scale-95"
            >
              <Sparkles className="h-3 w-3" />
              Hiring · {hiringCount} {hiringCount === 1 ? "role" : "roles"}
            </button>
          )}
          <span className="rounded-full border border-border px-2.5 py-0.5 text-[11px] font-semibold text-muted-foreground">
            {brand.min_followers.toLocaleString()}+ followers
          </span>
          <span className="rounded-full border border-border px-2.5 py-0.5 text-[11px] font-semibold text-muted-foreground">
            {brand.min_age}+
          </span>
          {brand.min_posts > 0 && (
            <span className="rounded-full border border-border px-2.5 py-0.5 text-[11px] font-semibold text-muted-foreground">
              {brand.min_posts}+ posts
            </span>
          )}
          {slides.length > 0 && (
            <span className="ml-auto rounded-full bg-foreground/5 px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-wider text-muted-foreground">
              {slides.length} showcase {slides.length === 1 ? "image" : "photos"}
            </span>
          )}
        </div>
      </div>
    </Link>
  );
}

/**
 * The athlete rail — verified athletes surfaced to every brand browsing the
 * marketplace. This is the athlete badge's marketplace value: hold the badge,
 * get seen by the companies writing sponsorship checks.
 */
function AthleteSpotlight() {
  const athletesQuery = useQuery({
    queryKey: ["marketplace-athletes"],
    staleTime: 5 * 60_000,
    queryFn: async (): Promise<WhisperProfile[]> => {
      const { data } = await supabase
        .from("whisper_profiles")
        .select("user_id, username, display_name, profile_image_url, is_athlete")
        .eq("is_athlete", true)
        .limit(12);
      return (data as WhisperProfile[] | null) ?? [];
    },
  });
  const athletes = athletesQuery.data ?? [];
  if (athletes.length === 0) return null;

  return (
    <div className="mt-4">
      <div className="flex items-baseline justify-between">
        <p className="flex items-center gap-1.5 text-[11px] font-black uppercase tracking-[0.16em] text-red-500">
          <Sparkles className="h-3.5 w-3.5" />
          Athletes open to sponsorship
        </p>
        <span className="text-[11px] font-semibold text-muted-foreground">
          Verified · pitch them in DMs
        </span>
      </div>
      <div className="no-scrollbar -mx-4 mt-2 flex gap-2.5 overflow-x-auto px-4 pb-1">
        {athletes.map((a) => (
          <Link
            key={a.user_id}
            to={`/u/${a.username}`}
            className="flex w-[104px] shrink-0 flex-col items-center gap-1.5 rounded-[18px] border border-border bg-card px-2 py-3 transition-colors hover:bg-secondary/40"
          >
            <Avatar
              url={a.profile_image_url}
              name={a.username}
              size={56}
            />
            <span className="flex w-full items-center justify-center gap-1">
              <span className="min-w-0 truncate text-[12.5px] font-bold">
                {a.display_name || a.username}
              </span>
              <SealBadge
                size={13}
                colors={["#ff5a70", "#ed3b52"]}
                shadowColor="#ed3b52"
                title="Verified Athlete"
              >
                <Medal style={{ width: 6.5, height: 6.5 }} strokeWidth={3} />
              </SealBadge>
            </span>
            <span className="w-full truncate text-center text-[11px] text-muted-foreground">
              @{a.username}
            </span>
          </Link>
        ))}
      </div>
    </div>
  );
}

type BrandSort = "featured" | "pay" | "open";

const SORT_LABELS: Record<BrandSort, string> = {
  featured: "Featured",
  pay: "Top pay",
  open: "Easiest to join",
};

/**
 * The brand marketplace — searchable, filterable by industry, sorted by
 * what matters (verification, pay, accessibility), with Ember-verified
 * brands spotlighted up top and Business+ hiring woven straight in.
 */
export default function Brands() {
  const { user } = useAuth();
  const [query, setQuery] = useState<string>("");
  const [industry, setIndustry] = useState<string | null>(null);
  const [sort, setSort] = useState<BrandSort>("featured");

  const brandsQuery = useQuery({
    queryKey: ["brands"],
    queryFn: () => fetchBrands(),
  });

  const myBrandQuery = useQuery({
    queryKey: ["brand", user?.id ?? ""],
    queryFn: () => fetchBrand(user!.id),
    enabled: !!user?.id,
  });

  const brands = useMemo(() => brandsQuery.data ?? [], [brandsQuery.data]);

  const hiringQuery = useQuery({
    queryKey: ["brand-hiring", brands.map((b) => b.user_id)],
    queryFn: () => fetchHiringCounts(brands.map((b) => b.user_id)),
    enabled: brands.length > 0,
  });
  const hiring = hiringQuery.data ?? {};

  const industries = useMemo(() => {
    const set = new Set<string>();
    for (const b of brands) {
      const label = b.industry?.trim();
      if (label) set.add(label);
    }
    return Array.from(set).sort((a, b) => a.localeCompare(b));
  }, [brands]);

  const shown = useMemo(() => {
    const q = query.trim().toLowerCase();
    const list = brands.filter((b) => {
      if (industry && (b.industry ?? "").trim() !== industry) return false;
      if (!q) return true;
      return (
        b.company_name.toLowerCase().includes(q) ||
        (b.industry ?? "").toLowerCase().includes(q) ||
        (b.about ?? "").toLowerCase().includes(q)
      );
    });
    const payOf = (b: BrandProfile): number =>
      b.typical_pay_max_cents ?? b.typical_pay_min_cents ?? 0;
    if (sort === "pay") {
      list.sort((a, b) => payOf(b) - payOf(a));
    } else if (sort === "open") {
      list.sort((a, b) => a.min_followers - b.min_followers);
    } else {
      list.sort((a, b) => {
        if (a.ember_verified !== b.ember_verified) return a.ember_verified ? -1 : 1;
        const hireDiff = (hiring[b.user_id] ?? 0) - (hiring[a.user_id] ?? 0);
        if (hireDiff !== 0) return hireDiff;
        return payOf(b) - payOf(a);
      });
    }
    return list;
  }, [brands, query, industry, sort, hiring]);

  // Featured = Ember-verified, only meaningful on the default sort with no
  // active search/filter — otherwise everything renders as one honest list.
  const showFeatured = sort === "featured" && !query.trim() && !industry;
  const featured = showFeatured ? shown.filter((b) => b.ember_verified) : [];
  const rest = showFeatured ? shown.filter((b) => !b.ember_verified) : shown;

  const hiringBrandCount = useMemo(
    () => brands.filter((b) => (hiring[b.user_id] ?? 0) > 0).length,
    [brands, hiring]
  );

  return (
    <div>
      <Header title="Brand marketplace" />
      <div className="mx-auto w-full max-w-xl px-4 pb-24 pt-3">
        {/* Live stats strip */}
        <div className="flex items-center gap-2 overflow-x-auto pb-1">
          <span className="shrink-0 rounded-full bg-indigo-500/10 px-3 py-1.5 text-[12px] font-bold text-indigo-500">
            {brands.length} {brands.length === 1 ? "brand" : "brands"} live
          </span>
          {hiringBrandCount > 0 && (
            <span className="shrink-0 rounded-full bg-emerald-500/10 px-3 py-1.5 text-[12px] font-bold text-emerald-600">
              {hiringBrandCount} hiring now
            </span>
          )}
          <span className="shrink-0 rounded-full bg-orange-500/10 px-3 py-1.5 text-[12px] font-bold text-orange-500">
            {brands.filter((b) => b.ember_verified).length} Ember verified
          </span>
        </div>

        {/* Company door — manage your listing + the suite it lives with */}
        <div className="mt-3 rounded-[20px] border border-indigo-500/25 bg-indigo-500/5 p-4">
          <p className="text-[14px] font-extrabold">
            {myBrandQuery.data ? "Your brand is live" : "Are you a company?"}
          </p>
          <p className="mt-1 text-[12.5px] leading-snug text-muted-foreground">
            {myBrandQuery.data
              ? "Your marketplace card, applications, deals, and escrow all run from your dashboard — and the Business Suite runs your ads and Business+ team beside it."
              : "List your brand here, set requirements and transparent pay, and let eligible creators apply — escrow protects both sides. Your listing lives beside your ads in the Business Suite."}
          </p>
          <div className="mt-3 flex flex-wrap gap-2">
            <Link
              to={myBrandQuery.data ? "/brand/dashboard" : "/brand/signup"}
              className="inline-flex items-center gap-1.5 rounded-full bg-indigo-500 px-4 py-2 text-[13px] font-bold text-white transition-transform active:scale-[0.97]"
            >
              {myBrandQuery.data ? (
                <>Brand dashboard</>
              ) : (
                <>
                  <Plus className="h-3.5 w-3.5" /> Create brand profile
                </>
              )}
            </Link>
            <button
              onClick={() => void openPortal("business")}
              className="inline-flex items-center gap-1.5 rounded-full border border-border bg-card px-4 py-2 text-[13px] font-bold transition-transform active:scale-[0.97]"
            >
              <BriefcaseBusiness className="h-3.5 w-3.5" />
              Business Suite
              <ArrowUpRight className="h-3 w-3 text-muted-foreground" />
            </button>
            <Link
              to="/sponsorships"
              className="inline-flex items-center rounded-full border border-border bg-card px-4 py-2 text-[13px] font-bold transition-transform active:scale-[0.97]"
            >
              My sponsorships
            </Link>
          </div>
        </div>

        {/* Verified athletes — the badge's marketplace value */}
        <AthleteSpotlight />

        {/* Search + sort + industry filters */}
        <div className="sticky top-14 z-10 -mx-4 mt-4 border-b border-border bg-background/95 px-4 pb-2.5 pt-2 backdrop-blur">
          <div className="flex items-center gap-2">
            <div className="flex h-10 flex-1 items-center gap-2 rounded-full bg-secondary px-3.5">
              <Search className="h-4 w-4 shrink-0 text-muted-foreground" />
              <input
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Search brands, industries…"
                className="w-full bg-transparent text-[14px] outline-none placeholder:text-muted-foreground"
              />
            </div>
            <div className="flex shrink-0 rounded-full bg-secondary p-0.5">
              {(Object.keys(SORT_LABELS) as BrandSort[]).map((s) => (
                <button
                  key={s}
                  onClick={() => setSort(s)}
                  className={cn(
                    "rounded-full px-2.5 py-1.5 text-[11px] font-bold transition-colors",
                    sort === s
                      ? "bg-background text-foreground shadow-sm"
                      : "text-muted-foreground"
                  )}
                >
                  {SORT_LABELS[s]}
                </button>
              ))}
            </div>
          </div>
          {industries.length > 0 && (
            <div className="no-scrollbar -mx-1 mt-2 flex gap-1.5 overflow-x-auto px-1">
              <button
                onClick={() => setIndustry(null)}
                className={cn(
                  "shrink-0 rounded-full border px-3 py-1 text-[12px] font-bold transition-colors",
                  industry === null
                    ? "border-foreground bg-foreground text-background"
                    : "border-border bg-card text-muted-foreground"
                )}
              >
                All
              </button>
              {industries.map((label) => (
                <button
                  key={label}
                  onClick={() => setIndustry(industry === label ? null : label)}
                  className={cn(
                    "shrink-0 rounded-full border px-3 py-1 text-[12px] font-bold transition-colors",
                    industry === label
                      ? "border-foreground bg-foreground text-background"
                      : "border-border bg-card text-muted-foreground"
                  )}
                >
                  {label}
                </button>
              ))}
            </div>
          )}
        </div>

        <div className="mt-5 space-y-4">
          {brandsQuery.isLoading ? (
            <div className="flex justify-center py-16">
              <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
            </div>
          ) : shown.length === 0 ? (
            <div className="py-16 text-center">
              <Building2 className="mx-auto h-8 w-8 text-muted-foreground" />
              <p className="mt-3 text-[15px] font-bold">
                {brands.length === 0 ? "No brands yet" : "Nothing matches"}
              </p>
              <p className="mx-auto mt-1 max-w-xs text-[13px] text-muted-foreground">
                {brands.length === 0
                  ? "Brands that join Whisper appear here with their requirements and typical pay — so you always know what a partnership is worth before you apply."
                  : "Try a different search or clear the industry filter."}
              </p>
            </div>
          ) : (
            <>
              {featured.length > 0 && (
                <>
                  <p className="flex items-center gap-1.5 text-[11px] font-black uppercase tracking-[0.16em] text-orange-500">
                    <Flame className="h-3.5 w-3.5" />
                    Featured — Ember verified
                  </p>
                  {featured.map((brand) => (
                    <BrandCard
                      key={brand.user_id}
                      brand={brand}
                      hiringCount={hiring[brand.user_id] ?? 0}
                    />
                  ))}
                  {rest.length > 0 && (
                    <p className="pt-2 text-[11px] font-black uppercase tracking-[0.16em] text-muted-foreground">
                      All brands
                    </p>
                  )}
                </>
              )}
              {rest.map((brand) => (
                <BrandCard
                  key={brand.user_id}
                  brand={brand}
                  hiringCount={hiring[brand.user_id] ?? 0}
                />
              ))}
            </>
          )}
        </div>
      </div>
    </div>
  );
}
