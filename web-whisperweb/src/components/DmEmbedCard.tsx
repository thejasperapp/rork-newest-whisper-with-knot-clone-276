import { memo, useEffect, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import {
  Dumbbell,
  ChevronDown,
  ChevronRight,
  Footprints,
  Moon,
  Scale,
  UtensilsCrossed,
  ArrowDownCircle,
  ShoppingCart,
  Circle,
  CheckCircle2,
  Loader2,
  Sparkles,
  Leaf,
  ArrowLeftRight,
  MessageSquareText,
  Dumbbell as DumbbellIcon,
  Send,
  XCircle,
  BadgeCheck,
  Video,
  Phone,
  Lock,
} from "lucide-react";

import { cn } from "@/lib/utils";
import { Avatar } from "@/components/Avatar";
import { fetchProfileByUsername } from "@/lib/api";
import {
  decodeProgramDM,
  decodeCoachMacros,
  decodeCoachTargets,
  decodeCoachDietPlan,
  decodeCoachProposal,
  coachProposalTitle,
  coachCardState,
  setCoachCardState,
  respondToCoachProposal,
  type CoachMacrosPayload,
  type CoachDietPlanPayload,
  type CoachProposalPayload,
  type CoachCardState,
} from "@/lib/coach";
import { applyMyGoals } from "@/lib/jasperData";
import { parseWorkoutEmbed } from "@/lib/workout";
import {
  decodeGrocery,
  checkedGroceryItems,
  toggleGroceryItem,
  type GroceryPayload,
} from "@/lib/grocery";
import { decodeCallInvite, meetingIdFromText } from "@/lib/meetings";
import { meetingInvitationFromText } from "@/lib/meetingInvitation";
import {
  fetchProgramAccess,
  startEmbeddedProgramCheckout,
  formatCents,
} from "@/lib/coachPay";
import { EmbeddedCheckoutSheet } from "@/components/EmbeddedCheckoutSheet";
import { useAuth } from "@/hooks/useAuth";
import { useJasperDark } from "@/components/JasperIntelKit";
import { emberGlowCardStyle, JASPER_MACROS } from "@/lib/jasperIntel";

/** Warm coach accent — matches iOS `WhisperTheme.coachAccent` (#fa7321). */
const COACH_ACCENT = "#fa7321";

/**
 * Renders the rich coach/workout/grocery DM embeds (program, macros, daily
 * targets, diet plan, workout, grocery list) instead of leaking the raw
 * `::whisper-…::{json}` payload. Returns null when the body isn't a recognised
 * embed so the caller falls back to a plain bubble.
 */
function DmEmbedCardBase({
  body,
  mine,
  meId,
}: {
  body: string | null | undefined;
  mine: boolean;
  meId: string;
}) {
  const [open, setOpen] = useState<boolean>(false);
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const [buyBusy, setBuyBusy] = useState<boolean>(false);
  const [checkout, setCheckout] = useState<{
    clientSecret: string;
    publishableKey: string;
  } | null>(null);

  const program = decodeProgramDM(body);
  const macros = decodeCoachMacros(body);
  const targets = decodeCoachTargets(body);
  const dietPlan = decodeCoachDietPlan(body);
  const proposal = decodeCoachProposal(body);
  const workout = parseWorkoutEmbed(body);
  const grocery = decodeGrocery(body);
  const call = decodeCallInvite(body);
  const invitation = meetingInvitationFromText(body);

  // Paid programs stay locked for recipients until they buy — the coach
  // (sender) and past buyers see the full plan. Free/legacy programs skip
  // the access check entirely.
  const programLocked = !!program && program.priceCents > 0 && !!program.id && !mine;
  const programAccess = useQuery({
    queryKey: ["program-access", program?.id ?? "none"],
    queryFn: () => fetchProgramAccess(program!.id),
    enabled: programLocked && !!user,
    staleTime: 5 * 60 * 1000,
  });
  const programUnlocked = !programLocked || programAccess.data?.purchased === true;

  if (
    !program &&
    !macros &&
    !targets &&
    !dietPlan &&
    !proposal &&
    !workout &&
    !grocery &&
    !call &&
    !invitation
  )
    return null;

  const shell = cn(
    "w-[min(270px,82vw)] overflow-hidden rounded-[20px] border text-left",
    mine ? "border-primary/30 bg-primary/10" : "border-border bg-card"
  );

  // ─── 1:1 call — the DM call buttons' ring. Fresh rings show an answer
  // action; older ones read as call history. Voice and video render with
  // their own icon/label and keep their mode when tapped.
  if (call) {
    const fresh = call.at > 0 && Date.now() - call.at < 10 * 60 * 1000;
    const isVoice = call.mode === "audio";
    return (
      <a
        href={`/meet/${call.meetingId}?call=${encodeURIComponent(call.fromUsername)}${isVoice ? "&mode=audio" : ""}`}
        className={cn(shell, "block")}
      >
        <div className="flex items-center gap-3 px-4 py-3.5">
          <span
            className={cn(
              "flex h-10 w-10 shrink-0 items-center justify-center rounded-full",
              fresh ? "bg-emerald-500 text-white" : "bg-secondary text-muted-foreground"
            )}
          >
            {isVoice ? <Phone className="h-5 w-5" /> : <Video className="h-5 w-5" />}
          </span>
          <span className="min-w-0 flex-1">
            <span className="block text-[13.5px] font-bold">
              {mine ? "Outgoing" : "Incoming"} {isVoice ? "voice" : "video"} call
            </span>
            <span className="block text-[11.5px] text-muted-foreground">
              {fresh
                ? mine
                  ? "Ringing — tap to rejoin"
                  : "Tap to answer"
                : "Call ended — tap to call back"}
            </span>
          </span>
          <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
        </div>
      </a>
    );
  }

  // ─── Shared meeting — a mydailywhisper.com/meet/{id} link becomes a rich
  // "Join meeting" card (works for links pasted from iOS or web).
  if (invitation) {
    return (
      <a href={invitation.href} className={cn(shell, "block")} rel="noreferrer">
        <div className="flex items-center gap-3 px-4 py-3.5">
          <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-foreground text-background">
            <Video className="h-5 w-5" />
          </span>
          <span className="min-w-0 flex-1">
            <span className="block text-[13.5px] font-bold">{invitation.social ? "Whisper invitation" : "Whisper Meet"}</span>
            <span className="block text-[11.5px] text-muted-foreground">
              {invitation.social ? "Open in Whisper" : "Open in Whisper Meet"}
            </span>
          </span>
          <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
        </div>
      </a>
    );
  }

  if (program && programLocked && !programUnlocked) {
    const startProgramBuy = async (): Promise<void> => {
      if (!user || buyBusy) return;
      setBuyBusy(true);
      try {
        const res = await startEmbeddedProgramCheckout({
          programId: program.id,
          userId: user.id,
          email: user.email ?? "",
          cancelPath: "/messages",
        });
        if ("alreadyPurchased" in res && res.alreadyPurchased) {
          void queryClient.invalidateQueries({
            queryKey: ["program-access", program.id],
          });
        } else if ("clientSecret" in res) {
          setCheckout({
            clientSecret: res.clientSecret,
            publishableKey: res.publishableKey,
          });
        }
      } catch (err) {
        toast.error(
          err instanceof Error ? err.message : "Couldn't start checkout."
        );
      } finally {
        setBuyBusy(false);
      }
    };

    return (
      <>
        <div className={shell}>
          <div className="flex items-center gap-3 p-3.5">
            <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl bg-primary/15 text-primary">
              <Dumbbell className="h-5 w-5" />
            </span>
            <div className="min-w-0 flex-1">
              <p className="text-[10px] font-bold uppercase tracking-wide text-primary">
                Training program
              </p>
              <p className="truncate text-[15px] font-bold">{program.title}</p>
              <p className="truncate text-xs text-muted-foreground">
                {program.weeks}w · {program.sessionsPerWeek}×/wk · {program.focus}
              </p>
            </div>
            <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-secondary text-muted-foreground">
              <Lock className="h-3.5 w-3.5" />
            </span>
          </div>
          {program.summary && (
            <p className="line-clamp-2 px-3.5 pb-2 text-xs text-muted-foreground">
              {program.summary}
            </p>
          )}
          <div className="px-3.5 pb-3.5">
            <button
              onClick={() => void startProgramBuy()}
              disabled={buyBusy || programAccess.isLoading || !user}
              className="flex h-10 w-full items-center justify-center gap-2 rounded-full bg-foreground text-[13px] font-bold text-background transition-transform active:scale-[0.98] disabled:opacity-60"
            >
              {buyBusy || programAccess.isLoading ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <>Unlock for {formatCents(program.priceCents)}</>
              )}
            </button>
            <p className="mt-1.5 text-center text-[10.5px] text-muted-foreground">
              One-time purchase · yours forever · secured by Stripe
            </p>
          </div>
        </div>
        {checkout && (
          <EmbeddedCheckoutSheet
            clientSecret={checkout.clientSecret}
            publishableKey={checkout.publishableKey}
            onClose={() => setCheckout(null)}
            onComplete={() => {
              setCheckout(null);
              toast.success("Program unlocked");
              void queryClient.invalidateQueries({
                queryKey: ["program-access", program.id],
              });
            }}
          />
        )}
      </>
    );
  }

  if (program) {
    const totalExercises = program.days.reduce(
      (n, d) => n + d.exercises.length,
      0
    );
    // WHISPER_PLANS.md / WHISPER_BRIDGE.md — program chat embeds wear the
    // ember glow box in BOTH directions, light and dark; never gray glass.
    return (
      <EmberShell className={shell}>
        <button
          onClick={() => setOpen((v) => !v)}
          className="flex w-full items-center gap-3 p-3.5 text-left"
        >
          <span
            className="flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl"
            style={{ background: "rgba(243,144,87,0.15)", color: "#E76F3A" }}
          >
            <Dumbbell className="h-5 w-5" />
          </span>
          <div className="min-w-0 flex-1">
            <p className="text-[10px] font-bold uppercase tracking-wide" style={{ color: "#E76F3A" }}>
              Workout plan
              {program.priceCents > 0 && mine
                ? ` · ${formatCents(program.priceCents)}`
                : ""}
            </p>
            <p className="truncate text-[15px] font-bold">{program.title}</p>
            <p className="truncate text-xs text-muted-foreground">
              {program.weeks}w · {program.sessionsPerWeek}×/wk · {program.focus}
            </p>
          </div>
          <ChevronDown
            className={cn(
              "h-4 w-4 shrink-0 text-muted-foreground transition-transform",
              open && "rotate-180"
            )}
          />
        </button>
        {program.summary && !open && (
          <p className="line-clamp-2 px-3.5 pb-3.5 text-xs text-muted-foreground">
            {program.summary}
          </p>
        )}
        {open && (
          <div className="space-y-3 border-t border-border/60 px-3.5 py-3">
            {program.summary && (
              <p className="text-xs text-muted-foreground">{program.summary}</p>
            )}
            {program.days.map((d) => (
              <div key={d.id}>
                <p className="text-xs font-bold">
                  {d.name}
                  {d.focus ? ` · ${d.focus}` : ""}
                </p>
                <ul className="mt-1 space-y-0.5">
                  {d.exercises.map((ex) => (
                    <li
                      key={ex.id}
                      className="flex justify-between gap-2 text-xs text-muted-foreground"
                    >
                      <span className="truncate">{ex.name}</span>
                      <span className="shrink-0 font-medium text-foreground/80">
                        {ex.sets}×{ex.reps}
                      </span>
                    </li>
                  ))}
                </ul>
              </div>
            ))}
            <p className="text-[11px] text-muted-foreground">
              {totalExercises} exercises total
            </p>
          </div>
        )}
      </EmberShell>
    );
  }

  if (macros)
    return <CoachMacrosCard payload={macros} mine={mine} meId={meId} />;

  if (targets) {
    return (
      <div className={cn(shell, "p-3.5")}>
        <p className="mb-2.5 text-[10px] font-bold uppercase tracking-wide text-sky-500">
          Daily targets
        </p>
        <div className="grid grid-cols-2 gap-1.5">
          <div className="flex items-center gap-2 rounded-2xl bg-secondary/60 px-3 py-2.5">
            <Footprints className="h-4 w-4 text-sky-500" />
            <div>
              <p className="text-sm font-bold">{targets.steps ?? "—"}</p>
              <p className="text-[10px] text-muted-foreground">Steps</p>
            </div>
          </div>
          <div className="flex items-center gap-2 rounded-2xl bg-secondary/60 px-3 py-2.5">
            <Moon className="h-4 w-4 text-indigo-400" />
            <div>
              <p className="text-sm font-bold">
                {targets.sleep_hours ?? "—"}
                <span className="text-[10px] font-medium text-muted-foreground">
                  {targets.sleep_hours != null ? "h" : ""}
                </span>
              </p>
              <p className="text-[10px] text-muted-foreground">Sleep</p>
            </div>
          </div>
        </div>
        {targets.note && (
          <p className="mt-2 text-xs text-muted-foreground">{targets.note}</p>
        )}
      </div>
    );
  }

  if (dietPlan)
    return <CoachDietPlanCard payload={dietPlan} mine={mine} meId={meId} />;

  if (proposal)
    return <CoachProposalCard payload={proposal} mine={mine} meId={meId} />;

  if (workout) {
    const mins = Math.round(workout.durationSeconds / 60);
    return (
      <div className={cn(shell, "p-3.5")}>
        <div className="mb-2 flex items-center gap-2.5">
          <span className="flex h-9 w-9 items-center justify-center rounded-2xl bg-primary/15 text-primary">
            <Dumbbell className="h-4.5 w-4.5" />
          </span>
          <div className="min-w-0">
            <p className="text-[10px] font-bold uppercase tracking-wide text-primary">
              Workout · {workout.focus || "Session"}
            </p>
            <p className="truncate text-sm font-bold">{workout.displayName}</p>
          </div>
        </div>
        <div className="flex gap-4 text-xs font-semibold text-muted-foreground">
          <span>{mins} min</span>
          <span>{workout.totalSets} sets</span>
          <span>{workout.calories} cal</span>
        </div>
      </div>
    );
  }

  if (grocery) return <GroceryCard payload={grocery} mine={mine} />;

  return null;
}

/**
 * Resolves a coach's profile photo from their username so the inline cards show
 * the real avatar — mirrors iOS `WhisperAvatar`, which looks the photo up from
 * the username via the backend cache. Returns null while loading / when unset.
 */
function useCoachAvatar(username: string | null | undefined): string | null {
  const handle = (username ?? "").trim().toLowerCase();
  const enabled = handle.length > 0 && handle !== "coach" && handle !== "your coach";
  const { data } = useQuery({
    queryKey: ["coach-avatar", handle],
    queryFn: () => fetchProfileByUsername(handle),
    enabled,
    staleTime: 5 * 60 * 1000,
  });
  return data?.profile_image_url ?? null;
}

/** Number formatter mirroring iOS — drops a trailing `.0`. */
function fmt(v: number | null): string {
  if (v == null) return "—";
  return Number.isInteger(v) ? `${v}` : v.toFixed(1);
}

interface Stat {
  value: string;
  unit: string;
}

/** WHISPER_PLANS.md §2 — the glow-box shell for plan chat embeds. */
function EmberShell({ className, children }: { className?: string; children: React.ReactNode }) {
  const dark = useJasperDark();
  return (
    <div className={className} style={emberGlowCardStyle(dark, 0.5, 20)}>
      {children}
    </div>
  );
}

/** §4 canonical macro colors on stat values — kcal ember · protein teal · carbs amber · fat blue. */
const STAT_MACRO_COLORS: Record<string, string> = {
  kcal: JASPER_MACROS.kcal,
  protein: JASPER_MACROS.protein,
  carbs: JASPER_MACROS.carbs,
  fat: JASPER_MACROS.fat,
};

/** Columnar stat row with hairline dividers — matches the iOS coach cards. */
function StatRow({ stats, mine }: { stats: Stat[]; mine: boolean }) {
  return (
    <div
      className={cn(
        "mx-3 flex items-stretch rounded-xl py-2.5",
        mine ? "bg-background/10" : "bg-foreground/5"
      )}
    >
      {stats.map((s, i) => (
        <div key={s.unit} className="flex flex-1 items-center">
          <div className="flex flex-1 flex-col items-center gap-0.5">
            <span
              className="text-sm font-semibold tabular-nums"
              style={STAT_MACRO_COLORS[s.unit] ? { color: STAT_MACRO_COLORS[s.unit] } : undefined}
            >
              {s.value}
            </span>
            <span className="text-[10px] font-medium opacity-60">{s.unit}</span>
          </div>
          {i < stats.length - 1 && (
            <span
              className={cn(
                "h-5 w-px",
                mine ? "bg-background/15" : "bg-foreground/10"
              )}
            />
          )}
        </div>
      ))}
    </div>
  );
}

/** Coach attribution header (avatar + @username + coach badge + subtitle). */
function CoachHeader({
  username,
  avatarUrl,
  subtitle,
  icon,
}: {
  username: string;
  avatarUrl: string | null;
  subtitle: string;
  icon: React.ReactNode;
}) {
  return (
    <div className="flex items-center gap-2.5 px-3.5 pb-2.5 pt-3">
      <Avatar name={username} url={avatarUrl} size={32} />
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-1">
          <span className="truncate text-[13px] font-semibold">@{username}</span>
          <Dumbbell
            className="h-3 w-3 shrink-0"
            strokeWidth={2.6}
            style={{ color: COACH_ACCENT }}
          />
        </div>
        <p className="text-[11px] opacity-60">{subtitle}</p>
      </div>
      <span style={{ color: COACH_ACCENT }}>{icon}</span>
    </div>
  );
}

/**
 * Footer CTA strip — visual parity with the iOS "Tap to apply/save" footer.
 * When `saved` it flips to a green confirmation (no chevron), exactly like the
 * iOS `WhisperCoachMacrosInlineCard` footer.
 */
function CoachFooter({
  label,
  savedLabel,
  saved,
}: {
  label: string;
  savedLabel: string;
  saved: boolean;
}) {
  return (
    <div
      className="mt-2.5 flex items-center gap-1.5 px-3.5 pb-3"
      style={{ color: saved ? "#22c55e" : COACH_ACCENT }}
    >
      {saved ? (
        <CheckCircle2 className="h-4 w-4" />
      ) : (
        <ArrowDownCircle className="h-4 w-4" />
      )}
      <span className="text-[13px] font-medium">{saved ? savedLabel : label}</span>
      {!saved && <ChevronRight className="ml-auto h-3.5 w-3.5 opacity-50" />}
    </div>
  );
}

function CoachMacrosCard({
  payload,
  mine,
  meId,
}: {
  payload: CoachMacrosPayload;
  mine: boolean;
  meId: string;
}) {
  const cardId = `macros:${payload.coachUsername}:${payload.calories ?? ""}:${payload.protein_g ?? ""}:${payload.carbs_g ?? ""}:${payload.fat_g ?? ""}`;
  const avatarUrl = useCoachAvatar(payload.coachUsername);
  const [saved, setSaved] = useState<boolean>(false);
  const [working, setWorking] = useState<boolean>(false);

  useEffect(() => {
    setSaved(coachCardState(cardId) === "applied");
  }, [cardId]);

  const stats: Stat[] = [];
  if (payload.calories != null) stats.push({ value: `${payload.calories}`, unit: "kcal" });
  if (payload.protein_g != null) stats.push({ value: fmt(payload.protein_g), unit: "protein" });
  if (payload.carbs_g != null) stats.push({ value: fmt(payload.carbs_g), unit: "carbs" });
  if (payload.fat_g != null) stats.push({ value: fmt(payload.fat_g), unit: "fat" });
  if (payload.water_cups != null) stats.push({ value: `${payload.water_cups}`, unit: "water" });

  const apply = async (): Promise<void> => {
    if (saved || working) return;
    setWorking(true);
    const ok = await applyMyGoals(meId, {
      calories: payload.calories,
      protein_g: payload.protein_g,
      carbs_g: payload.carbs_g,
      fat_g: payload.fat_g,
    });
    setWorking(false);
    if (ok) {
      setCoachCardState(cardId, "applied");
      setSaved(true);
    }
  };

  return (
    <button
      type="button"
      onClick={apply}
      disabled={saved || working}
      className={cn(
        "block w-[min(264px,82vw)] overflow-hidden rounded-[20px] border text-left transition-transform active:scale-[0.98]",
        mine
          ? "border-white/10 bg-foreground text-background"
          : "border-border bg-card text-foreground"
      )}
    >
      <CoachHeader
        username={payload.coachUsername || "coach"}
        avatarUrl={avatarUrl}
        subtitle="Macro update"
        icon={<Scale className="h-4 w-4" />}
      />
      {stats.length > 0 && <StatRow stats={stats} mine={mine} />}
      {working ? (
        <div
          className="mt-2.5 flex items-center gap-1.5 px-3.5 pb-3"
          style={{ color: COACH_ACCENT }}
        >
          <Loader2 className="h-4 w-4 animate-spin" />
          <span className="text-[13px] font-medium">Applying…</span>
        </div>
      ) : (
        <CoachFooter
          label="Tap to apply"
          savedLabel="Applied to your goals"
          saved={saved}
        />
      )}
    </button>
  );
}

function CoachDietPlanCard({
  payload,
  mine,
  meId,
}: {
  payload: CoachDietPlanPayload;
  mine: boolean;
  meId: string;
}) {
  const cardId = `diet:${payload.coachUsername}:${payload.name}:${payload.calories ?? ""}:${payload.protein_g ?? ""}`;
  const avatarUrl = useCoachAvatar(payload.coachUsername);
  const dark = useJasperDark();
  const [saved, setSaved] = useState<boolean>(false);
  const [working, setWorking] = useState<boolean>(false);

  useEffect(() => {
    setSaved(coachCardState(cardId) === "saved");
  }, [cardId]);

  const save = async (): Promise<void> => {
    if (saved || working) return;
    setWorking(true);
    const ok = await applyMyGoals(meId, {
      calories: payload.calories,
      protein_g: payload.protein_g,
      carbs_g: payload.carbs_g,
      fat_g: payload.fat_g,
    });
    setWorking(false);
    if (ok) {
      setCoachCardState(cardId, "saved");
      setSaved(true);
    }
  };

  const chips = [
    payload.dietary_preference,
    payload.goal,
    payload.days_count ? `${payload.days_count} day${payload.days_count === 1 ? "" : "s"}` : null,
    payload.meals_per_day
      ? `${payload.meals_per_day} meal${payload.meals_per_day === 1 ? "" : "s"}/day`
      : null,
  ].filter((c): c is string => !!c && c !== "No Preference");

  const stats: Stat[] = [
    { value: fmt(payload.calories), unit: "kcal" },
    { value: fmt(payload.protein_g), unit: "protein" },
    { value: fmt(payload.carbs_g), unit: "carbs" },
    { value: fmt(payload.fat_g), unit: "fat" },
  ];

  return (
    <button
      type="button"
      onClick={save}
      disabled={saved || working}
      className="block w-[min(264px,82vw)] overflow-hidden rounded-[20px] text-left transition-transform active:scale-[0.98]"
      style={emberGlowCardStyle(dark, 0.5, 20)}
    >
      <CoachHeader
        username={payload.coachUsername || "coach"}
        avatarUrl={avatarUrl}
        subtitle="Diet plan"
        icon={<UtensilsCrossed className="h-4 w-4" />}
      />
      <p className="line-clamp-2 px-3.5 pb-2.5 text-[13px] font-semibold">
        {payload.name || "Coach plan"}
      </p>
      <StatRow stats={stats} mine={mine} />
      {chips.length > 0 && (
        <div className="flex flex-wrap gap-1.5 px-3.5 pt-2.5">
          {chips.map((c) => (
            <span
              key={c}
              className={cn(
                "rounded-full px-2 py-0.5 text-[11px] font-medium opacity-70",
                mine ? "bg-background/10" : "bg-foreground/5"
              )}
            >
              {c}
            </span>
          ))}
        </div>
      )}
      {working ? (
        <div
          className="mt-2.5 flex items-center gap-1.5 px-3.5 pb-3"
          style={{ color: COACH_ACCENT }}
        >
          <Loader2 className="h-4 w-4 animate-spin" />
          <span className="text-[13px] font-medium">Saving…</span>
        </div>
      ) : (
        <CoachFooter
          label="Tap to save"
          savedLabel="Saved to your plans"
          saved={saved}
        />
      )}
    </button>
  );
}

/**
 * Collaborative grocery list — tap items to check them off. Check state is
 * per-device (localStorage), mirroring the iOS `WhisperGroceryStore`.
 */
function GroceryCard({
  payload,
  mine,
}: {
  payload: GroceryPayload;
  mine: boolean;
}) {
  const [checked, setChecked] = useState<Set<string>>(new Set());

  useEffect(() => {
    setChecked(checkedGroceryItems(payload.id));
  }, [payload.id]);

  const items = payload.items.slice(0, 20);

  return (
    <div
      className={cn(
        "w-[min(270px,82vw)] overflow-hidden rounded-[18px] border p-3.5",
        mine
          ? "border-white/10 bg-foreground text-background"
          : "border-border bg-card text-foreground"
      )}
    >
      <div className="mb-2.5 flex items-center gap-2">
        <ShoppingCart className="h-4 w-4 shrink-0" />
        <span className="line-clamp-2 flex-1 text-sm font-bold">
          {payload.title}
        </span>
        <span className="shrink-0 text-[11px] font-extrabold opacity-70">
          {checked.size}/{payload.items.length}
        </span>
      </div>

      <div className="space-y-0.5">
        {items.map((item) => {
          const done = checked.has(item);
          return (
            <button
              key={item}
              onClick={() => setChecked(toggleGroceryItem(payload.id, item))}
              className="flex w-full items-center gap-2 py-1 text-left"
            >
              {done ? (
                <CheckCircle2 className="h-4 w-4 shrink-0 text-green-500" />
              ) : (
                <Circle className="h-4 w-4 shrink-0 opacity-40" />
              )}
              <span
                className={cn(
                  "flex-1 truncate text-[13px] font-semibold transition-opacity",
                  done && "line-through opacity-50"
                )}
              >
                {item}
              </span>
            </button>
          );
        })}
      </div>

      <p className="mt-2 text-[11px] opacity-60">
        Tap items to check off — your taps stay on this device.
      </p>
    </div>
  );
}

/** Icon for a coach-proposal kind — mirrors iOS `WhisperCoachProposalEmbed.icon`. */
function proposalIcon(kind: string): React.ReactNode {
  const cls = "h-4 w-4";
  switch (kind) {
    case "macros":
      return <Scale className={cls} />;
    case "diet_plan":
      return <Leaf className={cls} />;
    case "workout":
      return <DumbbellIcon className={cls} />;
    case "exercise_swap":
      return <ArrowLeftRight className={cls} />;
    case "note":
      return <MessageSquareText className={cls} />;
    default:
      return <Sparkles className={cls} />;
  }
}

/**
 * Coach suggestion card — web parity with iOS `WhisperCoachProposalInlineCard`.
 * Recipients get Apply / Decline actions; the sender sees an "awaiting client
 * response" strip. After responding the card shows a status pill that persists
 * across refreshes.
 */
function CoachProposalCard({
  payload,
  mine,
  meId,
}: {
  payload: CoachProposalPayload;
  mine: boolean;
  meId: string;
}) {
  const avatarUrl = useCoachAvatar(payload.coachUsername);
  const [status, setStatus] = useState<CoachCardState | null>(null);
  const [working, setWorking] = useState<"accepted" | "declined" | null>(null);

  useEffect(() => {
    const s = coachCardState(payload.id);
    setStatus(s === "accepted" || s === "declined" ? s : null);
  }, [payload.id]);

  const respond = async (next: "accepted" | "declined"): Promise<void> => {
    if (working || status) return;
    setWorking(next);
    await respondToCoachProposal({ proposalId: payload.id, userId: meId, status: next });
    setWorking(null);
    setCoachCardState(payload.id, next);
    setStatus(next);
  };

  return (
    <div
      className={cn(
        "w-[min(278px,85vw)] overflow-hidden rounded-[20px] border",
        mine
          ? "border-white/10 bg-foreground text-background"
          : "border-border bg-card text-foreground"
      )}
    >
      <div className="flex items-center gap-2.5 px-3.5 pb-2.5 pt-3">
        <Avatar name={payload.coachUsername} url={avatarUrl} size={32} />
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-1">
            <span className="truncate text-[13px] font-semibold">
              @{payload.coachUsername}
            </span>
            <Dumbbell
              className="h-3 w-3 shrink-0"
              strokeWidth={2.6}
              style={{ color: COACH_ACCENT }}
            />
          </div>
          <p className="text-[11px] opacity-60">{coachProposalTitle(payload.kind)}</p>
        </div>
        <span style={{ color: COACH_ACCENT }}>{proposalIcon(payload.kind)}</span>
      </div>

      <div className="space-y-2 px-3.5 pb-3">
        {payload.summary && (
          <p
            className={cn(
              "rounded-xl px-3 py-2 text-[13px] font-semibold tabular-nums",
              mine ? "bg-background/10" : "bg-foreground/5"
            )}
          >
            {payload.summary}
          </p>
        )}
        {payload.note && (
          <p className="text-xs leading-snug opacity-70">{payload.note}</p>
        )}
      </div>

      <div className={cn("h-px", mine ? "bg-background/10" : "bg-foreground/10")} />

      {mine ? (
        <div className="flex items-center gap-1.5 px-3.5 py-3 text-xs font-semibold opacity-60">
          <Send className="h-3.5 w-3.5" />
          Sent · awaiting client response
        </div>
      ) : status ? (
        <div className="px-3.5 py-3">
          <StatusPill status={status} />
        </div>
      ) : (
        <div className="flex gap-2 px-3 py-3">
          <button
            type="button"
            onClick={() => respond("declined")}
            disabled={working != null}
            className="flex flex-1 items-center justify-center gap-1.5 rounded-full bg-red-500/10 py-2 text-[13px] font-semibold text-red-500 disabled:opacity-60"
          >
            {working === "declined" && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
            {working === "declined" ? "Declining…" : "Decline"}
          </button>
          <button
            type="button"
            onClick={() => respond("accepted")}
            disabled={working != null}
            className="flex flex-1 items-center justify-center gap-1.5 rounded-full py-2 text-[13px] font-semibold text-white disabled:opacity-60"
            style={{ backgroundColor: COACH_ACCENT }}
          >
            {working === "accepted" && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
            {working === "accepted" ? "Applying…" : "Apply"}
          </button>
        </div>
      )}
    </div>
  );
}

/** Accepted / declined status pill for a responded coach proposal. */
function StatusPill({ status }: { status: CoachCardState }) {
  const accepted = status === "accepted";
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-bold",
        accepted
          ? "bg-green-500/12 text-green-500"
          : "bg-red-500/12 text-red-500"
      )}
    >
      {accepted ? (
        <BadgeCheck className="h-3.5 w-3.5" />
      ) : (
        <XCircle className="h-3.5 w-3.5" />
      )}
      {accepted ? "Accepted" : "Declined"}
    </span>
  );
}

export const DmEmbedCard = memo(DmEmbedCardBase);

/** True when a DM body is any rich embed (so the caller skips plain rendering). */
export function isDmEmbed(body: string | null | undefined): boolean {
  return !!(
    decodeProgramDM(body) ||
    decodeCoachMacros(body) ||
    decodeCoachTargets(body) ||
    decodeCoachDietPlan(body) ||
    decodeCoachProposal(body) ||
    parseWorkoutEmbed(body) ||
    decodeGrocery(body) ||
    decodeCallInvite(body) ||
    meetingIdFromText(body)
  );
}
