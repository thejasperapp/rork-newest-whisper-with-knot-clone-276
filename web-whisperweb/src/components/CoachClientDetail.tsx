import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { useJasperGeneration } from "@/hooks/useJasperGeneration";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  Antenna,
  BadgeDollarSign,
  Check,
  Copy,
  Dumbbell,
  Eye,
  Flame,
  Footprints,
  Leaf,
  Loader2,
  Lock,
  Minus,
  Moon,
  Plus,
  RotateCw,
  Send,
  ShoppingCart,
  Sparkles,
  Store,
  Target,
  Undo2,
  UtensilsCrossed,
  Wand2,
  X,
} from "lucide-react";
import { toast } from "sonner";

import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Avatar } from "@/components/Avatar";
import { cn } from "@/lib/utils";
import { siteUrl } from "@/lib/site";
import { fetchProfilesByIds, sendMessage } from "@/lib/api";
import {
  CoachProgram,
  CoachRequest,
  encodeCoachMacros,
  encodeCoachTargets,
  encodeProgramForDM,
  fetchProposalsForClient,
  submitProposal,
} from "@/lib/coach";
import { fetchClientGoals } from "@/lib/jasperData";
import {
  coachAccessMeta,
  coachChangeFeedArmed,
  coachChangeFeedNote,
  reconnectCoachAccess,
  coachDashboard,
  coachDelete,
  coachGenerateDietPlan,
  coachRecentEvents,
  coachWrite,
  dashLockedNames,
  dashLockedScope,
  dashRows,
  friendlyCoachMessage,
  type JasperClientDashboard,
} from "@/lib/jasperCoachConnect";
import {
  JASPER_ACTIVITY_LEVELS,
  JASPER_DIET_GOALS,
  JASPER_DIET_PREFERENCES,
} from "@/lib/jasperConnect";
import { jasperReadinessColor, JASPER_EMBER_GRADIENT } from "@/lib/jasperIntel";
import {
  JasperDietPlanPanel,
  JasperGroceryPanel,
  JasperMarketplacePanel,
} from "@/components/JasperPanels";
import { JasperWaterCup } from "@/components/JasperWaterCup";
import { JasperAnalysisDock } from "@/components/JasperAnalysisDock";
import { formatCents } from "@/lib/coachPay";
import { timeAgo } from "@/lib/format";

type Json = Record<string, unknown>;

function numAny(v: unknown): number | null {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") {
    const n = Number(v);
    if (Number.isFinite(n)) return n;
  }
  return null;
}

function strAny(v: unknown): string | null {
  return typeof v === "string" && v.length > 0 ? v : null;
}

function fmtSleep(seconds: number | null): string | null {
  if (!seconds || seconds <= 0) return null;
  const h = Math.floor(seconds / 3600);
  const m = Math.round((seconds % 3600) / 60);
  return `${h}h ${m.toString().padStart(2, "0")}m`;
}

/**
 * The coach's client view — the 1:1 web port of the iOS
 * `WhisperClientHealthView`: every health number is Jasper's one-call
 * `GET /v1/dashboard` through the client's Connect token (no legacy
 * snapshot, no local recompute), with the TODAY ⇄ WEEK DIGEST switch, the
 * 6-number summary grid, readiness ring + 14-day trend, the tappable
 * 14-night sleep strip, blood work with honest per-scope locks, plan rows
 * (diet · shared groceries · Jasper's water cup), real Coach tools writing
 * into the client's Jasper with one-tap undo, and the marketplace import
 * preselecting this client. The meeting-style Jasper dock reads the SAME
 * payload.
 */
export function CoachClientDetail({
  client,
  coachUserId,
  coachUsername,
  programs,
  onClose,
  locked = false,
  priceCents = null,
}: {
  client: CoachRequest;
  coachUserId: string;
  coachUsername: string;
  programs: CoachProgram[];
  onClose: () => void;
  /** True when this coach charges and the client hasn't paid this cycle. */
  locked?: boolean;
  priceCents?: number | null;
}) {
  const generation = useJasperGeneration();
  const uid = client.client_user_id;
  const queryClient = useQueryClient();
  const [period, setPeriod] = useState<"today" | "week">("today");
  const [selectedNight, setSelectedNight] = useState<number | null>(null);
  const [panel, setPanel] = useState<"diet" | "grocery" | "marketplace" | "tools" | null>(null);
  const [confirmReconnect, setConfirmReconnect] = useState<boolean>(false);
  useEffect(() => { setPanel(null); }, [generation]);

  const profileQuery = useQuery({
    queryKey: ["profile-by-id", uid],
    queryFn: () => fetchProfilesByIds([uid]),
  });
  const clientProfile = profileQuery.data?.[uid];

  // THE dashboard — one call, 60s cache inside the lib (the ≤1/min cap),
  // kept warm with a 30s on-screen poll exactly like iOS.
  const dashQuery = useQuery({
    queryKey: ["jasper-client-dashboard", uid, period, coachUserId, generation],
    queryFn: () => coachDashboard(uid, period === "week" ? "week" : undefined),
    refetchInterval: 30000,
    retry: false,
  });
  const dash = dashQuery.data ?? null;
  const meta = coachAccessMeta(uid);
  // Change feed (GET /v1/events/page) — reconciled ahead of every dashboard
  // read on the same 60s rail; Jasper has paused webhook push.
  const recentEvents = coachRecentEvents(uid);
  const changeFeedArmed = coachChangeFeedArmed(uid);
  const changeFeedNote = coachChangeFeedNote(uid);

  const goalsQuery = useQuery({
    queryKey: ["client-goals", uid],
    queryFn: () => fetchClientGoals(uid),
  });
  const goals = goalsQuery.data;

  const dm = async (body: string): Promise<void> => {
    await sendMessage(coachUserId, coachUsername, uid, client.client_username, body);
  };

  const sendPaymentLink = useMutation({
    mutationFn: () =>
      dm(
        `Hey @${client.client_username} — to unlock your coaching plan (programs, macros & check-ins), complete your monthly payment here: ${siteUrl(`/hire/${coachUserId}`)}`
      ),
    onSuccess: () => toast("Payment link sent in DMs"),
    onError: () => toast("Couldn't send the payment link"),
  });

  const reconnectMutation = useMutation({
    mutationFn: () => reconnectCoachAccess(uid),
    onSuccess: () => { void queryClient.invalidateQueries({ queryKey: ["jasper-client-dashboard", uid] }); },
    onError: (error) => toast.error(friendlyCoachMessage(error)),
  });

  const refresh = (): void => {
    void queryClient.invalidateQueries({ queryKey: ["jasper-client-dashboard", uid] });
    void coachDashboard(uid, period === "week" ? "week" : undefined, true)
      .then(() =>
        queryClient.invalidateQueries({ queryKey: ["jasper-client-dashboard", uid] })
      )
      .catch(() => undefined);
  };

  // Readiness trend — 14 days off the readiness section rows.
  const readinessRows = dash ? dashRows(dash, "readiness") : [];
  const readinessTrend = readinessRows
    .map((r) => numAny(r.score))
    .filter((v): v is number => v !== null)
    .slice(-14);

  // Sleep nights — the tappable 14-night strip.
  const sleepRows = dash ? dashRows(dash, "sleep").slice(-14) : [];
  const nightIndex = selectedNight ?? sleepRows.length - 1;
  const night = nightIndex >= 0 ? (sleepRows[nightIndex] as Json | undefined) : undefined;

  const bloodRows = dash ? dashRows(dash, "blood_panels") : [];
  const bloodScope = dash ? dashLockedScope(dash, "blood_panels") : null;

  const workoutsRows = dash ? dashRows(dash, "workouts") : [];
  const mealsRows = dash ? dashRows(dash, "meals") : [];
  const waterRows = dash ? dashRows(dash, "water") : [];
  const goalsRows = dash ? dashRows(dash, "goals") : [];
  const photosRows = dash ? dashRows(dash, "photos") : [];
  const programsRows = dash ? dashRows(dash, "programs") : [];
  const profileRows = dash ? dashRows(dash, "profile") : [];

  const waterTodayML = waterRows.reduce<number>((acc, r) => acc + (numAny(r.amount_ml) ?? 0), 0);
  const waterCups = Math.round(waterTodayML / 250);

  const streak = numAny(profileRows[0]?.current_streak);
  const lifetime = numAny(profileRows[0]?.total_workouts);

  const lockedLeftovers = dash
    ? dashLockedNames(dash).filter(
        (n) => !["blood_panels", "workouts", "meals", "goals", "photos", "programs", "readiness", "sleep", "water"].includes(n)
      )
    : [];

  const s = dash?.summary;

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="no-scrollbar max-h-[92vh] max-w-lg overflow-y-auto lg:max-w-3xl">
        {/* ── Header ────────────────────────────────────────────────────── */}
        <DialogHeader>
          <DialogTitle className="flex items-center gap-3">
            <Avatar name={client.client_username} url={clientProfile?.profile_image_url} size={44} />
            <span className="flex min-w-0 flex-col">
              <Link to={`/u/${client.client_username}`} className="truncate font-bold hover:underline">
                {clientProfile?.display_name || client.client_username}
              </Link>
              <span className="flex items-center gap-1.5 text-xs font-normal text-muted-foreground">
                @{client.client_username}
                <span className="rounded-full bg-[#fa7321]/12 px-2 py-0.5 text-[10px] font-black text-[#fa7321]">
                  Active client
                </span>
                {dash && (
                  <span className="flex items-center gap-1 rounded-full bg-emerald-500/10 px-1.5 py-0.5 text-[8px] font-black uppercase tracking-wide text-emerald-600">
                    <span className="h-[5px] w-[5px] rounded-full bg-emerald-500" /> Live
                  </span>
                )}
              </span>
            </span>
          </DialogTitle>
        </DialogHeader>

        {/* Meeting-style Jasper dock — Win / Watch / Next move off the SAME
            one-call payload the panel renders. */}
        <JasperAnalysisDock
          pillLabel="Quick analysis"
          boxTitle={`@${client.client_username} — Knot's read`}
          className="bottom-6 z-[60]"
          focus="You are Knot, helping the coach analyze ONE client's live one-call dashboard. Give the coach a quick read in 3 tight parts: **Win** — the strongest number right now; **Watch** — the risk or slipping metric; **Next move** — one concrete action for this week. Ground every claim in the numbers below; if something is missing, say it isn't shared instead of inventing it."
          buildContext={() => {
            if (!s) return null;
            const lines: string[] = [`CLIENT: @${client.client_username} (live GET /v1/dashboard)`];
            if (s.readinessScore !== null) lines.push(`Readiness ${s.readinessScore}/100`);
            if (s.sleepQualityScore !== null)
              lines.push(`Sleep quality ${s.sleepQualityScore}${fmtSleep(s.sleepDurationSeconds) ? ` · ${fmtSleep(s.sleepDurationSeconds)}` : ""}`);
            if (s.bioageDeltaYears !== null)
              lines.push(`Bio-age delta ${s.bioageDeltaYears >= 0 ? "+" : ""}${s.bioageDeltaYears.toFixed(1)}y`);
            if (s.weightKg !== null) lines.push(`Weight ${s.weightKg.toFixed(1)} kg`);
            if (s.workoutsLast7d !== null) lines.push(`Workouts last 7d: ${s.workoutsLast7d}`);
            if (s.kcalToday !== null) lines.push(`Today ${s.kcalToday} kcal · ${s.mealsToday ?? 0} meals · water ${waterCups} cups`);
            if (goals?.calories) lines.push(`Macro targets: ${goals.calories} kcal · P${goals.protein_g ?? "?"} C${goals.carbs_g ?? "?"} F${goals.fat_g ?? "?"}`);
            const lockedNames = dash ? dashLockedNames(dash) : [];
            if (lockedNames.length > 0) lines.push(`Not shared (client's choice): ${lockedNames.join(", ")}`);
            return lines.length > 1 ? lines.join("\n") : null;
          }}
          emptyText="This client's live dashboard hasn't loaded yet — give it a second, then re-run."
        />

        {locked && (
          <div className="flex items-center gap-2.5 rounded-2xl border border-amber-500/30 bg-amber-500/10 px-3.5 py-2.5 text-[13px] font-semibold text-amber-600">
            <BadgeDollarSign className="h-4 w-4 shrink-0" />
            <span className="flex-1">
              Unpaid this cycle — coaching tools are locked until
              {priceCents ? ` the ${formatCents(priceCents)}/mo` : " the monthly"} payment clears.
            </span>
            <button
              onClick={() => sendPaymentLink.mutate()}
              disabled={sendPaymentLink.isPending}
              className="shrink-0 rounded-full bg-amber-500 px-3 py-1.5 text-[11px] font-black text-black disabled:opacity-50"
            >
              DM payment link
            </button>
          </div>
        )}

        {/* ── Jasper dashboard — the one-call payload ───────────────────── */}
        <section className="rounded-2xl border border-border bg-card p-4">
          <p className="mb-3 flex items-center gap-2 text-sm font-bold">
            <Antenna className="h-4 w-4 text-[#fa7321]" /> Jasper dashboard
          </p>

          {dashQuery.isLoading ? (
            <div className="space-y-2.5">
              <p className="flex items-center gap-2 text-[12.5px] text-muted-foreground">
                <Loader2 className="h-3.5 w-3.5 animate-spin" />
                One call — pulling @{client.client_username}'s live dashboard from Jasper…
              </p>
              <div className="grid grid-cols-3 gap-2">
                {[0, 1, 2, 3, 4, 5].map((i) => (
                  <div key={i} className="h-[52px] animate-pulse rounded-xl bg-secondary" />
                ))}
              </div>
              <div className="h-[88px] animate-pulse rounded-xl bg-secondary" />
            </div>
          ) : dashQuery.isError || !dash ? (
            <div className="space-y-2.5 py-2 text-center">
              <p className="text-[14px] font-bold text-foreground">Live dashboard unavailable</p>
              <p className="text-[12px] text-muted-foreground">
                {friendlyCoachMessage(dashQuery.error ?? "Couldn't reach Jasper.")}
              </p>
              <p className="text-[9px] text-muted-foreground">
                Whisper renders only Jasper's one-call payload here — no local stand-ins.
              </p>
              <button
                onClick={refresh}
                className="mx-auto flex items-center gap-1.5 rounded-full bg-foreground px-4 py-2 text-[12px] font-bold text-background"
              >
                <RotateCw className="h-3 w-3" /> Retry read
              </button>
              <button className="min-h-11 px-3 text-sm underline disabled:opacity-50" disabled={reconnectMutation.isPending} onClick={() => setConfirmReconnect(true)}>Reconnect Jasper access</button>
              <Dialog open={confirmReconnect} onOpenChange={setConfirmReconnect}>
                <DialogContent><DialogHeader><DialogTitle>Reconnect after client review?</DialogTitle></DialogHeader>
                  <p className="text-sm text-muted-foreground">Ask the client to review their grant in Jasper first. A new token requests the existing coach permissions; Jasper still decides what is shared.</p>
                  <button className="min-h-11 rounded-full bg-foreground px-5 text-background" disabled={reconnectMutation.isPending} onClick={() => { setConfirmReconnect(false); reconnectMutation.mutate(); }}>Reconnect Jasper access</button>
                </DialogContent>
              </Dialog>
            </div>
          ) : (
            <div className="space-y-3.5">
              {/* Access line */}
              <div className="flex items-center gap-1.5 text-[11px] text-muted-foreground">
                <Check className="h-3.5 w-3.5 text-emerald-500" />
                <span className="min-w-0 flex-1 truncate">
                  @{client.client_username}
                  {meta ? ` · ${meta.scopes.includes("all") ? "full access" : `${meta.scopes.length} scopes${meta.canWrite ? " · read & write" : ""}`} · revocable` : " · connected"}
                </span>
                <button
                  onClick={refresh}
                  aria-label="Refresh"
                  className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-secondary text-muted-foreground"
                >
                  <RotateCw className="h-3 w-3" />
                </button>
              </div>

              {/* Change feed — journal events since the last refresh */}
              {recentEvents.length > 0 ? (
                <div className="flex items-center gap-1.5 rounded-[10px] bg-emerald-500/10 px-2.5 py-1.5">
                  <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-emerald-500" />
                  <span className="text-[8px] font-black tracking-[0.1em] text-emerald-500">LIVE</span>
                  <span className="min-w-0 flex-1 truncate text-[11px] font-semibold">
                    {recentEvents[0].title}
                    {recentEvents[0].occurredAt ? ` · ${timeAgo(recentEvents[0].occurredAt)}` : ""}
                  </span>
                  {recentEvents.length > 1 && (
                    <span className="shrink-0 text-[9px] font-bold text-muted-foreground">+{recentEvents.length - 1}</span>
                  )}
                </div>
              ) : changeFeedArmed ? (
                <p className="flex items-center gap-1 text-[9px] text-muted-foreground">
                  <Antenna className="h-3 w-3 shrink-0" /> Change feed positioned — new events show here on the next refresh · webhook push paused by Jasper
                </p>
              ) : changeFeedNote ? (
                <p className="flex items-center gap-1 text-[9px] text-muted-foreground">
                  <Antenna className="h-3 w-3 shrink-0" /> {changeFeedNote}
                </p>
              ) : null}

              {/* TODAY ⇄ WEEK DIGEST */}
              <div className="flex gap-1.5">
                {(["today", "week"] as const).map((p) => (
                  <button
                    key={p}
                    onClick={() => setPeriod(p)}
                    className={cn(
                      "rounded-full px-3 py-1.5 text-[9px] font-black uppercase tracking-[0.08em] transition-colors",
                      period === p ? "bg-foreground text-background" : "bg-secondary text-muted-foreground"
                    )}
                  >
                    {p === "today" ? "Today" : "Week digest"}
                  </button>
                ))}
              </div>

              {/* Streak line */}
              {(streak !== null || lifetime !== null) && (
                <p className="flex items-center gap-1 text-[11px] text-muted-foreground">
                  <Flame className="h-3 w-3 text-orange-500" />
                  {streak ?? 0}-day streak · {lifetime ?? 0} lifetime workouts
                </p>
              )}

              {/* The 6 headline numbers */}
              <div className="grid grid-cols-3 gap-2">
                <SummaryTile
                  label="Readiness"
                  value={s?.readinessScore !== null && s?.readinessScore !== undefined ? String(s.readinessScore) : "—"}
                  tint={s?.readinessScore != null ? jasperReadinessColor(s.readinessScore) : undefined}
                />
                <SummaryTile
                  label="Sleep"
                  value={s?.sleepQualityScore != null ? String(s.sleepQualityScore) : "—"}
                  sub={fmtSleep(s?.sleepDurationSeconds ?? null) ?? undefined}
                />
                <SummaryTile
                  label="Bio age"
                  value={
                    s?.bioageDeltaYears != null
                      ? `${s.bioageDeltaYears >= 0 ? "+" : ""}${s.bioageDeltaYears.toFixed(1)}y`
                      : "—"
                  }
                  sub={s?.biologicalAge != null ? `${s.biologicalAge.toFixed(1)} bio` : undefined}
                  tint={s?.bioageDeltaYears != null ? (s.bioageDeltaYears <= 0 ? "#5CDBB8" : "#F26659") : undefined}
                />
                <SummaryTile label="Weight" value={s?.weightKg != null ? s.weightKg.toFixed(1) : "—"} sub="kg" />
                <SummaryTile label="Workouts 7d" value={s?.workoutsLast7d != null ? String(s.workoutsLast7d) : "—"} />
                <SummaryTile
                  label="Today"
                  value={s?.kcalToday != null ? String(s.kcalToday) : "—"}
                  sub={`kcal${s?.mealsToday != null ? ` · ${s.mealsToday} meals` : ""}`}
                />
              </div>

              {/* WEEK digest */}
              {period === "week" &&
                (dash.digest ? (
                  <div className="space-y-2 rounded-xl bg-secondary/60 p-3">
                    <p className="text-[9px] font-black uppercase tracking-[0.1em] text-muted-foreground">
                      This week vs last
                    </p>
                    <DigestRow title="Readiness" value={dash.digest.readinessAvg != null ? `${Math.round(dash.digest.readinessAvg)} avg` : "—"} delta={dash.digest.readinessDelta} />
                    <DigestRow
                      title="Sleep"
                      value={
                        dash.digest.sleepQuality != null
                          ? `${Math.round(dash.digest.sleepQuality)} quality${fmtSleep(dash.digest.sleepDurationSeconds) ? ` · ${fmtSleep(dash.digest.sleepDurationSeconds)}` : ""}`
                          : "—"
                      }
                      delta={dash.digest.sleepQualityDelta}
                    />
                    <DigestRow
                      title="Training"
                      value={`${dash.digest.workouts ?? 0} workouts${dash.digest.volumeKg != null ? ` · ${Math.round(dash.digest.volumeKg).toLocaleString()} kg` : ""}${dash.digest.prsThisWeek != null ? ` · ${dash.digest.prsThisWeek} PRs` : ""}`}
                      delta={dash.digest.workoutsDelta}
                    />
                    <DigestRow
                      title="Nutrition"
                      value={`${dash.digest.kcalPerDay != null ? `${dash.digest.kcalPerDay.toLocaleString()} kcal/day` : "—"}${dash.digest.mealsLogged != null ? ` · ${dash.digest.mealsLogged} meals` : ""}`}
                      delta={dash.digest.kcalDelta}
                      deltaUnit=" kcal"
                    />
                    <DigestRow
                      title="Weight"
                      value={dash.digest.weightKgLatest != null ? `${dash.digest.weightKgLatest.toFixed(1)} kg` : "—"}
                      delta={dash.digest.weightDeltaKg}
                      deltaUnit=" kg"
                    />
                    {dash.digest.highlights.map((h) => (
                      <div key={h} className="flex items-start gap-2">
                        <span className="mt-1.5 h-1 w-1 shrink-0 rounded-full bg-[#fa7321]" />
                        <p className="min-w-0 flex-1 text-[11.5px] leading-snug text-foreground">{h}</p>
                        <button
                          type="button"
                          aria-label="Copy highlight"
                          onClick={() => {
                            void navigator.clipboard.writeText(h);
                            toast("Copied — paste it into a weekly check-in");
                          }}
                          className="flex h-[22px] w-[22px] shrink-0 items-center justify-center rounded-full bg-secondary text-muted-foreground"
                        >
                          <Copy className="h-2.5 w-2.5" />
                        </button>
                      </div>
                    ))}
                    {dash.digest.highlights.length > 0 && (
                      <p className="text-[9px] text-muted-foreground">
                        Written to paste into a weekly check-in — Jasper computed these server-side.
                      </p>
                    )}
                  </div>
                ) : (
                  <p className="flex items-center gap-2 text-[11.5px] text-muted-foreground">
                    <Loader2 className="h-3 w-3 animate-spin" /> Computing the week-over-week digest…
                  </p>
                ))}

              {/* Readiness · 14 days */}
              {readinessTrend.length > 0 ? (
                <div>
                  <p className="mb-1.5 text-[9px] font-black uppercase tracking-[0.1em] text-muted-foreground">
                    Readiness · 14 days
                  </p>
                  <div className="flex items-center gap-3">
                    <RecoveryRing score={s?.readinessScore ?? readinessTrend[readinessTrend.length - 1]} />
                    <div className="flex h-11 flex-1 items-end gap-1">
                      {readinessTrend.map((score, i) => (
                        <span
                          key={i}
                          className="flex-1 rounded-full"
                          style={{
                            height: `${Math.max(11, (score / 100) * 100)}%`,
                            background: jasperReadinessColor(score),
                            opacity: i === readinessTrend.length - 1 ? 1 : 0.55,
                          }}
                        />
                      ))}
                    </div>
                  </div>
                </div>
              ) : dash && dashLockedScope(dash, "readiness") ? (
                <LockedRow title="Readiness" scope={dashLockedScope(dash, "readiness")!} username={client.client_username} />
              ) : null}

              {/* Sleep · tap a night */}
              {sleepRows.length > 0 ? (
                <div>
                  <p className="mb-1.5 text-[9px] font-black uppercase tracking-[0.1em] text-muted-foreground">
                    Sleep · tap a night
                  </p>
                  <div className="flex justify-end gap-1 overflow-x-auto pb-1">
                    {sleepRows.map((row, i) => {
                      const started = strAny(row.started_at) ?? strAny(row.recorded_on);
                      const date = started ? new Date(started) : null;
                      const selected = i === nightIndex;
                      return (
                        <button
                          key={i}
                          onClick={() => setSelectedNight(i)}
                          className={cn(
                            "flex w-[30px] shrink-0 flex-col items-center rounded-lg py-1",
                            selected ? "bg-foreground text-background" : "bg-secondary text-foreground"
                          )}
                        >
                          <span className="text-[8px] font-black uppercase opacity-60">
                            {date ? date.toLocaleDateString("en-US", { weekday: "narrow" }) : "·"}
                          </span>
                          <span className="text-[11px] font-bold tabular-nums">
                            {date ? date.getDate() : "–"}
                          </span>
                        </button>
                      );
                    })}
                  </div>
                  {night && <NightBar night={night} />}
                </div>
              ) : dash && dashLockedScope(dash, "sleep") ? (
                <LockedRow title="Sleep" scope={dashLockedScope(dash, "sleep")!} username={client.client_username} />
              ) : null}

              {/* Blood work */}
              {bloodScope ? (
                <div className="rounded-xl border border-orange-500/25 bg-orange-500/5 p-3">
                  <p className="flex items-center gap-1.5 text-[12.5px] font-bold text-foreground">
                    <Lock className="h-3.5 w-3.5 text-orange-500" /> Blood work · locked
                    <span className="ml-auto rounded-full bg-orange-500/10 px-2 py-0.5 font-mono text-[9px] font-bold text-orange-500">
                      {bloodScope}
                    </span>
                  </p>
                  <p className="mt-1 text-[10.5px] leading-snug text-muted-foreground">
                    Blood never rides a coach token by default. Ask @{client.client_username} to grant blood
                    work explicitly on their Jasper consent screen — until then this section stays locked,
                    and everything else keeps working.
                  </p>
                </div>
              ) : bloodRows.length > 0 ? (
                <BloodPanel rows={bloodRows} />
              ) : null}

              {/* Detail rows */}
              <div className="space-y-1.5">
                <DetailRow
                  icon={<Dumbbell className="h-3.5 w-3.5" />}
                  title="Training"
                  locked={dash ? dashLockedScope(dash, "workouts") : null}
                  username={client.client_username}
                  value={
                    workoutsRows.length > 0
                      ? `${workoutsRows.length} workouts · last ${timeAgo(strAny(workoutsRows[workoutsRows.length - 1]?.started_at) ?? strAny(workoutsRows[workoutsRows.length - 1]?.recorded_at) ?? new Date().toISOString())}`
                      : "No workouts in the window"
                  }
                />
                <DetailRow
                  icon={<UtensilsCrossed className="h-3.5 w-3.5" />}
                  title="Nutrition"
                  locked={dash ? dashLockedScope(dash, "meals") : null}
                  username={client.client_username}
                  value={`${s?.mealsToday ?? mealsRows.length} meals today · ${s?.kcalToday ?? 0} kcal · ${waterTodayML} ml water`}
                />
                <DetailRow
                  icon={<Target className="h-3.5 w-3.5" />}
                  title="Goals"
                  locked={dash ? dashLockedScope(dash, "goals") : null}
                  username={client.client_username}
                  value={goalsRows.length > 0 ? `${goalsRows.length} open` : "None open"}
                />
                <DetailRow
                  icon={<Eye className="h-3.5 w-3.5" />}
                  title="Photo check-ins"
                  locked={dash ? dashLockedScope(dash, "photos") : null}
                  username={client.client_username}
                  value={
                    photosRows.length > 0
                      ? `${photosRows.length} check-ins — metadata only, photo bytes stay in Jasper's private storage`
                      : "No check-ins yet"
                  }
                />
                <DetailRow
                  icon={<Dumbbell className="h-3.5 w-3.5" />}
                  title="Active programs"
                  locked={dash ? dashLockedScope(dash, "programs") : null}
                  username={client.client_username}
                  value={
                    programsRows.length > 0
                      ? `${programsRows.length} · ${strAny(programsRows[0]?.name) ?? "program"}`
                      : "None assigned"
                  }
                />
              </div>

              {/* Plan rows — diet · shared groceries · Jasper's water cup */}
              <div className="space-y-1.5 rounded-xl bg-secondary/50 p-2">
                <button
                  onClick={() => setPanel("diet")}
                  className="flex w-full items-center gap-2.5 rounded-lg px-2 py-2 text-left transition-colors hover:bg-secondary"
                >
                  <span className="flex h-[30px] w-[30px] shrink-0 items-center justify-center rounded-[9px] bg-[#fa7321]/12 text-[#fa7321]">
                    <UtensilsCrossed className="h-3.5 w-3.5" />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block text-[8.5px] font-black uppercase tracking-[0.08em] text-muted-foreground">
                      Diet plan
                    </span>
                    <span className="block truncate text-[12px] font-semibold text-foreground">
                      The full plan exactly as Jasper stores it — live
                    </span>
                  </span>
                </button>
                <button
                  onClick={() => setPanel("grocery")}
                  className="flex w-full items-center gap-2.5 rounded-lg px-2 py-2 text-left transition-colors hover:bg-secondary"
                >
                  <span className="flex h-[30px] w-[30px] shrink-0 items-center justify-center rounded-[9px] bg-[#fa7321]/12 text-[#fa7321]">
                    <ShoppingCart className="h-3.5 w-3.5" />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block text-[8.5px] font-black uppercase tracking-[0.08em] text-muted-foreground">
                      Groceries
                    </span>
                    <span className="block truncate text-[12px] font-semibold text-foreground">
                      Shared state — checks sync with their Jasper live
                    </span>
                  </span>
                </button>
                {waterRows.length > 0 && (
                  <div className="flex items-center gap-2.5 px-2 py-2">
                    <JasperWaterCup level={Math.min(1, waterCups / 8)} width={30} height={42} />
                    <span className="min-w-0 flex-1">
                      <span className="block text-[8.5px] font-black uppercase tracking-[0.08em] text-muted-foreground">
                        Water today · Jasper's own cup
                      </span>
                      <span className="block text-[12px] font-semibold text-foreground">
                        {waterCups} of 8 cups · {waterTodayML} ml — the water_cup render spec, live
                      </span>
                    </span>
                  </div>
                )}
              </div>

              {/* Coach action buttons */}
              <div className="flex flex-wrap gap-2">
                {meta?.canWrite !== false ? (
                  <button
                    onClick={() => setPanel("tools")}
                    className="flex items-center gap-1.5 rounded-full px-4 py-2 text-[12px] font-black text-white"
                    style={{ background: JASPER_EMBER_GRADIENT }}
                  >
                    <Wand2 className="h-3.5 w-3.5" /> Coach tools
                  </button>
                ) : (
                  <span className="flex items-center gap-1.5 rounded-full bg-secondary px-4 py-2 text-[11px] font-bold text-muted-foreground">
                    <Eye className="h-3 w-3" /> Read-only · client's choice
                  </span>
                )}
                <button
                  onClick={() => setPanel("marketplace")}
                  className="flex items-center gap-1.5 rounded-full bg-secondary px-4 py-2 text-[12px] font-bold text-foreground"
                >
                  <Store className="h-3.5 w-3.5" /> Marketplace
                </button>
              </div>

              {lockedLeftovers.length > 0 && (
                <p className="text-[9px] text-muted-foreground">
                  Also not shared (client's choice): {lockedLeftovers.join(", ")}
                </p>
              )}
              <p className="text-[9px] text-muted-foreground">
                One call · /v1/dashboard · {timeAgo(new Date(dash.fetchedAt).toISOString())} — the exact
                payload Jasper's own coach view renders. Nothing here is computed locally.
              </p>
            </div>
          )}
        </section>

        {/* ── Suggest changes (proposals — client reviews in Whisper) ────── */}
        {!locked && (
          <SuggestChanges
            client={client}
            coachUserId={coachUserId}
            coachUsername={coachUsername}
            programs={programs}
            initialCalories={goals?.calories ?? null}
            initialProtein={goals?.protein_g ?? null}
            initialCarbs={goals?.carbs_g ?? null}
            initialFat={goals?.fat_g ?? null}
            dm={dm}
          />
        )}

        {/* ── Message client ─────────────────────────────────────────────── */}
        <Link
          to={`/messages?to=${client.client_username}`}
          className="flex w-full items-center justify-center gap-2 rounded-2xl bg-[#fa7321] py-3 text-[14px] font-black text-white transition-transform active:scale-[0.99]"
        >
          <Send className="h-4 w-4" /> Message client
        </Link>

        {/* ── Panels — the same Jasper modals as iOS ─────────────────────── */}
        <JasperDietPlanPanel
          open={panel === "diet"}
          onClose={() => setPanel(null)}
          clientUid={uid}
          clientUsername={client.client_username}
          onOpenGrocery={() => setPanel("grocery")}
        />
        <JasperGroceryPanel
          open={panel === "grocery"}
          onClose={() => setPanel(null)}
          clientUid={uid}
          clientUsername={client.client_username}
        />
        <JasperMarketplacePanel open={panel === "marketplace"} onClose={() => setPanel(null)} />
        {panel === "tools" && (
          <CoachToolsPanel
            clientUid={uid}
            clientUsername={client.client_username}
            coachUsername={coachUsername}
            onClose={() => setPanel(null)}
            onWrote={refresh}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}

// MARK: - Summary tiles + digest rows + rings

function SummaryTile({ label, value, sub, tint }: { label: string; value: string; sub?: string; tint?: string }) {
  return (
    <div className="rounded-xl bg-secondary/60 px-2 py-2 text-center">
      <p className="text-[15px] font-bold tabular-nums" style={tint ? { color: tint } : undefined}>
        {value}
      </p>
      <p className="text-[8px] font-black uppercase tracking-[0.08em] text-muted-foreground">{label}</p>
      {sub && <p className="text-[8px] text-muted-foreground">{sub}</p>}
    </div>
  );
}

function DigestRow({ title, value, delta, deltaUnit = "" }: { title: string; value: string; delta: number | null; deltaUnit?: string }) {
  return (
    <div className="flex items-center gap-2">
      <span className="w-16 shrink-0 text-[10.5px] text-muted-foreground">{title}</span>
      <span className="min-w-0 flex-1 truncate text-[12px] font-bold text-foreground">{value}</span>
      {delta !== null && (
        <span className="shrink-0 rounded-full bg-[#F39057]/[0.13] px-2 py-0.5 text-[9px] font-black text-[#F39057]">
          {delta >= 0 ? "+" : ""}
          {Number.isInteger(delta) ? delta : delta.toFixed(1)}
          {deltaUnit}
        </span>
      )}
    </div>
  );
}

function RecoveryRing({ score }: { score: number | null }) {
  const value = score ?? 0;
  const color = jasperReadinessColor(value);
  const radius = 26;
  const circumference = 2 * Math.PI * radius;
  return (
    <svg width={64} height={64} viewBox="0 0 64 64" className="shrink-0 -rotate-90">
      <circle cx={32} cy={32} r={radius} fill="none" stroke="currentColor" strokeOpacity={0.12} strokeWidth={6} />
      <circle
        cx={32}
        cy={32}
        r={radius}
        fill="none"
        stroke={color}
        strokeWidth={6}
        strokeLinecap="round"
        strokeDasharray={circumference}
        strokeDashoffset={circumference * (1 - Math.min(1, value / 100))}
        style={{ transition: "stroke-dashoffset 600ms ease" }}
      />
      <text x={32} y={32} textAnchor="middle" dominantBaseline="central" className="rotate-90 fill-current text-[15px] font-black" style={{ transformOrigin: "32px 32px" }}>
        {score ?? "—"}
      </text>
    </svg>
  );
}

const STAGE_COLORS: Record<string, string> = {
  awake: "#F26659",
  rem: "#5CB3F2",
  core: "#3394E0",
  light: "#3394E0",
  deep: "#1D5FA8",
};

/** Selected-night stage bar — the compact hypnogram read. */
function NightBar({ night }: { night: Json }) {
  const stages: { name: string; seconds: number }[] = [];
  for (const key of ["awake", "rem", "core", "light", "deep"]) {
    const v = numAny(night[`${key}_seconds`]) ?? numAny(night[key]);
    if (v && v > 0) stages.push({ name: key, seconds: v });
  }
  const quality = numAny(night.quality_score) ?? numAny(night.quality);
  const duration = numAny(night.duration_seconds);
  const total = stages.reduce((acc, s) => acc + s.seconds, 0);
  return (
    <div className="mt-2">
      {total > 0 ? (
        <div className="flex h-3.5 w-full overflow-hidden rounded-full">
          {stages.map((stage) => (
            <span
              key={stage.name}
              style={{ width: `${(stage.seconds / total) * 100}%`, background: STAGE_COLORS[stage.name] ?? "#3394E0" }}
              title={`${stage.name} ${fmtSleep(stage.seconds) ?? ""}`}
            />
          ))}
        </div>
      ) : (
        <div className="h-3.5 w-full rounded-full bg-secondary" />
      )}
      <p className="mt-1 text-[10px] text-muted-foreground">
        {fmtSleep(duration) ?? "—"}
        {quality != null ? ` · quality ${Math.round(quality)}` : ""}
        {total > 0 ? ` · ${stages.map((st) => `${st.name} ${fmtSleep(st.seconds)}`).join(" · ")}` : ""}
      </p>
    </div>
  );
}

const BLOOD_MARKERS: [string, string, string][] = [
  ["albumin", "Albumin", "g/dL"],
  ["creatinine", "Creatinine", "mg/dL"],
  ["glucose", "Glucose", "mg/dL"],
  ["crp", "CRP", "mg/L"],
  ["lymphocyte_pct", "Lymph", "%"],
  ["mcv", "MCV", "fL"],
  ["rdw", "RDW", "%"],
  ["alp", "ALP", "U/L"],
  ["wbc", "WBC", "10³/µL"],
];

function BloodPanel({ rows }: { rows: Json[] }) {
  const latest = rows[rows.length - 1];
  const pheno = numAny(latest.pheno_age) ?? numAny(latest.phenoAge);
  const drawn = strAny(latest.drawn_at) ?? strAny(latest.recorded_at);
  return (
    <div className="rounded-xl bg-secondary/60 p-3">
      <p className="text-[9px] font-black uppercase tracking-[0.1em] text-muted-foreground">
        Blood panel{drawn ? ` · drawn ${timeAgo(drawn)}` : ""}
      </p>
      {pheno != null && (
        <p className="mt-1 text-[22px] font-black text-foreground">
          {pheno.toFixed(1)} <span className="text-[11px] font-bold text-muted-foreground">PhenoAge</span>
        </p>
      )}
      <div className="mt-2 grid grid-cols-3 gap-1.5">
        {BLOOD_MARKERS.map(([key, label, unit]) => {
          const v = numAny(latest[key]);
          if (v === null) return null;
          return (
            <div key={key} className="rounded-lg bg-background/60 px-1.5 py-1 text-center">
              <p className="text-[12px] font-bold tabular-nums text-foreground">{v}</p>
              <p className="text-[7.5px] text-muted-foreground">
                {label} · {unit}
              </p>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function LockedRow({ title, scope, username }: { title: string; scope: string; username: string }) {
  return (
    <div className="flex items-center gap-2.5 rounded-xl bg-secondary/60 px-3 py-2.5">
      <Lock className="h-3.5 w-3.5 shrink-0 text-orange-500" />
      <span className="min-w-0 flex-1">
        <span className="block text-[10px] font-black uppercase tracking-wide text-foreground">
          {title} · not shared
        </span>
        <span className="block text-[10px] text-muted-foreground">
          Client's choice — ask @{username} to grant {scope}
        </span>
      </span>
    </div>
  );
}

function DetailRow({
  icon,
  title,
  value,
  locked,
  username,
}: {
  icon: React.ReactNode;
  title: string;
  value: string;
  locked: string | null;
  username: string;
}) {
  if (locked) return <LockedRow title={title} scope={locked} username={username} />;
  return (
    <div className="flex items-center gap-2.5 rounded-xl px-1 py-1">
      <span className="flex h-[26px] w-[26px] shrink-0 items-center justify-center rounded-lg bg-[#fa7321]/10 text-[#fa7321]">
        {icon}
      </span>
      <span className="min-w-0 flex-1">
        <span className="block text-[8.5px] font-black uppercase tracking-[0.08em] text-muted-foreground">
          {title}
        </span>
        <span className="block truncate text-[12px] font-semibold text-foreground">{value}</span>
      </span>
    </div>
  );
}

// MARK: - Suggest changes (proposal system — client reviews in Whisper)

function SuggestChanges({
  client,
  coachUserId,
  coachUsername,
  programs,
  initialCalories,
  initialProtein,
  initialCarbs,
  initialFat,
  dm,
}: {
  client: CoachRequest;
  coachUserId: string;
  coachUsername: string;
  programs: CoachProgram[];
  initialCalories: number | null;
  initialProtein: number | null;
  initialCarbs: number | null;
  initialFat: number | null;
  dm: (body: string) => Promise<void>;
}) {
  const [tool, setTool] = useState<"macros" | "targets" | "programs" | "history">("macros");
  const [calories, setCalories] = useState<string>("2200");
  const [protein, setProtein] = useState<string>("180");
  const [carbs, setCarbs] = useState<string>("220");
  const [fat, setFat] = useState<string>("70");
  const [water, setWater] = useState<string>("8");
  const [touched, setTouched] = useState<boolean>(false);
  const [steps, setSteps] = useState<string>("10000");
  const [sleep, setSleep] = useState<string>("8");
  const [note, setNote] = useState<string>("");

  useEffect(() => {
    if (touched) return;
    if ((initialCalories ?? 0) > 0) setCalories(String(Math.round(initialCalories!)));
    if ((initialProtein ?? 0) > 0) setProtein(String(Math.round(initialProtein!)));
    if ((initialCarbs ?? 0) > 0) setCarbs(String(Math.round(initialCarbs!)));
    if ((initialFat ?? 0) > 0) setFat(String(Math.round(initialFat!)));
  }, [initialCalories, initialProtein, initialCarbs, initialFat, touched]);

  const num = (v: string): number | null => {
    const n = Number(v);
    return Number.isFinite(n) && v.trim() !== "" ? n : null;
  };

  const proposalsQuery = useQuery({
    queryKey: ["coach-proposals", coachUserId, client.client_user_id],
    queryFn: () => fetchProposalsForClient(coachUserId, client.client_user_id),
    enabled: tool === "history",
  });

  const sendMacros = useMutation({
    mutationFn: async () => {
      await dm(
        encodeCoachMacros(coachUsername, {
          calories: num(calories),
          protein_g: num(protein),
          carbs_g: num(carbs),
          fat_g: num(fat),
          water_cups: num(water),
        })
      );
      await submitProposal({
        coachUserId,
        clientUserId: client.client_user_id,
        kind: "macros",
        patch: {
          calories: num(calories) ?? 0,
          protein: num(protein) ?? 0,
          carbs: num(carbs) ?? 0,
          fat: num(fat) ?? 0,
        },
        note: note.trim() || null,
      });
      if (note.trim()) await dm(note.trim());
    },
    onSuccess: () => toast(`Macros sent to @${client.client_username}`),
    onError: () => toast("Couldn't send macros"),
  });

  const sendTargets = useMutation({
    mutationFn: () =>
      dm(encodeCoachTargets(coachUsername, { steps: num(steps), sleep_hours: num(sleep), note: note.trim() || null })),
    onSuccess: () => toast(`Targets sent to @${client.client_username}`),
    onError: () => toast("Couldn't send targets"),
  });

  const sendProgram = useMutation({
    mutationFn: (program: CoachProgram) => dm(encodeProgramForDM(program)),
    onSuccess: () => toast(`Program sent to @${client.client_username}`),
    onError: () => toast("Couldn't send program"),
  });

  return (
    <section className="rounded-2xl border border-border bg-card p-4">
      <p className="mb-1 flex items-center gap-2 text-sm font-bold">
        <Sparkles className="h-4 w-4 text-[#fa7321]" /> Suggest changes
      </p>
      <p className="mb-3 text-[11px] text-muted-foreground">
        Send a proposal — your client reviews it in Whisper and accepts, modifies or declines.
      </p>
      <div className="mb-3 flex gap-1.5">
        {(
          [
            ["macros", "Macros"],
            ["targets", "Targets"],
            ["programs", "Programs"],
            ["history", "History"],
          ] as const
        ).map(([id, label]) => (
          <button
            key={id}
            onClick={() => setTool(id)}
            className={cn(
              "rounded-full px-3 py-1.5 text-[11px] font-bold transition-colors",
              tool === id ? "bg-foreground text-background" : "bg-secondary text-muted-foreground"
            )}
          >
            {label}
          </button>
        ))}
      </div>

      {tool === "macros" && (
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <Field label="Calories" value={calories} onChange={(v) => { setTouched(true); setCalories(v); }} />
            <Field label="Protein (g)" value={protein} onChange={(v) => { setTouched(true); setProtein(v); }} />
            <Field label="Carbs (g)" value={carbs} onChange={(v) => { setTouched(true); setCarbs(v); }} />
            <Field label="Fat (g)" value={fat} onChange={(v) => { setTouched(true); setFat(v); }} />
            <Field label="Water (cups)" value={water} onChange={setWater} />
          </div>
          <NoteField note={note} setNote={setNote} />
          <SendButton pending={sendMacros.isPending} onClick={() => sendMacros.mutate()} label="Send macros" />
        </div>
      )}
      {tool === "targets" && (
        <div className="space-y-3">
          <div className="flex items-center gap-4 text-sm font-bold">
            <span className="flex items-center gap-1.5 text-[#22c55e]">
              <Footprints className="h-4 w-4" /> Steps
            </span>
            <span className="flex items-center gap-1.5 text-[#7a2ef7]">
              <Moon className="h-4 w-4" /> Sleep
            </span>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Daily steps" value={steps} onChange={setSteps} />
            <Field label="Sleep (hours)" value={sleep} onChange={setSleep} />
          </div>
          <NoteField note={note} setNote={setNote} />
          <SendButton pending={sendTargets.isPending} onClick={() => sendTargets.mutate()} label="Send targets" />
        </div>
      )}
      {tool === "programs" && (
        <div className="space-y-2">
          {programs.length === 0 ? (
            <p className="rounded-2xl border border-dashed border-border px-4 py-8 text-center text-sm text-muted-foreground">
              Build a program in the studio first, then send it here.
            </p>
          ) : (
            programs.map((p) => (
              <div key={p.id} className="flex items-center gap-3 rounded-2xl border border-border p-3">
                <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-primary/10 text-primary">
                  <Dumbbell className="h-5 w-5" />
                </span>
                <div className="min-w-0 flex-1">
                  <p className="truncate font-bold">{p.title}</p>
                  <p className="text-xs text-muted-foreground">
                    {p.focus} · {p.weeks}w · {p.days.length} days
                  </p>
                </div>
                <button
                  onClick={() => sendProgram.mutate(p)}
                  className="flex items-center gap-1 rounded-full bg-primary px-3.5 py-2 text-xs font-bold text-primary-foreground transition-transform active:scale-90"
                >
                  <Send className="h-3.5 w-3.5" /> Send
                </button>
              </div>
            ))
          )}
        </div>
      )}
      {tool === "history" && (
        <div className="space-y-2">
          {proposalsQuery.isLoading && (
            <p className="py-6 text-center text-sm text-muted-foreground">Loading…</p>
          )}
          {!proposalsQuery.isLoading && (proposalsQuery.data?.length ?? 0) === 0 && (
            <p className="rounded-2xl border border-dashed border-border px-4 py-8 text-center text-sm text-muted-foreground">
              No plans sent yet.
            </p>
          )}
          {proposalsQuery.data?.map((p) => (
            <div key={p.id} className="flex items-center gap-3 rounded-2xl border border-border p-3">
              <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-secondary text-muted-foreground">
                <Check className="h-4 w-4" />
              </span>
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-semibold capitalize">{p.kind.replace("_", " ")}</p>
                {p.note && <p className="truncate text-xs text-muted-foreground">{p.note}</p>}
              </div>
              <span className="shrink-0 text-xs text-muted-foreground">{timeAgo(p.created_at)}</span>
            </div>
          ))}
        </div>
      )}
    </section>
  );
}

// MARK: - Coach tools (writes into the client's Jasper · undo anytime)

const PROGRAM_GOALS = [
  "General Fitness", "Build Muscle", "Lose Fat", "Get Stronger",
  "Improve Endurance", "Athletic Performance", "Tone & Define", "Increase Flexibility",
];

interface ToolReceipt {
  resource: string;
  id: string | null;
  summary: string;
  undone: boolean;
}

interface DraftExercise {
  name: string;
  sets: number;
  reps: string;
  rest: number;
}

interface DraftDay {
  name: string;
  focus: string;
  exercises: DraftExercise[];
}

/** Apple-epoch seconds (Jasper's plan_shapes `createdAt` contract). */
function appleEpochSeconds(): number {
  return Math.round(Date.now() / 1000 - 978307200);
}

function CoachToolsPanel({
  clientUid,
  clientUsername,
  coachUsername,
  onClose,
  onWrote,
}: {
  clientUid: string;
  clientUsername: string;
  coachUsername: string;
  onClose: () => void;
  onWrote: () => void;
}) {
  const [tool, setTool] = useState<"program" | "diet" | "log" | "card">("program");
  const [busy, setBusy] = useState<boolean>(false);
  const [receipt, setReceipt] = useState<ToolReceipt | null>(null);

  // Program
  const [pName, setPName] = useState<string>("");
  const [pGoal, setPGoal] = useState<string>("General Fitness");
  const [pWeeks, setPWeeks] = useState<number>(8);
  const [pDaysPerWeek, setPDaysPerWeek] = useState<number>(4);
  const [pSummary, setPSummary] = useState<string>("");
  const [pDays, setPDays] = useState<DraftDay[]>([
    { name: "Day 1", focus: "", exercises: [{ name: "", sets: 3, reps: "10", rest: 90 }] },
  ]);

  // Diet
  const [dGoal, setDGoal] = useState<string>("Fat Loss");
  const [dPref, setDPref] = useState<string>("No Preference");
  const [dAllergies, setDAllergies] = useState<string>("");
  const [dMeals, setDMeals] = useState<number>(4);
  const [dUseProfile, setDUseProfile] = useState<boolean>(false);
  const [dKcal, setDKcal] = useState<string>("");
  const [dProtein, setDProtein] = useState<string>("");
  const [dAge, setDAge] = useState<string>("");
  const [dGender, setDGender] = useState<string>("male");
  const [dWeight, setDWeight] = useState<string>("");
  const [dHeight, setDHeight] = useState<string>("");
  const [dActivity, setDActivity] = useState<string>("Moderately Active");

  // Log
  const [logKind, setLogKind] = useState<"meal" | "water">("meal");
  const [mName, setMName] = useState<string>("");
  const [mType, setMType] = useState<string>("lunch");
  const [mKcal, setMKcal] = useState<string>("");
  const [mProtein, setMProtein] = useState<string>("");
  const [waterML, setWaterML] = useState<number>(250);

  // Card
  const [cTitle, setCTitle] = useState<string>("");
  const [cNote, setCNote] = useState<string>("");

  const finish = (resource: string, id: string | null, summary: string): void => {
    setReceipt({ resource, id, summary, undone: false });
    onWrote();
  };

  const run = async (): Promise<void> => {
    setBusy(true);
    try {
      if (tool === "program") {
        const clientId = crypto.randomUUID().toLowerCase();
        const workoutDays = pDays
          .filter((d) => d.exercises.some((ex) => ex.name.trim()))
          .map((d) => ({
            id: crypto.randomUUID().toLowerCase(),
            name: d.name,
            focus: d.focus,
            exercises: d.exercises
              .filter((ex) => ex.name.trim())
              .map((ex) => ({
                id: crypto.randomUUID().toLowerCase(),
                name: ex.name.trim(),
                sets: ex.sets,
                reps: String(ex.reps),
                restSeconds: ex.rest,
              })),
          }));
        if (!pName.trim() || workoutDays.length === 0) {
          toast.error("Name the program and fill at least one day.");
          return;
        }
        // plan_shapes contract: payload rides VERBATIM into the client's
        // Jasper — uuid id mirroring client_id, Apple-epoch createdAt
        // seconds, reps ALWAYS strings, source "coach".
        const receiptOut = await coachWrite(clientUid, "programs", {
          client_id: clientId,
          name: pName.trim(),
          goal: pGoal,
          weeks: pWeeks,
          days_per_week: pDaysPerWeek,
          payload: {
            id: clientId,
            name: pName.trim(),
            goal: pGoal,
            weeks: pWeeks,
            daysPerWeek: pDaysPerWeek,
            summary: pSummary.trim(),
            workoutDays,
            createdAt: appleEpochSeconds(),
            source: "coach",
            coachUsername,
          },
        });
        finish("programs", receiptOut.id, `Assigned "${pName.trim()}" into @${clientUsername}'s Jasper`);
      } else if (tool === "diet") {
        const body: Json = {
          goal: dGoal,
          dietary_preference: dPref,
          meals_per_day: dMeals,
          save: true,
        };
        const allergies = dAllergies.split(",").map((a) => a.trim()).filter((a) => a.length > 0);
        if (allergies.length > 0) body.allergies = allergies;
        if (dUseProfile) {
          body.profile = {
            age: Number(dAge) || 28,
            gender: dGender,
            weight_lbs: Number(dWeight) || 170,
            height_inches: Number(dHeight) || 70,
            activity_level: dActivity,
          };
        } else {
          if (Number(dKcal)) body.target_calories = Number(dKcal);
          if (Number(dProtein)) body.target_protein_g = Number(dProtein);
        }
        const answer = await coachGenerateDietPlan(clientUid, body);
        const plan = (typeof answer.plan === "object" && answer.plan !== null ? answer.plan : {}) as Json;
        finish("diet_plans", strAny(plan.id), `Generated & saved "${strAny(plan.name) ?? "diet plan"}" into @${clientUsername}'s Jasper — grocery list live`);
      } else if (tool === "log") {
        if (logKind === "meal") {
          if (!mName.trim()) {
            toast.error("Name the meal.");
            return;
          }
          const receiptOut = await coachWrite(clientUid, "meals", {
            name: mName.trim(),
            meal_type: mType,
            calories: Number(mKcal) || 0,
            protein: Number(mProtein) || 0,
            logged_at: new Date().toISOString(),
          });
          finish("meals", receiptOut.id, `Logged "${mName.trim()}" for @${clientUsername}`);
        } else {
          const receiptOut = await coachWrite(clientUid, "water", {
            amount_ml: waterML,
            logged_at: new Date().toISOString(),
          });
          finish("water", receiptOut.id, `Logged ${waterML} ml water for @${clientUsername}`);
        }
      } else {
        if (!cTitle.trim()) {
          toast.error("Title the card.");
          return;
        }
        const receiptOut = await coachWrite(clientUid, "charts", {
          title: cTitle.trim(),
          kind: "card",
          note: cNote.trim(),
        });
        finish("charts", receiptOut.id, `Card landed in @${clientUsername}'s Jasper "Shared with you" inbox`);
      }
    } catch (e) {
      toast.error(friendlyCoachMessage(e));
    } finally {
      setBusy(false);
    }
  };

  const undo = async (): Promise<void> => {
    if (!receipt?.id) return;
    try {
      await coachDelete(clientUid, receipt.resource, receipt.id);
      setReceipt({ ...receipt, undone: true });
      toast("Undone — Jasper emits a deletion event so the client's apps stay truthful.");
      onWrote();
    } catch (e) {
      toast.error(friendlyCoachMessage(e));
    }
  };

  const chip = (selected: boolean): string =>
    cn(
      "rounded-full px-3 py-1.5 text-[11px] font-bold transition-colors",
      selected ? "text-white" : "bg-secondary text-muted-foreground"
    );

  const sendLabel =
    tool === "program"
      ? `Assign to @${clientUsername}`
      : tool === "diet"
        ? busy
          ? "Jasper is generating (15-60s)…"
          : `Generate & save to @${clientUsername}`
        : tool === "log"
          ? logKind === "meal"
            ? `Log meal for @${clientUsername}`
            : `Log water for @${clientUsername}`
          : "Send to their Jasper inbox";

  return (
    <div className="fixed inset-0 z-[70] flex items-end justify-center bg-black/60 p-3 backdrop-blur-sm sm:items-center" onClick={onClose}>
      <div
        className="flex max-h-[88vh] w-full max-w-md flex-col overflow-hidden rounded-[24px] border border-border bg-card shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-border px-4 py-3">
          <div>
            <p className="text-[14px] font-black text-foreground">Coach tools</p>
            <p className="text-[10.5px] text-muted-foreground">
              Writes into @{clientUsername}'s Jasper · undo anytime
            </p>
          </div>
          <button
            type="button"
            aria-label="Close"
            onClick={onClose}
            className="flex h-8 w-8 items-center justify-center rounded-full bg-secondary text-muted-foreground"
          >
            <X className="h-3.5 w-3.5" strokeWidth={3} />
          </button>
        </div>

        <div className="flex gap-1.5 overflow-x-auto px-4 py-2.5">
          {(
            [
              ["program", "Program", Dumbbell],
              ["diet", "Diet plan", Leaf],
              ["log", "Log", UtensilsCrossed],
              ["card", "Inbox card", Send],
            ] as const
          ).map(([id, label, Icon]) => (
            <button
              key={id}
              onClick={() => setTool(id)}
              className={cn("flex shrink-0 items-center gap-1.5", chip(tool === id))}
              style={tool === id ? { background: JASPER_EMBER_GRADIENT } : undefined}
            >
              <Icon className="h-3 w-3" /> {label}
            </button>
          ))}
        </div>

        <div className="no-scrollbar min-h-0 flex-1 space-y-3 overflow-y-auto px-4 pb-3">
          {receipt && (
            <div className="flex items-center gap-2.5 rounded-2xl border border-emerald-500/30 bg-emerald-500/10 px-3 py-2.5">
              {receipt.undone ? (
                <Undo2 className="h-4 w-4 shrink-0 text-muted-foreground" />
              ) : (
                <Check className="h-4 w-4 shrink-0 text-emerald-500" />
              )}
              <p className="min-w-0 flex-1 text-[12px] font-semibold text-foreground">
                {receipt.undone ? "Undone." : receipt.summary}
              </p>
              {!receipt.undone && receipt.id && (
                <button
                  onClick={() => void undo()}
                  className="shrink-0 rounded-full bg-[#F39057]/15 px-3 py-1.5 text-[11px] font-black text-[#F39057]"
                >
                  Undo
                </button>
              )}
            </div>
          )}

          {tool === "program" && (
            <>
              <input value={pName} onChange={(e) => setPName(e.target.value)} placeholder="Program name" className="h-10 w-full rounded-xl border border-border bg-secondary px-3.5 text-[14px] font-bold outline-none" />
              <div className="flex flex-wrap gap-1.5">
                {PROGRAM_GOALS.map((g) => (
                  <button key={g} onClick={() => setPGoal(g)} className={chip(pGoal === g)} style={pGoal === g ? { background: JASPER_EMBER_GRADIENT } : undefined}>
                    {g}
                  </button>
                ))}
              </div>
              <div className="flex items-center gap-4">
                <Stepper label="Weeks" value={pWeeks} min={1} max={16} onChange={setPWeeks} />
                <Stepper label="Days/wk" value={pDaysPerWeek} min={1} max={7} onChange={setPDaysPerWeek} />
              </div>
              <textarea value={pSummary} onChange={(e) => setPSummary(e.target.value)} placeholder="Overview (optional)" rows={2} className="w-full rounded-xl border border-border bg-secondary px-3.5 py-2.5 text-[13px] outline-none" />
              {pDays.map((day, di) => (
                <div key={di} className="space-y-2 rounded-xl border border-border p-2.5">
                  <div className="flex items-center gap-2">
                    <input value={day.name} onChange={(e) => setPDays((prev) => prev.map((d, i) => (i === di ? { ...d, name: e.target.value } : d)))} className="h-8 min-w-0 flex-1 rounded-lg bg-secondary px-2.5 text-[12.5px] font-bold outline-none" />
                    <input value={day.focus} onChange={(e) => setPDays((prev) => prev.map((d, i) => (i === di ? { ...d, focus: e.target.value } : d)))} placeholder="Push · Pull · Legs…" className="h-8 min-w-0 flex-1 rounded-lg bg-secondary px-2.5 text-[12.5px] outline-none" />
                    <button onClick={() => setPDays((prev) => prev.filter((_, i) => i !== di))} className="text-muted-foreground"><X className="h-3.5 w-3.5" /></button>
                  </div>
                  {day.exercises.map((ex, ei) => (
                    <div key={ei} className="grid grid-cols-[1fr_52px_52px_60px_20px] items-center gap-1.5">
                      <input value={ex.name} onChange={(e) => setPDays((prev) => prev.map((d, i) => (i === di ? { ...d, exercises: d.exercises.map((x, j) => (j === ei ? { ...x, name: e.target.value } : x)) } : d)))} placeholder="Exercise" className="h-8 rounded-lg bg-secondary px-2.5 text-[12px] outline-none" />
                      <input value={String(ex.sets)} onChange={(e) => setPDays((prev) => prev.map((d, i) => (i === di ? { ...d, exercises: d.exercises.map((x, j) => (j === ei ? { ...x, sets: Number(e.target.value) || 1 } : x)) } : d)))} inputMode="numeric" title="Sets" className="h-8 rounded-lg bg-secondary px-1.5 text-center text-[12px] outline-none" />
                      <input value={ex.reps} onChange={(e) => setPDays((prev) => prev.map((d, i) => (i === di ? { ...d, exercises: d.exercises.map((x, j) => (j === ei ? { ...x, reps: e.target.value } : x)) } : d)))} title="Reps" className="h-8 rounded-lg bg-secondary px-1.5 text-center text-[12px] outline-none" />
                      <input value={String(ex.rest)} onChange={(e) => setPDays((prev) => prev.map((d, i) => (i === di ? { ...d, exercises: d.exercises.map((x, j) => (j === ei ? { ...x, rest: Number(e.target.value) || 0 } : x)) } : d)))} inputMode="numeric" title="Rest s" className="h-8 rounded-lg bg-secondary px-1.5 text-center text-[12px] outline-none" />
                      <button onClick={() => setPDays((prev) => prev.map((d, i) => (i === di ? { ...d, exercises: d.exercises.filter((_, j) => j !== ei) } : d)))} className="text-muted-foreground"><X className="h-3 w-3" /></button>
                    </div>
                  ))}
                  <button onClick={() => setPDays((prev) => prev.map((d, i) => (i === di ? { ...d, exercises: [...d.exercises, { name: "", sets: 3, reps: "10", rest: 90 }] } : d)))} className="flex items-center gap-1 text-[11.5px] font-bold text-[#F39057]">
                    <Plus className="h-3 w-3" /> Add exercise
                  </button>
                </div>
              ))}
              <button onClick={() => setPDays((prev) => [...prev, { name: `Day ${prev.length + 1}`, focus: "", exercises: [{ name: "", sets: 3, reps: "10", rest: 90 }] }])} className="flex w-full items-center justify-center gap-1.5 rounded-xl border border-dashed border-border py-2.5 text-[12px] font-bold text-muted-foreground">
                <Plus className="h-3.5 w-3.5" /> Add day
              </button>
              <p className="text-[10px] text-muted-foreground">
                Byte-exact plan shape — lands in their Jasper with day strips and the workout player, under your coach badge. Empty days are skipped.
              </p>
            </>
          )}

          {tool === "diet" && (
            <>
              <div className="flex flex-wrap gap-1.5">
                {JASPER_DIET_GOALS.map((g) => (
                  <button key={g} onClick={() => setDGoal(g)} className={chip(dGoal === g)} style={dGoal === g ? { background: JASPER_EMBER_GRADIENT } : undefined}>{g}</button>
                ))}
              </div>
              <div className="flex flex-wrap gap-1.5">
                {JASPER_DIET_PREFERENCES.map((p) => (
                  <button key={p} onClick={() => setDPref(p)} className={chip(dPref === p)} style={dPref === p ? { background: JASPER_EMBER_GRADIENT } : undefined}>{p}</button>
                ))}
              </div>
              <input value={dAllergies} onChange={(e) => setDAllergies(e.target.value)} placeholder="Allergies (comma separated, optional)" className="h-9 w-full rounded-xl border border-border bg-secondary px-3.5 text-[13px] outline-none" />
              <Stepper label="Meals/day" value={dMeals} min={2} max={6} onChange={setDMeals} />
              <div className="flex gap-1.5">
                <button onClick={() => setDUseProfile(false)} className={chip(!dUseProfile)} style={!dUseProfile ? { background: JASPER_EMBER_GRADIENT } : undefined}>Macro targets</button>
                <button onClick={() => setDUseProfile(true)} className={chip(dUseProfile)} style={dUseProfile ? { background: JASPER_EMBER_GRADIENT } : undefined}>From a profile</button>
              </div>
              {dUseProfile ? (
                <div className="space-y-2">
                  <div className="grid grid-cols-2 gap-2">
                    <input value={dAge} onChange={(e) => setDAge(e.target.value)} placeholder="Age" inputMode="numeric" className="h-9 rounded-xl border border-border bg-secondary px-3 text-[13px] outline-none" />
                    <div className="flex gap-1.5">
                      <button onClick={() => setDGender("male")} className={cn("flex-1", chip(dGender === "male"))} style={dGender === "male" ? { background: JASPER_EMBER_GRADIENT } : undefined}>Male</button>
                      <button onClick={() => setDGender("female")} className={cn("flex-1", chip(dGender === "female"))} style={dGender === "female" ? { background: JASPER_EMBER_GRADIENT } : undefined}>Female</button>
                    </div>
                    <input value={dWeight} onChange={(e) => setDWeight(e.target.value)} placeholder="Weight (lbs)" inputMode="numeric" className="h-9 rounded-xl border border-border bg-secondary px-3 text-[13px] outline-none" />
                    <input value={dHeight} onChange={(e) => setDHeight(e.target.value)} placeholder="Height (in)" inputMode="numeric" className="h-9 rounded-xl border border-border bg-secondary px-3 text-[13px] outline-none" />
                  </div>
                  <div className="flex flex-wrap gap-1.5">
                    {JASPER_ACTIVITY_LEVELS.map((a) => (
                      <button key={a} onClick={() => setDActivity(a)} className={chip(dActivity === a)} style={dActivity === a ? { background: JASPER_EMBER_GRADIENT } : undefined}>{a}</button>
                    ))}
                  </div>
                  <p className="text-[10px] text-muted-foreground">Mifflin-St Jeor — protein lands at 1.8-2.2 g/kg, exactly like the Jasper app.</p>
                </div>
              ) : (
                <div className="grid grid-cols-2 gap-2">
                  <input value={dKcal} onChange={(e) => setDKcal(e.target.value)} placeholder="Calories" inputMode="numeric" className="h-9 rounded-xl border border-border bg-secondary px-3 text-[13px] outline-none" />
                  <input value={dProtein} onChange={(e) => setDProtein(e.target.value)} placeholder="Protein g" inputMode="numeric" className="h-9 rounded-xl border border-border bg-secondary px-3 text-[13px] outline-none" />
                </div>
              )}
              <p className="text-[10px] text-muted-foreground">
                Generation is paused for native review. Cloud plan storage does not confirm native validation or active selection.
              </p>
            </>
          )}

          {tool === "log" && (
            <>
              <div className="flex gap-1.5">
                <button onClick={() => setLogKind("meal")} className={chip(logKind === "meal")} style={logKind === "meal" ? { background: JASPER_EMBER_GRADIENT } : undefined}>Meal</button>
                <button onClick={() => setLogKind("water")} className={chip(logKind === "water")} style={logKind === "water" ? { background: JASPER_EMBER_GRADIENT } : undefined}>Water</button>
              </div>
              {logKind === "meal" ? (
                <>
                  <input value={mName} onChange={(e) => setMName(e.target.value)} placeholder="Meal name" className="h-10 w-full rounded-xl border border-border bg-secondary px-3.5 text-[14px] font-bold outline-none" />
                  <div className="flex flex-wrap gap-1.5">
                    {["breakfast", "lunch", "dinner", "snack"].map((t) => (
                      <button key={t} onClick={() => setMType(t)} className={cn("capitalize", chip(mType === t))} style={mType === t ? { background: JASPER_EMBER_GRADIENT } : undefined}>{t}</button>
                    ))}
                  </div>
                  <div className="grid grid-cols-2 gap-2">
                    <input value={mKcal} onChange={(e) => setMKcal(e.target.value)} placeholder="Calories" inputMode="numeric" className="h-9 rounded-xl border border-border bg-secondary px-3 text-[13px] outline-none" />
                    <input value={mProtein} onChange={(e) => setMProtein(e.target.value)} placeholder="Protein g" inputMode="numeric" className="h-9 rounded-xl border border-border bg-secondary px-3 text-[13px] outline-none" />
                  </div>
                </>
              ) : (
                <div className="flex flex-wrap items-center gap-1.5">
                  {[250, 500, 750, 1000].map((ml) => (
                    <button key={ml} onClick={() => setWaterML(ml)} className={chip(waterML === ml)} style={waterML === ml ? { background: JASPER_EMBER_GRADIENT } : undefined}>{ml} ml</button>
                  ))}
                  <span className="ml-auto flex items-center gap-2">
                    <button onClick={() => setWaterML((v) => Math.max(50, v - 50))} className="flex h-7 w-7 items-center justify-center rounded-full bg-secondary"><Minus className="h-3 w-3" /></button>
                    <span className="w-16 text-center text-[16px] font-black tabular-nums">{waterML}</span>
                    <button onClick={() => setWaterML((v) => v + 50)} className="flex h-7 w-7 items-center justify-center rounded-full bg-secondary"><Plus className="h-3 w-3" /></button>
                  </span>
                </div>
              )}
            </>
          )}

          {tool === "card" && (
            <>
              <input value={cTitle} onChange={(e) => setCTitle(e.target.value)} placeholder="Card title" className="h-10 w-full rounded-xl border border-border bg-secondary px-3.5 text-[14px] font-bold outline-none" />
              <textarea value={cNote} onChange={(e) => setCNote(e.target.value)} placeholder="Note" rows={3} className="w-full rounded-xl border border-border bg-secondary px-3.5 py-2.5 text-[13px] outline-none" />
              <p className="text-[10px] text-muted-foreground">
                Lands in @{clientUsername}'s Jasper "Shared with you" inbox as a Whisper card.
              </p>
            </>
          )}
        </div>

        <div className="border-t border-border p-3">
          {tool === "diet" && <p className="mb-3 text-sm text-muted-foreground">Connected meal generation is paused. Create and review the plan in Jasper’s Nutrition screen, then refresh saved plans here. Nothing is generated or saved from this screen.</p>}
          <button
            onClick={() => void run()}
            disabled={busy || tool === "diet"}
            className="flex h-[50px] w-full items-center justify-center gap-2 rounded-full text-[14px] font-black text-white disabled:opacity-70"
            style={{ background: JASPER_EMBER_GRADIENT, boxShadow: "0 6px 18px rgba(243,144,87,0.4)" }}
          >
            {busy && <Loader2 className="h-4 w-4 animate-spin" />}
            {tool === "diet" ? "Native nutrition review required" : sendLabel}
          </button>
        </div>
      </div>
    </div>
  );
}

function Stepper({ label, value, min, max, onChange }: { label: string; value: number; min: number; max: number; onChange: (v: number) => void }) {
  return (
    <div className="flex items-center gap-2">
      <span className="text-[12px] font-bold text-muted-foreground">{label}</span>
      <button onClick={() => onChange(Math.max(min, value - 1))} className="flex h-7 w-7 items-center justify-center rounded-full bg-secondary"><Minus className="h-3 w-3" /></button>
      <span className="w-6 text-center text-[14px] font-black tabular-nums">{value}</span>
      <button onClick={() => onChange(Math.min(max, value + 1))} className="flex h-7 w-7 items-center justify-center rounded-full bg-secondary"><Plus className="h-3 w-3" /></button>
    </div>
  );
}

function Field({ label, value, onChange }: { label: string; value: string; onChange: (v: string) => void }) {
  return (
    <div>
      <label className="mb-1.5 block text-xs font-semibold text-muted-foreground">{label}</label>
      <input
        type="number"
        inputMode="numeric"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="w-full rounded-xl border border-border bg-card px-3 py-2.5 text-sm outline-none focus:border-foreground/40"
      />
    </div>
  );
}

function NoteField({ note, setNote }: { note: string; setNote: (v: string) => void }) {
  return (
    <div>
      <label className="mb-1.5 block text-xs font-semibold text-muted-foreground">Optional note</label>
      <textarea
        value={note}
        onChange={(e) => setNote(e.target.value)}
        rows={2}
        placeholder="e.g. Bumping protein for your cut — let's hit this for 2 weeks."
        className="w-full resize-none rounded-2xl border border-border bg-card px-4 py-3 text-sm outline-none focus:border-foreground/40"
      />
    </div>
  );
}

function SendButton({ pending, onClick, label }: { pending: boolean; onClick: () => void; label: string }) {
  return (
    <button
      onClick={onClick}
      disabled={pending}
      className="flex w-full items-center justify-center gap-2 rounded-2xl bg-primary py-3.5 text-[15px] font-bold text-primary-foreground transition-transform active:scale-[0.98] disabled:opacity-50"
    >
      <Send className="h-4 w-4" />
      {pending ? "Sending…" : label}
    </button>
  );
}
