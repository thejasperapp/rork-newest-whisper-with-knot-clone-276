import { memo, useMemo, useRef, useState } from "react";
import { Plus } from "lucide-react";
import { useQuery } from "@tanstack/react-query";

import { Avatar } from "@/components/Avatar";
import { cn } from "@/lib/utils";
import { StoryEditor } from "@/components/StoryEditor";
import { StoryViewer, type StoryGroup } from "@/components/StoryViewer";
import { ThoughtBubble } from "@/components/ThoughtBubble";
import { ThoughtComposer } from "@/components/ThoughtComposer";
import { ThoughtRepliesSheet } from "@/components/ThoughtRepliesSheet";
import { snapshotFromThought, type ThoughtSnapshot } from "@/lib/thoughtReplies";
import { useDragScroll } from "@/hooks/useDragScroll";
import { loadSeenStoryIds } from "@/lib/storySeen";
import { useAuth } from "@/hooks/useAuth";
import { fetchMyThought, fetchThoughts, isThoughtActive } from "@/lib/thoughts";
import { fetchLiveHostIds } from "@/lib/api";
import type { WhisperProfile, WhisperStory } from "@/lib/types";

import { WHISPER_STORY_RING } from "@/lib/storyRing";

function groupStories(
  stories: WhisperStory[],
  profiles: Record<string, WhisperProfile>
): StoryGroup[] {
  const map = new Map<string, StoryGroup>();
  for (const s of stories) {
    const profile = profiles[s.user_id];
    const g = map.get(s.user_id) ?? {
      userId: s.user_id,
      username: profile?.username ?? s.username,
      avatarUrl: profile?.profile_image_url ?? null,
      stories: [],
    };
    g.stories.push(s);
    map.set(s.user_id, g);
  }
  return Array.from(map.values());
}

function StoriesBase({
  stories,
  profiles = {},
}: {
  stories: WhisperStory[];
  profiles?: Record<string, WhisperProfile>;
}) {
  const { user, profile } = useAuth();
  const [viewer, setViewer] = useState<number | null>(null);
  const [storyFile, setStoryFile] = useState<File | null>(null);
  const [thinking, setThinking] = useState<boolean>(false);
  const storyInputRef = useRef<HTMLInputElement>(null);
  const [replyTarget, setReplyTarget] = useState<{
    userId: string;
    username: string;
    thought: ThoughtSnapshot | null;
  } | null>(null);
  const { ref, handlers, didDrag } = useDragScroll<HTMLDivElement>();
  const [seenTick, setSeenTick] = useState<number>(0);
  const groups = useMemo(
    () => groupStories(stories, profiles),
    [stories, profiles]
  );
  // Seen-state drives the gradient (unseen) vs gray (seen) rings —
  // recomputed when the viewer closes so rings dim right away.
  const seenIds = useMemo(() => loadSeenStoryIds(), [seenTick, stories]);
  const hasUnseen = (g: StoryGroup): boolean =>
    g.stories.some((s) => !seenIds.has(s.id));

  // My current note (drives the bubble text + the composer prefill).
  const myThoughtQuery = useQuery({
    queryKey: ["my-thought", user?.id],
    queryFn: () => fetchMyThought(user!.id),
    enabled: !!user,
  });
  const myThought = myThoughtQuery.data ?? null;
  const myNoteActive = isThoughtActive(myThought);

  // Friends' active notes, surfaced above their story avatars.
  const otherIds = useMemo(
    () => groups.map((g) => g.userId).filter((id) => id !== user?.id),
    [groups, user?.id]
  );
  const thoughtsQuery = useQuery({
    queryKey: ["thoughts", otherIds],
    queryFn: () => fetchThoughts(otherIds),
    enabled: otherIds.length > 0,
  });
  const thoughts = thoughtsQuery.data ?? {};

  // Exclude the viewer's own group from the friend list — my stories live in
  // the dedicated "Your story" bubble at the start of the strip.
  const others = useMemo(
    () => groups.filter((g) => g.userId !== profile?.user_id),
    [groups, profile?.user_id]
  );
  const myGroupIndex = groups.findIndex((g) => g.userId === profile?.user_id);
  const hasMyStory = myGroupIndex >= 0;

  // LIVE badges on story rings — hosts currently live (kit 4.0 grammar,
  // matching the iOS strip's red-ringed LIVE bubbles).
  const liveQuery = useQuery({
    queryKey: ["live-host-ids"],
    queryFn: fetchLiveHostIds,
    staleTime: 60_000,
    refetchInterval: 120_000,
  });
  const liveSet = useMemo(
    () => new Set(liveQuery.data ?? []),
    [liveQuery.data]
  );

  const guarded =
    <E,>(fn: (e: E) => void) =>
    (e: E) => {
      if (didDrag()) return;
      fn(e);
    };

  const openStoryPicker = (): void => storyInputRef.current?.click();
  const handleStoryPick = (e: React.ChangeEvent<HTMLInputElement>): void => {
    const picked = e.target.files?.[0] ?? null;
    e.target.value = "";
    if (picked) setStoryFile(picked);
  };

  return (
    <>
      <div
        ref={ref}
        {...handlers}
        className="no-scrollbar flex cursor-grab gap-4 overflow-x-auto px-4 pb-4 pt-14 active:cursor-grabbing"
      >
        {/* Your story — IG-Notes "What's on your mind?" thought note, a rounded
            card centered above the avatar that overlaps its top edge with two
            tail dots dipping into the ring — matched 1:1 to the iOS app. */}
        <div className="flex w-[76px] shrink-0 flex-col items-center gap-1.5">
          <div className="relative">
            {/* Thought bubble — tappable, opens the note composer. */}
            <button
              onClick={guarded(() => setThinking(true))}
              aria-label="Share a note"
              className="absolute left-1/2 z-30 -translate-x-1/2 transition-transform active:scale-95"
              style={{ bottom: "calc(100% - 8px)" }}
            >
              <ThoughtBubble
                text={myNoteActive ? myThought!.text : "Note..."}
                style={myNoteActive ? myThought!.style : "plain"}
                accent={myNoteActive ? myThought!.accent : ""}
                emoji={myNoteActive ? myThought!.emoji : ""}
                colorHex={myNoteActive ? myThought!.color_hex : ""}
              />
            </button>
            <button
              onClick={guarded(() =>
                hasMyStory ? setViewer(myGroupIndex) : openStoryPicker()
              )}
              className="block"
            >
              <div
                className={cn("rounded-full p-[3px]")}
                style={
                  hasMyStory && hasUnseen(groups[myGroupIndex])
                    ? { background: WHISPER_STORY_RING }
                    : hasMyStory
                      ? { background: "hsl(var(--muted-foreground) / 0.45)" }
                      : { background: "hsl(var(--border))" }
                }
              >
                <div className="rounded-full border-2 border-background">
                  <Avatar
                    name={profile?.username}
                    url={profile?.profile_image_url}
                    size={64}
                  />
                </div>
              </div>
            </button>
            <button
              onClick={guarded(() => openStoryPicker())}
              aria-label="Add story"
              className="absolute bottom-0 right-0 z-30 flex h-[24px] w-[24px] items-center justify-center rounded-full border-2 border-background bg-primary text-primary-foreground"
            >
              <Plus className="h-3.5 w-3.5" />
            </button>
          </div>
          <span className="w-full truncate text-center text-xs text-muted-foreground">
            {myNoteActive ? "Your note" : hasMyStory ? "Your story" : "Add story"}
          </span>
        </div>

        {others.map((g) => {
          const realIndex = groups.indexOf(g);
          const note = thoughts[g.userId];
          return (
            <button
              key={g.userId}
              onClick={guarded(() => setViewer(realIndex))}
              className="flex w-[76px] shrink-0 flex-col items-center gap-1.5"
            >
              <div className="relative">
                {note && (
                  <span
                    role="button"
                    tabIndex={0}
                    onClick={guarded((e) => {
                      e.stopPropagation();
                      setReplyTarget({
                        userId: g.userId,
                        username: g.username,
                        thought: snapshotFromThought(note),
                      });
                    })}
                    className="absolute left-1/2 z-20 -translate-x-1/2 transition-transform active:scale-95"
                    style={{ bottom: "calc(100% - 8px)" }}
                  >
                    <ThoughtBubble
                      text={note.text}
                      style={note.style}
                      accent={note.accent}
                      emoji={note.emoji}
                      colorHex={note.color_hex}
                      scale={0.92}
                    />
                  </span>
                )}
                <div
                  className="rounded-full p-[3px]"
                  style={{
                    background: liveSet.has(g.userId)
                      ? "linear-gradient(45deg, #C913B9, #F03E4D, #FE7C39)"
                      : hasUnseen(g)
                        ? WHISPER_STORY_RING
                        : "hsl(var(--muted-foreground) / 0.4)",
                  }}
                >
                  <div className="rounded-full border-2 border-background">
                    <Avatar name={g.username} url={g.avatarUrl} size={64} />
                  </div>
                </div>
                {liveSet.has(g.userId) && (
                  <span className="absolute -bottom-1 left-1/2 z-30 -translate-x-1/2 rounded-[5px] border-2 border-background bg-gradient-to-r from-[#C913B9] via-[#F03E4D] to-[#FE7C39] px-1.5 py-px text-[7px] font-bold uppercase tracking-wider text-white">
                    LIVE
                  </span>
                )}
              </div>
              <span className="w-full truncate text-center text-xs text-foreground">
                {g.username}
              </span>
            </button>
          );
        })}
      </div>

      {viewer !== null && groups[viewer] && (
        <StoryViewer
          groups={groups}
          startGroup={viewer}
          onClose={() => {
            setViewer(null);
            setSeenTick((t) => t + 1);
          }}
          me={{
            id: user?.id,
            username: profile?.username,
            avatarUrl: profile?.profile_image_url,
          }}
        />
      )}

      <input
        ref={storyInputRef}
        type="file"
        accept="image/*"
        className="hidden"
        onChange={handleStoryPick}
      />

      {storyFile && (
        <StoryEditor file={storyFile} onClose={() => setStoryFile(null)} />
      )}

      <ThoughtComposer
        open={thinking}
        onOpenChange={setThinking}
        current={myThought}
      />

      {replyTarget && (
        <ThoughtRepliesSheet
          open={!!replyTarget}
          onOpenChange={(o) => !o && setReplyTarget(null)}
          ownerUserId={replyTarget.userId}
          ownerUsername={replyTarget.username}
          isOwner={replyTarget.userId === user?.id}
          liveThought={replyTarget.thought}
        />
      )}
    </>
  );
}

export const Stories = memo(StoriesBase);
