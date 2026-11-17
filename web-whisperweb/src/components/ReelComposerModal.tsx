import { memo, useCallback, useEffect, useMemo, useRef, useState } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import {
  X,
  Smile,
  Music,
  Loader2,
  Upload,
  RefreshCw,
  Hash,
  AtSign,
  Check,
  Play,
  Pause,
  Volume2,
  VolumeX,
  ChevronRight,
} from "lucide-react";
import { toast } from "sonner";

import { Avatar } from "@/components/Avatar";
import { MusicPickerSheet } from "@/components/MusicPickerSheet";
import { WavesTabGlyph } from "@/components/WavesTabGlyph";
import { cn } from "@/lib/utils";
import { createReel, uploadMedia } from "@/lib/api";
import { useAuth } from "@/hooks/useAuth";
import { WHISPER_BRAND_GRADIENT } from "@/lib/brand";
import { encodePostMeta, hasMeta, type PostMeta, type PostMusic } from "@/lib/postMeta";

const REEL_EMOJIS = [
  "🔥", "💪", "🏃", "🏋️", "🥗", "✨", "👏", "🙌",
  "💯", "❤️", "👀", "🎯", "🚀", "⚡️", "🏆", "🥳",
];

const CAPTION_MAX = 2200;
const COVER_FRAMES = 8;

const VIDEO_RE = /^video\//i;

/**
 * Pull `count` evenly spaced frames out of a local video as small JPEG data
 * URLs — the cover strip. Resolves to an empty list when the browser can't
 * decode the file (HEVC .mov in Chrome, for example) so the composer can say
 * so instead of spinning.
 */
async function extractFrames(url: string, count: number): Promise<{ frames: string[]; duration: number }> {
  return new Promise((resolve) => {
    const video = document.createElement("video");
    video.muted = true;
    video.playsInline = true;
    video.preload = "auto";
    video.src = url;
    const frames: string[] = [];
    let settled = false;
    const finish = (duration: number): void => {
      if (settled) return;
      settled = true;
      video.removeAttribute("src");
      video.load();
      resolve({ frames, duration });
    };
    const timeout = window.setTimeout(() => finish(Number.isFinite(video.duration) ? video.duration : 0), 20_000);
    video.onerror = () => {
      window.clearTimeout(timeout);
      finish(0);
    };
    video.onloadedmetadata = () => {
      const duration = Number.isFinite(video.duration) ? video.duration : 0;
      if (!duration || !video.videoWidth) {
        window.clearTimeout(timeout);
        finish(duration);
        return;
      }
      const canvas = document.createElement("canvas");
      const scale = 200 / Math.max(1, video.videoWidth);
      canvas.width = Math.max(1, Math.round(video.videoWidth * scale));
      canvas.height = Math.max(1, Math.round(video.videoHeight * scale));
      const ctx = canvas.getContext("2d");
      if (!ctx) {
        window.clearTimeout(timeout);
        finish(duration);
        return;
      }
      let i = 0;
      const step = (): void => {
        if (i >= count) {
          window.clearTimeout(timeout);
          finish(duration);
          return;
        }
        // Skip the very first/last instants — they're often black.
        const t = Math.min(duration - 0.05, Math.max(0.05, ((i + 0.5) / count) * duration));
        video.currentTime = t;
      };
      video.onseeked = () => {
        try {
          ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
          frames.push(canvas.toDataURL("image/jpeg", 0.72));
        } catch {
          // A tainted or undecodable frame — keep going.
        }
        i += 1;
        step();
      };
      step();
    };
  });
}

/** Render one frame at `time` as an upload-ready JPEG (720px wide max). */
async function captureFrameBlob(url: string, time: number): Promise<Blob | null> {
  return new Promise((resolve) => {
    const video = document.createElement("video");
    video.muted = true;
    video.playsInline = true;
    video.preload = "auto";
    video.src = url;
    let settled = false;
    const done = (blob: Blob | null): void => {
      if (settled) return;
      settled = true;
      video.removeAttribute("src");
      video.load();
      resolve(blob);
    };
    const timeout = window.setTimeout(() => done(null), 15_000);
    video.onerror = () => {
      window.clearTimeout(timeout);
      done(null);
    };
    video.onloadedmetadata = () => {
      video.currentTime = Math.min(Math.max(0.05, time), Math.max(0.05, (video.duration || 1) - 0.05));
    };
    video.onseeked = () => {
      window.clearTimeout(timeout);
      const canvas = document.createElement("canvas");
      const scale = Math.min(1, 720 / Math.max(1, video.videoWidth));
      canvas.width = Math.max(1, Math.round(video.videoWidth * scale));
      canvas.height = Math.max(1, Math.round(video.videoHeight * scale));
      const ctx = canvas.getContext("2d");
      if (!ctx) {
        done(null);
        return;
      }
      try {
        ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
        canvas.toBlob((b) => done(b), "image/jpeg", 0.86);
      } catch {
        done(null);
      }
    };
  });
}

function formatClock(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds <= 0) return "0:00";
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${String(s).padStart(2, "0")}`;
}

function ReelComposerModalBase({
  open,
  onOpenChange,
  initialMusic = null,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /**
   * "Use this sound" from a sound page — the composer opens with the sound
   * already attached (a catalog track or another wave's original sound).
   */
  initialMusic?: PostMusic | null;
}) {
  const { user, profile } = useAuth();
  const queryClient = useQueryClient();
  const fileRef = useRef<HTMLInputElement>(null);
  const previewRef = useRef<HTMLVideoElement>(null);
  const captionRef = useRef<HTMLTextAreaElement>(null);

  const [file, setFile] = useState<File | null>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [isVideo, setIsVideo] = useState<boolean>(true);
  const [duration, setDuration] = useState<number>(0);
  const [frames, setFrames] = useState<string[]>([]);
  const [framesState, setFramesState] = useState<"idle" | "busy" | "failed">("idle");
  const [coverIndex, setCoverIndex] = useState<number>(0);
  const [caption, setCaption] = useState<string>("");
  const [showEmoji, setShowEmoji] = useState<boolean>(false);
  const [showMusic, setShowMusic] = useState<boolean>(false);
  const [music, setMusic] = useState<PostMusic | null>(null);
  const [commentsOff, setCommentsOff] = useState<boolean>(false);
  const [hideCounts, setHideCounts] = useState<boolean>(false);
  // Instagram's "Also share to feed" — on by default like IG; the wave then
  // rides the ranked feed as a reel-in-feed card (still a wave everywhere else).
  const [shareToFeed, setShareToFeed] = useState<boolean>(true);
  const [dragOver, setDragOver] = useState<boolean>(false);
  const [previewPlaying, setPreviewPlaying] = useState<boolean>(true);
  const [previewMuted, setPreviewMuted] = useState<boolean>(true);
  const [progress, setProgress] = useState<string | null>(null);

  // Attach the incoming sound each time the composer opens with one.
  useEffect(() => {
    if (open && initialMusic) setMusic(initialMusic);
  }, [open, initialMusic]);

  const username = profile?.username ?? "you";

  const revokePreview = useCallback((): void => {
    if (previewUrl) URL.revokeObjectURL(previewUrl);
  }, [previewUrl]);

  const reset = (): void => {
    revokePreview();
    setFile(null);
    setPreviewUrl(null);
    setIsVideo(true);
    setDuration(0);
    setFrames([]);
    setFramesState("idle");
    setCoverIndex(0);
    setCaption("");
    setShowEmoji(false);
    setShowMusic(false);
    setMusic(null);
    setCommentsOff(false);
    setHideCounts(false);
    setProgress(null);
    setPreviewPlaying(true);
  };

  const close = (): void => {
    reset();
    onOpenChange(false);
  };

  const generateFrames = useCallback(async (url: string): Promise<void> => {
    setFramesState("busy");
    setFrames([]);
    const { frames: out, duration: d } = await extractFrames(url, COVER_FRAMES);
    if (d > 0) setDuration(d);
    if (out.length === 0) {
      setFramesState("failed");
      return;
    }
    setFrames(out);
    setCoverIndex(0);
    setFramesState("idle");
  }, []);

  const adopt = (picked: File): void => {
    revokePreview();
    const url = URL.createObjectURL(picked);
    const video = VIDEO_RE.test(picked.type) || /\.(mp4|mov|webm|m4v)$/i.test(picked.name);
    setFile(picked);
    setPreviewUrl(url);
    setIsVideo(video);
    setFrames([]);
    setCoverIndex(0);
    setDuration(0);
    setPreviewPlaying(true);
    if (video) void generateFrames(url);
    else setFramesState("idle");
  };

  const handlePick = (e: React.ChangeEvent<HTMLInputElement>): void => {
    const picked = e.target.files?.[0];
    e.target.value = "";
    if (!picked) return;
    adopt(picked);
  };

  const onDrop = (e: React.DragEvent<HTMLDivElement>): void => {
    e.preventDefault();
    setDragOver(false);
    const dropped = Array.from(e.dataTransfer.files).find(
      (f) => VIDEO_RE.test(f.type) || /^image\//i.test(f.type)
    );
    if (dropped) adopt(dropped);
  };

  // Keep the preview's play/mute state honest.
  useEffect(() => {
    const v = previewRef.current;
    if (!v) return;
    v.muted = previewMuted;
    if (previewPlaying) void v.play().catch(() => setPreviewPlaying(false));
    else v.pause();
  }, [previewPlaying, previewMuted, previewUrl]);

  const coverTime = useMemo(() => {
    if (!duration || frames.length === 0) return 0.1;
    return ((coverIndex + 0.5) / frames.length) * duration;
  }, [coverIndex, duration, frames.length]);

  const publish = useMutation({
    mutationFn: async (): Promise<void> => {
      if (!user || !profile) throw new Error("Set up your profile first.");
      if (!file || !previewUrl) throw new Error("Pick a video for your wave.");
      setProgress(isVideo ? "Uploading your video…" : "Uploading your photo…");
      const mediaUrl = await uploadMedia(file, user.id);

      let coverUrl: string | null = null;
      if (isVideo) {
        setProgress("Saving your cover…");
        const blob = await captureFrameBlob(previewUrl, coverTime).catch(() => null);
        if (blob) {
          const coverFile = new File([blob], "cover.jpg", { type: "image/jpeg" });
          coverUrl = await uploadMedia(coverFile, user.id).catch(() => null);
        }
      }

      setProgress("Posting…");
      // The sound, the cover, and the toggles ride the shared caption meta
      // wire (the same field iOS and the grid composer write) so attribution,
      // tiles, and comment/count rules agree on every platform.
      const meta: PostMeta = {};
      if (music) meta.music = music;
      if (coverUrl) meta.cover = coverUrl;
      if (commentsOff) meta.commentsOff = true;
      if (hideCounts) meta.hideCounts = true;
      if (shareToFeed) meta.feed = true;
      const body = caption.trim();
      await createReel({
        userId: user.id,
        username: profile.username,
        caption: hasMeta(meta) ? encodePostMeta(meta, body) : body,
        mediaUrls: [mediaUrl],
      });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["reels"] });
      queryClient.invalidateQueries({ queryKey: ["feed"] });
      queryClient.invalidateQueries({ queryKey: ["profile-posts"] });
      toast("Wave posted");
      reset();
      onOpenChange(false);
    },
    onError: (err) => {
      setProgress(null);
      toast(err instanceof Error ? err.message : "Couldn't post your wave.");
    },
  });

  const insertAtCursor = (text: string): void => {
    const el = captionRef.current;
    if (!el) {
      setCaption((c) => c + text);
      return;
    }
    const start = el.selectionStart ?? caption.length;
    const end = el.selectionEnd ?? caption.length;
    const next = caption.slice(0, start) + text + caption.slice(end);
    setCaption(next.slice(0, CAPTION_MAX));
    window.requestAnimationFrame(() => {
      el.focus();
      const pos = start + text.length;
      el.setSelectionRange(pos, pos);
    });
  };

  const canPost = !!file && !publish.isPending && framesState !== "busy";

  return (
    <Dialog.Root open={open} onOpenChange={(o) => (o ? onOpenChange(true) : close())}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-50 bg-black/60 backdrop-blur-[2px] data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0" />
        <Dialog.Content
          className={cn(
            "fixed inset-x-0 bottom-0 z-50 mx-auto flex max-h-[94dvh] w-full flex-col rounded-t-[26px] bg-background text-foreground shadow-2xl outline-none data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:slide-out-to-bottom data-[state=open]:slide-in-from-bottom sm:bottom-auto sm:top-1/2 sm:max-h-[88dvh] sm:-translate-y-1/2 sm:rounded-[26px]",
            file ? "max-w-[960px]" : "max-w-[560px]"
          )}
          onOpenAutoFocus={(e) => e.preventDefault()}
        >
          {/* Header */}
          <div className="flex h-14 shrink-0 items-center justify-between border-b border-border px-4">
            <button
              onClick={close}
              className="flex h-9 w-9 items-center justify-center rounded-full text-foreground transition-colors hover:bg-secondary"
              aria-label="Cancel"
            >
              <X className="h-5 w-5" />
            </button>
            <Dialog.Title className="flex items-center gap-2 text-[16px] font-bold">
              <WavesTabGlyph size={20} active />
              New wave
            </Dialog.Title>
            {file ? (
              <button
                onClick={() => publish.mutate()}
                disabled={!canPost}
                className="flex h-9 items-center gap-1.5 rounded-full px-4 text-[13px] font-bold text-white transition-transform active:scale-95 disabled:opacity-40"
                style={{ background: WHISPER_BRAND_GRADIENT }}
              >
                {publish.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : null}
                {publish.isPending ? "Posting" : "Post wave"}
              </button>
            ) : (
              <span className="w-9" />
            )}
          </div>

          {!file ? (
            /* ─── Step 1 — pick the footage ─── */
            <div className="min-h-0 flex-1 overflow-y-auto p-5">
              <div
                onDragOver={(e) => {
                  e.preventDefault();
                  setDragOver(true);
                }}
                onDragLeave={() => setDragOver(false)}
                onDrop={onDrop}
                className={cn(
                  "flex flex-col items-center justify-center gap-4 rounded-[22px] border border-dashed px-6 py-14 text-center transition-colors",
                  dragOver ? "border-foreground bg-secondary/60" : "border-border"
                )}
              >
                <span
                  className="flex h-16 w-16 items-center justify-center rounded-[20px] text-white shadow-lg"
                  style={{ background: WHISPER_BRAND_GRADIENT }}
                >
                  <Upload className="h-7 w-7" />
                </span>
                <div>
                  <p className="text-[18px] font-bold">Drag a video here</p>
                  <p className="mt-1 text-[13px] text-muted-foreground">
                    Vertical (9:16) looks best · MP4 or MOV · up to 3 minutes
                  </p>
                </div>
                <button
                  onClick={() => fileRef.current?.click()}
                  className="flex h-11 items-center gap-2 rounded-full bg-foreground px-5 text-[14px] font-bold text-background transition-transform active:scale-95"
                >
                  Select from computer
                </button>
                {music && (
                  <p className="flex items-center gap-1.5 text-[12px] text-muted-foreground">
                    <Music className="h-3.5 w-3.5" />
                    Sound attached: {music.title} — {music.artist}
                  </p>
                )}
              </div>
              <div className="mt-4 grid grid-cols-3 gap-2">
                {[
                  { title: "Pick a cover", body: "Choose the frame that fronts your wave everywhere." },
                  { title: "Add a sound", body: "Tag a track or another wave's original sound." },
                  { title: "Set the rules", body: "Turn off comments or hide the like count." },
                ].map((tip) => (
                  <div key={tip.title} className="rounded-2xl border border-border px-3 py-3">
                    <p className="text-[12.5px] font-bold">{tip.title}</p>
                    <p className="mt-0.5 text-[11.5px] leading-snug text-muted-foreground">{tip.body}</p>
                  </div>
                ))}
              </div>
            </div>
          ) : (
            /* ─── Step 2 — the studio ─── */
            <div className="grid min-h-0 flex-1 grid-cols-1 overflow-y-auto lg:grid-cols-[340px_minmax(0,1fr)] lg:overflow-hidden">
              {/* Preview */}
              <div className="flex items-start justify-center bg-black p-4 lg:h-full lg:items-center lg:overflow-hidden">
                <div className="relative aspect-[9/16] h-[52dvh] max-h-[560px] overflow-hidden rounded-2xl bg-[#0a0a0a] lg:h-auto lg:max-h-full lg:w-full">
                  {isVideo && previewUrl ? (
                    <video
                      ref={previewRef}
                      src={previewUrl}
                      loop
                      playsInline
                      muted={previewMuted}
                      autoPlay
                      onLoadedMetadata={(e) => {
                        const v = e.currentTarget;
                        if (Number.isFinite(v.duration)) setDuration(v.duration);
                      }}
                      onClick={() => setPreviewPlaying((p) => !p)}
                      className="h-full w-full object-contain"
                    />
                  ) : previewUrl ? (
                    <img src={previewUrl} alt="" className="h-full w-full object-cover" draggable={false} />
                  ) : null}
                  {isVideo && (
                    <>
                      <div className="pointer-events-none absolute inset-x-0 top-0 bg-gradient-to-b from-black/60 to-transparent px-3 pb-8 pt-3">
                        <p className="flex items-center gap-2 text-[12px] font-semibold text-white">
                          <Avatar url={profile?.profile_image_url} name={username} size={22} />
                          {username}
                          {duration > 0 && <span className="text-white/60">· {formatClock(duration)}</span>}
                        </p>
                      </div>
                      <div className="absolute bottom-3 left-3 right-3 flex items-center justify-between">
                        <button
                          type="button"
                          onClick={() => setPreviewPlaying((p) => !p)}
                          aria-label={previewPlaying ? "Pause preview" : "Play preview"}
                          className="flex h-9 w-9 items-center justify-center rounded-full bg-black/50 text-white backdrop-blur-md"
                        >
                          {previewPlaying ? <Pause className="h-4 w-4" /> : <Play className="ml-0.5 h-4 w-4" />}
                        </button>
                        <button
                          type="button"
                          onClick={() => setPreviewMuted((m) => !m)}
                          aria-label={previewMuted ? "Unmute preview" : "Mute preview"}
                          className="flex h-9 w-9 items-center justify-center rounded-full bg-black/50 text-white backdrop-blur-md"
                        >
                          {previewMuted ? <VolumeX className="h-4 w-4" /> : <Volume2 className="h-4 w-4" />}
                        </button>
                      </div>
                    </>
                  )}
                </div>
              </div>

              {/* Form */}
              <div className="min-h-0 overflow-y-auto px-5 py-4 lg:h-full">
                {/* Cover */}
                {isVideo && (
                  <section>
                    <div className="flex items-center justify-between">
                      <p className="text-[13px] font-bold">Cover</p>
                      {framesState === "failed" ? (
                        <button
                          type="button"
                          onClick={() => previewUrl && void generateFrames(previewUrl)}
                          className="flex items-center gap-1 text-[12px] font-semibold text-muted-foreground hover:text-foreground"
                        >
                          <RefreshCw className="h-3.5 w-3.5" />
                          Try again
                        </button>
                      ) : (
                        <p className="text-[11.5px] text-muted-foreground">Fronts your wave on every grid</p>
                      )}
                    </div>
                    {framesState === "busy" ? (
                      <div className="mt-2 flex h-[92px] items-center gap-2 rounded-xl border border-border px-3 text-[12px] text-muted-foreground">
                        <Loader2 className="h-4 w-4 animate-spin" />
                        Reading frames…
                      </div>
                    ) : framesState === "failed" ? (
                      <div className="mt-2 flex h-[92px] items-center rounded-xl border border-dashed border-border px-3 text-[12px] text-muted-foreground">
                        Couldn't read frames from this file — the first frame will be the cover. Converting to MP4 usually fixes it.
                      </div>
                    ) : (
                      <div className="mt-2 flex gap-1.5 overflow-x-auto">
                        {frames.map((src, i) => (
                          <button
                            key={i}
                            type="button"
                            onClick={() => setCoverIndex(i)}
                            aria-label={`Cover frame ${i + 1}`}
                            className={cn(
                              "relative aspect-[9/16] h-[92px] shrink-0 overflow-hidden rounded-lg transition-transform active:scale-95",
                              coverIndex === i ? "ring-2 ring-foreground" : "opacity-80 hover:opacity-100"
                            )}
                          >
                            <img src={src} alt="" className="h-full w-full object-cover" draggable={false} />
                            {coverIndex === i && (
                              <span className="absolute bottom-1 right-1 flex h-4 w-4 items-center justify-center rounded-full bg-foreground text-background">
                                <Check className="h-2.5 w-2.5" strokeWidth={3} />
                              </span>
                            )}
                          </button>
                        ))}
                      </div>
                    )}
                  </section>
                )}

                {/* Caption */}
                <section className={cn(isVideo && "mt-5")}>
                  <div className="flex items-center justify-between">
                    <p className="text-[13px] font-bold">Caption</p>
                    <p className="text-[11.5px] tabular-nums text-muted-foreground">
                      {caption.length.toLocaleString()} / {CAPTION_MAX.toLocaleString()}
                    </p>
                  </div>
                  <textarea
                    ref={captionRef}
                    value={caption}
                    onChange={(e) => setCaption(e.target.value.slice(0, CAPTION_MAX))}
                    placeholder="Say something about your wave…"
                    rows={4}
                    className="mt-2 w-full resize-none rounded-xl border border-border bg-transparent px-3 py-2.5 text-[15px] leading-snug outline-none placeholder:text-muted-foreground focus:border-foreground/40"
                  />
                  <div className="mt-1.5 flex items-center gap-1">
                    <button
                      type="button"
                      onClick={() => insertAtCursor("#")}
                      className="flex h-8 items-center gap-1 rounded-full border border-border px-2.5 text-[12px] font-semibold text-muted-foreground hover:text-foreground"
                    >
                      <Hash className="h-3.5 w-3.5" />
                      Hashtag
                    </button>
                    <button
                      type="button"
                      onClick={() => insertAtCursor("@")}
                      className="flex h-8 items-center gap-1 rounded-full border border-border px-2.5 text-[12px] font-semibold text-muted-foreground hover:text-foreground"
                    >
                      <AtSign className="h-3.5 w-3.5" />
                      Mention
                    </button>
                    <button
                      type="button"
                      onClick={() => setShowEmoji((v) => !v)}
                      className={cn(
                        "flex h-8 w-8 items-center justify-center rounded-full border border-border transition-colors hover:text-foreground",
                        showEmoji ? "text-foreground" : "text-muted-foreground"
                      )}
                      aria-label="Add emoji"
                    >
                      <Smile className="h-4 w-4" />
                    </button>
                  </div>
                  {showEmoji && (
                    <div className="mt-2 grid grid-cols-8 gap-1 rounded-2xl border border-border p-2">
                      {REEL_EMOJIS.map((e) => (
                        <button
                          key={e}
                          type="button"
                          onClick={() => insertAtCursor(e)}
                          className="flex h-9 items-center justify-center rounded-lg text-xl transition-colors hover:bg-secondary"
                        >
                          {e}
                        </button>
                      ))}
                    </div>
                  )}
                </section>

                {/* Sound */}
                <section className="mt-5">
                  <p className="text-[13px] font-bold">Sound</p>
                  {music ? (
                    <div className="mt-2 flex items-center gap-3 rounded-xl border border-border px-3 py-2.5">
                      {music.artworkURL ? (
                        <img src={music.artworkURL} alt="" className="h-11 w-11 rounded-lg object-cover" draggable={false} />
                      ) : (
                        <span className="flex h-11 w-11 items-center justify-center rounded-lg bg-secondary">
                          <Music className="h-5 w-5 text-muted-foreground" />
                        </span>
                      )}
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-[13.5px] font-bold">{music.title}</p>
                        <p className="truncate text-[12px] text-muted-foreground">{music.artist}</p>
                      </div>
                      <button
                        type="button"
                        onClick={() => setShowMusic(true)}
                        className="text-[12px] font-semibold text-muted-foreground hover:text-foreground"
                      >
                        Change
                      </button>
                      <button
                        type="button"
                        onClick={() => setMusic(null)}
                        aria-label="Remove sound"
                        className="flex h-8 w-8 items-center justify-center rounded-full text-muted-foreground hover:bg-secondary hover:text-foreground"
                      >
                        <X className="h-4 w-4" />
                      </button>
                    </div>
                  ) : (
                    <button
                      type="button"
                      onClick={() => setShowMusic(true)}
                      className="mt-2 flex w-full items-center gap-3 rounded-xl border border-border px-3 py-2.5 text-left transition-colors hover:bg-secondary/50"
                    >
                      <span className="flex h-11 w-11 items-center justify-center rounded-lg bg-secondary">
                        <Music className="h-5 w-5 text-muted-foreground" />
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="block text-[13.5px] font-bold">Add a sound</span>
                        <span className="block text-[12px] text-muted-foreground">
                          Tag a track — your wave's own audio stays as the original sound.
                        </span>
                      </span>
                      <ChevronRight className="h-4 w-4 text-muted-foreground" />
                    </button>
                  )}
                </section>

                {/* Rules */}
                <section className="mt-5">
                  <p className="text-[13px] font-bold">Advanced</p>
                  <div className="mt-2 divide-y divide-border rounded-xl border border-border">
                    {[
                      {
                        key: "feed",
                        title: "Also share to feed",
                        body: "Your wave shows up in your followers' feeds too — it stays a wave everywhere else.",
                        on: shareToFeed,
                        set: setShareToFeed,
                      },
                      {
                        key: "comments",
                        title: "Turn off commenting",
                        body: "Nobody can comment on this wave.",
                        on: commentsOff,
                        set: setCommentsOff,
                      },
                      {
                        key: "counts",
                        title: "Hide like count",
                        body: "Only you see how many people liked it.",
                        on: hideCounts,
                        set: setHideCounts,
                      },
                    ].map((row) => (
                      <label key={row.key} className="flex cursor-pointer items-center gap-3 px-3 py-3">
                        <span className="min-w-0 flex-1">
                          <span className="block text-[13.5px] font-semibold">{row.title}</span>
                          <span className="block text-[12px] text-muted-foreground">{row.body}</span>
                        </span>
                        <button
                          type="button"
                          role="switch"
                          aria-checked={row.on}
                          onClick={() => row.set(!row.on)}
                          className={cn(
                            "relative h-7 w-12 shrink-0 rounded-full transition-colors",
                            row.on ? "bg-foreground" : "bg-secondary"
                          )}
                        >
                          <span
                            className={cn(
                              "absolute top-0.5 h-6 w-6 rounded-full shadow transition-all",
                              row.on ? "left-[22px] bg-background" : "left-0.5 bg-white"
                            )}
                          />
                        </button>
                      </label>
                    ))}
                  </div>
                </section>

                {/* Swap */}
                <div className="mt-5 flex items-center justify-between pb-2">
                  <button
                    type="button"
                    onClick={() => fileRef.current?.click()}
                    className="flex items-center gap-1.5 text-[12.5px] font-semibold text-muted-foreground hover:text-foreground"
                  >
                    <RefreshCw className="h-3.5 w-3.5" />
                    Swap video
                  </button>
                  <p className="text-[11.5px] text-muted-foreground">
                    Trim, text, filters & effects live in the iPhone app for now.
                  </p>
                </div>
              </div>
            </div>
          )}

          {/* Posting overlay */}
          {publish.isPending && progress && (
            <div className="absolute inset-0 z-10 flex flex-col items-center justify-center gap-3 rounded-[26px] bg-background/85 backdrop-blur-sm">
              <span
                className="flex h-14 w-14 items-center justify-center rounded-full text-white"
                style={{ background: WHISPER_BRAND_GRADIENT }}
              >
                <Loader2 className="h-6 w-6 animate-spin" />
              </span>
              <p className="text-[14px] font-bold">{progress}</p>
            </div>
          )}

          <input
            ref={fileRef}
            type="file"
            accept="video/*,image/*"
            className="hidden"
            onChange={handlePick}
          />

          {showMusic && (
            <MusicPickerSheet
              open={showMusic}
              onOpenChange={setShowMusic}
              onPick={(track) => {
                setMusic({
                  id: track.id,
                  title: track.title,
                  artist: track.artist,
                  previewURL: track.previewURL,
                  artworkURL: track.artworkURL,
                });
                setShowMusic(false);
              }}
            />
          )}
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

export const ReelComposerModal = memo(ReelComposerModalBase);
