import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Film as FilmIcon, Newspaper } from "lucide-react";

import { isRenderableCover, parseFilmFrameCover } from "@/lib/articles";
import { fetchFilm, formatTimecode } from "@/lib/films";
import { cn } from "@/lib/utils";

/**
 * Renders an article cover from either a real image URL or the backend's
 * `film-frame:<filmId>:<seconds>` token (which no <img> can load). The token
 * resolves to the linked film's poster with a timecode chip, and any dead
 * URL falls back to a quiet placeholder instead of a broken image.
 */
export function ArticleCover({
  cover,
  alt,
  className,
  imgClassName,
}: {
  cover: string | null | undefined;
  alt?: string;
  /** Wrapper classes — must size the cover (the img fills it). */
  className?: string;
  imgClassName?: string;
}) {
  const [broken, setBroken] = useState<boolean>(false);
  const frame = parseFilmFrameCover(cover);
  const filmQuery = useQuery({
    queryKey: ["film", frame?.filmId ?? null],
    queryFn: () => fetchFilm(frame!.filmId),
    enabled: !!frame,
    staleTime: 300_000,
  });

  const resolvedUrl = frame
    ? filmQuery.data?.poster_url ?? null
    : isRenderableCover(cover)
      ? (cover ?? "").trim()
      : null;

  return (
    <div className={cn("relative overflow-hidden bg-secondary", className)}>
      {resolvedUrl && !broken ? (
        <img
          src={resolvedUrl}
          alt={alt ?? ""}
          loading="lazy"
          decoding="async"
          onError={() => setBroken(true)}
          className={cn(
            "absolute inset-0 h-full w-full object-cover",
            imgClassName
          )}
        />
      ) : frame && filmQuery.isLoading ? (
        <div className="absolute inset-0 animate-pulse bg-secondary" />
      ) : (
        <div className="absolute inset-0 flex items-center justify-center bg-gradient-to-br from-secondary to-secondary/40 text-muted-foreground/50">
          {frame ? (
            <FilmIcon className="h-7 w-7" />
          ) : (
            <Newspaper className="h-7 w-7" />
          )}
        </div>
      )}
      {frame && (
        <span className="absolute bottom-2 right-2 inline-flex items-center gap-1 rounded-full bg-black/60 px-2 py-0.5 text-[10px] font-black uppercase tracking-wider text-[#7CEBC4] backdrop-blur-sm">
          <FilmIcon className="h-2.5 w-2.5" />
          Clip · {formatTimecode(frame.timeSeconds)}
        </span>
      )}
    </div>
  );
}

/**
 * Resolves a cover value to something an <img>/<video poster> can actually
 * load: real URLs pass through, film-frame tokens resolve to the provided
 * film poster (when known), anything else drops to null.
 */
export function resolvableCoverUrl(
  cover: string | null | undefined,
  filmPoster?: string | null
): string | null {
  if (isRenderableCover(cover)) return (cover ?? "").trim();
  if (parseFilmFrameCover(cover)) return filmPoster ?? null;
  return null;
}
