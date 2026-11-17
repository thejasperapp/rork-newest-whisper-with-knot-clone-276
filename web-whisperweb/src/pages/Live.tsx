import { Link, useNavigate } from "react-router-dom";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import {
  Radio,
  Mic2,
  Plus,
  ArrowLeft,
  Users,
  Headphones,
  CalendarClock,
  Trash2,
  Share2,
  Timer,
  Play,
} from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { Avatar } from "@/components/Avatar";
import { FloatingHeader, FloatingButton } from "@/components/FloatingHeader";
import { useAuth } from "@/hooks/useAuth";
import { supabase } from "@/lib/supabase";
import { fetchProfilesByIds } from "@/lib/api";
import { toast } from "sonner";
import { cn } from "@/lib/utils";

interface LiveRoom {
  id: string;
  name: string;
  description: string | null;
  topic: string | null;
  host_id: string;
  listener_count: number;
  is_live: boolean;
  created_at: string;
  scheduled_at?: string | null;
}

interface RoomSpeaker {
  room_id: string;
  user_id: string;
  is_host: boolean;
}

/** Live rooms + upcoming scheduled rooms. Falls back to the legacy
 * live-only query when the `scheduled_at` column hasn't been migrated yet. */
async function fetchLiveRooms(): Promise<LiveRoom[]> {
  const nowISO = new Date().toISOString();
  const { data, error } = await supabase
    .from("whisper_live_rooms")
    .select("id, name, description, topic, host_id, listener_count, is_live, created_at, scheduled_at")
    .or(`is_live.eq.true,scheduled_at.gt.${nowISO}`)
    .order("created_at", { ascending: false });
  if (!error && data) return data as LiveRoom[];
  const { data: legacy } = await supabase
    .from("whisper_live_rooms")
    .select("id, name, description, topic, host_id, listener_count, is_live, created_at")
    .eq("is_live", true)
    .order("listener_count", { ascending: false });
  return (legacy as LiveRoom[] | null) ?? [];
}

async function fetchRoomSpeakers(roomIds: string[]): Promise<Record<string, RoomSpeaker[]>> {
  if (roomIds.length === 0) return {};
  const { data } = await supabase
    .from("whisper_live_room_speakers")
    .select("room_id, user_id, is_host")
    .in("room_id", roomIds);
  const map: Record<string, RoomSpeaker[]> = {};
  for (const row of (data as RoomSpeaker[] | null) ?? []) {
    (map[row.room_id] ??= []).push(row);
  }
  // Host first so the cluster leads with the host's face.
  for (const key of Object.keys(map)) {
    map[key].sort((a, b) => Number(b.is_host) - Number(a.is_host));
  }
  return map;
}

function isUpcoming(room: LiveRoom): boolean {
  if (room.is_live || !room.scheduled_at) return false;
  return new Date(room.scheduled_at).getTime() > Date.now();
}

/** Deterministic cover gradient per room — Twitch-style channel colors. */
const COVER_GRADIENTS: [string, string][] = [
  ["#F43F5E", "#FB923C"],
  ["#8B5CF6", "#EC4899"],
  ["#0EA5E9", "#8B5CF6"],
  ["#10B981", "#0EA5E9"],
  ["#F59E0B", "#EF4444"],
  ["#6366F1", "#14B8A6"],
];
function coverFor(roomId: string): [string, string] {
  let h = 0;
  for (let i = 0; i < roomId.length; i++) h = (h * 31 + roomId.charCodeAt(i)) >>> 0;
  return COVER_GRADIENTS[h % COVER_GRADIENTS.length];
}

export default function Live() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  const { data: rooms = [] } = useQuery({
    queryKey: ["live-rooms-page"],
    queryFn: fetchLiveRooms,
    staleTime: 15_000,
  });

  // Realtime: cards appear/disappear the moment lives start or end.
  useEffect(() => {
    const channel = supabase
      .channel("live-rooms-page")
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "whisper_live_rooms" },
        () => queryClient.invalidateQueries({ queryKey: ["live-rooms-page"] })
      )
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [queryClient]);

  const roomIds = rooms.map((r) => r.id);
  const speakersQuery = useQuery({
    queryKey: ["live-rooms-speakers", roomIds],
    queryFn: () => fetchRoomSpeakers(roomIds),
    enabled: roomIds.length > 0,
  });
  const speakersByRoom = speakersQuery.data ?? {};

  const allUserIds = Array.from(
    new Set(
      rooms
        .map((r) => r.host_id)
        .concat(Object.values(speakersByRoom).flat().map((s) => s.user_id))
        .filter(Boolean)
    )
  );
  const profilesQuery = useQuery({
    queryKey: ["live-host-profiles", allUserIds],
    queryFn: () => fetchProfilesByIds(allUserIds),
    enabled: allUserIds.length > 0,
  });
  const profiles = profilesQuery.data ?? {};

  // Who I follow — powers the "Following · live now" rail (go-live surfacing).
  const followsQuery = useQuery({
    queryKey: ["live-my-follows", user?.id ?? "anon"],
    enabled: !!user,
    queryFn: async (): Promise<string[]> => {
      const { data } = await supabase
        .from("whisper_follows")
        .select("followee_id")
        .eq("follower_id", user!.id)
        .limit(1000);
      return ((data as { followee_id: string }[] | null) ?? []).map(
        (r) => r.followee_id
      );
    },
  });
  const followedIds = useMemo(
    () => new Set(followsQuery.data ?? []),
    [followsQuery.data]
  );

  const [selectedTopic, setSelectedTopic] = useState<string>("");
  const topics = useMemo(
    () =>
      Array.from(
        new Set(rooms.map((r) => (r.topic ?? "").trim()).filter(Boolean))
      ).slice(0, 12),
    [rooms]
  );

  const matchesTopic = (r: LiveRoom): boolean =>
    !selectedTopic || (r.topic ?? "").trim() === selectedTopic;
  const liveNowAll = rooms
    .filter((r) => r.is_live && matchesTopic(r))
    .slice()
    .sort((a, b) => (b.listener_count ?? 0) - (a.listener_count ?? 0));
  const featured = liveNowAll[0] ?? null;
  const liveRest = liveNowAll.slice(1);
  const upcoming = rooms.filter((r) => isUpcoming(r) && matchesTopic(r));
  const followedLive = rooms.filter(
    (r) => r.is_live && followedIds.has(r.host_id)
  );

  const shareRoom = async (room: LiveRoom): Promise<void> => {
    const url = `https://mydailywhisper.com/live/${room.id}`;
    try {
      if (navigator.share) {
        await navigator.share({ title: room.name, url });
      } else {
        await navigator.clipboard.writeText(url);
        toast.success("Live link copied");
      }
    } catch {
      // Share sheet dismissed.
    }
  };

  const deleteRoom = async (room: LiveRoom): Promise<void> => {
    if (!window.confirm("Delete this live? This removes it for everyone.")) return;
    const { error } = await supabase.from("whisper_live_rooms").delete().eq("id", room.id);
    if (error) {
      toast.error("Could not delete the live");
      return;
    }
    toast.success("Live deleted");
    queryClient.invalidateQueries({ queryKey: ["live-rooms-page"] });
  };

  const startScheduled = async (room: LiveRoom): Promise<void> => {
    const { error } = await supabase
      .from("whisper_live_rooms")
      .update({ is_live: true })
      .eq("id", room.id);
    if (error) {
      toast.error("Could not start the live");
      return;
    }
    navigate(`/live/${room.id}`);
  };

  /** Small management strip under a card (share + delete/go-live). */
  const manageRow = (room: LiveRoom): JSX.Element | null => {
    const isMine = user?.id === room.host_id;
    const upcomingRoom = isUpcoming(room);
    if (!isMine && !upcomingRoom) return null;
    return (
      <div className="flex items-center gap-2 px-1 pt-1.5">
        {upcomingRoom && room.scheduled_at && (
          <Countdown
            target={room.scheduled_at}
            onDone={() => queryClient.invalidateQueries({ queryKey: ["live-rooms-page"] })}
          />
        )}
        <div className="ml-auto flex items-center gap-1.5">
          {upcomingRoom && isMine && (
            <button
              onClick={() => void startScheduled(room)}
              className="rounded-full bg-rose-500 px-3.5 py-1.5 text-[11px] font-bold text-white transition-transform active:scale-95"
            >
              Go live now
            </button>
          )}
          <button
            onClick={() => void shareRoom(room)}
            className="flex h-7 w-7 items-center justify-center rounded-full bg-secondary text-muted-foreground transition-all hover:text-foreground active:scale-90"
            aria-label="Share live link"
          >
            <Share2 className="h-3.5 w-3.5" />
          </button>
          {isMine && (
            <button
              onClick={() => void deleteRoom(room)}
              className="flex h-7 w-7 items-center justify-center rounded-full bg-red-500/10 text-red-500 transition-all active:scale-90"
              aria-label="Delete live"
            >
              <Trash2 className="h-3.5 w-3.5" />
            </button>
          )}
        </div>
      </div>
    );
  };

  /** Twitch-style stream preview card — 16:9 cover, LIVE badge, viewer chip. */
  const previewCard = (room: LiveRoom, big = false): JSX.Element => {
    const speakers = speakersByRoom[room.id] ?? [];
    const cohostCount = Math.max(0, speakers.length - 1);
    const hostProfile = profiles[room.host_id];
    const [c1, c2] = coverFor(room.id);

    return (
      <div key={room.id}>
        <Link
          to={`/live/${room.id}`}
          className="group block overflow-hidden rounded-[18px] border border-border/50 bg-card transition-all hover:-translate-y-0.5 hover:border-rose-500/40 hover:shadow-lg active:scale-[0.99]"
        >
          {/* Cover — gradient stage with the host front and center. */}
          <div
            className={cn("relative w-full", big ? "aspect-[2/1]" : "aspect-video")}
            style={{
              backgroundImage: `radial-gradient(120% 140% at 20% 0%, ${c1}cc, ${c2}99 55%, #111 130%)`,
            }}
          >
            {/* Host avatar centered like an IG live tile */}
            <div className="absolute inset-0 flex items-center justify-center">
              <div className="rounded-full bg-white/15 p-[3px] backdrop-blur-sm">
                <div className="animate-pulse rounded-full bg-gradient-to-br from-rose-500 via-orange-500 to-pink-600 p-[3px]">
                  <div className="rounded-full border-2 border-white/70">
                    <Avatar
                      url={hostProfile?.profile_image_url ?? null}
                      name={hostProfile?.username ?? "host"}
                      size={big ? 84 : 60}
                    />
                  </div>
                </div>
              </div>
            </div>
            {/* LIVE badge + viewers — Twitch chrome */}
            <span className="absolute left-2.5 top-2.5 rounded-md bg-rose-600 px-2 py-0.5 text-[11px] font-black uppercase tracking-wide text-white shadow">
              LIVE
            </span>
            <span className="absolute bottom-2.5 left-2.5 flex items-center gap-1 rounded-md bg-black/60 px-2 py-0.5 text-[11px] font-bold text-white backdrop-blur-sm">
              <Users className="h-3 w-3" />
              {room.listener_count.toLocaleString()} watching
            </span>
            {cohostCount > 0 && (
              <span className="absolute bottom-2.5 right-2.5 rounded-md bg-black/60 px-2 py-0.5 text-[10px] font-bold text-white backdrop-blur-sm">
                +{cohostCount} live together
              </span>
            )}
            {/* Hover play affordance */}
            <span className="absolute right-2.5 top-2.5 flex h-8 w-8 items-center justify-center rounded-full bg-white/90 text-rose-600 opacity-0 shadow transition-opacity group-hover:opacity-100">
              <Play className="ml-0.5 h-4 w-4 fill-current" />
            </span>
          </div>

          {/* Meta row — title, host, category (Twitch grammar). */}
          <div className="flex gap-2.5 p-3">
            <Avatar
              url={hostProfile?.profile_image_url ?? null}
              name={hostProfile?.username ?? "host"}
              size={34}
            />
            <div className="min-w-0 flex-1">
              <h3 className={cn("truncate font-bold leading-tight", big ? "text-[16px]" : "text-[14px]")}>
                {room.name}
              </h3>
              <p className="truncate text-[12px] text-muted-foreground">
                {hostProfile?.display_name ?? hostProfile?.username ?? "host"}
              </p>
              {room.topic && (
                <span className="mt-1 inline-block rounded-full bg-secondary px-2 py-0.5 text-[10px] font-semibold text-muted-foreground">
                  {room.topic}
                </span>
              )}
            </div>
          </div>
        </Link>
        {manageRow(room)}
      </div>
    );
  };

  /** Compact row for scheduled rooms. */
  const upcomingRow = (room: LiveRoom): JSX.Element => {
    const hostProfile = profiles[room.host_id];
    return (
      <div
        key={room.id}
        className="overflow-hidden rounded-[18px] border border-amber-500/30 bg-card"
      >
        <Link to={`/live/${room.id}`} className="flex items-center gap-3 p-3.5 active:scale-[0.99]">
          <div className="rounded-full bg-gradient-to-br from-amber-500 to-orange-400 p-[3px]">
            <Avatar
              url={hostProfile?.profile_image_url ?? null}
              name={hostProfile?.username ?? "host"}
              size={44}
            />
          </div>
          <div className="min-w-0 flex-1">
            <span className="inline-flex items-center gap-1 rounded-full bg-amber-500/10 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide text-amber-500">
              <CalendarClock className="h-3 w-3" />
              Scheduled
            </span>
            <h3 className="mt-0.5 truncate text-[14px] font-bold">{room.name}</h3>
            <p className="truncate text-[12px] text-muted-foreground">
              {hostProfile?.display_name ?? hostProfile?.username ?? "host"}
              {room.topic ? ` · ${room.topic}` : ""}
            </p>
          </div>
        </Link>
        <div className="px-3.5 pb-3">{manageRow(room)}</div>
      </div>
    );
  };

  return (
    <div className="flex min-h-[100dvh] flex-col bg-muted/30">
      <FloatingHeader
        title="Live on Whisper"
        left={<FloatingButton to="/" label="Back"><ArrowLeft className="h-5 w-5" /></FloatingButton>}
        right={user ? (
          <Link
            to="/live/start"
            className="glass flex items-center gap-1.5 rounded-full border border-border/40 bg-gradient-to-r from-rose-500 to-orange-500 px-3 py-1.5 text-[12px] font-bold text-white shadow-sm transition-transform active:scale-95"
          >
            <Plus className="h-3.5 w-3.5" />
            Go live
          </Link>
        ) : undefined}
      />

      <main className="mx-auto w-full max-w-3xl px-4 pt-6 pb-10">
        {/* Following · live now — IG story-strip grammar, one tap to join */}
        {followedLive.length > 0 && (
          <div className="mb-5">
            <h3 className="mb-2 text-[11px] font-black uppercase tracking-wide text-muted-foreground">
              Following · live now
            </h3>
            <div className="no-scrollbar flex gap-3 overflow-x-auto">
              {followedLive.map((room) => {
                const host = profiles[room.host_id];
                return (
                  <Link
                    key={room.id}
                    to={`/live/${room.id}`}
                    className="flex w-16 shrink-0 flex-col items-center gap-1"
                  >
                    <span className="relative">
                      <span className="block rounded-full bg-gradient-to-br from-rose-500 via-orange-500 to-pink-600 p-[2.5px]">
                        <span className="block rounded-full border-2 border-background">
                          <Avatar
                            url={host?.profile_image_url ?? null}
                            name={host?.username ?? "host"}
                            size={52}
                          />
                        </span>
                      </span>
                      <span className="absolute -bottom-1 left-1/2 -translate-x-1/2 rounded-[5px] border-2 border-background bg-gradient-to-r from-rose-500 to-orange-500 px-1.5 py-px text-[7px] font-bold uppercase tracking-wider text-white">
                        LIVE
                      </span>
                    </span>
                    <span className="w-full truncate text-center text-[10px] font-bold">
                      {host?.username ?? "live"}
                    </span>
                  </Link>
                );
              })}
            </div>
          </div>
        )}

        {/* Category chips — browse lives by topic (Twitch directory grammar) */}
        {topics.length > 0 && (
          <div className="no-scrollbar mb-5 flex gap-1.5 overflow-x-auto">
            <button
              onClick={() => setSelectedTopic("")}
              className={cn(
                "shrink-0 rounded-full px-3.5 py-1.5 text-[12px] font-bold transition-colors",
                !selectedTopic
                  ? "bg-foreground text-background"
                  : "bg-secondary text-muted-foreground"
              )}
            >
              All
            </button>
            {topics.map((t) => (
              <button
                key={t}
                onClick={() => setSelectedTopic(selectedTopic === t ? "" : t)}
                className={cn(
                  "shrink-0 rounded-full px-3.5 py-1.5 text-[12px] font-bold transition-colors",
                  selectedTopic === t
                    ? "bg-rose-500 text-white"
                    : "bg-secondary text-muted-foreground"
                )}
              >
                {t}
              </button>
            ))}
          </div>
        )}

        {rooms.length === 0 ? (
          <div className="rounded-[24px] border border-dashed border-border bg-card p-10 text-center">
            <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-rose-500/10">
              <Headphones className="h-8 w-8 text-rose-500" />
            </div>
            <p className="text-lg font-bold">No lives right now</p>
            <p className="mt-1 text-sm text-muted-foreground">
              Go live now or schedule one for later — invite friends to broadcast together.
            </p>
            {user && (
              <Link
                to="/live/start"
                className="mt-5 inline-flex items-center gap-2 rounded-full bg-gradient-to-r from-rose-500 to-orange-500 px-5 py-2.5 text-sm font-bold text-white transition-transform active:scale-95"
              >
                <Plus className="h-4 w-4" />
                Go live now
              </Link>
            )}
          </div>
        ) : (
          <div className="space-y-7">
            {liveNowAll.length === 0 && upcoming.length === 0 && selectedTopic && (
              <p className="rounded-2xl border border-dashed border-border bg-card px-4 py-6 text-center text-[13px] text-muted-foreground">
                Nothing live in {selectedTopic} right now — try another category.
              </p>
            )}

            {/* FEATURED — the biggest room right now, Twitch front-page style */}
            {featured && (
              <section>
                <h3 className="mb-2.5 flex items-center gap-1.5 text-[13px] font-black uppercase tracking-wide">
                  <span className="relative flex h-2 w-2">
                    <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-rose-400 opacity-75" />
                    <span className="relative inline-flex h-2 w-2 rounded-full bg-rose-500" />
                  </span>
                  Featured live
                </h3>
                {previewCard(featured, true)}
              </section>
            )}

            {/* The directory grid */}
            {liveRest.length > 0 && (
              <section>
                <h3 className="mb-2.5 flex items-center gap-1.5 text-[13px] font-black uppercase tracking-wide">
                  <Radio className="h-3.5 w-3.5 text-rose-500" />
                  Live channels
                </h3>
                <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                  {liveRest.map((r) => previewCard(r))}
                </div>
              </section>
            )}

            {upcoming.length > 0 && (
              <section>
                <h3 className="mb-2.5 flex items-center gap-1.5 text-[13px] font-black uppercase tracking-wide text-amber-500">
                  <CalendarClock className="h-3.5 w-3.5" />
                  Upcoming
                </h3>
                <div className="space-y-3">{upcoming.map(upcomingRow)}</div>
              </section>
            )}

            {/* Start-your-own footer CTA */}
            {user && (
              <div className="flex items-center justify-between rounded-[20px] border border-border/50 bg-card px-4 py-3.5">
                <div className="flex items-center gap-3">
                  <span className="flex h-10 w-10 items-center justify-center rounded-full bg-rose-500/10">
                    <Mic2 className="h-5 w-5 text-rose-500" />
                  </span>
                  <div>
                    <p className="text-[14px] font-bold leading-tight">Start your own live</p>
                    <p className="text-[12px] text-muted-foreground">
                      Solo or with up to 3 friends — gifts pay you 70%.
                    </p>
                  </div>
                </div>
                <Link
                  to="/live/start"
                  className="rounded-full bg-gradient-to-r from-rose-500 to-orange-500 px-4 py-2 text-[12px] font-bold text-white transition-transform active:scale-95"
                >
                  Go live
                </Link>
              </div>
            )}
          </div>
        )}
      </main>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  Live countdown for scheduled rooms                                 */
/* ------------------------------------------------------------------ */

function Countdown({ target, onDone }: { target: string; onDone?: () => void }) {
  const [remaining, setRemaining] = useState<number>(
    () => new Date(target).getTime() - Date.now()
  );

  useEffect(() => {
    const timer = setInterval(() => {
      const next = new Date(target).getTime() - Date.now();
      setRemaining(next);
      if (next <= 0) {
        clearInterval(timer);
        onDone?.();
      }
    }, 1000);
    return () => clearInterval(timer);
  }, [target, onDone]);

  const label = (): string => {
    if (remaining <= 0) return "Starting now";
    const total = Math.floor(remaining / 1000);
    const days = Math.floor(total / 86_400);
    const hours = Math.floor((total % 86_400) / 3600);
    const minutes = Math.floor((total % 3600) / 60);
    const seconds = total % 60;
    if (days > 0) return `${days}d ${hours}h ${minutes}m`;
    if (hours > 0) return `${hours}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
    return `${minutes}:${String(seconds).padStart(2, "0")}`;
  };

  return (
    <span className="flex items-center gap-1.5 rounded-full bg-amber-500/10 px-2.5 py-1 text-[11px] font-black tabular-nums text-amber-600">
      <Timer className="h-3 w-3" />
      {label()}
    </span>
  );
}
