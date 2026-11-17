import { useEffect, useMemo, useRef, useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import {
  ArrowRight,
  CalendarDays,
  Clapperboard,
  Download,
  FileText,
  Film as FilmIcon,
  Flame,
  Image as ImageIcon,
  ImagePlus,
  Link2,
  Loader2,
  Pencil,
  Play,
  Plus,
  ScanText,
  Scissors,
  Sparkles,
  Trash2,
  Upload,
  Video,
  Wand2,
  X,
} from "lucide-react";
import { toast } from "sonner";

import { Header } from "@/components/Header";
import { EmberMascot } from "@/components/EmberMascot";
import { JasperKitKeyframes } from "@/components/JasperIntelKit";
import { coachModeInfo, loadCoachMode } from "@/lib/emberBrain";
import { jasperMintShellStyle, jasperPillPalette } from "@/lib/jasperIntel";
import { useAuth } from "@/hooks/useAuth";
import { useMyBadge } from "@/hooks/useMyBadge";
import { fetchFilms, createFilm, type Film } from "@/lib/films";
import { emberAsk, emberImagine } from "@/lib/ember";
import { uploadMedia, uploadFilm } from "@/lib/api";
import {
  authorFetchArticles,
  authorUpsertArticle,
  authorDeleteArticle,
} from "@/lib/articles";

/**
 * Whisper Studio — the media team's full production workspace. Directors land
 * here to upload and publish Featured Film Friday premieres, work with the
 * real Ember assistant (tuned to a director's voice), have Ember read and
 * analyze their film, generate a movie poster, and manage the films they've
 * shipped. Gated on `is_director` or a mod+ badge.
 *
 * Everything Ember does here uses the real `emberAsk` / `emberImagine` backend
 * — the same assistant every other Whisper surface uses — with a
 * director-tuned system prompt layered on top.
 */
export default function DirectorStudio() {
  const { profile } = useAuth();
  const badge = useMyBadge();
  const allowed =
    !!profile?.is_director ||
    badge === "moderator" ||
    badge === "admin" ||
    badge === "owner";

  if (!allowed) {
    return (
      <div>
        <Header title="Whisper Studio" />
        <div className="mx-auto max-w-md px-4 py-20 text-center">
          <Clapperboard className="mx-auto h-10 w-10 text-muted-foreground/50" />
          <p className="mt-4 text-lg font-bold">Whisper media team only</p>
          <p className="mx-auto mt-1 max-w-xs text-sm text-muted-foreground">
            Whisper Studio is the media team's workspace for premieres, plans,
            and production.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div>
      <Header title="Whisper Studio" />
      <div className="mx-auto w-full max-w-xl px-4 pb-24 pt-3">
        <StudioHero />
        <PremiereStatusBoard />
        <EmberStudioAssistant />
        <DirectorArticleSection />
        <PublishFilmSection />
        <PublishedFilmsSection />
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Studio identity banner                                              */
/* ------------------------------------------------------------------ */

/**
 * The studio's identity banner — a premium, editorial header with a film-strip
 * motif. Sets the tone for the whole workspace: this is a production room,
 * not a settings page.
 */
function StudioHero() {
  const { profile, session } = useAuth();
  const token = session?.access_token ?? "";
  const mode = loadCoachMode();
  const info = coachModeInfo(mode);
  const name =
    profile?.display_name?.trim() || profile?.username?.trim() || "Director";

  // The live production desk — films live · next premiere · articles.
  const filmsQuery = useQuery({ queryKey: ["films"], queryFn: () => fetchFilms() });
  const articlesQuery = useQuery({
    queryKey: ["director-articles", session?.user.id],
    enabled: !!token,
    queryFn: () => authorFetchArticles(token),
    retry: false,
  });
  const published = (filmsQuery.data ?? []).filter((f) => f.published);
  const todayIso = new Date().toISOString().slice(0, 10);
  const upcoming = published
    .filter((f) => (f.featured_date ?? "") >= todayIso)
    .sort((a, b) => (a.featured_date ?? "").localeCompare(b.featured_date ?? ""))[0];
  const premiereLabel = upcoming?.featured_date
    ? new Date(upcoming.featured_date + "T00:00:00").toLocaleDateString("en-US", {
        month: "short",
        day: "numeric",
      })
    : "—";
  return (
    <div className="relative mt-9">
      <JasperKitKeyframes />
      {/* The ghost peeks over the TOP CENTER of the opaque card — the same
          pill language as the Jasper docks (head above the edge, body
          genuinely behind). */}
      <span
        className="pointer-events-none absolute -top-9 left-1/2 z-0 -translate-x-1/2"
        style={{ animation: "jasper-mascot-bob 1.7s ease-in-out infinite" }}
      >
        <EmberMascot
          size={58}
          coachMode={mode}
          isActive={false}
          expression="calm"
          cyclesExpressions
        />
      </span>
      <div
        className="relative z-10 overflow-hidden rounded-[24px] border bg-card px-5 py-6 text-center"
        style={{
          borderColor: `${info.accent}47`,
          boxShadow: `0 14px 34px ${info.accent}24`,
        }}
      >
        {/* Film-perforation strips along the top and bottom edges — accent
            tinted like iOS, inset from the card edge. */}
        <div className="pointer-events-none absolute inset-x-0 top-2 flex items-center justify-center gap-[7px] px-2">
          {Array.from({ length: 22 }).map((_, i) => (
            <span
              key={i}
              className="h-1 w-2.5 shrink-0 rounded-[2px]"
              style={{ background: `${info.accent}2e` }}
            />
          ))}
        </div>
        <div className="pointer-events-none absolute inset-x-0 bottom-2 flex items-center justify-center gap-[7px] px-2">
          {Array.from({ length: 22 }).map((_, i) => (
            <span
              key={i}
              className="h-1 w-2.5 shrink-0 rounded-[2px]"
              style={{ background: `${info.accent}2e` }}
            />
          ))}
        </div>
        <p
          className="text-[10px] font-black uppercase tracking-[0.24em]"
          style={{ color: info.deepAccent }}
        >
          Whisper Studios
        </p>
        <p className="mt-1 font-display text-[22px] font-black tracking-tight">
          The production floor
        </p>
        <p className="mx-auto mt-1.5 max-w-sm text-[13px] leading-relaxed text-muted-foreground">
          {name}'s workspace — films, Friday premieres, articles. Jasper works
          the set with you.
        </p>
        {/* The live production desk — accent-tinted stat tiles with icons,
            exactly like the iOS marquee. */}
        <div className="mx-auto mt-4 grid w-full max-w-sm grid-cols-3 gap-2">
          {(
            [
              [
                FilmIcon,
                String(published.length),
                published.length === 1 ? "Film live" : "Films live",
              ],
              [CalendarDays, premiereLabel, "Next premiere"],
              [
                FileText,
                String(articlesQuery.data?.length ?? 0),
                (articlesQuery.data?.length ?? 0) === 1 ? "Article" : "Articles",
              ],
            ] as const
          ).map(([Icon, value, label]) => (
            <div
              key={label}
              className="rounded-xl px-2 py-2.5"
              style={{
                background: `${info.accent}1a`,
                border: `1px solid ${info.accent}38`,
              }}
            >
              <p className="flex items-center justify-center gap-1 text-[15px] font-black leading-none">
                <Icon
                  className="h-3 w-3 shrink-0"
                  style={{ color: info.deepAccent }}
                  strokeWidth={3}
                />
                {value}
              </p>
              <p className="mt-1.5 text-[8.5px] font-black uppercase tracking-[0.14em] text-muted-foreground">
                {label}
              </p>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Premiere status board                                               */
/* ------------------------------------------------------------------ */

/**
 * A live status board showing this week's Featured Film Friday premiere —
 * the next scheduled film, or a quiet "no premiere this week" marquee.
 * Pulls the same films query the published-films list uses, so it stays in
 * sync with what's actually scheduled.
 */
function PremiereStatusBoard() {
  const filmsQuery = useQuery({
    queryKey: ["films"],
    queryFn: () => fetchFilms(),
  });
  const films = (filmsQuery.data ?? []).filter((f) => f.published);

  // Find the next upcoming or most-recent Friday premiere.
  const now = new Date();
  const thisFriday = nextFriday(now);
  const upcoming = films
    .filter((f) => f.featured_date)
    .sort((a, b) => (a.featured_date! < b.featured_date! ? 1 : -1))[0];

  const isThisWeek =
    upcoming &&
    upcoming.featured_date ===
      thisFriday.toISOString().slice(0, 10);

  return (
    <div className="mt-4 overflow-hidden rounded-[20px] border border-border bg-card">
      <div className="flex items-center justify-between rounded-b-[22px] border-b border-border/60 bg-background/95 px-5 py-3 backdrop-blur-sm">
        <div className="flex items-center gap-2">
          <span className="relative flex h-2 w-2">
            <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-orange-400 opacity-75" />
            <span className="relative inline-flex h-2 w-2 rounded-full bg-orange-500" />
          </span>
          <p className="text-[11px] font-bold uppercase tracking-[0.18em] text-muted-foreground">
            This Friday
          </p>
        </div>
        <span className="text-[11px] font-bold text-muted-foreground">
          {thisFriday.toLocaleDateString("en-US", {
            month: "short",
            day: "numeric",
          })}
        </span>
      </div>
      {upcoming ? (
        <a
          href={`/films/${upcoming.id}`}
          className="flex items-center gap-4 px-5 py-4 transition-colors hover:bg-secondary/40"
        >
          <div className="flex h-16 w-12 shrink-0 items-center justify-center overflow-hidden rounded-lg bg-black shadow-sm">
            {upcoming.poster_url ? (
              <img
                src={upcoming.poster_url}
                alt=""
                className="h-full w-full object-cover"
              />
            ) : (
              <FilmIcon className="h-5 w-5 text-white/40" />
            )}
          </div>
          <div className="min-w-0 flex-1">
            <p className="truncate text-[15px] font-extrabold leading-tight">
              {upcoming.title}
            </p>
            <p className="mt-0.5 truncate text-[12px] text-muted-foreground">
              {upcoming.synopsis || "No synopsis yet"}
            </p>
            <p className="mt-1 text-[11px] font-bold text-muted-foreground">
              {isThisWeek ? "Premieres Friday" : "Scheduled"}
            </p>
          </div>
        </a>
      ) : (
        <div className="px-5 py-5">
          <p className="text-[13px] font-bold text-foreground">
            No premiere this week
          </p>
          <p className="mt-0.5 text-[12px] leading-relaxed text-muted-foreground">
            Upload a film below and set its featured date to this Friday to
            schedule the premiere.
          </p>
        </div>
      )}
    </div>
  );
}

/** The next Friday on or after the given date (as a local midnight Date). */
function nextFriday(from: Date): Date {
  const d = new Date(from);
  d.setHours(0, 0, 0, 0);
  const day = d.getDay(); // 0 Sun … 5 Fri … 6 Sat
  const delta = day <= 5 ? 5 - day : 5 + (7 - day);
  d.setDate(d.getDate() + delta);
  return d;
}

/* ------------------------------------------------------------------ */
/* Publish a film                                                      */
/* ------------------------------------------------------------------ */

/**
 * Upload + publish a new film. The director uploads the video file (and an
 * optional poster) straight into Supabase storage, fills in the metadata, and
 * schedules the Friday premiere. The poster field is intentionally tied to the
 * Ember poster generator below — directors can generate a poster there and
 * paste the URL here, or upload their own.
 */
function PublishFilmSection() {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const [title, setTitle] = useState<string>("");
  const [synopsis, setSynopsis] = useState<string>("");
  const [videoUrl, setVideoUrl] = useState<string>("");
  const [trailerUrl, setTrailerUrl] = useState<string>("");
  const [posterUrl, setPosterUrl] = useState<string>("");
  const [duration, setDuration] = useState<string>("");
  const [featuredDate, setFeaturedDate] = useState<string>("");
  const [published, setPublished] = useState<boolean>(true);
  const [videoUploading, setVideoUploading] = useState<boolean>(false);
  const [videoProgress, setVideoProgress] = useState<number>(0);
  const [trailerUploading, setTrailerUploading] = useState<boolean>(false);
  const [posterUploading, setPosterUploading] = useState<boolean>(false);
  const videoInputRef = useRef<HTMLInputElement | null>(null);
  const trailerInputRef = useRef<HTMLInputElement | null>(null);
  const posterInputRef = useRef<HTMLInputElement | null>(null);

  const onVideoFile = async (
    e: React.ChangeEvent<HTMLInputElement>
  ): Promise<void> => {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file || !user) return;
    if (!file.type.startsWith("video/")) {
      toast.error("Choose a video file.");
      return;
    }
    // Allow big films — the Supabase resumable uploader chunks the file so
    // up to 10 GB can stream without hitting the single-request body limit.
    if (file.size > 10 * 1024 * 1024 * 1024) {
      toast.error("Film must be under 10 GB.");
      return;
    }
    setVideoUploading(true);
    setVideoProgress(0);
    try {
      const url = await uploadFilm(file, user.id, (frac) =>
        setVideoProgress(Math.round(frac * 100))
      );
      setVideoUrl(url);
      toast.success("Film uploaded — don't forget to publish.");
    } catch {
      toast.error("Couldn't upload the film. Try again.");
    } finally {
      setVideoUploading(false);
      setVideoProgress(0);
    }
  };

  const onTrailerFile = async (
    e: React.ChangeEvent<HTMLInputElement>
  ): Promise<void> => {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file || !user) return;
    // Accept any video format the browser can probe — MP4, MOV, WebM, MKV,
    // AVI, etc. The <video> tag handles playback; the upload just stores bytes.
    const isVideo = file.type.startsWith("video/") || /^\.(mp4|mov|webm|mkv|avi|m4v|flv|wmv|3gp|ogv)$/i.test(file.name.slice(file.name.lastIndexOf(".")));
    if (!isVideo) {
      toast.error("Choose a video file (MP4, MOV, WebM, MKV, AVI…).");
      return;
    }
    if (file.size > 2 * 1024 * 1024 * 1024) {
      toast.error("Trailer must be under 2 GB.");
      return;
    }
    setTrailerUploading(true);
    try {
      const url = await uploadFilm(file, user.id);
      setTrailerUrl(url);
      toast.success("Trailer uploaded.");
    } catch {
      toast.error("Couldn't upload the trailer. Try again.");
    } finally {
      setTrailerUploading(false);
    }
  };

  const onPosterFile = async (
    e: React.ChangeEvent<HTMLInputElement>
  ): Promise<void> => {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file || !user) return;
    if (!file.type.startsWith("image/")) {
      toast.error("Choose an image file.");
      return;
    }
    setPosterUploading(true);
    try {
      const url = await uploadMedia(file, user.id);
      setPosterUrl(url);
      toast.success("Poster uploaded.");
    } catch {
      toast.error("Couldn't upload the poster. Try again.");
    } finally {
      setPosterUploading(false);
    }
  };

  const mutation = useMutation({
    mutationFn: () =>
      createFilm({
        title: title.trim(),
        synopsis: synopsis.trim(),
        videoUrl: videoUrl.trim(),
        trailerUrl: trailerUrl.trim(),
        posterUrl: posterUrl.trim(),
        durationSeconds: duration ? Math.round(Number(duration)) : null,
        featuredDate: featuredDate || null,
        published,
      }),
    onSuccess: () => {
      toast.success("Film published.");
      setTitle("");
      setSynopsis("");
      setVideoUrl("");
      setTrailerUrl("");
      setPosterUrl("");
      setDuration("");
      setFeaturedDate("");
      void queryClient.invalidateQueries({ queryKey: ["films"] });
    },
    onError: (err) =>
      toast.error(err instanceof Error ? err.message : "Couldn't publish that film."),
  });

  const inputClass =
    "w-full rounded-xl border border-border bg-background px-3.5 py-2.5 text-[14px] outline-none placeholder:text-muted-foreground/60 transition-colors focus:border-foreground/40";

  return (
    <div className="mt-5 rounded-[20px] border border-border bg-card p-5">
      <div className="flex items-center gap-2">
        <Upload className="h-4 w-4 text-muted-foreground" />
        <h2 className="text-[14px] font-extrabold">Upload a film</h2>
      </div>

      <div className="mt-4 space-y-3">
        <input
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="Film title"
          className={inputClass}
        />
        <textarea
          value={synopsis}
          onChange={(e) => setSynopsis(e.target.value)}
          placeholder="Synopsis — what's this film about?"
          rows={3}
          className={`${inputClass} resize-none`}
        />

        {/* Video upload */}
        <div>
          <p className="text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
            Film file <span className="font-normal normal-case text-muted-foreground/70">(up to 10 GB — MP4, MOV, WebM, MKV, AVI — uploads in chunks)</span>
          </p>
          <div className="mt-1.5 flex items-center gap-3">
            <div className="flex h-14 w-24 shrink-0 items-center justify-center overflow-hidden rounded-xl bg-secondary">
              {videoUrl ? (
                <video src={videoUrl} className="h-full w-full object-cover" muted />
              ) : (
                <Video className="h-5 w-5 text-muted-foreground/50" />
              )}
            </div>
            <div className="flex flex-1 flex-col gap-1.5">
              <button
                type="button"
                onClick={() => videoInputRef.current?.click()}
                disabled={videoUploading || !user}
                className="inline-flex w-fit items-center gap-1.5 rounded-full bg-foreground/5 px-4 py-2 text-[12.5px] font-bold transition-transform active:scale-[0.97] disabled:opacity-50"
              >
                {videoUploading ? (
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                ) : (
                  <Video className="h-3.5 w-3.5" />
                )}
                {videoUrl ? "Replace film" : "Upload film"}
              </button>
              {videoUploading && (
                <div className="w-full max-w-[180px]">
                  <div className="h-1.5 overflow-hidden rounded-full bg-secondary">
                    <div
                      className="h-full rounded-full bg-foreground transition-all duration-300"
                      style={{ width: `${videoProgress}%` }}
                    />
                  </div>
                  <p className="mt-1 text-[10px] font-bold text-muted-foreground">
                    {videoProgress}%
                  </p>
                </div>
              )}
              {videoUrl && !videoUploading && (
                <button
                  type="button"
                  onClick={() => setVideoUrl("")}
                  className="w-fit text-left text-[12px] font-bold text-red-500"
                >
                  Remove
                </button>
              )}
            </div>
            <input
              ref={videoInputRef}
              type="file"
              accept="video/*,.mkv,.avi,.flv,.wmv,.3gp,.ogv,.m4v"
              onChange={(e) => void onVideoFile(e)}
              className="hidden"
            />
          </div>
        </div>

        {/* Trailer upload */}
        <div>
          <p className="text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
            Trailer <span className="font-normal normal-case text-muted-foreground/70">(optional — shown on any article written about this film)</span>
          </p>
          <div className="mt-1.5 flex items-center gap-3">
            <div className="flex h-14 w-24 shrink-0 items-center justify-center overflow-hidden rounded-xl bg-secondary">
              {trailerUrl ? (
                <video src={trailerUrl} className="h-full w-full object-cover" muted />
              ) : (
                <Video className="h-5 w-5 text-muted-foreground/50" />
              )}
            </div>
            <div className="flex flex-1 flex-col gap-1.5">
              <button
                type="button"
                onClick={() => trailerInputRef.current?.click()}
                disabled={trailerUploading || !user}
                className="inline-flex w-fit items-center gap-1.5 rounded-full bg-foreground/5 px-4 py-2 text-[12.5px] font-bold transition-transform active:scale-[0.97] disabled:opacity-50"
              >
                {trailerUploading ? (
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                ) : (
                  <Video className="h-3.5 w-3.5" />
                )}
                {trailerUrl ? "Replace trailer" : "Upload trailer"}
              </button>
              {trailerUrl && !trailerUploading && (
                <button
                  type="button"
                  onClick={() => setTrailerUrl("")}
                  className="w-fit text-left text-[12px] font-bold text-red-500"
                >
                  Remove
                </button>
              )}
            </div>
            <input
              ref={trailerInputRef}
              type="file"
              accept="video/*,.mkv,.avi,.flv,.wmv,.3gp,.ogv,.m4v"
              onChange={(e) => void onTrailerFile(e)}
              className="hidden"
            />
          </div>
        </div>

        {/* Poster upload */}
        <div>
          <p className="text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
            Poster <span className="font-normal normal-case text-muted-foreground/70">(optional — Jasper can generate one below)</span>
          </p>
          <div className="mt-1.5 flex items-center gap-3">
            <div className="flex h-14 w-24 shrink-0 items-center justify-center overflow-hidden rounded-xl bg-secondary">
              {posterUrl ? (
                <img src={posterUrl} alt="" className="h-full w-full object-cover" />
              ) : (
                <ImagePlus className="h-5 w-5 text-muted-foreground/50" />
              )}
            </div>
            <div className="flex flex-col gap-1.5">
              <button
                type="button"
                onClick={() => posterInputRef.current?.click()}
                disabled={posterUploading || !user}
                className="inline-flex items-center gap-1.5 rounded-full bg-foreground/5 px-4 py-2 text-[12.5px] font-bold transition-transform active:scale-[0.97] disabled:opacity-50"
              >
                {posterUploading ? (
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                ) : (
                  <ImagePlus className="h-3.5 w-3.5" />
                )}
                {posterUrl ? "Replace poster" : "Upload poster"}
              </button>
              {posterUrl && (
                <button
                  type="button"
                  onClick={() => setPosterUrl("")}
                  className="text-left text-[12px] font-bold text-red-500"
                >
                  Remove
                </button>
              )}
            </div>
            <input
              ref={posterInputRef}
              type="file"
              accept="image/*"
              onChange={(e) => void onPosterFile(e)}
              className="hidden"
            />
          </div>
        </div>

        <div className="grid grid-cols-2 gap-2.5">
          <input
            value={duration}
            onChange={(e) => setDuration(e.target.value)}
            inputMode="numeric"
            placeholder="Duration (sec)"
            className={inputClass}
          />
          <input
            type="date"
            value={featuredDate}
            onChange={(e) => setFeaturedDate(e.target.value)}
            className={inputClass}
          />
        </div>
        <label className="flex items-center justify-end gap-2 text-[13px] font-semibold">
          Publish immediately
          <button
            role="switch"
            aria-checked={published}
            onClick={() => setPublished((v) => !v)}
            className={`relative h-6 w-11 rounded-full transition-colors ${
              published ? "bg-foreground" : "bg-secondary"
            }`}
          >
            <span
              className={`absolute top-0.5 h-5 w-5 rounded-full bg-white shadow transition-all ${
                published ? "left-[22px]" : "left-0.5"
              }`}
            />
          </button>
        </label>
        <button
          onClick={() => mutation.mutate()}
          disabled={mutation.isPending || !title.trim() || !videoUrl.trim()}
          className="flex w-full items-center justify-center gap-2 rounded-full bg-foreground py-3 text-[14px] font-bold text-background transition-transform active:scale-[0.98] disabled:opacity-40"
        >
          {mutation.isPending ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : (
            <FilmIcon className="h-4 w-4" />
          )}
          Publish film
        </button>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* The real Ember assistant — tuned for directors                      */
/* ------------------------------------------------------------------ */

/**
 * The director-tuned Ember system prompt. This is layered on top of Ember's
 * default personality (the warm, witty Whisper companion) — it sharpens the
 * voice for a working director and gives Ember the context to act like a
 * festival programmer + production partner.
 */
const DIRECTOR_SYSTEM = `You are Jasper, the in-house creative assistant for the Whisper media team — a small studio that produces short documentary films with fitness creators (lifters, runners, athletes). You are still Jasper (warm, witty, observant) but your craft is cinematic and specific. You think like a festival programmer and a working director: you care about hook, structure, and what a small crew can actually shoot. Keep replies tight and vivid — no padding, no generic advice. When you ask a question, ask one at a time, and make it specific enough that the director can answer in a sentence. You can read a film's synopsis and give structural notes, suggest a poster concept, or help plan a release — whatever the director needs.`;

type EmberTool =
  | "writersBlock"
  | "shotList"
  | "synopsisPolish"
  | "titleIdeas"
  | "releasePlan"
  | "directorsStatement"
  | "readTheFilm"
  | "posterConcept";

interface Tool {
  id: EmberTool;
  label: string;
  icon: typeof Sparkles;
  tagline: string;
  /** First message Ember sends to the director to kick off the tool. */
  opener: (ctx: string) => string;
  /** The system-level tuning that shapes Ember's director voice. */
  system: string;
  /** Whether this tool is a "quick" single-shot (poster concept) vs a thread. */
  quick?: boolean;
  /** Flagship tools get a prominent hero card; the rest stay in the grid. */
  flagship?: boolean;
  /** A short one-line description for the hero card. */
  description?: string;
  /** Accent tint for the tool card — gives each tool its own visual identity. */
  accent: string;
  /** A short hint shown inside the card describing what Ember will do. */
  hint: string;
}

const TOOLS: Tool[] = [
  {
    id: "writersBlock",
    label: "Writer's block",
    icon: Wand2,
    tagline: "Find the opening hook",
    opener: (t) =>
      `A director is stuck on a short film about: "${t}". Before you pitch ideas, ask one specific question that will help you target the hook — about the subject, the stakes, or the moment that matters most.`,
    system: DIRECTOR_SYSTEM,
    accent: "from-violet-500/12 to-violet-500/[0.03]",
    hint: "Tell Jasper the subject — it asks one sharp question, then pitches hooks.",
  },
  {
    id: "shotList",
    label: "Shot list",
    icon: FilmIcon,
    tagline: "Plan the coverage",
    opener: (t) =>
      `A director is planning coverage for: "${t}". Ask one question about the location or the subject's movement so you can write a shot list a small crew can actually execute.`,
    system: DIRECTOR_SYSTEM,
    accent: "from-sky-500/12 to-sky-500/[0.03]",
    hint: "Share the scene — Jasper writes a shot list a small crew can shoot.",
  },
  {
    id: "synopsisPolish",
    label: "Synopsis polish",
    icon: Pencil,
    tagline: "Tighten the logline",
    opener: (d) =>
      `Here's a working synopsis: "${d}". Ask one question about the audience or the emotional core before you rewrite it into a tight, festival-catalogue logline.`,
    system: DIRECTOR_SYSTEM,
    accent: "from-emerald-500/12 to-emerald-500/[0.03]",
    hint: "Paste the draft — Jasper rewrites it into a festival-grade logline.",
  },
  {
    id: "titleIdeas",
    label: "Title ideas",
    icon: Sparkles,
    tagline: "Name the film",
    opener: (t) =>
      `A director needs a title for a short film about: "${t}". Ask one question about the tone (raw, lyrical, punchy?) before you brainstorm.`,
    system: DIRECTOR_SYSTEM,
    accent: "from-amber-500/12 to-amber-500/[0.03]",
    hint: "Describe the film — Jasper asks about tone, then brainstorms titles.",
  },
  {
    id: "releasePlan",
    label: "Release plan",
    icon: Upload,
    tagline: "Plan the premiere",
    opener: (t) =>
      `A director is scheduling a Featured Film Friday premiere for: "${t}". Ask one question about the subject's availability or the community hook, then you'll shape a release plan around it.`,
    system: DIRECTOR_SYSTEM,
    accent: "from-rose-500/12 to-rose-500/[0.03]",
    hint: "Name the film — Jasper builds a release plan around the Friday premiere.",
  },
  {
    id: "directorsStatement",
    label: "Director's note",
    icon: Flame,
    tagline: "Write the statement",
    opener: (t) =>
      `A director is writing a director's statement for a film about: "${t}". Ask one question about why they made this film before you draft the statement.`,
    system: DIRECTOR_SYSTEM,
    accent: "from-orange-500/12 to-orange-500/[0.03]",
    hint: "Tell Jasper the subject — it asks why you made it, then drafts the statement.",
  },
  {
    id: "readTheFilm",
    label: "Read the film",
    icon: ScanText,
    tagline: "Jasper reads your synopsis",
    flagship: true,
    description: "Paste the full synopsis — Jasper gives you a tight structural read: hook, arc, emotional core, the moment working hardest.",
    opener: (synopsis) =>
      `A director wants you to read their film. Here's the synopsis:\n\n"""${synopsis}"""\n\nGive them a tight structural read: the hook, the arc, the emotional core, and one moment that's working hardest. Then ask one question about what they want to strengthen — pacing, stakes, or the ending.`,
    system: `${DIRECTOR_SYSTEM}\n\nWhen reading a film, be specific and honest — name what's working and what's soft. Don't flatter. A director trusts you when you're precise.`,
    accent: "from-blue-500/12 to-blue-500/[0.03]",
    hint: "Paste the full synopsis — Jasper gives you a structural read.",
  },
  {
    id: "posterConcept",
    label: "Movie poster",
    icon: ImagePlus,
    tagline: "Generate a poster",
    flagship: true,
    quick: true,
    description: "Tell Jasper the mood and the one image that anchors the frame. Jasper writes the prompt and generates a real, downloadable poster.",
    opener: (t) =>
      `A director wants a movie poster for: "${t}". Ask one question about the mood (stark, warm, heroic, intimate?) and the one image that should anchor the frame, then you'll generate it.`,
    system: `${DIRECTOR_SYSTEM}\n\nYou can also generate poster imagery. When the director gives you the mood and the anchor image, describe the poster as a single vivid image-generation prompt (composition, subject, palette, lighting, negative space for the title). Keep it to one sentence.`,
    accent: "from-fuchsia-500/12 to-fuchsia-500/[0.03]",
    hint: "Tell Jasper the mood + anchor image — it generates a real, downloadable poster.",
  },
];

/* ------------------------------------------------------------------ */
/* Director's article — write the film's companion piece               */
/* ------------------------------------------------------------------ */

/**
 * A lightweight article composer right in the studio, so a director can
 * write the companion piece (director's note, review, behind-the-scenes)
 * without leaving to the separate Write Articles page. Uses the same
 * `authorUpsertArticle` backend — the byline is locked server-side.
 */
function DirectorArticleSection() {
  const { session, user, profile } = useAuth();
  const queryClient = useQueryClient();
  const [open, setOpen] = useState<boolean>(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [title, setTitle] = useState<string>("");
  const [excerpt, setExcerpt] = useState<string>("");
  const [body, setBody] = useState<string>("");
  const [category, setCategory] = useState<string>("Film Review");
  const [published, setPublished] = useState<boolean>(true);
  const [taggedFilmId, setTaggedFilmId] = useState<string>("");
  const [clipSeconds, setClipSeconds] = useState<string>("");
  const [coverUrl, setCoverUrl] = useState<string>("");
  const [coverUploading, setCoverUploading] = useState<boolean>(false);
  const coverInputRef = useRef<HTMLInputElement | null>(null);
  const token = session?.access_token ?? "";

  // Fetch the director's published films so they can tag an article to one.
  const filmsQuery = useQuery({
    queryKey: ["films"],
    queryFn: () => fetchFilms(),
  });
  const films = (filmsQuery.data ?? []).slice(0, 20);

  const list = useQuery({
    queryKey: ["director-articles", session?.user.id],
    enabled: !!token,
    queryFn: () => authorFetchArticles(token),
    retry: false,
  });
  const articles = (list.data ?? []).slice(0, 5);

  const resetForm = (): void => {
    setTitle("");
    setExcerpt("");
    setBody("");
    setCategory("Film Review");
    setPublished(true);
    setTaggedFilmId("");
    setClipSeconds("");
    setCoverUrl("");
    setEditingId(null);
  };

  const taggedFilm = useMemo(
    () => films.find((f) => f.id === taggedFilmId) || null,
    [films, taggedFilmId]
  );

  const save = useMutation({
    mutationFn: async () =>
      authorUpsertArticle(token, {
        id: editingId ?? undefined,
        title: title.trim(),
        excerpt: excerpt.trim(),
        cover_url: coverUrl.trim(),
        category,
        author_name: "",
        paragraphs: body
          .split(/\n\s*\n/)
          .map((p) => p.trim())
          .filter(Boolean),
        published,
        film_id: taggedFilmId || undefined,
        clip_time_seconds: clipSeconds && !isNaN(Number(clipSeconds)) ? Number(clipSeconds) : undefined,
      }),
    onSuccess: () => {
      toast.success(editingId ? "Article updated." : "Article published.");
      setOpen(false);
      resetForm();
      void queryClient.invalidateQueries({
        queryKey: ["director-articles", session?.user.id],
      });
    },
    onError: (err) =>
      toast.error(
        err instanceof Error ? err.message : "Couldn't save that article."
      ),
  });

  const removeArticle = useMutation({
    mutationFn: (id: string) => authorDeleteArticle(token, id),
    onSuccess: () => {
      toast.success("Article deleted.");
      void queryClient.invalidateQueries({
        queryKey: ["director-articles", session?.user.id],
      });
    },
    onError: (err) =>
      toast.error(err instanceof Error ? err.message : "Couldn't delete that article."),
  });

  const startEdit = (a: { id: string; title: string; excerpt: string; paragraphs: string[]; category: string; published: boolean; film_id?: string | null; cover_url?: string | null; clip_time_seconds?: number | null }): void => {
    setEditingId(a.id);
    setTitle(a.title);
    setExcerpt(a.excerpt);
    setBody(a.paragraphs.join("\n\n"));
    setCategory(a.category || "Film Review");
    setPublished(a.published);
    setTaggedFilmId(a.film_id ?? "");
    setCoverUrl(a.cover_url ?? "");
    setClipSeconds(a.clip_time_seconds != null ? String(a.clip_time_seconds) : "");
    setOpen(true);
  };

  const inputClass =
    "w-full rounded-xl border border-border bg-background px-3.5 py-2.5 text-[14px] outline-none placeholder:text-muted-foreground/60 focus:border-foreground/40";

  const onCoverFile = async (e: React.ChangeEvent<HTMLInputElement>): Promise<void> => {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file || !user) return;
    if (!file.type.startsWith("image/")) {
      toast.error("Choose an image file for the cover.");
      return;
    }
    setCoverUploading(true);
    try {
      const url = await uploadMedia(file, user.id);
      setCoverUrl(url);
      toast.success("Cover photo uploaded.");
    } catch {
      toast.error("Couldn't upload the cover photo. Try again.");
    } finally {
      setCoverUploading(false);
    }
  };

  return (
    <div className="mt-5 rounded-[20px] border border-border bg-card p-5">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Pencil className="h-4 w-4 text-muted-foreground" />
          <h2 className="text-[14px] font-extrabold">Director's article</h2>
        </div>
        <button
          onClick={() => {
            if (open) resetForm();
            setOpen((v) => !v);
          }}
          className="inline-flex items-center gap-1.5 rounded-full bg-foreground/5 px-3.5 py-1.5 text-[12px] font-bold transition-transform active:scale-95"
        >
          {open ? <X className="h-3.5 w-3.5" /> : <Plus className="h-3.5 w-3.5" />}
          {open ? "Close" : "New"}
        </button>
      </div>
      <p className="mt-1 text-[12.5px] leading-relaxed text-muted-foreground">
        Write the companion piece for your film — a director's note, a review,
        or a behind-the-scenes story. Tag it to a film so the trailer plays
        at the top. Published with your byline.
      </p>

      {/* Recent articles — with edit + delete */}
      {articles.length > 0 && !open && (
        <div className="mt-3 space-y-2">
          {articles.map((a) => (
            <div
              key={a.id}
              className="flex items-center gap-3 rounded-xl border border-border bg-background p-2.5 transition-colors hover:bg-secondary/40"
            >
              <a
                href={`/articles/${a.slug}`}
                className="flex min-w-0 flex-1 items-center gap-3"
              >
                <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-foreground/5">
                  {a.film_id ? <FilmIcon className="h-3 w-3 text-muted-foreground" /> : <Pencil className="h-3 w-3 text-muted-foreground" />}
                </span>
                <div className="min-w-0 flex-1">
                  <p className="truncate text-[13px] font-bold">{a.title}</p>
                  <p className="text-[11px] text-muted-foreground">
                    {a.category} · {a.published ? "Published" : "Draft"}{a.film_id ? " · Tagged film" : ""}
                  </p>
                </div>
                <ArrowRight className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
              </a>
              <button
                onClick={() => startEdit(a)}
                className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-foreground/5 hover:text-foreground"
                aria-label="Edit article"
              >
                <Pencil className="h-3 w-3" />
              </button>
              <button
                onClick={() => {
                  if (confirm("Delete this article? This can't be undone.")) {
                    removeArticle.mutate(a.id);
                  }
                }}
                className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-red-500/10 hover:text-red-500"
                aria-label="Delete article"
              >
                <Trash2 className="h-3 w-3" />
              </button>
            </div>
          ))}
        </div>
      )}

      {/* Inline composer */}
      {open && (
        <div className="mt-4 space-y-2.5">
          <div className="flex items-center gap-2 text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
            {editingId ? (
              <><Pencil className="h-3 w-3" /> Editing article</>
            ) : (
              <><Plus className="h-3 w-3" /> New article</>
            )}
          </div>
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="Article title"
            className={inputClass}
          />
          <input
            value={excerpt}
            onChange={(e) => setExcerpt(e.target.value)}
            placeholder="One-line excerpt…"
            className={inputClass}
          />
          <div className="flex flex-wrap gap-1.5">
            {["Film Review", "Director's Note", "Behind the Scenes", "News"].map(
              (cat) => (
                <button
                  key={cat}
                  type="button"
                  onClick={() => setCategory(cat)}
                  className={`rounded-full px-3 py-1 text-[11px] font-bold transition-colors ${
                    category === cat
                      ? "bg-foreground text-background"
                      : "bg-secondary text-muted-foreground"
                  }`}
                >
                  {cat}
                </button>
              )
            )}
          </div>

          {/* Film tag selector — link this article to one of the director's films */}
          {films.length > 0 && (
            <div>
              <p className="mb-1.5 flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
                <Link2 className="h-3 w-3" /> Tag to a film
                <span className="font-normal normal-case text-muted-foreground/70">(shows the trailer at the top)</span>
              </p>
              <div className="flex flex-wrap gap-1.5">
                <button
                  type="button"
                  onClick={() => { setTaggedFilmId(""); setClipSeconds(""); }}
                  className={`rounded-full px-3 py-1.5 text-[11px] font-bold transition-colors ${
                    !taggedFilmId
                      ? "bg-foreground text-background"
                      : "bg-secondary text-muted-foreground"
                  }`}
                >
                  None
                </button>
                {films.map((f) => (
                  <button
                    key={f.id}
                    type="button"
                    onClick={() => setTaggedFilmId(f.id)}
                    className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-[11px] font-bold transition-colors ${
                      taggedFilmId === f.id
                        ? "bg-foreground text-background"
                        : "bg-secondary text-muted-foreground"
                    }`}
                  >
                    <FilmIcon className="h-3 w-3" />
                    <span className="max-w-[120px] truncate">{f.title}</span>
                  </button>
                ))}
              </div>
              {/* Clip timestamp — when set, the article starts at that exact
                  moment of the film. The clip also becomes the focus of the article. */}
              {taggedFilmId && (
                <div className="mt-2.5 flex items-center gap-2 rounded-xl border border-border bg-background px-3 py-2">
                  <Scissors className="h-3.5 w-3.5 shrink-0 text-orange-500" />
                  <input
                    value={clipSeconds}
                    onChange={(e) => setClipSeconds(e.target.value)}
                    inputMode="numeric"
                    placeholder="Clip at (seconds) — optional"
                    className="min-w-0 flex-1 bg-transparent text-[12.5px] font-semibold outline-none placeholder:text-muted-foreground/60"
                  />
                  {clipSeconds && !isNaN(Number(clipSeconds)) && Number(clipSeconds) >= 0 && (
                    <span className="shrink-0 rounded-md bg-orange-500/10 px-1.5 py-0.5 font-mono text-[10px] font-bold text-orange-600">
                      {Math.floor(Number(clipSeconds) / 60)}:{String(Math.floor(Number(clipSeconds) % 60)).padStart(2, "0")}
                    </span>
                  )}
                </div>
              )}
            </div>
          )}

          {/* Cover media — directors can upload a custom cover, use the film
              poster, or (when tagged) default to the film poster so the article
              never ships without a hero image. */}
          <div>
            <p className="mb-1.5 flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
              <ImageIcon className="h-3 w-3" /> Cover media
              <span className="font-normal normal-case text-muted-foreground/70">(card image + video poster)</span>
            </p>
            <div className="flex items-center gap-3">
              <div className="flex h-14 w-24 shrink-0 items-center justify-center overflow-hidden rounded-xl bg-secondary">
                {coverUrl ? (
                  <img src={coverUrl} alt="" className="h-full w-full object-cover" />
                ) : taggedFilm?.poster_url ? (
                  <img src={taggedFilm.poster_url} alt="" className="h-full w-full object-cover" />
                ) : (
                  <ImagePlus className="h-5 w-5 text-muted-foreground/50" />
                )}
              </div>
              <div className="flex flex-1 flex-wrap items-center gap-2">
                <button
                  type="button"
                  onClick={() => coverInputRef.current?.click()}
                  disabled={coverUploading || !user}
                  className="inline-flex items-center gap-1.5 rounded-full bg-foreground/5 px-4 py-2 text-[12.5px] font-bold transition-transform active:scale-[0.97] disabled:opacity-50"
                >
                  {coverUploading ? (
                    <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  ) : (
                    <ImagePlus className="h-3.5 w-3.5" />
                  )}
                  {coverUrl ? "Replace cover" : "Upload cover"}
                </button>
                {taggedFilm?.poster_url && (
                  <button
                    type="button"
                    onClick={() => setCoverUrl(taggedFilm.poster_url ?? "")}
                    className="inline-flex items-center gap-1.5 rounded-full bg-foreground/5 px-4 py-2 text-[12.5px] font-bold transition-transform active:scale-[0.97]"
                  >
                    <FilmIcon className="h-3.5 w-3.5" />
                    Use film poster
                  </button>
                )}
                {taggedFilm?.trailer_url && (
                  <button
                    type="button"
                    onClick={() => setCoverUrl(taggedFilm.poster_url ?? taggedFilm.trailer_url ?? "")}
                    className="inline-flex items-center gap-1.5 rounded-full bg-foreground/5 px-4 py-2 text-[12.5px] font-bold transition-transform active:scale-[0.97]"
                  >
                    <Play className="h-3.5 w-3.5 fill-current" />
                    Use trailer
                  </button>
                )}
                {coverUrl && (
                  <button
                    type="button"
                    onClick={() => setCoverUrl("")}
                    className="text-[12px] font-bold text-red-500"
                  >
                    Remove
                  </button>
                )}
              </div>
              <input
                ref={coverInputRef}
                type="file"
                accept="image/*"
                onChange={(e) => void onCoverFile(e)}
                className="hidden"
              />
            </div>
          </div>

          <textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder="Write the article… (blank line between paragraphs)"
            rows={6}
            className={`${inputClass} resize-none leading-relaxed`}
          />
          <div className="flex items-center justify-between">
            <label className="flex items-center gap-2 text-[12.5px] font-semibold text-muted-foreground">
              Publish
              <button
                role="switch"
                aria-checked={published}
                onClick={() => setPublished((v) => !v)}
                className={`relative h-5 w-9 rounded-full transition-colors ${
                  published ? "bg-foreground" : "bg-secondary"
                }`}
              >
                <span
                  className={`absolute top-0.5 h-4 w-4 rounded-full bg-white shadow transition-all ${
                    published ? "left-[18px]" : "left-0.5"
                  }`}
                />
              </button>
            </label>
            <div className="flex items-center gap-2">
              <button
                onClick={() => {
                  setOpen(false);
                  resetForm();
                }}
                className="rounded-full bg-secondary px-4 py-2 text-[12.5px] font-bold transition-transform active:scale-95"
              >
                Cancel
              </button>
              <button
                onClick={() => save.mutate()}
                disabled={save.isPending || !title.trim() || !body.trim()}
                className="inline-flex items-center gap-1.5 rounded-full bg-foreground px-4 py-2 text-[12.5px] font-bold text-background transition-transform active:scale-95 disabled:opacity-40"
              >
                {save.isPending ? (
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                ) : (
                  <Pencil className="h-3.5 w-3.5" />
                )}
                {editingId ? "Save" : "Publish"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

/**
 * The Ember studio assistant. Ember's living ghost sits at the top, then
 * the two flagship tools (Read the film, Movie poster) are presented as
 * quiet conversations you can start — not generic "feature cards." The
 * rest fold into a soft ink-toned list so the surface feels like Ember's
 * space, not a tool grid. Each opens a real back-and-forth modal powered
 * by the same `emberAsk` backend every other Ember surface uses.
 */
function EmberStudioAssistant() {
  const [openTool, setOpenTool] = useState<Tool | null>(null);
  const flagships = TOOLS.filter((t) => t.flagship);
  const rest = TOOLS.filter((t) => !t.flagship);

  return (
    <div className="mt-5 overflow-hidden rounded-[24px] border border-border bg-card">
      {/* Ember's space — the living ghost + a quiet intro in Ember's voice */}
      <div className="relative flex items-center gap-4 rounded-b-[22px] border-b border-border/60 bg-gradient-to-b from-foreground/[0.03] to-transparent px-5 py-5">
        <div className="relative h-14 w-14 shrink-0">
          <EmberMascot size={56} expression="calm" isActive />
        </div>
        <div className="min-w-0 flex-1">
          <p className="text-[11px] font-black uppercase tracking-[0.22em] text-muted-foreground">
            Jasper
          </p>
          <p className="mt-0.5 text-[14px] font-bold leading-tight text-foreground">
            Your studio partner
          </p>
          <p className="mt-1 text-[12px] leading-relaxed text-muted-foreground">
            I'll read your film, sketch a poster, break a block, or plan the
            cut. Pick a place to start.
          </p>
        </div>
      </div>

      {/* Flagship tools — presented as conversations, not feature cards */}
      <div className="space-y-px bg-border/60">
        {flagships.map((t) => (
          <button
            key={t.id}
            onClick={() => setOpenTool(t)}
            className="group flex w-full items-center gap-4 bg-card px-5 py-4 text-left transition-colors hover:bg-secondary/40 active:scale-[0.995]"
          >
            <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-foreground/[0.06] text-foreground/70 transition-colors group-hover:bg-foreground/10 group-hover:text-foreground">
              <t.icon className="h-4 w-4" />
            </span>
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <p className="text-[14px] font-extrabold leading-tight">
                  {t.label}
                </p>
                {t.quick && (
                  <span className="rounded-full bg-orange-500/10 px-2 py-0.5 text-[9px] font-bold uppercase tracking-wider text-orange-600">
                    Generates
                  </span>
                )}
              </div>
              <p className="mt-1 text-[12px] leading-snug text-muted-foreground">
                {t.description ?? t.tagline}
              </p>
            </div>
            <span className="text-muted-foreground/40 transition-transform group-hover:translate-x-0.5 group-hover:text-foreground/60">
              <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                <path d="M6 4l4 4-4 4" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </span>
          </button>
        ))}
      </div>

      {/* The rest — tailored tool cards, each with its own accent + hint */}
      <div className="px-5 pt-4 pb-2">
        <p className="text-[10px] font-bold uppercase tracking-[0.2em] text-muted-foreground/60">
          Also ask Jasper
        </p>
      </div>
      <div className="grid grid-cols-1 gap-2 px-5 pb-5 sm:grid-cols-2">
        {rest.map((t) => (
          <button
            key={t.id}
            onClick={() => setOpenTool(t)}
            className={`group relative flex items-start gap-3 overflow-hidden rounded-2xl border border-border bg-gradient-to-br ${t.accent} p-3.5 text-left transition-all hover:border-foreground/20 hover:shadow-sm active:scale-[0.98]`}
          >
            <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-xl bg-background/80 text-foreground/80 shadow-sm transition-colors group-hover:text-foreground">
              <t.icon className="h-4 w-4" />
            </span>
            <div className="min-w-0 flex-1">
              <p className="text-[13px] font-extrabold leading-tight text-foreground">
                {t.label}
              </p>
              <p className="mt-0.5 text-[11px] leading-snug text-muted-foreground">
                {t.hint}
              </p>
            </div>
            <span className="mt-0.5 shrink-0 text-muted-foreground/40 transition-transform group-hover:translate-x-0.5 group-hover:text-foreground/60">
              <svg width="14" height="14" viewBox="0 0 16 16" fill="none">
                <path d="M6 4l4 4-4 4" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </span>
          </button>
        ))}
      </div>

      {openTool && (
        <EmberToolModal tool={openTool} onClose={() => setOpenTool(null)} />
      )}
    </div>
  );
}

interface EmberTurn {
  role: "ember" | "director";
  text: string;
  /** Optional generated image URL (poster tool). */
  image?: string | null;
}

/**
 * The Ember tool modal — a real back-and-forth with Ember. Ember opens with a
 * targeted question (the director-tuned opener), the director replies, and
 * Ember responds using the same `emberAsk` backend every other Ember surface
 * uses. The poster tool additionally calls `emberImagine` to generate a real
 * movie poster image once Ember has the mood + anchor image.
 */
function EmberToolModal({ tool, onClose }: { tool: Tool; onClose: () => void }) {
  const mode = loadCoachMode();
  const pillPalette = jasperPillPalette(mode);
  const [turns, setTurns] = useState<EmberTurn[]>([]);
  const [input, setInput] = useState<string>("");
  const [seed, setSeed] = useState<string>("");
  const [phase, setPhase] = useState<"seed" | "chat">("seed");
  const [isThinking, setIsThinking] = useState<boolean>(false);
  const [posterLoading, setPosterLoading] = useState<boolean>(false);
  const [posterUrl, setPosterUrl] = useState<string | null>(null);
  const scrollRef = useRef<HTMLDivElement | null>(null);

  // Auto-scroll to the bottom as the thread grows.
  useEffect(() => {
    const el = scrollRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [turns, isThinking]);

  const start = async (): Promise<void> => {
    if (!seed.trim()) return;
    setPhase("chat");
    setTurns([{ role: "director", text: seed.trim() }]);
    await runEmber(tool.opener(seed.trim()));
  };

  const runEmber = async (prompt: string): Promise<void> => {
    setIsThinking(true);
    try {
      const reply = await emberAsk(`${tool.system}\n\n${prompt}`);
      setTurns((prev) => [...prev, { role: "ember", text: reply || "I lost my train of thought — try again." }]);
    } catch {
      setTurns((prev) => [
        ...prev,
        { role: "ember", text: "I lost my train of thought — try again." },
      ]);
    } finally {
      setIsThinking(false);
    }
  };

  const send = async (): Promise<void> => {
    const text = input.trim();
    if (!text || isThinking) return;
    setInput("");
    setTurns((prev) => [...prev, { role: "director", text }]);
    const history = turns
      .map((t) => (t.role === "director" ? `Director: ${t.text}` : `Jasper: ${t.text}`))
      .join("\n");
    await runEmber(
      `${tool.system}\n\nConversation so far:\n${history}\n\nDirector: ${text}\n\nContinue as Jasper. Stay in character, keep it short, and ask the next useful question if it helps move the work forward.`
    );

    // For the poster tool: once Ember has replied with a poster description,
    // automatically generate the image. We detect "ready" by the director
    // having answered the opener question (turns now has ≥ 4 entries).
    if (tool.id === "posterConcept" && !posterUrl && !posterLoading) {
      void maybeGeneratePoster();
    }
  };

  /**
   * For the poster tool — ask Ember to turn the conversation into a single
   * image-generation prompt, then generate the poster with `emberImagine`.
   */
  const maybeGeneratePoster = async (): Promise<void> => {
    setPosterLoading(true);
    try {
      const history = [...turns, { role: "director" as const, text: input }]
        .map((t) => (t.role === "director" ? `Director: ${t.text}` : `Jasper: ${t.text}`))
        .join("\n");
      const promptRequest = `${tool.system}\n\nConversation so far:\n${history}\n\nNow write a single, vivid image-generation prompt for the movie poster. One sentence: composition, subject, palette, lighting, and negative space for the title. Do not include any other text.`;
      const imagePrompt = await emberAsk(promptRequest);
      if (!imagePrompt) {
        setPosterLoading(false);
        return;
      }
      const url = await emberImagine(imagePrompt);
      if (url) {
        setPosterUrl(url);
        setTurns((prev) => [
          ...prev,
          { role: "ember", text: "Here's your poster. Save it or ask me to try a different mood.", image: url },
        ]);
      }
    } catch {
      // silent — the thread continues either way
    } finally {
      setPosterLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center">
      <button
        aria-label="Close"
        onClick={onClose}
        className="absolute inset-0 bg-black/55 backdrop-blur-sm"
      />
      <div className="relative flex max-h-[90vh] w-full max-w-lg flex-col overflow-hidden rounded-t-[24px] bg-background shadow-2xl sm:rounded-[24px]">
        {/* Header — Jasper's work room: the mint pill with the living mascot
            peeking from behind it, personality-tinted like every other dock. */}
        <div className="relative border-b border-border px-5 pb-3.5 pt-8">
          <div className="relative mx-auto w-fit">
            <span
              className="pointer-events-none absolute -top-[22px] left-1/2 z-0"
              style={{ transform: "translateX(-50%)" }}
            >
              <EmberMascot
                size={44}
                coachMode={mode}
                isActive={isThinking}
                expression={isThinking ? "thinking" : "calm"}
              />
            </span>
            <span
              className="relative z-10 flex h-9 items-center gap-2 rounded-full px-5"
              style={jasperMintShellStyle(mode)}
            >
              <tool.icon className="h-3.5 w-3.5" style={{ color: pillPalette.ink }} />
              <span className="text-[13px] font-black" style={{ color: pillPalette.ink }}>
                {tool.label}
              </span>
            </span>
          </div>
          <p className="mt-2 text-center text-[11px] text-muted-foreground">{tool.tagline}</p>
          <button
            onClick={onClose}
            aria-label="Close"
            className="absolute right-3.5 top-3.5 flex h-9 w-9 items-center justify-center rounded-full bg-secondary transition-transform active:scale-90"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {/* Body */}
        <div ref={scrollRef} className="min-h-0 flex-1 overflow-y-auto px-5 py-4">
          {phase === "seed" ? (
            <SeedStep
              tool={tool}
              seed={seed}
              setSeed={setSeed}
              onStart={start}
              isThinking={isThinking}
            />
          ) : (
            <div className="space-y-3">
              {turns.map((t, i) => (
                <Bubble key={i} turn={t} />
              ))}
              {posterLoading && (
                <div className="flex items-center gap-2 text-[12.5px] text-muted-foreground">
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  Jasper is generating the poster…
                </div>
              )}
              {isThinking && !posterLoading && (
                <div className="flex items-center gap-2 text-[12.5px] text-muted-foreground">
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  Jasper is thinking…
                </div>
              )}
            </div>
          )}
        </div>

        {/* Composer */}
        {phase === "chat" && (
          <div className="border-t border-border px-5 py-3 pb-[max(0.75rem,env(safe-area-inset-bottom))]">
            <div className="flex items-center gap-2">
              <input
                value={input}
                onChange={(e) => setInput(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" && !e.shiftKey) {
                    e.preventDefault();
                    void send();
                  }
                }}
                placeholder="Reply to Jasper…"
                className="min-w-0 flex-1 rounded-xl border border-border bg-card px-3.5 py-2.5 text-[14px] outline-none placeholder:text-muted-foreground/60"
              />
              <button
                onClick={() => void send()}
                disabled={isThinking || !input.trim()}
                className="flex h-10 w-10 items-center justify-center rounded-xl bg-foreground text-background transition-transform active:scale-95 disabled:opacity-40"
                aria-label="Send"
              >
                <Plus className="h-4 w-4 rotate-45" />
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function SeedStep({
  tool,
  seed,
  setSeed,
  onStart,
  isThinking,
}: {
  tool: Tool;
  seed: string;
  setSeed: (v: string) => void;
  onStart: () => void;
  isThinking: boolean;
}) {
  const placeholder =
    tool.id === "synopsisPolish"
      ? "Paste your current synopsis…"
      : tool.id === "readTheFilm"
        ? "Paste your synopsis — Jasper will read the whole thing…"
        : tool.id === "posterConcept"
          ? "What's the film about? Jasper will ask about the mood, then generate a poster…"
          : tool.id === "releasePlan"
            ? "What film are you scheduling?"
            : "What's the film about?";
  const mode = loadCoachMode();
  const modeInfo = coachModeInfo(mode);
  const pillPalette = jasperPillPalette(mode);
  // Fast-start chips seeded from the real slate — one tap drops a film into
  // the seed box so the work room starts from something real.
  const filmsQuery = useQuery({ queryKey: ["films"], queryFn: () => fetchFilms() });
  const slate = (filmsQuery.data ?? []).filter((f) => f.published).slice(0, 3);
  return (
    <div>
      <p className="text-[13.5px] leading-relaxed text-muted-foreground">
        Jasper will ask you a question, then work with you on{" "}
        <span className="font-bold text-foreground">{tool.label.toLowerCase()}</span>.
        {tool.id === "readTheFilm" && " Paste the full synopsis — Jasper reads the whole thing."}
        {tool.id === "posterConcept" && " Jasper will generate a real movie poster image once it has the mood."}
      </p>
      <textarea
        value={seed}
        onChange={(e) => setSeed(e.target.value)}
        placeholder={placeholder}
        rows={tool.id === "readTheFilm" || tool.id === "synopsisPolish" ? 5 : 3}
        autoFocus
        className="mt-3 w-full resize-none rounded-xl border border-border bg-card px-3.5 py-2.5 text-[14px] outline-none placeholder:text-muted-foreground/60"
      />
      {slate.length > 0 && (
        <div className="mt-3">
          <p className="text-[9px] font-black uppercase tracking-[0.16em] text-muted-foreground/70">
            Fast start — your slate
          </p>
          <div className="mt-1.5 flex flex-wrap gap-1.5">
            {slate.map((f) => (
              <button
                key={f.id}
                type="button"
                onClick={() => setSeed(`"${f.title}"${f.synopsis ? ` — ${f.synopsis}` : ""}`)}
                className="flex items-center gap-1.5 rounded-full border border-border bg-secondary/60 px-3 py-1.5 text-[11px] font-bold text-foreground/80 transition-colors hover:bg-secondary"
              >
                <FilmIcon className="h-3 w-3" style={{ color: modeInfo.deepAccent }} />
                <span className="max-w-[10rem] truncate">{f.title}</span>
              </button>
            ))}
          </div>
        </div>
      )}
      <button
        onClick={() => void onStart()}
        disabled={isThinking || !seed.trim()}
        className="mt-3 flex w-full items-center justify-center gap-2 rounded-full py-3 text-[14px] font-black transition-transform active:scale-[0.98] disabled:opacity-40"
        style={{
          background: `linear-gradient(135deg, ${modeInfo.accent}, ${modeInfo.deepAccent})`,
          color: pillPalette.ink,
        }}
      >
        {isThinking ? (
          <Loader2 className="h-4 w-4 animate-spin" />
        ) : (
          <Sparkles className="h-4 w-4" />
        )}
        Start with Jasper
      </button>
    </div>
  );
}

/** Animated thinking indicator with three pulsing dots. */
function ThinkingIndicator({ generating }: { generating: boolean }) {
  return (
    <div className="flex justify-start">
      <div className="rounded-2xl rounded-bl-md bg-secondary px-4 py-3">
        <p
          className="mb-1.5 flex items-center gap-1 text-[10px] font-black uppercase tracking-[0.14em]"
          style={{ color: coachModeInfo(loadCoachMode()).deepAccent }}
        >
          <Sparkles className="h-2.5 w-2.5" /> Jasper
        </p>
        <div className="flex items-center gap-2">
          <span className="flex gap-1">
            <span className="h-1.5 w-1.5 animate-bounce rounded-full bg-muted-foreground/60 [animation-delay:-0.3s]" />
            <span className="h-1.5 w-1.5 animate-bounce rounded-full bg-muted-foreground/60 [animation-delay:-0.15s]" />
            <span className="h-1.5 w-1.5 animate-bounce rounded-full bg-muted-foreground/60" />
          </span>
          <span className="text-[12px] text-muted-foreground">
            {generating ? "Generating the poster…" : "Thinking…"}
          </span>
        </div>
      </div>
    </div>
  );
}

function Bubble({ turn }: { turn: EmberTurn }) {
  const isEmber = turn.role === "ember";
  const modeInfo = coachModeInfo(loadCoachMode());
  return (
    <div className={`flex animate-in fade-in slide-in-from-bottom-1 duration-300 ${isEmber ? "justify-start" : "justify-end"}`}>
      {isEmber ? (
        <div
          className="relative max-w-[88%] rounded-2xl rounded-bl-md border bg-secondary py-3 pl-4 pr-4 text-[13.5px] leading-relaxed text-foreground"
          style={{ borderColor: `${modeInfo.accent}59` }}
        >
          <span
            className="absolute bottom-3 left-[6px] top-3 w-[3px] rounded-full"
            style={{ background: `${modeInfo.accent}B3` }}
            aria-hidden
          />
          <p
            className="mb-1 flex items-center gap-1.5 text-[9.5px] font-black uppercase tracking-[0.14em]"
            style={{ color: modeInfo.deepAccent }}
          >
            <Sparkles className="h-2.5 w-2.5" /> Jasper
            <span className="rounded-full bg-foreground/[0.06] px-1.5 py-0.5 text-[7.5px] font-black tracking-[0.08em] text-muted-foreground">
              {modeInfo.shortTitle.toUpperCase()}
            </span>
          </p>
          <p className="whitespace-pre-wrap">{turn.text}</p>
          {turn.image && (
            <div className="mt-3 overflow-hidden rounded-xl border border-border/60">
              <img
                src={turn.image}
                alt="Generated poster"
                className="w-full object-cover"
              />
              <a
                href={turn.image}
                download="whisper-poster.png"
                className="flex items-center gap-1 border-t border-border/60 bg-background px-3 py-2 text-[11px] font-bold text-foreground/70 transition-colors hover:text-foreground"
              >
                <Download className="h-3 w-3" /> Download poster
              </a>
            </div>
          )}
        </div>
      ) : (
        <div className="max-w-[85%] rounded-2xl rounded-br-md bg-foreground px-4 py-3 text-[13.5px] leading-relaxed text-background">
          <p className="whitespace-pre-wrap">{turn.text}</p>
        </div>
      )}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Published films                                                     */
/* ------------------------------------------------------------------ */

/** List of the director's published films, with a quick edit affordance. */
function PublishedFilmsSection() {
  const filmsQuery = useQuery({
    queryKey: ["films"],
    queryFn: () => fetchFilms(),
  });
  const films = filmsQuery.data ?? [];

  if (films.length === 0) return null;

  return (
    <div className="mt-5 rounded-[20px] border border-border bg-card p-5">
      <h2 className="text-[14px] font-extrabold">Published films</h2>
      <p className="mt-0.5 text-[12px] text-muted-foreground">
        What's live on the premiere page.
      </p>
      <div className="mt-3 space-y-2">
        {films.map((film: Film) => (
          <a
            key={film.id}
            href={`/films/${film.id}`}
            className="flex items-center gap-3 rounded-2xl border border-border bg-background p-3 transition-colors hover:bg-secondary/40"
          >
            <div className="flex h-12 w-20 shrink-0 items-center justify-center overflow-hidden rounded-xl bg-black">
              {film.poster_url ? (
                <img
                  src={film.poster_url}
                  alt=""
                  className="h-full w-full object-cover"
                />
              ) : (
                <FilmIcon className="h-5 w-5 text-white/50" />
              )}
            </div>
            <div className="min-w-0 flex-1">
              <p className="truncate text-[14px] font-bold">{film.title}</p>
              <p className="truncate text-[12px] text-muted-foreground">
                {film.featured_date
                  ? new Date(film.featured_date + "T00:00:00").toLocaleDateString("en-US", {
                      month: "short",
                      day: "numeric",
                    })
                  : "Unscheduled"}
              </p>
            </div>
            {film.featured_date && (
              <span className="rounded-full bg-foreground/5 px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-wider text-muted-foreground">
                Scheduled
              </span>
            )}
          </a>
        ))}
      </div>
    </div>
  );
}
