import { useEffect, useMemo, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Heart, MessageCircle, Radio, Repeat2, UserPlus } from "lucide-react";

import { supabase } from "@/lib/supabase";
import { contentPreview } from "@/lib/contentPreview";

import { Header } from "@/components/Header";
import { Avatar } from "@/components/Avatar";
import { UserBadges } from "@/components/UserBadges";
import { PullToRefresh } from "@/components/PullToRefresh";
import { useAuth } from "@/hooks/useAuth";
import {
  fetchActivity,
  fetchIncomingFollowRequests,
  fetchProfilesByIds,
  isFollowing,
  respondToFollowRequest,
  toggleFollow,
  type WhisperFollowRequest,
} from "@/lib/api";
import { markActivitySeen } from "@/lib/settings";
import { timeAgo } from "@/lib/format";
import { cn } from "@/lib/utils";
import type { WhisperActivity } from "@/lib/types";

/**
 * Solid type badges with a white glyph — the iOS grammar (the exact tints
 * of the native Activity tab). The old 12%-tinted plates with a same-colour
 * icon blended into themselves.
 */
const ICON: Record<
  WhisperActivity["kind"],
  { icon: typeof Heart; bg: string; filled: boolean }
> = {
  like: { icon: Heart, bg: "bg-[#F25273]", filled: true },
  comment: { icon: MessageCircle, bg: "bg-[#5C8CF2]", filled: true },
  repost: { icon: Repeat2, bg: "bg-[#33C780]", filled: false },
  follow: { icon: UserPlus, bg: "bg-[#FF8C2E]", filled: false },
};

/** Bold ink section title — Instagram's "Today / This week" grammar. */
function SectionTitle({
  children,
  count,
  liveDot,
}: {
  children: React.ReactNode;
  count?: number;
  liveDot?: boolean;
}) {
  return (
    <p className="flex items-center gap-2 px-4 pb-1 pt-4 text-[15px] font-bold text-foreground">
      {liveDot && <span className="h-2 w-2 rounded-full bg-[#F22659]" aria-hidden />}
      {children}
      {typeof count === "number" && count > 0 && (
        <span className="rounded-full bg-[#FF7340] px-1.5 py-px text-[11px] font-black tabular-nums text-white">
          {count}
        </span>
      )}
    </p>
  );
}

function verb(kind: WhisperActivity["kind"]): string {
  switch (kind) {
    case "like":
      return "liked your whisper";
    case "comment":
      return "commented";
    case "repost":
      return "reposted your whisper";
    case "follow":
      return "started following you";
  }
}

function FollowBackButton({ targetId, username }: { targetId: string; username: string }) {
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
      onClick={(e) => {
        e.preventDefault();
        e.stopPropagation();
        mutation.mutate();
      }}
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

interface LiveAlertRow {
  id: string;
  host_id: string;
  host_username: string;
  room_id: string;
  room_name: string;
  created_at: string;
}

/**
 * "Live now" — go-live alerts fanned out to followers (whisper_live_alerts,
 * live-v2). Only rooms that are STILL live survive the filter, deduped to
 * one row per host; tapping joins the live. Quietly renders nothing until
 * the migration runs.
 */
function LiveNowSection() {
  const { user } = useAuth();
  const navigate = useNavigate();

  const alertsQuery = useQuery({
    queryKey: ["live-alerts", user?.id],
    queryFn: async (): Promise<LiveAlertRow[]> => {
      const since = new Date(Date.now() - 6 * 3600_000).toISOString();
      const { data, error } = await supabase
        .from("whisper_live_alerts")
        .select("id, host_id, host_username, room_id, room_name, created_at")
        .eq("follower_id", user!.id)
        .gte("created_at", since)
        .order("created_at", { ascending: false })
        .limit(12);
      if (error || !data || data.length === 0) return [];
      const rows = data as LiveAlertRow[];
      const roomIds = Array.from(new Set(rows.map((r) => r.room_id)));
      const { data: liveRooms } = await supabase
        .from("whisper_live_rooms")
        .select("id")
        .in("id", roomIds)
        .eq("is_live", true);
      const liveSet = new Set(
        ((liveRooms as { id: string }[] | null) ?? []).map((r) => r.id)
      );
      const seenHosts = new Set<string>();
      return rows.filter((r) => {
        if (!liveSet.has(r.room_id) || seenHosts.has(r.host_id)) return false;
        seenHosts.add(r.host_id);
        return true;
      });
    },
    enabled: !!user,
    refetchInterval: 60_000,
  });

  const alerts = alertsQuery.data ?? [];
  if (alerts.length === 0) return null;

  return (
    <div className="border-b border-border">
      <SectionTitle liveDot>Live now</SectionTitle>
      {alerts.map((a) => (
        <button
          key={a.id}
          onClick={() => navigate(`/live/${a.room_id}`)}
          className="flex w-full items-center gap-3 px-4 py-3 text-left transition-colors hover:bg-secondary/40"
        >
          <div className="relative shrink-0">
            <Avatar name={a.host_username} size={44} />
            <span className="absolute -bottom-1 -right-1 flex h-[22px] w-[22px] items-center justify-center rounded-full border-2 border-background bg-[#F22659] text-white">
              <Radio className="h-3 w-3" strokeWidth={2.5} />
            </span>
          </div>
          <div className="min-w-0 flex-1">
            <p className="text-[15px] leading-snug">
              <span className="font-bold">@{a.host_username}</span>{" "}
              <span className="text-foreground">went live</span>{" "}
              <span className="text-muted-foreground">{timeAgo(a.created_at)}</span>
            </p>
            {a.room_name && (
              <p className="mt-0.5 truncate text-[13px] text-muted-foreground">
                {a.room_name}
              </p>
            )}
          </div>
          <span className="flex shrink-0 items-center gap-1.5 rounded-full bg-[#F22659] px-3.5 py-1.5 text-[12px] font-black uppercase tracking-wide text-white">
            <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-white" />
            Join
          </span>
        </button>
      ))}
    </div>
  );
}

/**
 * Pending follow-request rows with Instagram-style Confirm / Delete buttons.
 * Only renders when the signed-in (private) account has requests waiting.
 */
function FollowRequestsSection() {
  const { user } = useAuth();
  const queryClient = useQueryClient();

  const requestsQuery = useQuery({
    queryKey: ["follow-requests", user?.id],
    queryFn: () => fetchIncomingFollowRequests(user!.id),
    enabled: !!user,
  });
  const requests = requestsQuery.data ?? [];

  const requesterIds = useMemo(
    () => requests.map((r) => r.requester_id),
    [requests]
  );
  const profilesQuery = useQuery({
    queryKey: ["profiles", requesterIds],
    queryFn: () => fetchProfilesByIds(requesterIds),
    enabled: requesterIds.length > 0,
  });
  const profiles = profilesQuery.data ?? {};

  const respondMutation = useMutation({
    mutationFn: ({
      request,
      approve,
    }: {
      request: WhisperFollowRequest;
      approve: boolean;
    }) => respondToFollowRequest(request, approve),
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: ["follow-requests", user?.id] });
      queryClient.invalidateQueries({ queryKey: ["follow-counts"] });
    },
  });

  if (requests.length === 0) return null;

  return (
    <div className="border-b border-border">
      <SectionTitle count={requests.length}>Follow requests</SectionTitle>
      {requests.map((req) => {
        const profile = profiles[req.requester_id];
        const busy = respondMutation.isPending;
        return (
          <div key={req.id} className="flex items-center gap-3 px-4 py-3">
            <Link to={`/u/${req.requester_username}`} className="shrink-0">
              <Avatar
                url={profile?.profile_image_url}
                name={req.requester_username}
                size={44}
              />
            </Link>
            <div className="min-w-0 flex-1">
              <Link
                to={`/u/${req.requester_username}`}
                className="block truncate text-[15px] font-bold hover:underline"
              >
                @{req.requester_username}
              </Link>
              <p className="text-[13px] text-muted-foreground">
                Wants to follow you
              </p>
            </div>
            <div className="flex shrink-0 items-center gap-2">
              <button
                disabled={busy}
                onClick={() =>
                  respondMutation.mutate({ request: req, approve: true })
                }
                className="rounded-full bg-primary px-4 py-1.5 text-[13px] font-bold text-primary-foreground transition-opacity hover:opacity-90 disabled:opacity-50"
              >
                Confirm
              </button>
              <button
                disabled={busy}
                onClick={() =>
                  respondMutation.mutate({ request: req, approve: false })
                }
                className="rounded-full border border-border px-4 py-1.5 text-[13px] font-bold transition-colors hover:bg-secondary disabled:opacity-50"
              >
                Delete
              </button>
            </div>
          </div>
        );
      })}
    </div>
  );
}

function ActivityRow({ event: e }: { event: WhisperActivity }) {
  const navigate = useNavigate();
  const meta = ICON[e.kind];
  const Icon = meta.icon;
  const go = (): void => {
    if (e.postId) navigate(`/?post=${encodeURIComponent(e.postId)}`);
    else navigate(`/u/${encodeURIComponent(e.actorUsername)}?id=${encodeURIComponent(e.actorUserId)}`);
  };
  return (
    <div className="relative isolate flex w-full items-center gap-3 border-b border-border px-4 py-3 text-left transition-colors last:border-b-0 hover:bg-secondary/40">
      <button type="button" onClick={go} aria-label={`Open activity: ${e.actorUsername} ${verb(e.kind)}`} className="absolute inset-0 -z-10 rounded-lg focus-visible:outline focus-visible:outline-2 focus-visible:outline-ring" />
      <div className="pointer-events-none relative shrink-0">
        <Avatar url={e.actorProfile?.profile_image_url} name={e.actorUsername} size={44} />
        <span
          className={cn(
            "absolute -bottom-1 -right-1 flex h-[22px] w-[22px] items-center justify-center rounded-full border-2 border-background text-white",
            meta.bg
          )}
        >
          <Icon className="h-3 w-3" strokeWidth={2.5} fill={meta.filled ? "currentColor" : "none"} />
        </span>
      </div>

      <div className="pointer-events-none min-w-0 flex-1">
        <p className="text-[15px] leading-snug text-foreground">
          <Link
            to={`/u/${encodeURIComponent(e.actorUsername)}?id=${encodeURIComponent(e.actorUserId)}`}
            onClick={(ev) => ev.stopPropagation()}
            className="pointer-events-auto inline-flex items-center gap-1 font-bold hover:underline"
          >
            @{e.actorUsername}
            <UserBadges profile={e.actorProfile} size={13} />
          </Link>{" "}
          <span>{verb(e.kind)}</span>{" "}
          <span className="text-muted-foreground">{timeAgo(e.createdAt)}</span>
        </p>
        {e.preview && (
          <p className="mt-0.5 truncate text-[13px] text-muted-foreground">{contentPreview(e.preview, "Post")}</p>
        )}
      </div>

      {e.kind === "follow" && (
        <FollowBackButton targetId={e.actorUserId} username={e.actorUsername} />
      )}
    </div>
  );
}

export default function Notifications() {
  const { user } = useAuth();

  const activityQuery = useQuery({
    queryKey: ["activity", user?.id],
    queryFn: () => fetchActivity(user!.id),
    enabled: !!user,
  });

  // Mark everything seen once on mount so the nav dot clears.
  useEffect(() => {
    markActivitySeen();
  }, []);

  const events = useMemo(() => activityQuery.data ?? [], [activityQuery.data]);

  // Today / This week / Earlier — the iOS Activity tab's grouping.
  const groups = useMemo(() => {
    const startOfToday = new Date();
    startOfToday.setHours(0, 0, 0, 0);
    const weekAgo = Date.now() - 7 * 86_400_000;
    const today: WhisperActivity[] = [];
    const week: WhisperActivity[] = [];
    const earlier: WhisperActivity[] = [];
    for (const e of events) {
      const t = e.createdAt ? new Date(e.createdAt).getTime() : 0;
      if (t >= startOfToday.getTime()) today.push(e);
      else if (t >= weekAgo) week.push(e);
      else earlier.push(e);
    }
    return [
      { title: "Today", items: today },
      { title: "This week", items: week },
      { title: "Earlier", items: earlier },
    ].filter((g) => g.items.length > 0);
  }, [events]);

  const handleRefresh = async (): Promise<void> => {
    await activityQuery.refetch();
    markActivitySeen();
  };

  return (
    <div>
      <Header title="Activity" hideBell />

      <PullToRefresh onRefresh={handleRefresh}>
        <div className="px-0 pt-0 sm:px-0 sm:pt-4">
          <div className="overflow-hidden border-y border-border bg-background sm:rounded-[22px] sm:border sm:shadow-sm">
            <LiveNowSection />
            <FollowRequestsSection />
            {activityQuery.isLoading && (
              <div className="space-y-4 p-4">
                {[0, 1, 2, 3].map((i) => (
                  <div key={i} className="flex animate-pulse items-center gap-3">
                    <div className="h-11 w-11 rounded-full bg-secondary" />
                    <div className="h-3 w-44 rounded bg-secondary" />
                  </div>
                ))}
              </div>
            )}

            {!activityQuery.isLoading && events.length === 0 && (
              <div className="flex flex-col items-center gap-3 px-6 py-24 text-center">
                <div className="flex h-16 w-16 items-center justify-center rounded-full bg-secondary">
                  <Heart className="h-7 w-7 text-muted-foreground" />
                </div>
                <h2 className="font-display text-lg font-bold">No activity yet</h2>
                <p className="max-w-xs text-sm text-muted-foreground">
                  Likes, comments, reposts and new followers will show up here.
                </p>
              </div>
            )}

            {groups.map((group) => (
              <section key={group.title}>
                <SectionTitle>{group.title}</SectionTitle>
                {group.items.map((e) => (
                  <ActivityRow key={e.id} event={e} />
                ))}
              </section>
            ))}
          </div>
        </div>
      </PullToRefresh>
    </div>
  );
}
