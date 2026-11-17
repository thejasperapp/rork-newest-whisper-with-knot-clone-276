import { memo, useMemo } from "react";
import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import {
  Radio,
  Users,
  Mic2,
  Plus,
  Headphones,
  ArrowRight,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { useAuth } from "@/hooks/useAuth";
import { Avatar } from "@/components/Avatar";
import { supabase } from "@/lib/supabase";
import { fetchProfilesByIds } from "@/lib/api";

/* ------------------------------------------------------------------ */
/*  Types                                                              */
/* ------------------------------------------------------------------ */

interface LiveRoom {
  id: string;
  name: string;
  description: string | null;
  host_id: string;
  listener_count: number;
  is_live: boolean;
  created_at: string;
  topic: string | null;
  cohost_ids?: string[];
}

/* ------------------------------------------------------------------ */
/*  Data fetching                                                      */
/* ------------------------------------------------------------------ */

/**
 * ONLY rooms that are genuinely live right now. Stories used to leak into
 * this rail (posting a story made you look "Live") — the rail now reads
 * exclusively from whisper_live_rooms.
 */
async function fetchLiveRooms(): Promise<LiveRoom[]> {
  const { data } = await supabase
    .from("whisper_live_rooms")
    .select("id, name, description, host_id, listener_count, is_live, created_at, topic")
    .eq("is_live", true)
    .order("listener_count", { ascending: false })
    .limit(8);
  return (data as LiveRoom[] | null) ?? [];
}

/* ------------------------------------------------------------------ */
/*  Sub-components                                                     */
/* ------------------------------------------------------------------ */

function LivePill({ compact }: { compact?: boolean }) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1 rounded-full bg-rose-500/10 px-1.5 py-0.5 text-[10px] font-bold uppercase tracking-wide text-rose-500",
        compact && "px-1 py-0 text-[9px]"
      )}
    >
      <span className="relative flex h-1.5 w-1.5">
        <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-rose-400 opacity-75" />
        <span className="relative inline-flex h-1.5 w-1.5 rounded-full bg-rose-500" />
      </span>
      LIVE
    </span>
  );
}

function StackedAvatars({
  ids,
  profiles,
  size = 28,
}: {
  ids: string[];
  profiles: Record<string, { username: string; profile_image_url: string | null }>;
  size?: number;
}) {
  return (
    <div className="flex -space-x-2.5">
      {ids.slice(0, 3).map((id, i) => (
        <span
          key={id}
          className="rounded-full ring-2 ring-background"
          style={{ zIndex: ids.length - i }}
        >
          <Avatar
            url={profiles[id]?.profile_image_url ?? null}
            name={profiles[id]?.username ?? "user"}
            size={size}
          />
        </span>
      ))}
      {ids.length > 3 && (
        <span
          className="flex h-7 w-7 items-center justify-center rounded-full bg-secondary text-[10px] font-bold ring-2 ring-background"
          style={{ zIndex: 0 }}
        >
          +{ids.length - 3}
        </span>
      )}
    </div>
  );
}

function RoomCard({
  room,
  hostProfiles,
}: {
  room: LiveRoom;
  hostProfiles: Record<string, { username: string; profile_image_url: string | null }>;
}) {
  const hostIds = [room.host_id, ...(room.cohost_ids ?? [])].filter(Boolean);
  return (
    <Link
      to={`/live/${room.id}`}
      className="group relative block overflow-hidden rounded-2xl border border-border/50 bg-background/60 p-3 transition-all hover:border-rose-500/30 hover:bg-rose-500/[0.03]"
    >
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0 flex-1">
          <div className="mb-1 flex items-center gap-2">
            <LivePill compact />
            <span className="text-[11px] font-medium text-muted-foreground">
              {room.listener_count.toLocaleString()} watching
            </span>
          </div>
          <h4 className="truncate text-[14px] font-bold leading-tight">{room.name}</h4>
          {room.description && (
            <p className="mt-0.5 line-clamp-2 text-[12px] text-muted-foreground">
              {room.description}
            </p>
          )}
          {room.topic && (
            <span className="mt-2 inline-block rounded-full bg-secondary px-2 py-0.5 text-[10px] font-semibold text-muted-foreground">
              {room.topic}
            </span>
          )}
        </div>
        <div className="shrink-0">
          <StackedAvatars ids={hostIds} profiles={hostProfiles} size={30} />
        </div>
      </div>
      <div className="mt-3 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Mic2 className="h-3.5 w-3.5 text-rose-500" />
          <span className="text-[11px] font-medium text-muted-foreground">
            {hostProfiles[room.host_id]?.username ?? "host"}
          </span>
        </div>
        <span className="flex h-7 w-7 items-center justify-center rounded-full bg-rose-500 text-white opacity-0 transition-all group-hover:opacity-100">
          <Headphones className="h-3.5 w-3.5" />
        </span>
      </div>
    </Link>
  );
}

/** Hosts who are ACTUALLY live — red gradient ring + LIVE badge, one tap joins. */
function LiveHostRow({
  rooms,
  profiles,
}: {
  rooms: LiveRoom[];
  profiles: Record<string, { username: string; profile_image_url: string | null }>;
}) {
  return (
    <div className="flex gap-3 overflow-x-auto pb-2 pt-1">
      {rooms.map((room) => (
        <Link
          key={room.id}
          to={`/live/${room.id}`}
          className="flex shrink-0 flex-col items-center gap-1.5"
        >
          <span className="relative">
            <span className="block rounded-full bg-gradient-to-br from-rose-500 via-orange-500 to-pink-600 p-[2.5px]">
              <span className="block rounded-full border-2 border-background">
                <Avatar
                  url={profiles[room.host_id]?.profile_image_url ?? null}
                  name={profiles[room.host_id]?.username ?? "host"}
                  size={52}
                />
              </span>
            </span>
            <span className="absolute -bottom-1 left-1/2 -translate-x-1/2 rounded-[5px] border-2 border-background bg-gradient-to-r from-rose-500 to-orange-500 px-1.5 py-px text-[7px] font-bold uppercase tracking-wider text-white">
              LIVE
            </span>
          </span>
          <span className="max-w-[56px] truncate text-[11px] font-semibold">
            @{profiles[room.host_id]?.username ?? "live"}
          </span>
        </Link>
      ))}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Main component                                                     */
/* ------------------------------------------------------------------ */

function LiveRailBase() {
  const { user } = useAuth();
  const roomsQuery = useQuery({
    queryKey: ["live-rooms"],
    queryFn: fetchLiveRooms,
    staleTime: 15_000,
  });

  const rooms = roomsQuery.data ?? [];

  const roomHostIds = useMemo(
    () => Array.from(new Set(rooms.flatMap((r) => [r.host_id, ...(r.cohost_ids ?? [])]))),
    [rooms]
  );
  const hostProfilesQuery = useQuery({
    queryKey: ["live-room-hosts", roomHostIds],
    queryFn: () => fetchProfilesByIds(roomHostIds),
    enabled: roomHostIds.length > 0,
  });
  const hostProfiles = hostProfilesQuery.data ?? {};

  if (!user) return null;

  return (
    <div className="space-y-5">
      {/* Live hosts — only people with a room that is live RIGHT NOW. */}
      {rooms.length > 0 && (
        <section className="rounded-2xl border border-border/50 bg-background/60 p-4 backdrop-blur-sm">
          <div className="mb-3 flex items-center justify-between">
            <h3 className="flex items-center gap-2 text-sm font-bold">
              <Radio className="h-4 w-4 text-rose-500" />
              Live now
            </h3>
            <Link
              to="/live"
              className="flex items-center gap-1 text-[12px] font-semibold text-rose-500 transition-colors hover:text-rose-400"
            >
              See all <ArrowRight className="h-3 w-3" />
            </Link>
          </div>
          <LiveHostRow rooms={rooms} profiles={hostProfiles} />
        </section>
      )}

      {/* Live rooms */}
      <section className="rounded-2xl border border-border/50 bg-background/60 p-4 backdrop-blur-sm">
        <div className="mb-3 flex items-center justify-between">
          <h3 className="flex items-center gap-2 text-sm font-bold">
            <Mic2 className="h-4 w-4 text-rose-500" />
            Live on Whisper
          </h3>
          <Link
            to="/live"
            className="flex items-center gap-1 text-[12px] font-semibold text-rose-500 transition-colors hover:text-rose-400"
          >
            Explore <ArrowRight className="h-3 w-3" />
          </Link>
        </div>

        {rooms.length > 0 ? (
          <div className="flex flex-col gap-2.5">
            {rooms.slice(0, 4).map((room) => (
              <RoomCard key={room.id} room={room} hostProfiles={hostProfiles} />
            ))}
          </div>
        ) : (
          <div className="rounded-xl border border-dashed border-border/60 bg-secondary/20 p-4 text-center">
            <p className="text-[13px] font-semibold text-foreground/80">
              Nobody's live right now
            </p>
            <p className="mt-1 text-[12px] text-muted-foreground">
              Go live — your followers get pinged.
            </p>
            <Link
              to="/live/start"
              className="mt-3 inline-flex items-center gap-1.5 rounded-full bg-gradient-to-r from-rose-500 to-orange-500 px-4 py-2 text-[12px] font-bold text-white transition-transform active:scale-95"
            >
              <Plus className="h-3.5 w-3.5" />
              Go live
            </Link>
          </div>
        )}
      </section>

      {/* Watching stats teaser — real numbers only */}
      {rooms.length > 0 && (
        <section className="rounded-2xl border border-border/50 bg-background/60 p-4 backdrop-blur-sm">
          <div className="flex items-center gap-3">
            <span className="flex h-10 w-10 items-center justify-center rounded-full bg-rose-500/10">
              <Users className="h-5 w-5 text-rose-500" />
            </span>
            <div className="min-w-0">
              <p className="text-sm font-bold">
                {rooms
                  .reduce((sum, r) => sum + (r.listener_count ?? 0), 0)
                  .toLocaleString()}{" "}
                watching live
              </p>
              <p className="text-[12px] text-muted-foreground">
                across {rooms.length} {rooms.length === 1 ? "room" : "rooms"}
              </p>
            </div>
          </div>
        </section>
      )}
    </div>
  );
}

export const LiveRail = memo(LiveRailBase);
