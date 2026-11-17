import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  X,
  Type,
  BarChart2,
  SlidersHorizontal,
  MessageCircleQuestion,
  MapPin,
  AtSign,
  Music as MusicIcon,
  ImagePlus,
  Trash2,
  Loader2,
  Check,
  Plus,
  Search,
  Hash,
  Timer,
  PenLine,
  Undo2,
  Send,
  Sticker as StickerIcon,
} from "lucide-react";
import { toast } from "sonner";

import { Avatar } from "@/components/Avatar";
import { StorySticker } from "@/components/StorySticker";
import { GiphyPicker } from "@/components/GiphyPicker";
import { MusicPickerSheet } from "@/components/MusicPickerSheet";
import { cn } from "@/lib/utils";
import { createStory, uploadMedia, searchProfiles } from "@/lib/api";
import { currentPlaceName } from "@/lib/geo";
import { encodeStoryMetadata, type StorySticker as StickerType } from "@/lib/storyStickers";
import { StoryJasperDock } from "@/components/StoryJasperDock";
import { useAuth } from "@/hooks/useAuth";
import type { MusicTrack } from "@/lib/music";

const TEXT_COLORS = [
  "#FFFFFF",
  "#000000",
  "#FF3B30",
  "#FF9500",
  "#FFD60A",
  "#34C759",
  "#0A84FF",
  "#BF5AF2",
  "#FF2D92",
];

const SLIDER_EMOJIS = ["❤️", "😍", "🔥", "😂", "👏", "💪", "🤯", "🥶"];

type Tool =
  | "text"
  | "poll"
  | "slider"
  | "question"
  | "location"
  | "mention"
  | "gif"
  | "photo"
  | "hashtag"
  | "countdown"
  | "music"
  | "tray";

interface DrawStroke {
  points: { x: number; y: number }[];
  color: string;
  /** Stroke width as a fraction of the canvas width. */
  width: number;
  marker: "pen" | "neon" | "marker";
}

/** Paint normalized strokes onto any canvas size — live view AND final bake. */
function paintStrokes(
  ctx: CanvasRenderingContext2D,
  list: DrawStroke[],
  w: number,
  h: number
): void {
  for (const s of list) {
    if (s.points.length < 2) continue;
    ctx.save();
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    const lw = Math.max(1, s.width * w);
    const trace = (): void => {
      ctx.beginPath();
      ctx.moveTo(s.points[0].x * w, s.points[0].y * h);
      for (let i = 1; i < s.points.length; i++) {
        ctx.lineTo(s.points[i].x * w, s.points[i].y * h);
      }
      ctx.stroke();
    };
    if (s.marker === "neon") {
      ctx.shadowColor = s.color;
      ctx.shadowBlur = lw * 1.6;
      ctx.strokeStyle = s.color;
      ctx.lineWidth = lw;
      trace();
      ctx.shadowBlur = 0;
      ctx.strokeStyle = "#ffffff";
      ctx.lineWidth = Math.max(1, lw * 0.45);
      trace();
    } else if (s.marker === "marker") {
      ctx.globalAlpha = 0.55;
      ctx.strokeStyle = s.color;
      ctx.lineWidth = lw * 1.7;
      trace();
    } else {
      ctx.strokeStyle = s.color;
      ctx.lineWidth = lw;
      trace();
    }
    ctx.restore();
  }
}

/** The Instagram sticker tray — the kit's grid of sticker pills. */
const TRAY_ITEMS: { id: Tool; icon: typeof Type; label: string; tint: string }[] = [
  { id: "location", icon: MapPin, label: "Location", tint: "#ED4956" },
  { id: "mention", icon: AtSign, label: "Mention", tint: "#8A3AB9" },
  { id: "hashtag", icon: Hash, label: "Hashtag", tint: "#3897F0" },
  { id: "gif", icon: ImagePlus, label: "GIF", tint: "#FCAF45" },
  { id: "photo", icon: ImagePlus, label: "Photo", tint: "#0E9F76" },
  { id: "music", icon: MusicIcon, label: "Music", tint: "#ED4956" },
  { id: "poll", icon: BarChart2, label: "Poll", tint: "#3897F0" },
  { id: "question", icon: MessageCircleQuestion, label: "Question", tint: "#8A3AB9" },
  { id: "slider", icon: SlidersHorizontal, label: "Slider", tint: "#FCAF45" },
  { id: "countdown", icon: Timer, label: "Countdown", tint: "#ED4956" },
];

interface StoryMusic {
  previewURL: string;
  title: string;
  artist: string;
  artworkURL: string | null;
}

export function StoryEditor({
  file,
  onClose,
}: {
  file: File;
  onClose: () => void;
}) {
  const { user, profile } = useAuth();
  const queryClient = useQueryClient();
  const canvasRef = useRef<HTMLDivElement>(null);
  const previewUrl = useRef<string>(URL.createObjectURL(file)).current;

  const [stickers, setStickers] = useState<StickerType[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [caption, setCaption] = useState<string>("");
  const [music, setMusic] = useState<StoryMusic | null>(null);
  const [tool, setTool] = useState<Tool | null>(null);
  const [showMusic, setShowMusic] = useState<boolean>(false);
  const photoRef = useRef<HTMLInputElement>(null);
  // Instagram draw tool — strokes render live and bake into the posted image.
  const [drawing, setDrawing] = useState<boolean>(false);
  const [strokes, setStrokes] = useState<DrawStroke[]>([]);
  const [liveStroke, setLiveStroke] = useState<DrawStroke | null>(null);
  const [drawColor, setDrawColor] = useState<string>("#FFFFFF");
  const [drawWidth, setDrawWidth] = useState<number>(10);
  const [drawMarker, setDrawMarker] = useState<"pen" | "neon" | "marker">("pen");
  const drawCanvasRef = useRef<HTMLCanvasElement>(null);

  // Repaint the stroke canvas whenever the strokes change.
  useEffect(() => {
    const cv = drawCanvasRef.current;
    const host = canvasRef.current;
    if (!cv || !host) return;
    const rect = host.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    const w = Math.max(1, Math.round(rect.width * dpr));
    const h = Math.max(1, Math.round(rect.height * dpr));
    if (cv.width !== w) cv.width = w;
    if (cv.height !== h) cv.height = h;
    const ctx = cv.getContext("2d");
    if (!ctx) return;
    ctx.clearRect(0, 0, w, h);
    paintStrokes(ctx, liveStroke ? [...strokes, liveStroke] : strokes, w, h);
  }, [strokes, liveStroke, drawing]);

  const drawPoint = (e: React.PointerEvent): { x: number; y: number } | null => {
    const host = canvasRef.current;
    if (!host) return null;
    const rect = host.getBoundingClientRect();
    return {
      x: Math.min(1, Math.max(0, (e.clientX - rect.left) / rect.width)),
      y: Math.min(1, Math.max(0, (e.clientY - rect.top) / rect.height)),
    };
  };

  const onDrawDown = (e: React.PointerEvent<HTMLDivElement>): void => {
    const p = drawPoint(e);
    if (!p) return;
    e.currentTarget.setPointerCapture(e.pointerId);
    const host = canvasRef.current;
    const rectW = host ? host.getBoundingClientRect().width : 400;
    setLiveStroke({
      points: [p],
      color: drawColor,
      width: drawWidth / Math.max(1, rectW),
      marker: drawMarker,
    });
  };

  const onDrawMove = (e: React.PointerEvent<HTMLDivElement>): void => {
    if (!liveStroke) return;
    const p = drawPoint(e);
    if (!p) return;
    setLiveStroke((s) => (s ? { ...s, points: [...s.points, p] } : s));
  };

  const onDrawUp = (): void => {
    if (!liveStroke) return;
    if (liveStroke.points.length > 1) {
      const done = liveStroke;
      setStrokes((prev) => [...prev, done]);
    }
    setLiveStroke(null);
  };

  /** Bake drawn strokes into the story image at publish time. */
  const bakeUpload = async (): Promise<File> => {
    if (strokes.length === 0) return file;
    try {
      const img = await new Promise<HTMLImageElement>((resolve, reject) => {
        const el = new Image();
        el.onload = () => resolve(el);
        el.onerror = reject;
        el.src = previewUrl;
      });
      const rect = canvasRef.current?.getBoundingClientRect();
      const ratio = rect && rect.width > 0 ? rect.height / rect.width : 16 / 9;
      const outW = 1080;
      const outH = Math.round(outW * ratio);
      const c = document.createElement("canvas");
      c.width = outW;
      c.height = outH;
      const ctx = c.getContext("2d");
      if (!ctx) return file;
      const scale = Math.max(outW / img.naturalWidth, outH / img.naturalHeight);
      const dw = img.naturalWidth * scale;
      const dh = img.naturalHeight * scale;
      ctx.drawImage(img, (outW - dw) / 2, (outH - dh) / 2, dw, dh);
      paintStrokes(ctx, strokes, outW, outH);
      const blob = await new Promise<Blob | null>((resolve) =>
        c.toBlob((b) => resolve(b), "image/jpeg", 0.92)
      );
      if (!blob) return file;
      return new File([blob], "story.jpg", { type: "image/jpeg" });
    } catch {
      return file;
    }
  };

  const addSticker = (s: Omit<StickerType, "id" | "x" | "y" | "scale" | "rotation">): void => {
    const sticker: StickerType = {
      id: crypto.randomUUID(),
      x: 0.5,
      y: 0.42,
      scale: 1,
      rotation: 0,
      ...s,
    };
    setStickers((prev) => [...prev, sticker]);
    setSelectedId(sticker.id);
    setTool(null);
  };

  const updateSticker = (id: string, patch: Partial<StickerType>): void => {
    setStickers((prev) => prev.map((s) => (s.id === id ? { ...s, ...patch } : s)));
  };

  const removeSticker = (id: string): void => {
    setStickers((prev) => prev.filter((s) => s.id !== id));
    setSelectedId(null);
  };

  // Drag a placed sticker around the canvas (normalized coords).
  const startDrag = (e: React.PointerEvent, id: string): void => {
    e.stopPropagation();
    setSelectedId(id);
    const canvas = canvasRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    const move = (ev: PointerEvent): void => {
      const x = Math.max(0.04, Math.min(0.96, (ev.clientX - rect.left) / rect.width));
      const y = Math.max(0.06, Math.min(0.94, (ev.clientY - rect.top) / rect.height));
      updateSticker(id, { x, y });
    };
    const up = (): void => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  };

  const pickMusic = (track: MusicTrack): void => {
    const m: StoryMusic = {
      previewURL: track.previewURL,
      title: track.title,
      artist: track.artist,
      artworkURL: track.artworkURL,
    };
    setMusic(m);
    addSticker({
      kind: "music",
      musicTitle: track.title,
      musicArtist: track.artist,
      musicArtwork: track.artworkURL,
    });
  };

  const handlePhoto = async (e: React.ChangeEvent<HTMLInputElement>): Promise<void> => {
    const f = e.target.files?.[0];
    e.target.value = "";
    if (!f || !user) return;
    try {
      const url = await uploadMedia(f, user.id);
      addSticker({ kind: "photo", imageURL: url });
    } catch {
      toast.error("Couldn't add that photo.");
    }
  };

  const publish = useMutation({
    mutationFn: async (): Promise<void> => {
      if (!user || !profile) throw new Error("Set up your profile first.");
      const upload = await bakeUpload();
      const imageUrl = await uploadMedia(upload, user.id);
      await createStory({
        userId: user.id,
        username: profile.username,
        imageUrl,
        caption: caption.trim() || null,
        metadata: encodeStoryMetadata(stickers, canvasRef.current?.clientWidth),
        music,
      });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["stories"] });
      toast("Story shared");
      onClose();
    },
    onError: (err) => toast(err instanceof Error ? err.message : "Couldn't share."),
  });

  return createPortal(
    <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/95">
      <div className="relative flex max-h-[100svh] w-[min(100%,calc((100svh-160px)*9/16))] max-w-[440px] flex-col overflow-y-auto bg-black py-2 sm:rounded-3xl">
        {/* Canvas */}
        <div
          ref={canvasRef}
          data-story-stage
          className="relative aspect-[9/16] w-full shrink-0 overflow-hidden rounded-3xl"
          onPointerDown={() => setSelectedId(null)}
        >
          <img src={previewUrl} alt="" className="absolute inset-0 h-full w-full object-cover" />

          {/* Drawn strokes — the live view of what bakes into the image. */}
          <canvas
            ref={drawCanvasRef}
            className="pointer-events-none absolute inset-0 h-full w-full"
          />

          {stickers.map((s) => (
            <div
              key={s.id}
              onPointerDown={(e) => startDrag(e, s.id)}
              className="absolute cursor-grab touch-none active:cursor-grabbing"
              style={{
                left: `${s.x * 100}%`,
                top: `${s.y * 100}%`,
                transform: `translate(-50%, -50%) scale(${s.scale}) rotate(${s.rotation}rad)`,
              }}
            >
              <div className={cn(selectedId === s.id && "rounded-2xl ring-2 ring-white/80")}>
                <StorySticker sticker={s} authorUsername={profile?.username} authorAvatarUrl={profile?.profile_image_url} />
              </div>
              {selectedId === s.id && (
                <button
                  onPointerDown={(e) => e.stopPropagation()}
                  onClick={() => removeSticker(s.id)}
                  className="absolute -right-2 -top-2 flex h-6 w-6 items-center justify-center rounded-full bg-black/80 text-white"
                >
                  <Trash2 className="h-3.5 w-3.5" />
                </button>
              )}
            </div>
          ))}

          {/* Top bar — kit chrome: ✕ left; Aa · stickers · music · draw right. */}
          {!drawing && (
            <div className="absolute inset-x-0 top-0 z-20 flex items-center justify-between p-3">
              <button
                onClick={onClose}
                aria-label="Close"
                className="p-1.5 text-white drop-shadow-[0_1px_3px_rgba(0,0,0,0.6)] transition-transform active:scale-90"
              >
                <X className="h-7 w-7" strokeWidth={2.4} />
              </button>
              <div className="flex items-center gap-0.5">
                {music && (
                  <span className="mr-1 flex items-center gap-1.5 rounded-full bg-black/45 px-2.5 py-1.5 text-xs font-semibold text-white">
                    <MusicIcon className="h-3.5 w-3.5" />
                    <span className="max-w-[88px] truncate">{music.title}</span>
                    <button onClick={() => setMusic(null)} aria-label="Remove music">
                      <X className="h-3.5 w-3.5" />
                    </button>
                  </span>
                )}
                <button
                  onClick={() => setTool("text")}
                  aria-label="Add text"
                  className="p-2 text-white drop-shadow-[0_1px_3px_rgba(0,0,0,0.6)] transition-transform active:scale-90"
                >
                  <Type className="h-6 w-6" strokeWidth={2.6} />
                </button>
                <button
                  onClick={() => setTool("tray")}
                  aria-label="Stickers"
                  className="p-2 text-white drop-shadow-[0_1px_3px_rgba(0,0,0,0.6)] transition-transform active:scale-90"
                >
                  <StickerIcon className="h-6 w-6" strokeWidth={2.2} />
                </button>
                <button
                  onClick={() => setShowMusic(true)}
                  aria-label="Add music"
                  className="p-2 text-white drop-shadow-[0_1px_3px_rgba(0,0,0,0.6)] transition-transform active:scale-90"
                >
                  <MusicIcon className="h-6 w-6" strokeWidth={2.2} />
                </button>
                <button
                  onClick={() => setDrawing(true)}
                  aria-label="Draw"
                  className="p-2 text-white drop-shadow-[0_1px_3px_rgba(0,0,0,0.6)] transition-transform active:scale-90"
                >
                  <PenLine className="h-6 w-6" strokeWidth={2.2} />
                </button>
              </div>
            </div>
          )}

          {/* Jasper — the meeting-style pill dock floating over the canvas:
              Today's spark, caption ideas read from the actual photo, and
              question stickers — each landing as a draggable sticker. */}
          {!drawing && (
            <StoryJasperDock
              file={file}
              onCaption={(text) =>
                addSticker({ kind: "text", text, color: "#FFFFFF", style: 1 })
              }
              onQuestion={(q) =>
                addSticker({
                  kind: "question",
                  text: q,
                  background: "#FFFFFF",
                  color: "#000000",
                })
              }
            />
          )}

          {/* Draw capture surface — pointer strokes in normalized coords. */}
          {drawing && (
            <div
              className="absolute inset-0 z-30 touch-none"
              onPointerDown={onDrawDown}
              onPointerMove={onDrawMove}
              onPointerUp={onDrawUp}
              onPointerCancel={onDrawUp}
            />
          )}
        </div>

        {/* Caption + the kit send row — "Your story" pill + circular send. */}
        <div className="space-y-3 border-t border-white/10 bg-black p-3">
          <input
            value={caption}
            onChange={(e) => setCaption(e.target.value)}
            placeholder="Add a caption…"
            className="h-10 w-full rounded-full border border-white/20 bg-white/10 px-4 text-sm text-white outline-none placeholder:text-white/50"
          />
          <div className="flex items-center justify-between gap-3">
            <button
              onClick={() => publish.mutate()}
              disabled={publish.isPending}
              className="flex items-center gap-2 rounded-full bg-white py-1 pl-1 pr-4 transition-transform active:scale-95 disabled:opacity-60"
            >
              <Avatar
                name={profile?.username}
                url={profile?.profile_image_url}
                size={28}
              />
              <span className="text-[13px] font-extrabold text-black">Your story</span>
            </button>
            <button
              onClick={() => publish.mutate()}
              disabled={publish.isPending}
              aria-label="Share story"
              className="flex h-11 w-11 items-center justify-center rounded-full bg-white transition-transform active:scale-95 disabled:opacity-60"
            >
              {publish.isPending ? (
                <Loader2 className="h-5 w-5 animate-spin text-black" />
              ) : (
                <Send className="h-5 w-5 text-black" />
              )}
            </button>
          </div>
        </div>

        {/* Draw mode chrome — Undo/Done up top, brush + colours below. */}
        {drawing && (
          <>
            <div className="absolute inset-x-0 top-0 z-40 flex items-center justify-between p-3">
              <button
                onClick={() => setStrokes((s) => s.slice(0, -1))}
                disabled={strokes.length === 0}
                aria-label="Undo stroke"
                className="p-2 text-white drop-shadow-[0_1px_3px_rgba(0,0,0,0.6)] transition-transform active:scale-90 disabled:opacity-40"
              >
                <Undo2 className="h-6 w-6" strokeWidth={2.4} />
              </button>
              <button
                onClick={() => setDrawing(false)}
                className="px-2 py-1 text-[15px] font-extrabold text-white drop-shadow-[0_1px_3px_rgba(0,0,0,0.6)]"
              >
                Done
              </button>
            </div>
            <div className="absolute inset-x-0 bottom-0 z-40 space-y-3 bg-black/70 p-4 backdrop-blur-sm">
              <div className="flex items-center justify-center gap-2">
                {(["pen", "neon", "marker"] as const).map((m) => (
                  <button
                    key={m}
                    onClick={() => setDrawMarker(m)}
                    className={cn(
                      "rounded-full px-4 py-1.5 text-xs font-bold capitalize transition-colors",
                      drawMarker === m ? "bg-white text-black" : "bg-white/20 text-white"
                    )}
                  >
                    {m}
                  </button>
                ))}
                <input
                  type="range"
                  min={4}
                  max={26}
                  value={drawWidth}
                  onChange={(e) => setDrawWidth(Number(e.target.value))}
                  className="ml-2 w-24 accent-white"
                  aria-label="Brush size"
                />
              </div>
              <div className="flex items-center justify-center gap-2">
                {TEXT_COLORS.map((c) => (
                  <button
                    key={c}
                    onClick={() => setDrawColor(c)}
                    aria-label={`Colour ${c}`}
                    className={cn(
                      "h-7 w-7 rounded-full border-2 transition-transform active:scale-90",
                      drawColor === c ? "border-white ring-2 ring-white/60" : "border-white/50"
                    )}
                    style={{ background: c }}
                  />
                ))}
              </div>
            </div>
          </>
        )}

        <input
          ref={photoRef}
          type="file"
          accept="image/*"
          className="hidden"
          onChange={(e) => void handlePhoto(e)}
        />

        {/* Instagram sticker tray — the kit's grid of sticker pills. */}
        {tool === "tray" && (
          <div
            className="absolute inset-0 z-20 flex flex-col justify-end bg-black/50"
            onClick={() => setTool(null)}
          >
            <div
              className="rounded-t-3xl bg-[#262626] p-4 pb-6"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="mx-auto mb-4 h-1 w-10 rounded-full bg-white/25" />
              <div className="grid grid-cols-3 gap-2.5">
                {TRAY_ITEMS.map((t) => (
                  <button
                    key={t.id}
                    onClick={() => {
                      if (t.id === "photo") {
                        setTool(null);
                        photoRef.current?.click();
                      } else if (t.id === "music") {
                        setTool(null);
                        setShowMusic(true);
                      } else {
                        setTool(t.id);
                      }
                    }}
                    className="flex flex-col items-center gap-1.5 rounded-2xl bg-white px-2 py-3.5 shadow-sm transition-transform active:scale-95"
                  >
                    <t.icon className="h-5 w-5" style={{ color: t.tint }} strokeWidth={2.5} />
                    <span className="text-[11px] font-extrabold uppercase tracking-wide text-black">
                      {t.label}
                    </span>
                  </button>
                ))}
              </div>
            </div>
          </div>
        )}

        {/* Creation sheets */}
        {tool === "text" && (
          <TextSheet
            onClose={() => setTool(null)}
            onDone={(text, color, style) => addSticker({ kind: "text", text, color, style })}
          />
        )}
        {tool === "poll" && (
          <PollSheet
            onClose={() => setTool(null)}
            onDone={(text, options) => addSticker({ kind: "poll", text, pollOptions: options })}
          />
        )}
        {tool === "slider" && (
          <SliderSheet
            onClose={() => setTool(null)}
            onDone={(text, emoji) => addSticker({ kind: "slider", text, sliderEmoji: emoji })}
          />
        )}
        {tool === "question" && (
          <QuestionSheet
            onClose={() => setTool(null)}
            onDone={(text) => addSticker({ kind: "question", text, background: "#FFFFFF", color: "#000000" })}
          />
        )}
        {tool === "location" && (
          <LocationSheet
            onClose={() => setTool(null)}
            onDone={(label) => addSticker({ kind: "location", label })}
          />
        )}
        {tool === "mention" && (
          <MentionSheet
            onClose={() => setTool(null)}
            onDone={(handle) => addSticker({ kind: "mention", label: handle })}
          />
        )}
        {tool === "hashtag" && (
          <HashtagSheet
            onClose={() => setTool(null)}
            onDone={(tag) => addSticker({ kind: "hashtag", label: tag })}
          />
        )}
        {tool === "countdown" && (
          <CountdownSheet
            onClose={() => setTool(null)}
            onDone={(title, iso) => addSticker({ kind: "countdown", label: title, text: iso })}
          />
        )}
        {tool === "gif" && (
          <div className="absolute inset-x-3 bottom-3 z-10">
            <GiphyPicker
              inline
              onClose={() => setTool(null)}
              onSelect={(url) => addSticker({ kind: "gif", imageURL: url })}
            />
          </div>
        )}
      </div>

      <MusicPickerSheet open={showMusic} onOpenChange={setShowMusic} onPick={pickMusic} />
    </div>,
    document.body
  );
}

/* ------------------------------- Sheets -------------------------------- */

function SheetShell({
  title,
  onClose,
  children,
}: {
  title: string;
  onClose: () => void;
  children: React.ReactNode;
}) {
  return (
    <div className="absolute inset-0 z-20 flex flex-col justify-end bg-black/50" onClick={onClose}>
      <div
        className="space-y-3 rounded-t-2xl bg-background p-4"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between">
          <h3 className="font-display text-base font-bold">{title}</h3>
          <button onClick={onClose} className="rounded-full p-1 text-muted-foreground hover:bg-secondary">
            <X className="h-5 w-5" />
          </button>
        </div>
        {children}
      </div>
    </div>
  );
}

function TextSheet({
  onClose,
  onDone,
}: {
  onClose: () => void;
  onDone: (text: string, color: string, style: number) => void;
}) {
  const [text, setText] = useState<string>("");
  const [color, setColor] = useState<string>("#FFFFFF");
  const [style, setStyle] = useState<number>(0);
  return (
    <SheetShell title="Add text" onClose={onClose}>
      <input
        autoFocus
        value={text}
        onChange={(e) => setText(e.target.value)}
        placeholder="Type something…"
        className="w-full rounded-xl border border-border bg-secondary px-3 py-2.5 text-sm outline-none"
      />
      <div className="flex flex-wrap gap-2">
        {TEXT_COLORS.map((c) => (
          <button
            key={c}
            onClick={() => setColor(c)}
            className={cn("h-7 w-7 rounded-full border", color === c ? "ring-2 ring-foreground" : "border-border")}
            style={{ background: c }}
          />
        ))}
      </div>
      <div className="flex gap-2">
        {[0, 1, 2, 3].map((s) => (
          <button
            key={s}
            onClick={() => setStyle(s)}
            className={cn(
              "rounded-lg px-3 py-1.5 text-xs font-semibold",
              style === s ? "bg-primary text-primary-foreground" : "bg-secondary"
            )}
          >
            {["Plain", "Pill", "Outline", "Glow"][s]}
          </button>
        ))}
      </div>
      <button
        onClick={() => text.trim() && onDone(text.trim(), color, style)}
        disabled={!text.trim()}
        className="w-full rounded-full bg-primary py-2.5 text-sm font-bold text-primary-foreground disabled:opacity-50"
      >
        Add
      </button>
    </SheetShell>
  );
}

function PollSheet({
  onClose,
  onDone,
}: {
  onClose: () => void;
  onDone: (text: string, options: string[]) => void;
}) {
  const [question, setQuestion] = useState<string>("");
  const [options, setOptions] = useState<string[]>(["Yes", "No"]);
  const ready = options.filter((o) => o.trim()).length >= 2;
  return (
    <SheetShell title="Add poll" onClose={onClose}>
      <input
        autoFocus
        value={question}
        onChange={(e) => setQuestion(e.target.value)}
        placeholder="Ask a question…"
        className="w-full rounded-xl border border-border bg-secondary px-3 py-2.5 text-sm outline-none"
      />
      {options.map((opt, i) => (
        <div key={i} className="flex items-center gap-2">
          <input
            value={opt}
            onChange={(e) => setOptions((o) => o.map((x, idx) => (idx === i ? e.target.value : x)))}
            placeholder={`Option ${i + 1}`}
            className="flex-1 rounded-xl border border-border bg-secondary px-3 py-2 text-sm outline-none"
          />
          {options.length > 2 && (
            <button onClick={() => setOptions((o) => o.filter((_, idx) => idx !== i))}>
              <X className="h-4 w-4 text-muted-foreground" />
            </button>
          )}
        </div>
      ))}
      {options.length < 4 && (
        <button
          onClick={() => setOptions((o) => [...o, ""])}
          className="flex items-center gap-1.5 text-sm font-semibold text-primary"
        >
          <Plus className="h-4 w-4" /> Add option
        </button>
      )}
      <button
        onClick={() => ready && onDone(question.trim(), options.map((o) => o.trim()).filter(Boolean))}
        disabled={!ready}
        className="w-full rounded-full bg-primary py-2.5 text-sm font-bold text-primary-foreground disabled:opacity-50"
      >
        Add
      </button>
    </SheetShell>
  );
}

function SliderSheet({
  onClose,
  onDone,
}: {
  onClose: () => void;
  onDone: (text: string, emoji: string) => void;
}) {
  const [text, setText] = useState<string>("");
  const [emoji, setEmoji] = useState<string>("❤️");
  return (
    <SheetShell title="Add slider" onClose={onClose}>
      <input
        autoFocus
        value={text}
        onChange={(e) => setText(e.target.value)}
        placeholder="Slide to rate…"
        className="w-full rounded-xl border border-border bg-secondary px-3 py-2.5 text-sm outline-none"
      />
      <div className="flex flex-wrap gap-2">
        {SLIDER_EMOJIS.map((e) => (
          <button
            key={e}
            onClick={() => setEmoji(e)}
            className={cn("rounded-lg px-2 py-1 text-xl", emoji === e ? "bg-primary/20 ring-2 ring-primary" : "bg-secondary")}
          >
            {e}
          </button>
        ))}
      </div>
      <button
        onClick={() => onDone(text.trim() || "Slide to rate", emoji)}
        className="w-full rounded-full bg-primary py-2.5 text-sm font-bold text-primary-foreground"
      >
        Add
      </button>
    </SheetShell>
  );
}

function QuestionSheet({
  onClose,
  onDone,
}: {
  onClose: () => void;
  onDone: (text: string) => void;
}) {
  const [text, setText] = useState<string>("");
  return (
    <SheetShell title="Ask a question" onClose={onClose}>
      <input
        autoFocus
        value={text}
        onChange={(e) => setText(e.target.value)}
        placeholder="Ask me anything…"
        className="w-full rounded-xl border border-border bg-secondary px-3 py-2.5 text-sm outline-none"
      />
      <button
        onClick={() => onDone(text.trim() || "Ask me anything")}
        className="w-full rounded-full bg-primary py-2.5 text-sm font-bold text-primary-foreground"
      >
        Add
      </button>
    </SheetShell>
  );
}

function LocationSheet({
  onClose,
  onDone,
}: {
  onClose: () => void;
  onDone: (label: string) => void;
}) {
  const [label, setLabel] = useState<string>("");
  const [locating, setLocating] = useState<boolean>(false);
  const detect = async (): Promise<void> => {
    setLocating(true);
    try {
      setLabel(await currentPlaceName());
    } catch {
      toast.error("Couldn't get your location.");
    } finally {
      setLocating(false);
    }
  };
  return (
    <SheetShell title="Add location" onClose={onClose}>
      <div className="flex items-center gap-2">
        <input
          value={label}
          onChange={(e) => setLabel(e.target.value)}
          placeholder="Place name…"
          className="flex-1 rounded-xl border border-border bg-secondary px-3 py-2.5 text-sm outline-none"
        />
        <button
          onClick={() => void detect()}
          className="flex h-10 items-center gap-1.5 rounded-xl bg-secondary px-3 text-sm font-semibold"
        >
          {locating ? <Loader2 className="h-4 w-4 animate-spin" /> : <MapPin className="h-4 w-4" />}
        </button>
      </div>
      <button
        onClick={() => label.trim() && onDone(label.trim())}
        disabled={!label.trim()}
        className="w-full rounded-full bg-primary py-2.5 text-sm font-bold text-primary-foreground disabled:opacity-50"
      >
        Add
      </button>
    </SheetShell>
  );
}

function MentionSheet({
  onClose,
  onDone,
}: {
  onClose: () => void;
  onDone: (handle: string) => void;
}) {
  const [query, setQuery] = useState<string>("");
  const results = useQuery({
    queryKey: ["mention-search", query],
    queryFn: () => searchProfiles(query),
    enabled: query.trim().length > 0,
  });
  const people = results.data ?? [];
  return (
    <SheetShell title="Mention someone" onClose={onClose}>
      <div className="flex items-center gap-2 rounded-full bg-secondary px-3 py-2">
        <Search className="h-4 w-4 text-muted-foreground" />
        <input
          autoFocus
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search people"
          className="flex-1 bg-transparent text-sm outline-none"
        />
      </div>
      <div className="max-h-52 space-y-0.5 overflow-y-auto">
        {people.map((p) => (
          <button
            key={p.user_id}
            onClick={() => onDone(p.username)}
            className="flex w-full items-center gap-2.5 rounded-xl p-1.5 text-left hover:bg-secondary"
          >
            <Avatar url={p.profile_image_url} name={p.username} size={32} />
            <span className="text-sm font-semibold">@{p.username}</span>
          </button>
        ))}
        {query.trim() && (
          <button
            onClick={() => onDone(query.trim().replace(/^@/, ""))}
            className="flex w-full items-center gap-2.5 rounded-xl p-2 text-left text-sm font-semibold text-primary hover:bg-secondary"
          >
            <AtSign className="h-4 w-4" /> Mention "@{query.trim().replace(/^@/, "")}"
          </button>
        )}
      </div>
    </SheetShell>
  );
}

function HashtagSheet({
  onClose,
  onDone,
}: {
  onClose: () => void;
  onDone: (tag: string) => void;
}) {
  const [tag, setTag] = useState<string>("");
  const clean = tag.trim().replace(/#/g, "");
  return (
    <SheetShell title="Add hashtag" onClose={onClose}>
      <div className="flex items-center gap-2 rounded-xl border border-border bg-secondary px-3 py-2.5">
        <Hash className="h-4 w-4 text-muted-foreground" />
        <input
          autoFocus
          value={tag}
          onChange={(e) => setTag(e.target.value)}
          placeholder="YOURTAG"
          className="flex-1 bg-transparent text-sm uppercase outline-none"
        />
      </div>
      <button
        onClick={() => clean && onDone(clean)}
        disabled={!clean}
        className="w-full rounded-full bg-primary py-2.5 text-sm font-bold text-primary-foreground disabled:opacity-50"
      >
        Add
      </button>
    </SheetShell>
  );
}

function CountdownSheet({
  onClose,
  onDone,
}: {
  onClose: () => void;
  onDone: (title: string, iso: string) => void;
}) {
  const [title, setTitle] = useState<string>("");
  const [when, setWhen] = useState<string>(() => {
    const d = new Date(Date.now() + 24 * 60 * 60 * 1000);
    d.setMinutes(d.getMinutes() - d.getTimezoneOffset());
    return d.toISOString().slice(0, 16);
  });
  const valid = title.trim().length > 0 && !Number.isNaN(Date.parse(when));
  return (
    <SheetShell title="Add countdown" onClose={onClose}>
      <input
        autoFocus
        value={title}
        onChange={(e) => setTitle(e.target.value)}
        placeholder="What are you counting down to?"
        className="w-full rounded-xl border border-border bg-secondary px-3 py-2.5 text-sm outline-none"
      />
      <input
        type="datetime-local"
        value={when}
        onChange={(e) => setWhen(e.target.value)}
        className="w-full rounded-xl border border-border bg-secondary px-3 py-2.5 text-sm outline-none"
      />
      <button
        onClick={() => valid && onDone(title.trim(), new Date(when).toISOString())}
        disabled={!valid}
        className="w-full rounded-full bg-primary py-2.5 text-sm font-bold text-primary-foreground disabled:opacity-50"
      >
        Add
      </button>
    </SheetShell>
  );
}
