import { useMemo, useState } from "react";
import { AlertDialog, AlertDialogContent, AlertDialogHeader, AlertDialogTitle, AlertDialogDescription, AlertDialogFooter, AlertDialogCancel, AlertDialogAction } from '@/components/ui/alert-dialog';
import { useNavigate } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  BadgeCheck,
  Briefcase,
  CalendarDays,
  Check,
  ChevronDown,
  Copy,
  Landmark,
  Link2,
  Loader2,
  Lock,
  MessagesSquare,
  Pencil,
  Plus,
  Presentation,
  Trash2,
  UserPlus,
  Users,
  Video,
  X,
} from "lucide-react";
import { toast } from "sonner";

import { Avatar } from "@/components/Avatar";
import { BusinessPlusMark } from "@/components/BusinessPlusMark";
import { Input } from "@/components/ui/input";
import { EmbeddedCheckoutSheet } from "@/components/EmbeddedCheckoutSheet";
import { GroupThreadView } from "@/components/GroupChats";
import { useAuth } from "@/hooks/useAuth";
import { cn } from "@/lib/utils";
import { timeAgo } from "@/lib/format";
import {
  BUSINESS_PLUS_PERKS,
  BUSINESS_PLUS_PLANS,
  startEmbeddedCheckout,
  type BusinessPlusPlan,
  type EmbeddedCheckoutResult,
} from "@/lib/billing";
import {
  MEETING_LEAD_PROMPT,
  ROLE_ACCENTS,
  STARTER_QUESTIONS,
  addTeamMember,
  businessApplyUrl,
  createBusinessEvent,
  deleteBusinessEvent,
  deletePosition,
  deleteQuestion,
  ensureHqGroup,
  ensureTeamChat,
  fetchApplications,
  fetchBusinessEvents,
  fetchMyBusinessPlus,
  fetchPositions,
  fetchQuestions,
  fetchTeam,
  hqGroupSlug,
  removeTeamMember,
  savePosition,
  saveQuestion,
  setApplicationStatus,
  setCompanyName,
  updateTeamMember,
  type BusinessApplicationRow,
  type MyBusinessPlus,
} from "@/lib/businessPlus";
import { fetchMyGroupThreads } from "@/lib/groupChats";
import { meetingLink } from "@/lib/meetings";
import { supabase } from "@/lib/supabase";

const INDIGO = "#5A5FE8";

const EVENT_TYPES: { id: string; label: string; color: string }[] = [
  { id: "meet", label: "Meeting", color: "#0E9F76" },
  { id: "training", label: "Training", color: "#E8853D" },
  { id: "deadline", label: "Deadline", color: "#D5484F" },
  { id: "other", label: "Other", color: "#5A5FE8" },
];

/** Mints a fresh Whisper Meet link — wsp codes hash to the same room on
 *  every device, and the first arriver quietly creates the room. */
function mintTeamMeetLink(): string {
  const block = (): string =>
    Math.random().toString(36).replace(/[^a-z0-9]/g, "").slice(0, 4).padEnd(4, "x");
  return meetingLink(`wsp-${block()}-${block()}`);
}

/** The subscribe pitch — perks, plan pick, embedded checkout. */
function PlusPitch() {
  const { user, session } = useAuth();
  const [plan, setPlan] = useState<BusinessPlusPlan>("business-plus-monthly");
  const [starting, setStarting] = useState<boolean>(false);
  const [embedded, setEmbedded] = useState<EmbeddedCheckoutResult | null>(null);

  const subscribe = async (): Promise<void> => {
    if (!user) {
      toast("Sign in first.");
      return;
    }
    setStarting(true);
    try {
      const result = await startEmbeddedCheckout(plan, {
        userId: user.id,
        email: session?.user?.email ?? "",
      });
      setEmbedded(result);
    } catch (err) {
      toast(err instanceof Error ? err.message : "Couldn't start checkout.");
    } finally {
      setStarting(false);
    }
  };

  return (
    <div className="mx-auto max-w-2xl">
      <div
        className="overflow-hidden rounded-[24px] border p-6"
        style={{
          borderColor: `${INDIGO}40`,
          background: `linear-gradient(150deg, ${INDIGO}14, transparent 55%)`,
        }}
      >
        <div className="flex items-center gap-3">
          <span
            className="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl text-white shadow-lg"
            style={{ background: `linear-gradient(135deg, ${INDIGO}, #8B8FF5)` }}
          >
            <BusinessPlusMark className="h-7 w-7" strokeWidth={2.1} />
          </span>
          <p
            className="text-[11px] font-black uppercase tracking-[0.2em]"
            style={{ color: INDIGO }}
          >
            Business+
          </p>
        </div>
        <h2 className="mt-2.5 font-display text-[26px] font-extrabold leading-tight">
          Your company's workspace on Whisper.
        </h2>
        <p className="mt-1.5 max-w-md text-[13.5px] leading-relaxed text-muted-foreground">
          Meeting tools and the Notebook come with every account — Business+
          makes them yours: your team, your roles, your hiring questions, your
          private HQ, your calendar.
        </p>

        <div className="mt-4 space-y-2">
          {BUSINESS_PLUS_PERKS.map((perk, i) => (
            <div
              key={perk}
              className="flex items-start gap-2.5 rounded-2xl border border-border bg-card px-3.5 py-2.5"
              style={{ animationDelay: `${i * 60}ms` }}
            >
              <span
                className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-white"
                style={{ background: INDIGO }}
              >
                <Check className="h-3 w-3" />
              </span>
              <p className="text-[13px] font-semibold leading-snug">{perk}</p>
            </div>
          ))}
        </div>

        <div className="mt-4 grid grid-cols-2 gap-2">
          {(Object.keys(BUSINESS_PLUS_PLANS) as BusinessPlusPlan[]).map((p) => {
            const meta = BUSINESS_PLUS_PLANS[p];
            const active = plan === p;
            return (
              <button
                key={p}
                onClick={() => setPlan(p)}
                className={cn(
                  "rounded-2xl border p-3.5 text-left transition-colors",
                  active ? "bg-card" : "border-border bg-card/60"
                )}
                style={active ? { borderColor: INDIGO, boxShadow: `0 0 0 1px ${INDIGO}` } : undefined}
              >
                <p className="text-[12px] font-black uppercase tracking-wider text-muted-foreground">
                  {p === "business-plus-monthly" ? "Monthly" : "Annual"}
                </p>
                <p className="mt-1 text-[22px] font-extrabold">
                  {meta.price}
                  <span className="text-[13px] font-semibold text-muted-foreground">
                    {meta.detail}
                  </span>
                </p>
                <p className="text-[11.5px] text-muted-foreground">{meta.blurb}</p>
              </button>
            );
          })}
        </div>

        <button
          onClick={() => void subscribe()}
          disabled={starting || !user}
          className="mt-4 flex h-12 w-full items-center justify-center gap-2 rounded-full text-[15px] font-bold text-white transition-transform active:scale-[0.99] disabled:opacity-50"
          style={{ background: `linear-gradient(135deg, ${INDIGO}, #7A7FF0)` }}
        >
          {starting ? <Loader2 className="h-4 w-4 animate-spin" /> : <BusinessPlusMark className="h-4 w-4" strokeWidth={2.6} />}
          Activate Business+
        </button>
        <p className="mt-2 text-center text-[11.5px] text-muted-foreground">
          Secured by Stripe · 14-day refund window · cancel anytime
        </p>
      </div>

      {embedded && (
        <EmbeddedCheckoutSheet
          clientSecret={embedded.clientSecret}
          publishableKey={embedded.publishableKey}
          brief={{
            title: `Whisper Business+ · ${plan === "business-plus-annual" ? "Annual" : "Monthly"}`,
            price: BUSINESS_PLUS_PLANS[plan].price,
            cadence: BUSINESS_PLUS_PLANS[plan].detail,
            note: "Cancel anytime · 14-day refund window",
            perks: BUSINESS_PLUS_PERKS,
            refundDays: 14,
          }}
          onClose={() => setEmbedded(null)}
          onComplete={() => {
            setEmbedded(null);
            window.location.href = "/billing/success?embedded=1";
          }}
        />
      )}
    </div>
  );
}

type PlusTab = "team" | "hiring" | "calendar" | "hq";

const PLUS_TABS: { id: PlusTab; label: string; icon: typeof Users }[] = [
  { id: "team", label: "Team & roles", icon: Users },
  { id: "hiring", label: "Hiring", icon: Briefcase },
  { id: "calendar", label: "Team calendar", icon: CalendarDays },
  { id: "hq", label: "HQ & chat", icon: MessagesSquare },
];

function SectionCard({
  title,
  hint,
  children,
}: {
  title: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="rounded-[20px] border border-border bg-card p-4">
      <p className="text-[14px] font-extrabold">{title}</p>
      {hint && (
        <p className="mt-0.5 text-[12px] leading-snug text-muted-foreground">{hint}</p>
      )}
      <div className="mt-3">{children}</div>
    </div>
  );
}

/** One application row — match bar, best-fit chip, status controls. */
function ApplicationRow({
  app,
  isOwner,
  onStatus,
}: {
  app: BusinessApplicationRow;
  isOwner: boolean;
  onStatus: (status: BusinessApplicationRow["status"]) => void;
}) {
  const [open, setOpen] = useState<boolean>(false);
  const scoreEntries = Object.entries(app.position_scores ?? {}).sort((a, b) => b[1] - a[1]);
  return (
    <div className="rounded-2xl border border-border bg-background p-3">
      <button onClick={() => setOpen((v) => !v)} className="flex w-full items-center gap-3 text-left">
        <Avatar name={app.applicant_username} size={36} />
        <span className="min-w-0 flex-1">
          <span className="flex items-center gap-1.5">
            <span className="truncate text-[13.5px] font-bold">@{app.applicant_username}</span>
            {app.created_at && (
              <span className="shrink-0 text-[11px] text-muted-foreground">
                {timeAgo(app.created_at)}
              </span>
            )}
          </span>
          <span className="mt-1 flex items-center gap-2">
            <span className="h-1.5 w-24 overflow-hidden rounded-full bg-secondary">
              <span
                className="block h-full rounded-full"
                style={{
                  width: `${Math.max(4, app.match_score)}%`,
                  background: app.match_score >= 60 ? "#0E9F76" : app.match_score >= 30 ? "#E8853D" : "#8B93B0",
                }}
              />
            </span>
            <span className="text-[11.5px] font-bold">{app.match_score}% match</span>
            {app.best_position && (
              <span
                className="truncate rounded-full px-2 py-0.5 text-[10.5px] font-black"
                style={{ background: `${INDIGO}14`, color: INDIGO }}
              >
                {app.best_position}
              </span>
            )}
            {app.answers.some((a) => a.prompt === MEETING_LEAD_PROMPT) && (
              <span className="shrink-0 rounded-full bg-emerald-500/10 px-2 py-0.5 text-[10.5px] font-black text-emerald-600">
                Met in a meeting
              </span>
            )}
          </span>
        </span>
        <ChevronDown className={cn("h-4 w-4 shrink-0 text-muted-foreground transition-transform", open && "rotate-180")} />
      </button>
      {open && (
        <div className="mt-3 space-y-2 border-t border-border pt-3">
          {scoreEntries.length > 0 && (
            <div className="flex flex-wrap gap-1.5">
              {scoreEntries.map(([title, score]) => (
                <span key={title} className="rounded-full bg-secondary px-2 py-0.5 text-[10.5px] font-bold text-muted-foreground">
                  {title} · {score}%
                </span>
              ))}
            </div>
          )}
          {app.answers.map((a, i) => (
            <div key={i}>
              <p className="text-[11px] font-black uppercase tracking-wider text-muted-foreground">
                {a.prompt}
              </p>
              <p className="mt-0.5 whitespace-pre-wrap text-[13px] leading-snug">{a.answer}</p>
            </div>
          ))}
          {isOwner && (
            <div className="flex gap-1.5 pt-1">
              {(["new", "shortlist", "passed"] as const).map((s) => (
                <button
                  key={s}
                  onClick={() => onStatus(s)}
                  className={cn(
                    "rounded-full border px-3 py-1 text-[11.5px] font-bold capitalize transition-colors",
                    app.status === s
                      ? "border-foreground bg-foreground text-background"
                      : "border-border text-muted-foreground"
                  )}
                >
                  {s === "new" ? "New" : s === "shortlist" ? "Shortlist" : "Pass"}
                </button>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

/** The live Business+ home — team, hiring, calendar, HQ. */
function PlusHome({ me }: { me: MyBusinessPlus }) {
  const { user, profile } = useAuth();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [tab, setTab] = useState<PlusTab>("team");

  const businessId = me.business.user_id;
  const isOwner = me.isOwner;
  const owner = { id: businessId, username: profile?.username ?? "owner" };
  const meAsPerson = { id: user?.id ?? "", username: profile?.username ?? "you" };
  const company = me.business.company_name?.trim() || `${profile?.username ?? "Your"}'s company`;

  // Company name edit (owner)
  const [editingName, setEditingName] = useState<boolean>(false);
  const [nameDraft, setNameDraft] = useState<string>(me.business.company_name ?? "");
  const saveName = useMutation({
    mutationFn: () => setCompanyName(me.business.id, nameDraft),
    onSuccess: () => {
      toast("Company name saved");
      setEditingName(false);
      void queryClient.invalidateQueries({ queryKey: ["my-business-plus"] });
    },
    onError: (err: Error) => toast(err.message),
  });

  // Team
  const teamQuery = useQuery({
    queryKey: ["bp-team", businessId, user?.id],
    queryFn: () => fetchTeam(businessId),
    gcTime: 0,
    refetchOnWindowFocus: true,
    refetchInterval: 20000,
    retry: false,
  });
  const team = teamQuery.data ?? [];
  const [newUsername, setNewUsername] = useState<string>("");
  const [newRole, setNewRole] = useState<string>("");
  const [newAccent, setNewAccent] = useState<string>(ROLE_ACCENTS[0]);
  const addMember = useMutation({
    mutationFn: () =>
      addTeamMember({ businessId, username: newUsername, roleTitle: newRole, accent: newAccent }),
    onSuccess: () => {
      toast(`@${newUsername.trim().replace(/^@/, "")} joined the team`);
      setNewUsername("");
      setNewRole("");
      void queryClient.invalidateQueries({ queryKey: ["bp-team", businessId] });
    },
    onError: (err: Error) => toast(err.message),
  });
  const [editingMember, setEditingMember] = useState<string | null>(null);
  const [memberRoleDraft, setMemberRoleDraft] = useState<string>("");
  const [memberAccentDraft, setMemberAccentDraft] = useState<string>(ROLE_ACCENTS[0]);

  const [removing, setRemoving] = useState<{ id: string; username: string } | null>(null);
  const editMember = useMutation({
    mutationFn: (id: string) => updateTeamMember(businessId, id, { role_title: memberRoleDraft.trim() || 'Team member', accent: memberAccentDraft }),
    onSuccess: () => { setEditingMember(null); void queryClient.invalidateQueries({ queryKey: ['bp-team', businessId] }); },
    onError: (error: Error) => toast.error(error.message),
  });
  const removeMember = useMutation({
    mutationFn: (id: string) => removeTeamMember(businessId, id),
    onSuccess: () => { setRemoving(null); setEditingMember(null); void queryClient.invalidateQueries({ queryKey: ['bp-team', businessId] }); void queryClient.invalidateQueries({ queryKey: ['jasper-work-members'] }); },
    onError: (error: Error) => toast.error(error.message),
  });

  // Hiring
  const positionsQuery = useQuery({
    queryKey: ["bp-positions", businessId],
    queryFn: () => fetchPositions(businessId),
  });
  const positions = positionsQuery.data ?? [];
  const questionsQuery = useQuery({
    queryKey: ["bp-questions", businessId],
    queryFn: () => fetchQuestions(businessId),
  });
  const questions = questionsQuery.data ?? [];
  const applicationsQuery = useQuery({
    queryKey: ["bp-applications", businessId],
    queryFn: () => fetchApplications(businessId),
    enabled: tab === "hiring",
  });
  const [posTitle, setPosTitle] = useState<string>("");
  const [posKeywords, setPosKeywords] = useState<string>("");
  const [posBlurb, setPosBlurb] = useState<string>("");
  const addPosition = useMutation({
    mutationFn: () =>
      savePosition({
        businessId,
        title: posTitle,
        blurb: posBlurb,
        keywords: posKeywords.split(","),
        isOpen: true,
      }),
    onSuccess: () => {
      toast("Position published");
      setPosTitle("");
      setPosKeywords("");
      setPosBlurb("");
      void queryClient.invalidateQueries({ queryKey: ["bp-positions", businessId] });
    },
    onError: (err: Error) => toast(err.message),
  });
  const [questionDraft, setQuestionDraft] = useState<string>("");
  const addQuestion = useMutation({
    mutationFn: (prompt: string) =>
      saveQuestion({ businessId, prompt, displayOrder: questions.length }),
    onSuccess: () => {
      setQuestionDraft("");
      void queryClient.invalidateQueries({ queryKey: ["bp-questions", businessId] });
    },
    onError: (err: Error) => toast(err.message),
  });

  // Calendar
  const eventsQuery = useQuery({
    queryKey: ["bp-events", businessId],
    queryFn: () => fetchBusinessEvents(businessId),
    enabled: tab === "calendar",
  });
  const [evTitle, setEvTitle] = useState<string>("");
  const [evWhen, setEvWhen] = useState<string>("");
  const [evType, setEvType] = useState<string>("meet");
  const [evDuration, setEvDuration] = useState<number>(60);
  const [evMeet, setEvMeet] = useState<boolean>(false);
  const addEvent = useMutation({
    mutationFn: () => {
      if (!evTitle.trim() || !evWhen) throw new Error("Give it a title and a time.");
      return createBusinessEvent({
        businessId,
        createdBy: meAsPerson,
        title: evTitle,
        eventType: evType,
        startISO: new Date(evWhen).toISOString(),
        durationMinutes: evDuration,
        meetingLink: evMeet ? mintTeamMeetLink() : undefined,
      });
    },
    onSuccess: () => {
      toast("Added to the team calendar");
      setEvTitle("");
      setEvWhen("");
      setEvMeet(false);
      void queryClient.invalidateQueries({ queryKey: ["bp-events", businessId] });
    },
    onError: (err: Error) => toast(err.message),
  });

  // HQ + team chat
  const hqQuery = useQuery({
    queryKey: ["bp-hq", businessId],
    queryFn: async () => {
      const { data } = await supabase
        .from("whisper_communities")
        .select("slug")
        .eq("slug", hqGroupSlug(businessId))
        .limit(1)
        .maybeSingle();
      return !!data;
    },
  });
  const openHq = useMutation({
    mutationFn: async () => {
      if (isOwner) {
        return ensureHqGroup({ business: me.business, owner: meAsPerson, team });
      }
      if (!hqQuery.data) throw new Error("Ask the owner to open the HQ group first.");
      return hqGroupSlug(businessId);
    },
    onSuccess: (slug) => navigate(`/c/${slug}`),
    onError: (err: Error) => toast(err.message),
  });
  const threadsQuery = useQuery({
    queryKey: ["group-threads"],
    queryFn: fetchMyGroupThreads,
  });
  const teamThread = (threadsQuery.data ?? []).find((t) => t.business_id === businessId) ?? null;
  const startChat = useMutation({
    mutationFn: () => ensureTeamChat({ business: me.business, owner: meAsPerson, team }),
    onSuccess: () => {
      toast("Team chat is live");
      void queryClient.invalidateQueries({ queryKey: ["group-threads"] });
    },
    onError: (err: Error) => toast(err.message),
  });

  const shareUrl = businessApplyUrl(businessId, me.business.company_name);

  return (
    <div className="mx-auto max-w-2xl space-y-4">
      {/* Header */}
      <div
        className="rounded-[24px] border p-5"
        style={{
          borderColor: `${INDIGO}40`,
          background: `linear-gradient(150deg, ${INDIGO}12, transparent 60%)`,
        }}
      >
        <div className="flex items-center gap-2">
          <span
            className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg text-white"
            style={{ background: `linear-gradient(135deg, ${INDIGO}, #8B8FF5)` }}
          >
            <BusinessPlusMark className="h-[18px] w-[18px]" strokeWidth={2.4} />
          </span>
          <p
            className="text-[11px] font-black uppercase tracking-[0.2em]"
            style={{ color: INDIGO }}
          >
            Business+
          </p>
          <span className="rounded-full bg-emerald-500/10 px-2 py-0.5 text-[10px] font-black uppercase tracking-wide text-emerald-600">
            Active · {me.business.plan.includes("annual") ? "annual" : "monthly"}
          </span>
        </div>
        {editingName ? (
          <div className="mt-2 flex items-center gap-2">
            <Input
              value={nameDraft}
              onChange={(e) => setNameDraft(e.target.value)}
              placeholder="Company name"
              maxLength={60}
            />
            <button
              onClick={() => saveName.mutate()}
              disabled={saveName.isPending || !nameDraft.trim()}
              className="flex h-10 shrink-0 items-center gap-1 rounded-full bg-foreground px-4 text-[13px] font-bold text-background disabled:opacity-50"
            >
              {saveName.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Check className="h-3.5 w-3.5" />}
              Save
            </button>
          </div>
        ) : (
          <h2 className="mt-1.5 flex items-center gap-2 font-display text-[24px] font-extrabold leading-tight">
            {company}
            {isOwner && (
              <button
                onClick={() => {
                  setNameDraft(me.business.company_name ?? "");
                  setEditingName(true);
                }}
                className="rounded-full p-1.5 text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground"
                aria-label="Rename company"
              >
                <Pencil className="h-4 w-4" />
              </button>
            )}
          </h2>
        )}
        <p className="mt-0.5 text-[12.5px] text-muted-foreground">
          You: <span className="font-bold text-foreground">{me.roleTitle}</span>
          {" · "}
          {team.length + 1} on the team
        </p>
      </div>

      {/* Sub-tabs */}
      <div className="no-scrollbar flex gap-1.5 overflow-x-auto">
        {PLUS_TABS.map((t) => (
          <button
            key={t.id}
            onClick={() => setTab(t.id)}
            className={cn(
              "flex shrink-0 items-center gap-1.5 rounded-full border px-3.5 py-2 text-[12.5px] font-bold transition-colors",
              tab === t.id
                ? "border-foreground bg-foreground text-background"
                : "border-border bg-card text-muted-foreground"
            )}
          >
            <t.icon className="h-3.5 w-3.5" />
            {t.label}
          </button>
        ))}
      </div>

      {/* TEAM */}
      {tab === "team" && (
        <SectionCard
          title="Team & roles"
          hint="Add people by exact Whisper username. Only the owner manages membership; role titles do not grant owner permissions."
        >
          {teamQuery.isError && <p role="alert" className="mb-3 text-sm text-destructive">Team could not load. <button className="min-h-11 underline" onClick={() => void teamQuery.refetch()}>Retry team</button></p>}
          {teamQuery.isPending && <p role="status" className="mb-3 text-sm">Loading team…</p>}
          {isOwner && !teamQuery.isError && !teamQuery.isPending && (
            <div className="mb-3 space-y-2 rounded-2xl border border-dashed border-border p-3">
              <div className="grid grid-cols-2 gap-2">
                <Input
                  value={newUsername}
                  onChange={(e) => setNewUsername(e.target.value)}
                  placeholder="@username"
                  aria-label="Exact teammate username"
                />
                <Input
                  value={newRole}
                  onChange={(e) => setNewRole(e.target.value)}
                  placeholder="Role title — e.g. Head of Sales"
                  maxLength={40}
                />
              </div>
              <div className="flex items-center gap-1.5">
                {ROLE_ACCENTS.map((accent) => (
                  <button
                    key={accent}
                    onClick={() => setNewAccent(accent)}
                    className={cn(
                      "h-6 w-6 rounded-full transition-transform",
                      newAccent === accent && "scale-110 ring-2 ring-foreground ring-offset-2 ring-offset-card"
                    )}
                    style={{ background: accent }}
                    aria-label={`Accent ${accent}`}
                  />
                ))}
                <button
                  onClick={() => addMember.mutate()}
                  disabled={addMember.isPending || !newUsername.trim()}
                  className="ml-auto flex h-9 items-center gap-1.5 rounded-full bg-foreground px-4 text-[12.5px] font-bold text-background transition-transform active:scale-95 disabled:opacity-50"
                >
                  {addMember.isPending ? (
                    <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  ) : (
                    <UserPlus className="h-3.5 w-3.5" />
                  )}
                  Add person
                </button>
              </div>
            </div>
          )}
          <div className="space-y-1.5">
            {/* The owner row */}
            <div className="flex items-center gap-3 rounded-2xl bg-secondary/40 px-3 py-2.5">
              <Avatar name={isOwner ? meAsPerson.username : "owner"} size={36} />
              <span className="min-w-0 flex-1">
                <span className="block truncate text-[13.5px] font-bold">
                  {isOwner ? `@${meAsPerson.username}` : "The owner"}
                </span>
              </span>
              <span
                className="rounded-full px-2.5 py-1 text-[10.5px] font-black uppercase tracking-wide text-white"
                style={{ background: "#D9408C" }}
              >
                Owner
              </span>
            </div>
            {!teamQuery.isError && team.map((m) => (
              <div key={m.user_id} className="rounded-2xl border border-border px-3 py-2.5">
                <div className="flex items-center gap-3">
                  <Avatar name={m.username} size={36} />
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-[13.5px] font-bold">@{m.username}</span>
                  </span>
                  <span
                    className="max-w-[140px] truncate rounded-full px-2.5 py-1 text-[10.5px] font-black uppercase tracking-wide text-white"
                    style={{ background: m.accent }}
                  >
                    {m.role_title}
                  </span>
                  {isOwner && (
                    <button
                      onClick={() => {
                        setEditingMember(editingMember === m.user_id ? null : m.user_id);
                        setMemberRoleDraft(m.role_title);
                        setMemberAccentDraft(m.accent);
                      }}
                      className="rounded-full p-1.5 text-muted-foreground transition-colors hover:bg-secondary"
                      aria-label="Edit role"
                    >
                      <Pencil className="h-3.5 w-3.5" />
                    </button>
                  )}
                </div>
                {isOwner && editingMember === m.user_id && (
                  <div className="mt-2.5 space-y-2 border-t border-border pt-2.5">
                    <Input
                      value={memberRoleDraft}
                      onChange={(e) => setMemberRoleDraft(e.target.value)}
                      placeholder="Role title"
                      maxLength={40}
                    />
                    <div className="flex items-center gap-1.5">
                      {ROLE_ACCENTS.map((accent) => (
                        <button
                          key={accent}
                          onClick={() => setMemberAccentDraft(accent)}
                          className={cn(
                            "h-6 w-6 rounded-full transition-transform",
                            memberAccentDraft === accent &&
                              "scale-110 ring-2 ring-foreground ring-offset-2 ring-offset-card"
                          )}
                          style={{ background: accent }}
                          aria-label={`Accent ${accent}`}
                        />
                      ))}
                      <button
                        disabled={editMember.isPending || removeMember.isPending}
                        onClick={() => editMember.mutate(m.user_id)}
                        className="ml-auto rounded-full bg-foreground px-3.5 py-1.5 text-[12px] font-bold text-background"
                      >
                        Save
                      </button>
                      <button
                        disabled={editMember.isPending || removeMember.isPending}
                        onClick={() => setRemoving({ id: m.user_id, username: m.username })}
                        className="rounded-full p-1.5 text-destructive transition-colors hover:bg-destructive/10"
                        aria-label="Remove member"
                      >
                        <Trash2 className="h-4 w-4" />
                      </button>
                    </div>
                  </div>
                )}
              </div>
            ))}
            {!teamQuery.isPending && !teamQuery.isError && team.length === 0 && (
              <p className="py-3 text-center text-[12.5px] text-muted-foreground">
                {isOwner
                  ? "Nobody on the team yet — add your first person above."
                  : "No teammates yet."}
              </p>
            )}
          </div>
          <AlertDialog open={removing !== null} onOpenChange={(open) => { if (!open && !removeMember.isPending) setRemoving(null); }}><AlertDialogContent><AlertDialogHeader><AlertDialogTitle>Remove @{removing?.username}?</AlertDialogTitle><AlertDialogDescription>They will lose access to this team workspace. Existing chats and group memberships are not changed.</AlertDialogDescription></AlertDialogHeader><AlertDialogFooter><AlertDialogCancel disabled={removeMember.isPending}>Cancel</AlertDialogCancel><AlertDialogAction disabled={removeMember.isPending} onClick={(event) => { event.preventDefault(); if (removing) removeMember.mutate(removing.id); }}>{removeMember.isPending ? 'Removing…' : 'Remove from team'}</AlertDialogAction></AlertDialogFooter></AlertDialogContent></AlertDialog>
        </SectionCard>
      )}

      {/* HIRING */}
      {tab === "hiring" && (
        <>
          <SectionCard
            title="Your application link"
            hint="Share it anywhere — applicants answer YOUR questions and Whisper auto-matches them to your open positions."
          >
            <div className="flex items-center gap-2">
              <span className="min-w-0 flex-1 truncate rounded-full bg-secondary px-3.5 py-2.5 text-[12.5px] font-semibold">
                {shareUrl}
              </span>
              <button
                onClick={() => {
                  void navigator.clipboard.writeText(shareUrl);
                  toast("Link copied");
                }}
                className="flex h-10 shrink-0 items-center gap-1.5 rounded-full bg-foreground px-4 text-[12.5px] font-bold text-background transition-transform active:scale-95"
              >
                <Copy className="h-3.5 w-3.5" />
                Copy
              </button>
            </div>
          </SectionCard>

          <SectionCard
            title="Open positions"
            hint="Keywords power the auto-match — an applicant whose answers hit them scores higher."
          >
            <div className="space-y-1.5">
              {positions.map((p) => (
                <div key={p.id} className="flex items-start gap-2.5 rounded-2xl border border-border p-3">
                  <span className="min-w-0 flex-1">
                    <span className="flex items-center gap-1.5">
                      <span className="truncate text-[13.5px] font-bold">{p.title}</span>
                      <span
                        className={cn(
                          "rounded-full px-2 py-0.5 text-[9.5px] font-black uppercase",
                          p.is_open
                            ? "bg-emerald-500/10 text-emerald-600"
                            : "bg-secondary text-muted-foreground"
                        )}
                      >
                        {p.is_open ? "Open" : "Closed"}
                      </span>
                    </span>
                    {p.blurb && (
                      <span className="mt-0.5 block text-[12px] text-muted-foreground">{p.blurb}</span>
                    )}
                    {p.keywords.length > 0 && (
                      <span className="mt-1 flex flex-wrap gap-1">
                        {p.keywords.map((k) => (
                          <span key={k} className="rounded-full bg-secondary px-2 py-0.5 text-[10.5px] font-semibold text-muted-foreground">
                            {k}
                          </span>
                        ))}
                      </span>
                    )}
                  </span>
                  {isOwner && (
                    <span className="flex shrink-0 items-center gap-1">
                      <button
                        onClick={() => {
                          void savePosition({
                            id: p.id,
                            businessId,
                            title: p.title,
                            blurb: p.blurb,
                            keywords: p.keywords,
                            isOpen: !p.is_open,
                          }).then(() =>
                            queryClient.invalidateQueries({ queryKey: ["bp-positions", businessId] })
                          );
                        }}
                        className="rounded-full border border-border px-2.5 py-1 text-[11px] font-bold text-muted-foreground transition-colors hover:text-foreground"
                      >
                        {p.is_open ? "Close" : "Reopen"}
                      </button>
                      <button
                        onClick={() => {
                          void deletePosition(p.id).then(() =>
                            queryClient.invalidateQueries({ queryKey: ["bp-positions", businessId] })
                          );
                        }}
                        className="rounded-full p-1.5 text-destructive transition-colors hover:bg-destructive/10"
                        aria-label="Delete position"
                      >
                        <Trash2 className="h-3.5 w-3.5" />
                      </button>
                    </span>
                  )}
                </div>
              ))}
              {positions.length === 0 && (
                <p className="py-2 text-center text-[12.5px] text-muted-foreground">
                  No positions yet{isOwner ? " — publish your first below." : "."}
                </p>
              )}
            </div>
            {isOwner && (
              <div className="mt-3 space-y-2 rounded-2xl border border-dashed border-border p-3">
                <div className="grid grid-cols-2 gap-2">
                  <Input
                    value={posTitle}
                    onChange={(e) => setPosTitle(e.target.value)}
                    placeholder="Position — e.g. Social media manager"
                    maxLength={60}
                  />
                  <Input
                    value={posKeywords}
                    onChange={(e) => setPosKeywords(e.target.value)}
                    placeholder="Match keywords — social, content, reels"
                  />
                </div>
                <Input
                  value={posBlurb}
                  onChange={(e) => setPosBlurb(e.target.value)}
                  placeholder="One-line description (optional)"
                  maxLength={120}
                />
                <button
                  onClick={() => addPosition.mutate()}
                  disabled={addPosition.isPending || !posTitle.trim()}
                  className="flex h-9 items-center gap-1.5 rounded-full bg-foreground px-4 text-[12.5px] font-bold text-background transition-transform active:scale-95 disabled:opacity-50"
                >
                  {addPosition.isPending ? (
                    <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  ) : (
                    <Plus className="h-3.5 w-3.5" />
                  )}
                  Publish position
                </button>
              </div>
            )}
          </SectionCard>

          <SectionCard
            title="Your application questions"
            hint="Applicants answer these on your link — in your words, not a generic form."
          >
            <div className="space-y-1.5">
              {questions.map((q, i) => (
                <div key={q.id} className="flex items-center gap-2.5 rounded-2xl border border-border px-3 py-2.5">
                  <span
                    className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-[11px] font-black text-white"
                    style={{ background: INDIGO }}
                  >
                    {i + 1}
                  </span>
                  <span className="min-w-0 flex-1 text-[13px] font-semibold leading-snug">{q.prompt}</span>
                  {isOwner && (
                    <button
                      onClick={() => {
                        void deleteQuestion(q.id).then(() =>
                          queryClient.invalidateQueries({ queryKey: ["bp-questions", businessId] })
                        );
                      }}
                      className="rounded-full p-1.5 text-destructive transition-colors hover:bg-destructive/10"
                      aria-label="Delete question"
                    >
                      <Trash2 className="h-3.5 w-3.5" />
                    </button>
                  )}
                </div>
              ))}
              {questions.length === 0 && (
                <p className="py-2 text-center text-[12.5px] text-muted-foreground">
                  No questions yet — applicants currently just introduce themselves.
                </p>
              )}
            </div>
            {isOwner && (
              <div className="mt-3 flex items-center gap-2">
                <Input
                  value={questionDraft}
                  onChange={(e) => setQuestionDraft(e.target.value)}
                  placeholder="Write a question…"
                  maxLength={160}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" && questionDraft.trim()) addQuestion.mutate(questionDraft);
                  }}
                />
                <button
                  onClick={() => questionDraft.trim() && addQuestion.mutate(questionDraft)}
                  disabled={addQuestion.isPending || !questionDraft.trim()}
                  className="flex h-10 shrink-0 items-center gap-1 rounded-full bg-foreground px-4 text-[12.5px] font-bold text-background disabled:opacity-50"
                >
                  <Plus className="h-3.5 w-3.5" />
                  Add
                </button>
              </div>
            )}
            {isOwner && questions.length === 0 && (
              <button
                onClick={() => {
                  void Promise.all(
                    STARTER_QUESTIONS.map((prompt, i) =>
                      saveQuestion({ businessId, prompt, displayOrder: i })
                    )
                  ).then(() =>
                    queryClient.invalidateQueries({ queryKey: ["bp-questions", businessId] })
                  );
                }}
                className="mt-2 text-[12.5px] font-bold"
                style={{ color: INDIGO }}
              >
                Use the starter questions →
              </button>
            )}
          </SectionCard>

          <SectionCard
            title={`Applicants${(applicationsQuery.data ?? []).length > 0 ? ` · ${(applicationsQuery.data ?? []).length}` : ""}`}
            hint="Auto-matched to your open positions from their answers — best fits float up."
          >
            <div className="space-y-2">
              {(applicationsQuery.data ?? [])
                .slice()
                .sort((a, b) => b.match_score - a.match_score)
                .map((app) => (
                  <ApplicationRow
                    key={app.id}
                    app={app}
                    isOwner={isOwner}
                    onStatus={(status) => {
                      void setApplicationStatus(app.id, status).then(() =>
                        queryClient.invalidateQueries({ queryKey: ["bp-applications", businessId] })
                      );
                    }}
                  />
                ))}
              {(applicationsQuery.data ?? []).length === 0 && (
                <p className="py-2 text-center text-[12.5px] text-muted-foreground">
                  No applications yet — share your link to start the pipeline.
                </p>
              )}
            </div>
          </SectionCard>
        </>
      )}

      {/* CALENDAR */}
      {tab === "calendar" && (
        <SectionCard
          title="Team calendar"
          hint="Internal to your business — never on the shared Whisper calendar. Toggle Meet link to attach a ready-to-join room."
        >
          <div className="mb-3 space-y-2 rounded-2xl border border-dashed border-border p-3">
            <div className="grid grid-cols-2 gap-2">
              <Input
                value={evTitle}
                onChange={(e) => setEvTitle(e.target.value)}
                placeholder="Event — e.g. Weekly standup"
                maxLength={80}
              />
              <Input
                type="datetime-local"
                value={evWhen}
                onChange={(e) => setEvWhen(e.target.value)}
              />
            </div>
            <div className="flex flex-wrap items-center gap-1.5">
              {EVENT_TYPES.map((t) => (
                <button
                  key={t.id}
                  onClick={() => setEvType(t.id)}
                  className={cn(
                    "flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-[11.5px] font-bold transition-colors",
                    evType === t.id ? "border-foreground" : "border-border text-muted-foreground"
                  )}
                >
                  <span className="h-2 w-2 rounded-full" style={{ background: t.color }} />
                  {t.label}
                </button>
              ))}
              <button
                onClick={() => setEvMeet((v) => !v)}
                className={cn(
                  "flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-[11.5px] font-bold transition-colors",
                  evMeet ? "border-foreground" : "border-border text-muted-foreground"
                )}
              >
                <Video className="h-3.5 w-3.5" style={evMeet ? { color: "#0E9F76" } : undefined} />
                Meet link
              </button>
              <select
                value={evDuration}
                onChange={(e) => setEvDuration(Number(e.target.value))}
                className="rounded-full border border-border bg-background px-3 py-1.5 text-[11.5px] font-bold outline-none"
              >
                <option value={30}>30 min</option>
                <option value={60}>1 hour</option>
                <option value={90}>90 min</option>
              </select>
              <button
                onClick={() => addEvent.mutate()}
                disabled={addEvent.isPending}
                className="ml-auto flex h-9 items-center gap-1.5 rounded-full bg-foreground px-4 text-[12.5px] font-bold text-background transition-transform active:scale-95 disabled:opacity-50"
              >
                {addEvent.isPending ? (
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                ) : (
                  <Plus className="h-3.5 w-3.5" />
                )}
                Add
              </button>
            </div>
          </div>
          <div className="space-y-1.5">
            {(eventsQuery.data ?? []).map((ev) => {
              const type = EVENT_TYPES.find((t) => t.id === ev.event_type) ?? EVENT_TYPES[3];
              const start = new Date(ev.start_time);
              const canDelete = isOwner || ev.created_by === user?.id;
              return (
                <div key={ev.id} className="flex items-center gap-3 rounded-2xl border border-border px-3 py-2.5">
                  <span className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ background: type.color }} />
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-[13.5px] font-bold">{ev.title}</span>
                    <span className="block text-[11.5px] text-muted-foreground">
                      {start.toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" })}
                      {" · "}
                      {start.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" })}
                      {" · "}@{ev.created_by_username}
                    </span>
                  </span>
                  {ev.meeting_link && (
                    <a
                      href={ev.meeting_link}
                      target="_blank"
                      rel="noreferrer"
                      className="flex h-8 shrink-0 items-center gap-1 rounded-full px-3 text-[11.5px] font-bold text-white transition-transform active:scale-95"
                      style={{ background: "#0E9F76" }}
                    >
                      <Video className="h-3.5 w-3.5" />
                      Join
                    </a>
                  )}
                  {canDelete && (
                    <button
                      onClick={() => {
                        void deleteBusinessEvent(ev.id).then(() =>
                          queryClient.invalidateQueries({ queryKey: ["bp-events", businessId] })
                        );
                      }}
                      className="rounded-full p-1.5 text-destructive transition-colors hover:bg-destructive/10"
                      aria-label="Delete event"
                    >
                      <Trash2 className="h-3.5 w-3.5" />
                    </button>
                  )}
                </div>
              );
            })}
            {(eventsQuery.data ?? []).length === 0 && (
              <p className="py-2 text-center text-[12.5px] text-muted-foreground">
                Nothing scheduled — add the first team event above.
              </p>
            )}
          </div>
        </SectionCard>
      )}

      {/* HQ & CHAT */}
      {tab === "hq" && (
        <>
          <SectionCard
            title="Private HQ group"
            hint="An invite-only space on Whisper — only your team sees what's posted inside."
          >
            <div className="flex items-center gap-3">
              <span
                className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl text-white"
                style={{ backgroundImage: `linear-gradient(135deg, ${INDIGO}, #8B8FF5)` }}
              >
                <Lock className="h-5 w-5" />
              </span>
              <span className="min-w-0 flex-1">
                <span className="block text-[13.5px] font-bold">{company} HQ</span>
                <span className="block text-[12px] text-muted-foreground">
                  {hqQuery.data
                    ? "Live — your team is invited automatically."
                    : isOwner
                      ? "One tap creates it and invites the whole team."
                      : "Not open yet — the owner creates it."}
                </span>
              </span>
              <button
                onClick={() => openHq.mutate()}
                disabled={openHq.isPending || (!isOwner && !hqQuery.data)}
                className="flex h-9 shrink-0 items-center gap-1.5 rounded-full bg-foreground px-4 text-[12.5px] font-bold text-background transition-transform active:scale-95 disabled:opacity-50"
              >
                {openHq.isPending ? (
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                ) : (
                  <Link2 className="h-3.5 w-3.5" />
                )}
                {hqQuery.data ? "Open" : "Create & open"}
              </button>
            </div>
          </SectionCard>

          <SectionCard
            title="Team chat"
            hint="A group chat in DMs with the whole team — it works on the iPhone app too."
          >
            {teamThread ? (
              <GroupThreadView group={teamThread} me={meAsPerson} />
            ) : (
              <button
                onClick={() => startChat.mutate()}
                disabled={startChat.isPending || !isOwner}
                className="flex h-11 w-full items-center justify-center gap-2 rounded-full border border-border text-[13.5px] font-bold transition-colors hover:bg-secondary disabled:opacity-50"
              >
                {startChat.isPending ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <MessagesSquare className="h-4 w-4" />
                )}
                {isOwner ? "Start the team chat" : "The owner starts the team chat"}
              </button>
            )}
          </SectionCard>

          <SectionCard
            title="Present in meetings"
            hint="Your presentation tools, like coaches and recruiters have theirs."
          >
            <div className="flex items-start gap-3">
              <span
                className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl text-white"
                style={{ backgroundImage: `linear-gradient(135deg, ${INDIGO}, #8B8FF5)` }}
              >
                <Presentation className="h-5 w-5" />
              </span>
              <p className="text-[12.5px] leading-relaxed text-muted-foreground">
                In any Whisper meeting you'll see a{" "}
                <span className="font-bold text-foreground">Present</span> chip with
                three live cards — <span className="font-bold text-foreground">Company</span>,{" "}
                <span className="font-bold text-foreground">We're hiring</span> (open roles
                + your apply link), and{" "}
                <span className="font-bold text-foreground">Meet the team</span> (everyone
                with their role &amp; color). Viewers get an Apply button and a{" "}
                <span className="font-bold text-foreground">👋 I'm interested</span>{" "}
                hand-raise — you see hands live on the card, and every hand lands in
                Hiring as a lead marked “Met in a meeting”.
              </p>
            </div>
          </SectionCard>

          <SectionCard
            title="Included with Business+"
            hint="The workspace itself is yours too."
          >
            <div className="grid grid-cols-2 gap-2">
              {[
                { icon: BadgeCheck, label: "Meeting tools & AI notes" },
                { icon: Landmark, label: "The Notebook for the team" },
                { icon: Users, label: "Roles for every employee" },
                { icon: X, label: "Cancel anytime in Billing" },
              ].map((row) => (
                <div key={row.label} className="flex items-center gap-2 rounded-2xl bg-secondary/50 px-3 py-2.5">
                  <row.icon className="h-4 w-4 shrink-0" style={{ color: INDIGO }} />
                  <span className="text-[12px] font-semibold leading-tight">{row.label}</span>
                </div>
              ))}
            </div>
          </SectionCard>
        </>
      )}
    </div>
  );
}

/**
 * Business+ inside the Business Suite — the plan pitch before subscribing,
 * the full team workspace after.
 */
export function BusinessPlusPanel() {
  const { user, loading } = useAuth();
  const meQuery = useQuery({
    queryKey: ["my-business-plus", user?.id],
    queryFn: () => fetchMyBusinessPlus(user!.id),
    enabled: !!user?.id,
    staleTime: 0,
    gcTime: 0,
    refetchOnWindowFocus: true,
    refetchInterval: 20000,
    retry: false,
  });

  if (loading || meQuery.isLoading) {
    return (
      <div className="flex justify-center py-16">
        <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
      </div>
    );
  }
  if (!user) {
    return (
      <p className="py-16 text-center text-sm text-muted-foreground">
        Sign in to set up Business+.
      </p>
    );
  }
  if (meQuery.isError) return <div role="alert" className="space-y-3 rounded-2xl border p-5"><p>We couldn’t check your team access. This does not mean you need a new plan.</p><button className="min-h-11 underline" onClick={() => void meQuery.refetch()}>Retry team access</button></div>;
  return <><button className="mb-4 min-h-11 text-sm underline" disabled={meQuery.isFetching} onClick={() => void meQuery.refetch()}>Refresh team access</button>{meQuery.data ? <PlusHome key={`${user.id}:${meQuery.data.business.user_id}:${meQuery.data.isOwner}`} me={meQuery.data} /> : <PlusPitch />}</>;
}
