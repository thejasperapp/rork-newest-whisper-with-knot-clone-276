import { useCallback, useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { useNavigate } from "react-router-dom";
import {
  X,
  ChevronLeft,
  ChevronRight,
  MoreHorizontal,
  Trash2,
  Flag,
  Eye,
  Loader2,
  Check,
  Bookmark,
  Plus,
  Heart,
  Send,
} from "lucide-react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";

import { Avatar } from "@/components/Avatar";
import { StorySticker } from "@/components/StorySticker";
import { MarqueeText, EqualizerBars } from "@/components/MusicMarquee";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";
import { timeAgo } from "@/lib/format";
import {
  decodeStoryMetadata,
  isTappableSticker,
  type StorySticker as StorySticonType,
} from "@/lib/storyStickers";
import {
  recordStoryResponse,
  fetchPollTally,
  recordStoryView,
  fetchStoryViewers,
} from "@/lib/storyResponses";
import { deleteStory, reportStory, sendMessage } from "@/lib/api";
import { markStorySeen } from "@/lib/storySeen";
import {
  fetchHighlights,
  fetchMyHighlightCoverage,
  addStoryToHighlight,
  createHighlightWithStory,
  type StoryHighlight,
} from "@/lib/highlights";
import type { WhisperStory } from "@/lib/types";

/** Photo stories keep Instagram's 7-second beat; video stories run the clip's real length (3–60s). */
const DURATION = 7000;
const MIN_VIDEO_MS = 3000;
const MAX_VIDEO_MS = 60_000;

export interface StoryGroup {
  userId: string;
  username: string;
  avatarUrl: string | null;
  stories: WhisperStory[];
}

interface Me {
  id?: string;
  username?: string;
  avatarUrl?: string | null;
}

interface EditingState {
  sticker: StorySticonType;
  pollIndex: number | null;
  sliderValue: number | null;
  questionText: string;
  sending: boolean;
  sent: boolean;
  tally: Record<string, number> | null;
  votedIndex: number | null;
}

const REPORT_REASONS = [
  "Spam",
  "Nudity or sexual content",
  "Hate speech or symbols",
  "Violence or dangerous acts",
  "Bullying or harassment",
  "False information",
];

/** The eight Instagram quick reactions, kit order. */
const QUICK_REACTIONS = ["❤️", "🙌", "😂", "😮", "😢", "🔥", "🎉", "💯"];

export function StoryViewer({
  groups,
  startGroup,
  onClose,
  me,
}: {
  groups: StoryGroup[];
  startGroup: number;
  onClose: () => void;
  me: Me;
}) {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [groupIdx, setGroupIdx] = useState<number>(startGroup);
  const [storyIdx, setStoryIdx] = useState<number>(0);
  const [progress, setProgress] = useState<number>(0);
  /** Video stories: the clip's real length (clamped 3–60s) drives the segment. */
  const [videoDurationMs, setVideoDurationMs] = useState<number>(15_000);
  const [paused, setPaused] = useState<boolean>(false);
  const [readyID, setReadyID] = useState<string | null>(null);
  const [failedID, setFailedID] = useState<string | null>(null);
  const [retryMedia, setRetryMedia] = useState<number>(0);
  const [visible, setVisible] = useState<boolean>(() => !document.hidden);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const stageRef = useRef<HTMLDivElement | null>(null);
  const [stageWidth, setStageWidth] = useState<number>(390);
  useEffect(() => { const stage = stageRef.current; if (!stage) return; const update = (): void => setStageWidth(stage.clientWidth); update(); const observer = new ResizeObserver(update); observer.observe(stage); return () => observer.disconnect(); }, [groupIdx]);
  useEffect(() => { const update = (): void => setVisible(!document.hidden); document.addEventListener("visibilitychange", update); return () => document.removeEventListener("visibilitychange", update); }, []);
  const [editing, setEditing] = useState<EditingState | null>(null);
  const [showViewers, setShowViewers] = useState<boolean>(false);
  const [showHighlightSave, setShowHighlightSave] = useState<boolean>(false);
  // Instagram reply bar — "Send message", heart, quick reactions, burst.
  const [replyText, setReplyText] = useState<string>("");
  const [replyFocused, setReplyFocused] = useState<boolean>(false);
  const [sendingReply, setSendingReply] = useState<boolean>(false);
  const [likedIds, setLikedIds] = useState<Set<string>>(new Set());
  const [burst, setBurst] = useState<{ emoji: string; tick: number } | null>(null);
  const audioRef = useRef<HTMLAudioElement | null>(null);
  // Instagram stage gestures — drag down to close (the card follows the
  // finger), swipe sideways between authors, hold to pause, tap to advance.
  const [drag, setDrag] = useState<{ axis: "v" | "h" | null; dx: number; dy: number }>({
    axis: null,
    dx: 0,
    dy: 0,
  });
  const [closing, setClosing] = useState<boolean>(false);
  const [slideDir, setSlideDir] = useState<"left" | "right" | null>(null);
  const gRef = useRef<{
    active: boolean;
    id: number;
    sx: number;
    sy: number;
    st: number;
    axis: "v" | "h" | null;
    held: boolean;
    holdTimer: number;
    dx: number;
    dy: number;
  }>({ active: false, id: 0, sx: 0, sy: 0, st: 0, axis: null, held: false, holdTimer: 0, dx: 0, dy: 0 });

  const group = groups[groupIdx];
  const story = group?.stories[storyIdx];
  const isMine = !!me.id && group?.userId.toLowerCase() === me.id.toLowerCase();

  const metadata = story ? decodeStoryMetadata(story.metadata) : { stickers: [] };
  const music = story?.music_url
    ? {
        url: story.music_url,
        title: story.music_title ?? "",
        artist: story.music_artist ?? "",
      }
    : null;

  /** Animated dismissal — the card drops away while the backdrop fades. */
  const animateClose = useCallback((): void => {
    audioRef.current?.pause();
    setClosing(true);
    window.setTimeout(() => onClose(), 230);
  }, [onClose]);

  const goNext = useCallback((): void => {
    setEditing(null);
    setProgress(0);
    if (!group) return;
    if (storyIdx < group.stories.length - 1) {
      setStoryIdx((i) => i + 1);
    } else if (groupIdx < groups.length - 1) {
      setSlideDir("left");
      setGroupIdx((g) => g + 1);
      setStoryIdx(0);
    } else {
      animateClose();
    }
  }, [group, groupIdx, groups.length, storyIdx, animateClose]);

  const goPrev = (): void => {
    setEditing(null);
    setProgress(0);
    if (storyIdx > 0) {
      setStoryIdx((i) => i - 1);
    } else if (groupIdx > 0) {
      setSlideDir("right");
      setGroupIdx((g) => g - 1);
      setStoryIdx(0);
    }
  };

  /** A horizontal swipe landed — jump straight to another author. */
  const switchGroup = (idx: number, dir: "left" | "right"): void => {
    setEditing(null);
    setProgress(0);
    setSlideDir(dir);
    setGroupIdx(idx);
    setStoryIdx(0);
    setDrag({ axis: null, dx: 0, dy: 0 });
  };

  // Auto-advance timer (paused while holding or while an interaction is open).
  useEffect(() => {
    if (!story) return;
    if (paused || editing || replyFocused || closing || showViewers || showHighlightSave || !visible || readyID !== story.id || failedID === story.id || story.video_url) return;
    const started = Date.now();
    const base = progress;
    const tick = setInterval(() => {
      const elapsed = Date.now() - started;
      const next = base + elapsed / (story.video_url ? videoDurationMs : DURATION);
      if (next >= 1) {
        clearInterval(tick);
        goNext();
      } else {
        setProgress(next);
      }
    }, 50);
    return () => clearInterval(tick);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [groupIdx, storyIdx, paused, editing, replyFocused, closing, videoDurationMs, readyID, failedID, visible, showViewers, showHighlightSave]);

  const recordedViews = useRef<Set<string>>(new Set());
  // Music playback and fresh reply state per story segment.
  useEffect(() => {
    if (!story) return;
    // Local seen-state (drives the tray rings) + fresh reply state.
    setReadyID(null);
    setFailedID(null);
    setReplyText("");
    setReplyFocused(false);
    // Video stories re-measure their length from the clip's metadata.
    setVideoDurationMs(15_000);
    // Music.
    audioRef.current?.pause();
    audioRef.current = null;
    if (music?.url) {
      const audio = new Audio(music.url);
      audio.volume = 1;
      audioRef.current = audio;
    }
    return () => {
      audioRef.current?.pause();
      audioRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [story?.id]);

  // Pause/resume audio with the hold-to-pause gesture.
  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) return;
    if (paused || editing || replyFocused || closing || showViewers || showHighlightSave || !visible || readyID !== story?.id || failedID === story?.id) audio.pause();
    else audio.play().catch(() => undefined);
  }, [paused, editing, replyFocused, closing, showViewers, showHighlightSave, visible, readyID, failedID, story?.id]);

  useEffect(() => {
    if (!story || readyID !== story.id || failedID === story.id || !visible) return;
    const viewKey = `${me.id ?? "guest"}:${story.id}`;
    if (recordedViews.current.has(viewKey)) return;
    recordedViews.current.add(viewKey);
    markStorySeen(story.id);
    if (!isMine && me.id && me.username) void recordStoryView({ storyId: story.id, viewerId: me.id, viewerUsername: me.username, storyOwnerId: story.user_id });
  }, [story?.id, readyID, failedID, visible, isMine, me.id, me.username]);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    if (paused || editing || replyFocused || closing || showViewers || showHighlightSave || !visible) video.pause();
    else void video.play().catch((error: unknown) => { if (error instanceof Error && error.name === "NotAllowedError") setFailedID(story?.id ?? null); });
  }, [story?.id, paused, editing, replyFocused, closing, showViewers, showHighlightSave, visible, retryMedia]);

  // Keyboard navigation — ← → advance, Esc closes (the desktop experience).
  useEffect(() => {
    const onKey = (e: KeyboardEvent): void => {
      if (e.key === "Escape" && editing) { if (!editing.sending) cancelEditing(); return; }
      if (editing || replyFocused || closing || showViewers || showHighlightSave || !visible) return;
      if (e.key === "Escape") animateClose();
      else if (e.key === "ArrowLeft") goPrev();
      else if (e.key === "ArrowRight") goNext();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  // Preload neighbouring story images so advancing never flashes black.
  useEffect(() => {
    const urls: string[] = [];
    const g = groups[groupIdx];
    if (g) {
      const nxt = g.stories[storyIdx + 1];
      const prv = g.stories[storyIdx - 1];
      if (nxt) urls.push(nxt.image_url);
      if (prv) urls.push(prv.image_url);
    }
    const ng = groups[groupIdx + 1];
    const pg = groups[groupIdx - 1];
    if (ng?.stories[0]) urls.push(ng.stories[0].image_url);
    if (pg?.stories[0]) urls.push(pg.stories[0].image_url);
    for (const u of urls) {
      const img = new Image();
      img.src = u;
    }
  }, [groupIdx, storyIdx, groups]);

  // Which of MY story images already live in a highlight — fills the
  // bookmark so saved stories read as saved.
  const coverageQuery = useQuery({
    queryKey: ["highlight-coverage", me.id],
    queryFn: () => fetchMyHighlightCoverage(me.id!),
    enabled: !!me.id && isMine,
  });
  const savedToHighlight =
    !!story && !!coverageQuery.data?.has(story.image_url);

  // Who's seen my story — powers the Instagram "Seen by" facepile.
  const viewersQuery = useQuery({
    queryKey: ["story-viewers", story?.id],
    queryFn: () => fetchStoryViewers([story!.id]),
    enabled: !!story && isMine,
  });
  const seenBy = story ? (viewersQuery.data?.[story.id] ?? []) : [];

  if (!group || !story) return null;

  /** One pointer surface drives the whole Instagram gesture grammar. */
  const gestureBlocked =
    !!editing || replyFocused || showViewers || showHighlightSave || closing;

  const onSurfaceDown = (e: React.PointerEvent<HTMLDivElement>): void => {
    if (gestureBlocked) return;
    const g = gRef.current;
    g.active = true;
    g.id = e.pointerId;
    g.sx = e.clientX;
    g.sy = e.clientY;
    g.st = Date.now();
    g.axis = null;
    g.held = false;
    g.dx = 0;
    g.dy = 0;
    e.currentTarget.setPointerCapture(e.pointerId);
    window.clearTimeout(g.holdTimer);
    g.holdTimer = window.setTimeout(() => {
      g.held = true;
      setPaused(true);
    }, 180);
  };

  const onSurfaceMove = (e: React.PointerEvent<HTMLDivElement>): void => {
    const g = gRef.current;
    if (!g.active || e.pointerId !== g.id) return;
    const dx = e.clientX - g.sx;
    const dy = e.clientY - g.sy;
    if (!g.axis) {
      if (Math.abs(dx) < 12 && Math.abs(dy) < 12) return;
      g.axis = Math.abs(dy) > Math.abs(dx) ? "v" : "h";
      window.clearTimeout(g.holdTimer);
      setPaused(true);
    }
    g.dx = dx;
    g.dy = dy;
    if (g.axis === "v") {
      setDrag({ axis: "v", dx: 0, dy: Math.max(0, dy) });
    } else {
      const rubber =
        (groupIdx === 0 && dx > 0) || (groupIdx === groups.length - 1 && dx < 0);
      setDrag({ axis: "h", dx: rubber ? dx / 3 : dx, dy: 0 });
    }
  };

  const onSurfaceUp = (e: React.PointerEvent<HTMLDivElement>): void => {
    const g = gRef.current;
    if (!g.active || e.pointerId !== g.id) return;
    g.active = false;
    window.clearTimeout(g.holdTimer);
    const dt = Math.max(1, Date.now() - g.st);
    if (g.axis === "v") {
      if (g.dy > 130 || g.dy / dt > 0.55) {
        animateClose();
        return;
      }
      setDrag({ axis: null, dx: 0, dy: 0 });
      setPaused(false);
    } else if (g.axis === "h") {
      const commit = Math.abs(g.dx) > 72 || Math.abs(g.dx) / dt > 0.5;
      if (commit && g.dx < 0 && groupIdx < groups.length - 1) {
        switchGroup(groupIdx + 1, "left");
      } else if (commit && g.dx > 0 && groupIdx > 0) {
        switchGroup(groupIdx - 1, "right");
      } else {
        setDrag({ axis: null, dx: 0, dy: 0 });
      }
      setPaused(false);
    } else if (g.held) {
      setPaused(false);
    } else {
      const rect = e.currentTarget.getBoundingClientRect();
      const x = e.clientX - rect.left;
      setPaused(false);
      if (x < rect.width / 3) goPrev();
      else goNext();
    }
  };

  const onSurfaceCancel = (): void => {
    const g = gRef.current;
    g.active = false;
    window.clearTimeout(g.holdTimer);
    setDrag({ axis: null, dx: 0, dy: 0 });
    setPaused(false);
  };

  const backdropOpacity =
    closing ? 0 : drag.axis === "v" ? Math.max(0, 1 - drag.dy / 440) : 1;
  const cardStyle: React.CSSProperties = closing
    ? {
        transform: "translate3d(0, 105vh, 0) scale(0.92)",
        transition: "transform 230ms cubic-bezier(0.4, 0, 1, 1)",
      }
    : drag.axis === "v"
      ? {
          transform: `translate3d(0, ${drag.dy}px, 0) scale(${1 - Math.min(drag.dy, 420) / 1600})`,
          borderRadius: Math.min(28, 10 + drag.dy / 7),
          transition: "none",
        }
      : drag.axis === "h"
        ? { transform: `translate3d(${drag.dx}px, 0, 0)`, transition: "none" }
        : {
            transform: "translate3d(0, 0, 0)",
            transition:
              "transform 260ms cubic-bezier(0.32, 0.72, 0, 1), border-radius 260ms",
          };

  const beginPoll = (sticker: StorySticonType, index: number): void => {
    if (isMine) return;
    setPaused(true);
    setEditing({
      sticker,
      pollIndex: index,
      sliderValue: null,
      questionText: "",
      sending: false,
      sent: false,
      tally: null,
      votedIndex: null,
    });
  };

  const beginInteractive = (sticker: StorySticonType): void => {
    if (sticker.kind === "wave" || sticker.kind === "post") {
      // Instagram's "Watch reel" / "View post" — open the original.
      const id = (sticker.postID ?? "").toLowerCase();
      audioRef.current?.pause();
      onClose();
      navigate(sticker.kind === "wave" ? (id ? `/reels?wave=${encodeURIComponent(id)}` : "/reels") : (id ? `/?post=${encodeURIComponent(id)}` : "/"));
      return;
    }
    if (sticker.kind === "mention") {
      const handle = (sticker.label ?? "").replace(/^@/, "").trim();
      if (handle) {
        audioRef.current?.pause();
        onClose();
        navigate(`/u/${encodeURIComponent(handle)}`);
      }
      return;
    }
    if (sticker.kind === "location") {
      const label = (sticker.label ?? "").trim();
      const url =
        sticker.latitude != null && sticker.longitude != null
          ? `https://maps.google.com/?q=${sticker.latitude},${sticker.longitude}`
          : `https://maps.google.com/?q=${encodeURIComponent(label)}`;
      window.open(url, "_blank", "noopener");
      return;
    }
    if (isMine) return;
    setPaused(true);
    setEditing({
      sticker,
      pollIndex: null,
      sliderValue: sticker.kind === "slider" ? 0.5 : null,
      questionText: "",
      sending: false,
      sent: false,
      tally: null,
      votedIndex: null,
    });
  };

  const cancelEditing = (): void => {
    setEditing(null);
    setPaused(false);
  };

  const submitEditing = async (): Promise<void> => {
    if (!editing || editing.sending || !me.id || !me.username) return;
    const { sticker } = editing;
    let kind: "poll" | "slider" | "question";
    let prompt: string;
    let response: string;
    if (sticker.kind === "poll") {
      if (editing.pollIndex == null) return;
      const options = sticker.pollOptions?.length ? sticker.pollOptions : ["Yes", "No"];
      kind = "poll";
      prompt = sticker.text || "Poll";
      response = options[editing.pollIndex] ?? "";
    } else if (sticker.kind === "slider") {
      if (editing.sliderValue == null) return;
      kind = "slider";
      prompt = sticker.text || "Slider";
      response = `${Math.round(editing.sliderValue * 100)}%`;
    } else {
      const text = editing.questionText.trim();
      if (!text) return;
      kind = "question";
      prompt = sticker.text || "Ask me anything";
      response = text;
    }

    setEditing((e) => (e ? { ...e, sending: true } : e));
    try {
      await recordStoryResponse({
        storyId: story.id,
        storyOwnerId: story.user_id,
        responderId: me.id,
        responderUsername: me.username,
        kind,
        prompt,
        response,
      });
    } catch {
      toast.error("Couldn't send that — please try again.");
      setEditing((e) => (e ? { ...e, sending: false } : e));
      return;
    }

    // Poll: morph into live results before tearing down.
    if (kind === "poll") {
      const tally = await fetchPollTally(story.id, prompt);
      setEditing((e) =>
        e
          ? { ...e, sending: false, sent: true, tally, votedIndex: e.pollIndex }
          : e
      );
    } else {
      setEditing((e) => (e ? { ...e, sending: false, sent: true } : e));
    }
    setTimeout(() => cancelEditing(), 1200);
  };

  const handleDelete = async (): Promise<void> => {
    await deleteStory(story.id);
    queryClient.invalidateQueries({ queryKey: ["stories"] });
    toast("Story deleted");
    onClose();
  };

  const handleReport = async (reason: string): Promise<void> => {
    if (!me.id || !me.username) return;
    try {
      await reportStory({
        reporterId: me.id,
        reporterUsername: me.username,
        storyId: story.id,
        targetUserId: story.user_id,
        targetUsername: story.username,
        reason,
      });
      toast("Thanks — we'll review this story.");
    } catch {
      toast.error("Couldn't submit that report.");
    }
    setPaused(false);
  };

  const showBurst = (emoji: string): void => {
    setBurst((b) => ({ emoji, tick: (b?.tick ?? 0) + 1 }));
    window.setTimeout(() => {
      setBurst((b) => (b && b.emoji === emoji ? null : b));
    }, 1600);
  };

  /** DM the typed reply to the author — lands in the normal thread. */
  const sendReply = async (): Promise<void> => {
    const body = replyText.trim();
    if (!body || sendingReply || !me.id || !me.username) return;
    setSendingReply(true);
    try {
      await sendMessage(
        me.id,
        me.username,
        story.user_id,
        story.username,
        `Replied to your story: ${body}`
      );
      setReplyText("");
      setReplyFocused(false);
      showBurst("💬");
      toast("Reply sent");
    } catch {
      toast.error("Couldn't send that reply.");
    } finally {
      setSendingReply(false);
    }
  };

  /** One-tap quick reaction — DM + responses inbox + burst. */
  const sendReaction = async (emoji: string): Promise<void> => {
    if (!me.id || !me.username) return;
    setReplyFocused(false);
    showBurst(emoji);
    try {
      await sendMessage(
        me.id,
        me.username,
        story.user_id,
        story.username,
        `${emoji} Reacted to your story`
      );
      void recordStoryResponse({
        storyId: story.id,
        storyOwnerId: story.user_id,
        responderId: me.id,
        responderUsername: me.username,
        kind: "reaction",
        prompt: "Story reaction",
        response: emoji,
      }).catch(() => undefined);
    } catch {
      toast.error("Couldn't send that reaction.");
    }
  };

  /** Instagram's silent story like — no DM, lands in responses. */
  const toggleLike = (): void => {
    if (!me.id || !me.username) return;
    if (likedIds.has(story.id)) {
      setLikedIds((s) => {
        const next = new Set(s);
        next.delete(story.id);
        return next;
      });
      return;
    }
    setLikedIds((s) => new Set(s).add(story.id));
    showBurst("❤️");
    void recordStoryResponse({
      storyId: story.id,
      storyOwnerId: story.user_id,
      responderId: me.id,
      responderUsername: me.username,
      kind: "like",
      prompt: "Story like",
      response: "❤️",
    }).catch(() => undefined);
  };

  const shareStory = async (): Promise<void> => {
    try {
      if (navigator.share) {
        await navigator.share({
          title: `@${group.username} on Whisper`,
          url: story.image_url,
        });
        return;
      }
      throw new Error("no-share");
    } catch (err) {
      if (err instanceof Error && err.name === "AbortError") return;
      try {
        await navigator.clipboard.writeText(story.image_url);
        toast("Story link copied");
      } catch {
        toast.error("Couldn't share that story.");
      }
    }
  };

  // Rendered through a PORTAL to <body>: `position: fixed` positions against
  // the nearest transformed ancestor, and the feed's entrance animations
  // (translate/scale) silently re-anchored the viewer into the page flow —
  // users had to scroll to the bottom to find their story. The portal
  // guarantees the stage is glued to the real viewport, centered instantly.
  return createPortal(
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Backdrop — fades with the drag so the app shows through, IG-style. */}
      <div
        className="absolute inset-0 bg-black md:bg-black/95 md:backdrop-blur-sm"
        style={{
          opacity: backdropOpacity,
          transition: drag.axis ? "none" : "opacity 240ms ease",
        }}
      />
      <button
        onClick={goPrev}
        className="absolute left-2 z-30 hidden rounded-full bg-white/10 p-2 text-white hover:bg-white/20 md:block"
        aria-label="Previous story"
      >
        <ChevronLeft className="h-6 w-6" />
      </button>
      <button
        onClick={goNext}
        className="absolute right-2 z-30 hidden rounded-full bg-white/10 p-2 text-white hover:bg-white/20 md:block"
        aria-label="Next story"
      >
        <ChevronRight className="h-6 w-6" />
      </button>

      <div
        className="relative flex h-[100svh] w-[min(100%,calc((100svh-104px)*9/16))] max-w-[506px] flex-col justify-center overflow-hidden bg-black sm:rounded-3xl"
        style={{
          ...cardStyle,
          animation: "whisper-story-in 240ms cubic-bezier(0.32, 0.72, 0, 1)",
        }}
      >
        <div
          key={groupIdx}
          className="absolute inset-0 flex flex-col justify-center"
          style={
            slideDir
              ? {
                  animation: `whisper-story-slide-${slideDir} 260ms cubic-bezier(0.32, 0.72, 0, 1)`,
                }
              : undefined
          }
        >
        {/* MEDIA ZONE — the kit's 9:16 canvas; the toolbar sits BELOW it,
            never overlaid, exactly like the real story screen. */}
        <div ref={stageRef} data-story-stage data-story-reference-width={metadata.referenceStageWidth} className="relative aspect-[9/16] w-full shrink-0 overflow-hidden rounded-3xl">
        {story.video_url ? (
          <video
            key={`${story.id}:${retryMedia}`}
            src={story.video_url}
            poster={story.image_url}
            autoPlay
            playsInline
            muted={!!story.music_url}
            className="absolute inset-0 h-full w-full object-cover"
            ref={videoRef}
            onPlaying={() => { setReadyID(story.id); setFailedID(null); }}
            onError={() => setFailedID(story.id)}
            onTimeUpdate={e => { if (!paused && !editing && !replyFocused && !closing && visible && !showViewers && !showHighlightSave && e.currentTarget.duration > 0) { const end = Math.min(e.currentTarget.duration, MAX_VIDEO_MS / 1000); setProgress(Math.min(1, e.currentTarget.currentTime / end)); if (e.currentTarget.currentTime >= end && !e.currentTarget.ended) { e.currentTarget.pause(); goNext(); } } }}
            onEnded={() => { if (!paused && !editing && !replyFocused && !closing && visible && !showViewers && !showHighlightSave) goNext(); }}
            onLoadedMetadata={(e) => {
              const d = e.currentTarget.duration;
              if (Number.isFinite(d) && d > 0) {
                setVideoDurationMs(Math.max(MIN_VIDEO_MS, Math.min(MAX_VIDEO_MS, Math.round(d * 1000))));
              }
            }}
          />
        ) : (
          <img
            key={`${story.id}:${retryMedia}`}
            src={story.image_url}
            onLoad={() => setReadyID(story.id)}
            onError={() => setFailedID(story.id)}
            alt="Story"
            className="absolute inset-0 h-full w-full object-cover"
          />
        )}

        {/* Gesture surface — taps, hold-to-pause, drag to close or switch. */}
        <div
          className="absolute inset-0 z-0 touch-none"
          onPointerDown={onSurfaceDown}
          onPointerMove={onSurfaceMove}
          onPointerUp={onSurfaceUp}
          onPointerCancel={onSurfaceCancel}
        />

        {readyID !== story.id && failedID !== story.id && <div role="status" className="pointer-events-none absolute inset-0 z-20 flex items-center justify-center text-white"><Loader2 className="h-6 w-6 animate-spin motion-reduce:animate-none" /><span className="sr-only">Loading story</span></div>}
        {failedID === story.id && <button type="button" className="absolute left-1/2 top-1/2 z-30 min-h-12 -translate-x-1/2 -translate-y-1/2 rounded-full bg-white px-6 text-sm font-semibold text-black" onClick={() => { setFailedID(null); if (videoRef.current) { const video = videoRef.current; if (video.error) video.load(); void video.play().catch(() => setFailedID(story.id)); } else { setReadyID(null); setRetryMedia(v => v + 1); } }}>Play / retry story</button>}
        {/* Sticker layer */}
        <div className="pointer-events-none absolute inset-0 z-10">
          {metadata.stickers.map((s) => {
            const tappable = isTappableSticker(s.kind) && (!isMine || ["post", "wave", "mention", "location"].includes(s.kind));
            const isLifted = editing?.sticker.id === s.id;
            return (
              <div
                key={s.id}
                className={cn(tappable ? "pointer-events-auto" : "pointer-events-none")}
                style={{
                  position: "absolute",
                  left: `${s.x * 100}%`,
                  top: `${s.y * 100}%`,
                  transform: `translate(-50%, -50%) scale(${s.scale * (stageWidth / (metadata.referenceStageWidth ?? stageWidth))}) rotate(${s.rotation}rad)`,
                  opacity: isLifted ? 0 : 1,
                }}
              >
                <StorySticker
                  sticker={s}
                  interactive={tappable}
                  authorUsername={group.username}
                  authorAvatarUrl={group.avatarUrl}
                  onPickPoll={(idx) => beginPoll(s, idx)}
                  onTap={() => beginInteractive(s)}
                />
              </div>
            );
          })}
        </div>

        {/* Header chrome */}
        <div
          className={cn(
            "pointer-events-none absolute inset-x-0 top-0 z-10 transition-opacity",
            paused || editing ? "opacity-0" : "opacity-100"
          )}
        >
          <div className="flex gap-[3px] px-2 pt-2">
            {group.stories.map((s, i) => (
              <div key={s.id} className="h-[2px] flex-1 overflow-hidden rounded-full bg-white/35">
                <div
                  className="h-full bg-white"
                  style={{
                    width:
                      i < storyIdx ? "100%" : i === storyIdx ? `${progress * 100}%` : "0%",
                    transition: i === storyIdx ? "width 50ms linear" : undefined,
                  }}
                />
              </div>
            ))}
          </div>

          <div className="pointer-events-auto flex items-center gap-2 px-3 pt-2.5">
            <button
              onClick={() => {
                audioRef.current?.pause();
                onClose();
                navigate(`/u/${group.username}`);
              }}
              className="flex items-center gap-2"
            >
              <Avatar name={group.username} url={group.avatarUrl} size={32} />
              <span className="flex items-baseline gap-1.5 leading-tight">
                <span className="text-[13px] font-semibold text-white">{group.username}</span>
                <span className="text-[13px] text-white/70">{timeAgo(story.created_at)}</span>
              </span>
            </button>
            {music && (
              <div className="ml-1 flex max-w-[150px] items-center gap-1.5 rounded-full bg-black/35 px-2.5 py-1 text-white">
                <EqualizerBars size={11} color="#ffffff" />
                <MarqueeText
                  text={`${music.title}${music.artist ? ` — ${music.artist}` : ""}`}
                  className="max-w-[110px] text-[11px] font-medium text-white/90"
                />
              </div>
            )}
            <div className="ml-auto flex items-center gap-0.5">
              {!isMine && (
                <DropdownMenu
                  onOpenChange={(open) => {
                    setPaused(open);
                  }}
                >
                  <DropdownMenuTrigger className="rounded-full p-1.5 text-white outline-none hover:bg-white/15">
                    <MoreHorizontal className="h-5 w-5" />
                  </DropdownMenuTrigger>
                  <DropdownMenuContent align="end" className="w-52">
                    {REPORT_REASONS.map((reason) => (
                      <DropdownMenuItem key={reason} onClick={() => void handleReport(reason)}>
                        <Flag className="mr-2 h-4 w-4" />
                        {reason}
                      </DropdownMenuItem>
                    ))}
                  </DropdownMenuContent>
                </DropdownMenu>
              )}
              <button
                onClick={animateClose}
                className="rounded-full p-1 text-white outline-none hover:bg-white/15"
                aria-label="Close"
              >
                <X className="h-6 w-6" />
              </button>
            </div>
          </div>
        </div>

        {/* Caption */}
        {story.caption && !editing && !paused && (
          <p className="pointer-events-none absolute inset-x-0 bottom-5 z-10 px-6 text-center text-base font-medium text-white drop-shadow">
            {story.caption}
          </p>
        )}

        {/* Quick reactions — the media dims and the grid floats above the
            toolbar, IG-style. */}
        {!isMine && !editing && replyFocused && (
          <>
            <button
              aria-label="Close reactions"
              onClick={() => setReplyFocused(false)}
              className="absolute inset-0 z-[15] bg-black/50"
            />
            <div className="absolute inset-x-0 bottom-0 z-[16] grid grid-cols-4 gap-y-5 px-5 pb-4">
              {QUICK_REACTIONS.map((emoji) => (
                <button
                  key={emoji}
                  onPointerDown={() => void sendReaction(emoji)}
                  className="text-4xl transition-transform hover:scale-125 active:scale-95"
                  aria-label={`React ${emoji}`}
                >
                  {emoji}
                </button>
              ))}
            </div>
          </>
        )}

        {/* Floating reaction burst */}
        {burst && (
          <div key={burst.tick} className="pointer-events-none absolute inset-0 z-40">
            {[0, 1, 2, 3, 4, 5].map((i) => (
              <span
                key={i}
                className="absolute bottom-24 text-4xl"
                style={{
                  left: `${28 + ((i * 17) % 44)}%`,
                  animation: `whisper-story-burst 1.1s ease-out ${(i % 3) * 0.12}s forwards`,
                  opacity: 0,
                }}
              >
                {burst.emoji}
              </span>
            ))}
          </div>
        )}
        </div>

        {/* KIT TOOLBAR — below the media: reply bar on other people's
            stories, Activity · Create · Highlight · More on your own. */}
        <div className="relative z-20 flex min-h-[72px] shrink-0 items-center gap-3.5 bg-black px-3 pb-[env(safe-area-inset-bottom)]">
          {!isMine ? (
            <div
              className={cn(
                "flex flex-1 items-center gap-3.5 transition-opacity",
                paused && !replyFocused ? "opacity-40" : "opacity-100"
              )}
            >
              <div className="flex h-[38px] min-w-0 flex-1 items-center gap-2 rounded-full border border-white/60 px-4">
                <input
                  value={replyText}
                  onChange={(e) => setReplyText(e.target.value)}
                  onFocus={() => setReplyFocused(true)}
                  onBlur={() => window.setTimeout(() => setReplyFocused(false), 160)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") void sendReply();
                  }}
                  placeholder="Send message"
                  className="h-full min-w-0 flex-1 bg-transparent text-[13px] text-white outline-none placeholder:text-white/80"
                />
                {replyText.trim() && (
                  <button
                    onPointerDown={(e) => {
                      e.preventDefault();
                      void sendReply();
                    }}
                    className="text-[13px] font-extrabold text-white"
                  >
                    {sendingReply ? "…" : "Send"}
                  </button>
                )}
              </div>
              <button onClick={toggleLike} aria-label="Like story" className="active:scale-90">
                <Heart
                  className={cn(
                    "h-6 w-6 text-white transition-colors",
                    likedIds.has(story.id) && "fill-[#ED4956] text-[#ED4956]"
                  )}
                />
              </button>
              <button onClick={() => void shareStory()} aria-label="Share story" className="active:scale-90">
                <Send className="h-6 w-6 text-white" />
              </button>
            </div>
          ) : (
            <>
              <button
                onClick={() => {
                  setPaused(true);
                  setShowViewers(true);
                }}
                className="flex flex-col items-center gap-1 text-white"
                aria-label="Activity"
              >
                {seenBy.length > 0 ? (
                  <span className="flex -space-x-1.5">
                    {seenBy.slice(0, 3).map((v) => (
                      <span key={v.viewer_id} className="rounded-full ring-2 ring-black">
                        <Avatar name={v.viewer_username} size={22} />
                      </span>
                    ))}
                  </span>
                ) : (
                  <Eye className="h-[22px] w-[22px]" />
                )}
                <span className="text-[10px] font-medium">Activity</span>
              </button>
              <div className="ml-auto flex items-center gap-6">
                <button
                  onClick={() => {
                    animateClose();
                    navigate("/compose?mode=story");
                  }}
                  className="flex flex-col items-center gap-1 text-white"
                >
                  <Plus className="h-6 w-6" />
                  <span className="text-[10px] font-medium">Create</span>
                </button>
                <button
                  onClick={() => {
                    setPaused(true);
                    setShowHighlightSave(true);
                  }}
                  className="flex flex-col items-center gap-1 text-white"
                >
                  <Bookmark className={cn("h-6 w-6", savedToHighlight && "fill-white")} />
                  <span className="text-[10px] font-medium">Highlight</span>
                </button>
                <DropdownMenu onOpenChange={(open) => setPaused(open)}>
                  <DropdownMenuTrigger className="flex flex-col items-center gap-1 text-white outline-none">
                    <MoreHorizontal className="h-6 w-6" />
                    <span className="text-[10px] font-medium">More</span>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent align="end" className="w-52">
                    <DropdownMenuItem
                      className="text-destructive focus:text-destructive"
                      onClick={() => void handleDelete()}
                    >
                      <Trash2 className="mr-2 h-4 w-4" />
                      Delete story
                    </DropdownMenuItem>
                  </DropdownMenuContent>
                </DropdownMenu>
              </div>
            </>
          )}
        </div>

        {/* Lifted interaction overlay */}
        {editing && (
          <div
            className="absolute inset-0 z-30 flex flex-col items-center justify-center gap-5 bg-black/40 backdrop-blur-md"
            onClick={(e) => {
              if (e.target === e.currentTarget && !editing.sending) cancelEditing();
            }}
          >
            <div style={{ transform: "scale(1.12)" }}>
              <StorySticker
                sticker={editing.sticker}
                interactive
                authorUsername={group.username}
                authorAvatarUrl={group.avatarUrl}
                pollTally={editing.tally}
                votedIndex={editing.votedIndex}
                pendingPollIndex={editing.pollIndex}
                onPickPoll={(idx) =>
                  setEditing((ed) => (ed ? { ...ed, pollIndex: idx } : ed))
                }
                pendingSliderValue={editing.sliderValue}
                onSlide={(v) =>
                  setEditing((ed) => (ed ? { ...ed, sliderValue: v } : ed))
                }
                editableQuestion={editing.sticker.kind === "question"}
                questionText={editing.questionText}
                onChangeQuestion={(v) =>
                  setEditing((ed) => (ed ? { ...ed, questionText: v } : ed))
                }
              />
            </div>
            {!editing.tally && (
              <button
                onClick={() => void submitEditing()}
                disabled={editing.sending || editing.sent || !hasChoice(editing)}
                className={cn(
                  "flex items-center gap-2 rounded-full px-7 py-2.5 text-[15px] font-extrabold text-white shadow-lg transition-colors",
                  editing.sent ? "bg-green-500" : "bg-black",
                  !hasChoice(editing) && !editing.sent ? "opacity-50" : ""
                )}
              >
                {editing.sending ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : editing.sent ? (
                  <Check className="h-4 w-4" />
                ) : null}
                {editing.sent ? "Sent" : editing.sending ? "Sending…" : "Send"}
              </button>
            )}
          </div>
        )}

        {/* Viewers sheet */}
        {showViewers && (
          <ViewersSheet
            storyId={story.id}
            onClose={() => {
              setShowViewers(false);
              setPaused(false);
            }}
          />
        )}

        {/* Save-to-Highlights sheet (own stories) */}
        {showHighlightSave && me.id && (
          <HighlightQuickSave
            story={story}
            userId={me.id}
            onClose={() => {
              setShowHighlightSave(false);
              setPaused(false);
            }}
          />
        )}
        </div>
      </div>
    </div>,
    document.body
  );
}

function hasChoice(e: EditingState): boolean {
  if (e.sticker.kind === "poll") return e.pollIndex != null;
  if (e.sticker.kind === "slider") return e.sliderValue != null;
  if (e.sticker.kind === "question") return e.questionText.trim().length > 0;
  return false;
}

/** Quick "Save to Highlights" bottom sheet — lists every album with live
 *  saved-state, adds the current story with one tap, and creates a brand-new
 *  highlight inline so the flow works before any album exists. */
function HighlightQuickSave({
  story,
  userId,
  onClose,
}: {
  story: WhisperStory;
  userId: string;
  onClose: () => void;
}) {
  const queryClient = useQueryClient();
  const [title, setTitle] = useState<string>("");
  const [busyId, setBusyId] = useState<string | null>(null);
  const [savedIds, setSavedIds] = useState<Set<string>>(new Set());

  const albumsQuery = useQuery({
    queryKey: ["highlights", userId],
    queryFn: () => fetchHighlights(userId),
  });
  const albums = albumsQuery.data ?? [];

  const payload = {
    image_url: story.image_url,
    caption: story.caption,
    music_title: story.music_title,
    music_artist: story.music_artist,
    metadata: story.metadata,
    music_url: story.music_url,
    music_artwork: story.music_artwork,
  };

  const invalidate = (): void => {
    void queryClient.invalidateQueries({ queryKey: ["highlight-coverage", userId] });
    void queryClient.invalidateQueries({ queryKey: ["highlights", userId] });
  };

  const saveTo = async (album: StoryHighlight): Promise<void> => {
    if (busyId) return;
    setBusyId(album.id);
    try {
      await addStoryToHighlight(album.id, userId, payload);
      setSavedIds((s) => new Set(s).add(album.id));
      toast(`Saved to “${album.title}”`);
      invalidate();
    } catch {
      toast.error("Couldn't save to that highlight.");
    } finally {
      setBusyId(null);
    }
  };

  const create = async (): Promise<void> => {
    const trimmed = title.trim();
    if (!trimmed || busyId) return;
    setBusyId("create");
    try {
      const album = await createHighlightWithStory(userId, trimmed, payload);
      setSavedIds((s) => new Set(s).add(album.id));
      setTitle("");
      toast(`“${album.title}” created`);
      invalidate();
      void albumsQuery.refetch();
    } catch {
      toast.error("Couldn't create that highlight.");
    } finally {
      setBusyId(null);
    }
  };

  return (
    <div className="absolute inset-0 z-40 flex flex-col justify-end" onClick={onClose}>
      <div className="absolute inset-0 bg-black/40" />
      <div
        className="relative max-h-[75%] overflow-y-auto rounded-t-2xl bg-background p-4"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mx-auto mb-3 h-1 w-10 rounded-full bg-muted-foreground/30" />
        <div className="mb-1 flex items-center gap-2">
          <Bookmark className="h-4 w-4" />
          <h3 className="font-display text-base font-bold">Save to Highlights</h3>
        </div>
        <p className="mb-3 text-xs text-muted-foreground">
          Keeps this story on your profile after it expires.
        </p>

        {/* Inline creation — works with zero albums. */}
        <div className="mb-3 flex items-center gap-2 rounded-2xl border border-border bg-card p-2">
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") void create();
            }}
            placeholder="New highlight name…"
            maxLength={40}
            className="h-9 flex-1 bg-transparent px-2 text-sm outline-none placeholder:text-muted-foreground"
          />
          <button
            onClick={() => void create()}
            disabled={!title.trim() || busyId !== null}
            className="flex h-8 items-center gap-1 rounded-full bg-foreground px-3.5 text-xs font-bold text-background disabled:opacity-40"
          >
            {busyId === "create" ? (
              <Loader2 className="h-3.5 w-3.5 animate-spin" />
            ) : (
              <Plus className="h-3.5 w-3.5" />
            )}
            Create
          </button>
        </div>

        {albumsQuery.isLoading ? (
          <p className="py-6 text-center text-sm text-muted-foreground">Loading…</p>
        ) : albums.length === 0 ? (
          <p className="py-5 text-center text-sm text-muted-foreground">
            No highlights yet — name one above and this story becomes its cover.
          </p>
        ) : (
          <div className="space-y-1.5">
            {albums.map((album) => {
              const saved = savedIds.has(album.id);
              return (
                <div
                  key={album.id}
                  className="flex items-center gap-3 rounded-2xl border border-border bg-card px-3 py-2"
                >
                  <span className="flex h-10 w-10 shrink-0 items-center justify-center overflow-hidden rounded-full border border-border bg-secondary">
                    {album.cover_url ? (
                      <img
                        src={album.cover_url}
                        alt=""
                        className="h-full w-full object-cover"
                      />
                    ) : (
                      <Bookmark className="h-4 w-4 text-muted-foreground" />
                    )}
                  </span>
                  <span className="min-w-0 flex-1 truncate text-sm font-semibold">
                    {album.title}
                  </span>
                  {saved ? (
                    <span className="flex items-center gap-1 text-xs font-bold text-emerald-500">
                      <Check className="h-4 w-4" />
                      Saved
                    </span>
                  ) : (
                    <button
                      onClick={() => void saveTo(album)}
                      disabled={busyId !== null}
                      className="flex h-8 items-center rounded-full bg-foreground px-4 text-xs font-bold text-background disabled:opacity-40"
                    >
                      {busyId === album.id ? (
                        <Loader2 className="h-3.5 w-3.5 animate-spin" />
                      ) : (
                        "Add"
                      )}
                    </button>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}

function ViewersSheet({ storyId, onClose }: { storyId: string; onClose: () => void }) {
  const viewersQuery = useQuery({
    queryKey: ["story-viewers", storyId],
    queryFn: () => fetchStoryViewers([storyId]),
  });
  const viewers = viewersQuery.data?.[storyId] ?? [];

  return (
    <div className="absolute inset-0 z-40 flex flex-col justify-end" onClick={onClose}>
      <div className="absolute inset-0 bg-black/40" />
      <div
        className="relative max-h-[70%] overflow-y-auto rounded-t-2xl bg-background p-4"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mx-auto mb-3 h-1 w-10 rounded-full bg-muted-foreground/30" />
        <h3 className="mb-3 flex items-center gap-2 font-display text-base font-bold">
          <Eye className="h-4 w-4" />
          {viewers.length} {viewers.length === 1 ? "view" : "views"}
        </h3>
        {viewersQuery.isLoading ? (
          <p className="py-6 text-center text-sm text-muted-foreground">Loading…</p>
        ) : viewers.length === 0 ? (
          <p className="py-6 text-center text-sm text-muted-foreground">
            No views yet.
          </p>
        ) : (
          <div className="space-y-1">
            {viewers.map((v) => (
              <div key={v.viewer_id} className="flex items-center gap-2.5 py-1.5">
                <Avatar name={v.viewer_username} size={36} />
                <span className="text-sm font-semibold">{v.viewer_username}</span>
                <span className="ml-auto text-xs text-muted-foreground">
                  {timeAgo(v.created_at)}
                </span>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
