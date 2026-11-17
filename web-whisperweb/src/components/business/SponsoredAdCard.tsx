/**
 * The sponsored card Whisper serves into the feed — Instagram's photo/video
 * ad grammar: advertiser header with "Sponsored", the creative full-bleed at
 * its own ratio (video autoplays muted in view with a mute toggle), the CTA
 * bar directly under the media (tints to ink a few seconds after it's on
 * screen — Instagram's cue), the action row, and the caption led by the
 * business name. The ⋯ opens the ad sheet: Hide ad · Report ad · Why you're
 * seeing this ad · About Whisper ads · Ad Library.
 *
 * Impressions are tracked once per session per ad; CTA clicks are tracked and
 * open the advertiser's link. Every placement carries a clear "Ad" tag.
 */
import { useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import {
  Bookmark,
  Building2,
  ChevronRight,
  EyeOff,
  Flag,
  Heart,
  Info,
  Library,
  MoreHorizontal,
  Send,
  Volume2,
  VolumeX,
} from "lucide-react";
import { toast } from "sonner";

import { cn } from "@/lib/utils";
import { ActiveAd, externalUrl, trackAdClick, trackAdImpression } from "@/lib/business";
import { submitBugReport } from "@/lib/reports";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

interface SponsoredAdCardProps {
  ad: ActiveAd;
  /** Preview mode (ads manager) — no tracking, no external nav. */
  preview?: boolean;
  className?: string;
}

/** The small neutral "Ad" tag every sponsored surface wears. */
export function AdCornerTag({ dark = false }: { dark?: boolean }) {
  return (
    <span
      className={
        dark
          ? "rounded-md bg-black/50 px-1.5 py-0.5 text-[9.5px] font-black uppercase tracking-wide text-white/90 backdrop-blur-sm"
          : "rounded-md border border-border/60 bg-muted/60 px-1.5 py-0.5 text-[9.5px] font-black uppercase tracking-wide text-muted-foreground"
      }
    >
      Ad
    </span>
  );
}

/** Instagram's accepted creative ratios: 4:5 portrait … 1.91:1 landscape. */
function clampRatio(width: number, height: number): number {
  if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) return 1;
  return Math.min(1.91, Math.max(0.8, width / height));
}

const CTA_HOT_DELAY_MS = 3000;

export function SponsoredAdCard({ ad, preview = false, className = "" }: SponsoredAdCardProps) {
  const rootRef = useRef<HTMLElement | null>(null);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const mutedRef = useRef<boolean>(true);
  const [hidden, setHidden] = useState<boolean>(false);
  const [liked, setLiked] = useState<boolean>(false);
  const [saved, setSaved] = useState<boolean>(false);
  const [expanded, setExpanded] = useState<boolean>(false);
  const [ctaHot, setCtaHot] = useState<boolean>(false);
  const [muted, setMuted] = useState<boolean>(true);
  const [whyOpen, setWhyOpen] = useState<boolean>(false);
  const [aspect, setAspect] = useState<number>(1);
  const [reporting, setReporting] = useState<boolean>(false);

  const isVideo = ad.media_type === "video" && !!ad.video_url;
  const hasMedia = isVideo || !!ad.image_url;
  const destination = externalUrl(ad.cta_url) ?? externalUrl(ad.business_website);

  // Play the creative only while it's mostly on screen, and tint the CTA bar
  // to ink ~3s after the card lands in view — Instagram's grammar.
  useEffect(() => {
    const el = rootRef.current;
    if (!el || hidden || typeof IntersectionObserver === "undefined") return;
    let timer: number | null = null;
    let impressionTimer: number | null = null;
    let inView = false;
    const video = videoRef.current;
    const update = (): void => {
      if (inView && document.visibilityState === "visible") {
        if (timer === null) timer = window.setTimeout(() => setCtaHot(true), CTA_HOT_DELAY_MS);
        if (!preview && impressionTimer === null) impressionTimer = window.setTimeout(() => trackAdImpression(ad.id), 1000);
        if (video) {
          video.muted = mutedRef.current;
          void video.play().catch(() => {});
        }
      } else {
        if (timer !== null) window.clearTimeout(timer);
        if (impressionTimer !== null) window.clearTimeout(impressionTimer);
        timer = null;
        impressionTimer = null;
        setCtaHot(false);
        video?.pause();
      }
    };
    const io = new IntersectionObserver((entries) => {
      inView = (entries[0]?.intersectionRatio ?? 0) >= 0.5;
      update();
    }, { threshold: [0, 0.5] });
    io.observe(el);
    document.addEventListener("visibilitychange", update);
    return () => {
      io.disconnect();
      document.removeEventListener("visibilitychange", update);
      video?.pause();
      if (timer !== null) window.clearTimeout(timer);
      if (impressionTimer !== null) window.clearTimeout(impressionTimer);
    };
  }, [ad.id, ad.video_url, hidden, preview]);

  const openDestination = (): void => {
    if (preview || !destination) return;
    trackAdClick(ad.id);
    window.open(destination, "_blank", "noopener,noreferrer");
  };

  const toggleMute = (): void => {
    const next = !muted;
    mutedRef.current = next;
    setMuted(next);
    const video = videoRef.current;
    if (video) {
      video.muted = next;
      if (!next) void video.play().catch(() => {});
    }
  };

  const share = async (): Promise<void> => {
    const link = destination ?? `${window.location.origin}/ad-library`;
    try {
      await navigator.clipboard.writeText(link);
      toast("Link copied");
    } catch {
      toast("Couldn't copy the link");
    }
  };

  const reportAd = async (): Promise<void> => {
    if (preview || reporting) return;
    setReporting(true);
    try {
      const result = await submitBugReport({
        category: "other",
        details: `Ad report — "${ad.headline}" by ${ad.business_name} (ad ${ad.id}).`,
        includeEnvironment: false,
        context: { surface: "sponsored-ad", adId: ad.id, path: window.location.pathname },
      });
      if (result === "filed") {
        toast("Thanks — we'll review this ad");
        setHidden(true);
      } else {
        toast.error("Your report wasn't sent. Please try again later.");
      }
    } catch {
      toast.error("Your report wasn't sent. Please try again.");
    } finally {
      setReporting(false);
    }
  };

  if (hidden) {
    return (
      <div
        className={cn(
          "flex items-center justify-between gap-3 border-b border-border bg-background px-4 py-3 text-[13px] text-muted-foreground",
          className
        )}
      >
        <span>Ad hidden for this visit.</span>
        <button
          type="button"
          onClick={() => setHidden(false)}
          className="shrink-0 font-semibold text-foreground"
        >
          Undo
        </button>
      </div>
    );
  }

  const bodyIsLong = (ad.body?.length ?? 0) > 90;

  return (
    <article ref={rootRef} className={cn("relative border-b border-border bg-background", className)}>
      {/* Header — logo · business name · Sponsored · Ad tag · ⋯ */}
      <div className="flex items-center justify-between px-3 py-3">
        <button
          type="button"
          onClick={openDestination}
          className="flex min-w-0 items-center gap-2.5 text-left"
          aria-label={`Open ${ad.business_name}`}
        >
          {ad.business_logo_url ? (
            <img
              src={ad.business_logo_url}
              alt={ad.business_name}
              className="h-9 w-9 shrink-0 rounded-full border border-border/50 object-cover"
              loading="lazy"
            />
          ) : (
            <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-secondary">
              <Building2 className="h-4 w-4 text-muted-foreground" />
            </span>
          )}
          <span className="min-w-0">
            <span className="block truncate text-[13.5px] font-bold leading-tight">{ad.business_name}</span>
            <span className="block text-[12px] leading-tight text-muted-foreground">Sponsored</span>
          </span>
        </button>
        <div className="flex items-center gap-1">
          <AdCornerTag />
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <button
                type="button"
                className="flex h-8 w-8 items-center justify-center rounded-full transition-colors active:scale-90"
                aria-label="Ad options"
              >
                <MoreHorizontal className="h-5 w-5" />
              </button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-60">
              <DropdownMenuItem disabled={preview} onClick={() => setHidden(true)}>
                <EyeOff className="mr-2 h-4 w-4" />
                Hide ad
              </DropdownMenuItem>
              <DropdownMenuItem disabled={preview || reporting} onClick={() => void reportAd()}>
                <Flag className="mr-2 h-4 w-4" />
                Report ad
              </DropdownMenuItem>
              <DropdownMenuItem onClick={() => setWhyOpen((v) => !v)}>
                <Info className="mr-2 h-4 w-4" />
                Why you're seeing this ad
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem asChild>
                <Link to="/faq">
                  <Info className="mr-2 h-4 w-4" />
                  About Whisper ads
                </Link>
              </DropdownMenuItem>
              <DropdownMenuItem asChild>
                <Link to="/ad-library">
                  <Library className="mr-2 h-4 w-4" />
                  Ad Library
                </Link>
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      </div>

      {/* Creative — full-bleed at its own ratio (4:5 … 1.91:1) */}
      {hasMedia && (
        <div
          className="relative w-full cursor-pointer overflow-hidden bg-black"
          style={{ aspectRatio: String(aspect) }}
          onClick={openDestination}
          role="button"
          tabIndex={preview ? -1 : 0}
          onKeyDown={(event) => {
            if (event.target !== event.currentTarget) return;
            if (event.key === "Enter" || event.key === " ") { event.preventDefault(); openDestination(); }
          }}
          aria-label={ad.cta_label || "Learn more"}
        >
          {isVideo ? (
            <>
              <video
                ref={videoRef}
                src={ad.video_url ?? undefined}
                poster={ad.image_url ?? undefined}
                muted
                loop
                playsInline
                preload="metadata"
                onLoadedMetadata={(e) =>
                  setAspect(clampRatio(e.currentTarget.videoWidth, e.currentTarget.videoHeight))
                }
                className="h-full w-full object-cover"
              />
              <button
                type="button"
                onClick={(e) => {
                  e.stopPropagation();
                  toggleMute();
                }}
                className="absolute bottom-3 right-3 flex h-8 w-8 items-center justify-center rounded-full bg-black/60 text-white backdrop-blur-sm transition-transform active:scale-90"
                aria-label={muted ? "Unmute" : "Mute"}
              >
                {muted ? <VolumeX className="h-4 w-4" /> : <Volume2 className="h-4 w-4" />}
              </button>
            </>
          ) : (
            <img
              src={ad.image_url ?? undefined}
              alt={ad.headline}
              onLoad={(e) => setAspect(clampRatio(e.currentTarget.naturalWidth, e.currentTarget.naturalHeight))}
              className="h-full w-full object-cover"
              loading="lazy"
              draggable={false}
            />
          )}
        </div>
      )}

      {/* CTA bar — right under the media, tints to ink once it's been seen */}
      <button
        type="button"
        onClick={openDestination}
        className={cn(
          "flex w-full items-center justify-between px-3 py-3 text-[13.5px] font-semibold transition-colors duration-500",
          ctaHot ? "bg-foreground text-background" : "bg-secondary text-foreground"
        )}
      >
        <span>{ad.cta_label || "Learn more"}</span>
        <ChevronRight className="h-4 w-4" />
      </button>

      {/* Action row — heart · share | bookmark */}
      <div className="flex items-center justify-between px-3 pt-3">
        <div className="flex items-center gap-4">
          <button
            type="button"
            onClick={() => setLiked((v) => !v)}
            aria-pressed={liked}
            aria-label={liked ? "Unlike" : "Like"}
            className="transition-transform active:scale-90"
          >
            <Heart
              className={cn(
                "h-6 w-6 transition-colors",
                liked ? "fill-[#F22659] text-[#F22659]" : "text-foreground"
              )}
            />
          </button>
          <button
            type="button"
            onClick={() => void share()}
            aria-label="Share"
            className="transition-transform active:scale-90"
          >
            <Send className="h-6 w-6" />
          </button>
        </div>
        <button
          type="button"
          onClick={() => setSaved((v) => !v)}
          aria-pressed={saved}
          aria-label={saved ? "Unsave" : "Save"}
          className="transition-transform active:scale-90"
        >
          <Bookmark className={cn("h-6 w-6", saved && "fill-foreground")} />
        </button>
      </div>

      {/* Caption — business name bold, then the headline + body */}
      <div className="px-3 pb-3 pt-2">
        <p className="text-[13.5px] leading-snug">
          <span className="font-bold">{ad.business_name}</span>{" "}
          <span className="font-semibold">{ad.headline}</span>
        </p>
        {ad.body && (
          <p
            className={cn(
              "mt-0.5 whitespace-pre-line text-[13.5px] leading-snug text-foreground/90",
              !expanded && "line-clamp-2"
            )}
          >
            {ad.body}
          </p>
        )}
        {ad.body && bodyIsLong && !expanded && (
          <button
            type="button"
            onClick={() => setExpanded(true)}
            className="mt-0.5 text-[13px] text-muted-foreground"
          >
            more
          </button>
        )}
      </div>

      {/* Why you're seeing this ad — inline disclosure */}
      {whyOpen && (
        <div className="mx-3 mb-3 rounded-2xl border border-border bg-secondary/40 p-3 text-[12.5px] leading-relaxed text-muted-foreground">
          <p className="font-semibold text-foreground">Why you're seeing this ad</p>
          <p className="mt-1">
            This is a paid placement from {ad.business_name}. The ad rotation can use account roles
            and follower ranges selected by advertisers. Hiding this card only affects this visit;
            it does not change your saved advertising preferences.
          </p>
          <div className="mt-2 flex items-center gap-3">
            <Link to="/ad-library" className="font-semibold text-foreground">
              Ad Library
            </Link>
            <Link to="/faq" className="font-semibold text-foreground">
              Learn more
            </Link>
            <button
              type="button"
              onClick={() => setWhyOpen(false)}
              className="ml-auto font-semibold text-foreground"
            >
              Close
            </button>
          </div>
        </div>
      )}
    </article>
  );
}
