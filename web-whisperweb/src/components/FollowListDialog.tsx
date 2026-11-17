import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Search } from "lucide-react";

import { Avatar } from "@/components/Avatar";
import { UserBadges } from "@/components/UserBadges";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { fetchFollowers, fetchFollowing, isFollowing, toggleFollow } from "@/lib/api";
import { useAuth } from "@/hooks/useAuth";
import { cn } from "@/lib/utils";
import type { WhisperFollowUser } from "@/lib/types";

export type FollowTab = "followers" | "following";

interface FollowListDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  userId: string;
  username: string;
  initialTab: FollowTab;
}

function FollowButton({ targetId, username }: { targetId: string; username: string }) {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const followingQuery = useQuery({
    queryKey: ["is-following", user?.id, targetId],
    queryFn: () => isFollowing(user!.id, targetId),
    enabled: !!user,
  });
  const [optimistic, setOptimistic] = useState<boolean | null>(null);
  const following = optimistic ?? followingQuery.data ?? false;

  const mutation = useMutation({
    mutationFn: () => toggleFollow(user!.id, targetId, username, following),
    onMutate: () => setOptimistic(!following),
    onError: () => setOptimistic(following),
    onSettled: () =>
      queryClient.invalidateQueries({
        queryKey: ["is-following", user?.id, targetId],
      }),
  });

  if (user?.id === targetId) return null;

  return (
    <button
      onClick={() => mutation.mutate()}
      className={cn(
        "shrink-0 rounded-full px-4 py-1.5 text-[13px] font-bold transition-colors",
        following
          ? "border border-border text-foreground hover:bg-secondary"
          : "bg-primary text-primary-foreground hover:opacity-90"
      )}
    >
      {following ? "Following" : "Follow"}
    </button>
  );
}

/** Reusable row used by the follow lists and people suggestions. */
export function UserRow({
  person,
  onNavigate,
}: {
  person: WhisperFollowUser;
  onNavigate?: () => void;
}) {
  return (
    <div className="flex items-center gap-3 px-1 py-2.5">
      <Link
        to={`/u/${person.username}`}
        onClick={onNavigate}
        className="flex min-w-0 flex-1 items-center gap-3"
      >
        <Avatar
          url={person.profile?.profile_image_url}
          name={person.username}
          size={46}
        />
        <div className="min-w-0 flex-1">
          <p className="flex items-center gap-1 truncate text-[15px] font-semibold">
            @{person.username}
            <UserBadges profile={person.profile} size={13} />
          </p>
          {person.profile?.display_name && (
            <p className="truncate text-[13px] text-muted-foreground">
              {person.profile.display_name}
            </p>
          )}
        </div>
      </Link>
      <FollowButton targetId={person.userId} username={person.username} />
    </div>
  );
}

export function FollowListDialog({
  open,
  onOpenChange,
  userId,
  username,
  initialTab,
}: FollowListDialogProps) {
  const [tab, setTab] = useState<FollowTab>(initialTab);
  const [query, setQuery] = useState<string>("");

  const followersQuery = useQuery({
    queryKey: ["followers", userId],
    queryFn: () => fetchFollowers(userId),
    enabled: open,
  });
  const followingQuery = useQuery({
    queryKey: ["following", userId],
    queryFn: () => fetchFollowing(userId),
    enabled: open,
  });

  const rows = tab === "followers" ? followersQuery.data ?? [] : followingQuery.data ?? [];
  const loading =
    tab === "followers" ? followersQuery.isLoading : followingQuery.isLoading;

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return rows;
    return rows.filter(
      (r) =>
        r.username.toLowerCase().includes(q) ||
        (r.profile?.display_name ?? "").toLowerCase().includes(q)
    );
  }, [rows, query]);

  return (
    <Dialog
      open={open}
      onOpenChange={(o) => {
        if (o) setTab(initialTab);
        setQuery("");
        onOpenChange(o);
      }}
    >
      <DialogContent className="max-w-md gap-0 p-0">
        <DialogHeader className="px-5 pt-5">
          <DialogTitle className="text-center text-[16px]">
            @{username}
          </DialogTitle>
        </DialogHeader>

        <div className="mt-3 grid grid-cols-2 border-b border-border">
          {(["followers", "following"] as FollowTab[]).map((t) => (
            <button
              key={t}
              onClick={() => setTab(t)}
              className={cn(
                "relative py-2.5 text-[14px] font-semibold capitalize transition-colors",
                tab === t ? "text-foreground" : "text-muted-foreground"
              )}
            >
              {t}
              {tab === t && (
                <span className="absolute inset-x-0 -bottom-px mx-auto h-0.5 w-2/3 rounded-full bg-foreground" />
              )}
            </button>
          ))}
        </div>

        <div className="px-4 pt-3">
          <div className="flex items-center gap-2 rounded-full border border-border bg-card px-3.5 py-2">
            <Search className="h-4 w-4 text-muted-foreground" />
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search"
              className="min-w-0 flex-1 bg-transparent text-sm outline-none"
            />
          </div>
        </div>

        <div className="max-h-[55vh] overflow-y-auto px-4 pb-4 pt-1">
          {loading ? (
            <p className="py-10 text-center text-sm text-muted-foreground">
              Loading…
            </p>
          ) : filtered.length === 0 ? (
            <p className="py-10 text-center text-sm text-muted-foreground">
              {tab === "followers"
                ? "No followers yet."
                : "Not following anyone yet."}
            </p>
          ) : (
            filtered.map((person) => (
              <UserRow
                key={person.userId}
                person={person}
                onNavigate={() => onOpenChange(false)}
              />
            ))
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
