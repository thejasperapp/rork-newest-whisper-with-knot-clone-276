import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useQueryClient } from "@tanstack/react-query";
import {
  ArrowLeft,
  ImagePlus,
  X,
  Grid3X3,
  MoveLeft,
  MoveRight,
  Loader2,
  Camera,
  Crop,
  Heart,
  ChevronRight,
  MapPin,
  Music,
  UserRound,
  Sparkles,
  Accessibility,
  MessageCircle,
} from "lucide-react";
import { toast } from "sonner";

import { PostModeSelector } from "@/components/PostModeSelector";
import { canPostGrid } from "@/lib/accountAccess";
import { Avatar } from "@/components/Avatar";
import { cn } from "@/lib/utils";
import { createPost, uploadMedia } from "@/lib/api";
import { useAuth } from "@/hooks/useAuth";
import { MusicPickerSheet } from "@/components/MusicPickerSheet";
import { encodePostMeta } from "@/lib/postMeta";
import type { MusicTrack } from "@/lib/music";

const MAX_FILES = 10;
const ASPECT_RATIO = 4 / 5;

interface GridFile {
  file: File;
  preview: string;
  /** Per-photo filter id — baked into the uploaded image at publish. */
  filter: string;
}

type Step = "select" | "reorder" | "edit" | "caption";

/** Instagram's classic filter rack — CSS approximations baked via canvas. */
const FILTERS: { id: string; label: string; css: string }[] = [
  { id: "normal", label: "Normal", css: "" },
  { id: "clarendon", label: "Clarendon", css: "contrast(1.2) saturate(1.35)" },
  { id: "gingham", label: "Gingham", css: "brightness(1.05) hue-rotate(-10deg) sepia(0.06)" },
  { id: "moon", label: "Moon", css: "grayscale(1) contrast(1.1) brightness(1.1)" },
  { id: "lark", label: "Lark", css: "contrast(0.9) brightness(1.1) saturate(1.1)" },
  { id: "reyes", label: "Reyes", css: "sepia(0.22) brightness(1.1) contrast(0.85) saturate(0.75)" },
  { id: "juno", label: "Juno", css: "contrast(1.15) saturate(1.4) sepia(0.08)" },
  { id: "slumber", label: "Slumber", css: "saturate(0.66) brightness(1.05) sepia(0.05)" },
  { id: "aden", label: "Aden", css: "hue-rotate(-20deg) contrast(0.9) saturate(0.85) brightness(1.2)" },
];

function filterCss(id: string): string {
  return FILTERS.find((f) => f.id === id)?.css ?? "";
}

/** Draws the file through its CSS filter on a canvas so the FILTERED image
 *  is what actually uploads — every platform sees the same photo. */
async function bakeFilter(file: File, css: string): Promise<File> {
  if (!css) return file;
  const url = URL.createObjectURL(file);
  try {
    const img = await new Promise<HTMLImageElement>((resolve, reject) => {
      const el = new Image();
      el.onload = () => resolve(el);
      el.onerror = () => reject(new Error("image-load"));
      el.src = url;
    });
    const canvas = document.createElement("canvas");
    canvas.width = img.naturalWidth;
    canvas.height = img.naturalHeight;
    const ctx = canvas.getContext("2d");
    if (!ctx) return file;
    ctx.filter = css;
    ctx.drawImage(img, 0, 0);
    const blob = await new Promise<Blob | null>((resolve) =>
      canvas.toBlob(resolve, "image/jpeg", 0.92)
    );
    if (!blob) return file;
    return new File([blob], file.name.replace(/\.[^.]+$/, "") + "-edit.jpg", {
      type: "image/jpeg",
    });
  } catch {
    return file;
  } finally {
    URL.revokeObjectURL(url);
  }
}

export default function GridCompose() {
  const { user, profile } = useAuth();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const fileRef = useRef<HTMLInputElement>(null);

  const [step, setStep] = useState<Step>("select");
  const [files, setFiles] = useState<GridFile[]>([]);
  const [selectedIndex, setSelectedIndex] = useState<number>(0);
  const [caption, setCaption] = useState<string>("");
  const [busy, setBusy] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  // Instagram-style post details.
  const [tagged, setTagged] = useState<string[]>([]);
  const [location, setLocation] = useState<string>("");
  const [music, setMusic] = useState<MusicTrack | null>(null);
  const [showCounts, setShowCounts] = useState<boolean>(true);
  const [altText, setAltText] = useState<string>("");
  const [commentsOff, setCommentsOff] = useState<boolean>(false);

  const handlePick = (e: React.ChangeEvent<HTMLInputElement>): void => {
    const picked = Array.from(e.target.files ?? []);
    if (picked.length === 0) return;
    const remaining = MAX_FILES - files.length;
    if (remaining <= 0) {
      toast(`You can only add up to ${MAX_FILES} photos`);
      return;
    }
    const next = picked.slice(0, remaining).map((file) => ({
      file,
      preview: URL.createObjectURL(file),
      filter: "normal",
    }));
    setFiles((prev) => [...prev, ...next]);
    e.target.value = "";
  };

  const removeAt = (i: number): void => {
    URL.revokeObjectURL(files[i]!.preview);
    setFiles((prev) => {
      const next = prev.filter((_, idx) => idx !== i);
      if (selectedIndex >= next.length) {
        setSelectedIndex(Math.max(0, next.length - 1));
      }
      return next;
    });
  };

  const move = (i: number, direction: -1 | 1): void => {
    const j = i + direction;
    if (j < 0 || j >= files.length) return;
    setFiles((prev) => {
      const next = [...prev];
      [next[i], next[j]] = [next[j]!, next[i]!];
      return next;
    });
    setSelectedIndex(j);
  };

  const setFilterAt = (i: number, filter: string): void => {
    setFiles((prev) => prev.map((f, idx) => (idx === i ? { ...f, filter } : f)));
  };

  const submit = async (): Promise<void> => {
    if (!user || !profile) {
      setError("Set up your profile first.");
      return;
    }
    if (!canPostGrid(profile)) {
      setError("Grid publishing requires approved creator access.");
      return;
    }
    if (files.length < 1) {
      setError("Add at least one photo.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const urls: string[] = [];
      for (const { file, filter } of files) {
        const baked = await bakeFilter(file, filterCss(filter));
        urls.push(await uploadMedia(baked, user.id));
      }
      // Tag/location/music/count-visibility ride the caption as compact post
      // meta — the same embed regular thread posts use, no schema change.
      const encodedCaption = encodePostMeta(
        {
          tagged,
          location: location.trim() || null,
          music: music
            ? {
                id: music.id,
                title: music.title,
                artist: music.artist,
                artworkURL: music.artworkURL,
                previewURL: music.previewURL,
              }
            : null,
          hideCounts: showCounts ? undefined : true,
          altText: altText.trim() || undefined,
          commentsOff: commentsOff ? true : undefined,
        },
        caption.trim()
      );
      await createPost({
        userId: user.id,
        username: profile.username,
        caption: encodedCaption,
        mediaUrls: urls,
        kind: "grid",
      });
      queryClient.invalidateQueries({ queryKey: ["feed"] });
      queryClient.invalidateQueries({ queryKey: ["my-posts"] });
      toast("Grid post shared");
      navigate("/");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't publish grid.");
      toast("Couldn't publish grid");
    } finally {
      setBusy(false);
    }
  };

  const username = profile?.username ?? "you";

  useEffect(() => {
    return () => {
      for (const { preview } of files) {
        URL.revokeObjectURL(preview);
      }
    };
  }, []);

  const canProceedToReorder = files.length >= 1;
  const canShare = files.length >= 1 && !busy;

  const stepIndex =
    step === "select" ? 0 : step === "reorder" ? 1 : step === "edit" ? 2 : 3;

  return (
    <div className="flex min-h-[100dvh] flex-col bg-background">
      {/* Header */}
      <header className="sticky top-0 z-30 flex h-14 items-center justify-between rounded-b-[22px] border-b border-border bg-background/95 px-4 backdrop-blur">
        <button
          onClick={() => {
            if (step === "select") navigate(-1);
            else if (step === "reorder") setStep("select");
            else if (step === "edit") setStep("reorder");
            else setStep("edit");
          }}
          className="flex items-center gap-1 text-[15px] text-foreground transition-colors hover:text-muted-foreground"
        >
          <ArrowLeft className="h-5 w-5" />
          {step === "select" ? "Cancel" : "Back"}
        </button>

        {/* Centered title + step indicator (IG "New post" header) */}
        <div className="flex flex-col items-center gap-1">
          <span className="text-[16px] font-bold">New post</span>
          <div className="flex items-center gap-1.5">
            {(["select", "reorder", "edit", "caption"] as Step[]).map((s, i) => (
              <div
                key={s}
                className={cn(
                  "h-1 rounded-full transition-all",
                  i === stepIndex ? "w-5 bg-foreground" : i < stepIndex ? "w-1 bg-foreground/40" : "w-1 bg-border"
                )}
              />
            ))}
          </div>
        </div>

        <div className="flex items-center gap-2">
          {step === "caption" ? (
            <Grid3X3 className="h-4 w-4 text-emerald-500" />
          ) : (
            <button
              onClick={() => {
                if (step === "select" && canProceedToReorder) setStep("reorder");
                else if (step === "reorder") setStep("edit");
                else if (step === "edit") setStep("caption");
              }}
              disabled={step === "select" && !canProceedToReorder}
              className="rounded-full bg-foreground px-4 py-1.5 text-sm font-bold text-background transition-opacity disabled:opacity-40"
            >
              Next
            </button>
          )}
        </div>
      </header>

      <div className="flex justify-center px-4 py-3"><PostModeSelector value="grid" canLeave={() => !busy && ((!caption.trim() && files.length === 0 && tagged.length === 0 && !location && !music && !altText) || window.confirm("Switch format and discard this Grid draft? Stay here to keep your edits and photos."))} /></div>
      {/* Step content */}
      {step === "select" && (
        <SelectStep
          files={files}
          fileRef={fileRef}
          onPick={handlePick}
          onRemove={removeAt}
          selectedIndex={selectedIndex}
          onSelect={setSelectedIndex}
        />
      )}

      {step === "reorder" && (
        <ReorderStep
          files={files}
          fileRef={fileRef}
          onPick={handlePick}
          onRemove={removeAt}
          onMove={move}
          selectedIndex={selectedIndex}
          onSelect={setSelectedIndex}
        />
      )}

      {step === "edit" && (
        <EditStep
          files={files}
          selectedIndex={selectedIndex}
          onSelect={setSelectedIndex}
          onSetFilter={setFilterAt}
        />
      )}

      {step === "caption" && (
        <DetailsStep
          files={files}
          caption={caption}
          setCaption={setCaption}
          username={username}
          avatarUrl={profile?.profile_image_url ?? null}
          tagged={tagged}
          setTagged={setTagged}
          location={location}
          setLocation={setLocation}
          music={music}
          setMusic={setMusic}
          showCounts={showCounts}
          setShowCounts={setShowCounts}
          altText={altText}
          setAltText={setAltText}
          commentsOff={commentsOff}
          setCommentsOff={setCommentsOff}
          error={error}
          busy={busy}
          canShare={canShare}
          onSubmit={submit}
        />
      )}

      <input
        ref={fileRef}
        type="file"
        accept="image/*"
        multiple
        className="hidden"
        onChange={handlePick}
      />
    </div>
  );
}

// ---------------------------------------------------------------------------
// Step 1 — Select photos (image-first, full-bleed preview)
// ---------------------------------------------------------------------------

function SelectStep({
  files,
  fileRef,
  onPick,
  onRemove,
  selectedIndex,
  onSelect,
}: {
  files: GridFile[];
  fileRef: React.RefObject<HTMLInputElement | null>;
  onPick: (e: React.ChangeEvent<HTMLInputElement>) => void;
  onRemove: (i: number) => void;
  selectedIndex: number;
  onSelect: (i: number) => void;
}) {
  if (files.length === 0) {
    return (
      <div className="flex flex-1 flex-col items-center justify-center p-6">
        <button
          onClick={() => fileRef.current?.click()}
          className="flex w-full max-w-md flex-col items-center gap-4 rounded-[28px] border-2 border-dashed border-border bg-secondary/30 p-12 transition-colors hover:bg-secondary/60"
        >
          <div className="flex h-20 w-20 items-center justify-center rounded-3xl bg-background shadow-sm">
            <ImagePlus className="h-10 w-10 text-muted-foreground" />
          </div>
          <div className="text-center">
            <p className="text-[17px] font-bold">Select photos</p>
            <p className="mt-1 text-[14px] text-muted-foreground">
              Choose up to {MAX_FILES} images for your grid post
            </p>
          </div>
          <span className="flex items-center gap-1.5 rounded-full bg-foreground px-5 py-2.5 text-sm font-bold text-background">
            <Camera className="h-4 w-4" />
            Browse
          </span>
        </button>
      </div>
    );
  }

  return (
    <div className="flex flex-1 flex-col">
      {/* Main preview — 4:5 aspect ratio, full width */}
      <div className="relative w-full overflow-hidden bg-black" style={{ aspectRatio: ASPECT_RATIO }}>
        <img
          src={files[selectedIndex]?.preview}
          alt=""
          className="h-full w-full object-cover"
          draggable={false}
        />
        {/* Photo counter badge */}
        {files.length > 1 && (
          <div className="absolute right-3 top-3 rounded-full bg-black/60 px-2.5 py-1 text-[12px] font-bold text-white backdrop-blur">
            {selectedIndex + 1} / {files.length}
          </div>
        )}
        {/* Remove button */}
        <button
          onClick={() => onRemove(selectedIndex)}
          className="absolute left-3 top-3 flex h-9 w-9 items-center justify-center rounded-full bg-black/60 text-white backdrop-blur transition-transform active:scale-90"
        >
          <X className="h-4 w-4" />
        </button>
      </div>

      {/* Thumbnail strip */}
      <div className="border-t border-border p-3">
        <div className="flex gap-2 overflow-x-auto">
          {files.map((f, i) => (
            <div
              key={f.preview}
              className={cn(
                "relative h-16 w-16 shrink-0 cursor-pointer overflow-hidden rounded-xl border-2 transition-all",
                i === selectedIndex ? "border-emerald-500" : "border-transparent opacity-70"
              )}
              onClick={() => onSelect(i)}
            >
              <img src={f.preview} alt="" className="h-full w-full object-cover" draggable={false} />
            </div>
          ))}
          {files.length < MAX_FILES && (
            <button
              onClick={() => fileRef.current?.click()}
              className="flex h-16 w-16 shrink-0 items-center justify-center rounded-xl border-2 border-dashed border-border bg-secondary/30 transition-colors hover:bg-secondary/60"
            >
              <ImagePlus className="h-6 w-6 text-muted-foreground" />
            </button>
          )}
        </div>
        <p className="mt-2 text-center text-xs text-muted-foreground">
          {files.length} of {MAX_FILES} photos selected
        </p>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Step 2 — Reorder (3-column grid with drag arrows)
// ---------------------------------------------------------------------------

function ReorderStep({
  files,
  fileRef,
  onPick,
  onRemove,
  onMove,
  selectedIndex,
  onSelect,
}: {
  files: GridFile[];
  fileRef: React.RefObject<HTMLInputElement | null>;
  onPick: (e: React.ChangeEvent<HTMLInputElement>) => void;
  onRemove: (i: number) => void;
  onMove: (i: number, dir: -1 | 1) => void;
  selectedIndex: number;
  onSelect: (i: number) => void;
}) {
  return (
    <div className="flex flex-1 flex-col p-4">
      <div className="mb-4 flex items-center gap-2">
        <Crop className="h-5 w-5 text-emerald-500" />
        <div>
          <h2 className="text-lg font-bold">Reorder your photos</h2>
          <p className="text-sm text-muted-foreground">
            Tap to select, use arrows to reorder. First photo is the cover.
          </p>
        </div>
      </div>

      {/* Large preview of selected photo */}
      <div
        className="relative mb-4 w-full overflow-hidden rounded-2xl border border-border bg-secondary"
        style={{ aspectRatio: ASPECT_RATIO }}
      >
        <img
          src={files[selectedIndex]?.preview}
          alt=""
          className="h-full w-full object-cover"
          draggable={false}
        />
        <div className="absolute bottom-3 left-1/2 flex -translate-x-1/2 gap-1.5">
          {files.map((_, i) => (
            <span
              key={i}
              className={cn(
                "h-1.5 rounded-full transition-all",
                i === selectedIndex ? "w-4 bg-white" : "w-1.5 bg-white/50"
              )}
            />
          ))}
        </div>
      </div>

      {/* 3-column reorderable grid */}
      <div className="grid grid-cols-3 gap-2">
        {files.map((f, i) => (
          <div
            key={f.preview}
            className={cn(
              "group relative aspect-square cursor-pointer overflow-hidden rounded-xl border-2 transition-all",
              i === selectedIndex ? "border-emerald-500" : "border-transparent hover:border-border"
            )}
            onClick={() => onSelect(i)}
          >
            <img src={f.preview} alt="" className="h-full w-full object-cover" draggable={false} />

            {/* Order number badge */}
            <div className="absolute left-1 top-1 flex h-5 w-5 items-center justify-center rounded-full bg-black/60 text-[10px] font-bold text-white">
              {i + 1}
            </div>

            {/* Hover controls */}
            <div className="absolute inset-0 flex items-center justify-center gap-1 bg-black/40 opacity-0 transition-opacity group-hover:opacity-100">
              <button
                onClick={(e) => { e.stopPropagation(); onMove(i, -1); }}
                disabled={i === 0}
                className="flex h-7 w-7 items-center justify-center rounded-full bg-white/90 text-black disabled:opacity-30"
              >
                <MoveLeft className="h-3.5 w-3.5" />
              </button>
              <button
                onClick={(e) => { e.stopPropagation(); onMove(i, 1); }}
                disabled={i === files.length - 1}
                className="flex h-7 w-7 items-center justify-center rounded-full bg-white/90 text-black disabled:opacity-30"
              >
                <MoveRight className="h-3.5 w-3.5" />
              </button>
              <button
                onClick={(e) => { e.stopPropagation(); onRemove(i); }}
                className="flex h-7 w-7 items-center justify-center rounded-full bg-red-500/90 text-white"
              >
                <X className="h-3.5 w-3.5" />
              </button>
            </div>
          </div>
        ))}
        {files.length < MAX_FILES && (
          <button
            onClick={() => fileRef.current?.click()}
            className="flex aspect-square items-center justify-center rounded-xl border-2 border-dashed border-border bg-secondary/30 transition-colors hover:bg-secondary/60"
          >
            <ImagePlus className="h-6 w-6 text-muted-foreground" />
          </button>
        )}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Step 3 — Edit (Instagram's filter rack — per photo, baked at publish)
// ---------------------------------------------------------------------------

function EditStep({
  files,
  selectedIndex,
  onSelect,
  onSetFilter,
}: {
  files: GridFile[];
  selectedIndex: number;
  onSelect: (i: number) => void;
  onSetFilter: (i: number, filter: string) => void;
}) {
  const current = files[selectedIndex];
  if (!current) return null;
  return (
    <div className="flex flex-1 flex-col">
      {/* Filtered preview */}
      <div
        className="relative w-full overflow-hidden bg-black"
        style={{ aspectRatio: ASPECT_RATIO }}
      >
        <img
          src={current.preview}
          alt=""
          className="h-full w-full object-cover"
          style={{ filter: filterCss(current.filter) || undefined }}
          draggable={false}
        />
        {files.length > 1 && (
          <div className="absolute right-3 top-3 rounded-full bg-black/60 px-2.5 py-1 text-[12px] font-bold text-white backdrop-blur">
            {selectedIndex + 1} / {files.length}
          </div>
        )}
        {current.filter !== "normal" && (
          <div className="absolute left-3 top-3 flex items-center gap-1 rounded-full bg-black/60 px-2.5 py-1 text-[12px] font-bold text-white backdrop-blur">
            <Sparkles className="h-3 w-3" />
            {FILTERS.find((f) => f.id === current.filter)?.label}
          </div>
        )}
      </div>

      {/* Photo switcher — each thumb previews ITS OWN filter */}
      {files.length > 1 && (
        <div className="flex gap-2 overflow-x-auto border-t border-border p-3">
          {files.map((f, i) => (
            <button
              key={f.preview}
              onClick={() => onSelect(i)}
              className={cn(
                "relative h-14 w-14 shrink-0 overflow-hidden rounded-xl border-2 transition-all",
                i === selectedIndex
                  ? "border-emerald-500"
                  : "border-transparent opacity-70"
              )}
            >
              <img
                src={f.preview}
                alt=""
                className="h-full w-full object-cover"
                style={{ filter: filterCss(f.filter) || undefined }}
                draggable={false}
              />
            </button>
          ))}
        </div>
      )}

      {/* The filter rack */}
      <div className="border-t border-border p-3">
        <p className="mb-2 px-1 text-[12px] font-bold uppercase tracking-wide text-muted-foreground">
          Filters
        </p>
        <div className="flex gap-3 overflow-x-auto pb-1">
          {FILTERS.map((f) => (
            <button
              key={f.id}
              onClick={() => onSetFilter(selectedIndex, f.id)}
              className="flex shrink-0 flex-col items-center gap-1.5"
            >
              <span
                className={cn(
                  "block h-[72px] w-[72px] overflow-hidden rounded-xl border-2 transition-colors",
                  current.filter === f.id
                    ? "border-foreground"
                    : "border-transparent"
                )}
              >
                <img
                  src={current.preview}
                  alt=""
                  className="h-full w-full object-cover"
                  style={{ filter: f.css || undefined }}
                  draggable={false}
                />
              </span>
              <span
                className={cn(
                  "text-[11px]",
                  current.filter === f.id
                    ? "font-bold text-foreground"
                    : "text-muted-foreground"
                )}
              >
                {f.label}
              </span>
            </button>
          ))}
        </div>
        <p className="mt-2 text-center text-xs text-muted-foreground">
          Filters bake into the photo when you share — every platform sees the
          same image.
        </p>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Step 4 — "New post" details (Instagram-style: caption up top, then Tag
// people / Add location / Add music rows, Accessibility + Advanced settings,
// and one big Share button pinned to the bottom)
// ---------------------------------------------------------------------------

function DetailRow({
  icon,
  label,
  value,
  onClick,
}: {
  icon: React.ReactNode;
  label: string;
  value?: string;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className="flex w-full items-center gap-3.5 px-4 py-3.5 text-left transition-colors hover:bg-secondary/40"
    >
      <span className="text-foreground">{icon}</span>
      <span className="min-w-0 flex-1 truncate text-[16px]">{label}</span>
      {value && (
        <span className="max-w-[40%] truncate text-[13px] text-muted-foreground">
          {value}
        </span>
      )}
      <ChevronRight className="h-5 w-5 shrink-0 text-muted-foreground" />
    </button>
  );
}

function DetailsStep({
  files,
  caption,
  setCaption,
  username,
  avatarUrl,
  tagged,
  setTagged,
  location,
  setLocation,
  music,
  setMusic,
  showCounts,
  setShowCounts,
  altText,
  setAltText,
  commentsOff,
  setCommentsOff,
  error,
  busy,
  canShare,
  onSubmit,
}: {
  files: GridFile[];
  caption: string;
  setCaption: (v: string) => void;
  username: string;
  avatarUrl: string | null;
  tagged: string[];
  setTagged: (v: string[]) => void;
  location: string;
  setLocation: (v: string) => void;
  music: MusicTrack | null;
  setMusic: (v: MusicTrack | null) => void;
  showCounts: boolean;
  setShowCounts: (v: boolean) => void;
  altText: string;
  setAltText: (v: string) => void;
  commentsOff: boolean;
  setCommentsOff: (v: boolean) => void;
  error: string | null;
  busy: boolean;
  canShare: boolean;
  onSubmit: () => void;
}) {
  const [tagOpen, setTagOpen] = useState<boolean>(false);
  const [tagDraft, setTagDraft] = useState<string>("");
  const [locationOpen, setLocationOpen] = useState<boolean>(false);
  const [musicOpen, setMusicOpen] = useState<boolean>(false);
  const [accessibilityOpen, setAccessibilityOpen] = useState<boolean>(false);

  const addTag = (): void => {
    const clean = tagDraft
      .trim()
      .replace(/^@/, "")
      .replace(/[^a-zA-Z0-9._]/g, "");
    if (!clean) return;
    if (!tagged.includes(clean) && tagged.length < 20) {
      setTagged([...tagged, clean]);
    }
    setTagDraft("");
  };

  return (
    <div className="mx-auto flex w-full max-w-xl flex-1 flex-col">
      <div className="flex-1 pb-4">
        {/* Media preview — centered square, like IG's New post screen */}
        <div className="flex justify-center px-4 pt-4">
          <div
            className="relative w-full max-w-[300px] overflow-hidden rounded-xl bg-secondary shadow-sm"
            style={{ aspectRatio: ASPECT_RATIO }}
          >
            <img
              src={files[0]?.preview}
              alt=""
              className="h-full w-full object-cover"
              style={{ filter: filterCss(files[0]?.filter ?? "normal") || undefined }}
              draggable={false}
            />
            {files.length > 1 && (
              <span className="absolute right-2 top-2 rounded-full bg-black/60 px-2 py-0.5 text-[11px] font-bold text-white backdrop-blur">
                1 / {files.length}
              </span>
            )}
          </div>
        </div>

        {/* Caption — borderless, IG-style */}
        <div className="flex items-start gap-3 px-4 pb-3 pt-4">
          <Avatar url={avatarUrl} name={username} size={34} />
          <textarea
            value={caption}
            onChange={(e) => setCaption(e.target.value)}
            placeholder="Write a caption…"
            rows={3}
            maxLength={2200}
            className="min-h-[68px] flex-1 resize-none bg-transparent pt-1.5 text-[16px] leading-snug outline-none placeholder:text-muted-foreground"
          />
        </div>

        <div className="divide-y divide-border border-y border-border">
          {/* Tag people */}
          <div>
            <DetailRow
              icon={<UserRound className="h-5 w-5" />}
              label="Tag people"
              value={tagged.length > 0 ? `${tagged.length} tagged` : undefined}
              onClick={() => setTagOpen((v) => !v)}
            />
            {(tagOpen || tagged.length > 0) && (
              <div className="px-4 pb-3">
                {tagged.length > 0 && (
                  <div className="mb-2 flex flex-wrap gap-1.5">
                    {tagged.map((t) => (
                      <button
                        key={t}
                        onClick={() => setTagged(tagged.filter((x) => x !== t))}
                        className="flex items-center gap-1 rounded-full bg-secondary px-3 py-1.5 text-[13px] font-semibold transition-colors hover:bg-secondary/70"
                      >
                        @{t}
                        <X className="h-3 w-3 text-muted-foreground" />
                      </button>
                    ))}
                  </div>
                )}
                {tagOpen && (
                  <div className="flex items-center gap-2">
                    <input
                      value={tagDraft}
                      onChange={(e) => setTagDraft(e.target.value)}
                      onKeyDown={(e) => {
                        if (e.key === "Enter" || e.key === ",") {
                          e.preventDefault();
                          addTag();
                        }
                      }}
                      placeholder="@username"
                      autoFocus
                      className="h-10 flex-1 rounded-full border border-border bg-card px-4 text-[14px] outline-none focus:border-foreground/40"
                    />
                    <button
                      onClick={addTag}
                      disabled={!tagDraft.trim()}
                      className="rounded-full bg-foreground px-4 py-2 text-[13px] font-bold text-background disabled:opacity-40"
                    >
                      Add
                    </button>
                  </div>
                )}
              </div>
            )}
          </div>

          {/* Add location */}
          <div>
            <DetailRow
              icon={<MapPin className="h-5 w-5" />}
              label="Add location"
              value={location.trim() || undefined}
              onClick={() => setLocationOpen((v) => !v)}
            />
            {locationOpen && (
              <div className="flex items-center gap-2 px-4 pb-3">
                <input
                  value={location}
                  onChange={(e) => setLocation(e.target.value)}
                  placeholder="Add a place…"
                  autoFocus
                  className="h-10 flex-1 rounded-full border border-border bg-card px-4 text-[14px] outline-none focus:border-foreground/40"
                />
                {location.trim() && (
                  <button
                    onClick={() => setLocation("")}
                    aria-label="Clear location"
                    className="flex h-9 w-9 items-center justify-center rounded-full bg-secondary"
                  >
                    <X className="h-4 w-4" />
                  </button>
                )}
              </div>
            )}
          </div>

          {/* Add music */}
          <div>
            <DetailRow
              icon={<Music className="h-5 w-5" />}
              label="Add music"
              value={music ? `${music.title} · ${music.artist}` : undefined}
              onClick={() => setMusicOpen(true)}
            />
            {music && (
              <div className="px-4 pb-3">
                <button
                  onClick={() => setMusic(null)}
                  className="flex max-w-full items-center gap-1.5 rounded-full bg-secondary px-3 py-1.5 text-[13px] font-semibold transition-colors hover:bg-secondary/70"
                >
                  <Music className="h-3.5 w-3.5 shrink-0" />
                  <span className="truncate">
                    {music.title} · {music.artist}
                  </span>
                  <X className="h-3 w-3 shrink-0 text-muted-foreground" />
                </button>
              </div>
            )}
          </div>

          {/* Accessibility — alt text for screen readers (IG advanced grammar) */}
          <div>
            <DetailRow
              icon={<Accessibility className="h-5 w-5" />}
              label="Accessibility"
              value={altText.trim() ? "Alt text added" : undefined}
              onClick={() => setAccessibilityOpen((v) => !v)}
            />
            {accessibilityOpen && (
              <div className="px-4 pb-3">
                <textarea
                  value={altText}
                  onChange={(e) => setAltText(e.target.value)}
                  placeholder="Write alt text…"
                  rows={2}
                  maxLength={500}
                  className="w-full resize-none rounded-xl border border-border bg-card px-3 py-2 text-[14px] outline-none focus:border-foreground/40"
                />
                <p className="mt-1 text-[12px] text-muted-foreground">
                  Alt text describes your photos for people with visual
                  impairments.
                </p>
              </div>
            )}
          </div>

          {/* Advanced settings — like counts + commenting */}
          <div className="flex items-center justify-between px-4 py-3.5">
            <span className="flex items-center gap-3.5 text-[16px]">
              <Heart className="h-5 w-5" />
              Like and view count
            </span>
            <button
              role="switch"
              aria-checked={showCounts}
              onClick={() => setShowCounts(!showCounts)}
              className={cn(
                "relative h-[30px] w-[50px] shrink-0 rounded-full transition-colors",
                showCounts ? "bg-emerald-500" : "bg-border"
              )}
            >
              <span
                className={cn(
                  "absolute top-[3px] h-6 w-6 rounded-full bg-white shadow transition-transform",
                  showCounts ? "translate-x-[23px]" : "translate-x-[3px]"
                )}
              />
            </button>
          </div>

          <div className="flex items-center justify-between px-4 py-3.5">
            <span className="flex items-center gap-3.5 text-[16px]">
              <MessageCircle className="h-5 w-5" />
              Turn off commenting
            </span>
            <button
              role="switch"
              aria-checked={commentsOff}
              onClick={() => setCommentsOff(!commentsOff)}
              className={cn(
                "relative h-[30px] w-[50px] shrink-0 rounded-full transition-colors",
                commentsOff ? "bg-emerald-500" : "bg-border"
              )}
            >
              <span
                className={cn(
                  "absolute top-[3px] h-6 w-6 rounded-full bg-white shadow transition-transform",
                  commentsOff ? "translate-x-[23px]" : "translate-x-[3px]"
                )}
              />
            </button>
          </div>
        </div>

        <p className="px-4 pt-2 text-[12px] text-muted-foreground">
          {commentsOff
            ? "Nobody can comment on this post."
            : showCounts
              ? "Like and view counts will be visible on this post."
              : "Only you will see the total number of likes on this post."}
        </p>

        {error && (
          <p className="mx-4 mt-3 rounded-xl bg-destructive/15 px-3 py-2 text-sm text-destructive">
            {error}
          </p>
        )}
      </div>

      {/* Share — the one big IG-blue action */}
      <div className="sticky bottom-0 border-t border-border bg-background/95 p-3 backdrop-blur">
        <button
          onClick={onSubmit}
          disabled={busy || !canShare}
          className="flex w-full items-center justify-center gap-2 rounded-xl bg-[#0095F6] py-3.5 text-[15px] font-bold text-white transition-all hover:bg-[#1877F2] disabled:opacity-40 active:scale-[0.98]"
        >
          {busy ? (
            <>
              <Loader2 className="h-4 w-4 animate-spin" /> Sharing…
            </>
          ) : (
            "Share"
          )}
        </button>
      </div>

      <MusicPickerSheet
        open={musicOpen}
        onOpenChange={setMusicOpen}
        onPick={(track) => {
          setMusic(track);
          setMusicOpen(false);
        }}
      />
    </div>
  );
}
