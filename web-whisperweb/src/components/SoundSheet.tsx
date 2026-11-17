import { memo, useEffect, useMemo, useRef, useState } from "react";
import { Bookmark, Music2, Pause, Play, Video, X } from "lucide-react";

import * as Dialog from "@radix-ui/react-dialog";
import { Avatar } from "@/components/Avatar";
import { cn } from "@/lib/utils";
import { compactCount } from "@/lib/format";
import type { PostMusic } from "@/lib/postMeta";
import type { WhisperPost, WhisperProfile } from "@/lib/types";
import {
  isOriginalSound,
  isSoundSaved,
  soundLabel,
  toggleSavedSound,
  wavesUsingSound,
} from "@/lib/waveSounds";

const VIDEO_RE = /\.(mp4|mov|webm|m4v)(\?|$)/i;

/**
 * TikTok's Sound Page as a dialog: the sound's art, title and creator, how
 * many waves wear it, "Use this sound", Save, and the grid of every wave made
 * with it. Mirrors iOS `WhisperSoundSheet`.
 */
function SoundSheetBase({
  sound,
  pool,
  profiles,
  onClose,
  onUse,
  onOpenWave,
}: {
  sound: PostMusic;
  pool: WhisperPost[];
  profiles: Record<string, WhisperProfile | undefined>;
  onClose: () => void;
  /** "Use this sound" — open the composer with the sound attached. */
  onUse: (sound: PostMusic) => void;
  /** Tap a wave in the grid — scroll the player to it. */
  onOpenWave: (post: WhisperPost) => void;
}) {
  const [saved, setSaved] = useState<boolean>(() => isSoundSaved(sound));
  const [playing, setPlaying] = useState<boolean>(false);
  const audioRef = useRef<HTMLAudioElement | null>(null);

  const usernameFor = (p: WhisperPost): string =>
    profiles[p.user_id]?.username ?? p.username ?? "user";

  const waves = useMemo(
    () => wavesUsingSound(sound, pool, usernameFor),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [sound.id, pool, profiles]
  );
  const original = isOriginalSound(sound);
  const canPreview = !!sound.previewURL;

  // Stop the preview when the sheet unmounts.
  useEffect(() => {
    return () => {
      audioRef.current?.pause();
      audioRef.current = null;
    };
  }, []);

  const togglePreview = (): void => {
    if (!sound.previewURL) return;
    if (!audioRef.current) {
      const el = new Audio(sound.previewURL);
      el.addEventListener("ended", () => setPlaying(false));
      el.addEventListener("pause", () => setPlaying(false));
      el.addEventListener("play", () => setPlaying(true));
      audioRef.current = el;
    }
    const el = audioRef.current;
    if (el.paused) void el.play().catch(() => setPlaying(false));
    else el.pause();
  };

  const art = sound.artworkURL;

  return (
    <Dialog.Root open onOpenChange={(o) => !o && onClose()}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-[60] bg-black/70 backdrop-blur-[2px] data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0" />
        <Dialog.Content
          className="fixed inset-x-0 bottom-0 z-[60] mx-auto flex max-h-[88vh] w-full max-w-[520px] flex-col overflow-hidden rounded-t-[26px] bg-[#0b0b0c] text-white shadow-2xl outline-none data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:slide-out-to-bottom data-[state=open]:slide-in-from-bottom sm:bottom-auto sm:top-1/2 sm:-translate-y-1/2 sm:rounded-[26px]"
          onOpenAutoFocus={(e) => e.preventDefault()}
        >
          <div className="flex items-center justify-between px-4 pt-4">
            <Dialog.Title className="text-[15px] font-bold">Sound</Dialog.Title>
            <Dialog.Description className="sr-only">
              {soundLabel(sound)}
            </Dialog.Description>
            <button
              onClick={onClose}
              aria-label="Close"
              className="flex h-8 w-8 items-center justify-center rounded-full text-white/80 transition-colors hover:bg-white/10"
            >
              <X className="h-4.5 w-4.5" />
            </button>
          </div>

          <div className="no-scrollbar flex-1 overflow-y-auto px-4 pb-6 pt-3">
            {/* Header */}
            <div className="flex items-center gap-4">
              <button
                onClick={togglePreview}
                disabled={!canPreview}
                aria-label={playing ? "Pause preview" : "Play preview"}
                className="relative h-[100px] w-[100px] shrink-0 overflow-hidden rounded-[18px] border border-white/10 bg-gradient-to-br from-[#F22659] via-[#FF7340] to-[#FFA94D] disabled:cursor-default"
              >
                {art ? (
                  <img src={art} alt="" className="h-full w-full object-cover" draggable={false} />
                ) : original ? (
                  <span className="flex h-full w-full items-center justify-center">
                    <Avatar name={sound.artist} size={56} />
                  </span>
                ) : (
                  <span className="flex h-full w-full items-center justify-center">
                    <Music2 className="h-9 w-9 text-white" />
                  </span>
                )}
                {canPreview && (
                  <span className="absolute inset-0 flex items-center justify-center">
                    <span className="flex h-10 w-10 items-center justify-center rounded-full bg-black/45">
                      {playing ? (
                        <Pause className="h-4.5 w-4.5 fill-white text-white" />
                      ) : (
                        <Play className="h-4.5 w-4.5 fill-white text-white" />
                      )}
                    </span>
                  </span>
                )}
              </button>
              <div className="min-w-0">
                <h3 className="line-clamp-2 text-[19px] font-black leading-tight">
                  {original ? "Original sound" : sound.title}
                </h3>
                <div className="mt-1.5 flex items-center gap-1.5 text-[14px] font-semibold text-white/85">
                  {original && <Avatar name={sound.artist} size={18} />}
                  <span className="truncate">{sound.artist}</span>
                </div>
                <p className="mt-1.5 text-[13px] font-semibold text-white/55">
                  {waves.length === 1 ? "1 wave" : `${compactCount(waves.length)} waves`}
                </p>
              </div>
            </div>

            {/* Actions */}
            <div className="mt-5 flex items-center gap-2.5">
              <button
                onClick={() => onUse(sound)}
                className="flex flex-1 items-center justify-center gap-2 rounded-full bg-gradient-to-br from-[#F22659] via-[#FF7340] to-[#FFA94D] py-3.5 text-[15px] font-black text-white shadow-[0_10px_28px_-8px_rgba(255,115,64,0.6)] transition-transform active:scale-[0.98]"
              >
                <Video className="h-4 w-4" />
                Use this sound
              </button>
              <button
                onClick={() => setSaved(toggleSavedSound(sound))}
                aria-label={saved ? "Remove from saved sounds" : "Save sound"}
                className="flex items-center gap-1.5 rounded-full border border-white/15 bg-white/10 px-4 py-3.5 text-[14px] font-bold transition-colors hover:bg-white/15"
              >
                <Bookmark className={cn("h-4 w-4", saved && "fill-white")} />
                {saved ? "Saved" : "Save"}
              </button>
            </div>

            {/* Grid */}
            <p className="mt-6 text-[11px] font-black uppercase tracking-[0.1em] text-white/50">
              {waves.length === 0 ? "No waves yet" : "Waves with this sound"}
            </p>
            {waves.length === 0 ? (
              <div className="mt-2.5 flex flex-col items-center gap-2 rounded-2xl bg-white/5 py-7 text-center">
                <Music2 className="h-7 w-7 text-white/60" />
                <p className="text-[13px] font-semibold text-white/60">
                  Be the first to make a wave with it.
                </p>
              </div>
            ) : (
              <div className="mt-2.5 grid grid-cols-3 gap-0.5 overflow-hidden rounded-xl">
                {waves.map((post) => {
                  const media = post.media_urls ?? [];
                  const still = media.find((u) => !VIDEO_RE.test(u));
                  const video = media.find((u) => VIDEO_RE.test(u));
                  return (
                    <button
                      key={post.id}
                      onClick={() => onOpenWave(post)}
                      className="relative aspect-[9/16] overflow-hidden bg-white/10 transition-opacity hover:opacity-90"
                      aria-label={`Wave by ${usernameFor(post)}`}
                    >
                      {still ? (
                        <img src={still} alt="" className="h-full w-full object-cover" loading="lazy" draggable={false} />
                      ) : video ? (
                        <video
                          src={`${video}#t=0.1`}
                          muted
                          playsInline
                          preload="metadata"
                          className="h-full w-full object-cover"
                        />
                      ) : (
                        <span className="flex h-full w-full items-center justify-center bg-gradient-to-br from-[#FF7340]/80 to-[#F22659]/60">
                          <Music2 className="h-6 w-6 text-white/80" />
                        </span>
                      )}
                      <span className="absolute bottom-1.5 left-1.5 flex items-center gap-1 text-[11px] font-bold text-white drop-shadow">
                        <Play className="h-2.5 w-2.5 fill-white" />
                        {compactCount(post.likes_count ?? 0)}
                      </span>
                    </button>
                  );
                })}
              </div>
            )}
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

export const SoundSheet = memo(SoundSheetBase);
