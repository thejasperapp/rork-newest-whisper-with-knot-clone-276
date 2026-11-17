/**
 * LiveRoom — the live audio/video room experience with Instagram/Twitch-style chat.
 *
 * Features:
 *  - Full-bleed gradient stage with speaker avatar rings
 *  - Floating glass control bar
 *  - Live chat with Supabase Realtime (Instagram/Twitch style)
 *  - Gradient avatar background when cam is off
 *  - Pulsing audio rings around active speakers
 *  - Realtime speaker request auto-refresh
 *  - Bottom sheet for speaker requests
 */

import { useParams, useNavigate, Link } from "react-router-dom";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import {
  ArrowLeft,
  Radio,
  Users,
  X,
  Mic,
  MicOff,
  Headphones,
  Hand,
  Loader2,
  Video,
  VideoOff,
  Check,
  ChevronRight,
  Volume2,
  Send,
  Pin,
  MessageCircle,
  BarChart3,
  Dumbbell,
  Sparkles,
  Heart,
  Flame,
  Target,
  ClipboardList,
  Share2,
  MonitorUp,
  MonitorOff,
  UserPlus,
  Ban,
  Clock3,
  ShieldCheck,
  Trash2,
  Gift,
  Eye,
  SlidersHorizontal,
} from "lucide-react";
import { useEffect, useRef, useState, useCallback, useMemo } from "react";
import { WHISPER_BRAND_GRADIENT } from "@/lib/brand";

import { useAuth } from "@/hooks/useAuth";
import { Avatar } from "@/components/Avatar";
import { FloatingHeader, FloatingButton } from "@/components/FloatingHeader";
import { LiveGiftSheet } from "@/components/LiveGiftSheet";
import {
  fetchGiftEarnings,
  formatGiftCents,
  giftCashOut,
  type GiftEarnings,
} from "@/lib/gifts";
import { toast } from "sonner";
import { fetchProfilesByIds } from "@/lib/api";
import { supabase } from "@/lib/supabase";
import {
  createSpeakerRequest,
  decideSpeakerRequest,
  addSpeakerToRoom,
  removeSpeaker,
  fetchSpeakerRequests,
  ROLE_QUESTIONS,
  type SpeakerRequest,
  type SpeakerRole,
} from "@/lib/liveSpeakerRequests";
import {
  deleteChatMessage,
  fetchChatMessages,
  sendChatMessage,
  togglePinMessage,
  subscribeToChatMessages,
  type LiveChatMessage,
} from "@/lib/liveChat";
import {
  EMPTY_MODERATION,
  addModerator,
  banUser,
  fetchLiveModeration,
  findBannedWord,
  removeModerator,
  setBannedWords,
  timeoutUser,
  unbanUser,
  type LiveModerationState,
} from "@/lib/liveModeration";
import {
  createPoll,
  closePoll,
  votePoll,
  fetchPolls,
  fetchPollVoteCounts,
  fetchMyVotes,
  subscribeToPolls,
  type LivePoll,
} from "@/lib/livePolls";
import { WhisperLiveRTC, describeMediaBlock, type LiveParticipantInfo } from "@/lib/whisperLiveRTC";
import { cn } from "@/lib/utils";

interface LiveRoomData {
  id: string;
  name: string;
  description: string | null;
  topic: string | null;
  host_id: string;
  listener_count: number;
  is_live: boolean;
  created_at: string;
  is_video_enabled: boolean;
  /** Upcoming rooms carry a future timestamp — they are NOT "ended". */
  scheduled_at: string | null;
}

interface Speaker {
  user_id: string;
  is_host: boolean;
  is_cohost: boolean;
  can_video: boolean;
}

async function fetchRoom(id: string): Promise<LiveRoomData | null> {
  let data: LiveRoomData | null = null;
  const { data: full, error: fullError } = await supabase
    .from("whisper_live_rooms")
    .select("id, name, description, topic, host_id, listener_count, is_live, created_at, is_video_enabled, scheduled_at")
    .eq("id", id)
    .maybeSingle();
  if (!fullError && full) {
    data = full as LiveRoomData;
  } else if (fullError) {
    const { data: fallback, error: fallbackError } = await supabase
      .from("whisper_live_rooms")
      .select("id, name, description, topic, host_id, listener_count, is_live, created_at")
      .eq("id", id)
      .maybeSingle();
    if (fallbackError) return null;
    if (fallback) {
      data = {
        ...(fallback as Omit<LiveRoomData, "is_video_enabled" | "scheduled_at">),
        is_video_enabled: true,
        scheduled_at: null,
      };
    }
  }
  return data;
}

async function fetchSpeakers(roomId: string): Promise<Speaker[]> {
  const { data } = await supabase
    .from("whisper_live_room_speakers")
    .select("user_id, is_host, is_cohost, can_video")
    .eq("room_id", roomId);
  return (data as Speaker[] | null) ?? [];
}

async function fetchListeners(roomId: string): Promise<string[]> {
  const { data } = await supabase
    .from("whisper_live_room_listeners")
    .select("user_id")
    .eq("room_id", roomId);
  return ((data as { user_id: string }[] | null) ?? []).map((r) => r.user_id);
}

async function joinRoom(roomId: string, userId: string) {
  const { error } = await supabase
    .from("whisper_live_room_listeners")
    .upsert({ room_id: roomId, user_id: userId }, { onConflict: "room_id,user_id" });
  if (error) throw new Error(error.message ?? "Could not join");
}

async function leaveRoom(roomId: string, userId: string) {
  const { error } = await supabase
    .from("whisper_live_room_listeners")
    .delete()
    .eq("room_id", roomId)
    .eq("user_id", userId);
  if (error) throw new Error(error.message ?? "Could not leave");
}

async function endRoom(roomId: string) {
  const { data: row } = await supabase
    .from("whisper_live_rooms")
    .select("scheduled_at")
    .eq("id", roomId)
    .maybeSingle();
  const { error } = await supabase
    .from("whisper_live_rooms")
    .update({ is_live: false, updated_at: new Date().toISOString() })
    .eq("id", roomId);
  if (error) throw new Error(error.message ?? "Could not end Space");
  // Future-scheduled rooms survive an early end so the countdown keeps
  // working (mirrors iOS). Ad-hoc lives are deleted as before (the SQL
  // auto-delete trigger also covers this).
  const upcoming = (row as { scheduled_at?: string | null } | null)?.scheduled_at
    ? new Date((row as { scheduled_at: string }).scheduled_at).getTime() > Date.now()
    : false;
  if (!upcoming) {
    await supabase.from("whisper_live_rooms").delete().eq("id", roomId);
  }
}

/** One-line preview for the pinned strip — wire tokens never render raw. */
function pinnedPreview(body: string): string {
  const workout = parseWorkoutEmbed(body);
  if (workout) return `🏋️ Workout · ${workout.displayName}`;
  const tokenIdx = body.indexOf("::whisper-");
  if (tokenIdx >= 0) {
    const caption = body.slice(0, tokenIdx).trim();
    return caption || "Shared a card";
  }
  if (body.includes("jasper-sticker://") || body.includes("ember-sticker://")) return "Sticker";
  return body;
}

/** Max people on camera at once — Instagram-style group live cap. */
const MAX_BROADCASTERS = 4;

/** The right-hand column of the studio — chat for everyone, the Stream
 * Manager and speaker requests for the host (Twitch's dashboard grammar). */
type LiveSidePanel = "chat" | "manager" | "requests";

/** Top-bar icon button — quiet on the dark stage, lit on hover. */
const TOPBAR_BTN =
  "flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-white/70 transition-colors hover:bg-white/10 hover:text-white";
/** Stage control disc — the broadcaster's mic/camera/share/tools row. */
const CTRL_BTN =
  "flex h-10 w-10 shrink-0 items-center justify-center rounded-full transition-all active:scale-90";
/** Stream Manager field — sits on the dark panel. */
const MANAGER_INPUT =
  "w-full rounded-xl border border-white/10 bg-white/[0.06] px-3 py-2.5 text-[13.5px] text-white outline-none placeholder:text-white/35 focus:border-white/30";
const MANAGER_KICKER = "text-[11px] font-black uppercase tracking-wide text-white/50";
const MANAGER_TILE = "rounded-xl border border-white/10 bg-white/[0.04] px-3 py-2.5";

async function updateListenerCount(roomId: string): Promise<void> {
  const { count } = await supabase
    .from("whisper_live_room_listeners")
    .select("id", { count: "exact", head: true })
    .eq("room_id", roomId);
  await supabase
    .from("whisper_live_rooms")
    .update({ listener_count: count ?? 0, updated_at: new Date().toISOString() })
    .eq("id", roomId);
}

export default function LiveRoom() {
  const { id } = useParams<{ id: string }>();
  const { user, profile } = useAuth();
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  const [joined, setJoined] = useState(false);
  const [micOn, setMicOn] = useState(false);
  const [cameraOn, setCameraOn] = useState(false);
  const [handRaised, setHandRaised] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const [participants, setParticipants] = useState<LiveParticipantInfo[]>([]);
  const [audioConnected, setAudioConnected] = useState(false);
  const [showRequestModal, setShowRequestModal] = useState(false);
  const [showRequestsPanel, setShowRequestsPanel] = useState(false);
  const [remoteStreams, setRemoteStreams] = useState<Map<string, MediaStream>>(new Map());

  // Chat state
  const [chatMessages, setChatMessages] = useState<LiveChatMessage[]>([]);
  const [chatDraft, setChatDraft] = useState<string>("");
  const chatScrollRef = useRef<HTMLDivElement | null>(null);

  // Polls state
  const [polls, setPolls] = useState<LivePoll[]>([]);
  const [pollVoteCounts, setPollVoteCounts] = useState<Record<string, number[]>>({});
  const [myVotes, setMyVotes] = useState<Record<string, number>>({});
  const [showPollCreator, setShowPollCreator] = useState(false);

  // Cam layout state
  const [spotlightPeerId, setSpotlightPeerId] = useState<string | null>(null);
  const [screenSharing, setScreenSharing] = useState(false);
  const [showInviteModal, setShowInviteModal] = useState(false);

  // Role detection
  const isCoach = !!(profile?.is_coach);
  const isRecruiter = !!(profile?.is_recruiter);
  const isCreator = !!(profile?.is_verified) && !isCoach && !isRecruiter && !(profile?.is_athlete);
  const hasRoleTools = isCoach || isRecruiter || isCreator;
  const [showCoachTools, setShowCoachTools] = useState(false);
  const [showCreatorTools, setShowCreatorTools] = useState(false);
  const [showRecruiterTools, setShowRecruiterTools] = useState(false);

  // Floating reactions state
  const [floatingReactions, setFloatingReactions] = useState<{ id: string; emoji: string; x: number }[]>([]);

  // ── Live gifts — wallet-rail gifts with realtime banners (Phase 2)
  const [showGiftSheet, setShowGiftSheet] = useState<boolean>(false);
  const [giftBanners, setGiftBanners] = useState<{ key: string; emoji: string; label: string; qty: number; sender: string }[]>([]);
  const [streamGiftNetCents, setStreamGiftNetCents] = useState<number>(0);
  const [giftEarnings, setGiftEarnings] = useState<GiftEarnings | null>(null);
  const [giftCashingOut, setGiftCashingOut] = useState<boolean>(false);
  const [pastStreams, setPastStreams] = useState<{ id: string; name: string; endedAt: string; durationMin: number; peak: number; messages: number; giftCents: number }[] | null>(null);

  const rtcRef = useRef<WhisperLiveRTC | null>(null);

  // ── Live extras — goal / chat rules / raid (Twitch & TikTok-style),
  // host-authoritative state synced to every viewer over one broadcast
  // channel with a 10s heartbeat for late joiners.
  type LiveExtras = {
    goalLabel: string;
    goalTarget: number;
    goalCount: number;
    slowSeconds: number;
    followersOnly: boolean;
    raidTo: { id: string; name: string } | null;
  };
  const [extras, setExtras] = useState<LiveExtras>({
    goalLabel: "Hearts goal",
    goalTarget: 0,
    goalCount: 0,
    slowSeconds: 0,
    followersOnly: false,
    raidTo: null,
  });
  const extrasRef = useRef<LiveExtras>(extras);
  const extrasChannelRef = useRef<ReturnType<typeof supabase.channel> | null>(null);
  const isHostRef = useRef<boolean>(false);
  const lastChatAtRef = useRef<number>(0);
  const followsHostRef = useRef<boolean | null>(null);
  const [sidePanel, setSidePanel] = useState<LiveSidePanel>("chat");
  // The Stream Manager is a docked panel now (not a modal) — every lazy
  // loader that used to key off the sheet keys off the panel tab.
  const showStreamTools = sidePanel === "manager";
  const [modState, setModState] = useState<LiveModerationState>(EMPTY_MODERATION);
  const [modInput, setModInput] = useState<string>("");
  const [modBusy, setModBusy] = useState<boolean>(false);
  const [bannedWordsDraft, setBannedWordsDraft] = useState<string>("");
  const [titleDraft, setTitleDraft] = useState<string>("");
  const [topicDraft, setTopicDraft] = useState<string>("");
  const [managerTick, setManagerTick] = useState<number>(Date.now());
  const peakRef = useRef<number>(0);
  const [peakListeners, setPeakListeners] = useState<number>(0);
  const lastPeakWriteRef = useRef<number>(0);
  const [goalLabelDraft, setGoalLabelDraft] = useState<string>("Hearts goal");
  const [goalTargetDraft, setGoalTargetDraft] = useState<string>("");
  const [raidRooms, setRaidRooms] = useState<{ id: string; name: string }[]>([]);

  const roomQuery = useQuery({
    queryKey: ["live-room", id],
    queryFn: () => fetchRoom(id!),
    enabled: !!id,
    refetchInterval: 10_000,
  });

  const speakersQuery = useQuery({
    queryKey: ["live-room-speakers", id],
    queryFn: () => fetchSpeakers(id!),
    enabled: !!id,
    refetchInterval: 10_000,
  });

  const listenersQuery = useQuery({
    queryKey: ["live-room-listeners", id],
    queryFn: () => fetchListeners(id!),
    enabled: !!id,
    refetchInterval: 10_000,
  });

  const requestsQuery = useQuery({
    queryKey: ["live-speaker-requests", id],
    queryFn: () => fetchSpeakerRequests(id!),
    enabled: !!id,
    // Short staleTime so realtime invalidation triggers a fresh fetch
    staleTime: 5_000,
  });

  const room = roomQuery.data;
  const speakers = speakersQuery.data ?? [];
  const hostId = room?.host_id;
  const isHost = !!user && user.id === hostId;

  // ─── Moderation state — mods, bans, timeouts, banned words ────────────
  useEffect(() => {
    if (!id || !hostId) return;
    let stopped = false;
    const load = async (): Promise<void> => {
      const state = await fetchLiveModeration(hostId, id);
      if (!stopped) setModState(state);
    };
    void load();
    const timer = window.setInterval(() => void load(), 45_000);
    return () => {
      stopped = true;
      window.clearInterval(timer);
    };
  }, [id, hostId, showStreamTools]);

  const amMod = !!user && modState.mods.some((m) => m.mod_user_id === user.id);
  const canModerate = isHost || amMod;
  const iAmBanned =
    !!user && modState.bans.some((b) => b.banned_user_id === user.id);
  const myTimeoutUntil = user
    ? (modState.timeouts.find(
        (t) =>
          t.user_id === user.id && new Date(t.until).getTime() > Date.now()
      )?.until ?? null)
    : null;

  // Peak viewers — tracked locally, persisted best-effort for the manager.
  useEffect(() => {
    const count = room?.listener_count ?? 0;
    if (count > peakRef.current) {
      peakRef.current = count;
      setPeakListeners(count);
      if (isHost && id && Date.now() - lastPeakWriteRef.current > 15_000) {
        lastPeakWriteRef.current = Date.now();
        void supabase
          .from("whisper_live_rooms")
          .update({ peak_listeners: count })
          .eq("id", id)
          .then(() => undefined);
      }
    }
  }, [room?.listener_count, isHost, id]);

  // Stream Manager drafts are seeded when the panel opens.
  useEffect(() => {
    if (!showStreamTools) return;
    setTitleDraft(room?.name ?? "");
    setTopicDraft(room?.topic ?? "");
    setBannedWordsDraft(modState.bannedWords.join(", "));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [showStreamTools]);

  // The session clock ticks for the whole stream now — it sits in the
  // studio's top bar, not only inside the manager.
  useEffect(() => {
    if (!isHost) return;
    const timer = window.setInterval(() => setManagerTick(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, [isHost]);

  const sessionElapsed = ((): string => {
    const startIso = room?.created_at;
    if (!startIso) return "0:00";
    const total = Math.max(
      0,
      Math.floor((managerTick - new Date(startIso).getTime()) / 1000)
    );
    const hours = Math.floor(total / 3600);
    const minutes = Math.floor((total % 3600) / 60);
    const seconds = total % 60;
    return hours > 0
      ? `${hours}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`
      : `${minutes}:${String(seconds).padStart(2, "0")}`;
  })();
  const isSpeaker = speakers.some((s) => s.user_id === user?.id);
  const canPublish = isHost || isSpeaker;

  const allUserIds = Array.from(
    new Set(
      speakers
        .map((s) => s.user_id)
        .concat(listenersQuery.data ?? [])
        .concat(hostId ? [hostId] : [])
        .concat((requestsQuery.data ?? []).map((r) => r.user_id))
    )
  );

  const profilesQuery = useQuery({
    queryKey: ["live-room-profiles", allUserIds],
    queryFn: () => fetchProfilesByIds(allUserIds),
    enabled: allUserIds.length > 0,
  });

  const profiles = profilesQuery.data ?? {};

  // ─── Realtime subscriptions ─────────────────────────────────────────────────
  // Single channel for room/speakers/listeners/requests — all changes invalidate
  // the relevant queries so the UI auto-refreshes without manual button presses.
  useEffect(() => {
    if (!id) return;
    const channel = supabase
      .channel(`room:${id}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "whisper_live_rooms", filter: `id=eq.${id}` },
        () => queryClient.invalidateQueries({ queryKey: ["live-room", id] })
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "whisper_live_room_listeners", filter: `room_id=eq.${id}` },
        () => {
          queryClient.invalidateQueries({ queryKey: ["live-room-listeners", id] });
          void updateListenerCount(id);
        }
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "whisper_live_room_speakers", filter: `room_id=eq.${id}` },
        () => queryClient.invalidateQueries({ queryKey: ["live-room-speakers", id] })
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "whisper_live_speaker_requests", filter: `room_id=eq.${id}` },
        () => queryClient.invalidateQueries({ queryKey: ["live-speaker-requests", id] })
      )
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [id, queryClient]);

  // ─── Chat: load history + subscribe to realtime ─────────────────────────────
  useEffect(() => {
    if (!id) return;
    void fetchChatMessages(id).then((msgs) => setChatMessages(msgs));
    const unsub = subscribeToChatMessages(
      id,
      (msg) => {
        setChatMessages((prev) => {
          // Dedupe by id (realtime may fire twice)
          if (prev.some((m) => m.id === msg.id)) return prev;
          return [...prev, msg];
        });
      },
      (deletedId) => {
        setChatMessages((prev) => prev.filter((m) => m.id !== deletedId));
      }
    );
    return unsub;
  }, [id]);

  // Auto-scroll chat to bottom on new messages
  useEffect(() => {
    if (chatScrollRef.current) {
      chatScrollRef.current.scrollTop = chatScrollRef.current.scrollHeight;
    }
  }, [chatMessages]);

  // ─── Polls: load + subscribe to realtime ──────────────────────────────────
  const refreshPolls = useCallback(async () => {
    if (!id) return;
    const pollsData = await fetchPolls(id);
    setPolls(pollsData);
    const pollIds = pollsData.map((p) => p.id);
    if (pollIds.length > 0) {
      const [counts, votes] = await Promise.all([
        fetchPollVoteCounts(pollIds),
        fetchMyVotes(pollIds),
      ]);
      setPollVoteCounts(counts);
      setMyVotes(votes);
    }
  }, [id]);

  useEffect(() => {
    if (!id) return;
    void refreshPolls();
    const unsub = subscribeToPolls(
      id,
      () => void refreshPolls(),
      () => void refreshPolls()
    );
    return unsub;
  }, [id, refreshPolls]);

  // ─── Live gifts — realtime banners + host console data ──────────────────
  // Gift INSERTs stream to everyone in the room for the banner overlay and
  // the host's this-stream total; earnings + past-stream recaps load when
  // the Stream Manager opens. Everything degrades silently until the
  // live-gifts migration runs.
  useEffect(() => {
    if (!id) return;
    let cancelled = false;
    void (async () => {
      const { data } = await supabase
        .from("whisper_live_gifts")
        .select("net_cents")
        .eq("room_id", id);
      if (cancelled || !data) return;
      setStreamGiftNetCents(
        (data as { net_cents: number }[]).reduce((sum, g) => sum + (g.net_cents ?? 0), 0)
      );
    })();
    const channel = supabase
      .channel(`gifts:${id}`)
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "whisper_live_gifts", filter: `room_id=eq.${id}` },
        (payload) => {
          const g = payload.new as { gift_emoji?: string; gift_label?: string; qty?: number; sender_username?: string | null; net_cents?: number };
          const key = crypto.randomUUID();
          setGiftBanners((prev) => [
            ...prev.slice(-3),
            { key, emoji: g.gift_emoji ?? "🎁", label: g.gift_label ?? "Gift", qty: g.qty ?? 1, sender: g.sender_username ?? "someone" },
          ]);
          setStreamGiftNetCents((prev) => prev + (g.net_cents ?? 0));
          window.setTimeout(() => {
            setGiftBanners((prev) => prev.filter((b) => b.key !== key));
          }, 4600);
        }
      )
      .subscribe();
    return () => {
      cancelled = true;
      void supabase.removeChannel(channel);
    };
  }, [id]);

  useEffect(() => {
    if (!showStreamTools || !isHostRef.current || !user) return;
    void fetchGiftEarnings()
      .then(setGiftEarnings)
      .catch(() => setGiftEarnings(null));
    void (async () => {
      try {
        let rows: { id: string; name: string; created_at: string; updated_at: string; peak_listeners?: number | null }[] = [];
        const withPeak = await supabase
          .from("whisper_live_rooms")
          .select("id,name,created_at,updated_at,peak_listeners")
          .eq("host_id", user.id)
          .eq("is_live", false)
          .order("created_at", { ascending: false })
          .limit(6);
        if (withPeak.error) {
          // peak_listeners arrives with live-v2 — fall back without it.
          const noPeak = await supabase
            .from("whisper_live_rooms")
            .select("id,name,created_at,updated_at")
            .eq("host_id", user.id)
            .eq("is_live", false)
            .order("created_at", { ascending: false })
            .limit(6);
          rows = (noPeak.data ?? []) as typeof rows;
        } else {
          rows = (withPeak.data ?? []) as typeof rows;
        }
        const detailed = await Promise.all(
          rows.map(async (r) => {
            const [msgRes, giftRes] = await Promise.all([
              supabase
                .from("whisper_live_chat_messages")
                .select("id", { count: "exact", head: true })
                .eq("room_id", r.id),
              supabase.from("whisper_live_gifts").select("net_cents").eq("room_id", r.id),
            ]);
            const giftCents = ((giftRes.data ?? []) as { net_cents: number }[]).reduce(
              (sum, g) => sum + (g.net_cents ?? 0),
              0
            );
            const started = new Date(r.created_at).getTime();
            const ended = new Date(r.updated_at).getTime();
            return {
              id: r.id,
              name: r.name,
              endedAt: r.updated_at,
              durationMin: Math.max(1, Math.round((ended - started) / 60000)),
              peak: r.peak_listeners ?? 0,
              messages: msgRes.count ?? 0,
              giftCents,
            };
          })
        );
        setPastStreams(detailed);
      } catch {
        setPastStreams([]);
      }
    })();
  }, [showStreamTools, user]);

  const handleGiftCashout = async (): Promise<void> => {
    setGiftCashingOut(true);
    try {
      const res = await giftCashOut();
      toast.success(
        res.sentToBank
          ? `${formatGiftCents(res.amountCents)} sent to your bank!`
          : `${formatGiftCents(res.amountCents)} transferred — it lands with your next payout.`
      );
      setGiftEarnings(await fetchGiftEarnings().catch(() => null));
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Couldn't cash out.");
    } finally {
      setGiftCashingOut(false);
    }
  };

  // ─── Floating reactions ────────────────────────────────────────────────────
  // Reactions flow through the WebRTC signaling channel (same as iOS) so
  // cross-platform reactions work. The RTC callback is wired in connectRTC.
  const spawnReaction = useCallback((emoji: string) => {
    const x = Math.random() * 80 + 10;
    const reactionId = crypto.randomUUID();
    setFloatingReactions((prev) => [...prev, { id: reactionId, emoji, x }]);
    setTimeout(() => {
      setFloatingReactions((prev) => prev.filter((r) => r.id !== reactionId));
    }, 3000);
    // Every reaction the HOST's device sees pushes the live goal forward —
    // the host is the single counter so totals stay consistent for everyone.
    if (isHostRef.current) {
      setExtras((prev) =>
        prev.goalTarget > 0 ? { ...prev, goalCount: prev.goalCount + 1 } : prev
      );
    }
  }, []);

  const sendReaction = async (emoji: string): Promise<void> => {
    if (!id) return;
    // Send via the RTC signaling channel so iOS viewers see it too.
    rtcRef.current?.sendReaction(emoji);
    // If RTC isn't connected yet (listener hasn't joined), still show locally.
    if (!rtcRef.current) spawnReaction(emoji);
  };

  // ── Live extras wiring ────────────────────────────────────
  useEffect(() => {
    extrasRef.current = extras;
  }, [extras]);
  useEffect(() => {
    isHostRef.current = isHost;
  }, [isHost]);

  // Everyone joins the extras channel; viewers apply the host's state.
  useEffect(() => {
    if (!id) return;
    const channel = supabase
      .channel(`live-extras:${id}`)
      .on("broadcast", { event: "state" }, (msg) => {
        if (isHostRef.current) return; // the host is the source of truth
        const p = msg.payload as Partial<LiveExtras> | undefined;
        if (!p || typeof p !== "object") return;
        setExtras((prev) => ({ ...prev, ...p }));
      })
      .subscribe();
    extrasChannelRef.current = channel;
    return () => {
      extrasChannelRef.current = null;
      void supabase.removeChannel(channel);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  // Host: broadcast on every change + a 10s heartbeat for late joiners.
  useEffect(() => {
    if (!isHost || !id) return;
    const send = (): void => {
      void extrasChannelRef.current?.send({
        type: "broadcast",
        event: "state",
        payload: extrasRef.current,
      });
    };
    send();
    const timer = window.setInterval(send, 10_000);
    return () => window.clearInterval(timer);
  }, [isHost, id, extras]);

  // Raid — viewers ride along to the target room (Twitch-style send-off).
  useEffect(() => {
    if (isHost) return;
    const raid = extras.raidTo;
    if (!raid || !raid.id || raid.id === id) return;
    toast.success(`Raid! The host is sending everyone to ${raid.name}…`);
    const timer = window.setTimeout(() => {
      window.location.href = `/live/${raid.id}`;
    }, 2_500);
    return () => window.clearTimeout(timer);
  }, [extras.raidTo, id, isHost]);

  // Live rooms the host can raid — fetched when the tools sheet opens.
  useEffect(() => {
    if (!showStreamTools || !isHost) return;
    void supabase
      .from("whisper_live_rooms")
      .select("id, name")
      .eq("is_live", true)
      .neq("id", id ?? "")
      .limit(5)
      .then(({ data }) =>
        setRaidRooms((data ?? []) as { id: string; name: string }[])
      );
  }, [showStreamTools, isHost, id]);

  const applyGoal = (): void => {
    const target = Math.round(Number(goalTargetDraft));
    if (!Number.isFinite(target) || target <= 0) {
      toast.error("Enter a goal number — like 200 hearts.");
      return;
    }
    setExtras((prev) => ({
      ...prev,
      goalLabel: goalLabelDraft.trim() || "Hearts goal",
      goalTarget: target,
      goalCount: 0,
    }));
    toast.success("Goal is live — every reaction counts toward it.");
  };

  const startRaid = (target: { id: string; name: string }): void => {
    setExtras((prev) => ({ ...prev, raidTo: target }));
    setSidePanel("chat");
    toast.success(`Raiding ${target.name} — sending everyone over…`);
    window.setTimeout(() => {
      window.location.href = `/live/${target.id}`;
    }, 2_000);
  };

  // ─── WebRTC connection ──────────────────────────────────────────────────────

  const connectRTC = useCallback(
    async (asListener: boolean): Promise<void> => {
      if (!id || !user || !room) return;
      if (rtcRef.current) return;
      setConnecting(true);
      const peerId = crypto.randomUUID();
      const name = profile?.username ?? profile?.display_name ?? user.id;
      const rtc = new WhisperLiveRTC(peerId, user.id, name);
      rtcRef.current = rtc;
      try {
        rtc.onParticipantUpdate = (parts) => { if (rtcRef.current === rtc) setParticipants(parts); };
        rtc.onRemoteStream = (pid, stream) => {
          if (rtcRef.current !== rtc) return;
          setRemoteStreams((prev) => {
            const next = new Map(prev);
            next.set(pid, stream);
            return next;
          });
        };
        rtc.onReaction = (emoji) => { if (rtcRef.current === rtc) spawnReaction(emoji); };
        rtc.onError = (err) => { if (rtcRef.current === rtc) toast.error(err); };
        await rtc.join(id, asListener);
        if (rtcRef.current !== rtc) { rtc.leave(); return; }
        if (!asListener) { setMicOn(true); setCameraOn(true); }
        setAudioConnected(true);
      } catch {
        rtc.leave();
        if (rtcRef.current !== rtc) return;
        rtcRef.current = null;
        toast.error("Could not connect to room. Check your connection and device permissions.");
      } finally {
        if (!rtcRef.current || rtcRef.current === rtc) setConnecting(false);
      }
    },
    [id, user, room, profile]
  );

  // Host auto-connect on mount
  useEffect(() => {
    if (!room || !user || !id) return;
    if (user.id !== room.host_id) return;
    if (audioConnected || connecting) return;
    void joinRoom(id, user.id).catch(() => undefined);
    void updateListenerCount(id).catch(() => undefined);
    setJoined(true);
    void connectRTC(false);
  }, [room, user, id, audioConnected, connecting, connectRTC]);

  // Invited co-hosts auto-join the broadcast grid, Instagram-style.
  const invitedCheckedRef = useRef(false);
  useEffect(() => {
    if (!id || !user || !room || isHost) return;
    if (!speakersQuery.isSuccess) return;
    if (invitedCheckedRef.current) return;
    invitedCheckedRef.current = true;
    void (async () => {
      const { data: invite } = await supabase
        .from("whisper_live_invites")
        .select("id")
        .eq("room_id", id)
        .eq("invitee_id", user.id)
        .eq("status", "pending")
        .maybeSingle();
      if (!invite) return;
      if ((speakersQuery.data ?? []).length >= MAX_BROADCASTERS) return;
      try {
        await addSpeakerToRoom({ roomId: id, userId: user.id, canVideo: true });
        await supabase
          .from("whisper_live_invites")
          .update({ status: "accepted" })
          .eq("id", invite.id);
        await joinRoom(id, user.id).catch(() => undefined);
        setJoined(true);
        if (!audioConnected && !connecting) void connectRTC(true);
        toast.success("You're invited — joining the broadcast");
        refreshSpeakers();
      } catch {
        // Room may be full or the invites table not migrated yet.
      }
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id, user, room, isHost, speakersQuery.isSuccess]);

  // Auto-promote when speaker list changes
  const wasSpeakerRef = useRef(false);
  useEffect(() => {
    if (!id || !user || !room) return;
    const isNowSpeaker = speakers.some((s) => s.user_id === user.id);
    if (isNowSpeaker && !wasSpeakerRef.current && audioConnected && !isHost) {
      wasSpeakerRef.current = true;
      void rtcRef.current?.becomeSpeaker().then((promoted) => {
        if (!promoted) return; // devices blocked — stay a listener, error already toasted
        const media = rtcRef.current?.localMediaState;
        setMicOn(media?.hasAudio ?? false);
        setCameraOn(media?.hasVideo ?? false);
      });
    } else if (!isNowSpeaker && wasSpeakerRef.current) {
      wasSpeakerRef.current = false;
    }
  }, [speakers, user, id, room, audioConnected, isHost]);

  // Auto-end: if all speakers leave, the SQL trigger flips is_live=false.
  // The client watches for the room's is_live going false and navigates back.
  const [roomEnded, setRoomEnded] = useState(false);
  useEffect(() => {
    if (!room) return;
    // Upcoming scheduled rooms sit at is_live=false on purpose — never
    // treat them as "ended" (this used to kick viewers out of countdowns).
    const upcoming = room.scheduled_at
      ? new Date(room.scheduled_at).getTime() > Date.now()
      : false;
    if (!room.is_live && joined && !upcoming) {
      setRoomEnded(true);
      rtcRef.current?.leave();
      rtcRef.current = null;
      toast.info("This Space has ended");
      const timer = setTimeout(() => navigate("/live"), 2000);
      return () => clearTimeout(timer);
    }
  }, [room, joined, navigate]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      rtcRef.current?.leave();
      rtcRef.current = null;
      if (id && user) { void leaveRoom(id, user.id).catch(() => undefined); void updateListenerCount(id).catch(() => undefined); }
    };
  }, []);

  const refreshSpeakers = useCallback(() => {
    queryClient.invalidateQueries({ queryKey: ["live-room-speakers", id] });
  }, [id, queryClient]);

  const toggleMic = async (): Promise<void> => {
    if (!rtcRef.current) return;
    const next = !micOn;
    const applied = await rtcRef.current.setMicEnabled(next);
    setMicOn(applied);
    if (next && !applied) {
      toast.error(describeMediaBlock(rtcRef.current.localMediaState.audioError ?? "unknown", "microphone"));
    }
  };

  const toggleCamera = async (): Promise<void> => {
    if (!rtcRef.current || !canPublish) return;
    const next = !cameraOn;
    const applied = await rtcRef.current.setCameraEnabled(next);
    setCameraOn(applied);
    if (next && !applied) {
      toast.error(describeMediaBlock(rtcRef.current.localMediaState.videoError ?? "unknown", "camera"));
    }
  };

  const toggleScreenShare = async (): Promise<void> => {
    if (!rtcRef.current || !canPublish) return;
    if (rtcRef.current.isScreenSharing) {
      await rtcRef.current.stopScreenShare();
    } else {
      const ok = await rtcRef.current.startScreenShare();
      if (!ok) toast.error("Screen share was cancelled or isn't available");
    }
    setScreenSharing(rtcRef.current.isScreenSharing);
  };

  const shareUrl = `https://mydailywhisper.com/live/${id}`;
  const shareLive = async (): Promise<void> => {
    try {
      if (navigator.share) {
        await navigator.share({ title: room?.name ?? "Whisper Live", url: shareUrl });
      } else {
        await navigator.clipboard.writeText(shareUrl);
        toast.success("Live link copied");
      }
    } catch {
      // Share sheet dismissed.
    }
  };

  const joinMutation = useMutation({
    mutationFn: () => joinRoom(id!, user!.id),
    onSuccess: () => {
      setJoined(true);
      queryClient.invalidateQueries({ queryKey: ["live-room-listeners", id] });
      void updateListenerCount(id!);
      void connectRTC(true);
    },
    onError: (err) => toast.error(err instanceof Error ? err.message : "Could not join"),
  });

  const leaveMutation = useMutation({
    mutationFn: () => leaveRoom(id!, user!.id),
    onSuccess: () => {
      setJoined(false);
      rtcRef.current?.leave();
      rtcRef.current = null;
      setAudioConnected(false);
      setCameraOn(false);
      setMicOn(false);
      setParticipants([]);
      setRemoteStreams(new Map());
      queryClient.invalidateQueries({ queryKey: ["live-room-listeners", id] });
      void updateListenerCount(id!);
    },
    onError: (err) => toast.error(err instanceof Error ? err.message : "Could not leave"),
  });

  const endMutation = useMutation({
    mutationFn: () => endRoom(id!),
    onSuccess: () => {
      rtcRef.current?.leave();
      rtcRef.current = null;
      queryClient.invalidateQueries({ queryKey: ["live-room", id] });
      toast.success("Space ended");
      navigate("/live");
    },
    onError: (err) => toast.error(err instanceof Error ? err.message : "Could not end Space"),
  });

  // Viewers start watching the moment they arrive — Twitch's grammar. A
  // live room is a stage, not a lobby: signed-in viewers join once (the
  // listener row + the RTC hookup), never a second time after leaving.
  const autoJoinedRef = useRef<boolean>(false);
  useEffect(() => {
    if (!room || !user || !id) return;
    if (isHost || joined || roomEnded) return;
    if (!room.is_live) return;
    if (autoJoinedRef.current || joinMutation.isPending) return;
    autoJoinedRef.current = true;
    joinMutation.mutate();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [room?.id, room?.is_live, user?.id, isHost, joined, roomEnded]);

  const acceptRequestMutation = useMutation({
    mutationFn: async (request: SpeakerRequest) => {
      if (speakers.length >= MAX_BROADCASTERS) {
        throw new Error(`Live is full — max ${MAX_BROADCASTERS} people on camera`);
      }
      await decideSpeakerRequest(request.id, "accepted", user!.id);
      await addSpeakerToRoom({ roomId: request.room_id, userId: request.user_id, canVideo: ["athlete", "coach", "creator"].includes(request.desired_role) });
    },
    onSuccess: () => { toast.success("Speaker approved"); refreshSpeakers(); queryClient.invalidateQueries({ queryKey: ["live-speaker-requests", id] }); },
    onError: (err) => toast.error(err instanceof Error ? err.message : "Could not approve speaker"),
  });

  const rejectRequestMutation = useMutation({
    mutationFn: (request: SpeakerRequest) => decideSpeakerRequest(request.id, "rejected", user!.id),
    onSuccess: () => { toast.success("Speaker request declined"); queryClient.invalidateQueries({ queryKey: ["live-speaker-requests", id] }); },
    onError: () => toast.error("Could not decline request"),
  });

  const removeSpeakerMutation = useMutation({
    mutationFn: (userId: string) => removeSpeaker(id!, userId),
    onSuccess: () => { toast.success("Speaker removed"); refreshSpeakers(); },
    onError: () => toast.error("Could not remove speaker"),
  });

  // ─── Chat actions ───────────────────────────────────────────────────────────
  const sendChat = async (): Promise<void> => {
    if (!id || !user || !chatDraft.trim()) return;
    // Chat rules (host exempt) — Twitch-style moderation controls.
    if (!isHost) {
      if (iAmBanned) {
        toast.error("You're banned from this channel.");
        return;
      }
      if (myTimeoutUntil) {
        const secondsLeft = Math.max(
          1,
          Math.ceil((new Date(myTimeoutUntil).getTime() - Date.now()) / 1000)
        );
        toast.error(`You're timed out — ${secondsLeft}s left.`);
        return;
      }
      const blockedWord = findBannedWord(chatDraft, modState.bannedWords);
      if (blockedWord) {
        toast.error("That message contains a word the host has blocked.");
        return;
      }
      if (extras.followersOnly && hostId) {
        if (followsHostRef.current === null) {
          const { data } = await supabase
            .from("whisper_follows")
            .select("follower_id")
            .eq("follower_id", user.id)
            .eq("followee_id", hostId)
            .limit(1);
          followsHostRef.current = (data ?? []).length > 0;
        }
        if (followsHostRef.current === false) {
          toast.error("Followers-only chat — follow the host to join in.");
          return;
        }
      }
      if (extras.slowSeconds > 0) {
        const wait =
          lastChatAtRef.current + extras.slowSeconds * 1000 - Date.now();
        if (wait > 0) {
          toast.error(
            `Slow mode — you can chat again in ${Math.ceil(wait / 1000)}s.`
          );
          return;
        }
      }
    }
    const body = chatDraft.trim();
    setChatDraft("");
    try {
      await sendChatMessage({
        roomId: id,
        userId: user.id,
        username: profile?.username ?? "user",
        body,
        isHost,
      });
      lastChatAtRef.current = Date.now();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Could not send message");
      setChatDraft(body); // Restore on error
    }
  };

  // ─── Moderation actions — host + channel mods ───────────────────────
  const reloadModeration = async (): Promise<void> => {
    if (!id || !hostId) return;
    setModState(await fetchLiveModeration(hostId, id));
  };

  const modDeleteMessage = async (messageId: string): Promise<void> => {
    try {
      await deleteChatMessage(messageId);
      setChatMessages((prev) => prev.filter((m) => m.id !== messageId));
    } catch {
      toast.error("Couldn't delete that message");
    }
  };

  const modTimeout = async (msg: LiveChatMessage): Promise<void> => {
    if (!id) return;
    const error = await timeoutUser(id, msg.user_id, msg.username, 5);
    if (error) {
      toast.error(error);
      return;
    }
    toast.success(`${msg.username} timed out for 5 minutes`);
    void reloadModeration();
  };

  const modBan = async (msg: LiveChatMessage): Promise<void> => {
    if (!hostId) return;
    if (
      !window.confirm(
        `Ban ${msg.username} from this channel? They can't chat in any of this host's lives until unbanned.`
      )
    ) {
      return;
    }
    const error = await banUser(hostId, msg.user_id, msg.username);
    if (error) {
      toast.error(error);
      return;
    }
    toast.success(`${msg.username} banned from the channel`);
    void reloadModeration();
  };

  const handleAddMod = async (): Promise<void> => {
    if (!hostId || !modInput.trim() || modBusy) return;
    setModBusy(true);
    const error = await addModerator(hostId, modInput);
    setModBusy(false);
    if (error) {
      toast.error(error);
      return;
    }
    toast.success("Mod added");
    setModInput("");
    void reloadModeration();
  };

  const handleRemoveMod = async (modUserId: string): Promise<void> => {
    if (!hostId) return;
    await removeModerator(hostId, modUserId);
    setModState((prev) => ({
      ...prev,
      mods: prev.mods.filter((m) => m.mod_user_id !== modUserId),
    }));
  };

  const handleUnban = async (bannedUserId: string): Promise<void> => {
    if (!hostId) return;
    await unbanUser(hostId, bannedUserId);
    setModState((prev) => ({
      ...prev,
      bans: prev.bans.filter((b) => b.banned_user_id !== bannedUserId),
    }));
  };

  const handleSaveBannedWords = async (): Promise<void> => {
    if (!id) return;
    const words = bannedWordsDraft
      .split(",")
      .map((w) => w.trim())
      .filter(Boolean);
    const error = await setBannedWords(id, words);
    if (error) {
      toast.error(error);
      return;
    }
    toast.success(
      words.length > 0 ? "Blocked words saved" : "Blocked words cleared"
    );
    setModState((prev) => ({
      ...prev,
      bannedWords: words.map((w) => w.toLowerCase()),
    }));
  };

  const saveRoomDetails = async (): Promise<void> => {
    if (!id) return;
    const nextName = titleDraft.trim();
    if (!nextName) {
      toast.error("Give the live a title");
      return;
    }
    const { error } = await supabase
      .from("whisper_live_rooms")
      .update({ name: nextName, topic: topicDraft.trim() || null })
      .eq("id", id);
    if (error) {
      toast.error("Couldn't save — try again");
      return;
    }
    toast.success("Live details updated");
    void queryClient.invalidateQueries({ queryKey: ["live-room", id] });
  };

  const pinMessage = async (msgId: string, pinned: boolean): Promise<void> => {
    try {
      await togglePinMessage(msgId, pinned);
      setChatMessages((prev) =>
        prev.map((m) => (m.id === msgId ? { ...m, is_pinned: pinned } : m))
      );
    } catch {
      toast.error("Could not pin message");
    }
  };

  // ─── Render ─────────────────────────────────────────────────────────────────

  if (roomQuery.isLoading) {
    return (
      <div className="flex min-h-[100dvh] items-center justify-center bg-background">
        <div className="h-8 w-8 animate-spin rounded-full border-2 border-emerald-500 border-t-transparent" />
      </div>
    );
  }

  if (!room) {
    return (
      <div className="flex min-h-[100dvh] flex-col bg-background">
        <FloatingHeader
          title="Space"
          left={<FloatingButton to="/live" label="Back"><ArrowLeft className="h-5 w-5" /></FloatingButton>}
        />
        <main className="mx-auto flex w-full max-w-xl flex-col items-center px-4 py-12 text-center">
          <Radio className="mb-4 h-12 w-12 text-muted-foreground" />
          <p className="text-lg font-bold">This Space is unavailable</p>
          <p className="mt-1 text-sm text-muted-foreground">It may have ended or been removed.</p>
          <Link to="/live" className="mt-6 rounded-full bg-emerald-500 px-5 py-2.5 text-sm font-bold text-background">Back to Live</Link>
        </main>
      </div>
    );
  }

  const hostProfile = hostId ? profiles[hostId] : null;
  const listenerIds = (listenersQuery.data ?? []).filter((uid) => uid !== hostId && !speakers.some((s) => s.user_id === uid));
  const listenerProfiles = listenerIds.map((uid) => profiles[uid]).filter(Boolean);
  const pendingRequests = (requestsQuery.data ?? []).filter((r) => r.status === "pending");
  // Cap at 4 on-camera tiles; the screen sharer always leads (big tile).
  const videoParticipants = participants
    .filter((p) => p.hasVideo || p.isSpeaker)
    .sort((a, b) => Number(b.isScreenSharing) - Number(a.isScreenSharing))
    .slice(0, MAX_BROADCASTERS);
  // Shared screens take the spotlight automatically (manual spotlight wins).
  const screenSharerPeerId = videoParticipants.find((p) => p.isScreenSharing)?.peerId ?? null;
  const effectiveSpotlightId = spotlightPeerId ?? screenSharerPeerId;
  // Auto-pin: show the latest host message at the top when nothing is
  // explicitly pinned. The host always gets the pinned slot so viewers see
  // what the host is saying even if they joined mid-stream.
  const pinnedMessage = chatMessages.find((m) => m.is_pinned) ??
    [...chatMessages].reverse().find((m) => m.is_host && !m.body.startsWith("::whisper-"));

  // The stage: a spotlight (a shared screen, or a double-tapped tile) leads
  // with the rest as thumbnails; otherwise everyone on camera shares a grid.
  const spotlightParticipant = effectiveSpotlightId
    ? videoParticipants.find((p) => p.peerId === effectiveSpotlightId) ?? null
    : null;
  const stageOthers = spotlightParticipant
    ? videoParticipants.filter((p) => p.peerId !== spotlightParticipant.peerId)
    : [];
  const hostName = hostProfile?.display_name ?? hostProfile?.username ?? "Host";
  const showRulesLine = extras.slowSeconds > 0 || extras.followersOnly;

  const stageEmptyLine = ((): string => {
    if (isHost) {
      if (connecting) return "Starting your stream…";
      if (audioConnected) return "Your camera is off — turn it on or share your screen to put something on the stage.";
      return "Getting your stream ready…";
    }
    if (connecting) return "Connecting…";
    if (audioConnected) return "Audio-only right now — the host hasn't turned a camera on.";
    if (joined) return "Connecting to the stream…";
    return "Join to start watching.";
  })();

  return (
    <div className="dark fixed inset-0 z-[60] flex flex-col overflow-hidden bg-[#0e0e10] text-foreground lg:flex-row">
      {/* ═══════════════════════ STAGE COLUMN ═══════════════════════ */}
      <div className="flex min-h-0 min-w-0 flex-1 flex-col">
        {/* Top bar — back · LIVE · viewers · clock · title · tools */}
        <header className="flex h-12 shrink-0 items-center gap-2 border-b border-white/10 px-2 sm:px-3">
          <Link to="/live" aria-label="Back to Live" className={TOPBAR_BTN}>
            <ArrowLeft className="h-5 w-5" />
          </Link>
          <span className="flex h-6 shrink-0 items-center gap-1.5 rounded-md bg-[#F22659] px-2 text-[11px] font-black uppercase tracking-wider text-white">
            <span className="h-1.5 w-1.5 rounded-full bg-white" />
            Live
          </span>
          <span className="flex h-6 shrink-0 items-center gap-1 rounded-md bg-white/10 px-2 text-[12px] font-bold tabular-nums text-white">
            <Eye className="h-3.5 w-3.5" />
            {room.listener_count.toLocaleString()}
          </span>
          {isHost && (
            <span className="hidden h-6 shrink-0 items-center rounded-md bg-white/10 px-2 text-[12px] font-bold tabular-nums text-white/80 sm:flex">
              {sessionElapsed}
            </span>
          )}
          <p className="min-w-0 flex-1 truncate px-1 text-[14px] font-semibold text-white">{room.name}</p>
          <div className="flex shrink-0 items-center gap-0.5">
            <button onClick={() => void shareLive()} aria-label="Share live link" className={TOPBAR_BTN}>
              <Share2 className="h-4 w-4" />
            </button>
            {isHost && (
              <button onClick={() => setShowInviteModal(true)} aria-label="Invite friends to broadcast" className={TOPBAR_BTN}>
                <UserPlus className="h-4 w-4" />
              </button>
            )}
            {isHost && (
              <button
                onClick={() => setSidePanel(sidePanel === "requests" ? "chat" : "requests")}
                aria-label="Speaker requests"
                className={cn(TOPBAR_BTN, "relative", sidePanel === "requests" && "bg-white/15 text-white")}
              >
                <Hand className="h-4 w-4" />
                {pendingRequests.length > 0 && (
                  <span className="absolute -right-0.5 -top-0.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-[#F22659] px-1 text-[9px] font-bold text-white">
                    {pendingRequests.length}
                  </span>
                )}
              </button>
            )}
            {isHost && (
              <button
                onClick={() => setSidePanel(sidePanel === "manager" ? "chat" : "manager")}
                aria-label="Stream Manager"
                className={cn(TOPBAR_BTN, sidePanel === "manager" && "bg-white/15 text-white")}
              >
                <SlidersHorizontal className="h-4 w-4" />
              </button>
            )}
          </div>
        </header>

        {/* ─── The stage ─── */}
        <div className="relative min-h-0 flex-1 bg-black">
          <div className="absolute inset-0">
            {videoParticipants.length === 0 ? (
              <div className="absolute inset-0 overflow-hidden">
                {hostProfile?.profile_image_url ? (
                  <img
                    src={hostProfile.profile_image_url}
                    alt=""
                    className="absolute inset-[-12%] h-[124%] w-[124%] object-cover opacity-70 blur-[44px] saturate-[0.85]"
                    draggable={false}
                  />
                ) : (
                  <div className="absolute inset-0 opacity-30" style={{ background: WHISPER_BRAND_GRADIENT }} />
                )}
                <div className="absolute inset-0 bg-black/45" />
                <div className="relative flex h-full flex-col items-center justify-center gap-3 px-6 text-center">
                  <Avatar
                    url={hostProfile?.profile_image_url ?? null}
                    name={hostProfile?.username ?? "host"}
                    size={88}
                    className="ring-2 ring-white/25"
                  />
                  <p className="text-[16px] font-bold text-white">{hostName}</p>
                  <p className="max-w-sm text-[13px] leading-snug text-white/65">{stageEmptyLine}</p>
                  {isHost && audioConnected && (
                    <div className="mt-1 flex flex-wrap justify-center gap-2">
                      <button
                        onClick={() => void toggleCamera()}
                        className="flex h-10 items-center gap-2 rounded-full bg-white px-4 text-[13px] font-bold text-black transition-transform active:scale-95"
                      >
                        <Video className="h-4 w-4" />
                        Turn on camera
                      </button>
                      <button
                        onClick={() => void toggleScreenShare()}
                        className="flex h-10 items-center gap-2 rounded-full border border-white/25 bg-white/10 px-4 text-[13px] font-bold text-white transition-transform active:scale-95"
                      >
                        <MonitorUp className="h-4 w-4" />
                        Share screen
                      </button>
                    </div>
                  )}
                </div>
              </div>
            ) : spotlightParticipant ? (
              <>
                <VideoTile
                  key={spotlightParticipant.peerId}
                  participant={spotlightParticipant}
                  profile={profiles[spotlightParticipant.userId]}
                  isLocal={spotlightParticipant.userId === user?.id}
                  remoteStream={remoteStreams.get(spotlightParticipant.peerId) ?? null}
                  isHost={speakers.some((s) => s.user_id === spotlightParticipant.userId && s.is_host)}
                  isSpotlight
                  fill
                  onDoubleTap={() => setSpotlightPeerId(null)}
                />
                {stageOthers.length > 0 && (
                  <div className="absolute bottom-3 right-3 z-10 flex gap-2">
                    {stageOthers.map((p) => (
                      <div key={p.peerId} className="w-24 sm:w-32 lg:w-40">
                        <VideoTile
                          participant={p}
                          profile={profiles[p.userId]}
                          isLocal={p.userId === user?.id}
                          remoteStream={remoteStreams.get(p.peerId) ?? null}
                          isHost={speakers.some((s) => s.user_id === p.userId && s.is_host)}
                          compact
                          onDoubleTap={() => setSpotlightPeerId(p.peerId)}
                        />
                      </div>
                    ))}
                  </div>
                )}
              </>
            ) : (
              <div
                className={cn(
                  "relative grid h-full w-full auto-rows-fr gap-1 p-1",
                  videoParticipants.length === 1 ? "grid-cols-1" : "grid-cols-2"
                )}
              >
                <LinkedRingsOverlay
                  participants={videoParticipants}
                  profiles={profiles}
                  spotlightPeerId={effectiveSpotlightId}
                />
                {videoParticipants.map((p) => (
                  <VideoTile
                    key={p.peerId}
                    participant={p}
                    profile={profiles[p.userId]}
                    isLocal={p.userId === user?.id}
                    remoteStream={remoteStreams.get(p.peerId) ?? null}
                    isHost={speakers.some((s) => s.user_id === p.userId && s.is_host)}
                    fill
                    onDoubleTap={() => setSpotlightPeerId(p.peerId)}
                  />
                ))}
              </div>
            )}
          </div>

          {/* Goal bar — Twitch's overlay grammar, synced to every viewer */}
          {extras.goalTarget > 0 && (
            <div className="pointer-events-none absolute left-3 top-3 z-20 w-[min(320px,calc(100%-24px))] rounded-xl bg-black/55 px-3 py-2 backdrop-blur-md">
              <div className="flex items-center justify-between gap-2">
                <p className="truncate text-[12px] font-bold text-white">{extras.goalLabel || "Hearts goal"}</p>
                <p className="shrink-0 text-[11px] font-bold tabular-nums text-white/75">
                  {Math.min(extras.goalCount, extras.goalTarget)} / {extras.goalTarget}
                  {extras.goalCount >= extras.goalTarget ? " · reached 🎉" : ""}
                </p>
              </div>
              <div className="mt-1.5 h-1.5 overflow-hidden rounded-full bg-white/15">
                <div
                  className="h-full rounded-full transition-all duration-500"
                  style={{
                    width: `${Math.min(100, (extras.goalCount / Math.max(1, extras.goalTarget)) * 100)}%`,
                    background: extras.goalCount >= extras.goalTarget ? "#FFA94D" : WHISPER_BRAND_GRADIENT,
                  }}
                />
              </div>
            </div>
          )}

          {/* Status chips — top right */}
          <div className="pointer-events-none absolute right-3 top-3 z-20 flex flex-col items-end gap-1.5">
            {connecting && (
              <span className="flex items-center gap-1.5 rounded-full bg-black/55 px-2.5 py-1 text-[11px] font-semibold text-white backdrop-blur-md">
                <Loader2 className="h-3 w-3 animate-spin" />
                Connecting…
              </span>
            )}
            {screenSharing && (
              <span className="flex items-center gap-1.5 rounded-full bg-black/55 px-2.5 py-1 text-[11px] font-semibold text-white backdrop-blur-md">
                <MonitorUp className="h-3 w-3" />
                You're sharing your screen
              </span>
            )}
          </div>

          {/* Floating reactions live INSIDE the stage */}
          <div className="pointer-events-none absolute inset-0 z-20 overflow-hidden">
            {floatingReactions.map((r) => (
              <div
                key={r.id}
                className="absolute bottom-6 text-3xl"
                style={{ left: `${r.x}%`, animation: "floatUp 3s ease-out forwards" }}
              >
                {r.emoji}
              </div>
            ))}
          </div>
          <style>{`
            @keyframes floatUp {
              0% { transform: translateY(0) scale(0.5); opacity: 0; }
              15% { transform: translateY(-20px) scale(1.2); opacity: 1; }
              80% { transform: translateY(-200px) scale(1) rotate(10deg); opacity: 0.8; }
              100% { transform: translateY(-300px) scale(0.8) rotate(-5deg); opacity: 0; }
            }
          `}</style>

          {/* Gift banners — realtime, everyone sees them */}
          {giftBanners.length > 0 && (
            <div className="pointer-events-none absolute bottom-3 left-3 z-30 flex flex-col gap-2">
              {giftBanners.map((b) => (
                <div
                  key={b.key}
                  className="flex items-center gap-2.5 rounded-2xl border border-white/10 bg-black/70 py-2 pl-2.5 pr-4 shadow-xl backdrop-blur-md animate-rise"
                >
                  <span className="text-2xl">{b.emoji}</span>
                  <div>
                    <p className="text-[12.5px] font-extrabold text-white">@{b.sender}</p>
                    <p className="text-[11px] font-semibold text-[#FF7A99]">
                      sent a {b.label}
                      {b.qty > 1 ? ` ×${b.qty}` : ""}
                    </p>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* ─── Under the stage: channel info + controls ─── */}
        <div className="shrink-0 border-t border-white/10 bg-[#0e0e10] px-3 py-3 lg:px-5">
          <div className="flex items-start gap-3">
            <Link
              to={hostProfile?.username ? `/u/${hostProfile.username}` : "#"}
              className="relative shrink-0"
              aria-label={`@${hostProfile?.username ?? "host"}`}
            >
              <span className="absolute -inset-[3px] rounded-full" style={{ background: WHISPER_BRAND_GRADIENT }} />
              <span className="absolute -inset-px rounded-full bg-[#0e0e10]" />
              <Avatar
                url={hostProfile?.profile_image_url ?? null}
                name={hostProfile?.username ?? "host"}
                size={44}
                className="relative"
              />
            </Link>
            <div className="min-w-0 flex-1">
              <h1 className="truncate text-[15px] font-bold leading-tight text-white sm:text-[16px]">{room.name}</h1>
              <p className="mt-0.5 flex flex-wrap items-center gap-x-1.5 gap-y-0.5 text-[12.5px] text-white/65">
                <span className="font-semibold text-white/85">{hostName}</span>
                {room.topic && (
                  <>
                    <span aria-hidden>·</span>
                    <span className="rounded-md bg-white/10 px-1.5 py-0.5 text-[11px] font-semibold text-white/80">{room.topic}</span>
                  </>
                )}
                <span aria-hidden>·</span>
                <span className="tabular-nums">{room.listener_count.toLocaleString()} watching</span>
                {speakers.length > 1 && (
                  <>
                    <span aria-hidden>·</span>
                    <span>{speakers.length} on stage</span>
                  </>
                )}
              </p>
              {room.description && (
                <p className="mt-1 hidden text-[12.5px] leading-snug text-white/55 line-clamp-1 lg:block">{room.description}</p>
              )}
            </div>
            <div className="flex shrink-0 items-center gap-1.5">
              {!isHost && user && (
                <button
                  onClick={() => setShowGiftSheet(true)}
                  className="flex h-9 items-center gap-1.5 rounded-full px-3.5 text-[12.5px] font-bold text-white transition-transform active:scale-95"
                  style={{ background: WHISPER_BRAND_GRADIENT }}
                  aria-label="Send a gift"
                >
                  <Gift className="h-4 w-4" />
                  <span className="hidden sm:inline">Gift</span>
                </button>
              )}
              <button
                onClick={() => void shareLive()}
                className="hidden h-9 items-center gap-1.5 rounded-full bg-white/10 px-3.5 text-[12.5px] font-bold text-white transition-colors hover:bg-white/15 sm:flex"
              >
                <Share2 className="h-4 w-4" />
                Share
              </button>
            </div>
          </div>

          {/* Controls */}
          <div className="mt-3 flex items-center gap-2 overflow-x-auto">
            {joined && audioConnected && (
              <>
                <button
                  onClick={() => void toggleMic()}
                  className={cn(CTRL_BTN, micOn ? "bg-white/10 text-white hover:bg-white/15" : "bg-[#F22659] text-white")}
                  aria-label={micOn ? "Mute" : "Unmute"}
                >
                  {micOn ? <Mic className="h-5 w-5" /> : <MicOff className="h-5 w-5" />}
                </button>
                {canPublish && (
                  <button
                    onClick={() => void toggleCamera()}
                    className={cn(CTRL_BTN, cameraOn ? "bg-white text-black" : "bg-white/10 text-white/70 hover:bg-white/15")}
                    aria-label={cameraOn ? "Turn camera off" : "Turn camera on"}
                  >
                    {cameraOn ? <Video className="h-5 w-5" /> : <VideoOff className="h-5 w-5" />}
                  </button>
                )}
                {canPublish && (
                  <button
                    onClick={() => void toggleScreenShare()}
                    className={cn(CTRL_BTN, screenSharing ? "bg-white text-black" : "bg-white/10 text-white/70 hover:bg-white/15")}
                    aria-label={screenSharing ? "Stop sharing screen" : "Share screen"}
                  >
                    {screenSharing ? <MonitorOff className="h-5 w-5" /> : <MonitorUp className="h-5 w-5" />}
                  </button>
                )}
                {(isHost || isCoach || isRecruiter || isCreator) && (
                  <button
                    onClick={() => setShowPollCreator(true)}
                    className={cn(CTRL_BTN, "bg-white/10 text-white/70 hover:bg-white/15")}
                    aria-label="Create poll"
                  >
                    <BarChart3 className="h-5 w-5" />
                  </button>
                )}
                {isCoach && (
                  <button
                    onClick={() => setShowCoachTools(true)}
                    className={cn(CTRL_BTN, "bg-white/10 text-white/70 hover:bg-white/15")}
                    aria-label="Coach tools"
                  >
                    <Dumbbell className="h-5 w-5" />
                  </button>
                )}
                {isCreator && (
                  <button
                    onClick={() => setShowCreatorTools(true)}
                    className={cn(CTRL_BTN, "bg-white/10 text-white/70 hover:bg-white/15")}
                    aria-label="Creator tools"
                  >
                    <Sparkles className="h-5 w-5" />
                  </button>
                )}
                {isRecruiter && (
                  <button
                    onClick={() => setShowRecruiterTools(true)}
                    className={cn(CTRL_BTN, "bg-white/10 text-white/70 hover:bg-white/15")}
                    aria-label="Recruiter tools"
                  >
                    <Target className="h-5 w-5" />
                  </button>
                )}
              </>
            )}
            {joined && !isHost && !audioConnected && !connecting && (
              <button
                onClick={() => void connectRTC(true)}
                className="flex h-10 shrink-0 items-center gap-2 rounded-full bg-white/10 px-4 text-[13px] font-bold text-white transition-colors hover:bg-white/15"
              >
                <Headphones className="h-4 w-4" />
                Listen in
              </button>
            )}
            {!isHost && !isSpeaker && joined && (
              <button
                onClick={() => setShowRequestModal(true)}
                className="flex h-10 shrink-0 items-center gap-2 rounded-full bg-white/10 px-4 text-[13px] font-bold text-white transition-colors hover:bg-white/15"
              >
                <Hand className="h-4 w-4" />
                Request to speak
              </button>
            )}
            {joined && !isHost && (
              <button
                onClick={() => {
                  setHandRaised((h) => !h);
                  toast.info(handRaised ? "Hand lowered" : "Hand raised");
                }}
                className={cn(CTRL_BTN, handRaised ? "bg-[#FFA94D] text-black" : "bg-white/10 text-white/70 hover:bg-white/15")}
                aria-label="Raise hand"
              >
                <Hand className="h-5 w-5" />
              </button>
            )}
            <div className="flex-1" />
            {isHost ? (
              <button
                onClick={() => endMutation.mutate()}
                disabled={endMutation.isPending}
                className="flex h-10 shrink-0 items-center gap-2 rounded-full bg-[#F22659] px-4 text-[13px] font-bold text-white transition-transform active:scale-95 disabled:opacity-50"
              >
                <X className="h-4 w-4" />
                {endMutation.isPending ? "Ending…" : "End stream"}
              </button>
            ) : !joined ? (
              <button
                onClick={() => joinMutation.mutate()}
                disabled={!user || joinMutation.isPending}
                className="flex h-10 shrink-0 items-center gap-2 rounded-full px-5 text-[13px] font-bold text-white transition-transform active:scale-95 disabled:opacity-50"
                style={{ background: WHISPER_BRAND_GRADIENT }}
              >
                <Radio className="h-4 w-4" />
                {!user ? "Sign in" : joinMutation.isPending ? "Joining…" : "Watch"}
              </button>
            ) : (
              <button
                onClick={() => leaveMutation.mutate()}
                disabled={leaveMutation.isPending}
                className="flex h-10 shrink-0 items-center gap-2 rounded-full bg-white/10 px-4 text-[13px] font-bold text-white transition-colors hover:bg-white/15 disabled:opacity-50"
              >
                <X className="h-4 w-4" />
                {leaveMutation.isPending ? "Leaving…" : "Leave"}
              </button>
            )}
          </div>
        </div>
      </div>

      {/* ═══════════════════════ CHAT COLUMN ═══════════════════════ */}
      <aside className="flex h-[44dvh] shrink-0 flex-col border-t border-white/10 bg-[#18181b] lg:h-auto lg:w-[340px] lg:border-l lg:border-t-0 xl:w-[360px]">
        <div className="flex h-12 shrink-0 items-center border-b border-white/10 px-2">
          {isHost ? (
            <div className="flex w-full items-center gap-1">
              {(["chat", "manager", "requests"] as LiveSidePanel[]).map((k) => (
                <button
                  key={k}
                  onClick={() => setSidePanel(k)}
                  className={cn(
                    "flex h-8 items-center gap-1.5 rounded-full px-3 text-[12px] font-bold transition-colors",
                    sidePanel === k ? "bg-white text-black" : "text-white/60 hover:bg-white/10 hover:text-white"
                  )}
                >
                  {k === "chat" ? "Chat" : k === "manager" ? "Manager" : "Requests"}
                  {k === "requests" && pendingRequests.length > 0 && (
                    <span
                      className={cn(
                        "flex h-4 min-w-4 items-center justify-center rounded-full px-1 text-[9.5px] font-bold",
                        sidePanel === k ? "bg-black text-white" : "bg-[#F22659] text-white"
                      )}
                    >
                      {pendingRequests.length}
                    </span>
                  )}
                </button>
              ))}
            </div>
          ) : (
            <p className="px-2 text-[11.5px] font-black uppercase tracking-[0.14em] text-white/60">Stream chat</p>
          )}
        </div>

        {sidePanel === "manager" && isHost ? (
          /* ─── STREAM MANAGER — docked, not a modal ─── */
          <div className="min-h-0 flex-1 overflow-y-auto px-4 py-4">
            <p className="text-[15px] font-extrabold text-white">Stream Manager</p>
            <p className="text-[12px] text-white/55">Stats, title, rules, raids & moderation.</p>

            <div className="mt-4 grid grid-cols-3 gap-2">
              <div className={MANAGER_TILE}>
                <p className="text-[9.5px] font-black uppercase tracking-wide text-white/50">Session</p>
                <p className="mt-0.5 text-[15px] font-extrabold tabular-nums text-white">{sessionElapsed}</p>
              </div>
              <div className={MANAGER_TILE}>
                <p className="text-[9.5px] font-black uppercase tracking-wide text-white/50">Watching</p>
                <p className="mt-0.5 text-[15px] font-extrabold tabular-nums text-white">{room.listener_count.toLocaleString()}</p>
              </div>
              <div className={MANAGER_TILE}>
                <p className="text-[9.5px] font-black uppercase tracking-wide text-white/50">Peak</p>
                <p className="mt-0.5 text-[15px] font-extrabold tabular-nums text-white">
                  {Math.max(peakListeners, room.listener_count).toLocaleString()}
                </p>
              </div>
            </div>

            <div className="mt-5">
              <p className={MANAGER_KICKER}>Title & category</p>
              <input
                value={titleDraft}
                onChange={(e) => setTitleDraft(e.target.value)}
                placeholder="Live title"
                className={cn(MANAGER_INPUT, "mt-1.5")}
              />
              <div className="mt-2 flex gap-2">
                <input
                  value={topicDraft}
                  onChange={(e) => setTopicDraft(e.target.value)}
                  placeholder="Category — Gaming, Coaching, Q&A…"
                  className={cn(MANAGER_INPUT, "min-w-0 flex-1")}
                />
                <button
                  onClick={() => void saveRoomDetails()}
                  className="h-[42px] shrink-0 rounded-full bg-white px-4 text-[12.5px] font-bold text-black transition-transform active:scale-[0.97]"
                >
                  Save
                </button>
              </div>
            </div>

            <div className="mt-5">
              <p className={MANAGER_KICKER}>Live goal</p>
              <div className="mt-1.5 flex gap-2">
                <input
                  value={goalLabelDraft}
                  onChange={(e) => setGoalLabelDraft(e.target.value)}
                  placeholder="Hearts goal"
                  className={cn(MANAGER_INPUT, "min-w-0 flex-1")}
                />
                <input
                  value={goalTargetDraft}
                  onChange={(e) => setGoalTargetDraft(e.target.value)}
                  inputMode="numeric"
                  placeholder="200"
                  className={cn(MANAGER_INPUT, "w-24")}
                />
              </div>
              <div className="mt-2 flex gap-2">
                <button
                  onClick={applyGoal}
                  className="h-9 rounded-full px-4 text-[12.5px] font-bold text-white transition-transform active:scale-[0.97]"
                  style={{ background: WHISPER_BRAND_GRADIENT }}
                >
                  Set goal
                </button>
                {extras.goalTarget > 0 && (
                  <button
                    onClick={() => setExtras((prev) => ({ ...prev, goalTarget: 0, goalCount: 0 }))}
                    className="h-9 rounded-full border border-white/15 px-4 text-[12.5px] font-bold text-white"
                  >
                    Clear
                  </button>
                )}
              </div>
              <p className="mt-1.5 text-[10.5px] text-white/50">Every floating reaction counts toward the goal.</p>
            </div>

            <div className="mt-5">
              <p className={MANAGER_KICKER}>Slow mode</p>
              <div className="mt-1.5 grid grid-cols-4 gap-1.5">
                {[0, 5, 15, 30].map((secs) => (
                  <button
                    key={secs}
                    onClick={() => setExtras((prev) => ({ ...prev, slowSeconds: secs }))}
                    className={cn(
                      "h-9 rounded-full text-[12.5px] font-bold transition-colors",
                      extras.slowSeconds === secs ? "bg-white text-black" : "border border-white/15 text-white/70"
                    )}
                  >
                    {secs === 0 ? "Off" : `${secs}s`}
                  </button>
                ))}
              </div>
            </div>

            <div className={cn(MANAGER_TILE, "mt-4 flex items-center justify-between")}>
              <div>
                <p className="text-[13.5px] font-bold text-white">Followers-only chat</p>
                <p className="text-[11px] text-white/50">Only people who follow you can send messages.</p>
              </div>
              <button
                onClick={() => setExtras((prev) => ({ ...prev, followersOnly: !prev.followersOnly }))}
                aria-label="Toggle followers-only chat"
                className={cn("relative h-7 w-12 shrink-0 rounded-full transition-colors", extras.followersOnly ? "bg-white" : "bg-white/15")}
              >
                <span
                  className={cn(
                    "absolute top-0.5 h-6 w-6 rounded-full shadow transition-all",
                    extras.followersOnly ? "left-[22px] bg-black" : "left-0.5 bg-white"
                  )}
                />
              </button>
            </div>

            <div className="mt-5">
              <p className={MANAGER_KICKER}>Raid another live</p>
              {raidRooms.length === 0 ? (
                <p className="mt-1.5 text-[12px] text-white/50">
                  No other live rooms right now — raiding sends your whole audience to a friend's stream when you wrap up.
                </p>
              ) : (
                <div className="mt-1.5 space-y-1.5">
                  {raidRooms.map((r) => (
                    <button
                      key={r.id}
                      onClick={() => startRaid(r)}
                      className={cn(MANAGER_TILE, "flex w-full items-center justify-between text-left transition-colors hover:border-white/30")}
                    >
                      <span className="min-w-0 truncate text-[13.5px] font-bold text-white">{r.name}</span>
                      <span className="shrink-0 text-[11.5px] font-bold text-[#FF7340]">Raid →</span>
                    </button>
                  ))}
                </div>
              )}
            </div>

            {/* ─── Gifts & earnings ─── */}
            <div className="mt-5 border-t border-white/10 pt-4">
              <p className={cn(MANAGER_KICKER, "flex items-center gap-1.5")}>
                <Gift className="h-3.5 w-3.5" />
                Gifts & earnings
              </p>
              <div className="mt-2.5 grid grid-cols-2 gap-2">
                <div className={MANAGER_TILE}>
                  <p className="text-[9.5px] font-black uppercase tracking-wide text-white/50">This stream</p>
                  <p className="mt-0.5 text-[15px] font-extrabold tabular-nums text-[#FF7A99]">{formatGiftCents(streamGiftNetCents)}</p>
                </div>
                <div className={MANAGER_TILE}>
                  <p className="text-[9.5px] font-black uppercase tracking-wide text-white/50">Cashable</p>
                  <p className="mt-0.5 text-[15px] font-extrabold tabular-nums text-[#33C780]">
                    {formatGiftCents(giftEarnings?.availableCents ?? 0)}
                  </p>
                </div>
              </div>
              {giftEarnings && !giftEarnings.ready ? (
                <p className="mt-2 rounded-xl border border-[#FFA94D]/40 bg-[#FFA94D]/10 px-3 py-2.5 text-[11.5px] leading-relaxed text-white/70">
                  One-time setup: run <code className="rounded bg-white/10 px-1">supabase/live-gifts.sql</code> in the Supabase SQL
                  editor to switch on gifts.
                </p>
              ) : (
                <>
                  <button
                    onClick={() => void handleGiftCashout()}
                    disabled={giftCashingOut || (giftEarnings?.availableCents ?? 0) < 1000}
                    className="mt-2 flex h-10 w-full items-center justify-center gap-2 rounded-full bg-white text-[12.5px] font-bold text-black transition-transform active:scale-[0.98] disabled:opacity-40"
                  >
                    {giftCashingOut && <Loader2 className="h-4 w-4 animate-spin" />}
                    {(giftEarnings?.availableCents ?? 0) >= 1000
                      ? `Cash out ${formatGiftCents(giftEarnings?.availableCents ?? 0)}`
                      : "Cash out (min $10)"}
                  </button>
                  <p className="mt-1.5 text-[10.5px] text-white/50">
                    Viewers send gifts from prepaid credits — you keep 70%, paid to your linked bank on the same Stripe rail as
                    coaching.
                  </p>
                </>
              )}
            </div>

            {/* ─── Past streams ─── */}
            <div className="mt-5 border-t border-white/10 pt-4">
              <p className={cn(MANAGER_KICKER, "flex items-center gap-1.5")}>
                <BarChart3 className="h-3.5 w-3.5" />
                Past streams
              </p>
              {pastStreams === null ? (
                <p className="mt-2 text-[12px] text-white/50">Loading…</p>
              ) : pastStreams.length === 0 ? (
                <p className="mt-2 text-[12px] text-white/50">
                  Your ended streams show up here with duration, peak viewers, chat and gift totals.
                </p>
              ) : (
                <div className="mt-2 space-y-1.5">
                  {pastStreams.map((s) => (
                    <div key={s.id} className={MANAGER_TILE}>
                      <div className="flex items-center justify-between gap-2">
                        <p className="min-w-0 truncate text-[13px] font-bold text-white">{s.name}</p>
                        <p className="shrink-0 text-[10.5px] font-semibold text-white/50">
                          {new Date(s.endedAt).toLocaleDateString("en-US", { month: "short", day: "numeric" })}
                        </p>
                      </div>
                      <p className="mt-0.5 text-[11px] tabular-nums text-white/55">
                        {s.durationMin}m · peak {s.peak} · {s.messages} chats
                        {s.giftCents > 0 ? ` · ${formatGiftCents(s.giftCents)} gifts` : ""}
                      </p>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* ─── Moderation ─── */}
            <div className="mt-5 border-t border-white/10 pt-4">
              <p className={cn(MANAGER_KICKER, "flex items-center gap-1.5")}>
                <ShieldCheck className="h-3.5 w-3.5" />
                Moderation
              </p>
              {modState.missing ? (
                <p className="mt-2 rounded-xl border border-[#FFA94D]/40 bg-[#FFA94D]/10 px-3 py-2.5 text-[11.5px] leading-relaxed text-white/70">
                  One-time setup: run <code className="rounded bg-white/10 px-1">supabase/live-v2.sql</code> in the Supabase SQL
                  editor to unlock mods, bans, timeouts and blocked words.
                </p>
              ) : (
                <>
                  <p className="mt-2.5 text-[12px] font-bold text-white">Channel mods</p>
                  <p className="text-[10.5px] text-white/50">
                    Mods can delete messages, time out and ban viewers in every live you run — hover a chat message for their
                    tools.
                  </p>
                  {modState.mods.length > 0 && (
                    <div className="mt-1.5 flex flex-wrap gap-1.5">
                      {modState.mods.map((m) => (
                        <span
                          key={m.mod_user_id}
                          className="flex items-center gap-1 rounded-full bg-white/10 px-2.5 py-1 text-[11.5px] font-bold text-white"
                        >
                          @{m.mod_username}
                          <button
                            onClick={() => void handleRemoveMod(m.mod_user_id)}
                            aria-label={`Remove ${m.mod_username} as mod`}
                            className="text-white/50 transition-colors hover:text-white"
                          >
                            <X className="h-3 w-3" />
                          </button>
                        </span>
                      ))}
                    </div>
                  )}
                  <div className="mt-2 flex gap-2">
                    <input
                      value={modInput}
                      onChange={(e) => setModInput(e.target.value)}
                      onKeyDown={(e) => {
                        if (e.key === "Enter") void handleAddMod();
                      }}
                      placeholder="@username"
                      className={cn(MANAGER_INPUT, "min-w-0 flex-1 py-2 text-[13px]")}
                    />
                    <button
                      onClick={() => void handleAddMod()}
                      disabled={modBusy || !modInput.trim()}
                      className="h-[38px] shrink-0 rounded-full border border-white/15 px-3.5 text-[12px] font-bold text-white disabled:opacity-50"
                    >
                      Add mod
                    </button>
                  </div>

                  <p className="mt-4 text-[12px] font-bold text-white">Blocked words</p>
                  <p className="text-[10.5px] text-white/50">Messages containing these words are stopped before they send.</p>
                  <div className="mt-1.5 flex gap-2">
                    <input
                      value={bannedWordsDraft}
                      onChange={(e) => setBannedWordsDraft(e.target.value)}
                      placeholder="comma, separated, words"
                      className={cn(MANAGER_INPUT, "min-w-0 flex-1 py-2 text-[13px]")}
                    />
                    <button
                      onClick={() => void handleSaveBannedWords()}
                      className="h-[38px] shrink-0 rounded-full border border-white/15 px-3.5 text-[12px] font-bold text-white"
                    >
                      Save
                    </button>
                  </div>

                  {modState.bans.length > 0 && (
                    <>
                      <p className="mt-4 text-[12px] font-bold text-white">Banned from your channel</p>
                      <div className="mt-1.5 space-y-1.5">
                        {modState.bans.map((b) => (
                          <div key={b.banned_user_id} className={cn(MANAGER_TILE, "flex items-center justify-between py-2")}>
                            <span className="text-[12.5px] font-bold text-white">@{b.banned_username}</span>
                            <button
                              onClick={() => void handleUnban(b.banned_user_id)}
                              className="text-[11.5px] font-bold text-[#33C780]"
                            >
                              Unban
                            </button>
                          </div>
                        ))}
                      </div>
                    </>
                  )}
                </>
              )}
            </div>
          </div>
        ) : sidePanel === "requests" && isHost ? (
          /* ─── REQUESTS + PEOPLE ─── */
          <div className="min-h-0 flex-1 overflow-y-auto px-3 py-3">
            <p className={MANAGER_KICKER}>Speaker requests · {pendingRequests.length}</p>
            {pendingRequests.length === 0 ? (
              <p className="mt-2 rounded-xl border border-dashed border-white/15 px-3 py-5 text-center text-[12px] text-white/50">
                No requests yet — viewers can ask to join you on stage from the controls.
              </p>
            ) : (
              <div className="mt-2 space-y-2">
                {pendingRequests.map((r) => (
                  <RequestCard
                    key={r.id}
                    request={r}
                    profile={profiles[r.user_id]}
                    onAccept={() => acceptRequestMutation.mutate(r)}
                    onReject={() => rejectRequestMutation.mutate(r)}
                    isPending={acceptRequestMutation.isPending || rejectRequestMutation.isPending}
                  />
                ))}
              </div>
            )}

            <p className={cn(MANAGER_KICKER, "mt-5")}>On stage · {speakers.length}</p>
            <div className="mt-2 space-y-1">
              {speakers.map((s) => {
                const p = profiles[s.user_id];
                const liveP = participants.find((part) => part.userId === s.user_id);
                return (
                  <div key={s.user_id} className="flex items-center gap-2.5 rounded-xl px-2 py-1.5">
                    <Avatar url={p?.profile_image_url ?? null} name={p?.username ?? "speaker"} size={32} />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-[13px] font-bold text-white">{p?.display_name ?? p?.username ?? "Speaker"}</p>
                      <p className="text-[11px] text-white/50">
                        {s.is_host ? "Host" : liveP?.hasVideo ? "On camera" : liveP?.micOn ? "Speaking" : "Muted"}
                      </p>
                    </div>
                    {liveP?.micOn ? <Mic className="h-3.5 w-3.5 text-[#33C780]" /> : <MicOff className="h-3.5 w-3.5 text-white/40" />}
                    {!s.is_host && (
                      <button
                        onClick={() => removeSpeakerMutation.mutate(s.user_id)}
                        className="text-[11px] font-bold text-[#F22659] transition-opacity hover:opacity-70"
                      >
                        Remove
                      </button>
                    )}
                  </div>
                );
              })}
            </div>

            {listenerProfiles.length > 0 && (
              <>
                <p className={cn(MANAGER_KICKER, "mt-5")}>Watching · {listenerProfiles.length}</p>
                <div className="mt-2 flex flex-wrap gap-1.5">
                  {listenerProfiles.slice(0, 30).map((p) => (
                    <Avatar key={p.user_id} url={p.profile_image_url ?? null} name={p.username ?? "viewer"} size={28} />
                  ))}
                  {listenerProfiles.length > 30 && (
                    <div className="flex h-7 items-center rounded-full bg-white/10 px-3 text-[10px] font-bold text-white/70">
                      +{listenerProfiles.length - 30}
                    </div>
                  )}
                </div>
              </>
            )}
          </div>
        ) : (
          /* ─── STREAM CHAT ─── */
          <>
            {showRulesLine && (
              <p className="shrink-0 border-b border-white/10 px-3 py-1.5 text-[10.5px] font-semibold text-white/55">
                {extras.followersOnly ? "Followers-only chat" : ""}
                {extras.followersOnly && extras.slowSeconds > 0 ? " · " : ""}
                {extras.slowSeconds > 0 ? `Slow mode — one message every ${extras.slowSeconds}s` : ""}
              </p>
            )}
            {pinnedMessage && (
              <div className="flex shrink-0 items-start gap-2 border-b border-white/10 bg-white/[0.04] px-3 py-2">
                <Pin className="mt-0.5 h-3 w-3 shrink-0 text-[#FF7340]" />
                <div className="min-w-0 flex-1">
                  <p className="text-[11px] font-bold text-[#FF7340]">
                    {pinnedMessage.username}
                    {pinnedMessage.is_host && " · Host"}
                  </p>
                  <p className="text-[12px] leading-snug text-white">{pinnedPreview(pinnedMessage.body)}</p>
                </div>
                {isHost && (
                  <button
                    onClick={() => void pinMessage(pinnedMessage.id, false)}
                    className="text-[10px] font-bold text-white/50 hover:text-white"
                  >
                    Unpin
                  </button>
                )}
              </div>
            )}
            {polls.length > 0 && (
              <div className="shrink-0 space-y-1 border-b border-white/10 px-3 py-2">
                {polls.slice(0, 3).map((poll) => (
                  <PollCard
                    key={poll.id}
                    poll={poll}
                    voteCounts={pollVoteCounts[poll.id] ?? []}
                    myVote={myVotes[poll.id]}
                    canClose={poll.creator_id === user?.id}
                    onVote={(idx) => void votePoll(poll.id, idx).then(() => void refreshPolls())}
                    onClose={() => void closePoll(poll.id).then(() => void refreshPolls())}
                  />
                ))}
              </div>
            )}

            <div ref={chatScrollRef} className="min-h-0 flex-1 space-y-1 overflow-y-auto px-3 py-2">
              {chatMessages.length === 0 && polls.length === 0 ? (
                <div className="flex h-full flex-col items-center justify-center gap-2 text-center text-white/45">
                  <MessageCircle className="h-8 w-8 opacity-40" />
                  <p className="text-[13px] font-semibold">Welcome to the chat</p>
                  <p className="text-[11px]">Say hi — the host sees everything here.</p>
                </div>
              ) : (
                chatMessages.map((msg) => {
                  const msgProfile = profiles[msg.user_id];
                  const workoutPayload = parseWorkoutEmbed(msg.body);
                  return (
                    <div key={msg.id} className="group relative rounded-lg px-1.5 py-1 hover:bg-white/[0.04]">
                      <div className="flex items-start gap-2">
                        <Avatar url={msgProfile?.profile_image_url ?? null} name={msg.username} size={20} className="mt-0.5" />
                        <div className="min-w-0 flex-1 text-[13px] leading-snug">
                          <span className={cn("font-bold", msg.is_host ? "text-[#FF7340]" : "text-white")}>{msg.username}</span>
                          {msg.is_host && (
                            <span className="ml-1 rounded bg-[#F22659] px-1 py-px align-middle text-[8px] font-black uppercase text-white">
                              Host
                            </span>
                          )}
                          {workoutPayload ? (
                            <div className="mt-1">
                              <LiveWorkoutChatCard payload={workoutPayload} />
                            </div>
                          ) : (
                            <span className="text-white/90">
                              <span className="text-white/40">: </span>
                              {renderChatBody(msg.body)}
                            </span>
                          )}
                        </div>
                        <span className="shrink-0 pt-0.5 text-[9.5px] text-white/35">{timeAgoShort(msg.created_at)}</span>
                      </div>
                      {(isHost || canModerate) && !workoutPayload && (
                        <div className="absolute -top-2 right-1.5 hidden items-center gap-0.5 rounded-full border border-white/10 bg-[#0e0e10] px-1 py-0.5 shadow-lg group-hover:flex">
                          {isHost && (
                            <button
                              onClick={() => void pinMessage(msg.id, !msg.is_pinned)}
                              className="flex h-6 w-6 items-center justify-center rounded-full text-white/60 hover:bg-white/10 hover:text-white"
                              aria-label={msg.is_pinned ? "Unpin" : "Pin message"}
                            >
                              <Pin className={cn("h-3 w-3", msg.is_pinned && "fill-[#FF7340] text-[#FF7340]")} />
                            </button>
                          )}
                          {canModerate && msg.user_id !== user?.id && (
                            <>
                              <button
                                onClick={() => void modDeleteMessage(msg.id)}
                                className="flex h-6 w-6 items-center justify-center rounded-full text-white/60 hover:bg-white/10 hover:text-white"
                                aria-label="Delete message"
                              >
                                <Trash2 className="h-3 w-3" />
                              </button>
                              <button
                                onClick={() => void modTimeout(msg)}
                                className="flex h-6 w-6 items-center justify-center rounded-full text-white/60 hover:bg-white/10 hover:text-white"
                                aria-label="Time out for 5 minutes"
                              >
                                <Clock3 className="h-3 w-3" />
                              </button>
                              <button
                                onClick={() => void modBan(msg)}
                                className="flex h-6 w-6 items-center justify-center rounded-full text-white/60 hover:bg-white/10 hover:text-[#F22659]"
                                aria-label="Ban from channel"
                              >
                                <Ban className="h-3 w-3" />
                              </button>
                            </>
                          )}
                        </div>
                      )}
                    </div>
                  );
                })
              )}
            </div>

            {/* Chat input */}
            <div className="shrink-0 border-t border-white/10 px-3 py-2.5 pb-[max(0.625rem,env(safe-area-inset-bottom))]">
              {joined && user ? (
                <div className="flex items-center gap-2 rounded-xl border border-white/10 bg-white/[0.06] px-3 py-1.5 focus-within:border-white/30">
                  <input
                    value={chatDraft}
                    onChange={(e) => setChatDraft(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter" && chatDraft.trim()) void sendChat();
                    }}
                    placeholder="Send a message"
                    maxLength={500}
                    className="min-w-0 flex-1 bg-transparent py-1.5 text-[13px] text-white outline-none placeholder:text-white/40"
                  />
                  <button
                    onClick={() => void sendChat()}
                    disabled={!chatDraft.trim()}
                    className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-white transition-transform active:scale-90 disabled:opacity-30"
                    style={{ background: WHISPER_BRAND_GRADIENT }}
                    aria-label="Send"
                  >
                    <Send className="h-3.5 w-3.5" />
                  </button>
                </div>
              ) : user ? (
                <button
                  onClick={() => joinMutation.mutate()}
                  disabled={joinMutation.isPending}
                  className="flex h-10 w-full items-center justify-center gap-2 rounded-xl bg-white/10 text-[13px] font-bold text-white transition-colors hover:bg-white/15 disabled:opacity-50"
                >
                  <MessageCircle className="h-4 w-4" />
                  {joinMutation.isPending ? "Joining…" : "Join the stream to chat"}
                </button>
              ) : (
                <p className="py-2 text-center text-[12px] text-white/50">Sign in to chat.</p>
              )}
            </div>
          </>
        )}
      </aside>

      {showInviteModal && user && (
        <InviteFriendsModal
          roomId={id!}
          userId={user.id}
          slotsLeft={Math.max(0, MAX_BROADCASTERS - speakers.length)}
          alreadyIn={new Set(speakers.map((s) => s.user_id))}
          onClose={() => setShowInviteModal(false)}
        />
      )}

      {showRequestModal && (
        <SpeakerRequestModal
          roomId={id!}
          userId={user!.id}
          onClose={() => setShowRequestModal(false)}
          onSubmitted={() => {
            setShowRequestModal(false);
            setHandRaised(true);
            toast.success("Request sent. The host will review it.");
          }}
        />
      )}

      {showRequestsPanel && (
        <SpeakerRequestsPanel
          requests={requestsQuery.data ?? []}
          profiles={profiles}
          onClose={() => setShowRequestsPanel(false)}
          onAccept={(r) => acceptRequestMutation.mutate(r)}
          onReject={(r) => rejectRequestMutation.mutate(r)}
          isPending={acceptRequestMutation.isPending || rejectRequestMutation.isPending}
        />
      )}

      {showPollCreator && (
        <PollCreatorModal
          roomId={id!}
          userId={user!.id}
          username={profile?.username ?? "you"}
          onClose={() => setShowPollCreator(false)}
          onCreated={() => {
            setShowPollCreator(false);
            void refreshPolls();
            toast.success("Poll created");
          }}
        />
      )}

      {showCoachTools && (
        <CoachToolsSheet
          roomId={id!}
          userId={user!.id}
          username={profile?.username ?? "you"}
          onClose={() => setShowCoachTools(false)}
        />
      )}

      {showCreatorTools && (
        <CreatorToolsSheet onClose={() => setShowCreatorTools(false)} onReaction={(emoji) => void sendReaction(emoji)} />
      )}

      {showGiftSheet && user && <LiveGiftSheet roomId={id!} onClose={() => setShowGiftSheet(false)} />}

      {showRecruiterTools && (
        <RecruiterToolsSheet
          roomId={id!}
          participants={participants}
          profiles={profiles}
          listenerCount={room.listener_count}
          onClose={() => setShowRecruiterTools(false)}
        />
      )}
    </div>
  );
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function InviteFriendsModal({
  roomId,
  userId,
  slotsLeft,
  alreadyIn,
  onClose,
}: {
  roomId: string;
  userId: string;
  slotsLeft: number;
  alreadyIn: Set<string>;
  onClose: () => void;
}) {
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [sending, setSending] = useState(false);

  const followingQuery = useQuery({
    queryKey: ["live-invite-following", userId],
    queryFn: async () => {
      const { data } = await supabase
        .from("whisper_follows")
        .select("followee_id, followee_username")
        .eq("follower_id", userId)
        .limit(100);
      return ((data as { followee_id: string; followee_username: string }[] | null) ?? []);
    },
  });

  const followeeIds = (followingQuery.data ?? []).map((f) => f.followee_id);
  const profilesQuery = useQuery({
    queryKey: ["live-invite-profiles", followeeIds],
    queryFn: () => fetchProfilesByIds(followeeIds),
    enabled: followeeIds.length > 0,
  });
  const inviteProfiles = profilesQuery.data ?? {};

  const toggle = (uid: string): void => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(uid)) next.delete(uid);
      else if (next.size < slotsLeft) next.add(uid);
      return next;
    });
  };

  const sendInvites = async (): Promise<void> => {
    if (selected.size === 0) return;
    setSending(true);
    try {
      for (const invitee of selected) {
        await supabase.from("whisper_live_invites").upsert(
          { room_id: roomId, inviter_id: userId, invitee_id: invitee, status: "pending" },
          { onConflict: "room_id,invitee_id" }
        );
      }
      toast.success(`Invited ${selected.size} ${selected.size === 1 ? "person" : "people"} — they join the moment they open the live`);
      onClose();
    } catch {
      toast.error("Could not send invites");
    } finally {
      setSending(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/60 p-0 sm:items-center sm:p-4" onClick={onClose}>
      <div
        className="flex max-h-[80dvh] w-full max-w-md flex-col overflow-hidden rounded-t-[24px] border border-border/60 bg-background sm:rounded-[24px]"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-border/40 px-4 py-3">
          <div>
            <p className="text-[15px] font-black">Go live together</p>
            <p className="text-[11px] text-muted-foreground">
              Up to {MAX_BROADCASTERS} on camera · {slotsLeft} slot{slotsLeft === 1 ? "" : "s"} left
            </p>
          </div>
          <button onClick={onClose} className="flex h-8 w-8 items-center justify-center rounded-full bg-secondary" aria-label="Close">
            <X className="h-4 w-4" />
          </button>
        </div>
        <div className="flex-1 overflow-y-auto px-2 py-2">
          {(followingQuery.data ?? []).length === 0 ? (
            <p className="px-4 py-10 text-center text-[13px] text-muted-foreground">
              Follow people to invite them to your live.
            </p>
          ) : (
            (followingQuery.data ?? []).map((f) => {
              const p = inviteProfiles[f.followee_id];
              const locked = alreadyIn.has(f.followee_id);
              const isSelected = selected.has(f.followee_id);
              return (
                <button
                  key={f.followee_id}
                  onClick={() => !locked && toggle(f.followee_id)}
                  disabled={locked}
                  className={cn(
                    "flex w-full items-center gap-3 rounded-2xl px-3 py-2.5 text-left transition-colors",
                    locked ? "opacity-50" : "hover:bg-secondary/60"
                  )}
                >
                  <Avatar url={p?.profile_image_url ?? null} name={p?.username ?? f.followee_username} size={40} />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-[13px] font-bold">{p?.username ?? f.followee_username}</p>
                    {p?.display_name && <p className="truncate text-[11px] text-muted-foreground">{p.display_name}</p>}
                  </div>
                  {locked ? (
                    <span className="rounded-full bg-secondary px-2.5 py-1 text-[10px] font-bold text-muted-foreground">In live</span>
                  ) : (
                    <span
                      className={cn(
                        "flex h-6 w-6 items-center justify-center rounded-full border-2 transition-all",
                        isSelected ? "border-rose-500 bg-rose-500 text-white" : "border-border"
                      )}
                    >
                      {isSelected && <Check className="h-3.5 w-3.5" />}
                    </span>
                  )}
                </button>
              );
            })
          )}
        </div>
        <div className="border-t border-border/40 p-3">
          <button
            onClick={() => void sendInvites()}
            disabled={selected.size === 0 || sending}
            className="w-full rounded-full bg-gradient-to-r from-rose-500 to-orange-500 py-3 text-[14px] font-bold text-white transition-transform active:scale-[0.98] disabled:opacity-40"
          >
            {sending ? "Inviting…" : selected.size === 0 ? "Select people to invite" : `Invite ${selected.size} to go live`}
          </button>
        </div>
      </div>
    </div>
  );
}

function timeAgoShort(iso: string): string {
  if (!iso) return "";
  const diff = Date.now() - new Date(iso).getTime();
  if (diff < 60_000) return "now";
  if (diff < 3_600_000) return `${Math.floor(diff / 60_000)}m`;
  if (diff < 86_400_000) return `${Math.floor(diff / 3_600_000)}h`;
  return `${Math.floor(diff / 86_400_000)}d`;
}

/**
 * Renders a chat message body — converts any `::whisper-...::` structured
 * embed into a human-readable summary so raw JSON never leaks into the
 * live chat overlay. Mirrors the iOS `chatBody(_:)` function.
 */
function renderChatBody(body: string): string {
  if (body.startsWith("::whisper-workout-v1::")) return "📋 shared a training plan";
  if (body.startsWith("::whisper-recipe-v1::")) return "🥘 shared a recipe";
  if (body.startsWith("::whisper-grocery-v1::")) return "🛒 shared a grocery list";
  if (body.startsWith("::whisper-checkin-v1::")) return "✅ checked in";
  if (body.startsWith("::whisper-chart-v1::")) return "📈 shared a chart";
  if (body.startsWith("::whisper-calendar-v1::")) return "📅 shared a calendar event";
  if (body.startsWith("::whisper-program-v1::")) return "📋 shared a training program";
  if (body.startsWith("::whisper-coach-macros-v1::")) return "🔥 shared nutrition goals";
  if (body.startsWith("::whisper-coach-diet-plan-v1::")) return "🍽️ shared a diet plan";
  if (body.startsWith("::whisper-coach-targets-v1::")) return "🎯 shared daily targets";
  if (body.startsWith("::whisper-coach-proposal-v1::")) return "📋 new coach suggestion";
  if (body.startsWith("::whisper-healthshare-v1::")) return "❤️ shared health stats";
  if (body.startsWith("::whisper-map-v1::")) return "🗺️ shared a map";
  if (body.startsWith("::whisper-sharedpost-v1::")) return "📎 shared a post";
  if (body.startsWith("::whisper-factcheck-v1::")) return "🔍 fact check result";
  if (body.startsWith("::whisper-ember-answer-v1::")) return "✨ Jasper answered";
  if (body.startsWith("::whisper-profileshare-v1::")) return "👤 shared a profile";
  if (body.startsWith("::whisper-call-v1::")) return "📞 call";
  if (body.startsWith("::whisper-callsummary-v1::")) return "📞 call ended";
  if (body.startsWith("::whisper-macros-v1::")) return "🔥 shared macros";
  if (body.startsWith("::whisper-thought-reply-v1::")) return "💬 replied";
  if (body.startsWith("::whisper-workoutproposal-v1::")) return "🏋️ proposed a workout";
  if (body.startsWith("::whisper-postmeta-v1::")) return "📊 shared poll data";
  if (body.startsWith("::whisper-")) return "📎 shared an attachment";
  return body;
}

// ─── VideoTile with gradient avatar background ────────────────────────────────

function VideoTile({
  participant,
  profile,
  isLocal,
  remoteStream,
  isHost,
  isSpotlight,
  compact,
  fill,
  onDoubleTap,
}: {
  participant: LiveParticipantInfo;
  profile?: { username?: string; display_name?: string; profile_image_url?: string | null; is_coach?: boolean | null; is_recruiter?: boolean | null; is_athlete?: boolean | null; is_verified?: boolean | null };
  isLocal: boolean;
  remoteStream: MediaStream | null;
  isHost?: boolean;
  isSpotlight?: boolean;
  compact?: boolean;
  /** Fill the box the stage gives it (no intrinsic aspect) — the studio grammar. */
  fill?: boolean;
  onDoubleTap?: () => void;
}) {
  const ref = useRef<HTMLVideoElement | null>(null);
  const [tapCount, setTapCount] = useState(0);

  useEffect(() => {
    const stream = isLocal ? participant.remoteStream : remoteStream;
    if (!ref.current || !stream) return;
    ref.current.srcObject = stream;
    void ref.current.play().catch(() => undefined);
    return () => { if (ref.current) ref.current.srcObject = null; };
  }, [remoteStream, participant.remoteStream, isLocal]);

  const hasVideo = isLocal
    ? participant.hasVideo
    : remoteStream?.getVideoTracks().some((t) => t.enabled) ?? false;

  const gradientColors = useMemo(() => {
    const name = profile?.username ?? participant.name ?? "user";
    const hash = name.split("").reduce((acc, c) => acc + c.charCodeAt(0), 0);
    const hue1 = hash % 360;
    const hue2 = (hue1 + 40) % 360;
    return [`hsl(${hue1}, 65%, 50%)`, `hsl(${hue2}, 65%, 35%)`];
  }, [profile?.username, participant.name]);

  // Role ring color
  const ringColor = useMemo(() => {
    if (profile?.is_coach) return "#10b981";
    if (profile?.is_athlete) return "#3b82f6";
    if (profile?.is_recruiter) return "#f59e0b";
    if (profile?.is_verified) return "#a855f7";
    return null;
  }, [profile]);

  const handleTap = (): void => {
    const now = Date.now();
    if (now - tapCount < 300 && onDoubleTap) {
      onDoubleTap();
      setTapCount(0);
    } else {
      setTapCount(now);
    }
  };

  // Screen shares get 16:9 with object-contain so the full desktop is
  // visible; camera tiles keep 4:5 portrait with object-cover.
  const isScreenShare = participant.isScreenSharing;
  const aspectClass = fill
    ? "h-full min-h-0 w-full"
    : isSpotlight
      ? "aspect-[16/9]"
      : isScreenShare || compact
        ? "aspect-video"
        : "aspect-[4/5]";
  const avatarSize = isSpotlight || fill ? "h-20 w-20" : compact ? "h-8 w-8" : "h-14 w-14";

  return (
    <div
      className={cn(
        "relative overflow-hidden bg-black transition-all duration-300",
        fill ? "rounded-lg" : "rounded-2xl",
        aspectClass,
        isSpotlight && !fill && "ring-2 ring-white/40",
        ringColor && !isSpotlight && !fill && "ring-1",
      )}
      style={ringColor && !isSpotlight && !fill ? { boxShadow: `0 0 0 2px ${ringColor}40` } : undefined}
      onClick={handleTap}
    >
      {hasVideo ? (
        <video
          ref={ref}
          autoPlay
          playsInline
          muted={isLocal}
          className={cn(
            "h-full w-full",
            isScreenShare ? "object-contain" : "object-cover",
          )}
        />
      ) : (
        <div
          className="flex h-full w-full items-center justify-center"
          style={{
            background: `linear-gradient(135deg, ${gradientColors[0]}, ${gradientColors[1]})`,
          }}
        >
          {profile?.profile_image_url ? (
            <img
              src={profile.profile_image_url}
              alt=""
              className={cn("rounded-full object-cover ring-2 ring-white/30", avatarSize)}
            />
          ) : (
            <div className={cn("flex items-center justify-center rounded-full bg-white/20 font-bold text-white", avatarSize, compact ? "text-[10px]" : "text-[16px]")}>
              {(profile?.username ?? participant.name ?? "U")[0].toUpperCase()}
            </div>
          )}
        </div>
      )}
      {/* Name label */}
      <div className="absolute bottom-1.5 left-1.5 flex items-center gap-1 rounded-full bg-black/50 px-2 py-0.5 text-[10px] font-bold text-white backdrop-blur-sm">
        {participant.hasAudio && <span className="h-1.5 w-1.5 rounded-full bg-emerald-400" />}
        {profile?.display_name ?? profile?.username ?? participant.name}
        {isLocal && " (You)"}
        {isHost && " · Host"}
      </div>
      {/* Mic off indicator */}
      {!participant.micOn && (
        <div className="absolute right-1.5 top-1.5 rounded-full bg-black/50 p-1 text-white">
          <MicOff className="h-3 w-3" />
        </div>
      )}
      {/* Role ring indicator */}
      {ringColor && (
        <div className="absolute left-1.5 top-1.5 h-2 w-2 rounded-full" style={{ backgroundColor: ringColor }} />
      )}
      {/* Spotlight badge */}
      {isSpotlight && (
        <div className="absolute right-1.5 top-1.5 rounded-full bg-black/55 px-2 py-0.5 text-[9px] font-bold uppercase text-white backdrop-blur-sm">
          {isScreenShare ? "Screen" : "Spotlight"}
        </div>
      )}
      {/* Double-tap hint */}
      {!isSpotlight && !compact && !fill && onDoubleTap && (
        <div className="absolute bottom-1.5 right-1.5 rounded-full bg-black/30 px-1.5 py-0.5 text-[8px] font-semibold text-white/70">
          Double-tap to spotlight
        </div>
      )}
    </div>
  );
}

// ─── Linked Rings Overlay for verified users ─────────────────────────────────

function LinkedRingsOverlay({
  participants,
  profiles,
  spotlightPeerId,
}: {
  participants: LiveParticipantInfo[];
  profiles: Record<string, { is_coach?: boolean | null; is_recruiter?: boolean | null; is_athlete?: boolean | null; is_verified?: boolean | null }>;
  spotlightPeerId: string | null;
}) {
  // Only show when 2+ verified users are speakers
  const verifiedParticipants = participants.filter((p) => {
    const prof = profiles[p.userId];
    return prof && (prof.is_coach || prof.is_recruiter || prof.is_athlete || prof.is_verified);
  });
  if (verifiedParticipants.length < 2) return null;

  const roleColor = (userId: string): string => {
    const prof = profiles[userId];
    if (prof?.is_coach) return "#10b981";
    if (prof?.is_athlete) return "#3b82f6";
    if (prof?.is_recruiter) return "#f59e0b";
    if (prof?.is_verified) return "#a855f7";
    return "#666";
  };

  // Build a chain of arcs connecting verified users
  return (
    <svg
      className="pointer-events-none absolute inset-0 z-10 h-full w-full"
      preserveAspectRatio="none"
    >
      <defs>
        <linearGradient id="ringFlow" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stopColor="#10b981" stopOpacity="0.6">
            <animate attributeName="stop-color" values="#10b981;#3b82f6;#a855f7;#f59e0b;#10b981" dur="4s" repeatCount="indefinite" />
          </stop>
          <stop offset="100%" stopColor="#a855f7" stopOpacity="0.6">
            <animate attributeName="stop-color" values="#a855f7;#f59e0b;#10b981;#3b82f6;#a855f7" dur="4s" repeatCount="indefinite" />
          </stop>
        </linearGradient>
      </defs>
      {verifiedParticipants.map((p, i) => {
        const next = verifiedParticipants[(i + 1) % verifiedParticipants.length];
        const color = roleColor(p.userId);
        return (
          <line
            key={`${p.peerId}-${next.peerId}`}
            x1={`${(i + 0.5) * (100 / verifiedParticipants.length)}%`}
            y1="50%"
            x2={`${((i + 1) % verifiedParticipants.length + 0.5) * (100 / verifiedParticipants.length)}%`}
            y2="50%"
            stroke="url(#ringFlow)"
            strokeWidth="2"
            strokeDasharray="4 4"
            opacity="0.5"
          >
            <animate
              attributeName="stroke-dashoffset"
              from="0"
              to="-8"
              dur="1s"
              repeatCount="indefinite"
            />
          </line>
        );
      })}
      {/* Pulsing circles at each verified user position */}
      {verifiedParticipants.map((p, i) => {
        const color = roleColor(p.userId);
        const x = `${(i + 0.5) * (100 / verifiedParticipants.length)}%`;
        return (
          <circle key={`dot-${p.peerId}`} cx={x} cy="50%" r="3" fill={color} opacity="0.7">
            <animate
              attributeName="r"
              values="3;5;3"
              dur="2s"
              repeatCount="indefinite"
            />
          </circle>
        );
      })}
    </svg>
  );
}

// ─── Poll card rendered inline in chat ───────────────────────────────────────

function PollCard({
  poll,
  voteCounts,
  myVote,
  canClose,
  onVote,
  onClose,
}: {
  poll: LivePoll;
  voteCounts: number[];
  myVote: number | undefined;
  canClose: boolean;
  onVote: (optionIndex: number) => void;
  onClose: () => void;
}) {
  // Normalize to options length — sparse/short arrays used to make
  // Math.max return NaN so the winner highlight never rendered.
  const counts = poll.options.map((_, i) => voteCounts?.[i] ?? 0);
  const totalVotes = counts.reduce((sum, c) => sum + c, 0);
  const isClosed = !!poll.closed_at;
  const winningIndex = totalVotes > 0 ? counts.indexOf(Math.max(...counts)) : -1;

  return (
    <div className="my-1.5 rounded-2xl border border-border/60 bg-card p-3 animate-rise">
      <div className="mb-2 flex items-start justify-between">
        <div className="min-w-0 flex-1">
          <p className="text-[13px] font-bold">{poll.question}</p>
          <p className="mt-0.5 text-[10px] text-muted-foreground">
            Poll by @{poll.creator_username} · {totalVotes} {totalVotes === 1 ? "vote" : "votes"}
          </p>
        </div>
        {canClose && !isClosed && (
          <button
            onClick={onClose}
            className="shrink-0 rounded-full bg-secondary px-2 py-0.5 text-[10px] font-bold transition-colors hover:bg-secondary/80"
          >
            Close
          </button>
        )}
        {isClosed && (
          <span className="shrink-0 rounded-full bg-muted px-2 py-0.5 text-[10px] font-bold text-muted-foreground">
            Closed
          </span>
        )}
      </div>
      <div className="space-y-1.5">
        {poll.options.map((option, i) => {
          const votes = voteCounts[i] ?? 0;
          const pct = totalVotes > 0 ? Math.round((votes / totalVotes) * 100) : 0;
          const isSelected = myVote === i;
          const isWinner = isClosed && i === winningIndex && totalVotes > 0;
          return (
            <button
              key={i}
              onClick={() => !isClosed && onVote(i)}
              disabled={isClosed}
              className={cn(
                "relative w-full overflow-hidden rounded-xl border px-3 py-2 text-left text-[12px] font-semibold transition-all",
                isSelected ? "border-emerald-500/40" : "border-border",
                isWinner && "border-emerald-500 bg-emerald-500/5",
                !isClosed && "active:scale-[0.98]",
              )}
            >
              {/* Fill bar */}
              <div
                className={cn(
                  "absolute inset-y-0 left-0 transition-all duration-500 ease-out",
                  isSelected ? "bg-emerald-500/15" : "bg-secondary/50",
                )}
                style={{ width: `${pct}%` }}
              />
              <div className="relative flex items-center justify-between">
                <span className="flex items-center gap-1.5">
                  {isSelected && <Check className="h-3 w-3 text-emerald-500" />}
                  {isWinner && !isSelected && <Check className="h-3 w-3 text-emerald-500" />}
                  {option}
                </span>
                <span className="text-muted-foreground">{pct}%</span>
              </div>
            </button>
          );
        })}
      </div>
    </div>
  );
}

// ─── Speaker request modal ────────────────────────────────────────────────────

function SpeakerRequestModal({
  roomId,
  userId,
  onClose,
  onSubmitted,
}: {
  roomId: string;
  userId: string;
  onClose: () => void;
  onSubmitted: () => void;
}) {
  const [role, setRole] = useState<SpeakerRole>("general");
  const [answers, setAnswers] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const meta = ROLE_QUESTIONS[role];

  const submit = async (): Promise<void> => {
    const required = meta.fields.filter((f) => f.required).every((f) => answers[f.id]?.trim());
    if (!required) { toast.error("Please fill all required fields"); return; }
    setBusy(true);
    try {
      await createSpeakerRequest({ roomId, userId, desiredRole: role, answers });
      onSubmitted();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Could not send request");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/60 backdrop-blur-sm animate-page-in" onClick={onClose}>
      <div className="max-h-[85vh] w-full max-w-lg overflow-y-auto rounded-t-[28px] border border-border bg-background p-5 animate-rise" onClick={(e) => e.stopPropagation()}>
        <div className="mx-auto mb-4 h-1 w-10 rounded-full bg-border" />
        <div className="mb-4 flex items-center justify-between">
          <h2 className="text-lg font-bold">Request to speak</h2>
          <button onClick={onClose} className="rounded-full bg-secondary p-2 transition-transform active:scale-90">
            <X className="h-5 w-5" />
          </button>
        </div>
        <p className="mb-3 text-sm text-muted-foreground">Tell the host a bit about yourself.</p>
        <div className="mb-4 grid grid-cols-2 gap-2">
          {(Object.keys(ROLE_QUESTIONS) as SpeakerRole[]).map((r) => (
            <button
              key={r}
              onClick={() => { setRole(r); setAnswers({}); }}
              className={cn("rounded-xl border px-3 py-2 text-sm font-semibold transition-all tap-scale", role === r ? "border-foreground bg-foreground text-background" : "border-border bg-card")}
            >
              {ROLE_QUESTIONS[r].label}
            </button>
          ))}
        </div>
        <div className="space-y-3">
          {meta.fields.map((f) => (
            <div key={f.id}>
              <label className="mb-1.5 block text-xs font-semibold text-muted-foreground">
                {f.label}{f.required && <span className="ml-1 text-red-500">*</span>}
              </label>
              {f.type === "textarea" ? (
                <textarea
                  value={answers[f.id] ?? ""}
                  onChange={(e) => setAnswers((a) => ({ ...a, [f.id]: e.target.value }))}
                  rows={3}
                  className="w-full resize-none rounded-2xl border border-border bg-card px-4 py-3 text-sm outline-none focus:border-foreground/40"
                  placeholder={f.placeholder}
                />
              ) : (
                <input
                  type={f.type === "number" ? "number" : "text"}
                  value={answers[f.id] ?? ""}
                  onChange={(e) => setAnswers((a) => ({ ...a, [f.id]: e.target.value }))}
                  className="w-full rounded-2xl border border-border bg-card px-4 py-3 text-sm outline-none focus:border-foreground/40"
                  placeholder={f.placeholder}
                />
              )}
            </div>
          ))}
        </div>
        <button
          onClick={submit}
          disabled={busy}
          className="mt-5 flex w-full items-center justify-center gap-2 rounded-2xl bg-emerald-500 py-3.5 text-sm font-bold text-white transition-all active:scale-[0.98] disabled:opacity-50"
        >
          {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Check className="h-4 w-4" />}
          Send request
        </button>
      </div>
    </div>
  );
}

// ─── Speaker requests panel ───────────────────────────────────────────────────

function SpeakerRequestsPanel({
  requests,
  profiles,
  onClose,
  onAccept,
  onReject,
  isPending,
}: {
  requests: SpeakerRequest[];
  profiles: Record<string, { username?: string; display_name?: string; profile_image_url?: string | null }>;
  onClose: () => void;
  onAccept: (r: SpeakerRequest) => void;
  onReject: (r: SpeakerRequest) => void;
  isPending: boolean;
}) {
  const pending = requests.filter((r) => r.status === "pending");
  const reviewed = requests.filter((r) => r.status !== "pending");

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/60 backdrop-blur-sm animate-page-in" onClick={onClose}>
      <div className="max-h-[85vh] w-full max-w-lg overflow-y-auto rounded-t-[28px] border border-border bg-background p-5 animate-rise" onClick={(e) => e.stopPropagation()}>
        <div className="mx-auto mb-4 h-1 w-10 rounded-full bg-border" />
        <div className="mb-4 flex items-center justify-between">
          <h2 className="text-lg font-bold">Speaker requests</h2>
          <button onClick={onClose} className="rounded-full bg-secondary p-2 transition-transform active:scale-90">
            <X className="h-5 w-5" />
          </button>
        </div>
        {pending.length === 0 && reviewed.length === 0 && (
          <div className="rounded-2xl border border-dashed border-border bg-card p-6 text-center">
            <p className="text-sm font-bold">No requests yet</p>
            <p className="text-xs text-muted-foreground">Listeners can request to speak from the audience.</p>
          </div>
        )}
        {pending.length > 0 && (
          <div className="mb-4 space-y-2">
            <p className="text-xs font-bold uppercase tracking-wide text-muted-foreground">Pending ({pending.length})</p>
            {pending.map((r) => (
              <RequestCard key={r.id} request={r} profile={profiles[r.user_id]} onAccept={() => onAccept(r)} onReject={() => onReject(r)} isPending={isPending} />
            ))}
          </div>
        )}
        {reviewed.length > 0 && (
          <div className="space-y-2">
            <p className="text-xs font-bold uppercase tracking-wide text-muted-foreground">Reviewed</p>
            {reviewed.map((r) => (
              <div key={r.id} className="flex items-center gap-3 rounded-2xl border border-border bg-card p-3 opacity-70">
                <Avatar url={profiles[r.user_id]?.profile_image_url ?? null} name={profiles[r.user_id]?.username ?? "user"} size={36} />
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-bold">{profiles[r.user_id]?.display_name ?? profiles[r.user_id]?.username ?? "User"}</p>
                  <p className="text-xs text-muted-foreground">{ROLE_QUESTIONS[r.desired_role].label} · {r.status}</p>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function RequestCard({
  request,
  profile,
  onAccept,
  onReject,
  isPending,
}: {
  request: SpeakerRequest;
  profile?: { username?: string; display_name?: string; profile_image_url?: string | null };
  onAccept: () => void;
  onReject: () => void;
  isPending: boolean;
}) {
  const [expanded, setExpanded] = useState(false);
  return (
    <div className="rounded-2xl border border-border bg-card p-3">
      <div className="flex items-center gap-3">
        <Avatar url={profile?.profile_image_url ?? null} name={profile?.username ?? "user"} size={40} />
        <div className="min-w-0 flex-1">
          <p className="text-sm font-bold">{profile?.display_name ?? profile?.username ?? "User"}</p>
          <p className="text-xs text-muted-foreground">Wants to speak as {ROLE_QUESTIONS[request.desired_role].label}</p>
        </div>
        <button onClick={() => setExpanded((e) => !e)} className="rounded-full bg-secondary p-1.5 transition-transform active:scale-90">
          <ChevronRight className={cn("h-4 w-4 transition-transform", expanded && "rotate-90")} />
        </button>
      </div>
      {expanded && (
        <div className="mt-3 space-y-2 border-t border-border pt-2">
          {Object.entries(request.answers).map(([key, value]) => (
            <div key={key}>
              <p className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">{key}</p>
              <p className="text-sm">{value}</p>
            </div>
          ))}
        </div>
      )}
      <div className="mt-3 flex gap-2">
        <button onClick={onAccept} disabled={isPending} className="flex flex-1 items-center justify-center gap-1 rounded-xl bg-emerald-500 py-2 text-xs font-bold text-white transition-transform active:scale-95 disabled:opacity-50">
          <Check className="h-3.5 w-3.5" /> Accept
        </button>
        <button onClick={onReject} disabled={isPending} className="flex flex-1 items-center justify-center gap-1 rounded-xl bg-red-500 py-2 text-xs font-bold text-white transition-transform active:scale-95 disabled:opacity-50">
          <X className="h-3.5 w-3.5" /> Decline
        </button>
      </div>
    </div>
  );
}

// ─── Poll creator modal ──────────────────────────────────────────────────────

function PollCreatorModal({
  roomId,
  userId,
  username,
  onClose,
  onCreated,
}: {
  roomId: string;
  userId: string;
  username: string;
  onClose: () => void;
  onCreated: () => void;
}) {
  const [question, setQuestion] = useState("");
  const [options, setOptions] = useState<string[]>(["", ""]);
  const [busy, setBusy] = useState(false);

  const submit = async (): Promise<void> => {
    const cleanOptions = options.map((o) => o.trim()).filter(Boolean);
    if (!question.trim() || cleanOptions.length < 2) {
      toast.error("Add a question and at least 2 options");
      return;
    }
    setBusy(true);
    try {
      const pollId = await createPoll({
        roomId,
        question,
        options: cleanOptions,
        creatorId: userId,
        creatorUsername: username,
      });
      if (pollId) {
        onCreated();
      } else {
        toast.error("Could not create poll");
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Could not create poll");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/60 backdrop-blur-sm animate-page-in" onClick={onClose}>
      <div className="max-h-[85vh] w-full max-w-lg overflow-y-auto rounded-t-[28px] border border-border bg-background p-5 animate-rise" onClick={(e) => e.stopPropagation()}>
        <div className="mx-auto mb-4 h-1 w-10 rounded-full bg-border" />
        <div className="mb-4 flex items-center justify-between">
          <h2 className="flex items-center gap-2 text-lg font-bold">
            <BarChart3 className="h-5 w-5 text-emerald-500" />
            Create Poll
          </h2>
          <button onClick={onClose} className="rounded-full bg-secondary p-2 transition-transform active:scale-90">
            <X className="h-5 w-5" />
          </button>
        </div>
        <div className="space-y-4">
          <div>
            <label className="mb-1.5 block text-xs font-semibold text-muted-foreground">Question</label>
            <input
              value={question}
              onChange={(e) => setQuestion(e.target.value)}
              placeholder="e.g. What should we train today?"
              maxLength={200}
              className="w-full rounded-2xl border border-border bg-card px-4 py-3 text-sm outline-none focus:border-emerald-500/40"
            />
          </div>
          <div className="space-y-2">
            <label className="block text-xs font-semibold text-muted-foreground">Options ({options.length}/4)</label>
            {options.map((opt, i) => (
              <div key={i} className="flex items-center gap-2">
                <input
                  value={opt}
                  onChange={(e) => setOptions((prev) => prev.map((o, idx) => idx === i ? e.target.value : o))}
                  placeholder={`Option ${i + 1}`}
                  maxLength={100}
                  className="flex-1 rounded-xl border border-border bg-card px-3 py-2.5 text-sm outline-none focus:border-emerald-500/40"
                />
                {options.length > 2 && (
                  <button
                    onClick={() => setOptions((prev) => prev.filter((_, idx) => idx !== i))}
                    className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-secondary text-muted-foreground transition-transform active:scale-90"
                    aria-label="Remove option"
                  >
                    <X className="h-4 w-4" />
                  </button>
                )}
              </div>
            ))}
            {options.length < 4 && (
              <button
                onClick={() => setOptions((prev) => [...prev, ""])}
                className="flex items-center gap-1.5 text-sm font-semibold text-emerald-500 transition-colors hover:text-emerald-600"
              >
                <span className="text-lg leading-none">+</span> Add option
              </button>
            )}
          </div>
          <button
            onClick={submit}
            disabled={busy}
            className="flex w-full items-center justify-center gap-2 rounded-2xl bg-emerald-500 py-3.5 text-sm font-bold text-white transition-all active:scale-[0.98] disabled:opacity-50"
          >
            {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <BarChart3 className="h-4 w-4" />}
            Create poll
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── Coach tools sheet ───────────────────────────────────────────────────────

function CoachToolsSheet({
  roomId,
  userId,
  username,
  onClose,
}: {
  roomId: string;
  userId: string;
  username: string;
  onClose: () => void;
}) {
  const [planName, setPlanName] = useState("");
  const [focus, setFocus] = useState("");
  const [exercises, setExercises] = useState<{ name: string; sets: string; reps: string }[]>([{ name: "", sets: "3", reps: "10" }]);
  const [sending, setSending] = useState(false);

  const sendPlan = async (): Promise<void> => {
    const cleanExercises = exercises.filter((e) => e.name.trim());
    if (!planName.trim() || cleanExercises.length === 0) {
      toast.error("Add a plan name and at least one exercise");
      return;
    }
    setSending(true);
    try {
      // Encode as a workout embed so it saves to Jasper the same way feed workouts do
      const payload = {
        id: crypto.randomUUID(),
        displayName: planName.trim(),
        focus: focus.trim() || "General",
        durationSeconds: cleanExercises.length * 180,
        calories: cleanExercises.length * 50,
        exerciseNames: cleanExercises.map((e) => e.name.trim()),
        totalSets: cleanExercises.reduce((sum, e) => sum + (parseInt(e.sets) || 1), 0),
        date: Date.now(),
      };
      const embed = `::whisper-workout-v1::${JSON.stringify(payload)}`;
      await sendChatMessage({
        roomId,
        userId,
        username,
        body: embed,
        isHost: false,
      });
      toast.success("Training plan sent to room");
      onClose();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Could not send plan");
    } finally {
      setSending(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/60 backdrop-blur-sm animate-page-in" onClick={onClose}>
      <div className="max-h-[85vh] w-full max-w-lg overflow-y-auto rounded-t-[28px] border border-border bg-background p-5 animate-rise" onClick={(e) => e.stopPropagation()}>
        <div className="mx-auto mb-4 h-1 w-10 rounded-full bg-border" />
        <div className="mb-4 flex items-center justify-between">
          <h2 className="flex items-center gap-2 text-lg font-bold">
            <Dumbbell className="h-5 w-5 text-emerald-500" />
            Training Plan
          </h2>
          <button onClick={onClose} className="rounded-full bg-secondary p-2 transition-transform active:scale-90">
            <X className="h-5 w-5" />
          </button>
        </div>
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="mb-1.5 block text-xs font-semibold text-muted-foreground">Plan name</label>
              <input
                value={planName}
                onChange={(e) => setPlanName(e.target.value)}
                placeholder="e.g. Push Day"
                maxLength={60}
                className="w-full rounded-xl border border-border bg-card px-3 py-2.5 text-sm outline-none focus:border-emerald-500/40"
              />
            </div>
            <div>
              <label className="mb-1.5 block text-xs font-semibold text-muted-foreground">Focus</label>
              <input
                value={focus}
                onChange={(e) => setFocus(e.target.value)}
                placeholder="e.g. Strength"
                maxLength={40}
                className="w-full rounded-xl border border-border bg-card px-3 py-2.5 text-sm outline-none focus:border-emerald-500/40"
              />
            </div>
          </div>
          <div className="space-y-2">
            <label className="block text-xs font-semibold text-muted-foreground">Exercises</label>
            {exercises.map((ex, i) => (
              <div key={i} className="flex items-center gap-2">
                <input
                  value={ex.name}
                  onChange={(e) => setExercises((prev) => prev.map((x, idx) => idx === i ? { ...x, name: e.target.value } : x))}
                  placeholder="Exercise name"
                  className="min-w-0 flex-1 rounded-xl border border-border bg-card px-3 py-2 text-sm outline-none focus:border-emerald-500/40"
                />
                <input
                  value={ex.sets}
                  onChange={(e) => setExercises((prev) => prev.map((x, idx) => idx === i ? { ...x, sets: e.target.value } : x))}
                  placeholder="Sets"
                  type="number"
                  className="w-16 rounded-xl border border-border bg-card px-2 py-2 text-center text-sm outline-none focus:border-emerald-500/40"
                />
                <input
                  value={ex.reps}
                  onChange={(e) => setExercises((prev) => prev.map((x, idx) => idx === i ? { ...x, reps: e.target.value } : x))}
                  placeholder="Reps"
                  className="w-16 rounded-xl border border-border bg-card px-2 py-2 text-center text-sm outline-none focus:border-emerald-500/40"
                />
                {exercises.length > 1 && (
                  <button
                    onClick={() => setExercises((prev) => prev.filter((_, idx) => idx !== i))}
                    className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-secondary text-muted-foreground transition-transform active:scale-90"
                    aria-label="Remove exercise"
                  >
                    <X className="h-4 w-4" />
                  </button>
                )}
              </div>
            ))}
            <button
              onClick={() => setExercises((prev) => [...prev, { name: "", sets: "3", reps: "10" }])}
              className="flex items-center gap-1.5 text-sm font-semibold text-emerald-500 transition-colors hover:text-emerald-600"
            >
              <span className="text-lg leading-none">+</span> Add exercise
            </button>
          </div>
          <button
            onClick={sendPlan}
            disabled={sending}
            className="flex w-full items-center justify-center gap-2 rounded-2xl bg-emerald-500 py-3.5 text-sm font-bold text-white transition-all active:scale-[0.98] disabled:opacity-50"
          >
            {sending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
            Send to Room
          </button>
          <p className="text-center text-xs text-muted-foreground">
            Viewers can save this plan to their Jasper with one tap.
          </p>
        </div>
      </div>
    </div>
  );
}

// ─── Creator tools sheet ─────────────────────────────────────────────────────

function CreatorToolsSheet({
  onClose,
  onReaction,
}: {
  onClose: () => void;
  onReaction: (emoji: string) => void;
}) {
  const REACTIONS = [
    { emoji: "❤️", label: "Heart" },
    { emoji: "🔥", label: "Fire" },
    { emoji: "👏", label: "Clap" },
    { emoji: "🤯", label: "Mind blown" },
    { emoji: "💯", label: "100" },
    { emoji: "🎉", label: "Party" },
  ];

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/60 backdrop-blur-sm animate-page-in" onClick={onClose}>
      <div className="w-full max-w-lg rounded-t-[28px] border border-border bg-background p-5 animate-rise" onClick={(e) => e.stopPropagation()}>
        <div className="mx-auto mb-4 h-1 w-10 rounded-full bg-border" />
        <div className="mb-4 flex items-center justify-between">
          <h2 className="flex items-center gap-2 text-lg font-bold">
            <Sparkles className="h-5 w-5 text-purple-500" />
            Creator Tools
          </h2>
          <button onClick={onClose} className="rounded-full bg-secondary p-2 transition-transform active:scale-90">
            <X className="h-5 w-5" />
          </button>
        </div>
        <div className="space-y-4">
          {/* Floating reactions */}
          <div>
            <p className="mb-2 text-xs font-semibold text-muted-foreground">Send floating reaction</p>
            <div className="grid grid-cols-6 gap-2">
              {REACTIONS.map((r) => (
                <button
                  key={r.emoji}
                  onClick={() => { onReaction(r.emoji); }}
                  className="flex aspect-square items-center justify-center rounded-2xl border border-border bg-card text-2xl transition-all active:scale-90 hover:border-purple-500/30 hover:bg-purple-500/5"
                  aria-label={r.label}
                >
                  {r.emoji}
                </button>
              ))}
            </div>
          </div>
          {/* Screen share — live, driven from the control bar */}
          <div className="rounded-2xl border border-border bg-card p-4 text-center">
            <p className="text-sm font-bold">Screen Share</p>
            <p className="mt-1 text-xs text-muted-foreground">Live now — tap the screen icon in the control bar to share your screen as a stage tile.</p>
          </div>
          {/* Q&A mode placeholder */}
          <div className="rounded-2xl border border-dashed border-border bg-card p-4 text-center">
            <p className="text-sm font-bold">Q&A Mode</p>
            <p className="mt-1 text-xs text-muted-foreground">Coming soon — pin a question and highlight viewer answers.</p>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─── Recruiter tools sheet ───────────────────────────────────────────────────

function RecruiterToolsSheet({
  roomId,
  participants,
  profiles,
  listenerCount,
  onClose,
}: {
  roomId: string;
  participants: LiveParticipantInfo[];
  profiles: Record<string, { username?: string; display_name?: string; profile_image_url?: string | null; is_coach?: boolean | null; is_athlete?: boolean | null; is_recruiter?: boolean | null; is_verified?: boolean | null; bio?: string | null }>;
  listenerCount: number;
  onClose: () => void;
}) {
  const speakerParticipants = participants.filter((p) => p.isSpeaker);

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/60 backdrop-blur-sm animate-page-in" onClick={onClose}>
      <div className="max-h-[85vh] w-full max-w-lg overflow-y-auto rounded-t-[28px] border border-border bg-background p-5 animate-rise" onClick={(e) => e.stopPropagation()}>
        <div className="mx-auto mb-4 h-1 w-10 rounded-full bg-border" />
        <div className="mb-4 flex items-center justify-between">
          <h2 className="flex items-center gap-2 text-lg font-bold">
            <Target className="h-5 w-5 text-amber-500" />
            Recruiting Tools
          </h2>
          <button onClick={onClose} className="rounded-full bg-secondary p-2 transition-transform active:scale-90">
            <X className="h-5 w-5" />
          </button>
        </div>
        <div className="space-y-4">
          {/* Live stats */}
          <div className="grid grid-cols-3 gap-2">
            <div className="rounded-2xl border border-border bg-card p-3 text-center">
              <p className="text-2xl font-black text-amber-500">{listenerCount}</p>
              <p className="text-[10px] font-bold uppercase text-muted-foreground">Listeners</p>
            </div>
            <div className="rounded-2xl border border-border bg-card p-3 text-center">
              <p className="text-2xl font-black text-amber-500">{speakerParticipants.length}</p>
              <p className="text-[10px] font-bold uppercase text-muted-foreground">Speakers</p>
            </div>
            <div className="rounded-2xl border border-border bg-card p-3 text-center">
              <p className="text-2xl font-black text-amber-500">{participants.length}</p>
              <p className="text-[10px] font-bold uppercase text-muted-foreground">Total</p>
            </div>
          </div>
          {/* Talent spotlight */}
          <div>
            <p className="mb-2 flex items-center gap-1.5 text-xs font-bold uppercase tracking-wider text-muted-foreground">
              <Sparkles className="h-3.5 w-3.5" />
              Talent Spotlight
            </p>
            <div className="space-y-2">
              {speakerParticipants.slice(0, 5).map((p) => {
                const prof = profiles[p.userId];
                const roleColor = prof?.is_coach ? "#10b981" : prof?.is_athlete ? "#3b82f6" : prof?.is_verified ? "#a855f7" : "#666";
                return (
                  <div key={p.peerId} className="flex items-center gap-3 rounded-2xl border border-border bg-card p-3">
                    <div className="relative shrink-0">
                      <div className="rounded-full p-0.5" style={{ backgroundColor: roleColor }}>
                        <Avatar url={prof?.profile_image_url ?? null} name={prof?.username ?? p.name} size={36} />
                      </div>
                    </div>
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-bold">{prof?.display_name ?? prof?.username ?? p.name}</p>
                      {prof?.bio && <p className="line-clamp-1 text-xs text-muted-foreground">{prof.bio}</p>}
                    </div>
                    {p.micOn && (
                      <span className="flex h-2 w-2 rounded-full bg-emerald-500" />
                    )}
                  </div>
                );
              })}
              {speakerParticipants.length === 0 && (
                <p className="py-4 text-center text-xs text-muted-foreground">No speakers yet.</p>
              )}
            </div>
          </div>
          {/* Lead invites — pull listeners into a 1-on-1 interview */}
          <LeadInviteSection roomId={roomId} participants={participants} profiles={profiles} isHost={false} />
          {/* Evaluation notes */}
          <div className="rounded-2xl border border-dashed border-border bg-card p-4 text-center">
            <p className="text-sm font-bold">Evaluation Notes</p>
            <p className="mt-1 text-xs text-muted-foreground">Private rating sliders and notes per speaker — coming soon.</p>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─── Lead invite section (recruiter pulls listeners into 1-on-1) ───────────────

function LeadInviteSection({
  roomId,
  participants,
  profiles,
  isHost,
}: {
  roomId: string;
  participants: LiveParticipantInfo[];
  profiles: Record<string, { username?: string; display_name?: string; profile_image_url?: string | null; is_coach?: boolean | null; is_athlete?: boolean | null; is_verified?: boolean | null; bio?: string | null }>;
  isHost: boolean;
}) {
  const listeners = participants.filter((p) => !p.isSpeaker && p.userId !== "");
  const [selectedLead, setSelectedLead] = useState<string | null>(null);
  const [sending, setSending] = useState(false);

  const inviteLead = async (userId: string): Promise<void> => {
    setSending(true);
    try {
      // Send a speaker invite so the listener gets promoted to the stage
      // for a 1-on-1 interview within the live room. (This used to send
      // inviter_id: "" — an invalid uuid — and toast success anyway.)
      const { data: auth } = await supabase.auth.getUser();
      const inviterId = auth.user?.id;
      if (!inviterId) {
        toast.error("Sign in to send invites");
        return;
      }
      const { error } = await supabase.from("whisper_live_invites").upsert(
        { room_id: roomId, inviter_id: inviterId, invitee_id: userId, status: "pending" },
        { onConflict: "room_id,invitee_id" }
      );
      if (error) throw error;
      toast.success("Interview invite sent — they will join the stage");
      setSelectedLead(null);
    } catch {
      toast.error("Could not send invite");
    } finally {
      setSending(false);
    }
  };

  if (listeners.length === 0) {
    return (
      <div className="rounded-2xl border border-dashed border-border bg-card p-4 text-center">
        <p className="text-sm font-bold">No listeners yet</p>
        <p className="mt-1 text-xs text-muted-foreground">Listeners will appear here as they join.</p>
      </div>
    );
  }

  return (
    <div>
      <p className="mb-2 flex items-center gap-1.5 text-xs font-bold uppercase tracking-wider text-muted-foreground">
        <UserPlus className="h-3.5 w-3.5" />
        Invite to Interview ({listeners.length})
      </p>
      <div className="space-y-2">
        {listeners.slice(0, 10).map((p) => {
          const prof = profiles[p.userId];
          const isSelected = selectedLead === p.userId;
          return (
            <div key={p.peerId} className="flex items-center gap-3 rounded-2xl border border-border bg-card p-3">
              <Avatar url={prof?.profile_image_url ?? null} name={prof?.username ?? p.name} size={36} />
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-bold">{prof?.display_name ?? prof?.username ?? p.name}</p>
                {prof?.bio && <p className="line-clamp-1 text-xs text-muted-foreground">{prof.bio}</p>}
              </div>
              <button
                onClick={() => { setSelectedLead(p.userId); void inviteLead(p.userId); }}
                disabled={sending && isSelected}
                className="shrink-0 rounded-full bg-amber-500 px-3 py-1.5 text-[11px] font-bold text-white transition-transform active:scale-90 disabled:opacity-50"
              >
                {sending && isSelected ? "Sending…" : "Invite"}
              </button>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// ─── Workout embed parser + interactive card ─────────────────────────────────

interface WorkoutPayload {
  id: string;
  displayName: string;
  focus: string;
  durationSeconds: number;
  calories: number;
  exerciseNames: string[];
  totalSets: number;
  date: number;
}

function parseWorkoutEmbed(body: string): WorkoutPayload | null {
  const prefix = "::whisper-workout-v1::";
  if (!body.startsWith(prefix)) return null;
  try {
    const json = body.slice(prefix.length);
    const parsed = JSON.parse(json) as WorkoutPayload;
    if (!parsed.displayName || !parsed.exerciseNames) return null;
    return parsed;
  } catch {
    return null;
  }
}

function LiveWorkoutChatCard({ payload }: { payload: WorkoutPayload }) {
  const [saved, setSaved] = useState(false);
  const [expanded, setExpanded] = useState(false);

  return (
    <div
      className="mt-1 rounded-xl border border-emerald-500/40 bg-emerald-500/10 p-2.5 transition-all"
      onClick={() => setExpanded((e) => !e)}
    >
      <div className="flex items-center gap-2">
        <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-emerald-500 text-white">
          <Dumbbell className="h-3.5 w-3.5" />
        </div>
        <div className="min-w-0 flex-1">
          <p className="truncate text-[12px] font-bold text-emerald-500">{payload.displayName}</p>
          <p className="text-[10px] text-muted-foreground">{payload.focus}</p>
        </div>
      </div>
      {expanded && (
        <div className="mt-2 space-y-1 border-t border-emerald-500/20 pt-2">
          {payload.exerciseNames.slice(0, 8).map((name, i) => (
            <div key={i} className="flex items-center gap-1.5">
              <span className="h-1 w-1 rounded-full bg-emerald-500/60" />
              <span className="text-[11px] text-foreground/80">{name}</span>
            </div>
          ))}
          {payload.exerciseNames.length > 8 && (
            <p className="text-[10px] text-muted-foreground">+{payload.exerciseNames.length - 8} more</p>
          )}
        </div>
      )}
      <div className="mt-2 flex items-center justify-between">
        <span className="text-[9px] font-semibold text-muted-foreground">
          {payload.exerciseNames.length} exercises · {payload.totalSets} sets
        </span>
        <button
          onClick={(e) => {
            e.stopPropagation();
            setSaved(true);
            // Honest copy — the web can't import into workout history yet.
            toast.success("Noted — open Whisper on iPhone to train with this plan");
          }}
          className={cn(
            "flex items-center gap-1 rounded-lg px-2.5 py-1 text-[10px] font-bold transition-all active:scale-90",
            saved ? "bg-emerald-500 text-white" : "bg-emerald-500/15 text-emerald-500"
          )}
        >
          {saved ? <Check className="h-3 w-3" /> : <span className="text-sm leading-none">+</span>}
          {saved ? "Saved" : "Save"}
        </button>
      </div>
    </div>
  );
}
