import { useEffect, useMemo, useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ArrowRight,
  BarChart3,
  CalendarCheck,
  Check,
  ChevronRight,
  Clock,
  Copy,
  GraduationCap,
  Inbox as InboxIcon,
  Instagram,
  MapPin,
  MessageCircle,
  Music2,
  Pencil,
  Plus,
  QrCode,
  Search,
  Send,
  SquareKanban,
  Star,
  Trash2,
  Undo2,
  UserCheck,
  Users,
  Video,
  X,
} from "lucide-react";
import { toast } from "sonner";

import { RecruiterPromotionRecords } from '@/components/RecruiterPromotionRecords';
import { RecruiterClientProfile } from '@/components/RecruiterClientProfile';
import { RecruiterTeamPipeline } from '@/components/RecruiterTeamPipeline';
import { clientMatches, clientViewLabels, loadRecruiterClients, stageAge, type ClientView } from '@/lib/recruiterClients';
import { jasperMeetingRequest } from '@/lib/jasperMeetings';
import { Avatar } from "@/components/Avatar";
import { GuidedTour, type TourStep } from "@/components/GuidedTour";
import { RecruiterApplications } from "@/components/RecruiterApplications";
import { useAuth } from "@/hooks/useAuth";
import { supabase } from "@/lib/supabase";
import { timeAgo } from "@/lib/format";
import { inviteLink } from "@/lib/site";
import { ACTIVE_PORTAL } from "@/lib/portal";
import {
  NEXT_ACTION_PRESETS,
  SCORECARD_CRITERIA,
  TERRITORY_REGION_LABELS,
  addProspectActivity,
  createProspect,
  currentPeriod,
  deleteProspect,
  deleteTerritory,
  createTerritory,
  fetchMyPromotions,
  fetchOrCreateReferralCode,
  fetchProspectActivities,
  fetchProspects,
  fetchRecruiterApplication,
  fetchTarget,
  fetchTerritories,
  probeRecruitingV4,
  promoteUser,
  prospectCountForTerritory,
  saveTarget,
  submitRecruiterApplication,
  updateProspect,
  type ActivityKind,
  type PromotableRole,
  type Prospect,
  type ProspectActivity,
  type ProspectStatus,
  type RecruiterPromotion,
  type Territory,
  type TerritoryRegion,
} from "@/lib/recruiter";
import {
  decideMeetingRequest,
  fetchMyMeetingRequests,
  type MeetingRequest,
} from "@/lib/meetings";

/**
 * Recruiting OS v4 — rebuilt on how the best talent CRMs actually work
 * (Lever / Pin / Spott research): a due-today WORK QUEUE first, a
 * drag-and-drop pipeline, a person drawer with scorecards + an activity
 * timeline + the next-action discipline, the inbox that feeds the funnel,
 * and source/speed insights. Migration: supabase/recruiting-v4.sql.
 */

const ACCENT = "#7059E8";
const DAY_MS = 86_400_000;

type Tab = "today" | "pipeline" | "people" | "inbox" | "insights" | "grow";

const TABS: { id: Tab; label: string; icon: typeof Users }[] = [
  { id: "today", label: "Today", icon: CalendarCheck },
  { id: "pipeline", label: "Pipeline", icon: SquareKanban },
  { id: "people", label: "People", icon: Users },
  { id: "inbox", label: "Inbox", icon: InboxIcon },
  { id: "insights", label: "Insights", icon: BarChart3 },
  { id: "grow", label: "Grow", icon: QrCode },
];

const STAGES: {
  id: ProspectStatus;
  label: string;
  hint: string;
  color: string;
}[] = [
  { id: "discovered", label: "Sourced", hint: "Found — not contacted yet", color: "#8B93A7" },
  { id: "contacted", label: "Contacted", hint: "First touch sent", color: "#4D9DE0" },
  { id: "interested", label: "In talks", hint: "They replied — keep it warm", color: "#A855F7" },
  { id: "meeting", label: "Evaluating", hint: "Meeting / tryout stage", color: "#F59E0B" },
  { id: "ready", label: "Offer", hint: "Ready to sign", color: "#22C55E" },
];

const SOURCE_OPTIONS = [
  "Scouted",
  "Instagram",
  "TikTok",
  "Referral",
  "Event",
  "Application",
  "Other",
];

function stageOf(status: ProspectStatus) {
  return STAGES.find((s) => s.id === status) ?? STAGES[0];
}

function displayName(p: Prospect): string {
  return p.prospect_display_name || p.prospect_username || "Unnamed";
}

function daysSince(iso: string | null | undefined): number {
  if (!iso) return 0;
  return Math.max(0, Math.floor((Date.now() - new Date(iso).getTime()) / DAY_MS));
}

function todayStr(): string {
  return new Date().toISOString().slice(0, 10);
}

type DueState = "overdue" | "today" | "upcoming" | "none";

function dueState(due: string | null | undefined): DueState {
  if (!due) return "none";
  const t = todayStr();
  if (due < t) return "overdue";
  if (due === t) return "today";
  return "upcoming";
}

function dueLabel(due: string | null | undefined): string {
  const state = dueState(due);
  if (state === "none" || !due) return "";
  if (state === "overdue") {
    const d = Math.floor((Date.now() - new Date(`${due}T12:00:00`).getTime()) / DAY_MS);
    return d <= 1 ? "1 day late" : `${d} days late`;
  }
  if (state === "today") return "Due today";
  const d = Math.ceil((new Date(`${due}T12:00:00`).getTime() - Date.now()) / DAY_MS);
  return d <= 1 ? "Tomorrow" : `In ${d} days`;
}

function compositeScore(p: Prospect): number | null {
  const values = Object.values(p.scorecard ?? {}).filter(
    (n) => typeof n === "number" && n > 0
  );
  if (values.length === 0) return p.rating ?? null;
  return Math.round((values.reduce((a, b) => a + b, 0) / values.length) * 10) / 10;
}

function agingColor(p: Prospect): string {
  const d = stageAge(p.client, p.status);
  if (d === null) return '#8B93A7';
  if (d < 4) return "#22C55E";
  if (d < 8) return "#F59E0B";
  return "#EF4444";
}

function cleanHandle(raw: string | null | undefined): string {
  return (raw ?? "").trim().replace(/^@/, "");
}

function newMeetLink(): string {
  const chunk = (): string => crypto.randomUUID().replace(/-/g, "").slice(0, 4);
  return `https://meet.mydailywhisper.com/meet/wsp-${chunk()}-${chunk()}`;
}

const inputClass =
  "w-full rounded-xl border border-border/60 bg-background px-3 py-2.5 text-[13.5px] outline-none focus:border-[#7059E8]/60";

const pillClass = (active: boolean): string =>
  `shrink-0 rounded-full px-3 py-1.5 text-[11.5px] font-bold transition-colors ${
    active ? "bg-[#7059E8] text-white" : "bg-muted/70 text-muted-foreground"
  }`;

// ─── Guided walkthrough — spotlights REAL elements; "click here" steps only
//     advance when the user actually clicks the highlighted control, so the
//     tour genuinely walks them through every section with tips. ─────────

const TOUR_KEY = "whisper_rec_tour_v1";

const TOUR_STEPS: TourStep[] = [
  {
    target: "rec-home",
    title: "Welcome to your Recruiting OS",
    body: "This headline always tells you the one thing that matters right now — how many follow-ups need you today. The tiles under it keep score: due today, people in play, signed all-time, and meeting requests waiting.",
    tip: "Replay this walkthrough anytime with the Walkthrough button up top.",
  },
  {
    target: "rec-add",
    title: "Add anyone in seconds",
    body: "Met someone at the gym? Found a creator on IG? Tap Add person and they land in your pipeline as Sourced — a name and one handle is enough to start.",
  },
  {
    target: "rec-tab-today",
    title: "Your day starts in Today",
    body: "The work queue — the habit that separates pros from dabblers.",
    clickToAdvance: true,
  },
  {
    target: "rec-view-today",
    title: "Work the queue top to bottom",
    body: "Overdue in red, due today in violet, coming up after. Done logs the touch and immediately asks for the NEXT step, so nobody ever goes cold. Snooze pushes 3 days.",
    tip: "The amber 'No next step' list is rule one: every active person carries a next step.",
  },
  {
    target: "rec-tab-pipeline",
    title: "See the whole funnel",
    body: "Pipeline is your drag-and-drop board.",
    clickToAdvance: true,
  },
  {
    target: "rec-view-pipeline",
    title: "Drag people forward",
    body: "Sourced → Contacted → In talks → Evaluating → Offer. Drag cards between stages or tap a card's arrow. The little dot is aging: green under 4 days, amber under 8, red means go rescue them.",
    tip: "On an Offer card, Sign them flips their Whisper account to the new role.",
  },
  {
    target: "rec-tab-people",
    title: "Your whole talent pool",
    body: "People is the searchable database behind the board.",
    clickToAdvance: true,
  },
  {
    target: "rec-people-search",
    title: "Search everything",
    body: "Names, niches, cities, #tags — one box. Tag people from their profile drawer (#miami, #boxing) and filter with the chips underneath.",
    tip: "The gold star is their scorecard composite — rate Talent, Drive, Coachability, and Audience in the drawer.",
  },
  {
    target: "rec-tab-inbox",
    title: "Leads come to you too",
    body: "Inbox holds meeting requests and QR applications.",
    clickToAdvance: true,
  },
  {
    target: "rec-inbox-requests",
    title: "Approve calls in one tap",
    body: "When someone books a call from your featured card it lands here. Approve or deny inline — Use Whisper Meet mints the meeting link for you, no Zoom needed.",
    tip: "Approved requests email the person automatically.",
  },
  {
    target: "rec-tab-insights",
    title: "Know your numbers",
    body: "Insights shows whether the machine is actually working.",
    clickToAdvance: true,
  },
  {
    target: "rec-view-insights",
    title: "Goal, speed, and sources",
    body: "Your monthly goal ring (tap the targets to edit), average days-to-sign, weekly signings, and which sources turn into SIGNED talent — double down where the bars are tall.",
  },
  {
    target: "rec-tab-grow",
    title: "Grow your reach",
    body: "Grow holds your invite link, QR poster, and territories.",
    clickToAdvance: true,
  },
  {
    target: "rec-view-grow",
    title: "Claim your ground",
    body: "Share the invite link anywhere, print the QR poster for events, and claim territories so the scout map knows what's yours. Applications from your QR land in the Inbox.",
    tip: "That's the whole loop — start every session in Today and the system runs itself.",
  },
];

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

export default function RecruiterDashboard() {
  const { user, profile } = useAuth();
  const queryClient = useQueryClient();
  const [searchParams, setSearchParams] = useSearchParams();
  const isRecruiter = !!profile?.is_recruiter;

  const rawTab = searchParams.get("tab");
  const tab: Tab = (TABS.some((t) => t.id === rawTab) ? rawTab : "today") as Tab;
  const setTab = (next: Tab): void => {
    const params = new URLSearchParams(searchParams);
    params.set("tab", next);
    if (ACTIVE_PORTAL) params.set("portal", ACTIVE_PORTAL);
    setSearchParams(params, { replace: true });
  };

  const [drawerId, setDrawerId] = useState<string | null>(null);
  const [adding, setAdding] = useState<boolean>(false);
  const [tourOpen, setTourOpen] = useState<boolean>(false);

  // First visit: the guided walkthrough introduces the whole OS; the
  // Walkthrough button replays it anytime.
  useEffect(() => {
    if (!isRecruiter) return;
    try {
      if (localStorage.getItem(TOUR_KEY)) return;
    } catch {
      return;
    }
    const t = window.setTimeout(() => setTourOpen(true), 900);
    return () => window.clearTimeout(t);
  }, [isRecruiter]);

  const closeTour = (completed: boolean): void => {
    setTourOpen(false);
    try {
      localStorage.setItem(TOUR_KEY, completed ? "done" : "skipped");
    } catch {
      /* storage unavailable */
    }
  };

  // ── Data ────────────────────────────────────────────────────────────
  const prospectsQuery = useQuery({
    queryKey: ["recruiter-prospects", user?.id ?? "anon"],
    enabled: !!user && isRecruiter,
    queryFn: () => fetchProspects(user!.id),
  });
  const promotionsQuery = useQuery({
    queryKey: ["recruiter-promotions", user?.id ?? "anon"],
    enabled: !!user && isRecruiter,
    queryFn: () => fetchMyPromotions(user!.id),
  });
  const v4Query = useQuery({
    queryKey: ["recruiting-v4-probe"],
    enabled: isRecruiter,
    queryFn: probeRecruitingV4,
    staleTime: 5 * 60 * 1000,
  });
  const requestsQuery = useQuery({
    queryKey: ["recruiter-meeting-requests", user?.id ?? "anon"],
    enabled: !!user && isRecruiter,
    queryFn: async (): Promise<MeetingRequest[]> => {
      const { data } = await supabase.auth.getSession();
      const token = data.session?.access_token;
      if (!token) return [];
      try {
        return await fetchMyMeetingRequests(token);
      } catch {
        return [];
      }
    },
  });
  const targetQuery = useQuery({
    queryKey: ["recruiter-target", user?.id ?? "anon"],
    enabled: !!user && isRecruiter,
    queryFn: () => fetchTarget(user!.id),
  });

  const clientsQuery = useQuery({ queryKey: ['recruiter-clients', user?.id], enabled: !!user && isRecruiter, queryFn: ({ signal }) => loadRecruiterClients(user!.id, signal), gcTime: 0 });
  const [clientView, setClientView] = useState<ClientView>('all');
  const [pipelineScope, setPipelineScope] = useState<'private' | 'team'>('private');
  const prospects = useMemo(
    () => (prospectsQuery.data ?? []).map((p) => ({ ...p, client: clientsQuery.data?.[p.id] })),
    [prospectsQuery.data, clientsQuery.data]
  );
  const promotions = useMemo(
    () => promotionsQuery.data ?? [],
    [promotionsQuery.data]
  );
  const v4Ready = v4Query.data !== false;
  const requests = requestsQuery.data ?? [];
  const pendingRequests = requests.filter((r) => r.status === "pending");

  const invalidate = (): void => {
    void queryClient.invalidateQueries({ queryKey: ['recruiter-clients', user?.id] });
    void queryClient.invalidateQueries({ queryKey: ['recruiter-client', user?.id] });
    void queryClient.invalidateQueries({
      queryKey: ["recruiter-prospects", user?.id ?? "anon"],
    });
  };

  // ── Mutations shared across views ───────────────────────────────────
  const stageMutation = useMutation({
    mutationFn: async (input: { prospect: Prospect; status: ProspectStatus }) => {
      if (!user) throw new Error('Sign in required');
      await jasperMeetingRequest(user.id, `clients/stage?id=${input.prospect.id}`, { stage: input.status, expectedStage: input.prospect.status, expectedUpdatedAt: input.prospect.updated_at });
      if (v4Ready && user) {
        const label =
          input.status === "passed"
            ? "Archived (passed)"
            : `Moved to ${stageOf(input.status).label}`;
        try {
          await addProspectActivity(user.id, input.prospect.id, "stage", label);
        } catch {
          /* v4 optional */
        }
      }
    },
    onSuccess: invalidate,
    onError: () => toast.error("Couldn't move them. Try again."),
  });

  const completeMutation = useMutation({
    mutationFn: async (p: Prospect) => {
      if (user && v4Ready) {
        const preset = NEXT_ACTION_PRESETS.find(
          (a) => a.label === (p.next_action ?? "")
        );
        try {
          await addProspectActivity(
            user.id,
            p.id,
            (preset?.kind ?? "task") as ActivityKind,
            `Done: ${p.next_action ?? "follow-up"}`
          );
        } catch {
          /* best effort */
        }
      }
      await updateProspect(p.id, {
        next_action: null,
        next_action_due: null,
        last_touch_at: new Date().toISOString(),
      });
    },
    onSuccess: (_data, p) => {
      invalidate();
      toast.success("Logged. Set their next step 👇");
      setDrawerId(p.id);
    },
    onError: () =>
      toast.error(
        v4Ready ? "Couldn't log that." : "Run supabase/recruiting-v4.sql first."
      ),
  });

  const snoozeMutation = useMutation({
    mutationFn: async (p: Prospect) => {
      const due = new Date(Date.now() + 3 * DAY_MS).toISOString().slice(0, 10);
      await updateProspect(p.id, { next_action_due: due });
    },
    onSuccess: () => {
      invalidate();
      toast.success("Snoozed 3 days.");
    },
  });

  const decideMutation = useMutation({
    mutationFn: async (input: {
      id: string;
      decision: "approved" | "denied";
      meetingLink?: string;
    }) => {
      const { data } = await supabase.auth.getSession();
      const token = data.session?.access_token;
      if (!token) throw new Error("Sign in again.");
      await decideMeetingRequest(token, input);
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({
        queryKey: ["recruiter-meeting-requests", user?.id ?? "anon"],
      });
      toast.success("Request updated — they'll get an email.");
    },
    onError: (e: unknown) =>
      toast.error(e instanceof Error ? e.message : "Couldn't update."),
  });

  const addMutation = useMutation({
    mutationFn: async (input: {
      name: string;
      username: string;
      instagram: string;
      tiktok: string;
      niche: string;
      location: string;
      source: string;
      role: PromotableRole | "";
    }) => {
      if (!user) throw new Error("Sign in first.");
      await createProspect(user.id, {
        prospectDisplayName: input.name.trim() || undefined,
        prospectUsername: cleanHandle(input.username) || undefined,
        instagram: cleanHandle(input.instagram) || undefined,
        tiktok: cleanHandle(input.tiktok) || undefined,
        niche: input.niche.trim() || undefined,
        location: input.location.trim() || undefined,
        source: input.source || "Scouted",
        suggestedRole: input.role || undefined,
      });
    },
    onSuccess: () => {
      setAdding(false);
      invalidate();
      toast.success("Added to Sourced.");
    },
    onError: (e: unknown) =>
      toast.error(
        (e as { message?: string }).message ?? "Couldn't add them — try again."
      ),
  });

  const drawerProspect = prospects.find((p) => p.id === drawerId) ?? null;

  if (!user) return null;

  if (!isRecruiter) {
    return <ApplyGate userId={user.id} username={profile?.username ?? ""} />;
  }

  const active = prospects.filter((p) => p.status !== "passed");
  const dueNow = active.filter(
    (p) => dueState(p.next_action_due) === "overdue" || dueState(p.next_action_due) === "today"
  ).length;

  return (
    <div className="mx-auto w-full max-w-6xl px-4 py-6 lg:py-8">
      {/* Header */}
      <div
        className="rounded-[24px] border border-border/60 px-5 py-5"
        style={{
          background:
            "linear-gradient(135deg, rgba(112,89,232,0.12), rgba(112,89,232,0.03) 45%, transparent 70%)",
        }}
      >
        <div className="flex flex-wrap items-start gap-3">
          <div className="min-w-0 flex-1" data-tour="rec-home">
            <p
              className="text-[11px] font-black uppercase tracking-[0.2em]"
              style={{ color: ACCENT }}
            >
              Recruiting OS
            </p>
            <h1 className="mt-0.5 font-display text-[24px] font-extrabold leading-tight sm:text-[28px]">
              {dueNow > 0
                ? `${dueNow} follow-up${dueNow === 1 ? "" : "s"} need${dueNow === 1 ? "s" : ""} you today`
                : "All caught up. Go find someone great."}
            </h1>
          </div>
          <div className="flex shrink-0 flex-wrap items-center gap-2">
            <button
              onClick={() => setTourOpen(true)}
              title="Replay the guided walkthrough"
              className="flex h-11 items-center gap-1.5 rounded-full border border-border/70 bg-card px-4 text-[13px] font-bold transition-colors hover:bg-secondary/50"
            >
              <GraduationCap className="h-4 w-4" style={{ color: ACCENT }} />
              Walkthrough
            </button>
            <button
              onClick={() => setAdding(true)}
              data-tour="rec-add"
              className="flex h-11 items-center gap-1.5 rounded-full px-4 text-[13px] font-extrabold text-white transition-transform active:scale-95"
              style={{ backgroundColor: ACCENT }}
            >
              <Plus className="h-4 w-4" />
              Add person
            </button>
          </div>
        </div>

        {/* Stat strip — the four numbers that matter, lined up. */}
        <div className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-4">
          {[
            {
              value: dueNow,
              label: "Due today",
              tint: dueNow > 0 ? ACCENT : undefined,
            },
            { value: active.length, label: "In play" },
            { value: promotions.length, label: "Signed all-time" },
            { value: pendingRequests.length, label: "Requests waiting" },
          ].map((s) => (
            <div
              key={s.label}
              className="rounded-2xl border border-border/60 bg-card/70 px-3 py-2.5 text-center"
            >
              <p
                className="text-[20px] font-black leading-tight tabular-nums"
                style={s.tint ? { color: s.tint } : undefined}
              >
                {s.value}
              </p>
              <p className="text-[9.5px] font-bold uppercase tracking-[0.08em] text-muted-foreground">
                {s.label}
              </p>
            </div>
          ))}
        </div>
      </div>

      {/* v4 migration banner */}
      {!v4Ready && (
        <div className="mt-3 rounded-[16px] border border-amber-500/40 bg-amber-500/10 px-3.5 py-2.5">
          <p className="text-[11.5px] font-semibold leading-relaxed">
            One-time upgrade: run{" "}
            <span className="font-mono font-bold">supabase/recruiting-v4.sql</span>{" "}
            in the Supabase SQL editor to unlock next-step reminders, tags,
            scorecards, and the activity timeline. The pipeline works right now.
          </p>
        </div>
      )}

      {/* Tab pills */}
      <div className="no-scrollbar mt-4 flex gap-1.5 overflow-x-auto">
        {TABS.map((t) => {
          const activeTab = tab === t.id;
          const badge =
            t.id === "today"
              ? dueNow
              : t.id === "inbox"
                ? pendingRequests.length
                : 0;
          return (
            <button
              key={t.id}
              data-tour={`rec-tab-${t.id}`}
              onClick={() => setTab(t.id)}
              className={`flex h-10 shrink-0 items-center gap-1.5 rounded-full px-4 text-[12.5px] font-extrabold transition-colors ${
                activeTab ? "text-white" : "bg-muted/60 text-muted-foreground hover:text-foreground"
              }`}
              style={activeTab ? { backgroundColor: ACCENT } : undefined}
            >
              <t.icon className="h-3.5 w-3.5" />
              {t.label}
              {badge > 0 && (
                <span
                  className={`flex h-4.5 min-w-[18px] items-center justify-center rounded-full px-1 text-[10px] font-black ${
                    activeTab ? "bg-white/25 text-white" : "bg-[#7059E8]/15 text-[#7059E8]"
                  }`}
                >
                  {badge}
                </span>
              )}
            </button>
          );
        })}
      </div>

      <div className="mt-5">
        {(tab === 'pipeline' || tab === 'people') && <div className="mb-4 space-y-3">
          <div className="flex gap-2"><button className="min-h-11 rounded-full border px-4 text-sm" aria-pressed={pipelineScope === 'private'} onClick={() => setPipelineScope('private')}>My private list</button><button className="min-h-11 rounded-full border px-4 text-sm" aria-pressed={pipelineScope === 'team'} onClick={() => setPipelineScope('team')}>Team pipeline</button></div>
          {pipelineScope === 'private' && <><RecruiterPromotionRecords owner={user.id} /><div className="flex flex-wrap gap-2">{(Object.keys(clientViewLabels) as ClientView[]).map((view) => <button key={view} className="min-h-11 rounded-full bg-muted px-3 text-xs aria-pressed:bg-foreground aria-pressed:text-background" aria-pressed={clientView === view} onClick={() => setClientView(view)}>{clientViewLabels[view]}</button>)}</div><p className="text-xs text-muted-foreground">Stalled means 8+ days in a recorded stage. Older stage dates are unknown. Promotions are recorded role changes, not signed contracts.</p>{clientsQuery.error && <p role="alert" className="text-xs text-destructive">Private relationship details couldn’t load. <button onClick={() => void clientsQuery.refetch()}>Retry</button></p>}</>}
          {pipelineScope === 'team' && <RecruiterTeamPipeline key={user.id} owner={user.id} />}
        </div>}
        {tab === "today" && (
          <div data-tour="rec-view-today">
            {prospects.some((p) => p.client?.followUp) && <section className="mb-4 space-y-2 rounded-2xl border p-4"><h3 className="font-semibold">Private relationship follow-ups</h3>{prospects.filter((p) => p.status !== 'passed' && p.client?.followUp).map((p) => <button key={p.id} className="flex min-h-11 w-full flex-col rounded-xl bg-muted/40 p-3 text-left text-sm" onClick={() => setDrawerId(p.id)}><strong>{displayName(p)}</strong><span>{p.client?.followUp}</span><span className="text-xs text-muted-foreground">{p.client?.followUpDue || 'No due date'} · Open to review or clear</span></button>)}</section>}
            <TodayView
              prospects={prospects}
              v4Ready={v4Ready}
              onOpen={(p) => setDrawerId(p.id)}
              onComplete={(p) => completeMutation.mutate(p)}
              onSnooze={(p) => snoozeMutation.mutate(p)}
            />
          </div>
        )}
        {tab === "pipeline" && pipelineScope === 'private' && (
          <div data-tour="rec-view-pipeline">
            <PipelineView
              prospects={prospects.filter((p) => clientMatches(clientView, p, p.client, promotions))}
              promotions={promotions}
              onOpen={(p) => setDrawerId(p.id)}
              onStage={(p, status) => stageMutation.mutate({ prospect: p, status })}
            />
          </div>
        )}
        {tab === "people" && pipelineScope === 'private' && (
          <PeopleView prospects={prospects.filter((p) => clientMatches(clientView, p, p.client, promotions))} onOpen={(p) => setDrawerId(p.id)} />
        )}
        {tab === "inbox" && (
          <InboxView
            userId={user.id}
            requests={requests}
            loading={requestsQuery.isLoading}
            decidePending={decideMutation.isPending}
            onDecide={(id, decision, meetingLink) =>
              decideMutation.mutate({ id, decision, meetingLink })
            }
          />
        )}
        {tab === "insights" && (
          <div data-tour="rec-view-insights">
            <InsightsView
              prospects={prospects}
              promotions={promotions}
              target={targetQuery.data ?? null}
              onSaveTarget={async (coach, athlete, creator) => {
                await saveTarget(user.id, currentPeriod(), {
                  coach,
                  athlete,
                  creator,
                });
                void queryClient.invalidateQueries({
                  queryKey: ["recruiter-target", user?.id ?? "anon"],
                });
                toast.success("Goal saved.");
              }}
            />
          </div>
        )}
        {tab === "grow" && (
          <div data-tour="rec-view-grow">
            <GrowView
              userId={user.id}
              username={profile?.username ?? ""}
              prospects={prospects}
            />
          </div>
        )}
      </div>

      {drawerProspect && (
        <PersonDrawer
          prospect={drawerProspect}
          recruiterId={user.id}
          recruiterUsername={profile?.username ?? ""}
          promotions={promotions}
          v4Ready={v4Ready}
          onClose={() => setDrawerId(null)}
          onChanged={() => {
            invalidate();
            void queryClient.invalidateQueries({
              queryKey: ["recruiter-promotions", user?.id ?? "anon"],
            });
          }}
          onStage={(status) =>
            stageMutation.mutate({ prospect: drawerProspect, status })
          }
        />
      )}

      {adding && (
        <AddPersonSheet
          pending={addMutation.isPending}
          onClose={() => setAdding(false)}
          onCreate={(input) => addMutation.mutate(input)}
        />
      )}

      <GuidedTour
        steps={TOUR_STEPS}
        open={tourOpen}
        accent={ACCENT}
        onClose={closeTour}
      />
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Apply gate — non-recruiters
// ─────────────────────────────────────────────────────────────────────────────

function ApplyGate({ userId, username }: { userId: string; username: string }) {
  const appQuery = useQuery({
    queryKey: ["recruiter-application", userId],
    queryFn: () => fetchRecruiterApplication(userId),
  });
  const [fullName, setFullName] = useState<string>("");
  const [email, setEmail] = useState<string>("");
  const [region, setRegion] = useState<string>("");
  const [experience, setExperience] = useState<string>("");
  const [bio, setBio] = useState<string>("");
  const [social, setSocial] = useState<string>("");
  const queryClient = useQueryClient();

  const submit = useMutation({
    mutationFn: () =>
      submitRecruiterApplication({
        userId,
        username,
        email,
        fullName,
        region,
        experience,
        bio,
        social,
      }),
    onSuccess: () => {
      toast.success("Application sent — we'll review it soon.");
      void queryClient.invalidateQueries({
        queryKey: ["recruiter-application", userId],
      });
    },
    onError: () => toast.error("Couldn't submit. Try again."),
  });

  const status = appQuery.data?.status ?? "none";

  return (
    <div className="mx-auto w-full max-w-xl px-4 py-10">
      <p
        className="text-[11px] font-black uppercase tracking-[0.2em]"
        style={{ color: ACCENT }}
      >
        Recruiting OS
      </p>
      <h1 className="mt-1 font-display text-[26px] font-extrabold leading-tight">
        Scout talent for Whisper.
      </h1>
      <p className="mt-1.5 text-[13.5px] leading-relaxed text-muted-foreground">
        Recruiters find the coaches, athletes, and creators who make Whisper
        dense — and get the full pipeline OS to work them: follow-up queue,
        drag-and-drop stages, scorecards, and source analytics.
      </p>

      {status === "pending" ? (
        <div className="mt-6 rounded-[20px] border border-border/60 bg-card p-5">
          <p className="text-[15px] font-extrabold">Application in review</p>
          <p className="mt-1 text-[12.5px] leading-relaxed text-muted-foreground">
            We got it. You'll be notified the moment you're approved.
          </p>
        </div>
      ) : status === "denied" ? (
        <div className="mt-6 rounded-[20px] border border-border/60 bg-card p-5">
          <p className="text-[15px] font-extrabold">Not this time</p>
          <p className="mt-1 text-[12.5px] leading-relaxed text-muted-foreground">
            Your last application wasn't approved. You can apply again with
            more detail below.
          </p>
        </div>
      ) : null}

      {status !== "pending" && (
        <div className="mt-5 space-y-2.5 rounded-[20px] border border-border/60 bg-card p-4">
          <input
            value={fullName}
            onChange={(e) => setFullName(e.target.value)}
            placeholder="Full name"
            className={inputClass}
          />
          <input
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="Email"
            className={inputClass}
          />
          <input
            value={region}
            onChange={(e) => setRegion(e.target.value)}
            placeholder="Region you'd cover (e.g. Southeast, Atlanta)"
            className={inputClass}
          />
          <input
            value={social}
            onChange={(e) => setSocial(e.target.value)}
            placeholder="Instagram / TikTok handle"
            className={inputClass}
          />
          <textarea
            value={experience}
            onChange={(e) => setExperience(e.target.value)}
            placeholder="Your recruiting / networking experience"
            rows={2}
            className={`${inputClass} resize-none`}
          />
          <textarea
            value={bio}
            onChange={(e) => setBio(e.target.value)}
            placeholder="Why you?"
            rows={2}
            className={`${inputClass} resize-none`}
          />
          <button
            onClick={() => {
              if (!fullName.trim() || !region.trim()) {
                toast.error("Name and region are required.");
                return;
              }
              submit.mutate();
            }}
            disabled={submit.isPending}
            className="w-full rounded-full py-3 text-[13.5px] font-extrabold text-white transition-transform active:scale-[0.98] disabled:opacity-60"
            style={{ backgroundColor: ACCENT }}
          >
            {submit.isPending ? "Sending…" : "Apply to recruit"}
          </button>
        </div>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Today — the work queue (the #1 researched CRM discipline)
// ─────────────────────────────────────────────────────────────────────────────

function TodayView({
  prospects,
  v4Ready,
  onOpen,
  onComplete,
  onSnooze,
}: {
  prospects: Prospect[];
  v4Ready: boolean;
  onOpen: (p: Prospect) => void;
  onComplete: (p: Prospect) => void;
  onSnooze: (p: Prospect) => void;
}) {
  const active = prospects.filter((p) => p.status !== "passed");
  const overdue = active.filter((p) => dueState(p.next_action_due) === "overdue");
  const today = active.filter((p) => dueState(p.next_action_due) === "today");
  const upcoming = active
    .filter((p) => dueState(p.next_action_due) === "upcoming")
    .slice(0, 8);
  const noNext = active.filter((p) => dueState(p.next_action_due) === "none");

  const row = (p: Prospect, tone: "red" | "violet" | "muted"): React.ReactNode => {
    const stage = stageOf(p.status);
    return (
      <div
        key={p.id}
        className="flex items-center gap-2.5 rounded-[18px] border border-border/60 bg-card px-3 py-2.5"
      >
        <button onClick={() => onOpen(p)} className="shrink-0">
          <Avatar url={p.prospect_image_url} name={displayName(p)} size={38} />
        </button>
        <button onClick={() => onOpen(p)} className="min-w-0 flex-1 text-left">
          <div className="flex items-center gap-1.5">
            <p className="truncate text-[13.5px] font-extrabold">
              {displayName(p)}
            </p>
            <span
              className="flex shrink-0 items-center gap-1 rounded-full px-1.5 py-0.5 text-[9.5px] font-black uppercase tracking-wide"
              style={{ color: stage.color, backgroundColor: `${stage.color}18` }}
            >
              {stage.label}
            </span>
          </div>
          <p className="mt-0.5 truncate text-[11.5px] text-muted-foreground">
            {p.next_action ?? "Follow up"}
            {p.next_action_due ? (
              <span
                className={`ml-1.5 font-bold ${
                  tone === "red"
                    ? "text-red-500"
                    : tone === "violet"
                      ? "text-[#7059E8]"
                      : ""
                }`}
              >
                {dueLabel(p.next_action_due)}
              </span>
            ) : null}
          </p>
        </button>
        <button
          onClick={() => onSnooze(p)}
          title="Snooze 3 days"
          aria-label="Snooze"
          className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-muted/70 text-muted-foreground transition-colors hover:text-foreground"
        >
          <Clock className="h-4 w-4" />
        </button>
        <button
          onClick={() => onComplete(p)}
          title="Mark done"
          aria-label="Mark done"
          className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-white transition-transform active:scale-90"
          style={{ backgroundColor: "#22C55E" }}
        >
          <Check className="h-4 w-4" />
        </button>
      </div>
    );
  };

  return (
    <div className="space-y-5">
      {overdue.length === 0 && today.length === 0 && (
        <div className="rounded-[22px] border border-border/60 bg-card px-6 py-10 text-center">
          <span
            className="mx-auto flex h-14 w-14 items-center justify-center rounded-2xl"
            style={{ backgroundColor: `${ACCENT}14`, color: ACCENT }}
          >
            <CalendarCheck className="h-7 w-7" />
          </span>
          <p className="mt-3 text-[15px] font-extrabold">Nothing due today</p>
          <p className="mx-auto mt-1 max-w-sm text-[12.5px] leading-relaxed text-muted-foreground">
            The best recruiters never let a lead go cold — give everyone below
            a next step and tomorrow's queue builds itself.
          </p>
        </div>
      )}

      {overdue.length > 0 && (
        <div>
          <p className="mb-2 text-[10.5px] font-black uppercase tracking-[0.16em] text-red-500">
            Overdue · {overdue.length}
          </p>
          <div className="space-y-2">{overdue.map((p) => row(p, "red"))}</div>
        </div>
      )}

      {today.length > 0 && (
        <div>
          <p
            className="mb-2 text-[10.5px] font-black uppercase tracking-[0.16em]"
            style={{ color: ACCENT }}
          >
            Due today · {today.length}
          </p>
          <div className="space-y-2">{today.map((p) => row(p, "violet"))}</div>
        </div>
      )}

      {upcoming.length > 0 && (
        <div>
          <p className="mb-2 text-[10.5px] font-black uppercase tracking-[0.16em] text-muted-foreground">
            Coming up
          </p>
          <div className="space-y-2">{upcoming.map((p) => row(p, "muted"))}</div>
        </div>
      )}

      {noNext.length > 0 && (
        <div>
          <p className="mb-2 text-[10.5px] font-black uppercase tracking-[0.16em] text-amber-500">
            No next step · {noNext.length}
          </p>
          <p className="mb-2 text-[11.5px] leading-snug text-muted-foreground">
            {v4Ready
              ? "Rule one of recruiting: every active person carries a next step. Tap one and set it."
              : "Run supabase/recruiting-v4.sql to unlock next-step reminders."}
          </p>
          <div className="space-y-2">
            {noNext.slice(0, 10).map((p) => {
              const stage = stageOf(p.status);
              return (
                <button
                  key={p.id}
                  onClick={() => onOpen(p)}
                  className="flex w-full items-center gap-2.5 rounded-[18px] border border-dashed border-border/70 bg-card/60 px-3 py-2.5 text-left transition-colors hover:bg-secondary/40"
                >
                  <Avatar
                    url={p.prospect_image_url}
                    name={displayName(p)}
                    size={34}
                  />
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-[13px] font-bold">
                      {displayName(p)}
                    </span>
                    <span className="block truncate text-[11px] text-muted-foreground">
                      {stage.label} · last touch{" "}
                      {p.last_touch_at || p.updated_at
                        ? timeAgo(p.last_touch_at ?? p.updated_at ?? "")
                        : "never"}
                    </span>
                  </span>
                  <span
                    className="shrink-0 rounded-full px-2.5 py-1 text-[10.5px] font-extrabold"
                    style={{ color: ACCENT, backgroundColor: `${ACCENT}14` }}
                  >
                    Set next step
                  </span>
                </button>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Pipeline — drag & drop kanban with aging
// ─────────────────────────────────────────────────────────────────────────────

function PipelineView({
  prospects,
  promotions,
  onOpen,
  onStage,
}: {
  prospects: Prospect[];
  promotions: RecruiterPromotion[];
  onOpen: (p: Prospect) => void;
  onStage: (p: Prospect, status: ProspectStatus) => void;
}) {
  const [dragOver, setDragOver] = useState<ProspectStatus | null>(null);
  const [showPassed, setShowPassed] = useState<boolean>(false);
  const active = prospects.filter((p) => p.status !== "passed");
  const passed = prospects.filter((p) => p.status === "passed");

  const byStage = (id: ProspectStatus): Prospect[] =>
    active.filter((p) => p.status === id);

  const handleDrop = (e: React.DragEvent, status: ProspectStatus): void => {
    e.preventDefault();
    setDragOver(null);
    const id = e.dataTransfer.getData("text/plain");
    const p = prospects.find((x) => x.id === id);
    if (p && p.status !== status) onStage(p, status);
  };

  return (
    <div>
      <p className="mb-3 text-[11.5px] text-muted-foreground">
        Drag cards between stages — or use the arrow on each card. Dots show
        how long someone's been sitting: green &lt;4d, amber &lt;8d, red 8d+.
      </p>
      <div className="no-scrollbar -mx-4 flex gap-3 overflow-x-auto px-4 pb-2">
        {STAGES.map((stage, si) => {
          const list = byStage(stage.id);
          const next = STAGES[si + 1];
          return (
            <div
              key={stage.id}
              onDragOver={(e) => {
                e.preventDefault();
                setDragOver(stage.id);
              }}
              onDragLeave={() => setDragOver((v) => (v === stage.id ? null : v))}
              onDrop={(e) => handleDrop(e, stage.id)}
              className={`w-[248px] shrink-0 rounded-[20px] border p-2.5 transition-colors ${
                dragOver === stage.id
                  ? "border-[#7059E8] bg-[#7059E8]/8"
                  : "border-border/60 bg-card/60"
              }`}
            >
              <div className="flex items-center gap-1.5 px-1">
                <span
                  className="h-2 w-2 rounded-full"
                  style={{ backgroundColor: stage.color }}
                />
                <p className="text-[12px] font-extrabold">{stage.label}</p>
                <span className="text-[11px] font-bold text-muted-foreground">
                  {list.length}
                </span>
                <span className="ml-auto text-[9.5px] font-semibold text-muted-foreground/70">
                  {active.length > 0
                    ? `${Math.round((list.length / active.length) * 100)}%`
                    : ""}
                </span>
              </div>
              <p className="mt-0.5 px-1 text-[9.5px] text-muted-foreground/70">
                {stage.hint}
              </p>
              <div className="mt-2 space-y-2">
                {list.map((p) => (
                  <div
                    key={p.id}
                    draggable
                    onDragStart={(e) =>
                      e.dataTransfer.setData("text/plain", p.id)
                    }
                    className="cursor-grab rounded-[16px] border border-border/60 bg-card p-2.5 active:cursor-grabbing"
                  >
                    <div className="flex items-center gap-2">
                      <button onClick={() => onOpen(p)} className="shrink-0">
                        <Avatar
                          url={p.prospect_image_url}
                          name={displayName(p)}
                          size={32}
                        />
                      </button>
                      <button
                        onClick={() => onOpen(p)}
                        className="min-w-0 flex-1 text-left"
                      >
                        <p className="truncate text-[12.5px] font-extrabold leading-tight">
                          {displayName(p)}
                        </p>
                        <p className="truncate text-[10.5px] text-muted-foreground">
                          {p.niche || p.source || "—"}
                        </p>
                      </button>
                      <span
                        title={stageAge(p.client, p.status) === null ? 'Stage entry not recorded' : `${stageAge(p.client, p.status)}d in stage`}
                        className="flex shrink-0 items-center gap-1 text-[9.5px] font-bold text-muted-foreground"
                      >
                        <span
                          className="h-2 w-2 rounded-full"
                          style={{ backgroundColor: agingColor(p) }}
                        />
                        {stageAge(p.client, p.status) === null ? '—' : `${stageAge(p.client, p.status)}d`}
                      </span>
                    </div>
                    <div className="mt-1.5 flex items-center gap-1.5">
                      {p.next_action_due && (
                        <span
                          className={`truncate rounded-full px-1.5 py-0.5 text-[9px] font-bold ${
                            dueState(p.next_action_due) === "overdue"
                              ? "bg-red-500/12 text-red-500"
                              : "bg-muted/70 text-muted-foreground"
                          }`}
                        >
                          {dueLabel(p.next_action_due)}
                        </span>
                      )}
                      {compositeScore(p) != null && (
                        <span className="flex items-center gap-0.5 rounded-full bg-amber-500/12 px-1.5 py-0.5 text-[9px] font-bold text-amber-500">
                          <Star className="h-2.5 w-2.5 fill-amber-500" />
                          {compositeScore(p)}
                        </span>
                      )}
                      <span className="flex-1" />
                      {next ? (
                        <button
                          onClick={() => onStage(p, next.id)}
                          title={`Move to ${next.label}`}
                          aria-label={`Move to ${next.label}`}
                          className="flex h-6 w-6 items-center justify-center rounded-full bg-muted/70 text-muted-foreground transition-colors hover:text-foreground"
                        >
                          <ArrowRight className="h-3 w-3" />
                        </button>
                      ) : (
                        <button
                          onClick={() => onOpen(p)}
                          className="rounded-full bg-emerald-500/12 px-2 py-0.5 text-[9.5px] font-extrabold text-emerald-500"
                        >
                          Sign →
                        </button>
                      )}
                    </div>
                  </div>
                ))}
                {list.length === 0 && (
                  <div className="rounded-[14px] border border-dashed border-border/60 px-2 py-5 text-center text-[10.5px] text-muted-foreground/70">
                    Drop someone here
                  </div>
                )}
              </div>
            </div>
          );
        })}
      </div>

      {/* Signed + archive */}
      <div className="mt-4 flex flex-wrap items-center gap-2">
        <span className="flex items-center gap-1.5 rounded-full bg-emerald-500/12 px-3 py-1.5 text-[11.5px] font-extrabold text-emerald-600">
          <UserCheck className="h-3.5 w-3.5" />
          {promotions.length} recorded role promotions
        </span>
        {passed.length > 0 && (
          <button
            onClick={() => setShowPassed((v) => !v)}
            className="rounded-full bg-muted/70 px-3 py-1.5 text-[11.5px] font-bold text-muted-foreground transition-colors hover:text-foreground"
          >
            {showPassed ? "Hide" : "Show"} archive · {passed.length}
          </button>
        )}
      </div>
      {showPassed && passed.length > 0 && (
        <div className="mt-2.5 space-y-2">
          {passed.map((p) => (
            <div
              key={p.id}
              className="flex items-center gap-2.5 rounded-[16px] border border-border/50 bg-card/50 px-3 py-2 opacity-80"
            >
              <Avatar url={p.prospect_image_url} name={displayName(p)} size={30} />
              <button onClick={() => onOpen(p)} className="min-w-0 flex-1 text-left">
                <p className="truncate text-[12.5px] font-bold">
                  {displayName(p)}
                </p>
              </button>
              <button
                onClick={() => onStage(p, "interested")}
                className="flex items-center gap-1 rounded-full bg-muted/70 px-2.5 py-1 text-[10.5px] font-bold text-muted-foreground transition-colors hover:text-foreground"
              >
                <Undo2 className="h-3 w-3" />
                Bring back
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// People — searchable talent pool
// ─────────────────────────────────────────────────────────────────────────────

function PeopleView({
  prospects,
  onOpen,
}: {
  prospects: Prospect[];
  onOpen: (p: Prospect) => void;
}) {
  const [query, setQuery] = useState<string>("");
  const [tag, setTag] = useState<string | null>(null);

  const allTags = useMemo(() => {
    const set = new Set<string>();
    for (const p of prospects) for (const t of p.tags ?? []) set.add(t);
    return Array.from(set).slice(0, 12);
  }, [prospects]);

  const list = useMemo(() => {
    const q = query.trim().toLowerCase();
    return prospects
      .filter((p) => {
        if (tag && !(p.tags ?? []).includes(tag)) return false;
        if (!q) return true;
        return [
          displayName(p),
          p.prospect_username ?? "",
          p.niche ?? "",
          p.location ?? "",
          p.source ?? "",
          (p.tags ?? []).join(" "),
        ]
          .join(" ")
          .toLowerCase()
          .includes(q);
      })
      .sort(
        (a, b) =>
          new Date(b.last_touch_at ?? b.updated_at ?? 0).getTime() -
          new Date(a.last_touch_at ?? a.updated_at ?? 0).getTime()
      );
  }, [prospects, query, tag]);

  return (
    <div>
      <div
        data-tour="rec-people-search"
        className="flex h-11 items-center gap-2 rounded-full border border-border bg-card px-4"
      >
        <Search className="h-4 w-4 shrink-0 text-muted-foreground" />
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search names, niches, tags, cities…"
          className="min-w-0 flex-1 bg-transparent text-[13.5px] outline-none placeholder:text-muted-foreground/60"
        />
      </div>
      {allTags.length > 0 && (
        <div className="no-scrollbar mt-2.5 flex gap-1.5 overflow-x-auto">
          <button onClick={() => setTag(null)} className={pillClass(tag === null)}>
            All
          </button>
          {allTags.map((t) => (
            <button
              key={t}
              onClick={() => setTag(tag === t ? null : t)}
              className={pillClass(tag === t)}
            >
              #{t}
            </button>
          ))}
        </div>
      )}
      <div className="mt-3 space-y-2">
        {list.map((p) => {
          const stage = stageOf(p.status);
          return (
            <button
              key={p.id}
              onClick={() => onOpen(p)}
              className="flex w-full items-center gap-2.5 rounded-[18px] border border-border/60 bg-card px-3 py-2.5 text-left transition-colors hover:bg-secondary/40"
            >
              <Avatar url={p.prospect_image_url} name={displayName(p)} size={38} />
              <span className="min-w-0 flex-1">
                <span className="flex items-center gap-1.5">
                  <span className="truncate text-[13.5px] font-extrabold">
                    {displayName(p)}
                  </span>
                  <span
                    className="shrink-0 rounded-full px-1.5 py-0.5 text-[9.5px] font-black uppercase tracking-wide"
                    style={{
                      color: p.status === "passed" ? "#EF4444" : stage.color,
                      backgroundColor: `${p.status === "passed" ? "#EF4444" : stage.color}18`,
                    }}
                  >
                    {p.status === "passed" ? "Passed" : stage.label}
                  </span>
                </span>
                <span className="mt-0.5 block truncate text-[11px] text-muted-foreground">
                  {[p.niche, p.location, p.source].filter(Boolean).join(" · ") ||
                    "No details yet"}
                  {(p.tags ?? []).length > 0
                    ? ` · ${(p.tags ?? []).map((t) => `#${t}`).join(" ")}`
                    : ""}
                </span>
              </span>
              {compositeScore(p) != null && (
                <span className="flex shrink-0 items-center gap-0.5 rounded-full bg-amber-500/12 px-2 py-1 text-[10.5px] font-bold text-amber-500">
                  <Star className="h-3 w-3 fill-amber-500" />
                  {compositeScore(p)}
                </span>
              )}
              <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
            </button>
          );
        })}
        {list.length === 0 && (
          <div className="rounded-[22px] border border-border/60 bg-card px-6 py-10 text-center">
            <Users className="mx-auto h-8 w-8 text-muted-foreground/50" />
            <p className="mt-2 text-[14px] font-extrabold">
              {query.trim() || tag ? "No one matches" : "Your pool is empty"}
            </p>
            <p className="mx-auto mt-1 max-w-xs text-[12px] leading-relaxed text-muted-foreground">
              {query.trim() || tag
                ? "Try another search or clear the tag filter."
                : "Add your first person — every great roster started with one name."}
            </p>
          </div>
        )}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Inbox — applications + meeting requests feed the pipeline
// ─────────────────────────────────────────────────────────────────────────────

function InboxView({
  userId,
  requests,
  loading,
  decidePending,
  onDecide,
}: {
  userId: string;
  requests: MeetingRequest[];
  loading: boolean;
  decidePending: boolean;
  onDecide: (
    id: string,
    decision: "approved" | "denied",
    meetingLink?: string
  ) => void;
}) {
  const [links, setLinks] = useState<Record<string, string>>({});
  const pending = requests.filter((r) => r.status === "pending");
  const decided = requests.filter((r) => r.status !== "pending").slice(0, 6);

  return (
    <div className="space-y-5">
      <div data-tour="rec-inbox-requests">
        <p className="mb-2 text-[10.5px] font-black uppercase tracking-[0.16em] text-muted-foreground">
          Meeting requests · {pending.length} waiting
        </p>
        {loading && (
          <div className="h-20 animate-pulse rounded-[18px] border border-border/40 bg-muted/40" />
        )}
        {!loading && pending.length === 0 && (
          <div className="rounded-[18px] border border-border/60 bg-card px-4 py-6 text-center">
            <Video className="mx-auto h-6 w-6 text-muted-foreground/50" />
            <p className="mt-1.5 text-[12.5px] font-bold">No requests waiting</p>
            <p className="mx-auto mt-0.5 max-w-xs text-[11px] text-muted-foreground">
              When someone books a call from your featured card, it lands here.
            </p>
          </div>
        )}
        <div className="space-y-2.5">
          {pending.map((r) => (
            <div
              key={r.id}
              className="rounded-[18px] border border-border/60 bg-card p-3.5"
            >
              <div className="flex items-center gap-2">
                <Avatar url={null} name={r.requester_name} size={34} />
                <div className="min-w-0 flex-1">
                  <p className="truncate text-[13.5px] font-extrabold">
                    {r.requester_name}
                  </p>
                  <p className="truncate text-[11px] text-muted-foreground">
                    {r.requester_email} · wants{" "}
                    {new Date(r.requested_time).toLocaleString(undefined, {
                      month: "short",
                      day: "numeric",
                      hour: "numeric",
                      minute: "2-digit",
                    })}
                  </p>
                </div>
              </div>
              {r.message && (
                <p className="mt-2 rounded-xl bg-muted/40 px-3 py-2 text-[12px] leading-snug text-muted-foreground">
                  “{r.message}”
                </p>
              )}
              <div className="mt-2.5 flex flex-wrap items-center gap-2">
                <input
                  value={links[r.id] ?? ""}
                  onChange={(e) =>
                    setLinks((l) => ({ ...l, [r.id]: e.target.value }))
                  }
                  placeholder="Paste a meeting link…"
                  className="h-9 min-w-0 flex-1 rounded-full border border-border/60 bg-background px-3.5 text-[12px] outline-none"
                />
                <button
                  onClick={() =>
                    setLinks((l) => ({ ...l, [r.id]: newMeetLink() }))
                  }
                  className="h-9 shrink-0 rounded-full bg-emerald-500/12 px-3 text-[11.5px] font-extrabold text-emerald-600"
                >
                  Use Whisper Meet
                </button>
                <button
                  onClick={() => {
                    const link = (links[r.id] ?? "").trim();
                    if (!/^https:\/\//.test(link)) {
                      toast.error("Add a meeting link first (https://…)");
                      return;
                    }
                    onDecide(r.id, "approved", link);
                  }}
                  disabled={decidePending}
                  className="h-9 shrink-0 rounded-full px-4 text-[11.5px] font-extrabold text-white disabled:opacity-50"
                  style={{ backgroundColor: ACCENT }}
                >
                  Approve
                </button>
                <button
                  onClick={() => onDecide(r.id, "denied")}
                  disabled={decidePending}
                  className="h-9 shrink-0 rounded-full bg-muted/70 px-3.5 text-[11.5px] font-bold text-muted-foreground disabled:opacity-50"
                >
                  Deny
                </button>
              </div>
            </div>
          ))}
        </div>
        {decided.length > 0 && (
          <div className="mt-2.5 space-y-1.5">
            {decided.map((r) => (
              <div
                key={r.id}
                className="flex items-center gap-2 rounded-[14px] border border-border/50 bg-card/50 px-3 py-2"
              >
                <span className="min-w-0 flex-1 truncate text-[11.5px] text-muted-foreground">
                  {r.requester_name} ·{" "}
                  {r.created_at ? timeAgo(r.created_at) : ""}
                </span>
                <span
                  className={`shrink-0 rounded-full px-2 py-0.5 text-[9.5px] font-black uppercase ${
                    r.status === "approved"
                      ? "bg-emerald-500/12 text-emerald-600"
                      : "bg-red-500/12 text-red-500"
                  }`}
                >
                  {r.status}
                </span>
              </div>
            ))}
          </div>
        )}
      </div>

      <div>
        <p className="mb-2 text-[10.5px] font-black uppercase tracking-[0.16em] text-muted-foreground">
          Applications
        </p>
        <RecruiterApplications recruiterId={userId} />
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Insights — sources, speed, funnel, goal
// ─────────────────────────────────────────────────────────────────────────────

function InsightsView({
  prospects,
  promotions,
  target,
  onSaveTarget,
}: {
  prospects: Prospect[];
  promotions: RecruiterPromotion[];
  target: {
    target_coach: number;
    target_athlete: number;
    target_creator: number;
  } | null;
  onSaveTarget: (coach: number, athlete: number, creator: number) => Promise<void>;
}) {
  const [editGoal, setEditGoal] = useState<boolean>(false);
  const [gc, setGc] = useState<string>(String(target?.target_coach ?? 2));
  const [ga, setGa] = useState<string>(String(target?.target_athlete ?? 3));
  const [gv, setGv] = useState<string>(String(target?.target_creator ?? 2));

  const signedSet = useMemo(
    () =>
      new Set(
        promotions.map((p) => (p.promoted_username ?? "").toLowerCase())
      ),
    [promotions]
  );

  const monthStart = useMemo(() => {
    const d = new Date();
    return new Date(d.getFullYear(), d.getMonth(), 1).getTime();
  }, []);
  const signedThisMonth = promotions.filter(
    (p) => p.created_at && new Date(p.created_at).getTime() >= monthStart
  ).length;
  const goalTotal =
    (target?.target_coach ?? 2) +
    (target?.target_athlete ?? 3) +
    (target?.target_creator ?? 2);

  // Sources — count + signed per source.
  const sources = useMemo(() => {
    const map = new Map<string, { total: number; signed: number }>();
    for (const p of prospects) {
      const key = (p.source ?? "Direct").trim() || "Direct";
      const cur = map.get(key) ?? { total: 0, signed: 0 };
      cur.total += 1;
      if (
        p.prospect_username &&
        signedSet.has(p.prospect_username.toLowerCase())
      ) {
        cur.signed += 1;
      }
      map.set(key, cur);
    }
    return Array.from(map.entries())
      .map(([source, v]) => ({ source, ...v }))
      .sort((a, b) => b.total - a.total)
      .slice(0, 7);
  }, [prospects, signedSet]);
  const maxSource = Math.max(1, ...sources.map((s) => s.total));

  // Speed — average days from added → signed for matched prospects.
  const avgDaysToSign = useMemo(() => {
    const days: number[] = [];
    for (const promo of promotions) {
      const match = prospects.find(
        (p) =>
          (p.prospect_username ?? "").toLowerCase() ===
          (promo.promoted_username ?? "").toLowerCase()
      );
      if (match?.created_at && promo.created_at) {
        const d =
          (new Date(promo.created_at).getTime() -
            new Date(match.created_at).getTime()) /
          DAY_MS;
        if (d >= 0 && d < 365) days.push(d);
      }
    }
    if (days.length === 0) return null;
    return Math.round(days.reduce((a, b) => a + b, 0) / days.length);
  }, [prospects, promotions]);

  // 8-week signings.
  const weeks = useMemo(() => {
    const out: { label: string; count: number }[] = [];
    for (let i = 7; i >= 0; i--) {
      const start = Date.now() - (i + 1) * 7 * DAY_MS;
      const end = Date.now() - i * 7 * DAY_MS;
      const count = promotions.filter((p) => {
        const t = p.created_at ? new Date(p.created_at).getTime() : 0;
        return t >= start && t < end;
      }).length;
      out.push({ label: i === 0 ? "now" : `${i}w`, count });
    }
    return out;
  }, [promotions]);
  const maxWeek = Math.max(1, ...weeks.map((w) => w.count));

  const activeCount = prospects.filter((p) => p.status !== "passed").length;

  return (
    <div className="grid grid-cols-1 gap-3.5 lg:grid-cols-2">
      {/* Monthly goal */}
      <div className="rounded-[20px] border border-border/60 bg-card p-4">
        <div className="flex items-center justify-between">
          <p className="text-[13px] font-extrabold">This month's goal</p>
          <button
            onClick={() => setEditGoal((v) => !v)}
            className="text-[11px] font-bold text-muted-foreground hover:text-foreground"
          >
            {editGoal ? "Close" : "Edit"}
          </button>
        </div>
        <div className="mt-3 flex items-center gap-4">
          <div className="relative h-20 w-20 shrink-0">
            <svg viewBox="0 0 80 80" className="h-20 w-20 -rotate-90">
              <circle
                cx="40"
                cy="40"
                r="34"
                fill="none"
                strokeWidth="8"
                className="stroke-muted/60"
              />
              <circle
                cx="40"
                cy="40"
                r="34"
                fill="none"
                strokeWidth="8"
                stroke={ACCENT}
                strokeLinecap="round"
                strokeDasharray={`${Math.min(1, signedThisMonth / Math.max(1, goalTotal)) * 213.6} 213.6`}
              />
            </svg>
            <div className="absolute inset-0 flex flex-col items-center justify-center">
              <p className="text-[18px] font-black leading-none">
                {signedThisMonth}
              </p>
              <p className="text-[9px] font-bold text-muted-foreground">
                of {goalTotal}
              </p>
            </div>
          </div>
          <p className="text-[12px] leading-relaxed text-muted-foreground">
            {signedThisMonth >= goalTotal
              ? "Goal hit — raise the bar."
              : `${goalTotal - signedThisMonth} more signing${goalTotal - signedThisMonth === 1 ? "" : "s"} to hit this month's goal.`}
          </p>
        </div>
        {editGoal && (
          <div className="mt-3 flex flex-wrap items-end gap-2">
            {[
              { label: "Coaches", value: gc, set: setGc },
              { label: "Athletes", value: ga, set: setGa },
              { label: "Creators", value: gv, set: setGv },
            ].map((f) => (
              <label key={f.label} className="block">
                <span className="text-[9.5px] font-bold text-muted-foreground">
                  {f.label}
                </span>
                <input
                  value={f.value}
                  onChange={(e) => f.set(e.target.value)}
                  inputMode="numeric"
                  className="w-20 rounded-xl border border-border/60 bg-background px-2.5 py-2 text-[13px] outline-none"
                />
              </label>
            ))}
            <button
              onClick={() => {
                void onSaveTarget(
                  Math.max(0, Math.round(Number(gc) || 0)),
                  Math.max(0, Math.round(Number(ga) || 0)),
                  Math.max(0, Math.round(Number(gv) || 0))
                ).then(() => setEditGoal(false));
              }}
              className="h-[38px] rounded-full px-4 text-[12px] font-extrabold text-white"
              style={{ backgroundColor: ACCENT }}
            >
              Save
            </button>
          </div>
        )}
      </div>

      {/* Speed */}
      <div className="rounded-[20px] border border-border/60 bg-card p-4">
        <p className="text-[13px] font-extrabold">Speed & momentum</p>
        <div className="mt-3 grid grid-cols-2 gap-2">
          <div className="rounded-xl bg-muted/50 px-3 py-2.5">
            <p className="text-[9.5px] font-bold uppercase tracking-wide text-muted-foreground">
              Avg days to sign
            </p>
            <p className="text-[20px] font-black tabular-nums">
              {avgDaysToSign ?? "—"}
            </p>
          </div>
          <div className="rounded-xl bg-muted/50 px-3 py-2.5">
            <p className="text-[9.5px] font-bold uppercase tracking-wide text-muted-foreground">
              In play now
            </p>
            <p className="text-[20px] font-black tabular-nums">{activeCount}</p>
          </div>
        </div>
        <p className="mt-3 text-[9.5px] font-bold uppercase tracking-wide text-muted-foreground">
          Signings · last 8 weeks
        </p>
        <div className="mt-1.5 flex h-16 items-end gap-1.5">
          {weeks.map((w, i) => (
            <div key={i} className="flex flex-1 flex-col items-center gap-1">
              <div
                className="w-full rounded-t-md"
                style={{
                  height: `${Math.max(6, (w.count / maxWeek) * 100)}%`,
                  backgroundColor: w.count > 0 ? ACCENT : "var(--muted, #eee)",
                  opacity: w.count > 0 ? 1 : 0.4,
                }}
              />
              <span className="text-[8.5px] font-bold text-muted-foreground/70">
                {w.label}
              </span>
            </div>
          ))}
        </div>
      </div>

      {/* Sources */}
      <div className="rounded-[20px] border border-border/60 bg-card p-4 lg:col-span-2">
        <p className="text-[13px] font-extrabold">Where your people come from</p>
        <p className="mt-0.5 text-[11px] text-muted-foreground">
          Double down on the sources that actually sign.
        </p>
        <div className="mt-3 space-y-2.5">
          {sources.map((s) => (
            <div key={s.source}>
              <div className="flex items-center justify-between text-[11px] font-bold">
                <span>{s.source}</span>
                <span className="text-muted-foreground">
                  {s.total} added{s.signed > 0 ? ` · ${s.signed} signed` : ""}
                </span>
              </div>
              <div className="mt-1 h-2.5 overflow-hidden rounded-full bg-muted/60">
                <div
                  className="h-full rounded-full"
                  style={{
                    width: `${(s.total / maxSource) * 100}%`,
                    background: `linear-gradient(90deg, ${ACCENT}, ${ACCENT}99)`,
                  }}
                />
              </div>
            </div>
          ))}
          {sources.length === 0 && (
            <p className="py-4 text-center text-[11.5px] text-muted-foreground">
              Add people with a source and this chart builds itself.
            </p>
          )}
        </div>
      </div>

      {/* Funnel */}
      <div className="rounded-[20px] border border-border/60 bg-card p-4 lg:col-span-2">
        <p className="text-[13px] font-extrabold">Pipeline funnel</p>
        <div className="mt-3 grid grid-cols-5 gap-1.5">
          {STAGES.map((stage) => {
            const count = prospects.filter((p) => p.status === stage.id).length;
            const max = Math.max(
              1,
              ...STAGES.map(
                (s) => prospects.filter((p) => p.status === s.id).length
              )
            );
            return (
              <div key={stage.id} className="text-center">
                <div className="flex h-24 items-end justify-center">
                  <div
                    className="w-full max-w-[44px] rounded-t-lg"
                    style={{
                      height: `${Math.max(8, (count / max) * 100)}%`,
                      backgroundColor: stage.color,
                      opacity: count > 0 ? 0.9 : 0.25,
                    }}
                  />
                </div>
                <p className="mt-1 text-[10px] font-extrabold">{count}</p>
                <p className="text-[8.5px] font-bold uppercase tracking-wide text-muted-foreground">
                  {stage.label}
                </p>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Grow — invite link, QR, territories
// ─────────────────────────────────────────────────────────────────────────────

function GrowView({
  userId,
  username,
  prospects,
}: {
  userId: string;
  username: string;
  prospects: Prospect[];
}) {
  const queryClient = useQueryClient();
  const codeQuery = useQuery({
    queryKey: ["recruiter-code", userId],
    queryFn: () => fetchOrCreateReferralCode(userId, username),
  });
  const territoriesQuery = useQuery({
    queryKey: ["recruiter-territories", userId],
    queryFn: () => fetchTerritories(userId),
  });
  const [copied, setCopied] = useState<boolean>(false);
  const [tName, setTName] = useState<string>("");
  const [tRegion, setTRegion] = useState<TerritoryRegion>("southeast");
  const [tCities, setTCities] = useState<string>("");

  const territories = territoriesQuery.data ?? [];
  const link = codeQuery.data ? inviteLink(codeQuery.data.code) : "";

  const claim = useMutation({
    mutationFn: () =>
      createTerritory(userId, {
        name: tName.trim(),
        region: tRegion,
        cities: tCities,
      }),
    onSuccess: () => {
      setTName("");
      setTCities("");
      void queryClient.invalidateQueries({
        queryKey: ["recruiter-territories", userId],
      });
      toast.success("Territory claimed.");
    },
    onError: () => toast.error("Couldn't claim it. Try again."),
  });

  const remove = useMutation({
    mutationFn: (id: string) => deleteTerritory(id),
    onSuccess: () =>
      void queryClient.invalidateQueries({
        queryKey: ["recruiter-territories", userId],
      }),
  });

  const qrHref = ACTIVE_PORTAL
    ? "/recruiter/qr?portal=recruiter"
    : "/recruiter/qr";

  return (
    <div className="grid grid-cols-1 gap-3.5 lg:grid-cols-2">
      {/* Invite link */}
      <div className="rounded-[20px] border border-border/60 bg-card p-4">
        <p className="text-[13px] font-extrabold">Your invite link</p>
        <p className="mt-0.5 text-[11px] leading-snug text-muted-foreground">
          Everyone who signs up through it is credited to you — and lands in
          your Inbox as an application.
        </p>
        <div className="mt-3 flex items-center gap-2 rounded-full border border-border/60 bg-background px-3.5 py-2.5">
          <span className="min-w-0 flex-1 truncate font-mono text-[12px]">
            {link || "Generating…"}
          </span>
          <button
            onClick={() => {
              if (!link) return;
              void navigator.clipboard.writeText(link).then(() => {
                setCopied(true);
                window.setTimeout(() => setCopied(false), 1400);
              });
            }}
            aria-label="Copy invite link"
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-white"
            style={{ backgroundColor: copied ? "#22C55E" : ACCENT }}
          >
            {copied ? <Check className="h-3.5 w-3.5" /> : <Copy className="h-3.5 w-3.5" />}
          </button>
        </div>
        <Link
          to={qrHref}
          className="mt-2.5 inline-flex items-center gap-1.5 text-[12px] font-extrabold"
          style={{ color: ACCENT }}
        >
          <QrCode className="h-3.5 w-3.5" />
          Open your QR code & poster
          <ArrowRight className="h-3 w-3" />
        </Link>
      </div>

      {/* Territories */}
      <div className="rounded-[20px] border border-border/60 bg-card p-4">
        <div className="flex items-center gap-1.5">
          <MapPin className="h-4 w-4" style={{ color: ACCENT }} />
          <p className="text-[13px] font-extrabold">Your territories</p>
        </div>
        <div className="mt-2.5 space-y-2">
          {territories.map((t: Territory) => (
            <div
              key={t.id}
              className="flex items-center gap-2 rounded-[14px] border border-border/50 bg-background/60 px-3 py-2"
            >
              <span
                className="h-2.5 w-2.5 shrink-0 rounded-full"
                style={{ backgroundColor: t.color ?? ACCENT }}
              />
              <span className="min-w-0 flex-1">
                <span className="block truncate text-[12.5px] font-bold">
                  {t.name}
                </span>
                <span className="block truncate text-[10px] text-muted-foreground">
                  {TERRITORY_REGION_LABELS[t.region]}
                  {t.cities ? ` · ${t.cities}` : ""} ·{" "}
                  {prospectCountForTerritory(t, prospects)} prospect
                  {prospectCountForTerritory(t, prospects) === 1 ? "" : "s"}
                </span>
              </span>
              <button
                onClick={() => remove.mutate(t.id)}
                aria-label="Release territory"
                className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-muted/70 text-muted-foreground transition-colors hover:text-red-500"
              >
                <Trash2 className="h-3 w-3" />
              </button>
            </div>
          ))}
          {territories.length === 0 && (
            <p className="py-2 text-[11.5px] text-muted-foreground">
              Claim the regions you cover — prospects with matching locations
              count toward each one.
            </p>
          )}
        </div>
        <div className="mt-3 space-y-2">
          <input
            value={tName}
            onChange={(e) => setTName(e.target.value)}
            placeholder="Territory name (e.g. Atlanta metro)"
            className={inputClass}
          />
          <div className="flex gap-2">
            <select
              value={tRegion}
              onChange={(e) => setTRegion(e.target.value as TerritoryRegion)}
              className={`${inputClass} w-auto flex-1`}
            >
              {Object.entries(TERRITORY_REGION_LABELS).map(([id, label]) => (
                <option key={id} value={id}>
                  {label}
                </option>
              ))}
            </select>
            <button
              onClick={() => {
                if (!tName.trim()) {
                  toast.error("Name the territory first.");
                  return;
                }
                claim.mutate();
              }}
              disabled={claim.isPending}
              className="shrink-0 rounded-full px-4 text-[12px] font-extrabold text-white disabled:opacity-50"
              style={{ backgroundColor: ACCENT }}
            >
              Claim
            </button>
          </div>
          <input
            value={tCities}
            onChange={(e) => setTCities(e.target.value)}
            placeholder="Cities, comma-separated (optional)"
            className={inputClass}
          />
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Person drawer — the whole relationship in one panel
// ─────────────────────────────────────────────────────────────────────────────

function PersonDrawer({
  prospect,
  recruiterId,
  recruiterUsername,
  promotions,
  v4Ready,
  onClose,
  onChanged,
  onStage,
}: {
  prospect: Prospect;
  recruiterId: string;
  recruiterUsername: string;
  promotions: RecruiterPromotion[];
  v4Ready: boolean;
  onClose: () => void;
  onChanged: () => void;
  onStage: (status: ProspectStatus) => void;
}) {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const p = prospect;
  const [nextType, setNextType] = useState<string>(
    NEXT_ACTION_PRESETS.find((a) => a.label === (p.next_action ?? ""))?.id ??
      "dm"
  );
  const [nextDue, setNextDue] = useState<string>(p.next_action_due ?? "");
  const [tagDraft, setTagDraft] = useState<string>("");
  const [noteDraft, setNoteDraft] = useState<string>("");
  const [logKind, setLogKind] = useState<ActivityKind>("note");
  const [signRole, setSignRole] = useState<PromotableRole>(
    p.suggested_role === "athlete" ? "creator" : (p.suggested_role ?? "creator")
  );

  const activitiesQuery = useQuery({
    queryKey: ["prospect-activities", p.id],
    enabled: v4Ready,
    queryFn: () => fetchProspectActivities(p.id),
  });
  const activities = activitiesQuery.data ?? [];

  const isSigned = promotions.some(
    (promo) =>
      (promo.promoted_username ?? "").toLowerCase() ===
      (p.prospect_username ?? "__none__").toLowerCase()
  );

  const timeline = useMemo(() => {
    const fromLog = (p.contact_log ?? []).map((e, i) => ({
      id: `log-${i}`,
      kind: e.method as ActivityKind,
      body: e.note,
      created_at: e.date,
    }));
    const merged: { id: string; kind: string; body: string; created_at: string | null }[] =
      [
        ...activities.map((a: ProspectActivity) => ({
          id: a.id,
          kind: a.kind,
          body: a.body,
          created_at: a.created_at,
        })),
        ...fromLog,
      ];
    return merged
      .sort(
        (a, b) =>
          new Date(b.created_at ?? 0).getTime() -
          new Date(a.created_at ?? 0).getTime()
      )
      .slice(0, 30);
  }, [activities, p.contact_log]);

  const refreshActivities = (): void => {
    void queryClient.invalidateQueries({
      queryKey: ["prospect-activities", p.id],
    });
  };

  const requireV4 = (): boolean => {
    if (!v4Ready) {
      toast.error("Run supabase/recruiting-v4.sql first.");
      return false;
    }
    return true;
  };

  const saveNext = async (): Promise<void> => {
    if (!requireV4()) return;
    const preset = NEXT_ACTION_PRESETS.find((a) => a.id === nextType);
    try {
      await updateProspect(p.id, {
        next_action: preset?.label ?? "Follow up",
        next_action_due: nextDue || todayStr(),
      });
      onChanged();
      toast.success("Next step set.");
    } catch {
      toast.error("Couldn't save the next step.");
    }
  };

  const setScore = async (criterion: string, value: number): Promise<void> => {
    if (!requireV4()) return;
    const next = { ...(p.scorecard ?? {}) };
    next[criterion] = next[criterion] === value ? 0 : value;
    try {
      await updateProspect(p.id, { scorecard: next });
      onChanged();
    } catch {
      toast.error("Couldn't save the score.");
    }
  };

  const addTag = async (): Promise<void> => {
    if (!requireV4()) return;
    const t = tagDraft.trim().replace(/^#/, "").toLowerCase();
    if (!t) return;
    const tags = Array.from(new Set([...(p.tags ?? []), t])).slice(0, 8);
    setTagDraft("");
    try {
      await updateProspect(p.id, { tags });
      onChanged();
    } catch {
      toast.error("Couldn't add the tag.");
    }
  };

  const removeTag = async (t: string): Promise<void> => {
    try {
      await updateProspect(p.id, {
        tags: (p.tags ?? []).filter((x) => x !== t),
      });
      onChanged();
    } catch {
      /* noop */
    }
  };

  const logTouch = async (): Promise<void> => {
    if (!requireV4()) return;
    const body = noteDraft.trim();
    if (!body) return;
    setNoteDraft("");
    try {
      await addProspectActivity(recruiterId, p.id, logKind, body);
      onChanged();
      refreshActivities();
    } catch {
      toast.error("Couldn't log that.");
    }
  };

  const sign = async (): Promise<void> => {
    let promotedId = p.prospect_user_id;
    let promotedUsername = p.prospect_username ?? "";
    if (!promotedId) {
      const uname = cleanHandle(p.prospect_username);
      if (!uname) {
        toast.error("Add their Whisper @username first (edit below).");
        return;
      }
      const { data } = await supabase
        .from("whisper_profiles")
        .select("user_id, username")
        .ilike("username", uname)
        .limit(1)
        .maybeSingle();
      const found = data as { user_id: string; username: string } | null;
      if (!found) {
        toast.error(`No Whisper account found for @${uname}.`);
        return;
      }
      promotedId = found.user_id;
      promotedUsername = found.username;
      await updateProspect(p.id, { prospect_user_id: promotedId });
    }
    try {
      await promoteUser({
        recruiterId,
        recruiterUsername,
        promotedId,
        promotedUsername,
        role: signRole,
      });
      if (v4Ready) {
        try {
          await addProspectActivity(
            recruiterId,
            p.id,
            "stage",
            `Signed as ${signRole} 🎉`
          );
        } catch {
          /* best effort */
        }
      }
      onChanged();
      refreshActivities();
      toast.success(`Signed as ${signRole} 🎉`);
    } catch {
      toast.error("Couldn't sign them. Try again.");
    }
  };

  const kindIcon = (kind: string): React.ReactNode => {
    if (kind === "call") return <Video className="h-3 w-3" />;
    if (kind === "dm" || kind === "message")
      return <MessageCircle className="h-3 w-3" />;
    if (kind === "meeting") return <CalendarCheck className="h-3 w-3" />;
    if (kind === "stage") return <ArrowRight className="h-3 w-3" />;
    return <Pencil className="h-3 w-3" />;
  };

  return (
    <div className="fixed inset-0 z-[60]">
      <button
        aria-label="Close"
        onClick={onClose}
        className="absolute inset-0 bg-black/45 backdrop-blur-[2px]"
      />
      <div className="absolute inset-y-0 right-0 flex w-full max-w-[430px] flex-col overflow-hidden border-l border-border/60 bg-background shadow-2xl">
        {/* Header */}
        <div className="flex items-center gap-3 border-b border-border/60 px-4 py-3.5">
          <Avatar url={p.prospect_image_url} name={displayName(p)} size={44} />
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-1.5">
              <p className="truncate text-[15.5px] font-extrabold">
                {displayName(p)}
              </p>
              {isSigned && (
                <span className="shrink-0 rounded-full bg-emerald-500/12 px-1.5 py-0.5 text-[9px] font-black uppercase text-emerald-600">
                  Signed
                </span>
              )}
            </div>
            <p className="truncate text-[11.5px] text-muted-foreground">
              {[
                p.prospect_username ? `@${p.prospect_username}` : null,
                p.niche,
                p.location,
              ]
                .filter(Boolean)
                .join(" · ") || "No details yet"}
            </p>
          </div>
          <button
            onClick={onClose}
            aria-label="Close panel"
            className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-muted/70"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="min-h-0 flex-1 space-y-4 overflow-y-auto px-4 py-4">
          {/* Stage stepper */}
          <div>
            <p className="mb-1.5 text-[10px] font-black uppercase tracking-[0.14em] text-muted-foreground">
              Stage
            </p>
            <div className="no-scrollbar flex gap-1.5 overflow-x-auto">
              {STAGES.map((s) => (
                <button
                  key={s.id}
                  onClick={() => onStage(s.id)}
                  className="shrink-0 rounded-full px-3 py-1.5 text-[11px] font-bold transition-colors"
                  style={
                    p.status === s.id
                      ? { backgroundColor: s.color, color: "#fff" }
                      : {
                          backgroundColor: `${s.color}14`,
                          color: s.color,
                        }
                  }
                >
                  {s.label}
                </button>
              ))}
              <button
                onClick={() => onStage("passed")}
                className={`shrink-0 rounded-full px-3 py-1.5 text-[11px] font-bold ${
                  p.status === "passed"
                    ? "bg-red-500 text-white"
                    : "bg-red-500/10 text-red-500"
                }`}
              >
                Pass
              </button>
            </div>
          </div>

          <RecruiterClientProfile key={`${recruiterId}:${p.id}`} owner={recruiterId} prospect={p} />

          {/* Contact chips */}
          <div className="flex flex-wrap gap-1.5">
            {p.instagram && (
              <a
                href={`https://instagram.com/${cleanHandle(p.instagram)}`}
                target="_blank"
                rel="noreferrer"
                className="flex items-center gap-1 rounded-full bg-muted/70 px-2.5 py-1.5 text-[11px] font-bold text-foreground/80 hover:text-foreground"
              >
                <Instagram className="h-3 w-3" />@{cleanHandle(p.instagram)}
              </a>
            )}
            {p.tiktok && (
              <a
                href={`https://www.tiktok.com/@${cleanHandle(p.tiktok)}`}
                target="_blank"
                rel="noreferrer"
                className="flex items-center gap-1 rounded-full bg-muted/70 px-2.5 py-1.5 text-[11px] font-bold text-foreground/80 hover:text-foreground"
              >
                <Music2 className="h-3 w-3" />@{cleanHandle(p.tiktok)}
              </a>
            )}
            {p.prospect_user_id && p.prospect_username && (
              <button
                onClick={() =>
                  navigate(
                    `/messages?to=${p.prospect_user_id}&u=${encodeURIComponent(p.prospect_username ?? "")}`
                  )
                }
                className="flex items-center gap-1 rounded-full px-2.5 py-1.5 text-[11px] font-extrabold text-white"
                style={{ backgroundColor: ACCENT }}
              >
                <Send className="h-3 w-3" />
                DM on Whisper
              </button>
            )}
            {p.source && (
              <span className="rounded-full bg-muted/50 px-2.5 py-1.5 text-[10.5px] font-bold text-muted-foreground">
                via {p.source}
              </span>
            )}
          </div>

          {/* Next action */}
          <div className="rounded-[16px] border border-border/60 bg-card p-3">
            <p className="text-[11.5px] font-extrabold">Next step</p>
            <div className="no-scrollbar mt-2 flex gap-1.5 overflow-x-auto">
              {NEXT_ACTION_PRESETS.map((a) => (
                <button
                  key={a.id}
                  onClick={() => setNextType(a.id)}
                  className={pillClass(nextType === a.id)}
                >
                  {a.label}
                </button>
              ))}
            </div>
            <div className="mt-2 flex items-center gap-2">
              <input
                type="date"
                value={nextDue}
                onChange={(e) => setNextDue(e.target.value)}
                className={`${inputClass} flex-1`}
              />
              <button
                onClick={() => void saveNext()}
                className="h-[42px] shrink-0 rounded-full px-4 text-[12px] font-extrabold text-white"
                style={{ backgroundColor: ACCENT }}
              >
                Set
              </button>
            </div>
            {p.next_action && (
              <p className="mt-1.5 text-[10.5px] text-muted-foreground">
                Current: {p.next_action}
                {p.next_action_due ? ` · ${dueLabel(p.next_action_due)}` : ""}
              </p>
            )}
          </div>

          {/* Scorecard */}
          <div className="rounded-[16px] border border-border/60 bg-card p-3">
            <div className="flex items-center justify-between">
              <p className="text-[11.5px] font-extrabold">Scorecard</p>
              {compositeScore(p) != null && (
                <span className="flex items-center gap-1 rounded-full bg-amber-500/12 px-2 py-0.5 text-[10.5px] font-black text-amber-500">
                  <Star className="h-3 w-3 fill-amber-500" />
                  {compositeScore(p)} / 5
                </span>
              )}
            </div>
            <div className="mt-2 space-y-1.5">
              {SCORECARD_CRITERIA.map((c) => {
                const value = (p.scorecard ?? {})[c.id] ?? 0;
                return (
                  <div key={c.id} className="flex items-center gap-2">
                    <span className="w-24 shrink-0 text-[11px] font-bold text-muted-foreground">
                      {c.label}
                    </span>
                    <div className="flex gap-0.5">
                      {[1, 2, 3, 4, 5].map((n) => (
                        <button
                          key={n}
                          onClick={() => void setScore(c.id, n)}
                          aria-label={`${c.label} ${n} of 5`}
                          className="p-0.5 transition-transform active:scale-90"
                        >
                          <Star
                            className="h-4 w-4"
                            style={{
                              color: n <= value ? "#F5B23C" : "#9aa0a655",
                              fill: n <= value ? "#F5B23C" : "transparent",
                            }}
                          />
                        </button>
                      ))}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>

          {/* Tags */}
          <div className="rounded-[16px] border border-border/60 bg-card p-3">
            <p className="text-[11.5px] font-extrabold">Tags</p>
            <div className="mt-2 flex flex-wrap gap-1.5">
              {(p.tags ?? []).map((t) => (
                <span
                  key={t}
                  className="flex items-center gap-1 rounded-full px-2.5 py-1 text-[10.5px] font-bold"
                  style={{ color: ACCENT, backgroundColor: `${ACCENT}12` }}
                >
                  #{t}
                  <button
                    onClick={() => void removeTag(t)}
                    aria-label={`Remove ${t}`}
                  >
                    <X className="h-2.5 w-2.5" />
                  </button>
                </span>
              ))}
              <input
                value={tagDraft}
                onChange={(e) => setTagDraft(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") void addTag();
                }}
                placeholder="+ add tag"
                className="h-7 w-24 rounded-full border border-dashed border-border/70 bg-transparent px-2.5 text-[10.5px] outline-none"
              />
            </div>
          </div>

          {/* Timeline */}
          <div className="rounded-[16px] border border-border/60 bg-card p-3">
            <p className="text-[11.5px] font-extrabold">Timeline</p>
            <div className="mt-2 flex items-center gap-1.5">
              <select
                value={logKind}
                onChange={(e) => setLogKind(e.target.value as ActivityKind)}
                className="h-9 shrink-0 rounded-full border border-border/60 bg-background px-2.5 text-[11px] font-bold outline-none"
              >
                <option value="note">Note</option>
                <option value="dm">DM</option>
                <option value="call">Call</option>
                <option value="meeting">Meeting</option>
              </select>
              <input
                value={noteDraft}
                onChange={(e) => setNoteDraft(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") void logTouch();
                }}
                placeholder="Log a touchpoint…"
                className="h-9 min-w-0 flex-1 rounded-full border border-border/60 bg-background px-3 text-[11.5px] outline-none"
              />
              <button
                onClick={() => void logTouch()}
                aria-label="Log"
                className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-white"
                style={{ backgroundColor: ACCENT }}
              >
                <Plus className="h-4 w-4" />
              </button>
            </div>
            <div className="mt-2.5 space-y-2">
              {timeline.map((t) => (
                <div key={t.id} className="flex gap-2">
                  <span
                    className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full"
                    style={{ backgroundColor: `${ACCENT}12`, color: ACCENT }}
                  >
                    {kindIcon(t.kind)}
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="whitespace-pre-wrap break-words text-[11.5px] leading-snug">
                      {t.body}
                    </p>
                    <p className="text-[9.5px] text-muted-foreground">
                      {t.created_at ? timeAgo(t.created_at) : ""}
                    </p>
                  </div>
                </div>
              ))}
              {timeline.length === 0 && (
                <p className="py-2 text-[11px] text-muted-foreground">
                  {v4Ready
                    ? "No touchpoints yet — log the first one above."
                    : "Run supabase/recruiting-v4.sql to unlock the timeline."}
                </p>
              )}
            </div>
          </div>

          {/* Sign */}
          <div className="rounded-[16px] border border-emerald-500/40 bg-emerald-500/5 p-3">
            <p className="text-[11.5px] font-extrabold">
              {isSigned ? "Signed ✓" : "Sign them"}
            </p>
            {!isSigned && (
              <div className="mt-2 flex items-center gap-2">
                <select
                  value={signRole}
                  onChange={(e) => setSignRole(e.target.value as PromotableRole)}
                  className="h-10 flex-1 rounded-xl border border-border/60 bg-background px-2.5 text-[12px] font-bold outline-none"
                >
                  <option value="creator">As a creator</option>
                  <option value="coach">As a coach</option>
                </select>
                <button
                  onClick={() => void sign()}
                  className="h-10 shrink-0 rounded-full bg-emerald-500 px-4 text-[12.5px] font-extrabold text-white transition-transform active:scale-95"
                >
                  <span className="flex items-center gap-1">
                    <UserCheck className="h-3.5 w-3.5" />
                    Sign
                  </span>
                </button>
              </div>
            )}
            <p className="mt-1.5 text-[10px] leading-snug text-muted-foreground">
              Signing flips their role badge on Whisper and counts toward your
              monthly goal.
            </p>
          </div>

          {/* Danger */}
          <button
            onClick={() => {
              if (window.confirm(`Remove ${displayName(p)} from your pipeline?`)) {
                void deleteProspect(p.id).then(() => {
                  onClose();
                  onChanged();
                });
              }
            }}
            className="flex items-center gap-1.5 text-[11.5px] font-bold text-red-500/80 hover:text-red-500"
          >
            <Trash2 className="h-3.5 w-3.5" />
            Remove from pipeline
          </button>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Add person
// ─────────────────────────────────────────────────────────────────────────────

function AddPersonSheet({
  pending,
  onClose,
  onCreate,
}: {
  pending: boolean;
  onClose: () => void;
  onCreate: (input: {
    name: string;
    username: string;
    instagram: string;
    tiktok: string;
    niche: string;
    location: string;
    source: string;
    role: PromotableRole | "";
  }) => void;
}) {
  const [name, setName] = useState<string>("");
  const [username, setUsername] = useState<string>("");
  const [instagram, setInstagram] = useState<string>("");
  const [tiktok, setTiktok] = useState<string>("");
  const [niche, setNiche] = useState<string>("");
  const [location, setLocation] = useState<string>("");
  const [source, setSource] = useState<string>("Scouted");
  const [role, setRole] = useState<PromotableRole | "">("");

  return (
    <div
      className="fixed inset-0 z-[60] flex items-end justify-center bg-black/55 p-4 backdrop-blur-sm sm:items-center"
      onClick={onClose}
    >
      <div
        className="max-h-[88vh] w-full max-w-md overflow-y-auto rounded-[22px] border border-border/60 bg-background p-4 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between">
          <p className="text-[15px] font-extrabold">Add a person</p>
          <button
            onClick={onClose}
            aria-label="Close"
            className="flex h-8 w-8 items-center justify-center rounded-full bg-muted/70"
          >
            <X className="h-4 w-4" />
          </button>
        </div>
        <div className="mt-3 space-y-2.5">
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Name"
            className={inputClass}
          />
          <div className="flex gap-2">
            <input
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              placeholder="Whisper @username (if they have one)"
              className={inputClass}
            />
          </div>
          <div className="flex gap-2">
            <input
              value={instagram}
              onChange={(e) => setInstagram(e.target.value)}
              placeholder="Instagram"
              className={inputClass}
            />
            <input
              value={tiktok}
              onChange={(e) => setTiktok(e.target.value)}
              placeholder="TikTok"
              className={inputClass}
            />
          </div>
          <div className="flex gap-2">
            <input
              value={niche}
              onChange={(e) => setNiche(e.target.value)}
              placeholder="Niche (e.g. Powerlifting)"
              className={inputClass}
            />
            <input
              value={location}
              onChange={(e) => setLocation(e.target.value)}
              placeholder="City"
              className={inputClass}
            />
          </div>
          <div>
            <p className="mb-1.5 text-[10px] font-black uppercase tracking-[0.14em] text-muted-foreground">
              Where'd you find them?
            </p>
            <div className="no-scrollbar flex gap-1.5 overflow-x-auto">
              {SOURCE_OPTIONS.map((s) => (
                <button
                  key={s}
                  onClick={() => setSource(s)}
                  className={pillClass(source === s)}
                >
                  {s}
                </button>
              ))}
            </div>
          </div>
          <div>
            <p className="mb-1.5 text-[10px] font-black uppercase tracking-[0.14em] text-muted-foreground">
              Best fit
            </p>
            <div className="flex gap-1.5">
              {(["creator", "coach"] as PromotableRole[]).map((r) => (
                <button
                  key={r}
                  onClick={() => setRole(role === r ? "" : r)}
                  className={pillClass(role === r)}
                >
                  {r[0].toUpperCase() + r.slice(1)}
                </button>
              ))}
            </div>
          </div>
          <button
            onClick={() => {
              if (!name.trim() && !username.trim() && !instagram.trim()) {
                toast.error("Give them at least a name or a handle.");
                return;
              }
              onCreate({
                name,
                username,
                instagram,
                tiktok,
                niche,
                location,
                source,
                role,
              });
            }}
            disabled={pending}
            className="w-full rounded-full py-3 text-[13.5px] font-extrabold text-white transition-transform active:scale-[0.98] disabled:opacity-60"
            style={{ backgroundColor: ACCENT }}
          >
            {pending ? "Adding…" : "Add to Sourced"}
          </button>
        </div>
      </div>
    </div>
  );
}
