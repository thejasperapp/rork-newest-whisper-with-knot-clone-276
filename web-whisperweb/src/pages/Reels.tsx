import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import {
  Plus,
  MoreHorizontal,
  Volume2,
  VolumeX,
  Music2,
  Play,
  ExternalLink,
  Camera,
  ChevronDown,
  ChevronUp,
  Check,
  X,
} from "lucide-react";
import { toast } from "sonner";

import { WhisperLogo } from "@/components/WhisperLogo";
import { Avatar } from "@/components/Avatar";
import { UserBadges } from "@/components/UserBadges";
import { PostCorrectionNotice } from "@/components/PostCorrectionNotice";
import { MentionText } from "@/components/MentionText";
import { ReelComposerModal } from "@/components/ReelComposerModal";
import { SharePostDialog } from "@/components/SharePostDialog";
import { SoundSheet } from "@/components/SoundSheet";
import { stripPostMeta, waveCoverUrl, type PostMusic } from "@/lib/postMeta";
import { soundForPost, soundLabel } from "@/lib/waveSounds";
import { cn } from "@/lib/utils";
import { playLikeSound } from "@/lib/meetSounds";
import { compactCount, timeAgo } from "@/lib/format";
import { useAuth } from "@/hooks/useAuth";
import { useDocumentVisible } from "@/hooks/useDocumentVisible";
import { WhisperHeart as Heart, WhisperComment as MessageCircle, WhisperShare as Send } from "@/components/WhisperGlyph";
import { supabase } from "@/lib/supabase";
import {
  fetchReels,
  fetchProfilesByIds,
  fetchMyLikedPostIds,
  fetchLiarBadges,
  toggleLike,
  isFollowing,
  toggleFollow,
  fetchComments,
  addComment,
} from "@/lib/api";
import {
  fetchActiveAds,
  trackAdClick,
  trackAdImpression,
  externalUrl,
  type ActiveAd,
} from "@/lib/business";
import type { WhisperPost, WhisperProfile } from "@/lib/types";

type ReelTab = "reels" | "friends";

export default function Reels() {
  const { user, profile } = useAuth();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const visible = useDocumentVisible();
  const [interactionID, setInteractionID] = useState<string | null>(null);
  const [tab, setTab] = useState<ReelTab>("reels");
  const [muted, setMuted] = useState<boolean>(true);
  const [composing, setComposing] = useState<boolean>(false);
  const [activeIndex, setActiveIndex] = useState<number>(0);
  const [sharePost, setSharePost] = useState<WhisperPost | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  // A shared wave (DM card → /reels?wave=<id>) opens ON that wave.
  const [searchParams] = useSearchParams();
  const startWaveId = searchParams.get("wave");
  const jumpedToStartRef = useRef<boolean>(false);
  // The Sounds system — the tapped sound's page, and the composer opened
  // from its "Use this sound" with that sound pre-attached.
  const [soundSheet, setSoundSheet] = useState<PostMusic | null>(null);
  const [composeMusic, setComposeMusic] = useState<PostMusic | null>(null);
  const [scopeOpen, setScopeOpen] = useState<boolean>(false);
  // Space bar pause — a tick the active card flips its own pause on.
  const [pauseToggle, setPauseToggle] = useState<number>(0);
  // HORIZONTAL SWIPES (iOS parity): swipe LEFT into Following, RIGHT back to
  // For you, and one more swipe right on For you EXITS Waves for Home. The
  // vertical paging scroll is untouched — only clearly horizontal drags act.
  const swipeStartRef = useRef<{ x: number; y: number; t: number } | null>(null);

  const reelsQuery = useQuery({
    queryKey: ["reels", user?.id],
    queryFn: () => fetchReels(60),
  });

  const targetQuery = useQuery({ queryKey: ["wave-target", user?.id, startWaveId], enabled: !!user && !!startWaveId, retry: false,
    queryFn: async ({ signal }) => {
      const { data, error } = await supabase.from("whisper_posts").select("*").eq("id", startWaveId!).eq("is_reel", true).abortSignal(signal).maybeSingle();
      if (error) throw new Error("Couldn't open this Wave.");
      return data as WhisperPost | null;
    },
  });
  useEffect(() => { jumpedToStartRef.current = false; }, [startWaveId, user?.id]);

  const likesQuery = useQuery({
    queryKey: ["my-likes", user?.id],
    queryFn: () => fetchMyLikedPostIds(user!.id),
    enabled: !!user,
  });

  const authorIds = useMemo(
    () => (reelsQuery.data ?? []).map((p) => p.user_id),
    [reelsQuery.data]
  );
  const profilesQuery = useQuery({
    queryKey: ["profiles", authorIds],
    queryFn: () => fetchProfilesByIds(authorIds),
    enabled: authorIds.length > 0,
  });
  const profiles = profilesQuery.data ?? {};

  const authorUsernames = useMemo(
    () =>
      (reelsQuery.data ?? []).map(
        (p) => profiles[p.user_id]?.username ?? p.username ?? ""
      ),
    [reelsQuery.data, profiles]
  );
  const liarQuery = useQuery({
    queryKey: ["liar-badges", authorUsernames],
    queryFn: () => fetchLiarBadges(authorUsernames),
    enabled: authorUsernames.some(Boolean),
  });
  const liarBadges = liarQuery.data ?? {};

  // Following set for the Friends tab filter
  const followingQuery = useQuery({
    queryKey: ["is-following", user?.id],
    queryFn: async () => {
      if (!user) return new Set<string>();
      const { data } = await import("@/lib/supabase").then((m) =>
        m.supabase
          .from("whisper_follows")
          .select("following_id")
          .eq("follower_id", user.id)
      );
      return new Set<string>(
        ((data as { following_id: string }[] | null) ?? []).map(
          (r) => r.following_id
        )
      );
    },
    enabled: !!user && tab === "friends",
  });

  const allReels = useMemo(() => {
    const rows = reelsQuery.data ?? [];
    return targetQuery.data && !rows.some(row => row.id === targetQuery.data.id) ? [targetQuery.data, ...rows] : rows;
  }, [reelsQuery.data, targetQuery.data]);
  const reels = useMemo(() => {
    if (tab !== "friends") return allReels;
    const following = followingQuery.data ?? new Set<string>();
    return allReels.filter((p) => following.has(p.user_id));
  }, [allReels, tab, followingQuery.data]);

  const likedSet = useMemo(
    () => new Set(likesQuery.data ?? []),
    [likesQuery.data]
  );

  // The "reels" ad placement — a full-screen sponsored slide every 5
  // reels, cycling the live rotation from Whisper Business.
  const reelAdsQuery = useQuery({
    queryKey: ["business-active-ads", "reels"],
    queryFn: () => fetchActiveAds("reels", 4),
    enabled: !!user,
    staleTime: 5 * 60 * 1000,
  });
  const reelAds = useMemo(
    () => reelAdsQuery.data ?? [],
    [reelAdsQuery.data]
  );

  type ReelSlide =
    | { kind: "reel"; reel: WhisperPost }
    | { kind: "ad"; ad: ActiveAd };
  const slides = useMemo<ReelSlide[]>(() => {
    const out: ReelSlide[] = [];
    reels.forEach((reel, i) => {
      out.push({ kind: "reel", reel });
      if (reelAds.length > 0 && (i + 1) % 5 === 0) {
        out.push({
          kind: "ad",
          ad: reelAds[Math.floor(i / 5) % reelAds.length],
        });
      }
    });
    return out;
  }, [reels, reelAds]);

  // Track which reel is centered via scroll position
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const handler = (): void => {
      const idx = Math.round(el.scrollTop / el.clientHeight);
      setActiveIndex(idx);
    };
    el.addEventListener("scroll", handler, { passive: true });
    return () => el.removeEventListener("scroll", handler);
  }, []);

  const scrollToIndex = useCallback(
    (idx: number): void => {
      const el = containerRef.current;
      if (!el) return;
      const clamped = Math.max(0, Math.min(idx, Math.max(0, slides.length - 1)));
      el.scrollTo({ top: clamped * el.clientHeight, behavior: "smooth" });
    },
    [slides.length]
  );

  // DESKTOP WHEEL PAGING — the root of "waves don't work on desktop": with
  // mandatory snapping, a mouse-wheel tick moves the stage a few dozen
  // pixels and the browser snaps it straight BACK to the same wave, so the
  // wheel could never advance. Instagram intercepts the wheel and pages ONE
  // wave per gesture; so do we — accumulate a gesture's deltas, page once
  // it clearly commits, then ignore the inertia tail for a beat.
  const activeIndexRef = useRef<number>(0);
  activeIndexRef.current = activeIndex;
  const scrollToIndexRef = useRef<(idx: number) => void>(scrollToIndex);
  scrollToIndexRef.current = scrollToIndex;
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    let acc = 0;
    let lastPage = 0;
    let resetTimer: number | null = null;
    const onWheel = (e: WheelEvent): void => {
      if (Math.abs(e.deltaY) < Math.abs(e.deltaX)) return;
      e.preventDefault();
      const now = performance.now();
      if (now - lastPage < 620) return;
      acc += e.deltaY;
      if (resetTimer != null) window.clearTimeout(resetTimer);
      resetTimer = window.setTimeout(() => {
        acc = 0;
      }, 160);
      if (Math.abs(acc) < 36) return;
      const dir = acc > 0 ? 1 : -1;
      acc = 0;
      lastPage = now;
      scrollToIndexRef.current(activeIndexRef.current + dir);
    };
    el.addEventListener("wheel", onWheel, { passive: false });
    return () => {
      el.removeEventListener("wheel", onWheel);
      if (resetTimer != null) window.clearTimeout(resetTimer);
    };
  }, []);

  // Land on the shared wave once the pool contains it (one shot per visit).
  useEffect(() => {
    if (!startWaveId || jumpedToStartRef.current) return;
    const idx = slides.findIndex(
      (s) => s.kind === "reel" && s.reel.id === startWaveId
    );
    if (idx < 0) return;
    const el = containerRef.current;
    if (!el) return;
    jumpedToStartRef.current = true;
    el.scrollTo({ top: idx * el.clientHeight, behavior: "auto" });
    setActiveIndex(idx);
  }, [startWaveId, slides]);

  // Desktop grammar: ↑/↓ (or J/K) step waves, M toggles sound, Space
  // pauses — never while typing or while a sheet is up.
  useEffect(() => {
    const handler = (e: KeyboardEvent): void => {
      const target = e.target as HTMLElement | null;
      if (
        target &&
        (target.tagName === "INPUT" ||
          target.tagName === "TEXTAREA" ||
          target.isContentEditable)
      ) {
        return;
      }
      if (composing || soundSheet || sharePost || interactionID || !visible || scopeOpen) return;
      if (e.key === "ArrowDown" || e.key === "j") {
        e.preventDefault();
        scrollToIndex(activeIndex + 1);
      } else if (e.key === "ArrowUp" || e.key === "k") {
        e.preventDefault();
        scrollToIndex(activeIndex - 1);
      } else if (e.key === "m" || e.key === "M") {
        setMuted((m) => !m);
      } else if (e.key === " ") {
        e.preventDefault();
        setPauseToggle((t) => t + 1);
      }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [activeIndex, composing, soundSheet, sharePost, interactionID, visible, scopeOpen, scrollToIndex]);

  const onSwipeStart = (e: React.TouchEvent<HTMLDivElement>): void => {
    const t = e.touches[0];
    if (!t) return;
    swipeStartRef.current = { x: t.clientX, y: t.clientY, t: performance.now() };
  };

  const onSwipeEnd = (e: React.TouchEvent<HTMLDivElement>): void => {
    const start = swipeStartRef.current;
    swipeStartRef.current = null;
    const t = e.changedTouches[0];
    if (!start || !t) return;
    if (composing || soundSheet || sharePost || scopeOpen || interactionID || !visible) return;
    const dx = t.clientX - start.x;
    const dy = t.clientY - start.y;
    const elapsed = Math.max(1, performance.now() - start.t);
    const velocity = Math.abs(dx) / elapsed; // px per ms
    if (Math.abs(dx) < Math.abs(dy) * 1.4) return;
    if (Math.abs(dx) < 70 && velocity < 0.55) return;
    if (dx < 0) {
      if (tab !== "friends") {
        setTab("friends");
        scrollToIndex(0);
      }
      return;
    }
    if (tab === "friends") {
      setTab("reels");
      scrollToIndex(0);
    } else {
      navigate("/");
    }
  };

  return (
    <div
      className="fixed inset-0 z-40 bg-black"
      onTouchStart={onSwipeStart}
      onTouchEnd={onSwipeEnd}
      onTouchCancel={() => {
        swipeStartRef.current = null;
      }}
    >
      {startWaveId && (targetQuery.isPending || targetQuery.isError || !targetQuery.data) && <div role="status" className="absolute inset-0 z-50 flex flex-col items-center justify-center gap-4 bg-black p-6 text-center text-white"><p>{targetQuery.isPending ? "Opening Wave…" : "This Wave is unavailable or you no longer have access."}</p><button className="min-h-11 rounded-full border border-white/30 px-6" onClick={() => navigate("/reels", { replace: true })}>Back to Waves</button>{targetQuery.isError && <button className="min-h-11" onClick={() => void targetQuery.refetch()}>Retry</button>}</div>}
      {/* Snap-scrolling wave container — full-bleed on phones; on desktop a
          centered 9:16 stage with the action rail standing BESIDE it
          (Instagram web's grammar) instead of a video stretched across a
          landscape monitor. The desktop column = stage + 16px gap + 56px rail. */}
      <div
        ref={containerRef}
        className="no-scrollbar mx-auto h-full w-full snap-y snap-mandatory overflow-y-scroll lg:w-[calc((100dvh-2rem)*9/16+72px)]"
      >
        {slides.map((slide, i) =>
          slide.kind === "reel" ? (
            <ReelCard
              key={slide.reel.id}
              reel={slide.reel}
              author={profiles[slide.reel.user_id]}
              liar={liarBadges[(profiles[slide.reel.user_id]?.username ?? slide.reel.username ?? "").toLowerCase()]}
              liked={likedSet.has(slide.reel.id)}
              muted={muted}
              isActive={i === activeIndex && visible && !soundSheet && !composing && !sharePost && !scopeOpen && !interactionID && (!startWaveId || !!targetQuery.data)}
              setInteractionID={setInteractionID}
              near={Math.abs(i - activeIndex) <= 1}
              pauseToggle={pauseToggle}
              onOpenSound={setSoundSheet}
              meId={user?.id ?? ""}
              meUsername={profile?.username ?? "you"}
            />
          ) : (
            <SponsoredReelSlide
              key={`ad-${slide.ad.id}-${i}`}
              ad={slide.ad}
              isActive={i === activeIndex && visible && !soundSheet && !composing && !sharePost && !scopeOpen && !interactionID && (!startWaveId || !!targetQuery.data)}
              muted={muted}
            />
          )
        )}

        {reels.length === 0 && !reelsQuery.isLoading && (
          <div className="flex h-full snap-start flex-col items-center justify-center gap-4 px-8 text-center">
            <div className="flex h-16 w-16 items-center justify-center rounded-full border-2 border-white/30">
              <Play className="h-7 w-7 text-white/70" />
            </div>
            <h2 className="font-display text-lg font-bold text-white">
              {tab === "friends" ? "No waves from people you follow yet" : "No waves yet"}
            </h2>
            <p className="max-w-xs text-sm text-white/50">
              {tab === "friends"
                ? "Follow more people to see their waves here."
                : "Be the first — make a wave. Tap the camera up top."}
            </p>
            <button
              onClick={() => setComposing(true)}
              className="mt-2 flex items-center gap-1.5 rounded-full bg-white px-5 py-2.5 text-sm font-bold text-black transition-transform active:scale-95"
            >
              <Plus className="h-4 w-4" />
              New wave
            </button>
          </div>
        )}

        {reelsQuery.isLoading && (
          <div className="flex h-full snap-start items-center justify-center">
            <div className="h-8 w-8 animate-spin rounded-full border-2 border-white/20 border-t-white" />
          </div>
        )}
      </div>

      {/* The kit's Reels header (decoded from the Figma Reels frames): ONE
          36px row hugging the safe area — "For you ⌄" top-left, bare sound +
          camera glyphs top-right, no plates. Same width as the stage. */}
      {scopeOpen && (
        <button
          aria-hidden
          onClick={() => setScopeOpen(false)}
          className="absolute inset-0 z-[19] cursor-default"
        />
      )}
      <div className="pointer-events-none absolute inset-x-0 top-0 z-20 mx-auto flex h-9 w-full items-center justify-between px-4 mt-[calc(env(safe-area-inset-top,0px)+6px)] lg:mt-[22px] lg:w-[calc((100dvh-2rem)*9/16)] lg:-translate-x-9">
        <div className="pointer-events-auto relative">
          <button
            onClick={() => setScopeOpen((o) => !o)}
            aria-haspopup="menu"
            aria-expanded={scopeOpen}
            className="flex h-9 items-center gap-1.5 text-[18px] font-semibold text-white drop-shadow-lg"
          >
            {tab === "friends" ? "Following" : "For you"}
            <ChevronDown className="mt-px h-4 w-4" strokeWidth={2.6} />
          </button>
          {scopeOpen && (
            <div
              role="menu"
              className="absolute left-0 top-11 w-48 overflow-hidden rounded-2xl border border-white/10 bg-[#141414]/95 py-1 shadow-2xl backdrop-blur-xl"
            >
              {(["reels", "friends"] as ReelTab[]).map((t) => (
                <button
                  key={t}
                  role="menuitem"
                  onClick={() => {
                    setTab(t);
                    setScopeOpen(false);
                    scrollToIndex(0);
                  }}
                  className="flex w-full items-center justify-between px-4 py-2.5 text-[14px] font-semibold text-white transition-colors hover:bg-white/10"
                >
                  {t === "friends" ? "Following" : "For you"}
                  {tab === t && <Check className="h-4 w-4" />}
                </button>
              ))}
            </div>
          )}
        </div>

        <div className="pointer-events-auto flex items-center gap-0.5">
          <button
            onClick={() => setMuted((m) => !m)}
            aria-label={muted ? "Unmute" : "Mute"}
            className="flex h-9 w-9 items-center justify-center transition-transform active:scale-90"
          >
            {muted ? (
              <VolumeX className="h-[22px] w-[22px] text-white drop-shadow-lg" strokeWidth={1.9} />
            ) : (
              <Volume2 className="h-[22px] w-[22px] text-white drop-shadow-lg" strokeWidth={1.9} />
            )}
          </button>
          <button
            onClick={() => {
              setComposeMusic(null);
              setComposing(true);
            }}
            aria-label="New wave"
            className="flex h-9 w-9 items-center justify-center transition-transform active:scale-90"
          >
            <Camera className="h-[26px] w-[26px] text-white drop-shadow-lg" strokeWidth={1.7} />
          </button>
        </div>
      </div>

      {/* Desktop: back to the feed — outside the stage, quiet */}
      <Link
        to="/"
        aria-label="Back to Whisper"
        className="absolute left-5 z-20 hidden items-center gap-1.5 text-white/55 transition-colors hover:text-white lg:flex"
        style={{ top: "calc(env(safe-area-inset-top, 0px) + 12px)" }}
      >
        <WhisperLogo size={22} />
      </Link>

      {/* Desktop: step chevrons beside the stage (Instagram web's grammar) */}
      <div className="pointer-events-none absolute inset-y-0 right-6 z-20 hidden flex-col items-center justify-center gap-3 lg:flex">
        <button
          type="button"
          onClick={() => scrollToIndex(activeIndex - 1)}
          disabled={activeIndex <= 0}
          aria-label="Previous wave"
          className="pointer-events-auto flex h-11 w-11 items-center justify-center rounded-full bg-white/12 text-white backdrop-blur-md transition-all hover:bg-white/22 disabled:opacity-25 disabled:hover:bg-white/12"
        >
          <ChevronUp className="h-5 w-5" strokeWidth={2.4} />
        </button>
        <button
          type="button"
          onClick={() => scrollToIndex(activeIndex + 1)}
          disabled={activeIndex >= slides.length - 1}
          aria-label="Next wave"
          className="pointer-events-auto flex h-11 w-11 items-center justify-center rounded-full bg-white/12 text-white backdrop-blur-md transition-all hover:bg-white/22 disabled:opacity-25 disabled:hover:bg-white/12"
        >
          <ChevronDown className="h-5 w-5" strokeWidth={2.4} />
        </button>
      </div>

      <ReelComposerModal
        open={composing}
        onOpenChange={(o) => {
          setComposing(o);
          if (!o) setComposeMusic(null);
        }}
        initialMusic={composeMusic}
      />

      {soundSheet && (
        <SoundSheet
          sound={soundSheet}
          pool={allReels}
          profiles={profiles}
          onClose={() => setSoundSheet(null)}
          onUse={(s) => {
            setSoundSheet(null);
            setComposeMusic(s);
            setComposing(true);
          }}
          onOpenWave={(post) => {
            setSoundSheet(null);
            const idx = slides.findIndex(
              (s) => s.kind === "reel" && s.reel.id === post.id
            );
            if (idx >= 0) scrollToIndex(idx);
          }}
        />
      )}

      {sharePost && (
        <SharePostDialog
          open={!!sharePost}
          onOpenChange={(o) => !o && setSharePost(null)}
          post={sharePost}
          authorUsername={profiles[sharePost.user_id]?.username ?? sharePost.username ?? "user"}
        />
      )}
    </div>
  );
}

function ReelCard({
  reel,
  author,
  liar,
  liked,
  muted,
  isActive,
  near,
  pauseToggle,
  onOpenSound,
  meId,
  meUsername,
  setInteractionID,
}: {
  setInteractionID: React.Dispatch<React.SetStateAction<string | null>>;
  reel: WhisperPost;
  author?: WhisperProfile;
  liar?: import("@/lib/types").WhisperLiarBadge | null;
  liked: boolean;
  muted: boolean;
  isActive: boolean;
  /** Within one slide of the active wave — only these mount a <video>. */
  near: boolean;
  /** Space-bar tick from the page; the active card flips its pause. */
  pauseToggle: number;
  onOpenSound: (sound: PostMusic) => void;
  meId: string;
  meUsername: string;
}) {
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const videoRef = useRef<HTMLVideoElement>(null);
  const [paused, setPaused] = useState<boolean>(false);
  const [optimisticLiked, setOptimisticLiked] = useState<boolean>(liked);
  const [likeBump, setLikeBump] = useState<number>(0);
  const [heartBurst, setHeartBurst] = useState<number>(0);
  const [captionExpanded, setCaptionExpanded] = useState<boolean>(false);
  const [following, setFollowing] = useState<boolean>(false);
  const [showShare, setShowShare] = useState<boolean>(false);
  const [showComments, setShowComments] = useState<boolean>(false);
  useEffect(() => {
    if (!showComments && !showShare) return;
    setInteractionID(reel.id);
    return () => setInteractionID(current => current === reel.id ? null : current);
  }, [showComments, showShare, reel.id, setInteractionID]);
  // Playback truth: autoplay was refused (needs a click), the file failed to
  // load, or the footage is landscape (letterbox it instead of cropping).
  const [needsGesture, setNeedsGesture] = useState<boolean>(false);
  const [mediaError, setMediaError] = useState<boolean>(false);
  const [landscape, setLandscape] = useState<boolean>(false);

  // The my-likes query resolves after the reel renders — sync the optimistic
  // mirror so a refresh never drops an existing like.
  useEffect(() => setOptimisticLiked(liked), [liked]);

  const media = reel.media_urls ?? [];
  const videoUrl = media.find((u) => /\.(mp4|mov|webm|m4v)(\?|$)/i.test(u));
  const imageUrl = media.find((u) => !/\.(mp4|mov|webm|m4v)(\?|$)/i.test(u)) ?? media[0];
  // The poster is the SAVED cover (the composer's picked frame) first, then a
  // real still — never the video URL itself (browsers can't paint that).
  const coverUrl = waveCoverUrl(reel.caption) ?? (imageUrl && imageUrl !== videoUrl ? imageUrl : undefined);
  const username = author?.username ?? reel.username ?? "user";
  const displayName = author?.display_name ?? username;
  // The caption may lead with the meta wire (music etc.) — never show it raw.
  const caption = stripPostMeta(reel.caption);
  const sound = useMemo(() => soundForPost(reel, username), [reel, username]);
  const baseLikes = reel.likes_count ?? 0;
  const likeCount = baseLikes + (optimisticLiked ? 1 : 0) - (liked ? 1 : 0);
  const commentCount = reel.comments_count ?? 0;

  // Autoplay/pause based on active state (re-run when the video mounts).
  // The muted flag is set IMPERATIVELY before play(): React doesn't reflect
  // `muted` as an attribute on first mount and autoplay policy reads the
  // property — an unmuted first play() is refused and the wave sits on its
  // poster forever. A refusal that still happens surfaces a real play button.
  useEffect(() => {
    const v = videoRef.current;
    if (!v) return;
    if (isActive && !paused && !showShare && !showComments) {
      v.muted = muted;
      const attempt = v.play();
      if (attempt) {
        attempt
          .then(() => setNeedsGesture(false))
          .catch((err: unknown) => {
            const name = err instanceof Error ? err.name : "";
            if (name === "NotAllowedError") setNeedsGesture(true);
          });
      }
    } else {
      v.pause();
    }
  }, [isActive, paused, near, muted, showShare, showComments]);

  const playWithGesture = (): void => {
    const v = videoRef.current;
    if (!v) return;
    v.muted = muted;
    void v
      .play()
      .then(() => {
        setNeedsGesture(false);
        setPaused(false);
      })
      .catch(() => {});
  };

  // Space bar from the page — only the active card reacts.
  const lastPauseToggle = useRef<number>(pauseToggle);
  useEffect(() => {
    if (pauseToggle === lastPauseToggle.current) return;
    lastPauseToggle.current = pauseToggle;
    if (isActive) setPaused((p) => !p);
  }, [pauseToggle, isActive]);

  // Check follow status
  useQuery({
    queryKey: ["is-following", meId, reel.user_id],
    queryFn: async () => {
      const { supabase } = await import("@/lib/supabase");
      const { data } = await supabase
        .from("whisper_follows")
        .select("follower_id")
        .eq("follower_id", meId)
        .eq("following_id", reel.user_id)
        .maybeSingle();
      setFollowing(!!data);
      return !!data;
    },
    enabled: !!meId && meId !== reel.user_id,
  });

  const likeMutation = useMutation({
    mutationFn: () => toggleLike(reel.id, meId, optimisticLiked),
    onMutate: () => {
      if (!optimisticLiked) playLikeSound();
      setOptimisticLiked((v) => !v);
      setLikeBump((v) => v + 1);
    },
    onError: () => setOptimisticLiked((v) => !v),
    onSettled: () => queryClient.invalidateQueries({ queryKey: ["my-likes"] }),
  });

  const followMutation = useMutation({
    mutationFn: () => toggleFollow(meId, reel.user_id, username, following),
    onMutate: () => setFollowing((v) => !v),
    onSettled: () =>
      queryClient.invalidateQueries({ queryKey: ["is-following", meId] }),
  });

  const handleDoubleTap = (): void => {
    if (!optimisticLiked) {
      likeMutation.mutate();
    }
    setHeartBurst((v) => v + 1);
  };

  const lastTap = useRef<number>(0);
  const handleTap = (): void => {
    const now = Date.now();
    if (now - lastTap.current < 280) {
      handleDoubleTap();
      return;
    }
    lastTap.current = now;
    setTimeout(() => {
      if (Date.now() - lastTap.current >= 280) {
        setPaused((p) => !p);
      }
    }, 290);
  };

  // The action rail — rendered ONCE, placed twice: overlaid on the footage
  // on phones, standing beside the stage on desktop (Instagram web).
  const rail = (
    <>
        <button
          onClick={() => likeMutation.mutate()}
          className="flex flex-col items-center gap-1 transition-transform active:scale-90"
        >
          <span
            key={likeBump}
            className={cn(
              "flex h-12 w-12 items-center justify-center",
              optimisticLiked ? "animate-pop" : ""
            )}
          >
            <Heart
              className={cn(
                "h-8 w-8 text-white drop-shadow-lg",
                optimisticLiked && "fill-like text-like"
              )}
            />
          </span>
          <span className="text-[12px] font-semibold text-white drop-shadow">
            {compactCount(likeCount)}
          </span>
        </button>

        <button
          onClick={() => setShowComments(true)}
          className="flex flex-col items-center gap-1 transition-transform active:scale-90"
          aria-label="Comments"
        >
          <MessageCircle className="h-8 w-8 text-white drop-shadow-lg" />
          <span className="text-[12px] font-semibold text-white drop-shadow">
            {compactCount(commentCount)}
          </span>
        </button>

        <button
          onClick={() => setShowShare(true)}
          className="flex flex-col items-center gap-1 transition-transform active:scale-90"
        >
          <Send className="h-8 w-8 text-white drop-shadow-lg" />
          <span className="text-[12px] font-semibold text-white drop-shadow">
            Share
          </span>
        </button>

        <button
          onClick={() => navigate(`/u/${username}`)}
          className="mt-1 transition-transform active:scale-90"
          aria-label={`@${username}`}
        >
          <Avatar
            url={author?.profile_image_url}
            name={username}
            size={36}
            className="ring-2 ring-white/80"
          />
        </button>

        {/* TikTok's spinning record — album art (or the creator for original
            sounds), notes drifting off it while the wave plays. Tap → the
            sound page. */}
        <button
          onClick={() => onOpenSound(sound)}
          className="relative mt-1 transition-transform active:scale-90"
          aria-label={`Sound: ${soundLabel(sound)}`}
        >
          <span
            className={cn(
              "flex h-11 w-11 items-center justify-center rounded-full border-[1.5px] border-white/90 bg-gradient-to-b from-[#333] to-[#0a0a0a] shadow-lg",
              isActive && !paused && videoUrl && "animate-disc-spin"
            )}
          >
            <span className="absolute inset-[5px] rounded-full border border-white/10" />
            {sound.artworkURL ? (
              <img
                src={sound.artworkURL}
                alt=""
                className="h-[26px] w-[26px] rounded-full object-cover"
                draggable={false}
              />
            ) : (
              <Avatar url={author?.profile_image_url} name={username} size={26} />
            )}
          </span>
          {isActive && !paused && videoUrl && (
            <>
              <Music2 className="animate-float-note pointer-events-none absolute -left-2 top-1 h-3 w-3 text-white drop-shadow" />
              <Music2 className="animate-float-note-2 pointer-events-none absolute -left-1 top-3 h-3 w-3 text-white drop-shadow" />
            </>
          )}
        </button>
    </>
  );

  return (
    <div className="relative h-full w-full snap-start [scroll-snap-stop:always] lg:flex lg:items-center lg:justify-center">
     <div className="relative h-full w-full lg:flex lg:h-[calc(100%-2rem)] lg:w-auto lg:items-end lg:gap-4">
     {/* THE STAGE — full-bleed on phones, a rounded 9:16 card on desktop */}
     <div className="relative h-full w-full overflow-hidden bg-black lg:aspect-[9/16] lg:w-auto lg:rounded-2xl">
      {/* Landscape footage: the cover blurred behind, the video letterboxed */}
      {landscape && coverUrl && (
        <img
          src={coverUrl}
          alt=""
          className="pointer-events-none absolute inset-[-10%] h-[120%] w-[120%] object-cover opacity-60 blur-2xl"
          draggable={false}
        />
      )}

      {/* Media — video or image */}
      <div className="absolute inset-0 flex items-center justify-center" onClick={handleTap}>
        {videoUrl ? (
          near ? (
            <video
              ref={videoRef}
              src={videoUrl}
              poster={coverUrl}
              loop
              muted={muted}
              playsInline
              preload={isActive ? "auto" : "metadata"}
              onLoadedMetadata={(e) => {
                const v = e.currentTarget;
                setLandscape(v.videoWidth > v.videoHeight);
                setMediaError(false);
              }}
              onCanPlay={() => {
                const v = videoRef.current;
                if (v && isActive && !paused && v.paused) {
                  v.muted = muted;
                  void v.play().catch(() => {});
                }
              }}
              onError={() => setMediaError(true)}
              className={cn("h-full w-full", landscape ? "object-contain" : "object-cover")}
            />
          ) : coverUrl ? (
            <img
              src={coverUrl}
              alt=""
              className="h-full w-full object-cover"
              draggable={false}
              loading="lazy"
            />
          ) : (
            <div className="h-full w-full bg-black" />
          )
        ) : (
          <img
            src={imageUrl ?? ""}
            alt=""
            className="h-full w-full object-cover"
            draggable={false}
          />
        )}
      </div>

      {/* Gradient overlays for readability */}
      <div className="pointer-events-none absolute inset-0 bg-gradient-to-b from-black/40 via-transparent to-black/60" />

      {/* Autoplay refused — a real play button (the click is the gesture) */}
      {needsGesture && videoUrl && !mediaError && (
        <button
          type="button"
          onClick={(e) => {
            e.stopPropagation();
            playWithGesture();
          }}
          aria-label="Play"
          className="absolute inset-0 z-20 flex items-center justify-center"
        >
          <span className="flex h-20 w-20 items-center justify-center rounded-full bg-black/45 backdrop-blur-sm transition-transform active:scale-95">
            <Play className="ml-1 h-9 w-9 text-white" fill="white" />
          </span>
        </button>
      )}

      {/* Paused indicator */}
      {paused && videoUrl && !needsGesture && (
        <div className="pointer-events-none absolute inset-0 flex items-center justify-center">
          <div className="flex h-16 w-16 items-center justify-center rounded-full bg-black/40 backdrop-blur-sm">
            <Play className="h-8 w-8 text-white" fill="white" />
          </div>
        </div>
      )}

      {/* The file didn't load — say so, keep the poster */}
      {mediaError && (
        <div className="pointer-events-none absolute inset-0 z-20 flex flex-col items-center justify-center gap-1.5 bg-black/55 px-8 text-center">
          <p className="text-[15px] font-bold text-white">Couldn't play this wave</p>
          <p className="text-[12.5px] text-white/60">The video didn't load — it may still be processing. Try again in a moment.</p>
        </div>
      )}

      {/* Heart burst on double-tap */}
      {heartBurst > 0 && (
        <span
          key={heartBurst}
          className="animate-heart-burst pointer-events-none absolute inset-0 flex items-center justify-center"
        >
          <Heart className="h-28 w-28 fill-white text-white drop-shadow-2xl" />
        </span>
      )}

      {/* Phone rail — overlaid on the footage */}
      <div className="absolute bottom-24 right-3 z-10 flex flex-col items-center gap-5 lg:hidden">{rail}</div>

      {/* Bottom-left: author + caption + audio */}
      <div className="absolute bottom-24 left-4 right-20 z-10 space-y-2 lg:bottom-5 lg:right-4">
        <div className="flex items-center gap-2.5">
          <Link
            to={`/u/${username}`}
            className="flex items-center gap-2.5"
          >
            <Avatar
              url={author?.profile_image_url}
              name={username}
              size={32}
              className="ring-2 ring-white/60"
            />
            <span className="text-[15px] font-bold text-white drop-shadow-lg">
              {displayName}
            </span>
            <UserBadges profile={author} liar={liar} size={14} />
          </Link>
          {meId !== reel.user_id && (
            <button
              onClick={() => followMutation.mutate()}
              className={cn(
                "rounded-full px-3 py-1 text-[12px] font-bold transition-all",
                following
                  ? "border border-white/40 text-white"
                  : "bg-white text-black"
              )}
            >
              {following ? "Following" : "Follow"}
            </button>
          )}
        </div>

        <div className="max-h-[24vh] overflow-y-auto rounded-xl bg-card text-foreground"><PostCorrectionNotice postID={reel.id} /></div>
        {caption && (
          <div
            className={cn(
              "text-[14px] leading-snug text-white drop-shadow",
              !captionExpanded && "line-clamp-2"
            )}
          >
            <MentionText text={caption} />
            {caption.length > 80 && (
              <button
                onClick={() => setCaptionExpanded((v) => !v)}
                className="ml-1 text-white/60"
              >
                {captionExpanded ? "less" : "more"}
              </button>
            )}
          </div>
        )}

        {/* The attribution line — "♪ Original sound · username" or "♪ Title ·
            Artist" — scrolling when long. Tap → the sound page. */}
        <div className="flex items-center gap-2">
          <button
            onClick={() => onOpenSound(sound)}
            className="flex max-w-[240px] items-center gap-1.5 rounded-lg bg-black/40 px-2.5 py-1.5 text-[12px] font-semibold text-white backdrop-blur-sm transition-colors hover:bg-black/55"
            aria-label={`Sound: ${soundLabel(sound)}`}
          >
            <Music2 className="h-3.5 w-3.5 shrink-0" />
            <SoundMarquee text={soundLabel(sound)} />
          </button>
          <span className="text-[11px] text-white/55">{timeAgo(reel.created_at)}</span>
        </div>
      </div>

      {/* Progress bar for video reels */}
      {videoUrl && (
        <VideoProgress videoRef={videoRef} isActive={isActive} />
      )}
     </div>

     {/* Desktop rail — standing beside the stage, bottom-aligned */}
     <div className="hidden w-14 shrink-0 flex-col items-center gap-4 pb-2 lg:flex">{rail}</div>
     </div>

      {showShare && (
        <SharePostDialog
          open={showShare}
          onOpenChange={setShowShare}
          post={reel}
          authorUsername={username}
        />
      )}

      {showComments && (
        <WaveCommentsPanel
          postId={reel.id}
          authorUsername={username}
          caption={caption}
          meId={meId}
          meUsername={meUsername}
          onClose={() => setShowComments(false)}
        />
      )}
    </div>
  );
}

/**
 * The wave's comment thread — a docked panel beside the stage on desktop, a
 * bottom sheet on phones (the reels-comments grammar). The old comment
 * button navigated to `/?post=…`, a route nothing handled, so comments on
 * waves were unreachable on web.
 */
function WaveCommentsPanel({
  postId,
  authorUsername,
  caption,
  meId,
  meUsername,
  onClose,
}: {
  postId: string;
  authorUsername: string;
  caption: string;
  meId: string;
  meUsername: string;
  onClose: () => void;
}) {
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState<string>("");
  const inputRef = useRef<HTMLInputElement>(null);
  const commentsQuery = useQuery({
    queryKey: ["comments", postId],
    queryFn: () => fetchComments(postId),
  });
  const comments = commentsQuery.data ?? [];
  const authorIds = useMemo(
    () => Array.from(new Set(comments.map((c) => c.user_id))),
    [comments]
  );
  const profilesQuery = useQuery({
    queryKey: ["profiles", authorIds],
    queryFn: () => fetchProfilesByIds(authorIds),
    enabled: authorIds.length > 0,
  });
  const profiles = profilesQuery.data ?? {};

  const sendMutation = useMutation({
    mutationFn: (body: string) => addComment(postId, meId, meUsername, body),
    onSuccess: () => {
      setDraft("");
      void queryClient.invalidateQueries({ queryKey: ["comments", postId] });
    },
    onError: () => toast("Couldn't post that comment"),
  });

  useEffect(() => {
    const t = window.setTimeout(() => inputRef.current?.focus(), 80);
    const onKey = (e: KeyboardEvent): void => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => {
      window.clearTimeout(t);
      window.removeEventListener("keydown", onKey);
    };
  }, [onClose]);

  const submit = (): void => {
    const body = draft.trim();
    if (!body || !meId || sendMutation.isPending) return;
    sendMutation.mutate(body);
  };

  return (
    <div className="absolute inset-0 z-30 lg:fixed" onClick={onClose}>
      <div
        className="absolute inset-x-0 bottom-0 flex max-h-[72%] flex-col rounded-t-[22px] bg-background text-foreground shadow-2xl lg:inset-y-0 lg:left-auto lg:right-0 lg:max-h-none lg:w-[380px] lg:rounded-none lg:border-l lg:border-border"
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-label="Comments"
      >
        <div className="flex items-center justify-between border-b border-border px-4 py-3">
          <span className="text-[15px] font-bold">
            Comments{comments.length > 0 ? ` · ${compactCount(comments.length)}` : ""}
          </span>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close comments"
            className="flex h-8 w-8 items-center justify-center rounded-full transition-colors hover:bg-secondary"
          >
            <X className="h-[18px] w-[18px]" />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto px-4 py-3 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
          {caption && (
            <div className="mb-3 flex gap-2.5 border-b border-border pb-3">
              <Avatar name={authorUsername} size={32} />
              <p className="text-[13px] leading-snug">
                <span className="font-bold">{authorUsername}</span>{" "}
                <span className="text-foreground/90">{caption}</span>
              </p>
            </div>
          )}
          {commentsQuery.isLoading ? (
            <div className="space-y-3">
              {[0, 1, 2].map((i) => (
                <div key={i} className="flex gap-2.5">
                  <div className="h-8 w-8 rounded-full bg-secondary" />
                  <div className="flex-1 space-y-1.5 pt-1">
                    <div className="h-2.5 w-24 rounded bg-secondary" />
                    <div className="h-2.5 w-3/4 rounded bg-secondary" />
                  </div>
                </div>
              ))}
            </div>
          ) : comments.length === 0 ? (
            <div className="py-10 text-center">
              <p className="text-[15px] font-bold">No comments yet</p>
              <p className="mt-1 text-[13px] text-muted-foreground">Start the conversation.</p>
            </div>
          ) : (
            <ul className="space-y-3.5">
              {comments.map((c) => (
                <li key={c.id} className="flex gap-2.5">
                  <Link to={`/u/${c.username}`} className="shrink-0">
                    <Avatar
                      url={profiles[c.user_id]?.profile_image_url}
                      name={c.username}
                      size={32}
                    />
                  </Link>
                  <div className="min-w-0 flex-1">
                    <p className="text-[13px] leading-snug">
                      <Link to={`/u/${c.username}`} className="font-bold">
                        {c.username}
                      </Link>{" "}
                      <span className="text-foreground/90">
                        <MentionText text={c.body} />
                      </span>
                    </p>
                    <span className="mt-0.5 block text-[11px] text-muted-foreground">
                      {timeAgo(c.created_at ?? new Date().toISOString())}
                    </span>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </div>

        <form
          className="flex items-center gap-2 border-t border-border px-3 py-2.5"
          style={{ paddingBottom: "calc(env(safe-area-inset-bottom, 0px) + 10px)" }}
          onSubmit={(e) => {
            e.preventDefault();
            submit();
          }}
        >
          <Avatar name={meUsername} size={30} />
          <input
            ref={inputRef}
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            placeholder={meId ? "Add a comment…" : "Sign in to comment"}
            disabled={!meId}
            maxLength={600}
            className="h-10 min-w-0 flex-1 rounded-full border border-border bg-secondary/60 px-4 text-[14px] outline-none placeholder:text-muted-foreground focus:border-foreground/40"
          />
          <button
            type="submit"
            disabled={!draft.trim() || !meId || sendMutation.isPending}
            className="h-10 rounded-full bg-foreground px-4 text-[13px] font-bold text-background transition-opacity disabled:opacity-30"
          >
            Post
          </button>
        </form>
      </div>
    </div>
  );
}

/**
 * A full-screen sponsored slide between reels — the "reels" ad placement.
 * Impressions count once the slide is actually centered; the CTA tracks
 * clicks and opens the advertiser's destination.
 */
function SponsoredReelSlide({
  ad,
  isActive,
  muted,
}: {
  ad: ActiveAd;
  isActive: boolean;
  muted: boolean;
}) {
  const videoRef = useRef<HTMLVideoElement>(null);

  useEffect(() => {
    if (isActive && ad.id) trackAdImpression(ad.id);
  }, [isActive, ad.id]);

  useEffect(() => {
    const v = videoRef.current;
    if (!v) return;
    if (isActive) {
      void v.play().catch(() => {});
    } else {
      v.pause();
    }
  }, [isActive]);

  const destination =
    externalUrl(ad.cta_url) ?? externalUrl(ad.business_website);
  const isVideo = ad.media_type === "video" && !!ad.video_url;

  return (
    <div className="relative h-full w-full snap-start [scroll-snap-stop:always] overflow-hidden bg-black">
      <div className="absolute inset-0 flex items-center justify-center">
        {isVideo ? (
          <video
            ref={videoRef}
            src={ad.video_url ?? undefined}
            poster={ad.image_url ?? undefined}
            loop
            muted={muted}
            playsInline
            className="h-full w-full object-cover"
          />
        ) : ad.image_url ? (
          <img
            src={ad.image_url}
            alt={ad.headline}
            className="h-full w-full object-cover"
            draggable={false}
          />
        ) : (
          <div className="h-full w-full bg-gradient-to-b from-[#20224a] via-[#141530] to-black" />
        )}
      </div>

      <div className="pointer-events-none absolute inset-0 bg-gradient-to-b from-black/40 via-transparent to-black/75" />

      {/* "Ad" — always visible in the top right corner of the slide */}
      <span className="absolute right-4 top-[calc(env(safe-area-inset-top,0px)+16px)] z-20 rounded-md bg-black/50 px-2 py-0.5 text-[10px] font-black uppercase tracking-wide text-white/90 backdrop-blur-sm">
        Ad
      </span>

      <div className="absolute bottom-24 left-4 right-4 z-10 space-y-2.5">
        <div className="flex items-center gap-2.5">
          {ad.business_logo_url ? (
            <img
              src={ad.business_logo_url}
              alt={ad.business_name}
              className="h-9 w-9 rounded-full border border-white/40 object-cover"
            />
          ) : (
            <span className="flex h-9 w-9 items-center justify-center rounded-full bg-white/15 text-[13px] font-black text-white">
              {ad.business_name.slice(0, 1).toUpperCase()}
            </span>
          )}
          <div className="min-w-0">
            <p className="truncate text-[15px] font-bold text-white drop-shadow">
              {ad.business_name}
            </p>
            <p className="text-[10.5px] font-bold uppercase tracking-wide text-white/60">
              Sponsored
            </p>
          </div>
        </div>
        <p className="text-[16px] font-extrabold leading-snug text-white drop-shadow">
          {ad.headline}
        </p>
        {ad.body && (
          <p className="line-clamp-2 text-[13px] leading-snug text-white/80">
            {ad.body}
          </p>
        )}
        <button
          onClick={() => {
            trackAdClick(ad.id);
            if (destination)
              window.open(destination, "_blank", "noopener,noreferrer");
          }}
          className="flex w-full items-center justify-center gap-1.5 rounded-full bg-white py-3 text-[14px] font-extrabold text-black transition-transform active:scale-[0.98]"
        >
          {ad.cta_label || "Learn more"}
          <ExternalLink className="h-4 w-4" />
        </button>
      </div>
    </div>
  );
}

/**
 * One-line text that scrolls sideways when it doesn't fit — the TikTok sound
 * line. Sits still when it fits; loops seamlessly (copy + gap) when it doesn't.
 */
function SoundMarquee({ text }: { text: string }) {
  const wrapRef = useRef<HTMLSpanElement>(null);
  const textRef = useRef<HTMLSpanElement>(null);
  const singleWidth = useRef<number>(0);
  const [overflow, setOverflow] = useState<boolean>(false);
  const [distance, setDistance] = useState<number>(0);

  useEffect(() => {
    const w = wrapRef.current;
    const t = textRef.current;
    if (!w || !t) return;
    // Measure the single copy once (before the duplicate renders).
    if (!overflow) singleWidth.current = t.scrollWidth;
    const measure = (): void => {
      const single = singleWidth.current;
      const over = single > w.clientWidth + 2;
      setOverflow(over);
      setDistance(single + 36);
    };
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(w);
    return () => ro.disconnect();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [text]);

  const style: React.CSSProperties | undefined = overflow
    ? ({
        "--marquee-distance": `-${distance}px`,
        animationDuration: `${Math.max(4, distance / 26 + 1.2)}s`,
      } as React.CSSProperties)
    : undefined;

  return (
    <span ref={wrapRef} className="block max-w-[200px] overflow-hidden whitespace-nowrap">
      <span ref={textRef} className={cn("inline-block", overflow && "animate-marquee")} style={style}>
        {text}
        {overflow && <span className="inline-block w-9" />}
        {overflow && text}
      </span>
    </span>
  );
}

/** Thin progress bar that tracks the active video's playback position. */
function VideoProgress({
  videoRef,
  isActive,
}: {
  videoRef: React.RefObject<HTMLVideoElement>;
  isActive: boolean;
}) {
  const [progress, setProgress] = useState<number>(0);

  useEffect(() => {
    const v = videoRef.current;
    if (!v || !isActive) return;
    const handler = (): void => {
      if (v.duration > 0) {
        setProgress((v.currentTime / v.duration) * 100);
      }
    };
    v.addEventListener("timeupdate", handler);
    return () => v.removeEventListener("timeupdate", handler);
  }, [videoRef, isActive]);

  return (
    <div className="absolute bottom-20 left-0 right-0 z-10 h-0.5 bg-white/20">
      <div
        className="h-full bg-white transition-[width] duration-100 ease-linear"
        style={{ width: `${progress}%` }}
      />
    </div>
  );
}
