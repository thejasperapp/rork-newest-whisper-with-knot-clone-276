import { memo, useEffect, useRef, useState } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { Search, X, Pause, Play, Music } from "lucide-react";
import { useQuery } from "@tanstack/react-query";

import { cn } from "@/lib/utils";
import {
  searchTracks,
  trendingTracks,
  type MusicTrack,
} from "@/lib/music";

interface MusicPickerSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onPick: (track: MusicTrack) => void;
}

function MusicPickerSheetBase({
  open,
  onOpenChange,
  onPick,
}: MusicPickerSheetProps) {
  const [query, setQuery] = useState<string>("");
  const [debounced, setDebounced] = useState<string>("");
  const [playingId, setPlayingId] = useState<string | null>(null);
  const audioRef = useRef<HTMLAudioElement | null>(null);

  useEffect(() => {
    const t = setTimeout(() => setDebounced(query.trim()), 280);
    return () => clearTimeout(t);
  }, [query]);

  const trending = useQuery({
    queryKey: ["music-trending"],
    queryFn: trendingTracks,
    enabled: open,
    staleTime: 5 * 60 * 1000,
  });

  const results = useQuery({
    queryKey: ["music-search", debounced],
    queryFn: () => searchTracks(debounced),
    enabled: open && debounced.length > 0,
  });

  const list: MusicTrack[] = debounced
    ? results.data ?? []
    : trending.data ?? [];
  const loading = debounced ? results.isLoading : trending.isLoading;

  // Stop preview playback whenever the sheet closes.
  useEffect(() => {
    if (!open) {
      audioRef.current?.pause();
      audioRef.current = null;
      setPlayingId(null);
      setQuery("");
    }
  }, [open]);

  const togglePreview = (track: MusicTrack): void => {
    if (!track.previewURL) return;
    if (playingId === track.id) {
      audioRef.current?.pause();
      setPlayingId(null);
      return;
    }
    audioRef.current?.pause();
    const audio = new Audio(track.previewURL);
    audio.volume = 0.85;
    void audio.play().catch(() => undefined);
    audio.onended = () => setPlayingId(null);
    audioRef.current = audio;
    setPlayingId(track.id);
  };

  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-[60] bg-black/60 backdrop-blur-[2px] data-[state=open]:animate-in data-[state=open]:fade-in-0" />
        <Dialog.Content
          className="fixed inset-x-0 bottom-0 z-[60] mx-auto flex h-[78vh] w-full max-w-[480px] flex-col rounded-t-[26px] bg-background shadow-2xl outline-none data-[state=open]:animate-in data-[state=open]:slide-in-from-bottom sm:bottom-auto sm:top-1/2 sm:h-[70vh] sm:-translate-y-1/2 sm:rounded-[26px]"
          onOpenAutoFocus={(e) => e.preventDefault()}
        >
          <div className="flex items-center justify-between px-5 pb-3 pt-4">
            <Dialog.Title className="font-display text-xl font-bold">
              Music
            </Dialog.Title>
            <button
              onClick={() => onOpenChange(false)}
              className="flex h-8 w-8 items-center justify-center rounded-full bg-secondary text-muted-foreground transition-colors hover:text-foreground"
              aria-label="Close"
            >
              <X className="h-4 w-4" />
            </button>
          </div>

          <div className="px-4 pb-2">
            <div className="flex items-center gap-2 rounded-full border border-border bg-secondary px-4 py-2.5">
              <Search className="h-4 w-4 text-muted-foreground" />
              <input
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Search songs"
                className="flex-1 bg-transparent text-[15px] outline-none placeholder:text-muted-foreground"
              />
              {query && (
                <button
                  onClick={() => setQuery("")}
                  className="text-muted-foreground"
                  aria-label="Clear"
                >
                  <X className="h-4 w-4" />
                </button>
              )}
            </div>
          </div>

          <div className="min-h-0 flex-1 space-y-1.5 overflow-y-auto px-3 pb-6 pt-1">
            {loading && (
              <div className="space-y-2 p-1">
                {[0, 1, 2, 3, 4].map((i) => (
                  <div
                    key={i}
                    className="flex animate-pulse items-center gap-3 rounded-2xl p-2.5"
                  >
                    <div className="h-12 w-12 rounded-xl bg-secondary" />
                    <div className="flex-1 space-y-2">
                      <div className="h-3 w-32 rounded bg-secondary" />
                      <div className="h-3 w-20 rounded bg-secondary" />
                    </div>
                  </div>
                ))}
              </div>
            )}

            {!loading && list.length === 0 && (
              <p className="px-4 py-12 text-center text-sm text-muted-foreground">
                {debounced ? "No songs found." : "Search for a song to attach."}
              </p>
            )}

            {list.map((track) => (
              <div
                key={track.id}
                className="flex items-center gap-3 rounded-2xl border border-transparent p-2.5 transition-colors hover:border-border hover:bg-card"
              >
                <div className="relative h-12 w-12 shrink-0 overflow-hidden rounded-xl bg-secondary">
                  {track.artworkURL ? (
                    <img
                      src={track.artworkURL}
                      alt=""
                      className="h-full w-full object-cover"
                    />
                  ) : (
                    <div className="flex h-full w-full items-center justify-center text-muted-foreground">
                      <Music className="h-5 w-5" />
                    </div>
                  )}
                  {track.previewURL && (
                    <button
                      onClick={() => togglePreview(track)}
                      className="absolute inset-0 flex items-center justify-center bg-black/35 text-white opacity-0 transition-opacity hover:opacity-100 data-[playing=true]:opacity-100"
                      data-playing={playingId === track.id}
                      aria-label={playingId === track.id ? "Pause" : "Preview"}
                    >
                      {playingId === track.id ? (
                        <Pause className="h-5 w-5" />
                      ) : (
                        <Play className="h-5 w-5" />
                      )}
                    </button>
                  )}
                </div>
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-bold">{track.title}</p>
                  <p className="truncate text-xs text-muted-foreground">
                    {track.artist}
                  </p>
                </div>
                <button
                  onClick={() => {
                    audioRef.current?.pause();
                    onPick(track);
                    onOpenChange(false);
                  }}
                  className={cn(
                    "rounded-full bg-primary px-4 py-2 text-xs font-bold text-primary-foreground",
                    "transition-transform active:scale-90"
                  )}
                >
                  Use
                </button>
              </div>
            ))}
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

export const MusicPickerSheet = memo(MusicPickerSheetBase);
