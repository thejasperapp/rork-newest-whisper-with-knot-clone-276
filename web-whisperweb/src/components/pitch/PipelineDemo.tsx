import { useMemo, useState } from "react";
import { usePitchReset, usePitchToast } from "@/components/pitch/PitchContext";
import { PitchSheet } from "@/components/pitch/PitchPhoneFrame";
import {
  ArrowRight,
  Calendar,
  CheckCircle2,
  ChevronRight,
  Dumbbell,
  Filter,
  Instagram,
  Loader2,
  Mail,
  MapPin,
  MessageCircle,
  Music2,
  Plus,
  RotateCcw,
  Search,
  Star,
  Target,
  TrendingUp,
  Trophy,
  BadgeCheck,
  UserPlus,
  Users,
  X,
} from "lucide-react";

import { Avatar } from "@/components/Avatar";
import { cn } from "@/lib/utils";
import {
  PROSPECT_STATUS_COLORS,
  PROSPECT_STATUS_LABELS,
  type PromotableRole,
  type ProspectStatus,
} from "@/lib/recruiter";
import {
  SAMPLE_PROSPECTS,
  SAMPLE_MEETINGS,
  type SampleMeeting,
  type SampleProspect,
} from "@/lib/pitch";

const ROLE_META: Record<PromotableRole, { label: string; icon: typeof Dumbbell }> = {
  coach: { label: "Coach", icon: Dumbbell },
  athlete: { label: "Athlete", icon: Trophy },
  creator: { label: "Creator", icon: BadgeCheck },
};

const PIPELINE_STAGES: ProspectStatus[] = [
  "discovered",
  "contacted",
  "interested",
  "meeting",
  "ready",
];

function nextStage(status: ProspectStatus): ProspectStatus | null {
  const i = PIPELINE_STAGES.indexOf(status);
  if (i < 0 || i >= PIPELINE_STAGES.length - 1) return null;
  return PIPELINE_STAGES[i + 1];
}

const FUNNEL_STAGES: {
  key: ProspectStatus | "promoted";
  label: string;
  color: string;
}[] = [
  { key: "discovered", label: "Discovered", color: "bg-violet-500" },
  { key: "contacted", label: "Contacted", color: "bg-blue-500" },
  { key: "interested", label: "Interested", color: "bg-indigo-500" },
  { key: "meeting", label: "Meeting", color: "bg-amber-500" },
  { key: "ready", label: "Ready", color: "bg-emerald-500" },
  { key: "promoted", label: "Promoted", color: "bg-foreground" },
];

function StatCard({
  icon,
  value,
  label,
  highlight,
}: {
  icon: React.ReactNode;
  value: string;
  label: string;
  highlight?: boolean;
}) {
  return (
    <div
      className={cn(
        "flex flex-col items-center gap-1 rounded-2xl border py-3",
        highlight ? "border-emerald-500/30 bg-emerald-500/5" : "border-border bg-card"
      )}
    >
      <span className={cn("text-muted-foreground", highlight && "text-emerald-600")}>
        {icon}
      </span>
      <span
        className={cn(
          "text-xl font-extrabold tabular-nums",
          highlight && "text-emerald-600"
        )}
      >
        {value}
      </span>
      <span className="text-[10px] font-semibold text-muted-foreground">{label}</span>
    </div>
  );
}

/**
 * Live, clickable recruiter-pipeline demo for Pitch Mode. Mirrors the real
 * /recruiter dashboard exactly: 4-stat overview, pipeline funnel bar with
 * animated stage fills, the real filter chips with stage colors, the real
 * ProspectCard layout (avatar, name, role icon, status pill, location/niche
 * chips, star rating, notes), an interactive ProspectDetailSheet with status
 * selector + contact log, and the MeetingRequestsSection layout for incoming
 * requests. Every interaction is local demo state — nothing posts.
 */
export function PipelineDemo() {
  const [prospects, setProspects] = useState<SampleProspect[]>(SAMPLE_PROSPECTS);
  const [meetings, setMeetings] = useState<SampleMeeting[]>(SAMPLE_MEETINGS);
  const [filter, setFilter] = useState<ProspectStatus | "all">("all");
  const [promoted, setPromoted] = useState<Set<string>>(new Set());
  const [editing, setEditing] = useState<SampleProspect | null>(null);
  const showToast = usePitchToast();
  usePitchReset(() => {
    setProspects(SAMPLE_PROSPECTS);
    setMeetings(SAMPLE_MEETINGS);
    setPromoted(new Set());
    setFilter("all");
    setEditing(null);
  });

  const columnCounts = useMemo(() => {
    const counts: Record<ProspectStatus, number> = {
      discovered: 0,
      contacted: 0,
      interested: 0,
      meeting: 0,
      ready: 0,
      passed: 0,
    };
    for (const p of prospects) counts[p.status]++;
    return counts;
  }, [prospects]);

  const activeCount = prospects.filter((p) => p.status !== "passed").length;
  const readyCount = columnCounts.ready;
  const promotedCount = promoted.size;
  const conversionRate =
    promotedCount > 0
      ? Math.round(
          (promotedCount / (promotedCount + activeCount)) * 100
        )
      : 0;

  const funnelCounts = useMemo(() => {
    const f: Record<string, number> = { promoted: promotedCount };
    for (const s of PIPELINE_STAGES) f[s] = columnCounts[s];
    return f;
  }, [columnCounts, promotedCount]);
  const maxFunnel = Math.max(...FUNNEL_STAGES.map((s) => funnelCounts[s.key] ?? 0), 1);

  const visible = useMemo(
    () => (filter === "all" ? prospects : prospects.filter((p) => p.status === filter)),
    [prospects, filter]
  );

  const advance = (id: string): void => {
    setProspects((prev) =>
      prev.map((p) => {
        if (p.id !== id) return p;
        const next = nextStage(p.status);
        if (next) {
          showToast(`Moved ${p.prospect_display_name ?? "prospect"} to ${PROSPECT_STATUS_LABELS[next]}`, "success");
          return { ...p, status: next };
        }
        return p;
      })
    );
  };

  const setStatus = (id: string, status: ProspectStatus): void => {
    setProspects((prev) => prev.map((p) => (p.id === id ? { ...p, status } : p)));
  };

  const promote = (id: string): void => {
    const p = prospects.find((x) => x.id === id);
    setPromoted((prev) => new Set(prev).add(id));
    if (p) showToast(`Promoted ${p.prospect_display_name ?? "prospect"} to ${p.suggested_role ?? "creator"}`, "success");
  };

  const reset = (): void => {
    setProspects(SAMPLE_PROSPECTS);
    setMeetings(SAMPLE_MEETINGS);
    setPromoted(new Set());
    setFilter("all");
    setEditing(null);
    showToast("Pipeline demo reset");
  };

  return (
    <div className="space-y-5">
      {/* Overview stats — verbatim from the real dashboard */}
      <div className="grid grid-cols-4 gap-2">
        <StatCard icon={<Target className="h-4 w-4" />} value={String(activeCount)} label="Active" />
        <StatCard icon={<TrendingUp className="h-4 w-4" />} value={String(readyCount)} label="Ready" highlight />
        <StatCard icon={<BadgeCheck className="h-4 w-4" />} value={String(promotedCount)} label="Promoted" />
        <StatCard icon={<Users className="h-4 w-4" />} value={`${conversionRate}%`} label="Convert" />
      </div>

      {/* Pipeline funnel bar — animated stage fills */}
      <div className="rounded-2xl border border-border bg-card p-4">
        <p className="flex items-center gap-1.5 text-[12px] font-bold uppercase tracking-wider text-muted-foreground">
          <TrendingUp className="h-3.5 w-3.5" />
          Pipeline funnel
        </p>
        <div className="mt-3 space-y-2">
          {FUNNEL_STAGES.map((stage) => {
            const count = funnelCounts[stage.key] ?? 0;
            return (
              <div key={stage.key} className="flex items-center gap-2">
                <span className="w-20 shrink-0 text-[11px] font-semibold text-muted-foreground">
                  {stage.label}
                </span>
                <div className="relative h-6 flex-1 overflow-hidden rounded-lg bg-secondary/50">
                  <div
                    className={cn(
                      "absolute inset-y-0 left-0 rounded-lg transition-all duration-700 ease-out",
                      stage.color
                    )}
                    style={{
                      width: `${Math.max((count / maxFunnel) * 100, count > 0 ? 8 : 0)}%`,
                    }}
                  />
                  <span
                    className={cn(
                      "absolute inset-y-0 flex items-center pl-2 text-[11px] font-bold transition-opacity",
                      count > 0 ? "text-white" : "text-muted-foreground"
                    )}
                  >
                    {count}
                  </span>
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* Status filter chips — real colors from recruiter.ts */}
      <div className="no-scrollbar -mx-1 flex items-center gap-2 overflow-x-auto px-1 pb-1">
        <button
          onClick={() => setFilter("all")}
          className={cn(
            "flex shrink-0 items-center gap-1.5 rounded-full px-3 py-1.5 text-[12px] font-bold transition-colors",
            filter === "all"
              ? "bg-foreground text-background"
              : "bg-secondary text-muted-foreground"
          )}
        >
          <Filter className="h-3 w-3" />
          All ({prospects.length})
        </button>
        {PIPELINE_STAGES.map((s) => (
          <button
            key={s}
            onClick={() => setFilter(s)}
            className={cn(
              "flex shrink-0 items-center gap-1.5 rounded-full px-3 py-1.5 text-[12px] font-bold transition-colors",
              filter === s ? "text-white" : "bg-secondary text-muted-foreground"
            )}
            style={filter === s ? { backgroundColor: PROSPECT_STATUS_COLORS[s] } : {}}
          >
            <span
              className="h-2 w-2 rounded-full"
              style={{
                backgroundColor: filter === s ? "white" : PROSPECT_STATUS_COLORS[s],
              }}
            />
            {PROSPECT_STATUS_LABELS[s]} ({columnCounts[s]})
          </button>
        ))}
      </div>

      {/* Prospect list — real ProspectCard layout */}
      <div className="space-y-2">
        {visible.map((p) => (
          <ProspectCard
            key={p.id}
            prospect={p}
            promoted={promoted.has(p.id)}
            onEdit={() => setEditing(p)}
            onAdvance={() => advance(p.id)}
            onPromote={() => promote(p.id)}
          />
        ))}
        {visible.length === 0 && (
          <div className="rounded-2xl border border-dashed border-border bg-card px-4 py-10 text-center">
            <Target className="mx-auto h-7 w-7 text-muted-foreground" />
            <p className="mt-2 text-sm font-bold">No prospects here yet</p>
            <p className="mt-1 text-[13px] text-muted-foreground">
              Tap a card's action to move talent into this stage.
            </p>
          </div>
        )}
      </div>

      {/* Meetings section — mirrors MeetingRequestsSection */}
      <div className="space-y-2">
        <p className="flex items-center gap-1.5 text-[14px] font-bold">
          <Calendar className="h-4 w-4" />
          Meeting requests
          <span className="ml-1 rounded-full bg-foreground px-2 py-0.5 text-[11px] font-bold text-background">
            {meetings.filter((m) => m.status === "pending").length}
          </span>
        </p>
        <MeetingsList meetings={meetings} onDecide={(id, status) => {
          setMeetings((prev) => prev.map((m) => (m.id === id ? { ...m, status } : m)));
          const m = meetings.find((x) => x.id === id);
          showToast(`${m?.requester_name ?? "Request"} ${status}`, "success");
        }} />
      </div>

      <button
        onClick={reset}
        className="flex w-full items-center justify-center gap-1.5 rounded-xl py-2 text-xs font-semibold text-muted-foreground transition-colors hover:text-foreground"
      >
        <RotateCcw className="h-3.5 w-3.5" /> Reset demo
      </button>

      {editing && (
        <ProspectDetailSheet
          prospect={editing}
          promoted={promoted.has(editing.id)}
          onClose={() => setEditing(null)}
          onStatusChange={(status) => {
            setStatus(editing.id, status);
            setEditing({ ...editing, status });
          }}
          onPromote={() => {
            promote(editing.id);
            setEditing(null);
          }}
          onAdvance={() => {
            advance(editing.id);
            const next = nextStage(editing.status);
            if (next) setEditing({ ...editing, status: next });
          }}
        />
      )}
    </div>
  );
}

/** Real ProspectCard layout from RecruiterDashboard, adapted for demo state. */
function ProspectCard({
  prospect,
  promoted,
  onEdit,
  onAdvance,
  onPromote,
}: {
  prospect: SampleProspect;
  promoted: boolean;
  onEdit: () => void;
  onAdvance: () => void;
  onPromote: () => void;
}) {
  const statusColor = PROSPECT_STATUS_COLORS[prospect.status];
  const RoleIcon = prospect.suggested_role ? ROLE_META[prospect.suggested_role].icon : null;
  const next = nextStage(prospect.status);

  return (
    <div className="rounded-2xl border border-border bg-card p-3.5">
      <div className="flex items-start gap-3">
        <Avatar
          name={prospect.prospect_display_name ?? prospect.prospect_username ?? "?"}
          size={44}
        />
        <button onClick={onEdit} className="min-w-0 flex-1 text-left">
          <div className="flex items-center gap-2">
            <p className="truncate text-[14px] font-bold">
              {prospect.prospect_display_name ?? prospect.prospect_username ?? "Unknown"}
            </p>
            {RoleIcon && <RoleIcon className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />}
          </div>
          {prospect.prospect_username && (
            <p className="truncate text-[12px] text-muted-foreground">
              @{prospect.prospect_username}
            </p>
          )}
          <div className="mt-1.5 flex flex-wrap items-center gap-1.5">
            <span
              className="rounded-full px-2 py-0.5 text-[10px] font-bold text-white"
              style={{ backgroundColor: statusColor }}
            >
              {PROSPECT_STATUS_LABELS[prospect.status]}
            </span>
            {prospect.location && (
              <span className="flex items-center gap-0.5 text-[11px] text-muted-foreground">
                <MapPin className="h-2.5 w-2.5" />
                {prospect.location}
              </span>
            )}
            {prospect.niche && (
              <span className="rounded-full bg-secondary px-1.5 py-0.5 text-[10px] font-semibold text-muted-foreground">
                {prospect.niche}
              </span>
            )}
          </div>
          {typeof prospect.rating === "number" && prospect.rating > 0 && (
            <div className="mt-1 flex items-center gap-0.5">
              {Array.from({ length: 5 }).map((_, i) => (
                <Star
                  key={i}
                  className={cn(
                    "h-3 w-3",
                    i < (prospect.rating ?? 0)
                      ? "fill-amber-400 text-amber-400"
                      : "text-muted-foreground/30"
                  )}
                />
              ))}
            </div>
          )}
        </button>
      </div>

      {prospect.notes && (
        <p className="mt-2 line-clamp-2 rounded-lg bg-secondary/40 px-2.5 py-1.5 text-[12px] leading-snug text-muted-foreground">
          {prospect.notes}
        </p>
      )}

      <div className="mt-3 flex gap-2">
        {promoted ? (
          <span className="flex flex-1 items-center justify-center gap-1.5 rounded-xl bg-emerald-500/10 py-2.5 text-xs font-bold text-emerald-600">
            <UserPlus className="h-3.5 w-3.5" /> Promoted to{" "}
            {prospect.suggested_role ?? "creator"} (demo)
          </span>
        ) : prospect.status === "ready" ? (
          <button
            onClick={onPromote}
            className="flex flex-1 items-center justify-center gap-1.5 rounded-xl bg-foreground py-2.5 text-xs font-bold text-background transition-transform active:scale-[0.98]"
          >
            <UserPlus className="h-3.5 w-3.5" /> Promote to{" "}
            {prospect.suggested_role ?? "creator"}
          </button>
        ) : next ? (
          <button
            onClick={onAdvance}
            className="flex flex-1 items-center justify-center gap-1.5 rounded-xl border border-border bg-card py-2.5 text-xs font-bold transition-all hover:border-foreground/30 active:scale-[0.98]"
          >
            Move to {PROSPECT_STATUS_LABELS[next]}
            <ArrowRight className="h-3.5 w-3.5" />
          </button>
        ) : null}
        <button
          onClick={onEdit}
          className="flex items-center justify-center gap-1.5 rounded-xl border border-border px-4 py-2.5 text-xs font-bold transition-all hover:border-foreground/30 active:scale-[0.98]"
        >
          Details
          <ChevronRight className="h-3.5 w-3.5" />
        </button>
      </div>
    </div>
  );
}

/** Real ProspectDetailSheet layout — status selector, rating, notes, contact log. */
function ProspectDetailSheet({
  prospect,
  promoted,
  onClose,
  onStatusChange,
  onPromote,
  onAdvance,
}: {
  prospect: SampleProspect;
  promoted: boolean;
  onClose: () => void;
  onStatusChange: (status: ProspectStatus) => void;
  onPromote: () => void;
  onAdvance: () => void;
}) {
  const RoleIcon = prospect.suggested_role ? ROLE_META[prospect.suggested_role].icon : null;
  const next = nextStage(prospect.status);

  return (
    <PitchSheet open onClose={onClose} zIndex={80}>
      <div className="relative flex h-full w-full max-w-md flex-col overflow-hidden rounded-t-[24px] bg-card sm:rounded-[24px]">
        <div className="flex items-center justify-between border-b border-border px-4 py-3.5">
          <button
            onClick={onClose}
            aria-label="Close"
            className="flex h-8 w-8 items-center justify-center rounded-full transition-colors hover:bg-secondary"
          >
            <X className="h-5 w-5" />
          </button>
          <h2 className="text-[17px] font-bold">Prospect details</h2>
          <span className="w-8" />
        </div>

        <div className="min-h-0 flex-1 space-y-5 overflow-y-auto p-4">
          <div className="flex items-center gap-3">
            <Avatar
              name={prospect.prospect_display_name ?? prospect.prospect_username ?? "?"}
              size={56}
            />
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <p className="truncate text-[16px] font-bold">
                  {prospect.prospect_display_name ?? "Unknown"}
                </p>
                {RoleIcon && <RoleIcon className="h-4 w-4 shrink-0 text-muted-foreground" />}
              </div>
              {prospect.prospect_username && (
                <p className="truncate text-[13px] text-muted-foreground">
                  @{prospect.prospect_username}
                </p>
              )}
              <div className="mt-1 flex flex-wrap items-center gap-2">
                {prospect.instagram && (
                  <span className="flex items-center gap-1 text-[11px] font-bold text-muted-foreground">
                    <Instagram className="h-3 w-3" />
                    {prospect.instagram}
                  </span>
                )}
                {prospect.tiktok && (
                  <span className="flex items-center gap-1 text-[11px] font-bold text-muted-foreground">
                    <Music2 className="h-3 w-3" />
                    {prospect.tiktok}
                  </span>
                )}
                {prospect.location && (
                  <span className="flex items-center gap-0.5 text-[11px] text-muted-foreground">
                    <MapPin className="h-3 w-3" />
                    {prospect.location}
                  </span>
                )}
              </div>
            </div>
          </div>

          <div>
            <p className="mb-1.5 text-[12px] font-bold uppercase tracking-wider text-muted-foreground">
              Pipeline status
            </p>
            <div className="flex flex-wrap gap-1.5">
              {PIPELINE_STAGES.map((s) => (
                <button
                  key={s}
                  onClick={() => onStatusChange(s)}
                  className={cn(
                    "rounded-full px-3 py-1.5 text-[12px] font-bold transition-colors",
                    prospect.status === s ? "text-white" : "bg-secondary text-muted-foreground"
                  )}
                  style={
                    prospect.status === s
                      ? { backgroundColor: PROSPECT_STATUS_COLORS[s] }
                      : {}
                  }
                >
                  {PROSPECT_STATUS_LABELS[s]}
                </button>
              ))}
            </div>
          </div>

          {prospect.notes && (
            <div>
              <p className="mb-1.5 text-[12px] font-bold uppercase tracking-wider text-muted-foreground">
                Scouting notes
              </p>
              <p className="rounded-xl bg-secondary/40 px-3 py-2.5 text-[13px] leading-snug text-foreground/80">
                {prospect.notes}
              </p>
            </div>
          )}

          {promoted ? (
            <div className="flex items-center justify-center gap-1.5 rounded-xl bg-emerald-500/10 py-3 text-sm font-bold text-emerald-600">
              <CheckCircle2 className="h-4 w-4" /> Promoted to{" "}
              {prospect.suggested_role ?? "creator"}
            </div>
          ) : (
            <div className="flex gap-2">
              {next && (
                <button
                  onClick={onAdvance}
                  className="flex flex-1 items-center justify-center gap-1.5 rounded-xl border border-border bg-card py-3 text-[13px] font-bold transition-all hover:border-foreground/30 active:scale-[0.98]"
                >
                  Move to {PROSPECT_STATUS_LABELS[next]}
                  <ArrowRight className="h-4 w-4" />
                </button>
              )}
              {prospect.status === "ready" && (
                <button
                  onClick={onPromote}
                  className="flex flex-1 items-center justify-center gap-1.5 rounded-xl bg-foreground py-3 text-[13px] font-bold text-background transition-transform active:scale-[0.98]"
                >
                  <UserPlus className="h-4 w-4" /> Promote
                </button>
              )}
            </div>
          )}
        </div>
      </div>
    </PitchSheet>
  );
}

/** Mirrors the real MeetingRequestsSection layout with sample data. */
function MeetingsList({
  meetings,
  onDecide,
}: {
  meetings: SampleMeeting[];
  onDecide: (id: string, status: "approved" | "denied") => void;
}) {
  const sorted = [...meetings].sort((a, b) => {
    if (a.status === "pending" && b.status !== "pending") return -1;
    if (a.status !== "pending" && b.status === "pending") return 1;
    return a.requested_time.localeCompare(b.requested_time);
  });

  if (meetings.length === 0) {
    return (
      <div className="rounded-2xl border border-dashed border-border bg-card p-6 text-center">
        <Calendar className="mx-auto h-8 w-8 text-muted-foreground" />
        <p className="mt-3 text-[14px] font-bold">No meeting requests yet</p>
        <p className="mt-1 text-[13px] text-muted-foreground">
          When someone taps "Schedule a call" on your featured card, their
          request shows up here for you to approve or decline.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-2.5">
      {sorted.map((req) => {
        const when = new Date(req.requested_time).toLocaleString("en-US", {
          weekday: "short",
          month: "short",
          day: "numeric",
          hour: "numeric",
          minute: "2-digit",
        });
        const statusStyle =
          req.status === "pending"
            ? "bg-amber-500/15 text-amber-600"
            : req.status === "approved"
              ? "bg-emerald-500/15 text-emerald-600"
              : "bg-rose-500/15 text-rose-600";
        return (
          <div key={req.id} className="rounded-2xl border border-border bg-card p-4">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <p className="text-[15px] font-extrabold">{req.requester_name}</p>
                <a
                  href={`mailto:${req.requester_email}`}
                  className="text-[12.5px] text-muted-foreground hover:underline"
                >
                  {req.requester_email}
                </a>
              </div>
              <span
                className={cn(
                  "shrink-0 rounded-full px-2.5 py-1 text-[11px] font-bold capitalize",
                  statusStyle
                )}
              >
                {req.status}
              </span>
            </div>
            <div className="mt-3 flex items-center gap-2 text-[13px] text-foreground/80">
              <Calendar className="h-4 w-4 text-muted-foreground" />
              <span>{when}</span>
              <span className="text-muted-foreground">· {req.requester_timezone}</span>
            </div>
            {req.message && (
              <p className="mt-3 rounded-xl bg-secondary p-3 text-[13.5px] leading-relaxed text-foreground/90">
                "{req.message}"
              </p>
            )}
            {req.status === "pending" && (
              <div className="mt-4 flex gap-2">
                <button
                  onClick={() => onDecide(req.id, "approved")}
                  className="flex-1 rounded-xl bg-foreground py-2.5 text-[13px] font-bold text-background transition-transform active:scale-[0.98]"
                >
                  Approve
                </button>
                <button
                  onClick={() => onDecide(req.id, "denied")}
                  className="flex-1 rounded-xl border border-border bg-card py-2.5 text-[13px] font-bold text-foreground transition-transform active:scale-[0.98]"
                >
                  Decline
                </button>
              </div>
            )}
            {req.status === "approved" && (
              <p className="mt-3 text-[12.5px] text-muted-foreground">
                In production: a Whisper-branded email with your Google Meet link
                goes out automatically.
              </p>
            )}
          </div>
        );
      })}
    </div>
  );
}
