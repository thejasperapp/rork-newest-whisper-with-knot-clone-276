import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { ArrowRight, Clapperboard, Film as FilmIcon, Loader2, Play, Sparkles } from "lucide-react";

import { MemberShell, useIsMember } from "@/components/MemberShell";
import { Reveal } from "@/components/Reveal";
import { fetchFilms, formatTimecode, type Film } from "@/lib/films";
import { cn } from "@/lib/utils";

/**
 * Whisper Studios — Featured Film Friday. This is a rare, eventized premiere
 * page, not an always-on feed. The hero only renders when there's a film
 * scheduled for the current or most recent Friday; otherwise the page reads
 * as a quiet "studios" marquee with an archive of past premieres. The
 * presentation is cinema-grade: a full-bleed poster stage, a single
 * play-to-watch CTA, and the festival-style metadata underneath.
 */
export default function Films() {
  const filmsQuery = useQuery({
    queryKey: ["films"],
    queryFn: () => fetchFilms(),
  });

  const films = filmsQuery.data ?? [];
  const { current, upcoming, archive } = splitFilms(films);
  const { isMember } = useIsMember();

  return (
    <MemberShell>
      <div
        className={cn(
          "mx-auto max-w-5xl px-4 pb-24",
          isMember ? "pt-6" : "pt-20 sm:pt-24"
        )}
      >
        {/* Marquee header — studios identity, not a feed heading */}
        <Reveal variant="up">
          <div className="flex items-center justify-between gap-4">
            <div className="flex items-center gap-3">
              <span className="flex h-11 w-11 items-center justify-center rounded-2xl bg-foreground">
                <Clapperboard className="h-5 w-5 text-background" />
              </span>
              <div>
                <p className="text-[10px] font-bold uppercase tracking-[0.22em] text-muted-foreground">
                  Whisper Studios
                </p>
                <h1 className="font-display text-2xl font-black tracking-tight sm:text-[28px]">
                  Featured Film Friday
                </h1>
              </div>
            </div>
            {films.length > 0 && (
              <span className="hidden items-center gap-1.5 rounded-full border border-border bg-card px-3 py-1.5 text-[11px] font-bold uppercase tracking-wider text-muted-foreground sm:flex">
                <Sparkles className="h-3 w-3" />
                {films.length} premiere{films.length === 1 ? "" : "s"}
              </span>
            )}
          </div>
        </Reveal>

        {filmsQuery.isLoading ? (
          <div className="flex justify-center py-32">
            <Loader2 className="h-7 w-7 animate-spin text-muted-foreground" />
          </div>
        ) : films.length === 0 ? (
          <EmptyMarquee />
        ) : current || upcoming ? (
          <>
            <PremiereHero film={current ?? upcoming} isLive={!!current} />
            {archive.length > 0 && <ArchiveSection films={archive} />}
          </>
        ) : (
          <>
            {/* No active premiere — quiet marquee + archive only */}
            <QuietMarquee />
            <ArchiveSection films={archive} />
          </>
        )}
      </div>
    </MemberShell>
  );
}

/**
 * Split films into:
 *  - current: a film whose featured_date is this week's Friday (or earlier
 *    this week, treating Friday as the premiere day).
 *  - upcoming: a film with a featured_date in the future.
 *  - archive: everything else (past premieres + unscheduled).
 *
 * Only one film is ever "current" — Featured Film Friday is a single
 * once-in-a-while event, not a rolling feed.
 */
function splitFilms(films: Film[]): {
  current: Film | null;
  upcoming: Film | null;
  archive: Film[];
} {
  if (films.length === 0) return { current: null, upcoming: null, archive: [] };
  const now = new Date();
  const thisFriday = mostRecentFriday(now);
  let current: Film | null = null;
  let upcoming: Film | null = null;
  const archive: Film[] = [];
  for (const film of films) {
    if (!film.featured_date) {
      archive.push(film);
      continue;
    }
    const d = new Date(film.featured_date + "T00:00:00");
    if (sameDay(d, thisFriday) || (d < thisFriday && isThisWeek(d, now))) {
      if (!current) current = film;
      else archive.push(film);
    } else if (d > now) {
      if (!upcoming) upcoming = film;
      else archive.push(film);
    } else {
      archive.push(film);
    }
  }
  return { current, upcoming, archive };
}

function mostRecentFriday(now: Date): Date {
  const d = new Date(now);
  d.setHours(0, 0, 0, 0);
  const day = d.getDay(); // 0 Sun … 5 Fri … 6 Sat
  const diff = (day + 2) % 7; // days since Friday
  d.setDate(d.getDate() - diff);
  return d;
}

function sameDay(a: Date, b: Date): boolean {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}

function isThisWeek(d: Date, now: Date): boolean {
  const start = mostRecentFriday(now);
  const end = new Date(start);
  end.setDate(start.getDate() + 7);
  return d >= start && d < end;
}

/**
 * Full-bleed premiere hero — a cinema-grade stage for the current feature.
 * Layered film grain, a deep letterbox scrim, the festival title card, and a
 * play beacon that animates on hover. This is the centerpiece of the page —
 * it should feel like a movie poster come to life, not a feed card.
 */
function PremiereHero({ film, isLive }: { film: Film; isLive: boolean }) {
  return (
    <Reveal variant="up">
      <Link
        to={`/films/${film.id}`}
        className="group relative mt-8 block overflow-hidden rounded-[32px] bg-black shadow-[0_40px_100px_-20px_rgba(0,0,0,0.6)] ring-1 ring-white/10"
      >
        {/* Poster stage — 2.39:1 cinematic scope */}
        <div className="relative aspect-[2.39/1] w-full overflow-hidden bg-black">
          {film.poster_url ? (
            <img
              src={film.poster_url}
              alt=""
              className="h-full w-full object-cover transition-transform duration-[1600ms] ease-out group-hover:scale-[1.06]"
            />
          ) : (
            <div className="flex h-full w-full items-center justify-center bg-gradient-to-br from-zinc-900 via-black to-zinc-900">
              <Clapperboard className="h-16 w-16 text-white/15" />
            </div>
          )}

          {/* Film grain texture — subtle noise that gives the poster a
              celluloid feel rather than a flat digital image. */}
          <div
            className="pointer-events-none absolute inset-0 opacity-[0.08] mix-blend-overlay"
            style={{
              backgroundImage:
                "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='200' height='200'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='3' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E\")",
            }}
          />

          {/* Letterbox scrim — heavier at the bottom for the title card */}
          <div className="absolute inset-0 bg-gradient-to-t from-black via-black/35 to-black/10" />
          <div className="absolute inset-0 bg-gradient-to-b from-black/40 via-transparent to-transparent" />
          <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_30%_40%,transparent_30%,rgba(0,0,0,0.5)_100%)]" />

          {/* Top-left: featured-film tag + live pill */}
          <div className="absolute left-5 top-5 flex items-center gap-2 sm:left-8 sm:top-8">
            <span className="inline-flex items-center gap-1.5 rounded-full bg-white/10 px-3 py-1.5 text-[10px] font-black uppercase tracking-[0.2em] text-white/90 ring-1 ring-white/20 backdrop-blur-md">
              <FilmIcon className="h-3 w-3" /> Featured Film
            </span>
            {isLive && (
              <span className="inline-flex items-center gap-1.5 rounded-full bg-white px-3 py-1.5 text-[10px] font-black uppercase tracking-[0.18em] text-black">
                <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-red-600" />
                Live
              </span>
            )}
          </div>

          {/* Top-right: studio mark */}
          <div className="absolute right-5 top-5 hidden items-center gap-1.5 sm:flex sm:right-8 sm:top-8">
            <span className="flex h-7 w-7 items-center justify-center rounded-lg bg-white/10 ring-1 ring-white/20 backdrop-blur-md">
              <Clapperboard className="h-3.5 w-3.5 text-white/80" />
            </span>
            <span className="text-[10px] font-bold uppercase tracking-[0.2em] text-white/60">
              Whisper Studios
            </span>
          </div>

          {/* Center play beacon — animated ring */}
          <div className="absolute inset-0 flex items-center justify-center">
            <span className="relative flex h-24 w-24 items-center justify-center rounded-full bg-white/8 ring-1 ring-white/25 backdrop-blur-md transition-all duration-500 group-hover:scale-110 group-hover:bg-white/12 group-hover:ring-white/40">
              <span className="absolute inset-0 animate-ping rounded-full bg-white/5" />
              <Play className="ml-1 h-8 w-8 fill-white text-white drop-shadow-lg" />
            </span>
          </div>

          {/* Bottom: festival title card */}
          <div className="absolute inset-x-0 bottom-0 px-6 pb-7 pt-16 sm:px-10 sm:pb-10">
            {film.featured_date && (
              <p className="text-[10px] font-bold uppercase tracking-[0.28em] text-white/50">
                {formatPremiereDate(film.featured_date)}
              </p>
            )}
            <h2 className="mt-2.5 font-display text-[34px] font-black leading-[0.95] tracking-[-0.02em] text-white drop-shadow-2xl sm:text-[52px]">
              {film.title}
            </h2>
            {film.synopsis && (
              <p className="mt-3 max-w-lg text-[14px] leading-snug text-white/70 line-clamp-2 sm:text-[15px]">
                {film.synopsis}
              </p>
            )}
            <div className="mt-5 flex flex-wrap items-center gap-3">
              <span className="inline-flex items-center gap-2 rounded-full bg-white px-5 py-2.5 text-[12px] font-bold text-black transition-transform group-hover:translate-x-1">
                <Play className="h-3.5 w-3.5 fill-black" />
                Watch the premiere
              </span>
              <span className="inline-flex items-center gap-2 rounded-full bg-white/5 px-3.5 py-2 text-[11px] font-bold uppercase tracking-wider text-white/70 ring-1 ring-white/15 backdrop-blur-md">
                <Sparkles className="h-3 w-3" />
                A Whisper Studios film
              </span>
              {film.duration_seconds ? (
                <span className="font-mono text-[12px] font-semibold text-white/50">
                  {formatTimecode(film.duration_seconds)}
                </span>
              ) : null}
            </div>
          </div>
        </div>
      </Link>
    </Reveal>
  );
}

/** Quiet marquee state — no active premiere, just the studios identity. */
function QuietMarquee() {
  return (
    <Reveal variant="up">
      <div className="mt-10 overflow-hidden rounded-[28px] border border-border bg-gradient-to-br from-foreground/[0.04] via-card to-foreground/[0.02] p-8 text-center sm:p-12">
        <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-2xl bg-foreground/5">
          <Clapperboard className="h-7 w-7 text-muted-foreground/60" />
        </div>
        <p className="mt-4 font-display text-xl font-extrabold tracking-tight">
          No premiere this week
        </p>
        <p className="mx-auto mt-2 max-w-md text-[14px] leading-relaxed text-muted-foreground">
          Whisper Studios premieres a short film every few Fridays — training
          journeys, meet-day vlogs, and documentary stories from inside the
          community. The next premiere appears here the moment it's scheduled.
        </p>
      </div>
    </Reveal>
  );
}

/** Empty state — no films at all yet. */
function EmptyMarquee() {
  return (
    <Reveal variant="up">
      <div className="mt-16 text-center">
        <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-2xl bg-foreground/5">
          <FilmIcon className="h-7 w-7 text-muted-foreground/50" />
        </div>
        <p className="mt-4 font-display text-xl font-extrabold tracking-tight">
          The first premiere is being filmed
        </p>
        <p className="mx-auto mt-2 max-w-md text-[14px] leading-relaxed text-muted-foreground">
          Whisper Studios is the media team's home for short films made with
          our creators. The first Featured Film Friday premiere will appear
          here.
        </p>
      </div>
    </Reveal>
  );
}

/** Archive — past premieres in a tight, festival-style grid. */
function ArchiveSection({ films }: { films: Film[] }) {
  if (films.length === 0) return null;
  return (
    <div className="mt-14">
      <div className="mb-5 flex items-baseline justify-between">
        <h2 className="text-[12px] font-bold uppercase tracking-[0.22em] text-muted-foreground">
          Premiere Archive
        </h2>
        <span className="text-[11px] font-semibold text-muted-foreground/70">
          {films.length} film{films.length === 1 ? "" : "s"}
        </span>
      </div>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {films.map((film) => (
          <Reveal key={film.id} variant="up" threshold={0.1}>
            <ArchiveCard film={film} />
          </Reveal>
        ))}
      </div>
    </div>
  );
}

function ArchiveCard({ film }: { film: Film }) {
  return (
    <Link
      to={`/films/${film.id}`}
      className="group block overflow-hidden rounded-[20px] border border-border bg-card transition-all hover:-translate-y-0.5 hover:shadow-lg"
    >
      <div className="relative aspect-video w-full overflow-hidden bg-black">
        {film.poster_url ? (
          <img
            src={film.poster_url}
            alt=""
            className="h-full w-full object-cover transition-transform duration-700 group-hover:scale-105"
          />
        ) : (
          <div className="flex h-full w-full items-center justify-center bg-gradient-to-br from-zinc-900 via-black to-zinc-900">
            <FilmIcon className="h-8 w-8 text-white/20" />
          </div>
        )}
        <div className="absolute inset-0 bg-gradient-to-t from-black/70 via-black/10 to-transparent" />
        <span className="absolute right-3 top-3 flex h-9 w-9 items-center justify-center rounded-full bg-white/10 ring-1 ring-white/25 backdrop-blur-md transition-transform group-hover:scale-110">
          <Play className="ml-0.5 h-3.5 w-3.5 fill-white text-white" />
        </span>
        {film.duration_seconds ? (
          <span className="absolute bottom-3 right-3 rounded-md bg-black/70 px-1.5 py-0.5 font-mono text-[10px] font-bold text-white/90">
            {formatTimecode(film.duration_seconds)}
          </span>
        ) : null}
      </div>
      <div className="p-3.5">
        {film.featured_date && (
          <p className="text-[10px] font-bold uppercase tracking-[0.18em] text-muted-foreground">
            {formatPremiereDate(film.featured_date)}
          </p>
        )}
        <h3 className="mt-1 truncate font-display text-[15px] font-extrabold tracking-tight">
          {film.title}
        </h3>
        {film.synopsis && (
          <p className="mt-1 line-clamp-2 text-[12.5px] leading-snug text-muted-foreground">
            {film.synopsis}
          </p>
        )}
        <span className="mt-2.5 inline-flex items-center gap-1 text-[11px] font-bold text-foreground/70 transition-transform group-hover:translate-x-0.5">
          Watch <ArrowRight className="h-3 w-3" />
        </span>
      </div>
    </Link>
  );
}

function formatPremiereDate(iso: string): string {
  const d = new Date(iso + "T00:00:00");
  return d.toLocaleDateString("en-US", {
    weekday: "long",
    month: "long",
    day: "numeric",
    year: "numeric",
  });
}
