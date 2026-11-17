import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { ArrowRight, Clapperboard, Film as FilmIcon, Play } from "lucide-react";

import { fetchFilms, formatTimecode, type Film } from "@/lib/films";

/**
 * Featured Film Friday inline shelf — surfaces published Whisper films
 * inside the social feed so premieres are discoverable in-context, not
 * gated behind a separate page. Eventized feel: only the current/most-recent
 * premiere is hero-sized, with a compact archive rail beside it. The shelf
 * is seamless (like Facebook's inline content units) — no boxed ad chrome.
 *
 * Routers between the public films page and the in-feed detail. Tapping a
 * card navigates to `/films/:id` where the full cinema player + engagement
 * + comments live.
 */
export default function FeedFilmShelf() {
  const filmsQuery = useQuery({
    queryKey: ["films"],
    queryFn: () => fetchFilms(),
    // Cache for 10 minutes — premieres don't change minute to minute and
    // the shelf rides along with the feed.
    staleTime: 10 * 60 * 1000,
  });

  const films = filmsQuery.data ?? [];
  if (films.length === 0) return null;

  // Hero = the current/most-recent premiere; archive = the rest.
  const [hero, ...archive] = films.slice(0, 6);

  return (
    <div className="border-b border-border py-4">
      {/* Shelf header — quiet marquee identity, not a boxed ad */}
      <div className="flex items-center justify-between gap-3 px-4 pb-3">
        <div className="flex items-center gap-2.5">
          <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-foreground shadow-sm">
            <Clapperboard className="h-4 w-4 text-background" />
          </span>
          <div className="leading-tight">
            <p className="text-[10px] font-bold uppercase tracking-[0.18em] text-muted-foreground">
              Whisper Studios
            </p>
            <p className="font-display text-[15px] font-extrabold tracking-tight">
              Featured Film Friday
            </p>
          </div>
        </div>
        <Link
          to="/films"
          className="flex items-center gap-1 rounded-full border border-border px-3 py-1.5 text-[11px] font-bold uppercase tracking-wider text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground"
        >
          All films
          <ArrowRight className="h-3 w-3" />
        </Link>
      </div>

      {/* Horizontal rail — hero card + archive thumbs */}
      <div className="flex snap-x snap-mandatory gap-3 overflow-x-auto px-4 pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
        <HeroCard film={hero} />
        {archive.map((film) => (
          <ArchiveThumb key={film.id} film={film} />
        ))}
      </div>
    </div>
  );
}

/** Hero card — the current premiere, poster-forward with a play beacon. */
function HeroCard({ film }: { film: Film }) {
  return (
    <Link
      to={`/films/${film.id}`}
      className="group relative block shrink-0 snap-start overflow-hidden rounded-[22px] bg-black shadow-lg ring-1 ring-black/10 transition-shadow hover:shadow-xl"
    >
      <div className="relative h-[210px] w-[330px] overflow-hidden bg-black">
        {film.poster_url ? (
          <img
            src={film.poster_url}
            alt=""
            className="h-full w-full object-cover transition-transform duration-700 group-hover:scale-[1.04]"
          />
        ) : (
          <div className="flex h-full w-full items-center justify-center bg-gradient-to-br from-zinc-900 via-black to-zinc-900">
            <Clapperboard className="h-10 w-10 text-white/15" />
          </div>
        )}
        {/* Letterbox scrim */}
        <div className="absolute inset-0 bg-gradient-to-t from-black via-black/25 to-black/5" />

        {/* Tag + duration pills */}
        <div className="absolute left-3 right-3 top-3 flex items-center justify-between gap-1.5">
          <span className="inline-flex items-center gap-1 rounded-full bg-white/10 px-2.5 py-1 text-[9px] font-black uppercase tracking-[0.16em] text-white/90 ring-1 ring-white/20 backdrop-blur-md">
            <FilmIcon className="h-2.5 w-2.5" /> Premiere
          </span>
          {film.duration_seconds ? (
            <span className="rounded-full bg-black/50 px-2 py-1 font-mono text-[9px] font-bold text-white/80 backdrop-blur-md">
              {formatTimecode(film.duration_seconds)}
            </span>
          ) : null}
        </div>

        {/* Center play beacon */}
        <div className="absolute inset-0 flex items-center justify-center">
          <span className="flex h-16 w-16 items-center justify-center rounded-full bg-white/10 ring-1 ring-white/25 backdrop-blur-md transition-all duration-500 group-hover:scale-110 group-hover:bg-white/20">
            <Play className="ml-0.5 h-6 w-6 fill-white text-white" />
          </span>
        </div>

        {/* Title card */}
        <div className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/85 to-transparent px-4 pb-3.5 pt-12">
          <h3 className="font-display text-[19px] font-black leading-[1.05] tracking-[-0.01em] text-white line-clamp-1">
            {film.title}
          </h3>
          {(film.director_name || film.director_username) && (
            <p className="mt-1.5 text-[11px] font-bold text-white/70 line-clamp-1">
              A {film.director_name ?? film.director_username} film
            </p>
          )}
        </div>
      </div>
    </Link>
  );
}

/** Compact archive thumb — past/secondary premieres. */
function ArchiveThumb({ film }: { film: Film }) {
  return (
    <Link
      to={`/films/${film.id}`}
      className="group relative block shrink-0 snap-start overflow-hidden rounded-[16px] bg-card ring-1 ring-border transition-all hover:-translate-y-0.5 hover:shadow-md"
    >
      <div className="relative h-[210px] w-[142px] overflow-hidden bg-black">
        {film.poster_url ? (
          <img
            src={film.poster_url}
            alt=""
            className="h-full w-full object-cover transition-transform duration-700 group-hover:scale-105"
          />
        ) : (
          <div className="flex h-full w-full items-center justify-center bg-gradient-to-br from-zinc-900 via-black to-zinc-900">
            <FilmIcon className="h-6 w-6 text-white/15" />
          </div>
        )}
        <div className="absolute inset-0 bg-gradient-to-t from-black/85 via-black/10 to-transparent" />
        <span className="absolute right-2 top-2 flex h-7 w-7 items-center justify-center rounded-full bg-white/10 ring-1 ring-white/20 backdrop-blur-md transition-transform group-hover:scale-110">
          <Play className="ml-0.5 h-3 w-3 fill-white text-white" />
        </span>
        {film.duration_seconds ? (
          <span className="absolute left-2 top-2 rounded-full bg-black/55 px-1.5 py-0.5 font-mono text-[8px] font-bold text-white/80 backdrop-blur-md">
            {formatTimecode(film.duration_seconds)}
          </span>
        ) : null}
        <div className="absolute inset-x-0 bottom-0 px-2.5 pb-2.5 pt-6">
          <p className="text-[11px] font-bold leading-tight text-white line-clamp-2">
            {film.title}
          </p>
          {(film.director_name || film.director_username) && (
            <p className="mt-0.5 text-[9px] font-semibold text-white/55 line-clamp-1">
              {film.director_name ?? film.director_username}
            </p>
          )}
        </div>
      </div>
    </Link>
  );
}
