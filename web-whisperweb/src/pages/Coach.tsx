import { useEffect, useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import {
  useMutation,
  useQuery,
  useQueryClient,
} from "@tanstack/react-query";
import {
  AlertTriangle,
  BadgeDollarSign,
  BookOpen,
  Check,
  ChevronRight,
  Droplets,
  Dumbbell,
  Flame,
  Leaf,
  Loader2,
  Lock,
  MessageSquareText,
  Moon,
  Plus,
  RotateCw,
  Search,
  Send,
  ShoppingCart,
  Sparkles,
  Store,
  Trash2,
  Users,
  Wand2,
  X,
  Zap,
} from "lucide-react";
import { toast } from "sonner";

import { Header } from "@/components/Header";
import { Avatar } from "@/components/Avatar";
import { useAuth } from "@/hooks/useAuth";
import { sendMessage } from "@/lib/api";
import {
  blankProgram,
  CoachProgram,
  CoachRequest,
  deleteProgram,
  encodeProgramForDM,
  fetchCoachRequests,
  fetchMyPrograms,
  fetchPaidClientIds,
  saveProgram,
  updateCoachRequestStatus,
} from "@/lib/coach";
import { fetchCoachRate } from "@/lib/coachPay";
import { ProgramEditor } from "@/components/ProgramEditor";
import { CoachClientDetail } from "@/components/CoachClientDetail";
import { JasperAnalysisDock } from "@/components/JasperAnalysisDock";
import { PlanAutomationDialog } from "@/components/PlanAutomationDialog";
import {
  fetchOwnPlans,
  marketplacePublish,
  type JasperOwnPlan,
} from "@/lib/jasperConnect";
import { useCoachPreviews, type CoachPreview } from "@/hooks/useCoachPreviews";
import { jasperReadinessColor } from "@/lib/jasperIntel";
import {
  JasperDietBuilderPanel,
  JasperDietPlanPanel,
  JasperGroceryPanel,
  JasperMarketplacePanel,
  JasperRecipesPanel,
  JasperWaterPanel,
} from "@/components/JasperPanels";
import {
  EmberGlowCard,
  EmberGlowIcon,
  EmberKicker,
  EmberPlanKeyframes,
  JasperDietPlanGlowCard,
  JasperProgramDetailModal,
  JasperWorkoutPlanCard,
  parsePlanShape,
  type EmberPublishState,
} from "@/components/JasperPlanCards";
import { JASPER_EMBER_GRADIENT } from "@/lib/jasperIntel";
import { cn } from "@/lib/utils";
import { ACTIVE_PORTAL } from "@/lib/portal";

/** Coach identity accent — used ONLY for the studio kicker, matching iOS. */
const COACH_ACCENT = "#fa7321";

function fmtSleepShort(seconds: number | null): string | null {
  if (!seconds || seconds <= 0) return null;
  const h = Math.floor(seconds / 3600);
  const m = Math.round((seconds % 3600) / 60);
  return `${h}h ${m.toString().padStart(2, "0")}m`;
}

function greeting(): string {
  const hour = new Date().getHours();
  if (hour < 12) return "Good morning";
  if (hour < 17) return "Good afternoon";
  if (hour < 22) return "Good evening";
  return "Welcome back";
}

export default function Coach() {
  const { user, profile } = useAuth();
  const userId = user?.id ?? "";
  const username = profile?.username ?? "you";
  const queryClient = useQueryClient();
  const [searchParams, setSearchParams] = useSearchParams();

  // Standalone coach portal (coaches. subdomain or ?portal=coach): the
  // sidebar drives ONE category at a time via ?tab= — home, clients,
  // programs, selling. The main-site /coach page keeps its single scroll.
  const inPortal = ACTIVE_PORTAL === "coach";
  const portalTabParam = searchParams.get("tab");
  const coachTab: "home" | "clients" | "programs" | "selling" =
    inPortal &&
    (portalTabParam === "clients" ||
      portalTabParam === "programs" ||
      portalTabParam === "selling")
      ? portalTabParam
      : "home";
  const showSection = (
    section: "home" | "clients" | "programs" | "selling"
  ): boolean => !inPortal || coachTab === section;
  /** Portal links keep the ?portal= flag so hard refreshes stay in portal. */
  const portalHref = (tab: string): string => {
    const sp = new URLSearchParams();
    const flag = searchParams.get("portal");
    if (flag) sp.set("portal", flag);
    if (tab === "earnings") {
      const q = sp.toString();
      return `/coach/earnings${q ? `?${q}` : ""}`;
    }
    sp.set("tab", tab);
    return `/?${sp.toString()}`;
  };

  const requestsQuery = useQuery({
    queryKey: ["coach-requests", userId],
    queryFn: () => fetchCoachRequests(userId),
    enabled: !!userId,
  });

  const programsQuery = useQuery({
    queryKey: ["coach-programs", userId],
    queryFn: () => fetchMyPrograms(userId),
    enabled: !!userId,
  });

  const paidClientsQuery = useQuery({
    queryKey: ["coach-paid-clients", userId],
    queryFn: () => fetchPaidClientIds(userId),
    enabled: !!userId,
  });
  const paidClients = paidClientsQuery.data ?? new Set<string>();

  const myRateQuery = useQuery({
    queryKey: ["coach-rate", userId],
    queryFn: () => fetchCoachRate(userId),
    enabled: !!userId,
    retry: false,
  });
  const myRate = myRateQuery.data ?? null;
  const chargesClients = Boolean(
    myRate?.active && myRate.acceptingPayments && myRate.monthlyPriceCents
  );
  const isClientLocked = (clientUserId: string): boolean =>
    chargesClients && paidClientsQuery.isSuccess && !paidClients.has(clientUserId);

  const requests = requestsQuery.data;
  const pending = requests?.incoming.filter((r) => r.status === "pending") ?? [];
  const clients = useMemo(() => requests?.myClients ?? [], [requests]);
  const programs = programsQuery.data ?? [];

  const [editing, setEditing] = useState<CoachProgram | null>(null);
  const [detailClient, setDetailClient] = useState<CoachRequest | null>(null);
  const [jasperPanel, setJasperPanel] = useState<
    "marketplace" | "recipes" | "grocery" | "diet" | "dietplan" | "water" | null
  >(null);
  const [viewingProgram, setViewingProgram] = useState<JasperOwnPlan | null>(null);
  const [publishedIds, setPublishedIds] = useState<Set<string>>(new Set());
  const [publishNote, setPublishNote] = useState<string | null>(null);
  const [studioTab, setStudioTab] = useState<"training" | "diet">(() =>
    searchParams.get("tab") === "diet" ? "diet" : "training"
  );
  const [clientSearch, setClientSearch] = useState<string>("");
  /// Jasper dock quick action — the three-step plan automation wizard.
  const [automateOpen, setAutomateOpen] = useState<boolean>(false);

  // Deep link: /coach?client=<username> opens that client's live dashboard
  // (Jasper Intelligence's clientdashboard action lands here).
  useEffect(() => {
    const wanted = searchParams.get("client");
    if (!wanted || clients.length === 0) return;
    const match = clients.find(
      (c) => c.client_username.toLowerCase() === wanted.toLowerCase()
    );
    if (match) {
      setDetailClient(match);
      const next = new URLSearchParams(searchParams);
      next.delete("client");
      setSearchParams(next, { replace: true });
    }
  }, [clients, searchParams, setSearchParams]);

  const dashMap = useCoachPreviews(userId, clients.map(client => client.client_user_id), showSection("clients"));

  const needsAttention = (uid: string): boolean => {
    const dash = dashMap[uid];
    if (dash === "error") return true;
    if (!dash) return false;
    const readiness = dash.summary.readinessScore;
    const sleepQ = dash.summary.sleepQualityScore;
    return (readiness !== null && readiness < 50) || (sleepQ !== null && sleepQ < 50);
  };
  const attentionCount = clients.filter((c) => needsAttention(c.client_user_id)).length;

  // Attention-first, then freshest dashboard — exactly like iOS.
  const sortedClients = useMemo(() => {
    const filtered = clientSearch.trim()
      ? clients.filter((c) =>
          c.client_username.toLowerCase().includes(clientSearch.trim().toLowerCase())
        )
      : clients;
    return [...filtered].sort((a, b) => {
      const attA = needsAttention(a.client_user_id) ? 1 : 0;
      const attB = needsAttention(b.client_user_id) ? 1 : 0;
      if (attA !== attB) return attB - attA;
      const dashA = dashMap[a.client_user_id];
      const dashB = dashMap[b.client_user_id];
      const tA = dashA && dashA !== "error" ? dashA.fetchedAt : 0;
      const tB = dashB && dashB !== "error" ? dashB.fetchedAt : 0;
      return tB - tA;
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clients, clientSearch, dashMap]);

  // The studio reads THE API — programs + diet plans live off the coach's
  // own Jasper (GET /v1/programs / /v1/diet_plans), publishable in one tap.
  const ownPlansQuery = useQuery({
    queryKey: ["jasper-own-plans", userId],
    queryFn: fetchOwnPlans,
    enabled: !!userId,
    retry: false,
  });

  const publishPlan = useMutation({
    mutationFn: (plan: JasperOwnPlan) =>
      marketplacePublish({
        kind: plan.isProgram ? "program" : "diet_plan",
        title: plan.name,
        summary: plan.detail,
        goal: plan.goal || (plan.isProgram ? "General Fitness" : "Maintain Weight"),
        topLevel: plan.topLevel,
        payload: plan.payload,
      }),
    onSuccess: (_d, plan) => {
      setPublishNote(null);
      setPublishedIds((prev) => {
        const next = new Set(prev);
        next.add(plan.id);
        return next;
      });
      toast("Published — re-publishing the same title updates in place.");
    },
    onError: (e) => {
      const message = e instanceof Error ? e.message : "Publish failed — is this account connected to Jasper?";
      setPublishNote(message);
      toast(message);
    },
  });

  const respond = useMutation({
    mutationFn: ({ id, status }: { id: string; status: "accepted" | "declined" }) =>
      updateCoachRequestStatus(id, status),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["coach-requests", userId] });
    },
  });

  const removeProgram = useMutation({
    mutationFn: (id: string) => deleteProgram(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["coach-programs", userId] });
      toast("Program deleted");
    },
  });

  const persistProgram = useMutation({
    mutationFn: (p: CoachProgram) => saveProgram(p),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["coach-programs", userId] });
      setEditing(null);
      toast("Program saved");
    },
    onError: () => toast("Couldn't save program"),
  });

  const sendProgram = useMutation({
    mutationFn: async ({ program, client }: { program: CoachProgram; client: CoachRequest }) => {
      await sendMessage(
        userId,
        username,
        client.client_user_id,
        client.client_username,
        encodeProgramForDM(program)
      );
    },
    onSuccess: () => toast("Program sent to client"),
    onError: () => toast("Couldn't send program"),
  });

  const rateLabel = myRate?.monthlyPriceCents
    ? `$${Math.round(myRate.monthlyPriceCents / 100)}/mo`
    : "Free";

  const own = ownPlansQuery.data;
  const apiRows = studioTab === "training" ? own?.programs ?? [] : own?.dietPlans ?? [];

  return (
    <div>
      {!inPortal && <Header title="Coach Studio" />}

      {/* The meeting-style Jasper dock — a live roster read plus the coach
          quick actions: attention lens, check-in drafts, and the flagship
          "Automate plans" wizard. Mirrors iOS 1:1. */}
      <JasperAnalysisDock
        pillLabel="Knot's read"
        boxTitle="Roster analysis"
        focus="You are analyzing a coach's client roster (live Jasper dashboards). Lead with WHO NEEDS ATTENTION and why (readiness or sleep under 50, or no readable dashboard), then who's cruising, then ONE concrete coaching move for today. Use the actual @handles. The Plan questionnaire collects answers for review only; automated plan delivery is paused pending native Nutrition review in Jasper. Missing or unavailable data is not evidence of inactivity."
        buildContext={() => {
          if (clients.length === 0) return null;
          const lines: string[] = [
            "COACH ROSTER (live one-call Jasper dashboards)",
          ];
          for (const c of clients.slice(0, 14)) {
            const dash = dashMap[c.client_user_id];
            let signal = "no readable dashboard yet";
            if (dash && dash !== "error") {
              const bits: string[] = [];
              if (dash.summary.readinessScore !== null) {
                bits.push(`readiness ${dash.summary.readinessScore}`);
              }
              if (dash.summary.sleepQualityScore !== null) {
                bits.push(`sleep quality ${dash.summary.sleepQualityScore}`);
              }
              signal = bits.length > 0 ? bits.join(" · ") : "dashboard readable";
            } else if (dash === "error") {
              signal = "dashboard unavailable";
            }
            lines.push(`- @${c.client_username} · ${signal}`);
          }
          if (pending.length > 0) {
            lines.push(`Pending coaching requests: ${pending.length}`);
          }
          return lines.join("\n");
        }}
        emptyText="No clients yet — accept a coaching request and I'll read the roster here."
        actions={[
          {
            id: "attention",
            label: "Who needs attention",
            icon: AlertTriangle,
            kind: "lens",
            focus:
              "From the roster below, list ONLY the clients who need attention this week — one line each: @handle, the exact signal (readiness/sleep number or unreadable dashboard), and the single move to make. If everyone is fine, say so in one sentence.",
          },
          {
            id: "checkins",
            label: "Check-in drafts",
            icon: MessageSquareText,
            kind: "lens",
            focus:
              "Write 2 short copy-ready check-in DMs for the clients who most need one right now, grounded in their live numbers. Format: @handle — then the message in quotes. Warm, specific, coach-voiced.",
          },
          {
            id: "automate",
            label: "Plan questionnaire",
            icon: Wand2,
            kind: "perform",
            onPerform: () => setAutomateOpen(true),
          },
        ]}
      />
      <PlanAutomationDialog
        open={automateOpen}
        onOpenChange={setAutomateOpen}
        clients={clients.map((c) => ({
          userId: c.client_user_id,
          username: c.client_username,
        }))}
      />

      {/* The whole studio floats as ONE rounded box on the basic background
          — the same floating-box language as Jasper Intelligence and the DM
          pane. A single calm column like iOS; the box's own shadow lifts it. */}
      <div className="mx-auto w-full max-w-3xl px-3 pb-16 pt-4 sm:px-6">
        <div>
        <div className="overflow-hidden rounded-[28px] border border-border bg-card shadow-[0_22px_64px_rgba(15,13,22,0.10)] dark:shadow-[0_26px_80px_rgba(0,0,0,0.5)]">
        {/* ── Hero — greeting, exactly like iOS ─────────────────────────── */}
        {showSection("home") && (
        <section className="border-b border-border/60 p-5 sm:p-7">
          <p
            className="text-[10px] font-black uppercase tracking-[0.22em]"
            style={{ color: COACH_ACCENT }}
          >
            Coach Studio
          </p>
          <div className="mt-3.5 flex items-center gap-3.5">
            <Avatar url={profile?.profile_image_url} name={username} size={56} />
            <div className="min-w-0">
              <p className="truncate text-[19px] font-extrabold">{greeting()}</p>
              <p className="truncate text-[13px] text-muted-foreground">@{username}</p>
            </div>
          </div>
          {/* Live stat strip — Clients / Requests / Attention, in the hero. */}
          <div className="mt-5 grid grid-cols-3 gap-2.5">
          {(
            [
              [clients.length, "Clients", Users, undefined],
              [pending.length, "Requests", Send, undefined],
              [attentionCount, "Attention", Zap, attentionCount > 0 ? "#ef4444" : undefined],
            ] as const
          ).map(([value, label, Icon, tint]) => (
            <div key={label} className="rounded-2xl bg-secondary/50 px-3.5 py-3">
              <span className="mb-1 flex h-[26px] w-[26px] items-center justify-center rounded-full bg-background/80">
                <Icon className="h-3 w-3" style={tint ? { color: tint } : undefined} />
              </span>
              <p className="text-[22px] font-black leading-tight" style={tint ? { color: tint } : undefined}>
                {value}
              </p>
              <p className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">
                {label}
              </p>
            </div>
          ))}
          </div>
          {/* Portal home — clean jump-in tiles. */}
          {inPortal && (
            <div className="mt-4 grid grid-cols-2 gap-2.5">
              {(
                [
                  ["clients", "Clients", Users, `${clients.length} on your roster`],
                  ["programs", "Programs studio", Sparkles, "Jasper plans, live"],
                  ["selling", "Drafts & selling", Send, `${programs.length} DM drafts`],
                  ["earnings", "Earnings & payouts", BadgeDollarSign, "Income, bank & rate"],
                ] as const
              ).map(([tab, label, Icon, hint]) => (
                <Link
                  key={tab}
                  to={portalHref(tab)}
                  className="rounded-2xl border border-border bg-background/70 p-3.5 transition-all hover:-translate-y-0.5 hover:border-[#E8853D]/50"
                >
                  <Icon className="h-4 w-4" style={{ color: COACH_ACCENT }} />
                  <p className="mt-2 text-[13.5px] font-extrabold leading-tight">
                    {label}
                  </p>
                  <p className="mt-0.5 text-[11px] text-muted-foreground">
                    {hint}
                  </p>
                </Link>
              ))}
            </div>
          )}
        </section>
        )}

        <div className="space-y-9 p-5 sm:p-7">

        {/* ── Pending requests ──────────────────────────────────────────── */}
        {showSection("home") && pending.length > 0 && (
          <section>
            <h2 className="mb-2 text-[11px] font-black uppercase tracking-[0.14em] text-muted-foreground">
              New requests · {pending.length}
            </h2>
            <div className="space-y-2">
              {pending.map((r) => (
                <div
                  key={r.id}
                  className="flex items-center gap-3 rounded-[20px] border border-border/70 bg-background/60 p-3"
                >
                  <Avatar name={r.client_username} size={42} />
                  <div className="min-w-0 flex-1">
                    <Link
                      to={`/u/${r.client_username}`}
                      className="truncate font-semibold hover:underline"
                    >
                      @{r.client_username}
                    </Link>
                    {r.message ? (
                      <p className="truncate text-sm text-muted-foreground">{r.message}</p>
                    ) : (
                      <p className="text-sm text-muted-foreground">wants you as their coach</p>
                    )}
                  </div>
                  {paidClients.has(r.client_user_id) ? (
                    <span className="flex shrink-0 items-center gap-1 rounded-full bg-emerald-500/10 px-2.5 py-1 text-xs font-bold text-emerald-600">
                      <BadgeDollarSign className="h-3.5 w-3.5" />
                      Paid
                    </span>
                  ) : paidClientsQuery.isSuccess ? (
                    <span className="shrink-0 rounded-full bg-secondary px-2.5 py-1 text-xs font-semibold text-muted-foreground">
                      Awaiting payment
                    </span>
                  ) : null}
                  <button
                    onClick={() => respond.mutate({ id: r.id, status: "declined" })}
                    aria-label="Decline"
                    className="flex h-9 w-9 items-center justify-center rounded-full bg-secondary text-muted-foreground transition-colors hover:text-foreground"
                  >
                    <X className="h-4 w-4" />
                  </button>
                  <button
                    onClick={() => respond.mutate({ id: r.id, status: "accepted" })}
                    aria-label="Accept"
                    className="flex h-9 w-9 items-center justify-center rounded-full bg-primary text-primary-foreground transition-transform active:scale-90"
                  >
                    <Check className="h-4 w-4" />
                  </button>
                </div>
              ))}
            </div>
          </section>
        )}

        {/* ── Clients — one-call dashboard preview chips ─────────────────── */}
        {showSection("clients") && (
        <section id="clients" className="scroll-mt-24">
          <div className="mb-2 flex items-center gap-2">
            <h2 className="text-[11px] font-black uppercase tracking-[0.14em] text-muted-foreground">
              Clients
            </h2>
            <span className="rounded-full bg-secondary px-2 py-0.5 text-[10px] font-bold text-muted-foreground">
              {clients.length}
            </span>
          </div>
          {clients.length > 3 && (
            <div className="mb-2 flex h-9 items-center gap-2 rounded-full border border-border/70 bg-background/60 px-3.5">
              <Search className="h-3.5 w-3.5 text-muted-foreground" />
              <input
                value={clientSearch}
                onChange={(e) => setClientSearch(e.target.value)}
                placeholder="Search clients"
                className="min-w-0 flex-1 bg-transparent text-[13px] outline-none"
              />
            </div>
          )}
          {clients.length === 0 ? (
            <EmptyState
              icon={<Users className="h-7 w-7" />}
              title="No active clients yet"
              body="Share your @handle. When someone taps 'Become my coach,' their request lands here."
            />
          ) : (
            <>
              <div className="space-y-2">
                {sortedClients.map((c) => (
                  <ClientRosterRow
                    key={c.id}
                    client={c}
                    dash={dashMap[c.client_user_id]}
                    attention={needsAttention(c.client_user_id)}
                    paid={paidClients.has(c.client_user_id)}
                    paidKnown={paidClientsQuery.isSuccess}
                    onOpen={() => setDetailClient(c)}
                  />
                ))}
              </div>
            </>
          )}
        </section>
        )}
        {/* ── The Programs studio — the API end-to-end ───────────────────── */}
        {showSection("programs") && (
        <section id="programs" className="scroll-mt-24">
          <p
            className="text-[10px] font-black uppercase tracking-[0.2em]"
            style={{ color: COACH_ACCENT }}
          >
            Programs studio
          </p>
          <p className="mt-1 text-[21px] font-black leading-tight">Your Jasper studio — live.</p>
          <p className="mt-1 max-w-md text-[12.5px] leading-snug text-muted-foreground">
            Programs and diet plans read straight off your Jasper — publish to the marketplace
            or keep Whisper-only drafts for DMs.
          </p>

          {/* Training / Diet segmented picker */}
          <div className="mt-3 flex gap-1.5">
            {(
              [
                ["training", "Training", Dumbbell],
                ["diet", "Diet", Leaf],
              ] as const
            ).map(([id, label, Icon]) => (
              <button
                key={id}
                onClick={() => setStudioTab(id)}
                className={cn(
                  "flex items-center gap-1.5 rounded-full border px-4 py-2 text-[13px] font-semibold transition-colors",
                  studioTab === id
                    ? "border-transparent bg-foreground text-background"
                    : "border-border bg-card text-foreground"
                )}
              >
                <Icon className="h-3.5 w-3.5" strokeWidth={2.6} />
                {label}
              </button>
            ))}
          </div>

          {/* Quick panel tiles */}
          {/* 2×2 always — four across squeezed labels into two-line chips
              inside the desktop studio column. */}
          <div className="mt-2.5 grid grid-cols-2 gap-2">
            {(
              [
                ["marketplace", Store, "Marketplace"],
                ["recipes", BookOpen, "Recipes"],
                ["grocery", ShoppingCart, "Grocery list"],
                ["water", Droplets, "Water"],
              ] as const
            ).map(([key, Icon, label]) => (
              <button
                key={key}
                onClick={() => setJasperPanel(key)}
                className="flex items-center justify-center gap-1.5 whitespace-nowrap rounded-2xl border border-border/70 bg-background/60 px-3 py-2.5 text-[12px] font-bold transition-colors hover:bg-secondary/50"
              >
                <Icon className="h-3.5 w-3.5 text-[#f39057]" />
                {label}
              </button>
            ))}
          </div>

          {publishNote && (
            <p className="mt-2 text-[11px] font-semibold text-red-500">{publishNote}</p>
          )}

          {/* Diet tab — Jasper's own generator, first (WHISPER_PLANS glow box) */}
          {studioTab === "diet" && (
            <button onClick={() => setJasperPanel("diet")} className="mt-3 block w-full text-left">
              <EmberGlowCard glow={0.5} className="flex items-start gap-3 p-4">
                <EmberGlowIcon>
                  <Sparkles className="h-4 w-4" strokeWidth={2.4} />
                </EmberGlowIcon>
                <span className="min-w-0 flex-1">
                  <EmberKicker text="Native review required" />
                  <span className="block text-[15px] font-black">Review in Jasper</span>
                  <span className="mt-0.5 block text-[12px] leading-snug opacity-60">
                    Connected meal generation is paused. Create and review nutrition in Jasper.
                    Saved cloud plans remain readable with your permission.
                  </span>
                </span>
                <ChevronRight className="h-4 w-4 shrink-0 self-center opacity-40" />
              </EmberGlowCard>
            </button>
          )}

          {/* Section header */}
          <h2 className="mb-2 mt-4 flex items-center gap-1.5 text-[11px] font-black uppercase tracking-[0.14em] text-muted-foreground">
            {studioTab === "training" ? (
              <>
                <Zap className="h-3 w-3" /> In your Jasper — live
              </>
            ) : (
              <>
                <Leaf className="h-3 w-3" /> Diet plans in your Jasper — live
              </>
            )}
          </h2>

          {/* Live API rows */}
          {ownPlansQuery.isLoading ? (
            <div className="flex items-center justify-center gap-2 rounded-[20px] border border-border/70 bg-background/60 px-4 py-7 text-[13px] text-muted-foreground">
              <Loader2 className="h-4 w-4 animate-spin" /> Reading your Jasper…
            </div>
          ) : ownPlansQuery.isError ? (
            <div className="space-y-2.5 rounded-[20px] border border-border/70 bg-background/60 px-4 py-6 text-center">
              <p className="text-[14px] font-bold">Couldn't read your Jasper</p>
              <p className="text-[12px] text-muted-foreground">
                Connect Jasper first — Settings → Sync with Jasper. This studio reads your programs
                and diet plans live off the API.
              </p>
              <button
                onClick={() => void ownPlansQuery.refetch()}
                className="mx-auto flex items-center gap-1.5 rounded-full bg-foreground px-4 py-2 text-[12px] font-bold text-background"
              >
                <RotateCw className="h-3 w-3" /> Try again
              </button>
            </div>
          ) : apiRows.length === 0 ? (
            <div className="rounded-[20px] border border-dashed border-border px-4 py-6 text-center text-[12.5px] text-muted-foreground">
              {studioTab === "training"
                ? "No programs in your Jasper yet. Import one from the marketplace or assign one through Coach tools — it lands here instantly."
                : "No diet plans in your Jasper yet. Generate one with Jasper above — it saves straight into your account."}
            </div>
          ) : (
            <div className="space-y-3">
              {apiRows.map((plan) => (
                <ApiPlanRow
                  key={plan.id}
                  plan={plan}
                  published={publishedIds.has(plan.id)}
                  publishing={publishPlan.isPending}
                  onPublish={() => publishPlan.mutate(plan)}
                  onView={() =>
                    plan.isProgram ? setViewingProgram(plan) : setJasperPanel("dietplan")
                  }
                />
              ))}
            </div>
          )}

          {studioTab === "diet" && (
            <p className="mt-2 text-[10.5px] text-muted-foreground">
              Grocery checklists ride every plan and stay in sync with Jasper — a check-off in
              either app shows up in both.
            </p>
          )}
        </section>
        )}

        {/* ── Whisper drafts — sell & send in DMs (Training tab only) ────── */}
        {(inPortal ? coachTab === "selling" : studioTab === "training") && (
          <section id="drafts" className="scroll-mt-24">
            <div className="mb-2 flex items-center justify-between">
              <h2 className="text-[11px] font-black uppercase tracking-[0.14em] text-muted-foreground">
                Whisper drafts — sell & send in DMs
              </h2>
              <button
                onClick={() => setEditing(blankProgram(userId, username))}
                className="flex items-center gap-1 rounded-full bg-primary px-3.5 py-1.5 text-xs font-bold text-primary-foreground transition-transform active:scale-95"
              >
                <Plus className="h-3.5 w-3.5" />
                New program
              </button>
            </div>

            {programs.length === 0 ? (
              <EmptyState
                icon={<Dumbbell className="h-7 w-7" />}
                title="No programs yet"
                body="Build a training program once, then send it to any client in a tap."
              />
            ) : (
              <div className="space-y-2">
                {programs.map((p) => {
                  const lifts = p.days.reduce((acc, d) => acc + d.exercises.length, 0);
                  return (
                    <EmberGlowCard key={p.id} glow={0.5} className="p-4">
                      <div className="flex items-start gap-3">
                        <button onClick={() => setEditing(p)} className="min-w-0 flex-1 text-left">
                          <EmberKicker text={`${p.focus || "Workout plan"} — draft`} />
                          <p className="mt-0.5 flex items-center gap-1.5 truncate text-[16px] font-black">
                            <span className="truncate">{p.title}</span>
                            {p.priceCents > 0 && (
                              <span
                                className="shrink-0 rounded-full px-2 py-0.5 text-[11px] font-bold text-white"
                                style={{ background: JASPER_EMBER_GRADIENT }}
                              >
                                ${Math.round(p.priceCents / 100)}
                              </span>
                            )}
                          </p>
                          {p.summary && (
                            <p className="mt-0.5 line-clamp-2 text-[12px] opacity-60">
                              {p.summary}
                            </p>
                          )}
                          <span className="mt-2 flex gap-4">
                            {(
                              [
                                [p.weeks, "wks"],
                                [p.sessionsPerWeek, "x/wk"],
                                [p.days.length, "days"],
                                [lifts, "lifts"],
                              ] as const
                            ).map(([value, unit]) => (
                              <span key={unit} className="text-[12px]">
                                <span className="font-black">{value}</span>
                                <span className="ml-0.5 opacity-55">{unit}</span>
                              </span>
                            ))}
                          </span>
                        </button>
                        <button
                          onClick={() => removeProgram.mutate(p.id)}
                          aria-label="Delete program"
                          className="flex h-9 w-9 items-center justify-center rounded-full text-muted-foreground transition-colors hover:bg-destructive/10 hover:text-destructive"
                        >
                          <Trash2 className="h-4 w-4" />
                        </button>
                      </div>

                      {clients.length > 0 && (
                        <div className="mt-3 flex flex-wrap gap-1.5 border-t border-black/10 pt-3 dark:border-white/10">
                          <span className="self-center text-xs opacity-55">Send to:</span>
                          {clients.map((c) => {
                            const lockedClient = isClientLocked(c.client_user_id);
                            return (
                              <button
                                key={c.id}
                                onClick={() => {
                                  if (lockedClient) {
                                    toast(
                                      `@${c.client_username} hasn't paid this cycle — coaching tools are locked. Open Manage to DM them a payment link.`
                                    );
                                    return;
                                  }
                                  sendProgram.mutate({ program: p, client: c });
                                }}
                                className={cn(
                                  "flex items-center gap-1 rounded-full bg-secondary px-3 py-1.5 text-xs font-semibold transition-colors hover:bg-secondary/70",
                                  lockedClient && "opacity-60"
                                )}
                              >
                                {lockedClient ? <Lock className="h-3 w-3" /> : <Send className="h-3 w-3" />}
                                @{c.client_username}
                              </button>
                            );
                          })}
                        </div>
                      )}
                    </EmberGlowCard>
                  );
                })}
              </div>
            )}
          </section>
        )}

        {/* ── Earnings ──────────────────────────────────────────────────── */}
        {showSection("home") && (
        <section id="earnings" className="scroll-mt-24">
          <Link
            to="/coach/earnings"
            className="flex items-center gap-3.5 rounded-[20px] border border-border/70 bg-background/60 p-4 transition-colors hover:bg-secondary/40"
          >
            <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-secondary">
              <BadgeDollarSign className="h-5 w-5" />
            </span>
            <span className="min-w-0 flex-1">
              <span className="block font-bold">Earnings & payouts</span>
              <span className="text-sm text-muted-foreground">
                Coaching income, {rateLabel} rate and payout setup
              </span>
            </span>
            <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground/60" />
          </Link>
        </section>
        )}
        </div>
        </div>
        </div>
      </div>

      <EmberPlanKeyframes />

      {editing && (
        <ProgramEditor
          program={editing}
          saving={persistProgram.isPending}
          onCancel={() => setEditing(null)}
          onSave={(p) => persistProgram.mutate(p)}
        />
      )}

      {viewingProgram && (
        <JasperProgramDetailModal
          plan={parsePlanShape(viewingProgram.payload, viewingProgram.name, viewingProgram.goal)}
          onClose={() => setViewingProgram(null)}
        />
      )}

      {detailClient && (
        <CoachClientDetail
          client={detailClient}
          coachUserId={userId}
          coachUsername={username}
          programs={programs}
          locked={isClientLocked(detailClient.client_user_id)}
          priceCents={myRate?.monthlyPriceCents ?? null}
          onClose={() => setDetailClient(null)}
        />
      )}

      <JasperMarketplacePanel
        open={jasperPanel === "marketplace"}
        onClose={() => setJasperPanel(null)}
      />
      <JasperRecipesPanel open={jasperPanel === "recipes"} onClose={() => setJasperPanel(null)} />
      <JasperGroceryPanel open={jasperPanel === "grocery"} onClose={() => setJasperPanel(null)} />
      <JasperWaterPanel open={jasperPanel === "water"} onClose={() => setJasperPanel(null)} />
      <JasperDietPlanPanel
        open={jasperPanel === "dietplan"}
        onClose={() => setJasperPanel(null)}
        onOpenGrocery={() => setJasperPanel("grocery")}
      />
      <JasperDietBuilderPanel
        open={jasperPanel === "diet"}
        onClose={() => setJasperPanel(null)}
        onSaved={() =>
          void queryClient.invalidateQueries({ queryKey: ["jasper-own-plans", userId] })
        }
      />
    </div>
  );
}

/**
 * One live API row — WHISPER_PLANS.md §3/§4: every plan renders as the ember
 * glow box (glow 0.5, stacked), locked in place in the vertical stack.
 */
function ApiPlanRow({
  plan,
  published,
  publishing,
  onPublish,
  onView,
}: {
  plan: JasperOwnPlan;
  published: boolean;
  publishing: boolean;
  onPublish: () => void;
  onView: () => void;
}) {
  const payloadMissing = Object.keys(plan.payload).length === 0;
  const publishState: EmberPublishState = payloadMissing
    ? "hidden"
    : published
      ? "published"
      : publishing
        ? "publishing"
        : "publishable";
  const n = (v: unknown): number | null =>
    typeof v === "number" && Number.isFinite(v) ? v : null;

  if (plan.isProgram) {
    const shape = parsePlanShape(plan.payload, plan.name, plan.goal);
    const chips: string[] = [];
    if (plan.goal) chips.push(plan.goal);
    const weeks = n((plan.topLevel as Record<string, unknown>).weeks);
    if (weeks) chips.push(`${weeks} weeks`);
    chips.push("Jasper-ready");
    return (
      <JasperWorkoutPlanCard
        plan={shape}
        live
        chips={chips}
        onView={onView}
        publishState={publishState}
        onPublish={onPublish}
      />
    );
  }

  const tl = plan.topLevel as Record<string, unknown>;
  const payload = plan.payload as Record<string, unknown>;
  const grocery = (typeof payload.groceryList === "object" && payload.groceryList !== null
    ? payload.groceryList
    : {}) as Record<string, unknown>;
  const groceryCount = (Array.isArray(grocery.categories) ? grocery.categories : []).reduce<number>(
    (acc, cat) => {
      const c = (typeof cat === "object" && cat !== null ? cat : {}) as Record<string, unknown>;
      return acc + (Array.isArray(c.items) ? c.items.length : 0);
    },
    0
  );
  return (
    <JasperDietPlanGlowCard
      name={plan.name}
      metaLine={plan.detail || plan.goal || "Diet plan"}
      kcal={n(tl.target_calories)}
      protein={n(tl.target_protein_g)}
      carbs={n(tl.target_carbs_g)}
      fat={n(tl.target_fat_g)}
      live
      groceryCount={groceryCount}
      onView={onView}
      publishState={publishState}
      onPublish={onPublish}
    />
  );
}

/** Roster row — presence dot, attention subtitle, the 4 preview chips. */
function ClientRosterRow({
  client,
  dash,
  attention,
  paid,
  paidKnown,
  onOpen,
}: {
  client: CoachRequest;
  dash: CoachPreview | undefined;
  attention: boolean;
  paid: boolean;
  paidKnown: boolean;
  onOpen: () => void;
}) {
  const live = dash && dash !== "error" ? dash : null;
  const fresh = live ? Date.now() - live.fetchedAt < 600000 : false;
  const s = live?.summary;
  const subtitle = attention
    ? live
      ? s?.readinessScore !== null && s?.readinessScore !== undefined && s.readinessScore < 50
        ? `Low readiness · ${s.readinessScore}`
        : s?.sleepQualityScore !== null && s?.sleepQualityScore !== undefined && s.sleepQualityScore < 50
          ? `Rough sleep · quality ${s.sleepQualityScore}`
          : "Needs a look"
      : "Needs a look"
    : live
      ? `Live · ${Math.max(1, Math.round((Date.now() - live.fetchedAt) / 60000))}m ago`
      : dash === "error"
        ? "Dashboard unavailable — tap to retry"
        : "Pulling live dashboard…";
  return (
    <button
      onClick={onOpen}
      className="w-full rounded-[20px] border border-border/70 bg-background/60 p-3 text-left transition-colors hover:bg-secondary/40"
    >
      <div className="flex items-center gap-3">
        <span className="relative shrink-0">
          <Avatar name={client.client_username} size={44} />
          <span
            className={cn(
              "absolute bottom-0 right-0 h-[11px] w-[11px] rounded-full border-2 border-card",
              fresh ? "bg-emerald-500" : "bg-muted-foreground/40"
            )}
          />
        </span>
        <span className="min-w-0 flex-1">
          <span className="block truncate font-semibold">@{client.client_username}</span>
          <span className={cn("block truncate text-xs", attention ? "font-semibold text-red-500" : "text-muted-foreground")}>
            {subtitle}
          </span>
        </span>
        {paid ? (
          <span className="flex shrink-0 items-center gap-1 rounded-full bg-emerald-500/10 px-2.5 py-1 text-xs font-bold text-emerald-600">
            <BadgeDollarSign className="h-3.5 w-3.5" />
            Paid
          </span>
        ) : paidKnown ? (
          <span className="shrink-0 rounded-full bg-secondary px-2.5 py-1 text-xs font-semibold text-muted-foreground">
            Unpaid
          </span>
        ) : null}
        <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground/60" />
      </div>
      {s && (
        <div className="mt-2.5 flex flex-wrap gap-1.5">
          {s.readinessScore !== null && (
            <RosterChip
              icon={<Zap className="h-3 w-3" style={{ color: jasperReadinessColor(s.readinessScore) }} />}
              label={String(s.readinessScore)}
            />
          )}
          {s.kcalToday !== null && (
            <RosterChip icon={<Flame className="h-3 w-3 text-orange-500" />} label={`${s.kcalToday.toLocaleString()} kcal`} />
          )}
          {(s.sleepDurationSeconds !== null || s.sleepQualityScore !== null) && (
            <RosterChip
              icon={<Moon className="h-3 w-3 text-indigo-400" />}
              label={fmtSleepShort(s.sleepDurationSeconds) ?? String(s.sleepQualityScore ?? "—")}
            />
          )}
          {s.workoutsLast7d !== null && (
            <RosterChip icon={<Dumbbell className="h-3 w-3 text-muted-foreground" />} label={`${s.workoutsLast7d}×7d`} />
          )}
        </div>
      )}
    </button>
  );
}

function RosterChip({ icon, label }: { icon: React.ReactNode; label: string }) {
  return (
    <span className="flex items-center gap-1 rounded-full bg-secondary px-2.5 py-1 text-[11px] font-semibold text-foreground/85">
      {icon}
      {label}
    </span>
  );
}

function EmptyState({
  icon,
  title,
  body,
}: {
  icon: React.ReactNode;
  title: string;
  body: string;
}) {
  return (
    <div className="flex flex-col items-center rounded-[20px] border border-dashed border-border px-6 py-12 text-center">
      <span className="mb-3 flex h-14 w-14 items-center justify-center rounded-full bg-secondary text-muted-foreground">
        {icon}
      </span>
      <p className="font-semibold">{title}</p>
      <p className="mt-1 max-w-xs text-sm text-muted-foreground">{body}</p>
    </div>
  );
}
