import { useEffect, useMemo, useRef, useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import {
  TrendingUp,
  Target,
  CheckCircle2,
  XCircle,
  Eye,
  Loader2,
  Users,
  Award,
  MessageSquarePlus,
  Save,
  ChevronDown,
  ChevronUp,
  Clock,
  ArrowUpRight,
  Crown,
  ShieldCheck,
  UserCheck,
} from "lucide-react";
import { toast } from "sonner";

import { useAuth } from "@/hooks/useAuth";
import { Avatar } from "@/components/Avatar";
import { cn } from "@/lib/utils";
import {
  fetchRecruiterResponses,
  updateResponseStatus,
  subscribeToResponses,
  fetchNotesForResponse,
  saveQuestionNote,
  subscribeToResponseNotes,
  type ApplicantResponse,
  type ApplicantQuestion,
  type ApplicantNote,
  fetchAllQuestions,
} from "@/lib/applicantQuestionnaire";
import { fetchProfilesByIds } from "@/lib/api";
import {
  linkApplicationToProspect,
  promoteUser,
  type PromotableRole,
} from "@/lib/recruiter";

const POSITION_META: Record<string, { label: string; color: string; icon: typeof Crown }> = {
  coach: { label: "Coach", color: "#f97316", icon: ShieldCheck },
  athlete: { label: "Athlete", color: "#ef4444", icon: Award },
  creator: { label: "Creator", color: "#3b82f6", icon: Crown },
};

const STATUS_META: Record<string, { label: string; bg: string; text: string; dot: string }> = {
  submitted: { label: "New", bg: "bg-amber-500/10", text: "text-amber-600", dot: "bg-amber-500" },
  reviewed: { label: "Reviewed", bg: "bg-blue-500/10", text: "text-blue-600", dot: "bg-blue-500" },
  accepted: { label: "Accepted", bg: "bg-emerald-500/10", text: "text-emerald-600", dot: "bg-emerald-500" },
  rejected: { label: "Passed", bg: "bg-red-500/10", text: "text-red-600", dot: "bg-red-500" },
};

export function RecruiterApplications({ recruiterId }: { recruiterId: string }) {
  const queryClient = useQueryClient();
  const { profile } = useAuth();
  const [selected, setSelected] = useState<ApplicantResponse | null>(null);
  const [filter, setFilter] = useState<"all" | "new" | "accepted" | "rejected">("all");

  const responsesQuery = useQuery({
    queryKey: ["recruiter-applications", recruiterId],
    queryFn: () => fetchRecruiterResponses(recruiterId),
    enabled: !!recruiterId,
  });

  const questionsQuery = useQuery({
    queryKey: ["admin-applicant-questions"],
    queryFn: fetchAllQuestions,
  });

  useEffect(() => {
    if (!recruiterId) return;
    const unsub = subscribeToResponses(recruiterId, (payload) => {
      queryClient.invalidateQueries({ queryKey: ["recruiter-applications", recruiterId] });
      if (payload.event === "INSERT") {
        toast.success("New applicant received");
      }
    });
    return unsub;
  }, [recruiterId, queryClient]);

  const responses = responsesQuery.data ?? [];
  const questions = questionsQuery.data ?? [];

  // Every application automatically files into the prospect pipeline — a
  // prospect row is created for applicants who aren't in it yet, and the
  // submission is logged on their profile (idempotent per response).
  const linkedRef = useRef<Set<string>>(new Set());
  useEffect(() => {
    if (!recruiterId || responses.length === 0) return;
    let cancelled = false;
    void (async () => {
      let linkedAny = false;
      for (const response of responses) {
        if (cancelled) return;
        if (linkedRef.current.has(response.id)) continue;
        linkedRef.current.add(response.id);
        try {
          const linked = await linkApplicationToProspect(recruiterId, response);
          linkedAny = linkedAny || linked;
        } catch {
          /* pipeline filing is best-effort */
        }
      }
      if (linkedAny && !cancelled) {
        queryClient.invalidateQueries({ queryKey: ["prospects"] });
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [recruiterId, responses, queryClient]);

  const userIds = responses.map((r) => r.applicant_user_id).filter(Boolean) as string[];
  const profilesQuery = useQuery({
    queryKey: ["applicant-profiles", userIds],
    queryFn: () => fetchProfilesByIds(userIds),
    enabled: userIds.length > 0,
  });
  const profiles = profilesQuery.data ?? {};

  const statusMutation = useMutation({
    mutationFn: async ({
      id,
      status,
      response,
    }: {
      id: string;
      status: "reviewed" | "accepted" | "rejected";
      response: ApplicantResponse;
    }) => {
      await updateResponseStatus(id, status);

      // On accept, promote the applicant to their best-fit role and give the
      // recruiter credit in the promoted spot.
      if (status === "accepted" && response.applicant_user_id && response.best_position) {
        const role = response.best_position as PromotableRole;
        if (["coach", "athlete", "creator"].includes(role)) {
          const targetProfile = profiles[response.applicant_user_id];
          const promotedUsername = targetProfile?.username ?? response.applicant_name ?? "applicant";
          await promoteUser({
            recruiterId,
            recruiterUsername: profile?.username ?? "recruiter",
            promotedId: response.applicant_user_id,
            promotedUsername,
            role,
            notes: `Promoted via applicant questionnaire (score: ${response.potential_score ?? 0}/100)`,
          });
        }
      }
    },
    onSuccess: (_data, vars) => {
      const messages: Record<string, string> = {
        accepted: "Applicant accepted and promoted",
        rejected: "Applicant passed",
        reviewed: "Marked as reviewed",
      };
      toast.success(messages[vars.status] ?? "Updated");
      queryClient.invalidateQueries({ queryKey: ["recruiter-applications", recruiterId] });
      queryClient.invalidateQueries({ queryKey: ["recruiter-promotions", recruiterId] });
      setSelected(null);
    },
    onError: (err) => {
      toast.error(err instanceof Error ? err.message : "Could not update applicant");
    },
  });

  const filtered = useMemo(() => {
    if (filter === "all") return responses;
    if (filter === "new") return responses.filter((r) => r.status === "submitted");
    if (filter === "accepted") return responses.filter((r) => r.status === "accepted");
    if (filter === "rejected") return responses.filter((r) => r.status === "rejected");
    return responses;
  }, [responses, filter]);

  const pendingCount = responses.filter((r) => r.status === "submitted").length;
  const acceptedCount = responses.filter((r) => r.status === "accepted").length;

  return (
    <div className="space-y-5">
      {/* Header stats */}
      <div className="grid grid-cols-3 gap-3">
        <div className="rounded-2xl border border-border bg-card p-4 text-center">
          <p className="text-2xl font-black tabular-nums">{responses.length}</p>
          <p className="mt-0.5 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">Total</p>
        </div>
        <div className="rounded-2xl border border-border bg-card p-4 text-center">
          <p className="text-2xl font-black tabular-nums text-amber-500">{pendingCount}</p>
          <p className="mt-0.5 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">New</p>
        </div>
        <div className="rounded-2xl border border-border bg-card p-4 text-center">
          <p className="text-2xl font-black tabular-nums text-emerald-500">{acceptedCount}</p>
          <p className="mt-0.5 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">Accepted</p>
        </div>
      </div>

      {/* Filter pills */}
      <div className="flex gap-2">
        {(
          [
            ["all", "All"],
            ["new", "New"],
            ["accepted", "Accepted"],
            ["rejected", "Passed"],
          ] as const
        ).map(([key, label]) => (
          <button
            key={key}
            onClick={() => setFilter(key)}
            className={cn(
              "rounded-full px-3.5 py-1.5 text-[12px] font-bold transition-colors",
              filter === key
                ? "bg-foreground text-background"
                : "bg-secondary text-muted-foreground hover:bg-secondary/80"
            )}
          >
            {label}
          </button>
        ))}
      </div>

      {responsesQuery.isLoading ? (
        <div className="flex justify-center py-12">
          <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
        </div>
      ) : filtered.length === 0 ? (
        <div className="rounded-2xl border border-dashed border-border bg-card p-10 text-center">
          <div className="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-full bg-secondary">
            <Users className="h-7 w-7 text-muted-foreground" />
          </div>
          <p className="text-sm font-bold">{filter === "all" ? "No applicants yet" : "No applicants in this filter"}</p>
          <p className="mt-1 text-xs text-muted-foreground">
            {filter === "all"
              ? "Share your QR code or referral link to start receiving applications."
              : "Try a different filter."}
          </p>
        </div>
      ) : (
        <div className="space-y-3">
          {filtered.map((r) => {
            const profile = r.applicant_user_id ? profiles[r.applicant_user_id] : null;
            const positionMeta = r.best_position ? POSITION_META[r.best_position] : null;
            const status = STATUS_META[r.status] ?? STATUS_META.submitted;
            return (
              <button
                key={r.id}
                onClick={() => setSelected(r)}
                className="group flex w-full items-center gap-4 rounded-2xl border border-border bg-card p-4 text-left transition-all hover:border-foreground/20 hover:bg-secondary/30"
              >
                <Avatar url={profile?.profile_image_url ?? null} name={r.applicant_name ?? "applicant"} size={48} />
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <p className="truncate text-[15px] font-bold">{r.applicant_name ?? profile?.username ?? "Unknown"}</p>
                    <span className={cn("inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-bold", status.bg, status.text)}>
                      <span className={cn("h-1.5 w-1.5 rounded-full", status.dot)} />
                      {status.label}
                    </span>
                  </div>
                  <p className="truncate text-xs text-muted-foreground">{r.applicant_email ?? "No email"}</p>
                  <div className="mt-2 flex items-center gap-2">
                    {positionMeta && (
                      <span
                        className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-bold"
                        style={{ backgroundColor: `${positionMeta.color}15`, color: positionMeta.color }}
                      >
                        <positionMeta.icon className="h-3 w-3" />
                        {positionMeta.label}
                      </span>
                    )}
                    {typeof r.potential_score === "number" && (
                      <span className="text-[10px] font-semibold text-muted-foreground">Score {r.potential_score}/100</span>
                    )}
                  </div>
                </div>
                <div className="flex flex-col items-end gap-1 text-right">
                  <span className="text-[10px] font-semibold text-muted-foreground">
                    <Clock className="mr-1 inline h-3 w-3" />
                    {timeAgo(r.created_at)}
                  </span>
                  <ArrowUpRight className="h-4 w-4 text-muted-foreground transition-transform group-hover:-translate-y-0.5 group-hover:translate-x-0.5" />
                </div>
              </button>
            );
          })}
        </div>
      )}

      {selected && (
        <ApplicationDetail
          response={selected}
          questions={questions}
          recruiterId={recruiterId}
          recruiterUsername={profile?.username ?? "recruiter"}
          profiles={profiles}
          onClose={() => setSelected(null)}
          onStatusChange={(status) => statusMutation.mutate({ id: selected.id, status, response: selected })}
          isPending={statusMutation.isPending}
        />
      )}
    </div>
  );
}

function StatusBadge({ status }: { status: string }) {
  const meta = STATUS_META[status] ?? STATUS_META.submitted;
  return (
    <span className={cn("inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-bold", meta.bg, meta.text)}>
      <span className={cn("h-1.5 w-1.5 rounded-full", meta.dot)} />
      {meta.label}
    </span>
  );
}

function ApplicationDetail({
  response,
  questions,
  recruiterId,
  recruiterUsername,
  profiles,
  onClose,
  onStatusChange,
  isPending,
}: {
  response: ApplicantResponse;
  questions: ApplicantQuestion[];
  recruiterId: string;
  recruiterUsername: string;
  profiles: Record<string, { username: string | null; display_name: string | null; profile_image_url: string | null }>;
  onClose: () => void;
  onStatusChange: (status: "reviewed" | "accepted" | "rejected") => void;
  isPending: boolean;
}) {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const positionMeta = response.best_position ? POSITION_META[response.best_position] : null;
  const targetProfile = response.applicant_user_id ? profiles[response.applicant_user_id] : null;
  const canPromote = response.status !== "accepted" && !!response.applicant_user_id && !!response.best_position && ["coach", "athlete", "creator"].includes(response.best_position);

  const notesQuery = useQuery({
    queryKey: ["applicant-notes", response.id],
    queryFn: () => fetchNotesForResponse(response.id),
    enabled: !!response.id,
  });

  const [notes, setNotes] = useState<Record<string, string>>({});
  const [savingNoteId, setSavingNoteId] = useState<string | null>(null);
  const [expandedNotes, setExpandedNotes] = useState<Record<string, boolean>>({});

  useEffect(() => {
    const map: Record<string, string> = {};
    for (const n of notesQuery.data ?? []) {
      map[n.question_id] = n.note;
    }
    setNotes(map);
  }, [notesQuery.data]);

  useEffect(() => {
    const unsub = subscribeToResponseNotes(response.id, () => {
      queryClient.invalidateQueries({ queryKey: ["applicant-notes", response.id] });
    });
    return unsub;
  }, [response.id, queryClient]);

  const saveNote = async (questionId: string) => {
    if (!user) return;
    setSavingNoteId(questionId);
    try {
      await saveQuestionNote({
        responseId: response.id,
        questionId,
        recruiterId: user.id,
        note: notes[questionId] ?? "",
      });
      toast.success("Note saved");
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Could not save note");
    } finally {
      setSavingNoteId(null);
    }
  };

  const entries = Object.entries(response.answers).map(([questionId, answer]) => {
    const question = questions.find((q) => q.id === questionId);
    return { questionId, question: question?.question ?? answer.question, answer: answer.answer, questionObj: question };
  });

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4 backdrop-blur-sm" onClick={onClose}>
      <div
        className="relative max-h-[90vh] w-full max-w-2xl overflow-hidden rounded-3xl border border-border bg-background shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-start justify-between border-b border-border p-5">
          <div className="flex items-center gap-3">
            <Avatar url={targetProfile?.profile_image_url ?? null} name={response.applicant_name ?? "A"} size={56} />
            <div>
              <div className="flex items-center gap-2">
                <p className="font-display text-lg font-bold">{response.applicant_name ?? "Unknown"}</p>
                <StatusBadge status={response.status} />
              </div>
              <p className="text-sm text-muted-foreground">{response.applicant_email ?? "No email"}</p>
              <p className="text-xs text-muted-foreground">Applied {new Date(response.created_at).toLocaleDateString()}</p>
            </div>
          </div>
          <button onClick={onClose} className="flex h-10 w-10 items-center justify-center rounded-full bg-secondary transition-colors hover:bg-secondary/80">
            <XCircle className="h-5 w-5" />
          </button>
        </div>

        <div className="max-h-[calc(90vh-180px)] overflow-y-auto p-5">
          {/* Match scores */}
          {positionMeta && response.position_scores && (
            <div className="mb-6 rounded-2xl border border-border bg-card p-5">
              <div className="mb-4 flex items-center justify-between">
                <p className="flex items-center gap-1.5 text-sm font-bold">
                  <Target className="h-4 w-4" /> Position match
                </p>
                {typeof response.potential_score === "number" && (
                  <span className="text-xs font-semibold text-muted-foreground">Potential {response.potential_score}/100</span>
                )}
              </div>

              <div className="mb-5 flex items-center gap-4 rounded-2xl bg-secondary/40 p-4">
                <div
                  className="flex h-14 w-14 shrink-0 items-center justify-center rounded-2xl text-white"
                  style={{ backgroundColor: positionMeta.color }}
                >
                  <positionMeta.icon className="h-7 w-7" />
                </div>
                <div className="flex-1">
                  <p className="text-xs font-semibold text-muted-foreground">Best fit</p>
                  <p className="font-display text-2xl font-black" style={{ color: positionMeta.color }}>
                    {positionMeta.label}
                  </p>
                </div>
                {typeof response.confidence_score === "number" && (
                  <div className="text-right">
                    <p className="text-xs font-semibold text-muted-foreground">Confidence</p>
                    <p className="font-display text-2xl font-black">{response.confidence_score}%</p>
                  </div>
                )}
              </div>

              <div className="space-y-3">
                {Object.entries(response.position_scores).map(([role, score]) => {
                  const meta = POSITION_META[role];
                  if (!meta) return null;
                  return (
                    <div key={role}>
                      <div className="mb-1 flex items-center justify-between text-xs">
                        <span className="font-semibold">{meta.label}</span>
                        <span className="tabular-nums text-muted-foreground">{score}/100</span>
                      </div>
                      <div className="h-2 overflow-hidden rounded-full bg-secondary">
                        <div className="h-full rounded-full transition-all" style={{ width: `${score}%`, backgroundColor: meta.color }} />
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          {/* Answers */}
          <div className="space-y-4">
            <p className="flex items-center gap-1.5 text-sm font-bold">
              <Eye className="h-4 w-4" /> Questionnaire answers
            </p>
            {entries.map(({ questionId, question, answer }) => {
              const noteOpen = !!expandedNotes[questionId];
              return (
                <div key={questionId} className="rounded-2xl border border-border bg-card p-4">
                  <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">{question}</p>
                  <p className="mt-2 text-sm leading-relaxed">{answer}</p>

                  <button
                    onClick={() => setExpandedNotes((n) => ({ ...n, [questionId]: !n[questionId] }))}
                    className="mt-3 flex items-center gap-1 text-xs font-semibold text-muted-foreground transition-colors hover:text-foreground"
                  >
                    <MessageSquarePlus className="h-3.5 w-3.5" />
                    Recruiter note
                    {noteOpen ? <ChevronUp className="h-3.5 w-3.5" /> : <ChevronDown className="h-3.5 w-3.5" />}
                  </button>

                  {noteOpen && (
                    <div className="mt-3 rounded-xl bg-secondary/40 p-3">
                      <textarea
                        value={notes[questionId] ?? ""}
                        onChange={(e) => setNotes((n) => ({ ...n, [questionId]: e.target.value }))}
                        placeholder="Leave a private note about this answer…"
                        rows={2}
                        className="w-full resize-none rounded-xl border border-border bg-background px-3 py-2 text-xs outline-none focus:border-foreground/40"
                      />
                      <div className="mt-2 flex justify-end">
                        <button
                          onClick={() => saveNote(questionId)}
                          disabled={savingNoteId === questionId}
                          className="flex items-center gap-1 rounded-lg bg-foreground px-3 py-1.5 text-xs font-bold text-background transition-transform active:scale-95 disabled:opacity-50"
                        >
                          {savingNoteId === questionId ? <Loader2 className="h-3 w-3 animate-spin" /> : <Save className="h-3 w-3" />}
                          Save note
                        </button>
                      </div>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>

        {/* Footer actions */}
        <div className="border-t border-border bg-card p-5">
          {response.status === "submitted" || response.status === "reviewed" ? (
            <div className="flex flex-col gap-3 sm:flex-row">
              <button
                onClick={() => onStatusChange("accepted")}
                disabled={isPending}
                className="flex flex-1 items-center justify-center gap-2 rounded-2xl bg-emerald-500 py-3.5 text-sm font-bold text-white transition-transform active:scale-95 disabled:opacity-50"
              >
                {isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <CheckCircle2 className="h-4 w-4" />}
                {canPromote ? `Accept & promote to ${positionMeta?.label ?? "role"}` : "Accept"}
              </button>
              <button
                onClick={() => onStatusChange("rejected")}
                disabled={isPending}
                className="flex flex-1 items-center justify-center gap-2 rounded-2xl border border-border bg-background py-3.5 text-sm font-bold transition-colors hover:bg-secondary disabled:opacity-50"
              >
                <XCircle className="h-4 w-4" /> Pass
              </button>
            </div>
          ) : response.status === "accepted" ? (
            <div className="flex items-center gap-2 rounded-2xl bg-emerald-500/10 px-4 py-3 text-sm font-bold text-emerald-600">
              <UserCheck className="h-4 w-4" />
              Accepted{positionMeta ? ` and promoted to ${positionMeta.label}` : ""}. The recruiter is credited in Promotions.
            </div>
          ) : (
            <div className="flex items-center gap-2 rounded-2xl bg-secondary/40 px-4 py-3 text-sm font-bold text-muted-foreground">
              <XCircle className="h-4 w-4" /> Passed on this applicant.
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function timeAgo(date: string): string {
  const seconds = Math.floor((Date.now() - new Date(date).getTime()) / 1000);
  if (seconds < 60) return "Just now";
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h`;
  const days = Math.floor(hours / 24);
  return `${days}d`;
}
