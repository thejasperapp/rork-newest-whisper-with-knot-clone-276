import { useState } from "react";
import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { BookOpen, Building2, ExternalLink, Search } from "lucide-react";

import { WhisperLogo } from "@/components/WhisperLogo";
import {
  fetchAdsLibrary,
  externalUrl,
  type AdLibraryEntry,
} from "@/lib/business";

const ACCENT = "#5A5FE8";

const PLACEMENT_LABELS: Record<string, string> = {
  feed: "Feed",
  reels: "Reels",
  comments: "Comments",
  discover: "Discover",
};

function LibraryCard({ ad }: { ad: AdLibraryEntry }) {
  const destination = externalUrl(ad.cta_url);
  const started = new Date(ad.started_at);
  return (
    <div className="flex flex-col overflow-hidden rounded-[20px] border border-border/60 bg-card">
      <div className="flex items-center gap-2.5 px-3.5 pt-3">
        {ad.business_logo_url ? (
          <img
            src={ad.business_logo_url}
            alt={ad.business_name}
            className="h-8 w-8 shrink-0 rounded-full border border-border/50 object-cover"
            loading="lazy"
          />
        ) : (
          <span
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full"
            style={{ backgroundColor: `${ACCENT}18`, color: ACCENT }}
          >
            <Building2 className="h-4 w-4" />
          </span>
        )}
        <div className="min-w-0 flex-1">
          <p className="truncate text-[13px] font-bold leading-tight">
            {ad.business_name}
          </p>
          <p className="text-[10px] font-semibold text-muted-foreground">
            Running since{" "}
            {started.toLocaleDateString(undefined, {
              month: "short",
              day: "numeric",
              year: "numeric",
            })}
          </p>
        </div>
        <span
          className="shrink-0 rounded-full px-2 py-0.5 text-[9.5px] font-black uppercase tracking-wide"
          style={{ color: ACCENT, backgroundColor: `${ACCENT}14` }}
        >
          Active
        </span>
      </div>

      {ad.media_type === "video" && ad.video_url ? (
        <div className="mt-2.5 px-3.5">
          <video
            src={ad.video_url}
            poster={ad.image_url ?? undefined}
            muted
            loop
            playsInline
            autoPlay
            className="aspect-[16/9] w-full rounded-xl border border-border/40 bg-black object-cover"
          />
        </div>
      ) : ad.image_url ? (
        <div className="mt-2.5 px-3.5">
          <img
            src={ad.image_url}
            alt={ad.headline}
            className="aspect-[16/9] w-full rounded-xl border border-border/40 object-cover"
            loading="lazy"
          />
        </div>
      ) : null}

      <div className="flex flex-1 flex-col px-3.5 pb-3.5 pt-2.5">
        <p className="text-[13.5px] font-extrabold leading-snug">
          {ad.headline}
        </p>
        {ad.body && (
          <p className="mt-1 line-clamp-2 text-[11.5px] leading-relaxed text-muted-foreground">
            {ad.body}
          </p>
        )}
        <div className="mt-2 flex flex-wrap items-center gap-1.5">
          {ad.placements.map((p) => (
            <span
              key={p}
              className="rounded-full bg-muted/70 px-2 py-0.5 text-[9.5px] font-bold uppercase tracking-wide text-muted-foreground"
            >
              {PLACEMENT_LABELS[p] ?? p}
            </span>
          ))}
          <span className="rounded-full bg-muted/70 px-2 py-0.5 text-[9.5px] font-bold uppercase tracking-wide text-muted-foreground">
            {ad.objective}
          </span>
        </div>
        {destination && (
          <a
            href={destination}
            target="_blank"
            rel="noreferrer"
            className="mt-2.5 inline-flex items-center gap-1 text-[11.5px] font-bold"
            style={{ color: ACCENT }}
          >
            {ad.cta_label || "Learn more"}
            <ExternalLink className="h-3 w-3" />
          </a>
        )}
      </div>
    </div>
  );
}

/**
 * The Whisper Ad Library — a PUBLIC, searchable registry of every ad
 * currently live on the platform, exactly like Meta's transparency
 * library. No sign-in required; nothing here counts as ad delivery.
 */
export default function AdLibrary() {
  const [query, setQuery] = useState<string>("");
  const [submitted, setSubmitted] = useState<string>("");

  const libraryQuery = useQuery({
    queryKey: ["ads-library", submitted],
    queryFn: () => fetchAdsLibrary(submitted, 60),
  });

  const ads = libraryQuery.data ?? [];

  return (
    <div className="mx-auto w-full max-w-5xl px-4 py-8 lg:py-10">
      <div className="flex items-center gap-2.5">
        <WhisperLogo size={26} variant="wordmark" />
        <span
          className="rounded-full px-2.5 py-1 text-[10px] font-black uppercase tracking-[0.14em]"
          style={{ color: ACCENT, backgroundColor: `${ACCENT}1a` }}
        >
          Ad Library
        </span>
      </div>
      <h1 className="mt-4 font-display text-[26px] font-extrabold leading-tight sm:text-[30px]">
        Every ad running on Whisper. Public.
      </h1>
      <p className="mt-1.5 max-w-xl text-[13.5px] leading-relaxed text-muted-foreground">
        Search any advertiser and see exactly what they're running, where it
        serves, and since when — the same transparency Meta's Ad Library
        gives, built in from day one.
      </p>

      <div className="mt-5 flex h-12 max-w-xl items-center gap-2 rounded-full border border-border bg-card pl-4 pr-1.5">
        <Search className="h-4 w-4 shrink-0 text-muted-foreground" />
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") setSubmitted(query);
          }}
          placeholder="Search advertisers or headlines…"
          className="min-w-0 flex-1 bg-transparent text-[14px] outline-none placeholder:text-muted-foreground/60"
        />
        <button
          onClick={() => setSubmitted(query)}
          className="h-9 shrink-0 rounded-full px-4 text-[12.5px] font-bold text-white transition-transform active:scale-95"
          style={{ backgroundColor: ACCENT }}
        >
          Search
        </button>
      </div>

      {libraryQuery.isLoading && (
        <div className="mt-6 grid grid-cols-1 gap-3.5 sm:grid-cols-2 lg:grid-cols-3">
          {[0, 1, 2, 3, 4, 5].map((i) => (
            <div
              key={i}
              className="h-[220px] animate-pulse rounded-[20px] border border-border/40 bg-muted/40"
            />
          ))}
        </div>
      )}

      {libraryQuery.isError && (
        <div className="mt-6 rounded-[18px] border border-amber-500/40 bg-amber-500/10 px-4 py-3">
          <p className="text-[12.5px] font-semibold leading-relaxed">
            The library needs its one-time setup — run{" "}
            <span className="font-mono font-bold">
              supabase/business-suite-v5.sql
            </span>{" "}
            in the Supabase SQL editor.
          </p>
        </div>
      )}

      {!libraryQuery.isLoading && !libraryQuery.isError && ads.length === 0 && (
        <div className="mt-8 flex flex-col items-center gap-3 rounded-[22px] border border-border/60 bg-card px-6 py-14 text-center">
          <span
            className="flex h-14 w-14 items-center justify-center rounded-2xl"
            style={{ backgroundColor: `${ACCENT}12`, color: ACCENT }}
          >
            <BookOpen className="h-7 w-7" />
          </span>
          <p className="text-[15px] font-extrabold">
            {submitted ? "No live ads match that search" : "No ads live right now"}
          </p>
          <p className="max-w-sm text-[12.5px] leading-relaxed text-muted-foreground">
            {submitted
              ? "Try another advertiser name or headline keyword."
              : "The moment a campaign goes live it appears here for everyone to see."}
          </p>
        </div>
      )}

      {ads.length > 0 && (
        <div className="mt-6 grid grid-cols-1 gap-3.5 sm:grid-cols-2 lg:grid-cols-3">
          {ads.map((ad) => (
            <LibraryCard key={ad.id} ad={ad} />
          ))}
        </div>
      )}

      <p className="mt-8 text-[11px] leading-relaxed text-muted-foreground">
        Library views never bill advertisers or count as delivery. Want your
        business here?{" "}
        <Link to="/business" className="font-bold underline-offset-2 hover:underline" style={{ color: ACCENT }}>
          Open the Business Suite
        </Link>
        .
      </p>
    </div>
  );
}
