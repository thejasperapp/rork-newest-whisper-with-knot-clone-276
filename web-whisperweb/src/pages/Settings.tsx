import { useEffect, useMemo, useState } from "react";
import { useJasperGeneration } from "@/hooks/useJasperGeneration";
import { assertJasperSession, jasperSession } from "@/lib/jasperSession";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { useLocation, useNavigate } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ArrowLeft,
  BadgeCheck,
  Banknote,
  BarChart3,
  Bell,
  Bookmark,
  Briefcase,
  Check,
  ChevronRight,
  CircleDashed,
  Contrast,
  Download,
  Dumbbell,
  FileText,
  Flag,
  Ghost,
  Globe,
  Heart,
  Info,
  KeyRound,
  LineChart,
  Link2,
  Lock,
  LogOut,
  MessageCircle,
  MonitorSmartphone,
  Moon,
  PenLine,
  Play,
  Plus,
  Repeat2,
  ShieldAlert,
  ShieldCheck,
  Sparkles,
  Star,
  Sun,
  Trash2,
  Trophy,
  User,
  UserPen,
  Users,
  X,
} from "lucide-react";
import { toast } from "sonner";

import { useAuth } from "@/hooks/useAuth";
import { clearMessageSnapshots } from "@/lib/messageCache";
import { isVerifiedCreator, tierLabel } from "@/lib/accountAccess";
import { useMyBadge } from "@/hooks/useMyBadge";
import { Header } from "@/components/Header";
import { Avatar } from "@/components/Avatar";
import { Switch } from "@/components/ui/switch";
import { setProfilePrivacy } from "@/lib/api";
import {
  ACCOUNT_TYPES,
  BUSINESS_CATEGORIES,
  CREATOR_CATEGORIES,
  accountTypeLabel,
  saveAccountType,
  type AccountType,
} from "@/lib/accountTypes";
import { useSettings } from "@/lib/settings";
import { RemotePushSettings } from "@/components/RemotePushSettings";
import { SafetyDecisions } from "@/components/SafetyDecisions";
import {
  fetchJasperLinkStatus,
  redeemJasperLinkCode,
  revokeJasperLink,
} from "@/lib/jasperLink";
import {
  jasperCheckContract,
  jasperDisconnect,
  jasperConnect,
  JASPER_SCOPE_OPTIONS,
  jasperHasLocalToken,
  jasperMe,
  jasperRead,
  type JasperMeState,
} from "@/lib/jasperConnect";
import {
  JasperDietPlanPanel,
  JasperGroceryPanel,
  JasperRecipesPanel,
  JasperWaterPanel,
} from "@/components/JasperPanels";
import { JasperAppIcon } from "@/components/JasperAppIcon";
import { useJasperDark } from "@/components/JasperIntelKit";
import { emberGlowCardStyle } from "@/lib/jasperIntel";
import {
  BookOpen as JasperBookIcon,
  Droplets as JasperDropsIcon,
  Footprints as JasperStepsIcon,
  Link2Off as JasperUnlinkIcon,
  Moon as JasperMoonIcon,
  RotateCw as JasperRotateIcon,
  Scale as JasperScaleIcon,
  ShoppingCart as JasperCartIcon,
  Trophy as JasperTrophyIcon,
  UtensilsCrossed as JasperUtensilsIcon,
  Zap as JasperZapIcon,
} from "lucide-react";
import { timeAgo } from "@/lib/format";
import { fetchAllRoleStates, type RoleState, type SpecialRole } from "@/lib/applications";
import {
  cancelCoachSubscription,
  fetchMyCoachSubscriptions,
  formatCents,
} from "@/lib/coachPay";
import { resolveBackend } from "@/lib/billing";
import { BillingRefundsSection } from "@/components/BillingRefundsSection";
import { fetchMyRecruiter } from "@/lib/recruiterReviews";
import { RecruiterReviewSheet } from "@/components/RecruiterReviewSheet";
import { supabase } from "@/lib/supabase";
import {
  APPEARANCE_MODES,
  getAppearance,
  setAppearance,
  type AppearanceMode,
} from "@/lib/theme";

/** "iPhone" / "Android phone" / "Mac" / "Windows PC" — the device line on the session card. */
function describeDevice(): string {
  if (typeof navigator === "undefined") return "This device";
  const ua = navigator.userAgent;
  if (/iPad/i.test(ua) || (/Macintosh/i.test(ua) && "ontouchend" in document)) return "iPad";
  if (/iPhone/i.test(ua)) return "iPhone";
  if (/Android/i.test(ua)) return /Mobile/i.test(ua) ? "Android phone" : "Android tablet";
  if (/Macintosh|Mac OS X/i.test(ua)) return "Mac";
  if (/Windows/i.test(ua)) return "Windows PC";
  if (/CrOS/i.test(ua)) return "Chromebook";
  if (/Linux/i.test(ua)) return "Linux";
  return "This device";
}

/** "Safari · Whisper web" — the browser line on the session card. */
function describeBrowser(): string {
  if (typeof navigator === "undefined") return "Whisper web";
  const ua = navigator.userAgent;
  let browser = "Browser";
  if (/Edg\//i.test(ua)) browser = "Edge";
  else if (/OPR\//i.test(ua)) browser = "Opera";
  else if (/Chrome\//i.test(ua) && !/Chromium/i.test(ua)) browser = "Chrome";
  else if (/Firefox\//i.test(ua)) browser = "Firefox";
  else if (/Safari\//i.test(ua)) browser = "Safari";
  return `${browser} · Whisper web`;
}

function Row({
  icon,
  title,
  subtitle,
  control,
}: {
  icon: React.ReactNode;
  title: string;
  subtitle?: string;
  control: React.ReactNode;
}) {
  return (
    <div className="flex items-center gap-3 px-4 py-3.5">
      <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-secondary/70 text-foreground/70">
        {icon}
      </div>
      <div className="min-w-0 flex-1">
        <p className="text-[15px] font-semibold leading-tight">{title}</p>
        {subtitle && (
          <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
            {subtitle}
          </p>
        )}
      </div>
      <div className="shrink-0">{control}</div>
    </div>
  );
}

interface JasperProbe {
  resource: string;
  title: string;
  icon: React.ComponentType<{ className?: string }>;
  timeField: string;
}

const JASPER_PROBES: JasperProbe[] = [
  { resource: "workouts", title: "Workouts", icon: JasperZapIcon, timeField: "started_at" },
  { resource: "meals", title: "Meals", icon: JasperUtensilsIcon, timeField: "logged_at" },
  { resource: "sleep", title: "Sleep", icon: JasperMoonIcon, timeField: "started_at" },
  { resource: "weight", title: "Weight", icon: JasperScaleIcon, timeField: "measured_at" },
  { resource: "steps", title: "Steps", icon: JasperStepsIcon, timeField: "recorded_on" },
  { resource: "personal_records", title: "PRs", icon: JasperTrophyIcon, timeField: "achieved_at" },
];

interface JasperProbeResult {
  title: string;
  icon: React.ComponentType<{ className?: string }>;
  count: number;
  latest: string | null;
}

/**
 * Settings → Sync with Jasper — the web port of the iOS ConnectJasperButton
 * card: one-tap Connect (the session IS the consent, no codes), a resolution
 * pill (Linked / Same account / Not linked) driven by Jasper's own /v1/me
 * answer, the "LIVE FROM JASPER" 6-tile proof panel read through the token
 * itself, and the Diet plan · Grocery · Recipes · Water rows opening the
 * live Jasper surfaces.
 */
function SyncWithJasperSection() {
  const generation = useJasperGeneration();
  return <SyncWithJasperContent key={generation} generation={generation} />;
}

function SyncWithJasperContent({ generation }: { generation: number }) {
  const { user } = useAuth();
  const [showPermissions, setShowPermissions] = useState<boolean>(false);
  const [scopes, setScopes] = useState<string[]>(["read:profile", "read:workouts", "read:nutrition"]);
  const [showDisconnect, setShowDisconnect] = useState<boolean>(false);
  const queryClient = useQueryClient();
  const dark = useJasperDark();
  const [panel, setPanel] = useState<"diet" | "grocery" | "recipes" | "water" | null>(null);
  const [testNote, setTestNote] = useState<string | null>(null);

  const meQuery = useQuery<JasperMeState | null>({
    queryKey: ["jasper-connect-me", user?.id, generation],
    queryFn: async () => {
      if (!jasperHasLocalToken()) return null;
      return jasperMe();
    },
    retry: false,
  });

  const connectMutation = useMutation({
    mutationFn: async () => {
      const token = await jasperConnect(scopes);
      if (!token) throw new Error("Jasper didn't answer — sign in with the account linked to the Jasper app.");
      return token;
    },
    onSuccess: () => {
      setShowPermissions(false);
      toast("Jasper connected with your chosen permissions");
      queryClient.invalidateQueries({ queryKey: ["jasper-connect-me"] });
    },
    onError: (e) => toast(e instanceof Error ? e.message : "Couldn't connect — try again"),
  });

  const disconnectMutation = useMutation({
    mutationFn: jasperDisconnect,
    onSuccess: () => toast("Whisper Web's Jasper connection revoked"),
    onError: (error) => toast(error instanceof Error ? error.message : "Couldn't disconnect. Try again."),
  });

  // Guide §01 version check: /v1/experience once per connection generation;
  // an older host is reported under the card, never refused.
  const contractQuery = useQuery<string | null>({
    queryKey: ["jasper-contract-note", generation],
    queryFn: jasperCheckContract,
    enabled: !!meQuery.data,
    staleTime: 3600000,
    retry: false,
  });

  const probesQuery = useQuery<{ results: JasperProbeResult[]; failed: string[] }>({
    queryKey: ["jasper-live-panel", user?.id, generation],
    queryFn: async () => {
      const context = await jasperSession();
      const since = new Date(Date.now() - 30 * 86400000).toISOString();
      const settled = await Promise.allSettled(
        JASPER_PROBES.map(async (probe) => {
          const rows = await jasperRead(probe.resource, 200, since);
          const latest = rows
            .map((r) => (typeof r[probe.timeField] === "string" ? (r[probe.timeField] as string) : null))
            .filter((v): v is string => v !== null)
            .sort()
            .pop() ?? null;
          return { title: probe.title, icon: probe.icon, count: rows.length, latest };
        })
      );
      const results: JasperProbeResult[] = [];
      const failed: string[] = [];
      settled.forEach((outcome, i) => {
        if (outcome.status === "fulfilled") results.push(outcome.value);
        else failed.push(JASPER_PROBES[i].title);
      });
      assertJasperSession(context);
      return { results, failed };
    },
    enabled: !!meQuery.data,
    retry: false,
  });

  const me = meQuery.data ?? null;
  const resolution: { label: string; className: string } = me?.linked
    ? { label: "Linked", className: "bg-emerald-500/12 text-emerald-500" }
    : me?.username
      ? { label: "Same account", className: "bg-blue-500/12 text-blue-500" }
      : { label: "Not linked", className: "bg-orange-500/12 text-orange-500" };

  const jasperRow = (
    Icon: React.ComponentType<{ className?: string }>,
    title: string,
    subtitle: string,
    onClick: () => void
  ): React.ReactNode => (
    <button
      onClick={onClick}
      className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-secondary/50"
    >
      <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-[#F39057]/12 text-[#F39057]">
        <Icon className="h-5 w-5" />
      </div>
      <div className="min-w-0 flex-1">
        <p className="text-[15px] font-semibold leading-tight">{title}</p>
        <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">{subtitle}</p>
      </div>
    </button>
  );

  return (
    <Section title="Sync with Jasper">
      {!me && jasperHasLocalToken() ? <div className="px-4 py-4 text-sm"><p className="font-semibold">Jasper connection saved</p><p className="mt-1 text-muted-foreground">{meQuery.isFetching ? "Checking your connection…" : "Verification is temporarily unavailable. Your saved connection has not been removed."}</p><button className="mt-2 min-h-11 underline" disabled={meQuery.isFetching} onClick={() => void meQuery.refetch()}>Retry verification</button></div> : me ? (
        <>
          <div className="mx-2 mt-2 flex items-center gap-3 rounded-2xl px-3.5 py-3.5" style={emberGlowCardStyle(dark, 0.5, 16)}>
            <JasperAppIcon size={36} />
            <div className="min-w-0 flex-1">
              <p className="flex items-center gap-2 text-[15px] font-semibold leading-tight">
                Jasper connected
                <span className={`rounded-full px-2 py-0.5 text-[10px] font-black ${resolution.className}`}>
                  {resolution.label}
                </span>
              </p>
              <p className="mt-0.5 truncate text-[13px] leading-snug text-muted-foreground">
                {testNote ??
                  `${me.username ? `@${me.username} · ` : ""}${me.scopes.length} permissions granted`}
              </p>
            </div>
            <div className="flex shrink-0 gap-1.5">
              <button
                aria-label="Test connection"
                title="Test connection"
                onClick={() => {
                  void jasperMe()
                    .then(() => {
                      setTestNote("Connection verified with current permissions");
                      setTimeout(() => setTestNote(null), 4000);
                    })
                    .catch(() => toast("Couldn't verify Jasper right now. Your saved connection has not been removed; try again later."));
                }}
                className="flex h-8 w-8 items-center justify-center rounded-full bg-secondary text-muted-foreground transition-colors hover:text-foreground"
              >
                <JasperZapIcon className="h-3.5 w-3.5" />
              </button>
              <button
                aria-label="Reconnect (rotates the token)"
                title="Reconnect (rotates the token)"
                onClick={() => { setScopes(me.scopes); setShowPermissions(true); }}
                className="flex h-8 w-8 items-center justify-center rounded-full bg-secondary text-muted-foreground transition-colors hover:text-foreground"
              >
                <JasperRotateIcon className="h-3.5 w-3.5" />
              </button>
              <button
                aria-label="Disconnect"
                title="Revoke this web connection"
                onClick={() => setShowDisconnect(true)}
                className="flex h-8 w-8 items-center justify-center rounded-full bg-secondary text-muted-foreground transition-colors hover:text-destructive"
              >
                <JasperUnlinkIcon className="h-3.5 w-3.5" />
              </button>
            </div>
          </div>

          {contractQuery.data && (
            <p className="px-4 pb-3 text-[11px] text-orange-500">{contractQuery.data}</p>
          )}

          {!me.username && me.linked === false ? (
            <p className="px-4 pb-3 text-[12px] text-orange-500">
              No Jasper profile found on this sign-in — link your Jasper account above so Whisper
              sees your real data.
            </p>
          ) : (
            <div className="mx-4 mb-3 rounded-2xl bg-secondary/50 p-3">
              <div className="mb-2 flex items-center justify-between">
                <p className="text-[10px] font-black uppercase tracking-[0.11em] text-muted-foreground">
                  Live from Jasper · last 30 days
                </p>
                <button
                  aria-label="Refresh"
                  onClick={() => void queryClient.invalidateQueries({ queryKey: ["jasper-live-panel"] })}
                  className="text-[#F39057]"
                >
                  <JasperRotateIcon className="h-3 w-3" />
                </button>
              </div>
              {probesQuery.isLoading ? (
                <div className="grid grid-cols-3 gap-1.5">
                  {[0, 1, 2, 3, 4, 5].map((i) => (
                    <div key={i} className="h-[58px] animate-pulse rounded-[10px] bg-secondary" />
                  ))}
                </div>
              ) : probesQuery.data ? (
                <>
                  <div className="grid grid-cols-3 gap-1.5">
                    {probesQuery.data.results.map((r) => (
                      <div key={r.title} className="rounded-[10px] bg-background/70 px-2 py-2 text-center">
                        <r.icon className="mx-auto h-3.5 w-3.5 text-[#F39057]" />
                        <p className="mt-0.5 text-[15px] font-black tabular-nums">{r.count}</p>
                        <p className="text-[9px] font-semibold text-muted-foreground">{r.title}</p>
                        <p className="text-[8px] text-muted-foreground">
                          {r.latest ? timeAgo(r.latest) : "—"}
                        </p>
                      </div>
                    ))}
                  </div>
                  {probesQuery.data.failed.length === 0 && probesQuery.data.results.length > 0 && probesQuery.data.results.every((r) => r.count === 0) && (
                    <p className="mt-2 text-[10.5px] text-muted-foreground">
                      No shared cloud records in this window. Missing records do not mean missed workouts or zero intake.
                    </p>
                  )}
                  {probesQuery.data.failed.length > 0 && (
                    <p className="mt-2 text-[10.5px] text-muted-foreground">
                      Couldn't read: {probesQuery.data.failed.join(", ")} — everything else is live.
                    </p>
                  )}
                </>
              ) : (
                <p className="text-[11px] text-muted-foreground">
                  {probesQuery.error instanceof Error
                    ? probesQuery.error.message
                    : "Couldn't read Jasper right now."}
                </p>
              )}
            </div>
          )}

          {jasperRow(JasperUtensilsIcon, "Diet plan", "Your Jasper plan, live — targets, daily meals, and macros", () => setPanel("diet"))}
          {jasperRow(JasperCartIcon, "Grocery list", "From your active Jasper diet plan — the exact checklist Jasper renders", () => setPanel("grocery"))}
          {jasperRow(JasperBookIcon, "Recipes", "Save here → it's in Jasper's Nutrition → Recipes instantly, and back", () => setPanel("recipes"))}
          {jasperRow(JasperDropsIcon, "Water tracker", "Jasper's animated cup — tap cups straight into your log", () => setPanel("water"))}
        </>
      ) : (
        <button
          onClick={() => setShowPermissions(true)}
          disabled={connectMutation.isPending}
          className="mx-2 my-2 flex w-[calc(100%-1rem)] items-center gap-3 rounded-2xl px-3.5 py-4 text-left transition-transform active:scale-[0.99] disabled:opacity-60"
          style={emberGlowCardStyle(dark, 0.5, 16)}
        >
          <JasperAppIcon size={36} />
          <div className="min-w-0 flex-1">
            <p className="text-[15px] font-semibold leading-tight">
              {connectMutation.isPending ? "Connecting to Jasper…" : "Connect Jasper"}
            </p>
            <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
              Choose what Whisper can read or change. Uses your linked or same Jasper sign-in.
            </p>
          </div>
        </button>
      )}

      <Dialog open={showPermissions} onOpenChange={(open) => { if (!connectMutation.isPending) setShowPermissions(open); }}>
        <DialogContent className="max-h-[85dvh] overflow-y-auto">
          <DialogHeader><DialogTitle>Choose what to share</DialogTitle><DialogDescription>Start with only what you need. Writes are optional. Readable data is never permission to publish it. Private Files and original health reports are not available through Connect.</DialogDescription></DialogHeader>
          <div className="divide-y divide-border">
            {JASPER_SCOPE_OPTIONS.map(([scope, label]) => <label key={scope} className="flex min-h-11 cursor-pointer items-center gap-3 py-3 text-sm">
              <input type="checkbox" checked={scopes.includes(scope)} disabled={connectMutation.isPending} onChange={(event) => setScopes((current) => event.target.checked ? [...current, scope] : current.filter((item) => item !== scope))} />
              <span>{label}</span>
            </label>)}
          </div>
          <button className="min-h-11 rounded-full bg-foreground px-5 text-background disabled:opacity-50" disabled={scopes.length === 0 || connectMutation.isPending} onClick={() => connectMutation.mutate()}>{connectMutation.isPending ? "Connecting…" : "Allow selected permissions"}</button>
          {connectMutation.error && <p role="alert" className="text-sm text-destructive">{connectMutation.error.message}</p>}
        </DialogContent>
      </Dialog>
      <Dialog open={showDisconnect} onOpenChange={(open) => { if (!disconnectMutation.isPending) setShowDisconnect(open); }}>
        <DialogContent><DialogHeader><DialogTitle>Disconnect Jasper?</DialogTitle><DialogDescription>Revoke Whisper Web’s token on Jasper. This does not delete your Jasper records, unlink your accounts, or revoke separate iPhone and coach connections.</DialogDescription></DialogHeader>
          <button className="min-h-11 rounded-full bg-destructive px-5 text-destructive-foreground disabled:opacity-50" disabled={disconnectMutation.isPending} onClick={() => disconnectMutation.mutate()}>{disconnectMutation.isPending ? "Disconnecting…" : "Revoke connection"}</button>
          {disconnectMutation.error && <p role="alert" className="text-sm text-destructive">{disconnectMutation.error.message}</p>}
        </DialogContent>
      </Dialog>
      <JasperDietPlanPanel open={panel === "diet"} onClose={() => setPanel(null)} onOpenGrocery={() => setPanel("grocery")} />
      <JasperGroceryPanel open={panel === "grocery"} onClose={() => setPanel(null)} />
      <JasperRecipesPanel open={panel === "recipes"} onClose={() => setPanel(null)} />
      <JasperWaterPanel open={panel === "water"} onClose={() => setPanel(null)} />
    </Section>
  );
}

function ConnectJasperSection({ userId }: { userId: string | undefined }) {
  const queryClient = useQueryClient();
  const [code, setCode] = useState<string>("");

  const statusQuery = useQuery({
    queryKey: ["jasper-link", userId],
    queryFn: () => fetchJasperLinkStatus(userId!),
    enabled: !!userId,
  });
  const status = statusQuery.data;

  const redeemMutation = useMutation({
    mutationFn: () => redeemJasperLinkCode(code),
    onSuccess: (result) => {
      if (result.ok) {
        setCode("");
        toast("Jasper connected");
        queryClient.invalidateQueries({ queryKey: ["jasper-link", userId] });
      } else if (result.error === "cannot link an account to itself") {
        toast("That code belongs to this same account");
      } else if (result.error === "not authenticated") {
        toast("Please sign in again");
      } else {
        toast("That code is invalid or has expired");
      }
    },
    onError: () => toast("Couldn't connect Jasper — try again"),
  });

  const revokeMutation = useMutation({
    mutationFn: revokeJasperLink,
    onSuccess: (ok) => {
      if (ok) {
        toast("Jasper disconnected");
        queryClient.invalidateQueries({ queryKey: ["jasper-link", userId] });
      } else {
        toast("Couldn't disconnect — try again");
      }
    },
  });

  const canRedeem = code.trim().length >= 6 && !redeemMutation.isPending;

  return (
    <Section title="Jasper">
      {statusQuery.isError && status && <p className="px-4 pt-3 text-xs text-muted-foreground" role="status">Showing your last confirmed account status. The latest check failed; nothing was disconnected. <button type="button" className="underline" onClick={() => void statusQuery.refetch()}>Retry</button></p>}
      {statusQuery.isPending && !status ? <p className="px-4 py-4 text-sm text-muted-foreground" role="status">Checking your saved account link…</p> : statusQuery.isError && !status ? <div className="px-4 py-4 text-sm" role="alert">Your account link couldn’t be checked. Nothing has been disconnected.<button className="ml-2 underline" onClick={() => void statusQuery.refetch()}>Retry</button></div> : status?.isLinked ? (
        <>
          <div className="flex items-center gap-3 px-4 py-3.5">
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-emerald-500/12 text-emerald-500">
              <Check className="h-5 w-5" />
            </div>
            <div className="min-w-0 flex-1">
              <p className="text-[15px] font-semibold leading-tight">
                Connected to Jasper
              </p>
              <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
                {status.linkedAt
                  ? `Linked ${timeAgo(status.linkedAt)} — your fitness data flows into Whisper.`
                  : "Your fitness data flows into Whisper."}
              </p>
            </div>
          </div>
          <button
            onClick={() => { if (window.confirm("Unlink your Jasper accounts? This removes the shared account link on web and iPhone, not just this browser’s connection. You can link again with a new code.")) revokeMutation.mutate(); }}
            disabled={revokeMutation.isPending}
            className="flex w-full items-center gap-3 px-4 py-3.5 text-left text-destructive transition-colors hover:bg-destructive/10 disabled:opacity-60"
          >
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-destructive/10">
              <Link2 className="h-5 w-5" />
            </div>
            <p className="flex-1 text-[15px] font-semibold">
              {revokeMutation.isPending ? "Disconnecting\u2026" : "Unlink Jasper accounts"}
            </p>
          </button>
        </>
      ) : (
        <div className="px-4 py-4">
          <div className="flex items-center gap-3">
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-primary/12 text-primary">
              <Dumbbell className="h-5 w-5" />
            </div>
            <div className="min-w-0 flex-1">
              <p className="text-[15px] font-semibold leading-tight">
                Connect to Jasper
              </p>
              <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
                In Jasper, tap &ldquo;Connect to Whisper&rdquo; to get a code, then paste it here.
              </p>
            </div>
          </div>
          <div className="mt-3 flex gap-2">
            <input
              value={code}
              onChange={(e) => setCode(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter" && canRedeem) {
                  e.preventDefault();
                  redeemMutation.mutate();
                }
              }}
              placeholder="8-character code"
              autoCapitalize="characters"
              autoCorrect="off"
              spellCheck={false}
              maxLength={12}
              className="min-w-0 flex-1 rounded-xl border border-border bg-card px-3.5 py-2.5 text-sm font-medium uppercase tracking-[0.2em] outline-none placeholder:tracking-normal placeholder:normal-case focus:border-foreground/40"
            />
            <button
              onClick={() => redeemMutation.mutate()}
              disabled={!canRedeem}
              className="rounded-xl bg-primary px-4 text-sm font-bold text-primary-foreground transition-transform active:scale-95 disabled:opacity-50"
            >
              {redeemMutation.isPending ? "\u2026" : "Connect"}
            </button>
          </div>
        </div>
      )}
    </Section>
  );
}

/**
 * The client's active coaching subscriptions — lets them cancel a coach
 * at any time. Cancelling stops future renewals; access runs to the end of
 * the paid month. Hidden when there's nothing active.
 */
function CoachSubscriptionsSection({ userId }: { userId: string | undefined }) {
  const queryClient = useQueryClient();
  const subs = useQuery({
    queryKey: ["my-coach-subscriptions", userId ?? ""],
    queryFn: fetchMyCoachSubscriptions,
    enabled: !!userId,
    retry: false,
  });

  const cancel = useMutation({
    mutationFn: (subscriptionId: string) =>
      cancelCoachSubscription(subscriptionId),
    onSuccess: () => {
      toast("Subscription will end after this month");
      queryClient.invalidateQueries({ queryKey: ["my-coach-subscriptions"] });
    },
    onError: () => toast("Couldn't cancel — try again"),
  });

  const rows = subs.data ?? [];
  if (rows.length === 0) return null;

  return (
    <Section title="My coach subscriptions">
      {rows.map((s) => {
        const renewDate = s.currentPeriodEnd
          ? new Date(s.currentPeriodEnd).toLocaleDateString("en-US", {
              month: "short",
              day: "numeric",
            })
          : null;
        return (
          <div key={s.id} className="flex items-center gap-3 px-4 py-3.5">
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-orange-500/12 text-orange-500">
              <Dumbbell className="h-5 w-5" />
            </div>
            <div className="min-w-0 flex-1">
              <p className="truncate text-[15px] font-semibold leading-tight">
                @{s.coachUsername ?? "coach"}
                {s.priceCents ? ` · ${formatCents(s.priceCents)}/mo` : ""}
              </p>
              <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
                {s.cancelAtPeriodEnd
                  ? renewDate
                    ? `Cancelled — access until ${renewDate}`
                    : "Cancelled — access until the end of the month"
                  : renewDate
                    ? `Renews ${renewDate} · cancel anytime`
                    : "Renews monthly · cancel anytime"}
              </p>
            </div>
            {!s.cancelAtPeriodEnd && (
              <button
                onClick={() => {
                  if (
                    window.confirm(
                      `Stop coaching with @${s.coachUsername ?? "this coach"}? You keep access until the end of the paid month.`
                    )
                  ) {
                    cancel.mutate(s.id);
                  }
                }}
                disabled={cancel.isPending}
                className="shrink-0 rounded-full bg-destructive/10 px-3.5 py-2 text-[13px] font-bold text-destructive transition-transform active:scale-95 disabled:opacity-50"
              >
                Cancel
              </button>
            )}
          </div>
        );
      })}
    </Section>
  );
}

function roleStatusText(state: RoleState | undefined): string | null {
  if (!state) return null;
  if (state.active) return "Active";
  if (state.application === "pending") return "In review";
  if (state.application === "approved") return "Approved — activate";
  return null;
}

function SpecialAccountsSection({ userId }: { userId: string | undefined }) {
  const navigate = useNavigate();
  const states = useQuery({
    queryKey: ["special-account-states", userId ?? ""],
    queryFn: () => fetchAllRoleStates(userId!),
    enabled: !!userId,
  });

  const rows: {
    role: SpecialRole;
    icon: React.ReactNode;
    tint: string;
    title: string;
    subtitle: string;
  }[] = [
    {
      role: "coach",
      icon: <Dumbbell className="h-5 w-5" />,
      tint: "bg-orange-500/12 text-orange-500",
      title: "Become a coach",
      subtitle: "Coach badge, programs, and a client roster",
    },
    {
      role: "verified",
      icon: <ShieldCheck className="h-5 w-5" />,
      tint: "bg-sky-500/12 text-sky-500",
      title: "Creator badge",
      subtitle: "The verified check with your niche under your name",
    },
  ];

  const coachApproved =
    states.data?.coach.active ||
    states.data?.coach.application === "approved";

  return (
    <Section title="Special accounts">
      {coachApproved && (
        <button
          onClick={() => navigate("/coach/earnings")}
          className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-secondary/40"
        >
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-emerald-500/12 text-emerald-500">
            <Banknote className="h-5 w-5" />
          </div>
          <div className="min-w-0 flex-1">
            <p className="text-[15px] font-semibold leading-tight">
              Coach earnings
            </p>
            <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
              Set your rate, track income, and cash out
            </p>
          </div>
          <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
        </button>
      )}
      {rows.map((row) => {
        const status = roleStatusText(states.data?.[row.role]);
        return (
          <button
            key={row.role}
            onClick={() => navigate(`/apply/${row.role}`)}
            className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-secondary/40"
          >
            <div
              className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-xl ${row.tint}`}
            >
              {row.icon}
            </div>
            <div className="min-w-0 flex-1">
              <p className="text-[15px] font-semibold leading-tight">
                {row.title}
              </p>
              <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
                {row.subtitle}
              </p>
            </div>
            <span className="flex shrink-0 items-center gap-2">
              {status && (
                <span
                  className={`rounded-full px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide ${
                    status === "Active"
                      ? "bg-emerald-500 text-white"
                      : "bg-secondary text-foreground/70"
                  }`}
                >
                  {status === "Active" ? (
                    <span className="flex items-center gap-1">
                      <BadgeCheck className="h-3 w-3" /> Active
                    </span>
                  ) : (
                    status
                  )}
                </span>
              )}
              <ChevronRight className="h-4 w-4 text-muted-foreground" />
            </span>
          </button>
        );
      })}
    </Section>
  );
}

/**
 * Settings → Account type & tools — the Instagram-style split. Shows the
 * current type (personal / creator / business), switches it inline with a
 * category + contact editor for professional accounts, and surfaces the
 * matching pro dashboards.
 */
function AccountTypeSection() {
  const navigate = useNavigate();
  const { user, profile, refreshProfile } = useAuth();
  const [editing, setEditing] = useState<boolean>(false);
  const [choice, setChoice] = useState<AccountType>("personal");
  const [category, setCategory] = useState<string>("");
  const [contactEmail, setContactEmail] = useState<string>("");
  const [contactPhone, setContactPhone] = useState<string>("");

  const current: AccountType =
    profile?.account_type === "creator" || profile?.account_type === "business"
      ? profile.account_type
      : "personal";

  const openEditor = (): void => {
    setChoice(current);
    setCategory(profile?.professional_category ?? "");
    setContactEmail(profile?.contact_email ?? "");
    setContactPhone(profile?.contact_phone ?? "");
    setEditing(true);
  };

  const save = useMutation({
    mutationFn: () =>
      saveAccountType(user!.id, {
        accountType: choice,
        category,
        contactEmail,
        contactPhone,
      }),
    onSuccess: async () => {
      toast.success(
        choice === "personal"
          ? "Switched to a personal account"
          : `You're a ${choice} account now`
      );
      setEditing(false);
      await refreshProfile();
    },
    onError: (err) =>
      toast.error(err instanceof Error ? err.message : "Couldn't save that."),
  });

  const typeIcon = (t: AccountType): React.ReactNode =>
    t === "creator" ? (
      <Sparkles className="h-5 w-5" />
    ) : t === "business" ? (
      <Briefcase className="h-5 w-5" />
    ) : (
      <User className="h-5 w-5" />
    );

  const typeTint = (t: AccountType): string =>
    t === "creator"
      ? "bg-emerald-500/12 text-emerald-600"
      : t === "business"
        ? "bg-indigo-500/12 text-indigo-500"
        : "bg-secondary text-foreground/70";

  const suggestions = choice === "creator" ? CREATOR_CATEGORIES : BUSINESS_CATEGORIES;

  return (
    <Section title="Account type & tools">
      <div className="flex items-center gap-3 px-4 py-3.5">
        <div className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-xl ${typeTint(current)}`}>
          {typeIcon(current)}
        </div>
        <div className="min-w-0 flex-1">
          <p className="text-[15px] font-semibold leading-tight">
            {accountTypeLabel(current)}
          </p>
          <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
            {current === "personal"
              ? "Standard Whisper account — switch to professional anytime"
              : profile?.professional_category || "Professional account — add a category"}
          </p>
        </div>
        <button
          onClick={() => (editing ? setEditing(false) : openEditor())}
          className="shrink-0 rounded-full border border-border px-3.5 py-1.5 text-[13px] font-semibold transition-transform active:scale-95"
        >
          {editing ? "Close" : "Change"}
        </button>
      </div>

      {editing && (
        <div className="space-y-3 px-4 py-4">
          <div className="space-y-1.5">
            {ACCOUNT_TYPES.map((t) => (
              <button
                key={t.id}
                onClick={() => setChoice(t.id)}
                className={`flex w-full items-center gap-3 rounded-2xl border p-3 text-left transition-colors ${
                  choice === t.id ? "border-foreground/50 bg-secondary/50" : "border-border"
                }`}
              >
                <div className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-xl ${typeTint(t.id)}`}>
                  {typeIcon(t.id)}
                </div>
                <span className="min-w-0 flex-1">
                  <span className="block text-[14px] font-bold leading-tight">
                    {t.label}
                    <span className="ml-1.5 text-[11.5px] font-semibold text-muted-foreground">
                      {t.short}
                    </span>
                  </span>
                  <span className="mt-0.5 block text-[12px] leading-snug text-muted-foreground">
                    {t.blurb}
                  </span>
                </span>
                {choice === t.id && <Check className="h-5 w-5 shrink-0" />}
              </button>
            ))}
          </div>

          {choice !== "personal" && (
            <>
              <div>
                <p className="mb-1.5 text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
                  Category — shows on your profile
                </p>
                <input
                  value={category}
                  onChange={(e) => setCategory(e.target.value)}
                  placeholder={choice === "creator" ? "e.g. Fitness coach" : "e.g. Restaurant"}
                  maxLength={40}
                  className="w-full rounded-xl border border-border bg-card px-3.5 py-2.5 text-sm outline-none focus:border-foreground/40"
                />
                <div className="mt-2 flex flex-wrap gap-1.5">
                  {suggestions.slice(0, 6).map((s) => (
                    <button
                      key={s}
                      onClick={() => setCategory(s)}
                      className={`rounded-full border px-2.5 py-1 text-[11.5px] font-semibold transition-colors ${
                        category === s
                          ? "border-foreground bg-foreground text-background"
                          : "border-border text-muted-foreground hover:text-foreground"
                      }`}
                    >
                      {s}
                    </button>
                  ))}
                </div>
              </div>
              <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                <input
                  value={contactEmail}
                  onChange={(e) => setContactEmail(e.target.value)}
                  placeholder="Contact email (optional)"
                  type="email"
                  className="w-full rounded-xl border border-border bg-card px-3.5 py-2.5 text-sm outline-none focus:border-foreground/40"
                />
                <input
                  value={contactPhone}
                  onChange={(e) => setContactPhone(e.target.value)}
                  placeholder="Contact phone (optional)"
                  type="tel"
                  className="w-full rounded-xl border border-border bg-card px-3.5 py-2.5 text-sm outline-none focus:border-foreground/40"
                />
              </div>
              <p className="text-[11.5px] leading-snug text-muted-foreground">
                Contact details are shown to people who visit your profile — leave
                them blank to keep them private.
              </p>
            </>
          )}

          <button
            onClick={() => save.mutate()}
            disabled={save.isPending || !user}
            className="w-full rounded-full bg-primary py-2.5 text-[14px] font-bold text-primary-foreground transition-transform active:scale-[0.99] disabled:opacity-60"
          >
            {save.isPending ? "Saving…" : "Save account type"}
          </button>
        </div>
      )}

      {/* The pro door — a self-selected creator type gets ANALYTICS (the
          professional tier). Creator Studio is VERIFIED-ONLY and lives in
          its own section below for verified creators. */}
      {current === "creator" && (
        <button
          onClick={() => navigate(isVerifiedCreator(profile) ? "/dashboard" : "/analytics")}
          className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-secondary/40"
        >
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-emerald-500/12 text-emerald-600">
            {isVerifiedCreator(profile) ? <LineChart className="h-5 w-5" /> : <BarChart3 className="h-5 w-5" />}
          </div>
          <div className="min-w-0 flex-1">
            <p className="text-[15px] font-semibold leading-tight">
              {isVerifiedCreator(profile) ? "Creator Studio" : "Analytics"}
            </p>
            <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
              {isVerifiedCreator(profile)
                ? "Score, WPP earnings, and what the algorithm sees"
                : "Reach, interactions, followers, top posts — Creator Studio unlocks with verification"}
            </p>
          </div>
          <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
        </button>
      )}
      {current === "business" && (
        <button
          onClick={() => navigate("/business")}
          className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-secondary/40"
        >
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-indigo-500/12 text-indigo-500">
            <Briefcase className="h-5 w-5" />
          </div>
          <div className="min-w-0 flex-1">
            <p className="text-[15px] font-semibold leading-tight">Business Suite</p>
            <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
              Ads, brand deals, hiring &amp; Business+
            </p>
          </div>
          <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
        </button>
      )}
    </Section>
  );
}

/**
 * Owner/admin/moderator-only section linking to the review dashboard.
 * Reads the whisper_admins table (RLS lets a user see their own row) and
 * falls back to the legacy profile flags.
 */
function AdminSection({ userId }: { userId: string | undefined }) {
  const navigate = useNavigate();
  const adminRole = useQuery<string | null>({
    queryKey: ["my-admin-role", userId ?? ""],
    enabled: !!userId,
    queryFn: async () => {
      const [adm, prof] = await Promise.all([
        supabase
          .from("whisper_admins")
          .select("role")
          .eq("user_id", userId!)
          .limit(1)
          .maybeSingle(),
        supabase
          .from("profiles")
          .select("is_admin,is_moderator,is_owner")
          .eq("id", userId!)
          .limit(1)
          .maybeSingle(),
      ]);
      const tableRole = (adm.data as { role?: string } | null)?.role;
      if (tableRole) return tableRole;
      const p = prof.data as {
        is_admin?: boolean | null;
        is_moderator?: boolean | null;
        is_owner?: boolean | null;
      } | null;
      if (p?.is_owner) return "owner";
      if (p?.is_admin) return "admin";
      if (p?.is_moderator) return "moderator";
      return null;
    },
  });

  if (!adminRole.data) return null;

  return (
    <Section title="Admin">
      <button
        onClick={() => navigate("/admin/applications")}
        className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-secondary/40"
      >
        <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-violet-500/12 text-violet-500">
          <ShieldAlert className="h-5 w-5" />
        </div>
        <div className="min-w-0 flex-1">
          <p className="text-[15px] font-semibold leading-tight">
            Account reviews
          </p>
          <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
            Approve coach, athlete, and verified applications + manage the team
          </p>
        </div>
        <span className="flex shrink-0 items-center gap-2">
          <span className="rounded-full bg-secondary px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide text-foreground/70">
            {adminRole.data}
          </span>
          <ChevronRight className="h-4 w-4 text-muted-foreground" />
        </span>
      </button>
    </Section>
  );
}

/** IG-style group kicker — a quiet uppercase label organizing the sections. */
function GroupKicker({ label }: { label: string }) {
  return (
    <p className="mt-7 px-5 pb-1 text-[11px] font-bold uppercase tracking-[0.12em] text-muted-foreground/70 sm:px-2">
      {label}
    </p>
  );
}

function Section({
  title,
  children,
}: {
  title: string;
  children: React.ReactNode;
}) {
  return (
    <div id={title.toLowerCase().replace(/[^a-z0-9]+/g, "-")} className="mt-6 scroll-mt-20">
      <p className="px-5 pb-2 text-[11px] font-semibold uppercase tracking-[0.12em] text-muted-foreground">
        {title}
      </p>
      <div className="divide-y divide-border/70 overflow-hidden border-y border-border bg-card sm:rounded-[24px] sm:border sm:shadow-none">
        {children}
      </div>
    </div>
  );
}

export default function Settings() {
  const { hash } = useLocation();
  useEffect(() => {
    if (!hash) return;
    const frame = requestAnimationFrame(() => document.getElementById(hash.slice(1))?.scrollIntoView({ block: "start" }));
    return () => cancelAnimationFrame(frame);
  }, [hash]);
  const { user, profile, signOut, refreshProfile } = useAuth();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const myBadge = useMyBadge();
  const isVerified = myBadge !== "none";

  // Coaches and verified creators can write articles — mirrors the
  // backend's badge-author rule and the iOS settings menu.
  const roleStates = useQuery({
    queryKey: ["special-account-states", user?.id ?? ""],
    queryFn: () => fetchAllRoleStates(user!.id),
    enabled: !!user?.id,
  });
  const canWriteArticles = isVerified || !!roleStates.data?.coach.active;
  const {
    settings,
    setGhostMode,
    updateMutedWords,
  } = useSettings();

  const [clearMessagesOpen, setClearMessagesOpen] = useState(false);
  const [clearingMessages, setClearingMessages] = useState(false);
  const [isPrivate, setIsPrivate] = useState<boolean>(!!profile?.is_private);
  const [wordDraft, setWordDraft] = useState<string>("");
  const mutedWords = settings.mutedWords;

  // Appearance — System / Light / Dark / Pitch black, mirroring the iOS
  // Settings → Appearance section (Pitch black = OLED true-black theme).
  const [appearance, setAppearanceState] = useState<AppearanceMode>(getAppearance);
  const chooseAppearance = (mode: AppearanceMode): void => {
    setAppearance(mode);
    setAppearanceState(mode);
  };
  const appearanceIcon = (mode: AppearanceMode): React.ReactNode => {
    if (mode === "light") return <Sun className="h-5 w-5" />;
    if (mode === "dark") return <Moon className="h-5 w-5" />;
    if (mode === "pitch-black") return <Contrast className="h-5 w-5" />;
    return <MonitorSmartphone className="h-5 w-5" />;
  };

  // Security & login — password reset goes through the SAME branded backend
  // endpoint the login screen's "Forgot password?" and the iOS Security
  // Center use (POST /auth/password-reset). Supabase's built-in
  // `resetPasswordForEmail` is intentionally NOT used here: its redirect URL
  // falls back to the project's default Site URL (localhost) on Supabase,
  // and `window.location.origin` is a random preview URL in staging — both
  // produce dead links. The backend handler mints a recovery link that
  // always points at `mydailywhisper.com/reset-password`. The call rides
  // the version-aware resolver: the permanent alias is pinned to an old
  // deploy whose handler still mailed Supabase's action_link (→ localhost).
  const [sendingReset, setSendingReset] = useState<boolean>(false);
  const handleChangePassword = async (): Promise<void> => {
    if (!user?.email) {
      toast("No email is attached to this account");
      return;
    }
    setSendingReset(true);
    try {
      const base = await resolveBackend();
      const res = await fetch(`${base}/auth/password-reset`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: user.email }),
      });
      if (!res.ok) throw new Error("reset_failed");
      toast(`Password reset link sent to ${user.email}`);
    } catch {
      toast("Couldn't send the reset email — try again");
    } finally {
      setSendingReset(false);
    }
  };

  // Recruiter review — if this user signed up via a recruiter's referral
  // code, show a "Rate your recruiter" row so they can leave a 1–5 star
  // rating + review. The founder uses these to see which recruiters perform.
  const [showReviewSheet, setShowReviewSheet] = useState<boolean>(false);
  const myRecruiter = useQuery({
    queryKey: ["my-recruiter", user?.id],
    queryFn: () => fetchMyRecruiter(),
    enabled: !!user?.id && !profile?.is_recruiter,
    staleTime: 5 * 60 * 1000,
  });

  const privacyMutation = useMutation({
    mutationFn: (next: boolean) => setProfilePrivacy(user!.id, next),
    onMutate: (next) => setIsPrivate(next),
    onError: () => {
      setIsPrivate((v) => !v);
      toast("Couldn't update privacy");
    },
    onSuccess: async () => {
      await refreshProfile();
      queryClient.invalidateQueries({ queryKey: ["profile"] });
    },
  });


  const addWord = (): void => {
    const w = wordDraft.trim().toLowerCase();
    if (!w) return;
    if (mutedWords.includes(w)) {
      setWordDraft("");
      return;
    }
    updateMutedWords([...mutedWords, w]);
    setWordDraft("");
  };

  const removeWord = (word: string): void => {
    updateMutedWords(mutedWords.filter((w) => w !== word));
  };

  const handleSignOut = async (): Promise<void> => {
    await signOut();
    navigate("/auth");
  };

  // Security — end EVERY session (this device included), Instagram-style.
  const [signingOutAll, setSigningOutAll] = useState<boolean>(false);
  const handleSignOutEverywhere = async (): Promise<void> => {
    if (signingOutAll) return;
    setSigningOutAll(true);
    try {
      await supabase.auth.signOut({ scope: "global" });
      toast("Signed out on every device");
      navigate("/auth");
    } catch {
      toast("Couldn't sign out everywhere — try again");
    } finally {
      setSigningOutAll(false);
    }
  };

  // Your activity — real counts straight from the tables (cheap head counts):
  // interactions (likes · comments · reposts · saved) and content you shared
  // (whisps · waves · live stories). Mirrors the iOS Your-activity hub.
  const activityQuery = useQuery({
    queryKey: ["settings-activity", user?.id],
    enabled: !!user?.id,
    staleTime: 60_000,
    queryFn: async () => {
      const uid = user!.id;
      const head = (table: string) =>
        supabase.from(table).select("*", { count: "exact", head: true }).eq("user_id", uid);
      const [posts, waves, saved, likes, comments, reposts, stories] = await Promise.all([
        head("whisper_posts"),
        supabase
          .from("whisper_posts")
          .select("*", { count: "exact", head: true })
          .eq("user_id", uid)
          .eq("is_reel", true),
        head("whisper_bookmarks"),
        head("whisper_post_likes"),
        head("whisper_post_comments"),
        head("whisper_reposts"),
        supabase
          .from("whisper_stories")
          .select("*", { count: "exact", head: true })
          .eq("user_id", uid)
          .gt("expires_at", new Date().toISOString()),
      ]);
      const wavesCount = waves.count ?? 0;
      return {
        posts: Math.max(0, (posts.count ?? 0) - wavesCount),
        waves: wavesCount,
        saved: saved.count ?? 0,
        likes: likes.count ?? 0,
        comments: comments.count ?? 0,
        reposts: reposts.count ?? 0,
        stories: stories.error ? 0 : stories.count ?? 0,
      };
    },
  });
  const memberSince = useMemo(() => {
    const raw = user?.created_at;
    if (!raw) return null;
    return new Date(raw).toLocaleDateString(undefined, {
      month: "long",
      year: "numeric",
    });
  }, [user?.created_at]);

  const displayName = useMemo(
    () => profile?.display_name || profile?.username || "You",
    [profile]
  );

  return (
    <div>
      <Header
        title="Settings"
        left={
          <button
            onClick={() => navigate(-1)}
            aria-label="Back"
            className="glass flex h-10 w-10 items-center justify-center rounded-full border border-border/60 shadow-sm transition-transform active:scale-90"
          >
            <ArrowLeft className="h-5 w-5" />
          </button>
        }
        right={<span className="h-10 w-10" />}
      />

      <div className="px-0 pt-0 sm:px-0 sm:pt-2">
        {/* Account header */}
        <button
          onClick={() => navigate("/profile")}
          className="flex w-full items-center gap-3.5 overflow-hidden border-y border-border bg-card px-4 py-4 text-left transition-colors hover:bg-secondary/40 sm:rounded-[24px] sm:border sm:shadow-none"
        >
          <Avatar
            url={profile?.profile_image_url}
            name={profile?.username}
            size={56}
          />
          <div className="min-w-0 flex-1">
            <p className="truncate text-[17px] font-bold leading-tight">{displayName}</p>
            <p className="mt-0.5 truncate text-sm text-muted-foreground">
              @{profile?.username ?? "you"}
            </p>
          </div>
          <span className="shrink-0 rounded-full border border-border px-3.5 py-1.5 text-[13px] font-semibold">
            Edit
          </span>
        </button>

        <div id="decisions" className="my-4 scroll-mt-20"><SafetyDecisions /></div>
        <Section title="Your account">
          <button
            onClick={() => navigate("/profile?edit=1")}
            className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-secondary/40"
          >
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-secondary text-foreground/70">
              <UserPen className="h-5 w-5" />
            </div>
            <div className="min-w-0 flex-1">
              <p className="text-[15px] font-semibold leading-tight">Edit profile</p>
              <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
                Name, bio, photo, and interests
              </p>
            </div>
            <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
          </button>
          <button
            onClick={() => navigate("/saved")}
            className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-secondary/40"
          >
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-secondary text-foreground/70">
              <Bookmark className="h-5 w-5" />
            </div>
            <div className="min-w-0 flex-1">
              <p className="text-[15px] font-semibold leading-tight">Saved posts</p>
              <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
                Everything you’ve bookmarked
              </p>
            </div>
            <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
          </button>
          {/* Recruiter review — only shown for users who signed up via a
              recruiter's referral code, so they can rate their experience. */}
          {myRecruiter.data && (
            <button
              onClick={() => setShowReviewSheet(true)}
              className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-secondary/40"
            >
              <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-amber-500/10 text-amber-500">
                <Star className="h-5 w-5" />
              </div>
              <div className="min-w-0 flex-1">
                <p className="text-[15px] font-semibold leading-tight">
                  Rate your recruiter
                </p>
                <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
                  How was your experience with @{myRecruiter.data.username ?? "your recruiter"}?
                </p>
              </div>
              <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
            </button>
          )}
        </Section>

        <AccountTypeSection />

        <GroupKicker label="How you use Whisper" />
        {/* YOUR ACTIVITY — Instagram's hub on Whisper's real tables (iOS
            parity): Interactions · Content you shared · Account history. Every
            count is a live head-count query; nothing is estimated. */}
        <Section title="Your activity">
          <p className="px-4 pb-1 pt-3 text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
            Interactions
          </p>
          {(
            [
              { key: "likes", icon: <Heart className="h-5 w-5" />, title: "Likes", detail: "Posts you’ve liked", to: "/activity", count: activityQuery.data?.likes },
              { key: "comments", icon: <MessageCircle className="h-5 w-5" />, title: "Comments", detail: "Replies you’ve left on posts", to: "/activity", count: activityQuery.data?.comments },
              { key: "reposts", icon: <Repeat2 className="h-5 w-5" />, title: "Reposts", detail: "Posts you’ve shared to your profile", to: "/profile", count: activityQuery.data?.reposts },
              { key: "saved", icon: <Bookmark className="h-5 w-5" />, title: "Saved", detail: "Posts you’ve bookmarked to revisit", to: "/saved", count: activityQuery.data?.saved },
            ] as const
          ).map((row) => (
            <button
              key={row.key}
              onClick={() => navigate(row.to)}
              className="flex w-full items-center gap-3 px-4 py-3 text-left transition-colors hover:bg-secondary/40"
            >
              <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-secondary text-foreground/70">
                {row.icon}
              </div>
              <div className="min-w-0 flex-1">
                <p className="text-[15px] font-semibold leading-tight">{row.title}</p>
                <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">{row.detail}</p>
              </div>
              {typeof row.count === "number" && (
                <span className="shrink-0 rounded-full bg-secondary px-2.5 py-0.5 text-[12px] font-bold tabular-nums">
                  {row.count}
                </span>
              )}
              <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
            </button>
          ))}

          <p className="px-4 pb-1 pt-3 text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
            Content you shared
          </p>
          {(
            [
              { key: "posts", icon: <PenLine className="h-5 w-5" />, title: "Posts", detail: "Text and media posts on your profile", to: "/profile", count: activityQuery.data?.posts },
              { key: "waves", icon: <Play className="h-5 w-5" />, title: "Waves", detail: "Short videos on your Waves tab", to: "/profile", count: activityQuery.data?.waves },
              { key: "stories", icon: <CircleDashed className="h-5 w-5" />, title: "Stories", detail: "Live right now (stories last 24 hours)", to: "/profile", count: activityQuery.data?.stories },
            ] as const
          ).map((row) => (
            <button
              key={row.key}
              onClick={() => navigate(row.to)}
              className="flex w-full items-center gap-3 px-4 py-3 text-left transition-colors hover:bg-secondary/40"
            >
              <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-secondary text-foreground/70">
                {row.icon}
              </div>
              <div className="min-w-0 flex-1">
                <p className="text-[15px] font-semibold leading-tight">{row.title}</p>
                <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">{row.detail}</p>
              </div>
              {typeof row.count === "number" && (
                <span className="shrink-0 rounded-full bg-secondary px-2.5 py-0.5 text-[12px] font-bold tabular-nums">
                  {row.count}
                </span>
              )}
              <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
            </button>
          ))}

          <p className="px-4 pb-1 pt-3 text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
            Account history
          </p>
          <div className="flex w-full items-center gap-3 px-4 py-3">
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-secondary text-foreground/70">
              <User className="h-5 w-5" />
            </div>
            <div className="min-w-0 flex-1">
              <p className="text-[15px] font-semibold leading-tight">@{profile?.username ?? "you"}</p>
              <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
                {memberSince ? `Member since ${memberSince} · ` : ""}
                {tierLabel(profile)}
                {isVerifiedCreator(profile) ? " · Verified" : ""}
              </p>
            </div>
          </div>
        </Section>

        <GroupKicker label="Account security" />
        <Section title="Security">
          <button
            onClick={handleChangePassword}
            disabled={sendingReset}
            className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-secondary/40 disabled:opacity-60"
          >
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-secondary text-foreground/70">
              <KeyRound className="h-5 w-5" />
            </div>
            <div className="min-w-0 flex-1">
              <p className="text-[15px] font-semibold leading-tight">
                {sendingReset ? "Sending reset link…" : "Change password"}
              </p>
              <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
                We’ll email you a secure reset link
              </p>
            </div>
            <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
          </button>
          <div className="w-full px-4 py-3.5">
            <div className="flex items-center gap-3">
              <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-secondary text-foreground/70">
                <MonitorSmartphone className="h-5 w-5" />
              </div>
              <div className="min-w-0 flex-1">
                <p className="text-[15px] font-semibold leading-tight">Where you’re logged in</p>
                <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
                  1 active session in this browser
                </p>
              </div>
            </div>
            {/* The device card — iOS parity: glyph tile, device + THIS DEVICE chip,
                live dot, OS/browser line, then Account / Signed in rows. */}
            <div className="mt-3 overflow-hidden rounded-2xl border border-border/70 bg-secondary/30">
              <div className="flex items-center gap-3 p-3">
                <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl border border-border/70 bg-background text-foreground">
                  <MonitorSmartphone className="h-5 w-5" strokeWidth={1.8} />
                </div>
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-1.5">
                    <p className="text-[14px] font-semibold leading-tight">{describeDevice()}</p>
                    <span className="rounded-full border border-border/70 bg-background px-1.5 py-0.5 text-[9.5px] font-black tracking-[0.06em] text-muted-foreground">
                      THIS DEVICE
                    </span>
                  </div>
                  <p className="mt-0.5 truncate text-[12px] text-muted-foreground">{describeBrowser()}</p>
                </div>
                <span className="flex shrink-0 items-center gap-1.5 text-[12px] font-semibold text-emerald-500">
                  <span className="h-[7px] w-[7px] rounded-full bg-emerald-500" />
                  Active now
                </span>
              </div>
              <div className="border-t border-border/70">
                <div className="flex items-baseline gap-3 px-3 py-2.5">
                  <span className="w-[72px] shrink-0 text-[12px] font-semibold text-muted-foreground">Account</span>
                  <span className="truncate text-[12px]">{user?.email ?? "—"}</span>
                </div>
                <div className="ml-3 border-t border-border/70" />
                <div className="flex items-baseline gap-3 px-3 py-2.5">
                  <span className="w-[72px] shrink-0 text-[12px] font-semibold text-muted-foreground">Signed in</span>
                  <span className="truncate text-[12px]">
                    {user?.last_sign_in_at
                      ? `${new Date(user.last_sign_in_at).toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" })} · ${new Date(user.last_sign_in_at).toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" })} (${timeAgo(user.last_sign_in_at)})`
                      : "—"}
                  </span>
                </div>
              </div>
            </div>
            <p className="mt-2 text-[11px] leading-snug text-muted-foreground">
              Whisper can only see this browser’s session. To end every other login, use Sign out of all devices below.
            </p>
          </div>
          <button
            onClick={() => void handleSignOutEverywhere()}
            disabled={signingOutAll}
            className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-secondary/40 disabled:opacity-60"
          >
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-red-500/10 text-red-500">
              <LogOut className="h-5 w-5" />
            </div>
            <div className="min-w-0 flex-1">
              <p className="text-[15px] font-semibold leading-tight">
                {signingOutAll ? "Signing out everywhere…" : "Sign out of all devices"}
              </p>
              <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
                Ends every session, including this one
              </p>
            </div>
            <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
          </button>
        </Section>

        <GroupKicker label="What you see" />
        <Section title="Appearance">
          {APPEARANCE_MODES.map((mode) => (
            <button
              key={mode.id}
              onClick={() => chooseAppearance(mode.id)}
              className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-secondary/40"
            >
              <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-secondary text-foreground/70">
                {appearanceIcon(mode.id)}
              </div>
              <div className="min-w-0 flex-1">
                <p className="text-[15px] font-semibold leading-tight">{mode.label}</p>
                <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
                  {mode.subtitle}
                </p>
              </div>
              {appearance === mode.id && (
                <Check className="h-5 w-5 shrink-0 text-foreground" />
              )}
            </button>
          ))}
        </Section>

        <GroupKicker label="Payments & memberships" />
        <Section title="Membership">
          <button
            onClick={() => navigate("/one")}
            className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-secondary/40"
          >
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-foreground text-background">
              <Plus className="h-5 w-5" />
            </div>
            <div className="min-w-0 flex-1">
              <p className="text-[15px] font-semibold leading-tight">Whisper One</p>
              <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
                The membership — perks, boosts, and the One badge
              </p>
            </div>
            <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
          </button>
        </Section>

        {isVerified && (
          <Section title="Verification">
            <div className="flex items-center gap-3 px-4 py-3.5">
              <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-sky-500/12 text-sky-500">
                <Sparkles className="h-5 w-5" />
              </div>
              <div className="min-w-0 flex-1">
                <p className="text-[15px] font-semibold leading-tight">
                  You&rsquo;re verified
                </p>
                <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
                  Algorithm boost, priority push, trending nudge.
                </p>
              </div>
            </div>
            <button
              onClick={() => navigate("/dashboard")}
              className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-secondary/40"
            >
              <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-violet-500/12 text-violet-500">
                <LineChart className="h-5 w-5" />
              </div>
              <div className="min-w-0 flex-1">
                <p className="text-[15px] font-semibold leading-tight">
                  Creator Studio
                </p>
                <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
                  Analytics, top posts, what the algorithm sees.
                </p>
              </div>
              <span className="flex items-center gap-2 shrink-0">
                <span className="rounded-full bg-violet-500 px-1.5 py-0.5 text-[10px] font-bold text-white">
                  NEW
                </span>
                <ChevronRight className="h-4 w-4 text-muted-foreground" />
              </span>
            </button>
          </Section>
        )}

        <SpecialAccountsSection userId={user?.id} />

        <CoachSubscriptionsSection userId={user?.id} />

        <BillingRefundsSection />

        <AdminSection userId={user?.id} />

        <ConnectJasperSection userId={user?.id} />

        <SyncWithJasperSection />

        <GroupKicker label="More from Whisper" />
        <Section title="Discover">
          <button
            onClick={() => navigate("/search")}
            className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-secondary/40"
          >
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-secondary text-foreground/70">
              <Users className="h-5 w-5" />
            </div>
            <div className="min-w-0 flex-1">
              <p className="text-[15px] font-semibold leading-tight">Find people</p>
              <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
                Search creators, coaches, and friends
              </p>
            </div>
            <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
          </button>
        </Section>

        <Section title="Also from Whisper">
          <a
            href="https://apps.apple.com/us/app/jasper-fitness-made-easy/id6753958717"
            target="_blank"
            rel="noreferrer"
            className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-secondary/40"
          >
            <JasperAppIcon size={36} />
            <div className="min-w-0 flex-1">
              <p className="text-[15px] font-semibold leading-tight">Get Jasper</p>
              <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
                Fitness made easy — download on the App Store
              </p>
            </div>
            <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
          </a>
          <a
            href="https://thejasperapp.com"
            target="_blank"
            rel="noreferrer"
            className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-secondary/40"
          >
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-secondary text-foreground/70">
              <Globe className="h-5 w-5" />
            </div>
            <p className="flex-1 text-[15px] font-semibold">thejasperapp.com</p>
            <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
          </a>
        </Section>

        <GroupKicker label="Who can see your content" />
        <Section title="Privacy">
          <Row
            icon={<Lock className="h-5 w-5" />}
            title="Private account"
            subtitle="Only approved followers can see your whispers"
            control={
              <Switch
                checked={isPrivate}
                onCheckedChange={(v) => privacyMutation.mutate(v)}
              />
            }
          />
          <Row
            icon={<Ghost className="h-5 w-5" />}
            title="Ghost mode"
            subtitle="Hide your activity and read receipts"
            control={
              <Switch
                checked={settings.ghostMode}
                onCheckedChange={setGhostMode}
              />
            }
          />
        </Section>

        <GroupKicker label="How others can interact with you" />
        <Section title="Notifications">
          <RemotePushSettings />
        </Section>

        <Section title="Muted words">
          <div className="px-4 py-4">
            <p className="text-[13px] leading-snug text-muted-foreground">
              Whispers containing these words are hidden from your feed.
            </p>
            <div className="mt-3 flex gap-2">
              <input
                value={wordDraft}
                onChange={(e) => setWordDraft(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") {
                    e.preventDefault();
                    addWord();
                  }
                }}
                placeholder="Add a word or phrase"
                className="min-w-0 flex-1 rounded-xl border border-border bg-card px-3.5 py-2.5 text-sm outline-none focus:border-foreground/40"
              />
              <button
                onClick={addWord}
                className="rounded-xl bg-primary px-4 text-sm font-bold text-primary-foreground transition-transform active:scale-95"
              >
                Add
              </button>
            </div>
            {mutedWords.length > 0 && (
              <div className="mt-3 flex flex-wrap gap-2">
                {mutedWords.map((word) => (
                  <span
                    key={word}
                    className="flex items-center gap-1.5 rounded-full bg-secondary py-1.5 pl-3 pr-1.5 text-[13px] font-medium"
                  >
                    {word}
                    <button
                      onClick={() => removeWord(word)}
                      aria-label={`Unmute ${word}`}
                      className="flex h-5 w-5 items-center justify-center rounded-full text-muted-foreground transition-colors hover:bg-foreground/10 hover:text-foreground"
                    >
                      <X className="h-3.5 w-3.5" />
                    </button>
                  </span>
                ))}
              </div>
            )}
          </div>
        </Section>

        <GroupKicker label="Storage" />
        <Section title="On this browser">
          <button onClick={() => setClearMessagesOpen(true)} className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-secondary/40">
            <Trash2 className="h-5 w-5 shrink-0 text-muted-foreground" />
            <div className="flex-1">
              <p className="text-[15px] font-semibold">Clear cached messages</p>
              <p className="mt-1 text-[13px] text-muted-foreground">Remove saved text here, not your chat history or pending sends.</p>
            </div>
            <ChevronRight className="h-4 w-4 text-muted-foreground" />
          </button>
        </Section>
        <Dialog open={clearMessagesOpen} onOpenChange={setClearMessagesOpen}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Clear cached messages?</DialogTitle>
              <DialogDescription>Only saved text in this browser is removed. Your messages on Whisper and pending sends stay safe. Open chats can save a new copy after their next refresh.</DialogDescription>
            </DialogHeader>
            <div className="flex justify-end gap-3 pt-3">
              <button className="rounded-xl px-4 py-2 text-sm font-semibold hover:bg-secondary" onClick={() => setClearMessagesOpen(false)} disabled={clearingMessages}>Cancel</button>
              <button className="rounded-xl bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-50" disabled={clearingMessages || !user} onClick={async () => {
                if (!user) return;
                setClearingMessages(true);
                const cleared = await clearMessageSnapshots(user.id);
                setClearingMessages(false);
                if (cleared) { setClearMessagesOpen(false); toast.success("Cached messages cleared"); }
                else toast.error("Saved messages couldn’t be cleared. Please try again.");
              }}>{clearingMessages ? "Clearing…" : "Clear cached messages"}</button>
            </div>
          </DialogContent>
        </Dialog>

        <GroupKicker label="Login & account" />
        <Section title="Account">
          {canWriteArticles && (
            <button
              onClick={() => navigate("/studio/articles")}
              className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-secondary/40"
            >
              <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-secondary text-foreground/70">
                <PenLine className="h-5 w-5" />
              </div>
              <div className="min-w-0 flex-1">
                <p className="text-[15px] font-semibold leading-tight">
                  Write articles
                </p>
                <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
                  Open to coaches, athletes &amp; verified creators — publish
                  under your name
                </p>
              </div>
              <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
            </button>
          )}
          <button
            onClick={() => navigate("/safety")}
            className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-secondary/40"
          >
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-secondary text-foreground/70">
              <ShieldAlert className="h-5 w-5" />
            </div>
            <div className="min-w-0 flex-1">
              <p className="text-[15px] font-semibold leading-tight">
                Safety &amp; reports
              </p>
              <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
                Reviewed corrections, private reports, and protection limits
              </p>
            </div>
            <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
          </button>
          <button
            onClick={() => navigate("/support")}
            className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-secondary/40"
          >
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-secondary text-foreground/70">
              <Flag className="h-5 w-5" />
            </div>
            <div className="min-w-0 flex-1">
              <p className="text-[15px] font-semibold leading-tight">
                Report a problem
              </p>
              <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
                Something broken or someone out of line — tell us
              </p>
            </div>
            <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
          </button>
          <button
            onClick={handleSignOut}
            className="flex w-full items-center gap-3 px-4 py-3.5 text-left text-destructive transition-colors hover:bg-destructive/10"
          >
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-destructive/10">
              <LogOut className="h-5 w-5" />
            </div>
            <p className="flex-1 text-[15px] font-semibold">Log out</p>
          </button>
          <button
            onClick={() =>
              toast("Account deletion is permanent — contact support to proceed")
            }
            className="flex w-full items-center gap-3 px-4 py-3.5 text-left text-destructive transition-colors hover:bg-destructive/10"
          >
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-destructive/10">
              <Trash2 className="h-5 w-5" />
            </div>
            <p className="flex-1 text-[15px] font-semibold">Delete account</p>
          </button>
        </Section>

        <GroupKicker label="More info & support" />
        <Section title="About">
          <button
            onClick={() => navigate("/about")}
            className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-secondary/40"
          >
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-secondary text-foreground/70">
              <Info className="h-5 w-5" />
            </div>
            <p className="flex-1 text-[15px] font-semibold">About Whisper</p>
            <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
          </button>
          <button
            onClick={() => navigate("/privacy")}
            className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-secondary/40"
          >
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-secondary text-foreground/70">
              <Lock className="h-5 w-5" />
            </div>
            <p className="flex-1 text-[15px] font-semibold">Privacy policy</p>
            <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
          </button>
          <button
            onClick={() => navigate("/terms")}
            className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-secondary/40"
          >
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-secondary text-foreground/70">
              <FileText className="h-5 w-5" />
            </div>
            <p className="flex-1 text-[15px] font-semibold">Terms of service</p>
            <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
          </button>
          <a
            href="https://www.mydailywhisper.com"
            target="_blank"
            rel="noreferrer"
            className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition-colors hover:bg-secondary/40"
          >
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-secondary text-foreground/70">
              <Globe className="h-5 w-5" />
            </div>
            <p className="flex-1 text-[15px] font-semibold">mydailywhisper.com</p>
            <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
          </a>
        </Section>

        <p className="px-5 py-6 text-center text-xs text-muted-foreground">
          Whisper for web
        </p>
      </div>

      {showReviewSheet && myRecruiter.data && (
        <RecruiterReviewSheet
          recruiterId={myRecruiter.data.recruiterId}
          recruiterUsername={myRecruiter.data.username}
          onClose={() => setShowReviewSheet(false)}
        />
      )}
    </div>
  );
}
