import { memo, useEffect, useState } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { X, Trash2, Smile, MapPin, Music, Loader2 } from "lucide-react";
import { toast } from "sonner";

import { cn } from "@/lib/utils";
import { useAuth } from "@/hooks/useAuth";
import { ThoughtBubble } from "@/components/ThoughtBubble";
import { MusicPickerSheet } from "@/components/MusicPickerSheet";
import { resolveCurrentCity } from "@/lib/location";
import { Avatar } from "@/components/Avatar";
import {
  clearThought,
  postThought,
  type ThoughtStyle,
  type WhisperThought,
} from "@/lib/thoughts";

/** Curated bubble colour palette (mirrors the iOS swatch grid). */
const COLORS: string[] = [
  "",
  "#A855F7",
  "#7C3AED",
  "#EC4899",
  "#F472B6",
  "#EF4444",
  "#FB923C",
  "#F59E0B",
  "#22C55E",
  "#14B8A6",
  "#06B6D4",
  "#3B82F6",
  "#1F2937",
  "#000000",
];

/** Mirrors the iOS "What's on your mind" composer emoji row 1:1 so the
 *  same badges translate across platforms ("" = no emoji). */
const EMOJIS: string[] = [
  "",
  "🔥",
  "✨",
  "💪",
  "🏆",
  "🥺",
  "💜",
  "🌊",
  "🌴",
  "☕️",
  "🍕",
  "🎧",
  "🎯",
  "😎",
  "🌟",
  "⚡️",
  "🤩",
];

const MAX = 60;

interface ThoughtComposerProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** The user's existing thought, so the composer can prefill / clear. */
  current?: WhisperThought | null;
}

function ThoughtComposerBase({
  open,
  onOpenChange,
  current,
}: ThoughtComposerProps) {
  const { user, profile } = useAuth();
  const queryClient = useQueryClient();

  const [text, setText] = useState<string>("");
  const [style, setStyle] = useState<ThoughtStyle>("plain");
  const [accent, setAccent] = useState<string>("");
  const [emoji, setEmoji] = useState<string>("");
  const [colorHex, setColorHex] = useState<string>("");
  const [musicOpen, setMusicOpen] = useState<boolean>(false);
  const [locating, setLocating] = useState<boolean>(false);

  const tagLocation = async (): Promise<void> => {
    if (style === "location") {
      setStyle("plain");
      setAccent("");
      setText("");
      return;
    }
    setLocating(true);
    const city = await resolveCurrentCity();
    setLocating(false);
    if (!city) {
      toast("Couldn't get your location");
      return;
    }
    setStyle("location");
    setText(city);
    setAccent("");
  };

  const toggleMusic = (): void => {
    if (style === "music") {
      setStyle("plain");
      setAccent("");
      setText("");
      return;
    }
    setMusicOpen(true);
  };

  useEffect(() => {
    if (open) {
      setText(current?.text ?? "");
      setStyle(current?.style ?? "plain");
      setAccent(current?.accent ?? "");
      setEmoji(current?.emoji ?? "");
      setColorHex(current?.color_hex ?? "");
    }
  }, [open, current]);

  const invalidate = (): void => {
    queryClient.invalidateQueries({ queryKey: ["thoughts"] });
    queryClient.invalidateQueries({ queryKey: ["my-thought"] });
  };

  const save = useMutation({
    mutationFn: () =>
      postThought({
        userId: user!.id,
        text,
        style,
        accent,
        emoji,
        colorHex,
      }),
    onSuccess: () => {
      invalidate();
      onOpenChange(false);
      toast("Note shared");
    },
    onError: () => toast("Couldn't share your note"),
  });

  const remove = useMutation({
    mutationFn: () => clearThought(user!.id),
    onSuccess: () => {
      invalidate();
      onOpenChange(false);
      toast("Note removed");
    },
  });

  const preview =
    text.trim() ||
    (style === "location"
      ? "Here now"
      : style === "music"
        ? "Now playing"
        : "What's on your mind?");
  const canShare =
    (text.trim().length > 0 || (style !== "plain" && accent.length > 0)) &&
    !save.isPending;

  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-50 bg-black/60 backdrop-blur-[2px] data-[state=open]:animate-in data-[state=open]:fade-in-0" />
        <Dialog.Content
          className="fixed inset-x-0 bottom-0 z-50 mx-auto flex max-h-[92vh] w-full max-w-[480px] flex-col rounded-t-[26px] bg-background shadow-2xl outline-none data-[state=open]:animate-in data-[state=open]:slide-in-from-bottom sm:bottom-auto sm:top-1/2 sm:-translate-y-1/2 sm:rounded-[26px]"
          onOpenAutoFocus={(e) => e.preventDefault()}
        >
          <div className="flex items-center justify-between border-b border-border px-4 py-3.5">
            <button
              onClick={() => onOpenChange(false)}
              className="flex h-8 w-8 items-center justify-center rounded-full transition-colors hover:bg-secondary"
              aria-label="Cancel"
            >
              <X className="h-5 w-5" />
            </button>
            <Dialog.Title className="font-display text-[17px] font-bold">
              Share a note
            </Dialog.Title>
            <span className="w-8" />
          </div>

          <div className="min-h-0 flex-1 overflow-y-auto px-5 py-6">
            {/* Live preview — bubble above the avatar, just like the feed */}
            <div className="mb-8 flex justify-center">
              <div className="relative pt-9">
                <div className="absolute left-1/2 top-0 -translate-x-1/2">
                  <ThoughtBubble
                    text={preview}
                    style={style}
                    accent={accent}
                    emoji={emoji}
                    colorHex={colorHex}
                  />
                </div>
                <div className="rounded-full ring-2 ring-border">
                  <div className="rounded-full border-2 border-background">
                    <Avatar
                      name={profile?.username}
                      url={profile?.profile_image_url}
                      size={64}
                    />
                  </div>
                </div>
              </div>
            </div>

            {/* Text input */}
            <div className="rounded-2xl border border-border bg-card px-4 py-3">
              <textarea
                value={text}
                onChange={(e) => setText(e.target.value.slice(0, MAX))}
                placeholder={
                  style === "music"
                    ? "Song title"
                    : style === "location"
                      ? "Where are you?"
                      : "What's on your mind?"
                }
                rows={2}
                autoFocus
                className="w-full resize-none bg-transparent text-[16px] leading-snug outline-none placeholder:text-muted-foreground"
              />
              <div className="mt-1 text-right text-xs text-muted-foreground">
                {text.length}/{MAX}
              </div>
            </div>

            {/* Style toolbar — location + music (mirrors iOS chips) */}
            <div className="mt-4 flex gap-2.5">
              <button
                onClick={() => void tagLocation()}
                disabled={locating}
                className={cn(
                  "flex items-center gap-1.5 rounded-full border px-3.5 py-2 text-sm font-bold transition-colors",
                  style === "location"
                    ? "border-transparent bg-[#ff3d8c] text-white"
                    : "border-[#ff3d8c]/40 text-[#ff3d8c] hover:bg-[#ff3d8c]/10"
                )}
              >
                {locating ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <MapPin className="h-4 w-4" />
                )}
                {style === "location" ? text || "Located" : "Location"}
              </button>
              <button
                onClick={toggleMusic}
                className={cn(
                  "flex min-w-0 items-center gap-1.5 rounded-full border px-3.5 py-2 text-sm font-bold transition-colors",
                  style === "music"
                    ? "border-transparent bg-[#7a2ef7] text-white"
                    : "border-[#7a2ef7]/40 text-[#7a2ef7] hover:bg-[#7a2ef7]/10"
                )}
              >
                <Music className="h-4 w-4 shrink-0" />
                <span className="truncate">
                  {style === "music"
                    ? `${text}${accent ? ` · ${accent}` : ""}`
                    : "Music"}
                </span>
              </button>
            </div>

            {/* Emoji badge */}
            <div className="mt-5">
              <p className="mb-2 flex items-center gap-1.5 text-[13px] font-bold uppercase tracking-wide text-muted-foreground">
                <Smile className="h-4 w-4" /> Emoji
              </p>
              <div className="flex flex-wrap gap-2">
                {EMOJIS.map((e) => (
                  <button
                    key={e || "none"}
                    onClick={() => setEmoji(e)}
                    className={cn(
                      "flex h-10 w-10 items-center justify-center rounded-full text-xl transition-transform active:scale-90",
                      emoji === e
                        ? "bg-primary/15 ring-2 ring-primary"
                        : "bg-secondary"
                    )}
                  >
                    {e || <X className="h-4 w-4 text-muted-foreground" />}
                  </button>
                ))}
              </div>
            </div>

            {/* Colour swatches */}
            <div className="mt-5">
              <p className="mb-2 text-[13px] font-bold uppercase tracking-wide text-muted-foreground">
                Background
              </p>
              <div className="flex flex-wrap gap-2.5">
                {COLORS.map((c) => (
                  <button
                    key={c || "default"}
                    onClick={() => setColorHex(c)}
                    aria-label={c || "Default"}
                    className={cn(
                      "h-9 w-9 rounded-full border transition-transform active:scale-90",
                      colorHex === c
                        ? "ring-2 ring-offset-2 ring-foreground ring-offset-background"
                        : "border-border"
                    )}
                    style={{
                      background:
                        c || "linear-gradient(135deg, #ffffff, #e5e7eb)",
                    }}
                  />
                ))}
              </div>
            </div>
          </div>

          <div className="flex items-center gap-3 border-t border-border px-4 py-3">
            {current?.text && (
              <button
                onClick={() => remove.mutate()}
                disabled={remove.isPending}
                className="flex h-11 w-11 items-center justify-center rounded-full text-destructive transition-colors hover:bg-destructive/10"
                aria-label="Remove note"
              >
                <Trash2 className="h-5 w-5" />
              </button>
            )}
            <button
              onClick={() => canShare && save.mutate()}
              disabled={!canShare}
              className={cn(
                "flex-1 rounded-full py-3 text-[15px] font-bold transition-colors",
                canShare
                  ? "bg-primary text-primary-foreground"
                  : "border border-border text-muted-foreground"
              )}
            >
              {save.isPending ? "Sharing…" : "Share note"}
            </button>
          </div>

          <MusicPickerSheet
            open={musicOpen}
            onOpenChange={setMusicOpen}
            onPick={(track) => {
              setStyle("music");
              setText(track.title);
              setAccent(track.artist);
              setColorHex("");
            }}
          />
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

export const ThoughtComposer = memo(ThoughtComposerBase);
