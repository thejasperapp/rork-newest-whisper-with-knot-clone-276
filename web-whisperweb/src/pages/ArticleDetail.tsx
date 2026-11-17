import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import {
  ArrowLeft,
  ArrowRight,
  BookOpen,
  Bookmark,
  Clapperboard,
  Film as FilmIcon,
  Flame,
  Heart,
  Loader2,
  Play,
  Share2,
} from "lucide-react";

import { MemberShell, useIsMember } from "@/components/MemberShell";
import { ArticleCover, resolvableCoverUrl } from "@/components/ArticleCover";
import { Reveal } from "@/components/Reveal";
import { Button } from "@/components/ui/button";
import { usePageMeta } from "@/hooks/usePageMeta";
import { fetchArticle } from "@/lib/articles";
import { fetchFilm, formatTimecode, type Film } from "@/lib/films";
import { siteUrl } from "@/lib/site";
import { encodeArticleEmbed } from "@/lib/contentEmbeds";
import { FactCheckDock } from "@/components/FactCheckDock";
import { ShareContentDialog } from "@/components/ContentEmbedCards";
import { cn } from "@/lib/utils";

function formatDate(iso: string | null): string {
  if (!iso) return "";
  return new Date(iso).toLocaleDateString(undefined, {
    month: "long",
    day: "numeric",
    year: "numeric",
  });
}

/** One public article, rendered from its stored paragraphs. When the article
 *  is linked to a Featured Film, the film's trailer (or, for clipped
 *  articles, the clipped section of the film) plays at the top instead of a
 *  static cover image — and the director + Whisper Studios get credit. */
export default function ArticleDetail() {
  const { slug } = useParams<{ slug: string }>();

  const article = useQuery({
    queryKey: ["article", slug],
    queryFn: () => fetchArticle(slug ?? ""),
    enabled: !!slug,
    staleTime: 60_000,
  });

  // If the article is linked to a film, fetch the film so we can show its
  // trailer (or the clipped section) and credit the director.
  const filmId = article.data?.film_id ?? null;
  const film = useQuery({
    queryKey: ["film", filmId],
    queryFn: () => fetchFilm(filmId!),
    enabled: !!filmId,
    staleTime: 60_000,
  });

  usePageMeta(
    article.data?.title ?? "Articles",
    article.data?.excerpt || undefined
  );

  // Device-local like/save + the in-app share surface (mirrors the iOS reader).
  const [liked, setLiked] = useState<boolean>(false);
  const [saved, setSaved] = useState<boolean>(false);
  const [showShare, setShowShare] = useState<boolean>(false);

  useEffect(() => {
    const articleId = article.data?.id;
    if (!articleId) return;
    try {
      setLiked(localStorage.getItem(`whisper_article_like_${articleId}`) === "1");
      setSaved(localStorage.getItem(`whisper_article_save_${articleId}`) === "1");
    } catch {
      /* storage unavailable */
    }
  }, [article.data?.id]);

  /** ~200wpm reading estimate across excerpt + paragraphs. */
  const readMinutes = useMemo<number>(() => {
    const art = article.data;
    if (!art) return 0;
    const words = [art.excerpt ?? "", ...art.paragraphs]
      .join(" ")
      .split(/\s+/)
      .filter(Boolean).length;
    return Math.max(1, Math.ceil(words / 200));
  }, [article.data]);

  /** Dense claim text for the fact-check dock — capped so it stays sharp. */
  const factClaim = useMemo<string>(() => {
    const art = article.data;
    if (!art) return "";
    const parts: string[] = [art.title];
    if (art.excerpt) parts.push(art.excerpt);
    for (const p of art.paragraphs) {
      if (p.startsWith("#")) continue;
      parts.push(p);
      if (parts.join(" ").length > 700) break;
    }
    return parts.join(" ").slice(0, 750);
  }, [article.data]);

  const toggleEngagement = (kind: "like" | "save"): void => {
    const articleId = article.data?.id;
    if (!articleId) return;
    const next = kind === "like" ? !liked : !saved;
    if (kind === "like") setLiked(next);
    else setSaved(next);
    try {
      localStorage.setItem(
        `whisper_article_${kind}_${articleId}`,
        next ? "1" : "0"
      );
    } catch {
      /* storage unavailable */
    }
  };

  const a = article.data;
  const f: Film | null = film.data ?? null;
  const clipSeconds = a?.clip_time_seconds ?? null;
  const isClipped = !!clipSeconds && !!f;
  // For clipped articles, the "trailer" is the section of the film around the
  // timestamp — we just play the film and seek to the clip spot. For untagged
  // film articles, prefer the film's dedicated trailer so the article doesn't
  // spoil the full premiere.
  const mediaSrc = f
    ? isClipped
      ? f.video_url
      : f.trailer_url || f.video_url
    : null;
  // A `film-frame:` cover token can't load in a <video poster> — resolve it
  // to the film's real poster (or drop it) before handing it to the player.
  const mediaPoster =
    resolvableCoverUrl(a?.cover_url, f?.poster_url) ?? undefined;
  const directorHref = f?.director_username
    ? `/u/${f.director_username}`
    : f?.director_id
      ? `/u/${f.director_id}`
      : null;
  const directorName = f?.director_name || f?.director_username || null;

  // Author byline link.
  const authorHref = a?.author_username
    ? `/u/${a.author_username}`
    : null;

  const { isMember } = useIsMember();

  return (
    <MemberShell>
      <main
        className={cn(
          "px-4 pb-32 sm:px-6 lg:px-8",
          isMember ? "pt-6" : "pt-28 lg:pt-36"
        )}
      >
        <div className="mx-auto max-w-3xl">
          <Link
            to="/articles"
            className="inline-flex items-center gap-1.5 text-[13.5px] font-semibold text-muted-foreground hover:text-foreground"
          >
            <ArrowLeft className="h-4 w-4" />
            All articles
          </Link>

          {article.isLoading ? (
            <div className="flex justify-center pt-24">
              <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
            </div>
          ) : !a ? (
            <div className="mt-10 rounded-[28px] border border-border bg-card p-10 text-center">
              <p className="text-[16px] font-semibold">
                This article isn't available.
              </p>
              <p className="mt-1.5 text-[14.5px] text-muted-foreground">
                It may have been unpublished or the link is wrong.
              </p>
              <Button className="mt-6 rounded-full" asChild>
                <Link to="/articles">Browse articles</Link>
              </Button>
            </div>
          ) : (
            <article className="mt-6">
              <Reveal variant="fade">
                <span className="rounded-full bg-secondary px-3 py-1 text-[11.5px] font-extrabold uppercase tracking-wider">
                  {a.category}
                </span>
                <h1 className="mt-4 font-display text-[32px] font-extrabold leading-[1.15] tracking-tight sm:text-[42px]">
                  {a.title}
                </h1>
                <p className="mt-3 text-[14px] font-semibold text-muted-foreground">
                  {authorHref ? (
                    <Link to={authorHref} className="hover:underline">
                      {a.author_name}
                    </Link>
                  ) : (
                    a.author_name
                  )}
                  {a.published_at
                    ? ` · ${formatDate(a.published_at)}`
                    : ""}
                  <span className="inline-flex items-center gap-1">
                    {" · "}
                    <BookOpen className="h-3.5 w-3.5" />
                    {readMinutes} min read
                  </span>
                </p>

                {/* Film-linked media: trailer or clipped section.
                    For a clipped article, the film plays seeked to the clip
                    timestamp so the reader sees the exact moment the article
                    is about. Otherwise the film's trailer plays. */}
                {mediaSrc && f && (
                  <FilmMediaBlock
                    film={f}
                    src={mediaSrc}
                    poster={mediaPoster}
                    clipSeconds={isClipped ? clipSeconds : null}
                    directorHref={directorHref}
                    directorName={directorName}
                  />
                )}

                {/* Fallback cover image for non-film articles — resolves
                    film-frame tokens to the film poster + timecode chip. */}
                {!f && a.cover_url && (
                  <ArticleCover
                    cover={a.cover_url}
                    alt={a.title}
                    className="mt-7 aspect-[16/9] w-full rounded-[26px] border border-border"
                  />
                )}
              </Reveal>

              <div className="mt-8 space-y-5">
                {a.paragraphs.map((paragraph, index) => (
                  <Reveal key={`${a.id}-p-${index}`} variant="fade" threshold={0.05}>
                    <p className="text-[16.5px] leading-[1.75] text-foreground/85">
                      {paragraph}
                    </p>
                  </Reveal>
                ))}
              </div>

              {/* Like / save / share — device-local engagement + the in-app
                  share surface (DMs, wall repost, copy link) — mirrors iOS. */}
              <div className="mt-8 flex flex-wrap items-center gap-2">
                <button
                  type="button"
                  onClick={() => toggleEngagement("like")}
                  className={cn(
                    "inline-flex h-9 items-center gap-1.5 rounded-full border border-border bg-card px-4 text-[13px] font-bold transition-colors hover:bg-secondary/60",
                    liked && "text-red-500"
                  )}
                >
                  <Heart className={cn("h-4 w-4", liked && "fill-current")} />
                  {liked ? "Liked" : "Like"}
                </button>
                <button
                  type="button"
                  onClick={() => toggleEngagement("save")}
                  className={cn(
                    "inline-flex h-9 items-center gap-1.5 rounded-full border border-border bg-card px-4 text-[13px] font-bold transition-colors hover:bg-secondary/60",
                    saved && "text-sky-500"
                  )}
                >
                  <Bookmark className={cn("h-4 w-4", saved && "fill-current")} />
                  {saved ? "Saved" : "Save"}
                </button>
                <button
                  type="button"
                  onClick={() => setShowShare(true)}
                  className="inline-flex h-9 items-center gap-1.5 rounded-full border border-border bg-card px-4 text-[13px] font-bold transition-colors hover:bg-secondary/60"
                >
                  <Share2 className="h-4 w-4" />
                  Share
                </button>
              </div>

              <Reveal variant="scale">
                <div className="mt-12 rounded-[26px] border border-border bg-card p-8 text-center">
                  <h2 className="font-display text-[20px] font-extrabold">
                    Train with the people who wrote this.
                  </h2>
                  <p className="mx-auto mt-2 max-w-md text-[14.5px] text-muted-foreground">
                    Whisper is where verified coaches, athletes, and creators
                    actually train together.
                  </p>
                  <Button className="mt-5 rounded-full px-7 font-semibold" asChild>
                    <Link to="/auth?mode=signup">
                      Join Whisper
                      <ArrowRight className="ml-1 h-4 w-4" />
                    </Link>
                  </Button>
                </div>
              </Reveal>
            </article>
          )}
        </div>
      </main>

      {/* Jasper's fact check — the meeting-style pill pinned above the
          bottom edge; tap to run (cached per article). */}
      {a && factClaim && <FactCheckDock claim={factClaim} className="bottom-6" />}

      {a && (
        <ShareContentDialog
          open={showShare}
          onOpenChange={setShowShare}
          kicker="WHISPER JOURNAL"
          title={a.title}
          subtitle={`By ${a.author_name ?? "Whisper Team"}`}
          imageUrl={resolvableCoverUrl(a.cover_url, f?.poster_url)}
          embedBody={encodeArticleEmbed({
            id: a.id,
            slug: slug ?? "",
            title: a.title,
            author: a.author_name ?? "Whisper Team",
            cover: resolvableCoverUrl(a.cover_url, f?.poster_url),
            category: a.category,
          })}
          linkUrl={siteUrl(`/articles/${slug ?? ""}`)}
        />
      )}

    </MemberShell>
  );
}

/**
 * The film-linked media block — a cinema player for the trailer (or the
 * clipped section of the film for clipped articles), with the director +
 * Whisper Studios credit underneath. Styled to match the FilmDetail page.
 */
function FilmMediaBlock({
  film,
  src,
  poster,
  clipSeconds,
  directorHref,
  directorName,
}: {
  film: Film;
  src: string;
  poster?: string;
  clipSeconds: number | null;
  directorHref: string | null;
  directorName: string | null;
}) {
  return (
    <div className="mt-7">
      <div className="relative overflow-hidden rounded-[26px] bg-black shadow-[0_30px_70px_-15px_rgba(0,0,0,0.5)] ring-1 ring-white/10">
        <video
          src={src}
          poster={poster}
          controls
          playsInline
          preload="metadata"
          className="aspect-video w-full bg-black"
          // For clipped articles, start at the clip timestamp so the reader
          // sees the exact moment the article is about.
          ref={(el) => {
            if (el && clipSeconds != null) {
              el.currentTime = clipSeconds;
            }
          }}
        />
        {clipSeconds != null && (
          <div className="absolute left-4 top-4 inline-flex items-center gap-1.5 rounded-full bg-white/10 px-3 py-1.5 text-[10px] font-black uppercase tracking-[0.18em] text-white/90 ring-1 ring-white/20 backdrop-blur-md">
            <FilmIcon className="h-3 w-3" /> Clip · {formatTimecode(clipSeconds)}
          </div>
        )}
        {film.trailer_url && clipSeconds == null && (
          <div className="absolute left-4 top-4 inline-flex items-center gap-1.5 rounded-full bg-white/10 px-3 py-1.5 text-[10px] font-black uppercase tracking-[0.18em] text-white/90 ring-1 ring-white/20 backdrop-blur-md">
            <Play className="h-3 w-3 fill-white" /> Trailer
          </div>
        )}
      </div>

      {/* Film credit — director + Whisper Studios, with the director's name
          linked to their profile so the credit goes to the real director. */}
      <div className="mt-4 flex flex-wrap items-center gap-x-4 gap-y-2">
        <Link
          to={`/films/${film.id}`}
          className="inline-flex items-center gap-1.5 text-[13px] font-extrabold text-foreground underline-offset-4 transition-colors hover:underline"
        >
          <Clapperboard className="h-4 w-4 text-muted-foreground" />
          {film.title}
        </Link>
        {directorName && (
          <span className="inline-flex items-center gap-1.5 text-[12.5px] font-bold text-muted-foreground">
            A{" "}
            {directorHref ? (
              <Link
                to={directorHref}
                className="font-extrabold text-foreground underline-offset-4 transition-colors hover:underline"
              >
                {directorName}
              </Link>
            ) : (
              <span className="text-foreground">{directorName}</span>
            )}{" "}
            film
          </span>
        )}
        <span className="inline-flex items-center gap-1.5 text-[12.5px] font-bold text-muted-foreground">
          <Flame className="h-3.5 w-3.5 text-orange-500" />
          Whisper Studios
        </span>
      </div>
    </div>
  );
}
