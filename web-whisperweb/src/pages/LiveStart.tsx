import { useState, useMemo, useRef, useEffect } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useMutation, useQuery } from "@tanstack/react-query";
import {
  ArrowLeft,
  Radio,
  Sparkles,
  CalendarClock,
  UserPlus,
  Check,
  MonitorUp,
  MessageCircle,
  Gift,
  VideoOff,
  Loader2,
} from "lucide-react";
import { useAuth } from "@/hooks/useAuth";
import { supabase } from "@/lib/supabase";
import { toast } from "sonner";
import { Avatar } from "@/components/Avatar";
import { fetchProfilesByIds } from "@/lib/api";
import { WHISPER_BRAND_GRADIENT } from "@/lib/brand";
import { notifyFollowersLive } from "@/lib/liveModeration";
import { cn } from "@/lib/utils";

interface LiveRoomInput {
  name: string;
  description: string;
  topic: string;
  scheduledAt: string | null;
  inviteeIds: string[];
}

/** Max people on camera at once — Instagram-style group live cap. */
const MAX_BROADCASTERS = 4;

const TOPIC_PILLS = [
  { id: "Athletics", emoji: "🏃" },
  { id: "Coaching", emoji: "💪" },
  { id: "Creator Q&A", emoji: "✨" },
  { id: "Recruiting", emoji: "🎯" },
  { id: "Film", emoji: "🎬" },
  { id: "General", emoji: "💬" },
];

const ROLE_TEMPLATES: Record<string, { name: string; topic: string; description: string }> = {
  coach: {
    name: "Training Session Live",
    topic: "Coaching",
    description: "Join me for a live training session — exercises, form check, and Q&A. Bring your questions!",
  },
  recruiter: {
    name: "Recruiting Session",
    topic: "Recruiting",
    description: "Live recruiting session — athletes and coaches welcome. Let's find the next great talent.",
  },
  athlete: {
    name: "Athlete Q&A",
    topic: "Athletics",
    description: "Ask me anything about training, competition, and the athlete journey.",
  },
  creator: {
    name: "Creator Q&A",
    topic: "Creator Q&A",
    description: "Let's talk content, creativity, and building an audience. Ask me anything!",
  },
};

async function createRoom(input: LiveRoomInput, hostId: string): Promise<{ roomId: string; scheduled: boolean }> {
  const scheduled = !!input.scheduledAt;
  const payload: Record<string, unknown> = {
    name: input.name.trim(),
    description: input.description.trim() || null,
    topic: input.topic.trim() || null,
    host_id: hostId,
    is_live: !scheduled,
    listener_count: 0,
  };
  if (scheduled && input.scheduledAt) {
    payload.scheduled_at = new Date(input.scheduledAt).toISOString();
  }

  let { data: room, error: roomError } = await supabase
    .from("whisper_live_rooms")
    .insert(payload)
    .select("id")
    .single();

  // scheduled_at column may not be migrated yet — retry as an instant live.
  if (roomError && scheduled) {
    delete payload.scheduled_at;
    payload.is_live = true;
    const retry = await supabase
      .from("whisper_live_rooms")
      .insert(payload)
      .select("id")
      .single();
    room = retry.data;
    roomError = retry.error;
  }

  if (roomError || !room) {
    throw new Error(roomError?.message ?? "Failed to create room");
  }

  const { error: speakerError } = await supabase
    .from("whisper_live_room_speakers")
    .insert({
      room_id: room.id,
      user_id: hostId,
      is_host: true,
      is_cohost: false,
      can_video: true,
    });

  if (speakerError) {
    throw new Error(speakerError.message ?? "Failed to join as host");
  }

  // Group live invites — best-effort (table may not be migrated yet).
  for (const invitee of input.inviteeIds) {
    try {
      await supabase
        .from("whisper_live_invites")
        .upsert(
          { room_id: room.id, inviter_id: hostId, invitee_id: invitee, status: "pending" },
          { onConflict: "room_id,invitee_id" }
        );
    } catch {
      // Invites table not migrated yet — skip silently.
    }
  }

  return { roomId: room.id as string, scheduled };
}

export default function LiveStart() {
  const { user, profile } = useAuth();
  const navigate = useNavigate();
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [topic, setTopic] = useState("");
  const [selectedTemplate, setSelectedTemplate] = useState<string | null>(null);
  const [scheduleEnabled, setScheduleEnabled] = useState(false);
  const [scheduledAt, setScheduledAt] = useState<string>("");
  const [invitees, setInvitees] = useState<Set<string>>(new Set());
  const [showInvitePicker, setShowInvitePicker] = useState(false);

  // Following list for the co-host picker.
  const followingQuery = useQuery({
    queryKey: ["live-start-following", user?.id],
    queryFn: async () => {
      const { data } = await supabase
        .from("whisper_follows")
        .select("followee_id, followee_username")
        .eq("follower_id", user!.id)
        .limit(100);
      return ((data as { followee_id: string; followee_username: string }[] | null) ?? []);
    },
    enabled: !!user?.id,
  });
  const followeeIds = (followingQuery.data ?? []).map((f) => f.followee_id);
  const inviteProfilesQuery = useQuery({
    queryKey: ["live-start-profiles", followeeIds],
    queryFn: () => fetchProfilesByIds(followeeIds),
    enabled: followeeIds.length > 0,
  });
  const inviteProfiles = inviteProfilesQuery.data ?? {};

  const toggleInvitee = (uid: string): void => {
    setInvitees((prev) => {
      const next = new Set(prev);
      if (next.has(uid)) next.delete(uid);
      else if (next.size < MAX_BROADCASTERS - 1) next.add(uid);
      return next;
    });
  };

  /** Minimum schedulable time — 5 minutes from now, as a datetime-local value. */
  const minScheduleValue = useMemo(() => {
    const d = new Date(Date.now() + 5 * 60_000);
    d.setSeconds(0, 0);
    const pad = (n: number): string => String(n).padStart(2, "0");
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }, []);

  // Determine role for template suggestions
  const roleKey = useMemo(() => {
    if (profile?.is_coach) return "coach";
    if (profile?.is_recruiter) return "recruiter";
    if (profile?.is_athlete) return "athlete";
    if (profile?.is_verified) return "creator";
    return null;
  }, [profile]);

  const applyTemplate = (key: string): void => {
    const template = ROLE_TEMPLATES[key];
    if (!template) return;
    setSelectedTemplate(key);
    setName(template.name);
    setTopic(template.topic);
    setDescription(template.description);
  };

  const createMutation = useMutation({
    mutationFn: (input: LiveRoomInput) => {
      if (!user?.id) throw new Error("Sign in to go live");
      return createRoom(input, user.id);
    },
    onSuccess: ({ roomId, scheduled }, input) => {
      if (scheduled) {
        toast.success("Live scheduled — it shows with a countdown until it starts");
        navigate("/live");
      } else {
        // Tell followers — best-effort fanout that never blocks going live.
        if (user?.id) {
          void notifyFollowersLive({
            hostId: user.id,
            hostUsername: profile?.username ?? "someone",
            roomId,
            roomName: input.name.trim() || "Live on Whisper",
          });
        }
        toast.success("You're live");
        navigate(`/live/${roomId}`);
      }
    },
    onError: (err) => {
      toast.error(err instanceof Error ? err.message : "Could not start the stream");
    },
  });

  const scheduleValid = !scheduleEnabled || (scheduledAt.length > 0 && new Date(scheduledAt).getTime() > Date.now());
  const canSubmit = name.trim().length > 0 && scheduleValid && !createMutation.isPending;

  return (
    <div className="dark fixed inset-0 z-[60] flex flex-col overflow-hidden bg-[#0e0e10] text-foreground">
      {/* Top bar — the studio grammar from the first click */}
      <header className="flex h-12 shrink-0 items-center gap-2 border-b border-white/10 px-2 sm:px-3">
        <Link
          to="/live"
          aria-label="Back to Live"
          className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-white/70 transition-colors hover:bg-white/10 hover:text-white"
        >
          <ArrowLeft className="h-5 w-5" />
        </Link>
        <span className="flex h-6 shrink-0 items-center gap-1.5 rounded-md px-2 text-[11px] font-black uppercase tracking-wider text-white" style={{ background: WHISPER_BRAND_GRADIENT }}>
          <Radio className="h-3 w-3" />
          Go live
        </span>
        <p className="min-w-0 flex-1 truncate px-1 text-[14px] font-semibold text-white">Set up your stream</p>
      </header>

      <div className="min-h-0 flex-1 overflow-y-auto">
        <div className="mx-auto grid w-full max-w-6xl gap-6 px-4 py-5 lg:grid-cols-[minmax(0,1.3fr)_minmax(340px,440px)] lg:items-start lg:px-6 lg:py-8">
          <StudioPreview
            title={name}
            topic={topic}
            hostName={profile?.display_name ?? profile?.username ?? "You"}
            hostUsername={profile?.username ?? "you"}
            avatarUrl={profile?.profile_image_url ?? null}
          />

      <main className="w-full">
        <h2 className="text-[20px] font-black tracking-tight text-white">Stream details</h2>
        <p className="mb-5 mt-0.5 text-[13px] text-white/55">
          What viewers see on the Live page and above your chat.
        </p>

        {/* Role-aware templates */}
        {roleKey && (
          <div className="mb-6">
            <p className="mb-2.5 flex items-center gap-1.5 text-xs font-bold uppercase tracking-wider text-muted-foreground">
              <Sparkles className="h-3.5 w-3.5" />
              Quick start for {roleKey}s
            </p>
            <button
              onClick={() => applyTemplate(roleKey)}
              className={cn(
                "flex w-full items-center gap-3 rounded-2xl border p-3.5 text-left transition-all active:scale-[0.98]",
                selectedTemplate === roleKey
                  ? "border-white/40 bg-white/[0.06]"
                  : "border-white/10 bg-white/[0.03] hover:border-white/25"
              )}
            >
              <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-white/10 text-lg">
                {TOPIC_PILLS.find((t) => t.id === ROLE_TEMPLATES[roleKey].topic)?.emoji ?? "🎙️"}
              </span>
              <div className="min-w-0 flex-1">
                <p className="text-sm font-bold">{ROLE_TEMPLATES[roleKey].name}</p>
                <p className="line-clamp-1 text-xs text-muted-foreground">
                  {ROLE_TEMPLATES[roleKey].description}
                </p>
              </div>
            </button>
          </div>
        )}

        {/* Form */}
        <div className="flex flex-col gap-5">
          {/* Space name — large, creative-project feel */}
          <div className="flex flex-col gap-2">
            <label htmlFor="name" className="text-xs font-bold uppercase tracking-wider text-muted-foreground">
              Stream title
            </label>
            <input
              id="name"
              type="text"
              value={name}
              onChange={(e) => {
                setName(e.target.value);
                setSelectedTemplate(null);
              }}
              placeholder="What are you streaming?"
              maxLength={80}
              autoFocus
              className="rounded-2xl border border-white/10 bg-white/[0.06] px-4 py-3.5 text-lg font-bold text-white outline-none placeholder:font-normal placeholder:text-white/35 focus-visible:border-white/40"
            />
          </div>

          {/* Topic pills */}
          <div className="flex flex-col gap-2">
            <label className="text-xs font-bold uppercase tracking-wider text-muted-foreground">
              Category
            </label>
            <div className="flex flex-wrap gap-2">
              {TOPIC_PILLS.map((t) => (
                <button
                  key={t.id}
                  onClick={() => setTopic(topic === t.id ? "" : t.id)}
                  className={cn(
                    "flex items-center gap-1.5 rounded-full border px-3.5 py-1.5 text-sm font-semibold transition-all active:scale-95",
                    topic === t.id
                      ? "border-white bg-white text-black"
                      : "border-white/10 bg-white/[0.04] text-white/70 hover:text-white"
                  )}
                >
                  <span>{t.emoji}</span>
                  {t.id}
                </button>
              ))}
            </div>
          </div>

          {/* Description */}
          <div className="flex flex-col gap-2">
            <label htmlFor="description" className="text-xs font-bold uppercase tracking-wider text-muted-foreground">
              Description
            </label>
            <textarea
              id="description"
              value={description}
              onChange={(e) => {
                setDescription(e.target.value);
                setSelectedTemplate(null);
              }}
              placeholder="Tell viewers what to expect"
              maxLength={240}
              rows={3}
              className="resize-none rounded-2xl border border-white/10 bg-white/[0.06] px-4 py-3 text-sm text-white outline-none placeholder:text-white/35 focus-visible:border-white/40"
            />
          </div>

          {/* Go live together — invite co-hosts */}
          <div className="flex flex-col gap-2">
            <div className="flex items-center justify-between">
              <label className="flex items-center gap-1.5 text-xs font-bold uppercase tracking-wider text-muted-foreground">
                <UserPlus className="h-3.5 w-3.5" />
                Go live together
              </label>
              <button
                type="button"
                onClick={() => setShowInvitePicker((v) => !v)}
                className="text-xs font-bold text-[#FF7340] transition-opacity hover:opacity-80"
              >
                {showInvitePicker ? "Done" : invitees.size > 0 ? "Edit" : "Invite friends"}
              </button>
            </div>
            {invitees.size === 0 && !showInvitePicker && (
              <p className="text-xs text-muted-foreground">
                Up to {MAX_BROADCASTERS} people can broadcast together. Invited friends join your grid the moment they open the live.
              </p>
            )}
            {invitees.size > 0 && (
              <div className="flex items-center gap-2">
                <div className="flex -space-x-2.5">
                  {Array.from(invitees).slice(0, 3).map((uid) => (
                    <div key={uid} className="rounded-full ring-2 ring-background">
                      <Avatar
                        url={inviteProfiles[uid]?.profile_image_url ?? null}
                        name={inviteProfiles[uid]?.username ?? "friend"}
                        size={32}
                      />
                    </div>
                  ))}
                </div>
                <p className="truncate text-xs font-semibold">
                  {Array.from(invitees)
                    .map((uid) => `@${inviteProfiles[uid]?.username ?? "friend"}`)
                    .join(", ")}
                </p>
              </div>
            )}
            {showInvitePicker && (
              <div className="max-h-56 space-y-0.5 overflow-y-auto rounded-2xl border border-white/10 bg-white/[0.04] p-1.5">
                {(followingQuery.data ?? []).length === 0 ? (
                  <p className="px-3 py-6 text-center text-xs text-muted-foreground">
                    Follow people to invite them to your live.
                  </p>
                ) : (
                  (followingQuery.data ?? []).map((f) => {
                    const isSelected = invitees.has(f.followee_id);
                    const p = inviteProfiles[f.followee_id];
                    return (
                      <button
                        key={f.followee_id}
                        type="button"
                        onClick={() => toggleInvitee(f.followee_id)}
                        className="flex w-full items-center gap-2.5 rounded-xl px-2.5 py-2 text-left transition-colors hover:bg-secondary/60"
                      >
                        <Avatar url={p?.profile_image_url ?? null} name={p?.username ?? f.followee_username} size={32} />
                        <span className="min-w-0 flex-1 truncate text-[13px] font-bold">
                          {p?.username ?? f.followee_username}
                        </span>
                        <span
                          className={cn(
                            "flex h-5 w-5 items-center justify-center rounded-full border-2 transition-all",
                            isSelected ? "border-[#F22659] bg-[#F22659] text-white" : "border-white/25"
                          )}
                        >
                          {isSelected && <Check className="h-3 w-3" />}
                        </span>
                      </button>
                    );
                  })
                )}
              </div>
            )}
          </div>

          {/* Schedule for later */}
          <div className="flex flex-col gap-2">
            <div className="flex items-center justify-between">
              <label className="flex items-center gap-1.5 text-xs font-bold uppercase tracking-wider text-muted-foreground">
                <CalendarClock className="h-3.5 w-3.5" />
                Schedule for later
              </label>
              <button
                type="button"
                role="switch"
                aria-checked={scheduleEnabled}
                onClick={() => setScheduleEnabled((v) => !v)}
                className={cn(
                  "relative h-6 w-11 rounded-full transition-colors",
                  scheduleEnabled ? "bg-[#FFA94D]" : "bg-white/15"
                )}
              >
                <span
                  className={cn(
                    "absolute top-0.5 h-5 w-5 rounded-full bg-white shadow transition-transform",
                    scheduleEnabled ? "translate-x-[22px]" : "translate-x-0.5"
                  )}
                />
              </button>
            </div>
            {scheduleEnabled && (
              <div className="animate-rise">
                <input
                  type="datetime-local"
                  value={scheduledAt}
                  min={minScheduleValue}
                  onChange={(e) => setScheduledAt(e.target.value)}
                  className="w-full rounded-2xl border border-white/10 bg-white/[0.06] px-4 py-3 text-sm text-white outline-none focus-visible:border-white/40"
                />
                <p className="mt-1.5 text-xs text-muted-foreground">
                  Your live stays visible with a countdown until it starts — it won't be deleted.
                </p>
              </div>
            )}
          </div>

          {/* Go live button */}
          <button
            onClick={() =>
              createMutation.mutate({
                name,
                description,
                topic,
                scheduledAt: scheduleEnabled && scheduledAt ? scheduledAt : null,
                inviteeIds: Array.from(invitees),
              })
            }
            disabled={!canSubmit}
            className={cn(
              "group relative mt-2 flex items-center justify-center gap-2.5 overflow-hidden rounded-full px-6 py-4 text-base font-bold text-white shadow-lg transition-transform disabled:opacity-40 disabled:active:scale-100 active:scale-95",
              scheduleEnabled ? "bg-[#FFA94D] text-black shadow-[#FFA94D]/20" : "shadow-[#F22659]/20"
            )}
            style={scheduleEnabled ? undefined : { background: WHISPER_BRAND_GRADIENT }}
          >
            <span className="absolute inset-0 -translate-x-full bg-white/20 transition-transform duration-700 group-hover:translate-x-full" />
            {scheduleEnabled ? <CalendarClock className="h-5 w-5" /> : <Radio className="h-5 w-5 animate-pulse" />}
            {createMutation.isPending
              ? "Starting…"
              : scheduleEnabled
                ? "Schedule live"
                : invitees.size > 0
                  ? `Go live with ${invitees.size} friend${invitees.size === 1 ? "" : "s"}`
                  : "Go live"}
          </button>

          <p className="text-center text-xs text-muted-foreground">
            Your stream opens full screen — the stage on one side, chat on the other, screen share one tap away.
            Viewers can ask to join you on camera; you approve who does.
          </p>
        </div>
      </main>
        </div>
      </div>
    </div>
  );
}

/**
 * The studio preview — the host's own camera, mirrored, framed exactly like
 * the stage viewers will see, with the stream title laid over it. A blocked
 * or missing camera is an honest state, never a dead black box.
 */
function StudioPreview({
  title,
  topic,
  hostName,
  hostUsername,
  avatarUrl,
}: {
  title: string;
  topic: string;
  hostName: string;
  hostUsername: string;
  avatarUrl: string | null;
}) {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const [state, setState] = useState<"loading" | "ready" | "blocked">("loading");

  useEffect(() => {
    let stream: MediaStream | null = null;
    let cancelled = false;
    void (async () => {
      try {
        if (!navigator.mediaDevices?.getUserMedia) throw new Error("unsupported");
        stream = await navigator.mediaDevices.getUserMedia({
          video: { width: { ideal: 1280 }, height: { ideal: 720 }, facingMode: "user" },
          audio: false,
        });
        if (cancelled) {
          stream.getTracks().forEach((t) => t.stop());
          return;
        }
        if (videoRef.current) {
          videoRef.current.srcObject = stream;
          void videoRef.current.play().catch(() => undefined);
        }
        setState("ready");
      } catch {
        if (!cancelled) setState("blocked");
      }
    })();
    return () => {
      cancelled = true;
      stream?.getTracks().forEach((t) => t.stop());
    };
  }, []);

  return (
    <section className="flex flex-col gap-3 lg:sticky lg:top-0">
      <div className="relative aspect-video w-full overflow-hidden rounded-2xl border border-white/10 bg-black">
        <video
          ref={videoRef}
          autoPlay
          playsInline
          muted
          className={cn(
            "h-full w-full object-cover [transform:scaleX(-1)] transition-opacity duration-500",
            state === "ready" ? "opacity-100" : "opacity-0"
          )}
        />
        {state !== "ready" && (
          <div className="absolute inset-0 flex flex-col items-center justify-center gap-2.5 px-6 text-center">
            {avatarUrl && (
              <img
                src={avatarUrl}
                alt=""
                className="absolute inset-[-12%] h-[124%] w-[124%] object-cover opacity-60 blur-[44px] saturate-[0.85]"
                draggable={false}
              />
            )}
            <div className="absolute inset-0 bg-black/45" />
            <div className="relative flex flex-col items-center gap-2.5">
              <Avatar url={avatarUrl} name={hostUsername} size={72} className="ring-2 ring-white/25" />
              {state === "loading" ? (
                <p className="flex items-center gap-1.5 text-[12.5px] text-white/70">
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  Starting your camera…
                </p>
              ) : (
                <>
                  <p className="flex items-center gap-1.5 text-[13px] font-semibold text-white">
                    <VideoOff className="h-4 w-4" />
                    Camera preview unavailable
                  </p>
                  <p className="max-w-xs text-[12px] text-white/60">
                    You can still go live — turn the camera on or share your screen from the studio.
                  </p>
                </>
              )}
            </div>
          </div>
        )}
        <div className="pointer-events-none absolute left-3 top-3 flex items-center gap-1.5">
          <span className="rounded-md bg-white/15 px-2 py-0.5 text-[10.5px] font-black uppercase tracking-wider text-white backdrop-blur-md">
            Preview
          </span>
          <span className="rounded-md bg-black/55 px-2 py-0.5 text-[11px] font-bold text-white/85 backdrop-blur-md">
            Only you can see this
          </span>
        </div>
        <div className="pointer-events-none absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/75 to-transparent px-3 pb-3 pt-10">
          <p className="truncate text-[15px] font-bold text-white">{title.trim() || "Your stream title"}</p>
          <p className="text-[12px] text-white/70">
            {hostName}
            {topic ? ` · ${topic}` : ""}
          </p>
        </div>
      </div>

      <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
        {[
          { icon: MonitorUp, title: "Share your screen", body: "Stream games, apps, or a deck once you're live." },
          { icon: MessageCircle, title: "Chat beside the stage", body: "Viewers talk while you stream — you moderate." },
          { icon: Gift, title: "Gifts pay you", body: "Viewers cheer with gifts — you keep 70%." },
        ].map((tip) => (
          <div key={tip.title} className="flex items-start gap-2.5 rounded-xl border border-white/10 bg-white/[0.03] px-3 py-2.5">
            <span className="mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-white/10 text-white">
              <tip.icon className="h-3.5 w-3.5" />
            </span>
            <div className="min-w-0">
              <p className="text-[12.5px] font-bold text-white">{tip.title}</p>
              <p className="text-[11.5px] leading-snug text-white/55">{tip.body}</p>
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}
