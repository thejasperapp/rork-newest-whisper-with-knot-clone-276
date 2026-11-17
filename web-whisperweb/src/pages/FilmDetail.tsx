import { useEffect, useRef, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ArrowLeft,
  Bookmark,
  Clapperboard,
  Eye,
  Film as FilmIcon,
  Flag,
  Flame,
  Lightbulb,
  ListChecks,
  Loader2,
  Maximize,
  MessageSquareQuote,
  MessagesSquare,
  Minimize,
  Pause,
  Pencil,
  Play,
  Plus,
  Quote,
  RotateCcw,
  RotateCw,
  Scissors,
  Share2,
  Sparkles,
  Subtitles,
  ThumbsDown,
  ThumbsUp,
  Trash2,
  Volume2,
  VolumeX,
  X,
} from "lucide-react";
import { toast } from "sonner";

import { MemberShell, useIsMember } from "@/components/MemberShell";
import { cn } from "@/lib/utils";
import { Reveal } from "@/components/Reveal";
import { Avatar } from "@/components/Avatar";
import { useAuth } from "@/hooks/useAuth";
import { useMyBadge } from "@/hooks/useMyBadge";
import { siteUrl } from "@/lib/site";
import { encodeFilmEmbed } from "@/lib/contentEmbeds";
import { ShareContentDialog } from "@/components/ContentEmbedCards";
import {
  createFilmComment,
  createFilmTimestamp,
  deleteFilmComment,
  deleteFilmTimestamp,
  editFilmComment,
  fetchFilm,
  fetchFilmComments,
  fetchFilmReactions,
  fetchFilmTimestamps,
  formatTimecode,
  setFilmReaction,
  type FilmComment,
  type FilmTimestamp,
} from "@/lib/films";

/**
 * Whether the signed-in user may timestamp/review films. Coaches, athletes,
 * verified creators, directors, bloggers, mods, admins, owners.
 */
function canTimestamp(
  profile: { is_coach?: boolean | null; is_athlete?: boolean | null; is_verified?: boolean | null; is_director?: boolean | null; is_blogger?: boolean | null } | null,
  badge: string
): boolean {
  if (!profile) return false;
  if (profile.is_coach || profile.is_athlete || profile.is_verified || profile.is_director || profile.is_blogger) return true;
  return badge === "moderator" || badge === "admin" || badge === "owner";
}

/** The review/timestamp categories a blogger can assign to a marked moment. */
type TimestampCategory = "note" | "highlight" | "review" | "question" | "clip";

interface CategoryMeta {
  label: string;
  icon: typeof Flag;
  color: string;
  bg: string;
}

const CATEGORIES: Record<TimestampCategory, CategoryMeta> = {
  note: { label: "Note", icon: Bookmark, color: "text-muted-foreground", bg: "bg-secondary" },
  highlight: { label: "Highlight", icon: Sparkles, color: "text-amber-600", bg: "bg-amber-500/10" },
  review: { label: "Review", icon: MessageSquareQuote, color: "text-blue-600", bg: "bg-blue-500/10" },
  question: { label: "Question", icon: Lightbulb, color: "text-purple-600", bg: "bg-purple-500/10" },
  clip: { label: "Clip", icon: Scissors, color: "text-orange-600", bg: "bg-orange-500/10" },
};

const CATEGORY_ORDER: TimestampCategory[] = ["note", "highlight", "review", "question", "clip"];

/**
 * Film detail — the cinematic presentation page for a single Featured Film
 * Friday premiere. A Whisper-styled custom cinema player with breathing room
 * from the nav, a festival title block with the real director's name linked
 * to their profile, a YouTube-style engagement bar (like / dislike / comment /
 * share), a polished comments section with real avatars and threading, and a
 * robust timestamp/review rail that opens via a "Notes" button for
 * permissioned users.
 */
export default function FilmDetail() {
  const { id = "" } = useParams();
  const { profile } = useAuth();
  const { isMember } = useIsMember();
  const badge = useMyBadge();
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const [newLabel, setNewLabel] = useState<string>("");
  const [newCategory, setNewCategory] = useState<TimestampCategory>("note");
  const [filter, setFilter] = useState<TimestampCategory | "all">("all");
  const [notesOpen, setNotesOpen] = useState<boolean>(false);
  const queryClient = useQueryClient();

  const filmQuery = useQuery({
    queryKey: ["film", id],
    queryFn: () => fetchFilm(id),
    enabled: !!id,
  });

  const timestampsQuery = useQuery({
    queryKey: ["film-timestamps", id],
    queryFn: () => fetchFilmTimestamps(id),
    enabled: !!id,
  });

  const reactionsQuery = useQuery({
    queryKey: ["film-reactions", id],
    queryFn: () => fetchFilmReactions(id),
    enabled: !!id,
  });

  const commentsQuery = useQuery({
    queryKey: ["film-comments", id],
    queryFn: () => fetchFilmComments(id),
    enabled: !!id,
  });

  const film = filmQuery.data;
  const allTimestamps = timestampsQuery.data ?? [];
  const allowed = canTimestamp(profile, badge);

  // Filter timestamps by category.
  const timestamps =
    filter === "all"
      ? allTimestamps
      : allTimestamps.filter((t) => deriveCategory(t.label) === filter);

  const [showShare, setShowShare] = useState<boolean>(false);

  const createMutation = useMutation({
    mutationFn: () =>
      createFilmTimestamp({
        filmId: id,
        label: formatLabel(newCategory, newLabel),
        timeSeconds: videoRef.current?.currentTime ?? 0,
      }),
    onSuccess: () => {
      toast.success(`${CATEGORIES[newCategory].label} saved at ${formatTimecode(videoRef.current?.currentTime ?? 0)}.`);
      setNewLabel("");
      setNewCategory("note");
      void queryClient.invalidateQueries({ queryKey: ["film-timestamps", id] });
    },
    onError: (err) =>
      toast.error(err instanceof Error ? err.message : "Couldn't save that moment."),
  });

  const deleteMutation = useMutation({
    mutationFn: (tsId: string) => deleteFilmTimestamp(tsId),
    onSuccess: () => {
      toast.success("Moment removed.");
      void queryClient.invalidateQueries({ queryKey: ["film-timestamps", id] });
    },
    onError: () => toast.error("Couldn't delete that moment."),
  });

  const reactMutation = useMutation({
    mutationFn: (weight: "like" | "dislike") => setFilmReaction(id, weight),
    onMutate: (weight) => {
      // Optimistic: toggle locally.
      const current = reactionsQuery.data;
      if (current) {
        const wasSame = current.mine === weight;
        const delta = wasSame ? -1 : current.mine ? 0 : 1;
        const likes = weight === "like" ? current.likes + delta : current.likes - (current.mine === "like" ? 1 : 0);
        const dislikes = weight === "dislike" ? current.dislikes + delta : current.dislikes - (current.mine === "dislike" ? 1 : 0);
        queryClient.setQueryData(["film-reactions", id], {
          likes: Math.max(0, likes),
          dislikes: Math.max(0, dislikes),
          mine: wasSame ? null : weight,
        });
      }
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["film-reactions", id] });
    },
    onError: (err) =>
      toast.error(err instanceof Error ? err.message : "Couldn't react."),
  });

  // Share opens the in-app surface — send in DMs, repost to the wall, copy
  // the link — mirroring the iOS share sheet.
  const shareMutation = useMutation({
    mutationFn: async () => {
      setShowShare(true);
    },
  });

  if (filmQuery.isLoading) {
    return (
      <MemberShell>
        <div className="flex justify-center py-24">
          <Loader2 className="h-7 w-7 animate-spin text-muted-foreground" />
        </div>
      </MemberShell>
    );
  }

  if (!film) {
    return (
      <MemberShell>
        <div className="py-24 text-center">
          <FilmIcon className="mx-auto h-10 w-10 text-muted-foreground/50" />
          <p className="mt-4 text-lg font-bold">Film not found</p>
          <Link
            to="/films"
            className="mt-3 inline-block rounded-full bg-foreground px-5 py-2 text-[13px] font-bold text-background"
          >
            Back to films
          </Link>
        </div>
      </MemberShell>
    );
  }

  const reactions = reactionsQuery.data ?? { likes: 0, dislikes: 0, mine: null };
  const directorHref = film.director_username
    ? `/u/${film.director_username}`
    : film.director_id
      ? `/u/${film.director_id}`
      : null;
  const directorName = film.director_name || film.director_username || "Whisper Director";

  return (
    <MemberShell>
      <ShareContentDialog
        open={showShare}
        onOpenChange={setShowShare}
        kicker="WHISPER FILM"
        title={film.title}
        subtitle={`A ${directorName} film`}
        imageUrl={film.poster_url}
        embedBody={encodeFilmEmbed({
          id: film.id,
          title: film.title,
          director: directorName,
          poster: film.poster_url,
          duration: film.duration_seconds,
        })}
        linkUrl={siteUrl(`/films/${id}`)}
      />
      {/* Generous top padding so the player breathes away from the nav
          (tight when rendered inside the app chrome). */}
      <div
        className={cn(
          "mx-auto max-w-3xl px-4 pb-20 lg:max-w-6xl",
          isMember ? "pt-4 sm:pt-6" : "pt-20 sm:pt-24"
        )}
      >
        <Link
          to="/films"
          className="mb-5 inline-flex items-center gap-1.5 text-[13.5px] font-bold text-muted-foreground transition-colors hover:text-foreground"
        >
          <ArrowLeft className="h-4 w-4" /> All films
        </Link>

        {/* Desktop: cinema layout — the film + credits stay big on the left,
            the conversation (comments + moments) becomes a side rail. */}
        <div className="lg:grid lg:grid-cols-[minmax(0,7fr)_minmax(0,5fr)] lg:items-start lg:gap-8">
          <div className="min-w-0">

        {/* Cinema player — Whisper-styled custom player, letterboxed */}
        <Reveal variant="up">
          <WhisperFilmPlayer
            src={film.video_url}
            poster={film.poster_url ?? undefined}
            markers={allTimestamps.map((t) => t.time_seconds)}
            videoRef={videoRef}
            title={film.title}
          />
        </Reveal>

        {/* Festival title block */}
        <Reveal variant="up">
          <div className="mt-7">
            <div className="flex items-center gap-2">
              <span className="inline-flex items-center gap-1.5 rounded-full bg-foreground/5 px-3 py-1 text-[10px] font-black uppercase tracking-[0.18em] text-muted-foreground">
                <FilmIcon className="h-3 w-3" /> Featured Film
              </span>
              {film.featured_date && (
                <span className="text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
                  {new Date(film.featured_date + "T00:00:00").toLocaleDateString("en-US", {
                    weekday: "long",
                    month: "long",
                    day: "numeric",
                    year: "numeric",
                  })}
                </span>
              )}
            </div>
            <h1 className="mt-3 font-display text-3xl font-black tracking-[-0.01em] sm:text-[34px]">
              {film.title}
            </h1>
            {film.synopsis && (
              <p className="mt-3 max-w-2xl text-[15px] leading-relaxed text-muted-foreground">
                {film.synopsis}
              </p>
            )}

            {/* Director + studio credit — director name links to their profile */}
            <div className="mt-5 flex flex-wrap items-center gap-x-4 gap-y-2">
              <span className="inline-flex items-center gap-1.5 text-[12.5px] font-bold text-muted-foreground">
                <Clapperboard className="h-3.5 w-3.5" />
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
              <span className="inline-flex items-center gap-1.5 text-[12.5px] font-bold text-muted-foreground">
                <Flame className="h-3.5 w-3.5 text-orange-500" />
                Whisper Studios
              </span>
              {film.duration_seconds ? (
                <span className="font-mono text-[12px] font-semibold text-muted-foreground/70">
                  {formatTimecode(film.duration_seconds)}
                </span>
              ) : null}
            </div>
          </div>
        </Reveal>

        {/* YouTube-style engagement bar */}
        <Reveal variant="up">
          <EngagementBar
            reactions={reactions}
            commentCount={commentsQuery.data?.length ?? 0}
            myReaction={reactions.mine}
            onReact={(w) => reactMutation.mutate(w)}
            onShare={() => shareMutation.mutate()}
            isReacting={reactMutation.isPending}
            notesCount={allTimestamps.length}
            canNote={allowed}
            onToggleNotes={() => setNotesOpen((v) => !v)}
            notesOpen={notesOpen}
          />
        </Reveal>

          </div>

          <div className="min-w-0">
        {/* Comments section */}
        <Reveal variant="up">
          <CommentsSection
            filmId={id}
            comments={commentsQuery.data ?? []}
            currentUserId={profile?.user_id}
            isLoading={commentsQuery.isLoading}
          />
        </Reveal>

        {/* Robust timestamp / review rail — opens via the Notes button */}
        {notesOpen && (
          <Reveal variant="up">
            <TimestampRail
              allowed={allowed}
              timestamps={timestamps}
              allTimestamps={allTimestamps}
              filter={filter}
              setFilter={setFilter}
              newLabel={newLabel}
              setNewLabel={setNewLabel}
              newCategory={newCategory}
              setNewCategory={setNewCategory}
              createMutation={createMutation}
              deleteMutation={deleteMutation}
              videoRef={videoRef}
              currentUserId={profile?.user_id}
              filmTitle={film.title}
              onClose={() => setNotesOpen(false)}
            />
          </Reveal>
        )}
          </div>
        </div>
      </div>
    </MemberShell>
  );
}

/* ------------------------------------------------------------------ */
/* Whisper-styled custom film player                                   */
/* ------------------------------------------------------------------ */

/**
 * A cinema-grade custom video player in Whisper's black & white aesthetic.
 * The native controls are hidden; a custom overlay renders a big center
 * play/pause beacon, a bottom scrubber with the timecode, mute toggle,
 * captions toggle, and a fullscreen toggle. The controls auto-hide after a
 * few seconds of inactivity, and a single tap on the video toggles
 * play/pause. Designed to feel like a quiet, premium cinema room rather than
 * a generic HTML5 video.
 */
function WhisperFilmPlayer({
  src,
  poster,
  videoRef,
  title,
  markers = [],
}: {
  src: string;
  poster?: string;
  videoRef: React.RefObject<HTMLVideoElement | null>;
  title: string;
  /** Timestamped moments — rendered as dots ON the timeline (seconds). */
  markers?: number[];
}) {
  const wrapRef = useRef<HTMLDivElement | null>(null);
  const [playing, setPlaying] = useState<boolean>(false);
  const [muted, setMuted] = useState<boolean>(false);
  const [current, setCurrent] = useState<number>(0);
  const [duration, setDuration] = useState<number>(0);
  const [buffered, setBuffered] = useState<number>(0);
  const [showControls, setShowControls] = useState<boolean>(true);
  const [seeking, setSeeking] = useState<boolean>(false);
  const [isFullscreen, setIsFullscreen] = useState<boolean>(false);
  const [captionsOn, setCaptionsOn] = useState<boolean>(false);
  const [captionTrack, setCaptionTrack] = useState<TextTrack | null>(null);
  const hideTimer = useRef<number | null>(null);
  const progressRef = useRef<HTMLDivElement | null>(null);

  // Auto-hide controls after 3.5s of inactivity while playing.
  useEffect(() => {
    if (!playing || seeking) return;
    if (hideTimer.current) window.clearTimeout(hideTimer.current);
    hideTimer.current = window.setTimeout(() => setShowControls(false), 3500);
    return () => {
      if (hideTimer.current) window.clearTimeout(hideTimer.current);
    };
  }, [playing, seeking, showControls]);

  // Track fullscreen state changes (including Esc to exit).
  useEffect(() => {
    const onFsChange = (): void => {
      setIsFullscreen(!!document.fullscreenElement);
    };
    document.addEventListener("fullscreenchange", onFsChange);
    return () => document.removeEventListener("fullscreenchange", onFsChange);
  }, []);

  // Locate the first text track on the video element for caption toggling.
  useEffect(() => {
    const v = videoRef.current;
    if (!v) return;
    const track = v.textTracks?.[0] ?? null;
    if (track) {
      track.mode = "hidden";
      setCaptionTrack(track);
    }
  }, [videoRef]);

  const wake = (): void => {
    setShowControls(true);
    if (hideTimer.current) window.clearTimeout(hideTimer.current);
  };

  const togglePlay = (): void => {
    const v = videoRef.current;
    if (!v) return;
    if (v.paused) void v.play();
    else v.pause();
  };

  const onTimeUpdate = (): void => {
    const v = videoRef.current;
    if (!v || seeking) return;
    setCurrent(v.currentTime);
  };

  const onLoadedMetadata = (): void => {
    const v = videoRef.current;
    if (v) setDuration(v.duration || 0);
  };

  const onProgress = (): void => {
    const v = videoRef.current;
    if (!v) return;
    try {
      const ranges = v.buffered;
      if (ranges.length > 0) setBuffered(ranges.end(ranges.length - 1));
    } catch {
      /* buffered ranges unavailable */
    }
  };

  /** ±10s transport skip — the double-tap language, as buttons. */
  const skip = (delta: number): void => {
    const v = videoRef.current;
    if (!v) return;
    const cap = duration > 0 ? Math.max(0, duration - 0.25) : Number.MAX_SAFE_INTEGER;
    const target = Math.min(Math.max(0, v.currentTime + delta), cap);
    v.currentTime = target;
    setCurrent(target);
    wake();
  };

  const seekFromEvent = (clientX: number): void => {
    const v = videoRef.current;
    const bar = progressRef.current;
    if (!v || !bar || !duration) return;
    const rect = bar.getBoundingClientRect();
    const ratio = Math.min(1, Math.max(0, (clientX - rect.left) / rect.width));
    v.currentTime = ratio * duration;
    setCurrent(ratio * duration);
  };

  const toggleFullscreen = (): void => {
    const el = wrapRef.current;
    if (!el) return;
    if (!document.fullscreenElement) {
      void el.requestFullscreen?.().catch(() => {
        toast.error("Fullscreen isn't available here.");
      });
    } else {
      void document.exitFullscreen?.();
    }
  };

  const toggleCaptions = (): void => {
    if (captionTrack) {
      const next = captionTrack.mode === "showing" ? "hidden" : "showing";
      captionTrack.mode = next;
      setCaptionsOn(next === "showing");
    } else {
      // No track embedded — try to load one from the same URL with a .vtt
      // extension as a best-effort. If nothing exists, surface a message.
      const v = videoRef.current;
      if (v) {
        const trackEl = document.createElement("track");
        trackEl.kind = "subtitles";
        trackEl.label = "English";
        trackEl.srclang = "en";
        trackEl.src = src.replace(/\.(mp4|mov|webm|m4v|avi|mkv)$/i, ".vtt");
        trackEl.default = true;
        v.appendChild(trackEl);
        trackEl.addEventListener("load", () => {
          const t = v.textTracks?.[v.textTracks.length - 1] ?? null;
          if (t) {
            t.mode = "showing";
            setCaptionTrack(t);
            setCaptionsOn(true);
          }
        });
        trackEl.addEventListener("error", () => {
          toast.error("No captions track found for this film.");
        });
      }
    }
  };

  const progressPct = duration > 0 ? (current / duration) * 100 : 0;
  const bufferedPct = duration > 0 ? Math.min(100, (buffered / duration) * 100) : 0;
  const hasCaptions = !!captionTrack || /\.(mp4|mov|webm|m4v|avi|mkv)$/i.test(src);

  return (
    <div
      ref={wrapRef}
      className={`group relative overflow-hidden bg-black shadow-[0_30px_70px_-15px_rgba(0,0,0,0.5)] ring-1 ring-white/10 ${isFullscreen ? "flex h-screen w-screen items-center justify-center rounded-none" : "rounded-[24px]"}`}
      onMouseMove={wake}
      onMouseLeave={() => playing && setShowControls(false)}
    >
      <video
        ref={videoRef}
        src={src}
        poster={poster}
        playsInline
        preload="metadata"
        crossOrigin="anonymous"
        className={`${isFullscreen ? "max-h-screen max-w-full" : "aspect-video w-full"} bg-black`}
        onClick={() => {
          wake();
          togglePlay();
        }}
        onPlay={() => { setPlaying(true); wake(); }}
        onPause={() => { setPlaying(false); setShowControls(true); }}
        onTimeUpdate={onTimeUpdate}
        onLoadedMetadata={onLoadedMetadata}
        onProgress={onProgress}
        onEnded={() => { setPlaying(false); setShowControls(true); }}
      />

      {/* Center play/pause beacon — fades out while playing */}
      <button
        type="button"
        onClick={(e) => { e.stopPropagation(); wake(); togglePlay(); }}
        className={`absolute inset-0 flex items-center justify-center transition-opacity duration-500 ${showControls && !playing ? "opacity-100" : "opacity-0 pointer-events-none"}`}
        aria-label={playing ? "Pause" : "Play"}
      >
        <span className="flex h-20 w-20 items-center justify-center rounded-full bg-white/8 ring-1 ring-white/30 backdrop-blur-md transition-transform duration-300 group-hover:scale-110">
          <Play className="ml-1.5 h-8 w-8 fill-white text-white drop-shadow-lg" />
        </span>
      </button>

      {/* Pause indicator — brief when tapping to pause */}
      {showControls && playing && (
        <button
          type="button"
          onClick={(e) => { e.stopPropagation(); wake(); togglePlay(); }}
          className="absolute inset-0 flex items-center justify-center"
          aria-label="Pause"
        >
          <span className="flex h-16 w-16 items-center justify-center rounded-full bg-black/40 ring-1 ring-white/20 backdrop-blur-sm">
            <Pause className="h-6 w-6 fill-white text-white" />
          </span>
        </button>
      )}

      {/* Fullscreen badge when in fullscreen */}
      {isFullscreen && (
        <div className="pointer-events-none absolute left-4 top-4 inline-flex items-center gap-1.5 rounded-full bg-white/10 px-3 py-1.5 text-[10px] font-black uppercase tracking-[0.18em] text-white/90 ring-1 ring-white/20 backdrop-blur-md">
          <Minimize className="h-3 w-3" /> Fullscreen
        </div>
      )}

      {/* Bottom control bar — scrubber + time + mute + captions + fullscreen */}
      <div
        className={`absolute inset-x-0 bottom-0 z-10 bg-gradient-to-t from-black/85 via-black/30 to-transparent px-4 pb-3 pt-10 transition-opacity duration-300 ${showControls ? "opacity-100" : "opacity-0 pointer-events-none"}`}
      >
        {/* Scrubber */}
        <div
          ref={progressRef}
          className="group/scrub relative flex h-5 cursor-pointer items-center"
          onMouseDown={(e) => { setSeeking(true); seekFromEvent(e.clientX); }}
          onMouseMove={(e) => seeking && seekFromEvent(e.clientX)}
          onMouseUp={() => setSeeking(false)}
          onMouseLeave={() => setSeeking(false)}
        >
          <div className="relative h-1 w-full rounded-full bg-white/20">
            {/* Buffered range — mint-washed track ahead of the playhead. */}
            <div
              className="absolute left-0 top-0 h-full rounded-full bg-[#33D499]/30"
              style={{ width: `${bufferedPct}%` }}
            />
            {/* Played range — Jasper's ghost mint. */}
            <div
              className="absolute left-0 top-0 h-full rounded-full bg-[#33D499] transition-[width] duration-100"
              style={{ width: `${progressPct}%` }}
            />
            {/* Moment markers — the timestamped moments live ON the timeline. */}
            {duration > 0 &&
              markers.map((m, i) => (
                <span
                  key={`${m}-${i}`}
                  className="absolute top-1/2 h-[5px] w-[5px] -translate-x-1/2 -translate-y-1/2 rounded-full bg-white ring-1 ring-black/50"
                  style={{ left: `${(Math.min(m, duration) / duration) * 100}%` }}
                />
              ))}
            {/* Knob — mint, with a soft glow so it reads on dark frames. */}
            <div
              className="absolute top-1/2 h-3 w-3 -translate-x-1/2 -translate-y-1/2 rounded-full bg-[#7CEBC4] shadow-[0_0_8px_rgba(51,212,153,0.8)]"
              style={{ left: `${progressPct}%` }}
            />
          </div>
        </div>

        {/* Time + controls row */}
        <div className="mt-1.5 flex items-center gap-2">
          <span className="font-mono text-[11px] font-bold tabular-nums text-white/80">
            {formatTimecode(current)}
            <span className="mx-1 text-white/30">/</span>
            {formatTimecode(duration)}
          </span>
          <div className="ml-auto flex items-center gap-1">
            <button
              type="button"
              onClick={(e) => { e.stopPropagation(); skip(-10); }}
              className="flex h-7 w-7 items-center justify-center rounded-full text-white/80 transition-colors hover:bg-white/10 hover:text-white"
              aria-label="Back 10 seconds"
              title="Back 10s"
            >
              <RotateCcw className="h-4 w-4" />
            </button>
            <button
              type="button"
              onClick={(e) => { e.stopPropagation(); skip(10); }}
              className="flex h-7 w-7 items-center justify-center rounded-full text-white/80 transition-colors hover:bg-white/10 hover:text-white"
              aria-label="Forward 10 seconds"
              title="Forward 10s"
            >
              <RotateCw className="h-4 w-4" />
            </button>
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation();
                const v = videoRef.current;
                if (!v) return;
                v.muted = !v.muted;
                setMuted(v.muted);
              }}
              className="flex h-7 w-7 items-center justify-center rounded-full text-white/80 transition-colors hover:bg-white/10 hover:text-white"
              aria-label={muted ? "Unmute" : "Mute"}
            >
              {muted ? <VolumeX className="h-4 w-4" /> : <Volume2 className="h-4 w-4" />}
            </button>
            {hasCaptions && (
              <button
                type="button"
                onClick={(e) => { e.stopPropagation(); toggleCaptions(); }}
                className={`flex h-7 w-7 items-center justify-center rounded-full transition-colors hover:bg-white/10 ${
                  captionsOn ? "text-white" : "text-white/60"
                }`}
                aria-label={captionsOn ? "Turn off captions" : "Turn on captions"}
                title={captionsOn ? "Captions on" : "Captions"}
              >
                <Subtitles className="h-4 w-4" />
              </button>
            )}
            <button
              type="button"
              onClick={(e) => { e.stopPropagation(); toggleFullscreen(); }}
              className="flex h-7 w-7 items-center justify-center rounded-full text-white/80 transition-colors hover:bg-white/10 hover:text-white"
              aria-label={isFullscreen ? "Exit fullscreen" : "Fullscreen"}
              title={isFullscreen ? "Exit fullscreen" : "Fullscreen"}
            >
              {isFullscreen ? <Minimize className="h-4 w-4" /> : <Maximize className="h-4 w-4" />}
            </button>
          </div>
          <span className="max-w-[45%] truncate text-[11px] font-bold uppercase tracking-wider text-white/50">
            {title}
          </span>
        </div>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Engagement bar — like / dislike / comment / share / notes            */
/* ------------------------------------------------------------------ */

function EngagementBar({
  reactions,
  commentCount,
  myReaction,
  onReact,
  onShare,
  isReacting,
  notesCount,
  canNote,
  onToggleNotes,
  notesOpen,
}: {
  reactions: { likes: number; dislikes: number };
  commentCount: number;
  myReaction: "like" | "dislike" | null;
  onReact: (w: "like" | "dislike") => void;
  onShare: () => void;
  isReacting: boolean;
  notesCount: number;
  canNote: boolean;
  onToggleNotes: () => void;
  notesOpen: boolean;
}) {
  return (
    <div className="mt-6 rounded-2xl border border-border bg-card p-1.5">
      <div className="flex flex-wrap items-center gap-1">
        {/* Like */}
        <button
          onClick={() => onReact("like")}
          disabled={isReacting}
          className={`group inline-flex items-center gap-2 rounded-xl px-4 py-2.5 text-[13.5px] font-bold transition-all active:scale-95 disabled:opacity-50 ${
            myReaction === "like"
              ? "bg-foreground text-background"
              : "text-muted-foreground hover:bg-secondary hover:text-foreground"
          }`}
        >
          <ThumbsUp
            className={`h-[18px] w-[18px] transition-transform group-active:scale-90 ${
              myReaction === "like" ? "fill-current" : ""
            }`}
          />
          <span className="tabular-nums">{reactions.likes > 0 ? formatCount(reactions.likes) : "Like"}</span>
        </button>

        {/* Dislike */}
        <button
          onClick={() => onReact("dislike")}
          disabled={isReacting}
          className={`group inline-flex items-center gap-2 rounded-xl px-4 py-2.5 text-[13.5px] font-bold transition-all active:scale-95 disabled:opacity-50 ${
            myReaction === "dislike"
              ? "bg-foreground text-background"
              : "text-muted-foreground hover:bg-secondary hover:text-foreground"
          }`}
        >
          <ThumbsDown
            className={`h-[18px] w-[18px] transition-transform group-active:scale-90 ${
              myReaction === "dislike" ? "fill-current" : ""
            }`}
          />
          <span className="tabular-nums">{reactions.dislikes > 0 ? formatCount(reactions.dislikes) : "Dislike"}</span>
        </button>

        <div className="mx-0.5 h-7 w-px bg-border" />

        {/* Comment count (scrolls to comments) */}
        <a
          href="#comments"
          className="group inline-flex items-center gap-2 rounded-xl px-4 py-2.5 text-[13.5px] font-bold text-muted-foreground transition-all hover:bg-secondary hover:text-foreground active:scale-95"
        >
          <MessagesSquare className="h-[18px] w-[18px] transition-transform group-active:scale-90" />
          <span className="tabular-nums">{commentCount > 0 ? formatCount(commentCount) : "Comment"}</span>
        </a>

        {/* Share */}
        <button
          onClick={onShare}
          className="group inline-flex items-center gap-2 rounded-xl px-4 py-2.5 text-[13.5px] font-bold text-muted-foreground transition-all hover:bg-secondary hover:text-foreground active:scale-95"
        >
          <Share2 className="h-[18px] w-[18px] transition-transform group-active:scale-90" />
          <span>Share</span>
        </button>

        {/* Notes — only for permissioned users (blogger, director, creator, admins) */}
        {canNote && (
          <>
            <div className="mx-0.5 h-7 w-px bg-border" />
            <button
              onClick={onToggleNotes}
              className={`group inline-flex items-center gap-2 rounded-xl px-4 py-2.5 text-[13.5px] font-bold transition-all active:scale-95 ${
                notesOpen
                  ? "bg-foreground text-background"
                  : "text-muted-foreground hover:bg-secondary hover:text-foreground"
              }`}
            >
              <ListChecks className="h-[18px] w-[18px] transition-transform group-active:scale-90" />
              <span>Notes {notesCount > 0 ? formatCount(notesCount) : ""}</span>
            </button>
          </>
        )}
      </div>

      {/* Reaction ratio bar — a thin visual of likes vs dislikes */}
      {(reactions.likes > 0 || reactions.dislikes > 0) && (
        <div className="mt-2 flex h-1 overflow-hidden rounded-full bg-secondary">
          <div
            className="bg-foreground/70 transition-all duration-300"
            style={{ width: `${(reactions.likes / (reactions.likes + reactions.dislikes)) * 100}%` }}
          />
        </div>
      )}
    </div>
  );
}

function formatCount(n: number): string {
  if (n >= 1000) return `${(n / 1000).toFixed(1).replace(/\.0$/, "")}K`;
  return String(n);
}

/* ------------------------------------------------------------------ */
/* Comments section                                                     */
/* ------------------------------------------------------------------ */

function CommentsSection({
  filmId,
  comments,
  currentUserId,
  isLoading,
}: {
  filmId: string;
  comments: FilmComment[];
  currentUserId?: string;
  isLoading: boolean;
}) {
  const queryClient = useQueryClient();
  const [body, setBody] = useState<string>("");
  const [replyTo, setReplyTo] = useState<FilmComment | null>(null);

  const postMutation = useMutation({
    mutationFn: () => createFilmComment({ filmId, body, replyToCommentId: replyTo?.id ?? null }),
    onSuccess: () => {
      setBody("");
      setReplyTo(null);
      void queryClient.invalidateQueries({ queryKey: ["film-comments", filmId] });
    },
    onError: (err) =>
      toast.error(err instanceof Error ? err.message : "Couldn't post that comment."),
  });

  const deleteCommentMutation = useMutation({
    mutationFn: (commentId: string) => deleteFilmComment(commentId),
    onSuccess: () => {
      toast.success("Comment deleted.");
      void queryClient.invalidateQueries({ queryKey: ["film-comments", filmId] });
    },
    onError: () => toast.error("Couldn't delete that comment."),
  });

  const editCommentMutation = useMutation({
    mutationFn: ({ id, body }: { id: string; body: string }) => editFilmComment(id, body),
    onSuccess: () => {
      toast.success("Comment updated.");
      void queryClient.invalidateQueries({ queryKey: ["film-comments", filmId] });
    },
    onError: () => toast.error("Couldn't edit that comment."),
  });

  return (
    <div id="comments" className="mt-6 overflow-hidden rounded-[20px] border border-border bg-card">
      {/* Header */}
      <div className="border-b border-border/60 px-5 py-4">
        <div className="flex items-center gap-2">
          <MessagesSquare className="h-4 w-4 text-muted-foreground" />
          <h2 className="text-[14px] font-extrabold">
            Comments {comments.length > 0 && <span className="text-muted-foreground">· {comments.length}</span>}
          </h2>
        </div>
      </div>

      {/* Composer */}
      <div className="border-b border-border/60 px-5 py-4">
        {replyTo && (
          <div className="mb-2 flex items-center justify-between rounded-lg bg-secondary/50 px-3 py-2 text-[12px]">
            <span className="truncate text-muted-foreground">
              Replying to{" "}
              <span className="font-bold text-foreground">
                @{replyTo.author_username ?? "member"}
              </span>
            </span>
            <button
              onClick={() => setReplyTo(null)}
              className="text-[11px] font-bold text-muted-foreground hover:text-foreground"
            >
              Cancel
            </button>
          </div>
        )}
        <div className="flex items-start gap-2.5">
          <textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder="Add a comment…"
            rows={2}
            className="min-w-0 flex-1 resize-none rounded-xl border border-border bg-background px-3.5 py-2.5 text-[14px] outline-none placeholder:text-muted-foreground/60 focus:border-foreground/40"
            onKeyDown={(e) => {
              if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
                e.preventDefault();
                if (body.trim()) postMutation.mutate();
              }
            }}
          />
          <button
            onClick={() => postMutation.mutate()}
            disabled={!body.trim() || postMutation.isPending}
            className="flex shrink-0 items-center gap-1.5 rounded-xl bg-foreground px-4 py-2.5 text-[13px] font-bold text-background transition-transform active:scale-95 disabled:opacity-40"
          >
            {postMutation.isPending ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              <Plus className="h-4 w-4" />
            )}
            Post
          </button>
        </div>
      </div>

      {/* Threaded list */}
      <div className="px-5 py-4">
        {isLoading ? (
          <div className="flex justify-center py-8">
            <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
          </div>
        ) : comments.length === 0 ? (
          <div className="py-8 text-center">
            <MessagesSquare className="mx-auto h-7 w-7 text-muted-foreground/30" />
            <p className="mt-3 text-[13px] font-semibold text-muted-foreground">
              No comments yet.
            </p>
            <p className="mt-1 text-[12px] text-muted-foreground/70">
              Be the first to share what you thought.
            </p>
          </div>
        ) : (
          <div className="space-y-5">
            {comments.map((c) => (
              <CommentRow
                key={c.id}
                comment={c}
                canDelete={c.user_id === currentUserId}
                canEdit={c.user_id === currentUserId}
                onDelete={() => deleteCommentMutation.mutate(c.id)}
                onEdit={(body) => editCommentMutation.mutate({ id: c.id, body })}
                onReply={() => setReplyTo(c)}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function CommentRow({
  comment,
  canDelete,
  canEdit,
  onDelete,
  onEdit,
  onReply,
}: {
  comment: FilmComment;
  canDelete: boolean;
  canEdit: boolean;
  onDelete: () => void;
  onEdit: (body: string) => void;
  onReply: () => void;
}) {
  const [editing, setEditing] = useState<boolean>(false);
  const [editBody, setEditBody] = useState<string>(comment.body);
  const authorHref = comment.author_username
    ? `/u/${comment.author_username}`
    : `/u/${comment.user_id}`;
  const authorLabel = comment.author_username
    ? `@${comment.author_username}`
    : comment.author_name || "Member";

  return (
    <div className="flex items-start gap-3">
      {/* Avatar — real profile picture when available, initials otherwise */}
      <Link
        to={authorHref}
        className="shrink-0"
      >
        {comment.author_avatar_url ? (
          <img
            src={comment.author_avatar_url}
            alt={authorLabel}
            className="h-9 w-9 rounded-full object-cover ring-1 ring-border"
          />
        ) : (
          <span className="flex h-9 w-9 items-center justify-center rounded-full bg-foreground/8 text-[11px] font-black uppercase text-foreground/70 transition-colors hover:bg-foreground/12">
            {authorLabel.replace("@", "").slice(0, 2)}
          </span>
        )}
      </Link>
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <Link
            to={authorHref}
            className="text-[12.5px] font-bold text-foreground hover:underline"
          >
            {authorLabel}
          </Link>
          <span className="text-[11px] text-muted-foreground/70">
            {timeAgo(comment.created_at)}
          </span>
        </div>

        {editing ? (
          <div className="mt-1.5 flex items-start gap-2">
            <textarea
              value={editBody}
              onChange={(e) => setEditBody(e.target.value)}
              rows={2}
              className="min-w-0 flex-1 resize-none rounded-lg border border-border bg-background px-3 py-2 text-[13.5px] outline-none focus:border-foreground/40"
            />
            <div className="flex shrink-0 flex-col gap-1">
              <button
                onClick={() => {
                  if (editBody.trim()) {
                    onEdit(editBody);
                    setEditing(false);
                  }
                }}
                className="rounded-lg bg-foreground px-3 py-1.5 text-[11px] font-bold text-background"
              >
                Save
              </button>
              <button
                onClick={() => {
                  setEditing(false);
                  setEditBody(comment.body);
                }}
                className="rounded-lg bg-secondary px-3 py-1.5 text-[11px] font-bold text-muted-foreground"
              >
                Cancel
              </button>
            </div>
          </div>
        ) : (
          <p className="mt-1 whitespace-pre-wrap text-[13.5px] leading-relaxed text-foreground/90">
            {comment.body}
          </p>
        )}

        {/* Actions */}
        {!editing && (
          <div className="mt-1.5 flex items-center gap-3">
            <button
              onClick={onReply}
              className="text-[11px] font-bold text-muted-foreground/70 transition-colors hover:text-foreground"
            >
              Reply
            </button>
            {canEdit && (
              <button
                onClick={() => setEditing(true)}
                className="inline-flex items-center gap-1 text-[11px] font-bold text-muted-foreground/70 transition-colors hover:text-foreground"
              >
                <Pencil className="h-3 w-3" /> Edit
              </button>
            )}
          </div>
        )}

        {/* Threaded replies */}
        {comment.replies && comment.replies.length > 0 && (
          <div className="mt-3 space-y-3 border-l-2 border-border/60 pl-3">
            {comment.replies.map((reply) => {
              const replyHref = reply.author_username
                ? `/u/${reply.author_username}`
                : `/u/${reply.user_id}`;
              const replyLabel = reply.author_username
                ? `@${reply.author_username}`
                : reply.author_name || "Member";
              return (
                <div key={reply.id} className="flex items-start gap-2.5">
                  <Link to={replyHref} className="shrink-0">
                    {reply.author_avatar_url ? (
                      <img
                        src={reply.author_avatar_url}
                        alt={replyLabel}
                        className="h-7 w-7 rounded-full object-cover ring-1 ring-border"
                      />
                    ) : (
                      <span className="flex h-7 w-7 items-center justify-center rounded-full bg-foreground/8 text-[10px] font-black uppercase text-foreground/70">
                        {replyLabel.replace("@", "").slice(0, 2)}
                      </span>
                    )}
                  </Link>
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <Link
                        to={replyHref}
                        className="text-[12px] font-bold text-foreground hover:underline"
                      >
                        {replyLabel}
                      </Link>
                      <span className="text-[10px] text-muted-foreground/70">
                        {timeAgo(reply.created_at)}
                      </span>
                    </div>
                    <p className="mt-0.5 whitespace-pre-wrap text-[13px] leading-relaxed text-foreground/90">
                      {reply.body}
                    </p>
                    {reply.user_id === comment.user_id && (
                      <button
                        onClick={() => onDelete}
                        className="mt-1 inline-flex items-center gap-1 text-[10px] font-bold text-muted-foreground/60 transition-colors hover:text-red-500"
                      >
                        <Trash2 className="h-2.5 w-2.5" /> Delete
                      </button>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Delete own top-level comment */}
      {canDelete && !editing && (
        <button
          onClick={onDelete}
          className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-red-500/10 hover:text-red-500"
          aria-label="Delete comment"
        >
          <Trash2 className="h-3.5 w-3.5" />
        </button>
      )}
    </div>
  );
}

function timeAgo(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return "now";
  if (mins < 60) return `${mins}m`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h`;
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}d`;
  return new Date(iso).toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

/* ------------------------------------------------------------------ */
/* Timestamp rail                                                      */
/* ------------------------------------------------------------------ */

interface TimestampRailProps {
  allowed: boolean;
  timestamps: FilmTimestamp[];
  allTimestamps: FilmTimestamp[];
  filter: TimestampCategory | "all";
  setFilter: (f: TimestampCategory | "all") => void;
  newLabel: string;
  setNewLabel: (s: string) => void;
  newCategory: TimestampCategory;
  setNewCategory: (c: TimestampCategory) => void;
  createMutation: ReturnType<typeof useMutation<unknown, Error, unknown>>;
  deleteMutation: ReturnType<typeof useMutation<void, Error, string>>;
  videoRef: React.RefObject<HTMLVideoElement | null>;
  currentUserId?: string;
  filmTitle: string;
  onClose: () => void;
}

function TimestampRail({
  allowed,
  timestamps,
  allTimestamps,
  filter,
  setFilter,
  newLabel,
  setNewLabel,
  newCategory,
  setNewCategory,
  createMutation,
  deleteMutation,
  videoRef,
  currentUserId,
  filmTitle,
  onClose,
}: TimestampRailProps) {
  const currentTime = videoRef.current?.currentTime ?? 0;

  // Count per category for the filter chips.
  const counts: Record<string, number> = { all: allTimestamps.length };
  for (const t of allTimestamps) {
    const cat = deriveCategory(t.label);
    counts[cat] = (counts[cat] ?? 0) + 1;
  }

  return (
    <div className="mt-6 overflow-hidden rounded-[20px] border border-border bg-card">
      {/* Header */}
      <div className="border-b border-border/60 px-5 py-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <ListChecks className="h-4 w-4 text-muted-foreground" />
            <h2 className="text-[14px] font-extrabold">Notes & reviews</h2>
          </div>
          <div className="flex items-center gap-3">
            {allTimestamps.length > 0 && (
              <span className="text-[11px] font-bold text-muted-foreground">
                {allTimestamps.length} mark{allTimestamps.length === 1 ? "" : "s"}
              </span>
            )}
            <button
              onClick={onClose}
              className="inline-flex items-center gap-1 text-[11px] font-bold text-muted-foreground transition-colors hover:text-foreground"
            >
              <X className="h-3 w-3" /> Close
            </button>
          </div>
        </div>
        <p className="mt-1.5 text-[12.5px] leading-relaxed text-muted-foreground">
          {allowed
            ? "Mark a moment in the film — add a note, a highlight, a review, a question, or a clip."
            : "Bloggers, creators, directors, and mods can mark moments and review this film."}
        </p>

        {/* Featured-film credit tag */}
        <div className="mt-2.5 flex flex-wrap items-center gap-1.5">
          <span className="inline-flex items-center gap-1 rounded-full bg-foreground/[0.04] px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-wider text-muted-foreground">
            <FilmIcon className="h-2.5 w-2.5" /> Featured Film: {filmTitle}
          </span>
          <span className="inline-flex items-center gap-1 rounded-full bg-orange-500/8 px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-wider text-orange-600">
            <Flame className="h-2.5 w-2.5" /> Whisper Studios
          </span>
        </div>
      </div>

      {/* Composer */}
      {allowed && (
        <div className="border-b border-border/60 px-5 py-4">
          {/* Category selector */}
          <div className="mb-2.5 flex flex-wrap gap-1.5">
            {CATEGORY_ORDER.map((cat) => {
              const meta = CATEGORIES[cat];
              const active = newCategory === cat;
              return (
                <button
                  key={cat}
                  type="button"
                  onClick={() => setNewCategory(cat)}
                  className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-[11px] font-bold transition-all active:scale-95 ${
                    active
                      ? "bg-foreground text-background"
                      : `${meta.bg} ${meta.color}`
                  }`}
                >
                  <meta.icon className="h-3 w-3" />
                  {meta.label}
                </button>
              );
            })}
          </div>

          {/* Input + mark button */}
          <div className="flex flex-col gap-2 sm:flex-row">
            <input
              value={newLabel}
              onChange={(e) => setNewLabel(e.target.value)}
              placeholder={placeholderForCategory(newCategory)}
              className="flex-1 rounded-xl border border-border bg-background px-3.5 py-2.5 text-[14px] outline-none placeholder:text-muted-foreground/60 focus:border-foreground/40"
              onKeyDown={(e) => {
                if (e.key === "Enter" && newLabel.trim() && !createMutation.isPending) {
                  createMutation.mutate(undefined);
                }
              }}
            />
            <button
              onClick={() => createMutation.mutate(undefined)}
              disabled={!newLabel.trim() || createMutation.isPending}
              className="flex shrink-0 items-center justify-center gap-1.5 rounded-xl bg-foreground px-4 py-2.5 text-[13px] font-bold text-background transition-transform active:scale-[0.97] disabled:opacity-40"
            >
              {createMutation.isPending ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <Plus className="h-4 w-4" />
              )}
              Mark {formatTimecode(currentTime)}
            </button>
          </div>
        </div>
      )}

      {/* Category filter chips */}
      {allTimestamps.length > 0 && (
        <div className="flex flex-wrap items-center gap-1.5 border-b border-border/60 px-5 py-2.5">
          <button
            onClick={() => setFilter("all")}
            className={`rounded-full px-2.5 py-1 text-[11px] font-bold transition-colors ${
              filter === "all"
                ? "bg-foreground text-background"
                : "bg-secondary text-muted-foreground hover:text-foreground"
            }`}
          >
            All {counts.all ?? 0}
          </button>
          {CATEGORY_ORDER.map((cat) => {
            const count = counts[cat] ?? 0;
            if (count === 0) return null;
            const meta = CATEGORIES[cat];
            return (
              <button
                key={cat}
                onClick={() => setFilter(cat)}
                className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[11px] font-bold transition-colors ${
                  filter === cat
                    ? "bg-foreground text-background"
                    : `${meta.bg} ${meta.color}`
                }`}
              >
                <meta.icon className="h-2.5 w-2.5" />
                {meta.label} {count}
              </button>
            );
          })}
        </div>
      )}

      {/* Timestamp list */}
      <div className="px-5 py-4">
        {timestamps.length === 0 ? (
          <div className="py-8 text-center">
            <Eye className="mx-auto h-8 w-8 text-muted-foreground/30" />
            <p className="mt-3 text-[13px] font-semibold text-muted-foreground">
              {allTimestamps.length === 0
                ? "No moments marked yet."
                : "No moments in this category."}
            </p>
            {allTimestamps.length === 0 && allowed && (
              <p className="mt-1 text-[12px] text-muted-foreground/70">
                Play the film and mark a moment.
              </p>
            )}
          </div>
        ) : (
          <div className="space-y-2">
            {timestamps.map((ts) => {
              const cat = deriveCategory(ts.label);
              const meta = CATEGORIES[cat];
              return (
                <TimestampRow
                  key={ts.id}
                  ts={ts}
                  category={cat}
                  meta={meta}
                  canDelete={allowed && ts.user_id === currentUserId}
                  onDelete={() => deleteMutation.mutate(ts.id)}
                  onSeek={() => {
                    if (videoRef.current) {
                      videoRef.current.currentTime = ts.time_seconds;
                      void videoRef.current.play();
                    }
                  }}
                />
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}

/** One timestamp row — category-coloured, click to seek, delete if owned. */
function TimestampRow({
  ts,
  category,
  meta,
  canDelete,
  onDelete,
  onSeek,
}: {
  ts: FilmTimestamp;
  category: TimestampCategory;
  meta: CategoryMeta;
  canDelete: boolean;
  onDelete: () => void;
  onSeek: () => void;
}) {
  const label = stripCategoryPrefix(ts.label);
  const authorHref = ts.author_username
    ? `/u/${ts.author_username}`
    : `/u/${ts.user_id}`;
  const author = ts.author_username
    ? `@${ts.author_username}`
    : ts.author_name || "Member";
  return (
    <div className="flex items-start gap-3 rounded-xl border border-border bg-background p-3 transition-colors hover:border-foreground/20">
      {/* Category icon */}
      <span className={`mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-lg ${meta.bg}`}>
        <meta.icon className={`h-3.5 w-3.5 ${meta.color}`} />
      </span>

      {/* Timecode + label */}
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <button
            onClick={onSeek}
            className="flex shrink-0 items-center gap-1 rounded-md bg-foreground px-2 py-0.5 font-mono text-[11px] font-bold text-background transition-transform active:scale-95"
          >
            {formatTimecode(ts.time_seconds)}
          </button>
          <span className={`text-[10px] font-bold uppercase tracking-wider ${meta.color}`}>
            {meta.label}
          </span>
        </div>
        <p className="mt-1 text-[13px] leading-snug text-foreground">
          {label}
        </p>
        {ts.author_username && (
          <Link
            to={authorHref}
            className="mt-1 inline-block text-[11px] font-semibold text-muted-foreground/70 hover:text-foreground hover:underline"
          >
            by {author}
          </Link>
        )}
      </div>

      {/* Delete */}
      {canDelete && (
        <button
          onClick={onDelete}
          className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-red-500/10 hover:text-red-500"
          aria-label="Delete moment"
        >
          <Trash2 className="h-3.5 w-3.5" />
        </button>
      )}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Category encoding — stored in the label as a prefix so existing DB
   rows (plain labels) still work and no migration is needed.          */
/* ------------------------------------------------------------------ */

/** Encode a category + label into a single string for storage. */
function formatLabel(category: TimestampCategory, label: string): string {
  const trimmed = label.trim();
  if (category === "note") return trimmed; // default — no prefix for backwards compat
  return `[${category}] ${trimmed}`;
}

/** Derive the category from a stored label (falls back to "note"). */
function deriveCategory(label: string): TimestampCategory {
  const match = label.match(/^\[(note|highlight|review|question|clip)\]\s/);
  if (match) return match[1] as TimestampCategory;
  return "note";
}

/** Strip the category prefix from a stored label for display. */
function stripCategoryPrefix(label: string): string {
  return label.replace(/^\[(note|highlight|review|question|clip)\]\s/, "");
}

/** Placeholder text tuned per category. */
function placeholderForCategory(cat: TimestampCategory): string {
  switch (cat) {
    case "highlight":
      return "What makes this moment stand out?";
    case "review":
      return "Your review of this moment…";
    case "question":
      return "What would you ask the director about this moment?";
    case "clip":
      return "Describe the clip — what should the reader see?";
    default:
      return "What's interesting at this moment?";
  }
}
