import { useEffect, useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ChevronLeft, ChevronRight, Loader2, Music, Plus, X } from "lucide-react";
import { toast } from "sonner";

import {
  addStoryToHighlight,
  createHighlightWithStory,
  fetchHighlightItems,
  fetchHighlights,
  type StoryHighlight,
} from "@/lib/highlights";
import { fetchStories } from "@/lib/api";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import type { WhisperStory } from "@/lib/types";

/**
 * Instagram-style story-highlight bubbles — the same albums the user curates
 * on iOS, rendered on their web profile. Owners get the IG "New" bubble that
 * builds a highlight straight from their active stories.
 */
export function HighlightsRow({
  userId,
  isMe = false,
}: {
  userId: string;
  isMe?: boolean;
}) {
  const [open, setOpen] = useState<StoryHighlight | null>(null);
  const [creating, setCreating] = useState<boolean>(false);

  const highlightsQuery = useQuery({
    queryKey: ["story-highlights", userId],
    queryFn: () => fetchHighlights(userId),
  });
  const highlights = highlightsQuery.data ?? [];

  if (highlights.length === 0 && !isMe) return null;

  return (
    <>
      <div className="-mx-4 overflow-x-auto pb-3 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
        <div className="flex gap-4 px-4">
          {/* Owner "New" bubble — IG's dashed circle with a plus. */}
          {isMe && (
            <button
              onClick={() => setCreating(true)}
              className="flex w-16 shrink-0 flex-col items-center gap-1 transition-transform active:scale-95"
            >
              <span className="flex h-16 w-16 items-center justify-center rounded-full border border-dashed border-muted-foreground/50">
                <Plus className="h-6 w-6 text-foreground" strokeWidth={1.6} />
              </span>
              <span className="max-w-16 truncate text-[11px] font-medium">
                New
              </span>
            </button>
          )}
          {highlights.map((h) => (
            <button
              key={h.id}
              onClick={() => setOpen(h)}
              className="flex w-16 shrink-0 flex-col items-center gap-1 transition-transform active:scale-95"
            >
              <span className="flex h-16 w-16 items-center justify-center rounded-full border border-border p-[3px]">
                <span className="h-full w-full overflow-hidden rounded-full bg-secondary">
                  {h.cover_url ? (
                    <img
                      src={h.cover_url}
                      alt={h.title}
                      loading="lazy"
                      className="h-full w-full object-cover"
                    />
                  ) : (
                    <span className="flex h-full w-full items-center justify-center text-[18px] font-bold text-muted-foreground">
                      {h.title.slice(0, 1).toUpperCase()}
                    </span>
                  )}
                </span>
              </span>
              <span className="max-w-16 truncate text-[11px] font-medium">
                {h.title}
              </span>
            </button>
          ))}
        </div>
      </div>

      {open && (
        <HighlightViewer highlight={open} onClose={() => setOpen(null)} />
      )}

      {creating && (
        <NewHighlightDialog userId={userId} onClose={() => setCreating(false)} />
      )}
    </>
  );
}

/** IG's "New highlight" flow — pick from your active stories, name it, done. */
function NewHighlightDialog({
  userId,
  onClose,
}: {
  userId: string;
  onClose: () => void;
}) {
  const queryClient = useQueryClient();
  const [title, setTitle] = useState<string>("");
  const [picked, setPicked] = useState<Set<string>>(new Set());

  const storiesQuery = useQuery({
    queryKey: ["stories"],
    queryFn: fetchStories,
    staleTime: 60_000,
  });
  const myStories = useMemo<WhisperStory[]>(
    () => (storiesQuery.data ?? []).filter((s) => s.user_id === userId),
    [storiesQuery.data, userId]
  );

  const togglePick = (id: string): void => {
    setPicked((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const createMutation = useMutation({
    mutationFn: async () => {
      const chosen = myStories.filter((s) => picked.has(s.id));
      if (chosen.length === 0) throw new Error("Pick at least one story.");
      const [first, ...rest] = chosen;
      const album = await createHighlightWithStory(userId, title, {
        image_url: first.image_url,
        caption: first.caption ?? null,
        music_title: first.music_title ?? null,
        music_artist: first.music_artist ?? null,
        metadata: first.metadata ?? null,
      });
      for (const s of rest) {
        await addStoryToHighlight(album.id, userId, {
          image_url: s.image_url,
          caption: s.caption ?? null,
          music_title: s.music_title ?? null,
          music_artist: s.music_artist ?? null,
          metadata: s.metadata ?? null,
        });
      }
    },
    onSuccess: () => {
      toast("Highlight created");
      queryClient.invalidateQueries({ queryKey: ["story-highlights", userId] });
      onClose();
    },
    onError: (err) =>
      toast(err instanceof Error ? err.message : "Couldn't create the highlight"),
  });

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>New highlight</DialogTitle>
        </DialogHeader>
        <Input
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="Highlight name"
          maxLength={24}
          autoFocus
        />
        {myStories.length === 0 ? (
          <p className="rounded-xl border border-dashed border-border bg-secondary/30 px-4 py-6 text-center text-[13px] text-muted-foreground">
            No active stories to save. Post a story first — or save any story
            from the viewer's Highlight button.
          </p>
        ) : (
          <div className="grid max-h-64 grid-cols-4 gap-1.5 overflow-y-auto">
            {myStories.map((s) => (
              <button
                key={s.id}
                onClick={() => togglePick(s.id)}
                className={cn(
                  "relative aspect-[9/16] overflow-hidden rounded-lg bg-secondary transition-all",
                  picked.has(s.id) && "ring-2 ring-primary"
                )}
              >
                <img
                  src={s.image_url}
                  alt=""
                  loading="lazy"
                  className="h-full w-full object-cover"
                />
                {picked.has(s.id) && (
                  <span className="absolute right-1 top-1 flex h-4 w-4 items-center justify-center rounded-full bg-primary text-[10px] font-bold text-primary-foreground">
                    ✓
                  </span>
                )}
              </button>
            ))}
          </div>
        )}
        <button
          onClick={() => createMutation.mutate()}
          disabled={
            createMutation.isPending || title.trim().length === 0 || picked.size === 0
          }
          className="flex h-11 w-full items-center justify-center gap-2 rounded-full bg-primary text-sm font-semibold text-primary-foreground transition-opacity disabled:opacity-40"
        >
          {createMutation.isPending && (
            <Loader2 className="h-4 w-4 animate-spin" />
          )}
          Create highlight
        </button>
      </DialogContent>
    </Dialog>
  );
}

function HighlightViewer({
  highlight,
  onClose,
}: {
  highlight: StoryHighlight;
  onClose: () => void;
}) {
  const [index, setIndex] = useState<number>(0);

  const itemsQuery = useQuery({
    queryKey: ["story-highlight-items", highlight.id],
    queryFn: () => fetchHighlightItems(highlight.id),
  });
  const items = itemsQuery.data ?? [];
  const item = items[index] ?? null;

  useEffect(() => {
    setIndex(0);
  }, [highlight.id]);

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-sm overflow-hidden border-none bg-black p-0 text-white [&>button]:hidden">
        <DialogTitle className="sr-only">{highlight.title}</DialogTitle>
        <div className="relative aspect-[9/16] w-full">
          {/* Progress segments */}
          {items.length > 1 && (
            <div className="absolute inset-x-2 top-2 z-20 flex gap-1">
              {items.map((it, i) => (
                <span
                  key={it.id}
                  className={cn(
                    "h-0.5 flex-1 rounded-full",
                    i <= index ? "bg-white" : "bg-white/30"
                  )}
                />
              ))}
            </div>
          )}

          <div className="absolute inset-x-0 top-5 z-20 flex items-center justify-between px-3">
            <span className="text-[13px] font-bold drop-shadow">
              {highlight.title}
            </span>
            <button
              onClick={onClose}
              aria-label="Close"
              className="rounded-full bg-black/40 p-1.5 transition-transform active:scale-90"
            >
              <X className="h-4 w-4" />
            </button>
          </div>

          {item ? (
            <img
              src={item.image_url}
              alt={item.caption ?? highlight.title}
              className="h-full w-full object-cover"
            />
          ) : (
            <div className="flex h-full w-full items-center justify-center text-sm text-white/60">
              {itemsQuery.isLoading ? "Loading…" : "No stories saved"}
            </div>
          )}

          {item?.caption && (
            <p className="absolute inset-x-0 bottom-10 z-20 px-4 text-center text-[13px] font-medium drop-shadow">
              {item.caption}
            </p>
          )}
          {item?.music_title && (
            <p className="absolute inset-x-0 bottom-4 z-20 flex items-center justify-center gap-1 text-[11.5px] text-white/80">
              <Music className="h-3 w-3" />
              {item.music_title}
              {item.music_artist ? ` · ${item.music_artist}` : ""}
            </p>
          )}

          {/* Tap zones */}
          {index > 0 && (
            <button
              onClick={() => setIndex((i) => Math.max(0, i - 1))}
              aria-label="Previous story"
              className="absolute inset-y-0 left-0 z-10 flex w-1/3 items-center justify-start pl-1 text-white/0 hover:text-white/70"
            >
              <ChevronLeft className="h-6 w-6" />
            </button>
          )}
          {index < items.length - 1 && (
            <button
              onClick={() => setIndex((i) => Math.min(items.length - 1, i + 1))}
              aria-label="Next story"
              className="absolute inset-y-0 right-0 z-10 flex w-2/3 items-center justify-end pr-1 text-white/0 hover:text-white/70"
            >
              <ChevronRight className="h-6 w-6" />
            </button>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
