import { useEffect, useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Image as ImageIcon } from "lucide-react";
import { useAuth } from "@/hooks/useAuth";
import { loadSharedStory } from "@/lib/sharedStory";
import { StoryViewer } from "./StoryViewer";

/** A preview is never a saved snapshot or a permission grant. */
export function SharedStoryCard({ storyID }: { storyID: string }) {
  const { user, profile } = useAuth();
  return user ? <AccountStoryCard key={`${user.id}:${storyID}`} accountID={user.id} username={profile?.username} storyID={storyID} /> : <p className="p-4 text-sm">Sign in to view this story.</p>;
}
function AccountStoryCard({ accountID, username, storyID }: { accountID: string; username?: string; storyID: string }) {
  const [active, setActive] = useState<boolean>(() => document.visibilityState === "visible");
  const [freshAfter, setFreshAfter] = useState<number>(0);
  const [open, setOpen] = useState<boolean>(false);
  const [clock, setClock] = useState<number>(Date.now());
  const generation = useRef<number>(0);
  const query = useQuery({ queryKey: ["shared-story", accountID, storyID], queryFn: ({ signal }) => loadSharedStory(accountID, storyID, signal), retry: false, gcTime: 0, staleTime: 0, enabled: active, refetchInterval: active ? 15_000 : false });
  useEffect(() => {
    const update = (): void => { generation.current++; const visible = document.visibilityState === "visible"; setActive(visible); if (!visible) { setOpen(false); setFreshAfter(Date.now()+1); } };
    document.addEventListener("visibilitychange", update); return () => { generation.current++; document.removeEventListener("visibilitychange", update); };
  }, []);
  useEffect(() => {
    if (!query.data) return;
    const timer = window.setTimeout(() => setClock(Date.now()), Math.min(2_147_483_647, Math.max(1, Date.parse(query.data.expires_at)-Date.now())));
    return () => window.clearTimeout(timer);
  }, [query.data?.expires_at, query.dataUpdatedAt]);
  const story = active && !query.isError && query.dataUpdatedAt >= freshAfter && query.data && Date.parse(query.data.expires_at) > Math.max(clock, Date.now()) ? query.data : undefined;
  return <section aria-label="Shared story" className="w-56 max-w-full overflow-hidden rounded-2xl border border-border bg-background text-foreground">
    {story ? <img src={story.image_url} alt="Story preview" className="h-64 w-full object-cover" /> : <div className="flex h-28 items-center justify-center bg-secondary"><ImageIcon className="h-7 w-7 text-muted-foreground" /></div>}
    <div className="space-y-2 p-3"><p className="text-sm font-semibold">{story ? `@${story.username}'s story` : "Shared story"}</p>
      <p className="text-xs text-muted-foreground">{query.isError ? "Unavailable, expired, or access changed." : story ? "Only available while you have access." : "Checking story access…"}</p>
      <button type="button" disabled={!active || query.isFetching} className="min-h-11 w-full rounded-full bg-secondary text-sm font-semibold disabled:opacity-50" onClick={async () => { const epoch = generation.current; const result = await query.refetch(); if (epoch === generation.current && result.data && !result.isError && document.visibilityState === "visible") setOpen(true); }}>{query.isFetching ? "Checking…" : story ? "View story" : "Check again"}</button>
    </div>
    {open && story && <StoryViewer groups={[{ userId: story.user_id, username: story.username, avatarUrl: null, stories: [story] }]} startGroup={0} me={{ id: accountID, username }} onClose={() => setOpen(false)} />}
  </section>;
}
