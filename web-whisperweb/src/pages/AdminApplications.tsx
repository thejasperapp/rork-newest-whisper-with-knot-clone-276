import { useState } from "react";
import { Link } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  BadgeCheck,
  ChevronRight,
  CircleAlert,
  ClipboardList,
  Clock,
  Crown,
  Loader2,
  Megaphone,
  Shield,
  ShieldCheck,
  Star,
  Trash2,
  UserCheck,
  UserPlus,
} from "lucide-react";
import { toast } from "sonner";

import PublicNav from "@/components/PublicNav";
import PublicFooter from "@/components/PublicFooter";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { useAuth } from "@/hooks/useAuth";
import { BACKEND_URL, type BadgeRole } from "@/lib/billing";
import {
  fetchRecruiterReviews,
  type RecruiterReviewSummary,
} from "@/lib/recruiterReviews";
import { AdminApplicantQuestions } from "@/components/AdminApplicantQuestions";
import { AdminRefundsPanel } from "@/components/AdminRefundsPanel";
import { AdminReceiptsPanel } from "@/components/AdminReceiptsPanel";
import { AdminBadgeGrants } from "@/components/AdminBadgeGrants";

/**
 * Admin/mod/owner-only review dashboard for Coach, Athlete, and Verified
 * applications. Mirrors the iOS "Account reviews" screen. Decisions go
 * through the billing backend, which verifies the caller's Supabase JWT
 * server-side, stamps the row, and emails the approval/payment link itself
 * — perks stay OFF until the annual badge payment confirms via Stripe.
 */

interface ApplicationRow {
  id: string;
  user_id: string | null;
  username: string;
  email: string | null;
  full_name: string;
  status: string;
  created_at: string | null;
  // Coach
  credentials?: string | null;
  specialties?: string[] | null;
  experience_years?: number | null;
  website?: string | null;
  // Athlete
  sport?: string | null;
  level?: string | null;
  team?: string | null;
  prs?: string | null;
  // Shared-ish
  bio?: string | null;
  social?: string | null;
  // Verified
  category?: string | null;
  reason?: string | null;
  links?: string | null;
  followers?: number | null;
}

interface QueueData {
  pending: ApplicationRow[];
  recent: ApplicationRow[];
}

type Queues = Record<BadgeRole, QueueData>;

type AdminRole = "owner" | "admin" | "moderator";

interface TeamMember {
  id: string;
  user_id: string;
  username: string | null;
  email: string | null;
  role: AdminRole;
  created_at: string | null;
}

interface TeamData {
  members: TeamMember[];
  callerRole: AdminRole;
  callerUserId: string;
}

interface RecruiterLeaderboardRow {
  userId: string;
  username: string | null;
  displayName: string | null;
  profileImageUrl: string | null;
  signupCount: number;
  reviewCount: number;
  averageRating: number | null;
  positiveCount: number;
  negativeCount: number;
}

const ROLE_BADGE: Record<AdminRole, { label: string; classes: string }> = {
  owner: { label: "Owner", classes: "bg-amber-500/10 text-amber-600" },
  admin: { label: "Admin", classes: "bg-violet-500/10 text-violet-600" },
  moderator: { label: "Moderator", classes: "bg-sky-500/10 text-sky-600" },
};

const TABS: { role: BadgeRole; label: string; accent: string }[] = [
  { role: "coach", label: "Coaches", accent: "text-orange-500" },
  { role: "verified", label: "Creators", accent: "text-sky-500" },
];

function roleIcon(role: BadgeRole) {
  if (role === "coach") return <Megaphone className="h-4 w-4" />;
  return <BadgeCheck className="h-4 w-4" />;
}

function detailLine(row: ApplicationRow, role: BadgeRole): string {
  if (role === "coach") {
    const parts = [
      row.specialties?.length ? row.specialties.join(" · ") : null,
      row.experience_years ? `${row.experience_years} yrs experience` : null,
    ].filter(Boolean);
    return parts.join(" — ");
  }
  const cat = row.category?.replace(/_/g, " ") ?? "";
  const followers =
    typeof row.followers === "number" && row.followers > 0
      ? `${row.followers.toLocaleString()} followers`
      : null;
  return [cat, followers].filter(Boolean).join(" · ");
}

type TabId = BadgeRole | "team" | "recruiters" | "applicants";

export default function AdminApplications() {
  const { session, loading } = useAuth();
  const [tab, setTab] = useState<TabId>("coach");
  const [expanded, setExpanded] = useState<string | null>(null);
  const [newIdentifier, setNewIdentifier] = useState<string>("");
  const [newRole, setNewRole] = useState<AdminRole>("moderator");
  const queryClient = useQueryClient();
  const token = session?.access_token ?? "";

  const queues = useQuery<Queues>({
    queryKey: ["admin-applications", session?.user.id],
    enabled: !!token,
    queryFn: async ({ signal }) => {
      const res = await fetch(`${BACKEND_URL}/admin/applications`, {
        headers: { Authorization: `Bearer ${token}` }, signal,
      });
      if (res.status === 403) throw new Error("forbidden");
      if (!res.ok) throw new Error("Couldn't load applications.");
      return (await res.json()) as Queues;
    },
    retry: false,
  });

  const team = useQuery<TeamData>({
    queryKey: ["admin-team", session?.user.id],
    enabled: !!token && tab === "team",
    queryFn: async ({ signal }) => {
      const res = await fetch(`${BACKEND_URL}/admin/team`, {
        headers: { Authorization: `Bearer ${token}` }, signal,
      });
      if (res.status === 403) throw new Error("forbidden");
      if (!res.ok) throw new Error("Couldn't load the team.");
      return (await res.json()) as TeamData;
    },
    retry: false,
  });

  const canManageTeam =
    team.data?.callerRole === "owner" || team.data?.callerRole === "admin";

  const upsertMember = useMutation({
    mutationFn: async (input: { identifier: string; role: AdminRole }) => {
      const res = await fetch(`${BACKEND_URL}/admin/team/upsert`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify(input),
      });
      const data = (await res.json()) as { ok?: boolean; error?: string };
      if (!res.ok || !data.ok) {
        const msg =
          data.error === "user_not_found"
            ? "No account found with that username or email."
            : data.error === "owner_only"
              ? "Only the owner can grant the owner role."
              : data.error === "forbidden"
                ? "Moderators can't change the team."
                : data.error === "sync_failed"
                  ? "Saved the role, but the profile flags didn't sync. Try again in a moment."
                  : "Couldn't save. Try again.";
        throw new Error(msg);
      }
      return data;
    },
    onSuccess: () => {
      toast.success("Team updated.");
      setNewIdentifier("");
      void queryClient.invalidateQueries({ queryKey: ["admin-team"] });
    },
    onError: (err) => {
      toast.error(err instanceof Error ? err.message : "Something went wrong.");
    },
  });

  const removeMember = useMutation({
    mutationFn: async (userId: string) => {
      const res = await fetch(`${BACKEND_URL}/admin/team/remove`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ userId }),
      });
      const data = (await res.json()) as { ok?: boolean; error?: string };
      if (!res.ok || !data.ok) {
        const msg =
          data.error === "cannot_remove_self"
            ? "You can't remove yourself."
            : data.error === "owner_only"
              ? "Only the owner can remove an owner."
              : data.error === "forbidden"
                ? "Moderators can't change the team."
                : "Couldn't remove. Try again.";
        throw new Error(msg);
      }
      return data;
    },
    onSuccess: () => {
      toast.success("Member removed.");
      void queryClient.invalidateQueries({ queryKey: ["admin-team"] });
    },
    onError: (err) => {
      toast.error(err instanceof Error ? err.message : "Something went wrong.");
    },
  });

  const decide = useMutation({
    mutationFn: async (input: {
      role: BadgeRole;
      id: string;
      decision: "approved" | "denied";
    }) => {
      const res = await fetch(`${BACKEND_URL}/admin/applications/decide`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify(input),
      });
      const data = (await res.json()) as {
        ok?: boolean;
        emailSent?: boolean;
        error?: string;
      };
      if (!res.ok || !data.ok) {
        throw new Error(
          data.error === "forbidden"
            ? "Your account doesn't have review permissions."
            : "Couldn't save the decision. Try again."
        );
      }
      return data;
    },
    onSuccess: (data, vars) => {
      if (vars.decision === "approved") {
        toast.success(
          data.emailSent
            ? "Approved — payment link emailed to the applicant."
            : "Approved — but no email on file, so no payment link was sent."
        );
      } else {
        toast.success("Application denied.");
      }
      void queryClient.invalidateQueries({ queryKey: ["admin-applications"] });
    },
    onError: (err) => {
      toast.error(err instanceof Error ? err.message : "Something went wrong.");
    },
  });

  const forbidden =
    queues.error instanceof Error && queues.error.message === "forbidden";
  const active: QueueData | undefined =
    tab === "team" || tab === "recruiters" ? undefined : queues.data?.[tab];

  // Admin recruiter leaderboard — aggregate ratings + signup counts so the
  // founder can see which recruiters are performing well and which aren't.
  const recruitersList = useQuery<RecruiterLeaderboardRow[]>({
    queryKey: ["admin-recruiters", session?.user.id],
    enabled: !!token && tab === "recruiters",
    queryFn: async ({ signal }) => {
      const res = await fetch(`${BACKEND_URL}/admin/recruiters`, {
        headers: { Authorization: `Bearer ${token}` }, signal,
      });
      if (res.status === 403) throw new Error("forbidden");
      if (!res.ok) throw new Error("Couldn't load recruiters.");
      const data = (await res.json()) as { recruiters: RecruiterLeaderboardRow[] };
      return data.recruiters ?? [];
    },
    retry: false,
  });

  // Per-recruiter review drill-down (loaded when a recruiter is expanded).
  const [expandedRecruiter, setExpandedRecruiter] = useState<string | null>(null);
  const recruiterReviews = useQuery<RecruiterReviewSummary>({
    queryKey: ["recruiter-reviews", session?.user.id, expandedRecruiter],
    enabled: !!session && !!expandedRecruiter,
    queryFn: () => fetchRecruiterReviews(expandedRecruiter!),
    staleTime: 30_000,
  });

  return (
    <div className="flex min-h-screen flex-col bg-background">
      <PublicNav />

      <main className="mx-auto w-full max-w-2xl flex-1 px-4 pb-16 pt-28 sm:px-6">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <h1 className="font-display text-[26px] font-extrabold">
            Account reviews
          </h1>
          <div className="flex gap-2">
            <Button variant="outline" className="rounded-full" asChild>
              <a href="/admin/articles">Articles</a>
            </Button>
            <Button variant="outline" className="rounded-full" asChild>
              <a href="/admin/featured">Featured profiles</a>
            </Button>
          </div>
        </div>
        <p className="mt-2 text-[14px] leading-relaxed text-muted-foreground">
          Approving emails the applicant their annual payment link — the badge
          and perks only switch on after the payment confirms. Denying clears
          any lingering perks.
        </p>

        {loading || (queues.isPending && !!token) ? (
          <div className="flex justify-center pt-20">
            <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
          </div>
        ) : !session ? (
          <div className="mt-10 rounded-[24px] border border-border bg-card p-8 text-center">
            <ShieldCheck className="mx-auto mb-4 h-10 w-10 text-muted-foreground" />
            <p className="text-[15px] font-semibold">
              Sign in with an admin account to review applications.
            </p>
            <Button className="mt-5 rounded-full" asChild>
              <a href="/auth?next=%2Fadmin%2Fapplications">Sign in</a>
            </Button>
          </div>
        ) : forbidden ? (
          <div className="mt-10 rounded-[24px] border border-border bg-card p-8 text-center">
            <CircleAlert className="mx-auto mb-4 h-10 w-10 text-muted-foreground" />
            <p className="text-[15px] font-semibold">
              This account doesn't have review permissions.
            </p>
            <p className="mt-2 text-[13px] text-muted-foreground">
              Only admins, moderators, and the owner can access this page.
            </p>
          </div>
        ) : queues.isError ? (
          <div className="mt-10 rounded-[24px] border border-border bg-card p-8 text-center">
            <CircleAlert className="mx-auto mb-4 h-10 w-10 text-muted-foreground" />
            <p className="text-[15px] font-semibold">
              Couldn't load applications.
            </p>
            <Button
              variant="outline"
              className="mt-5 rounded-full"
              onClick={() => void queues.refetch()}
            >
              Retry
            </Button>
          </div>
        ) : (
          <>
            <div className="mt-6 flex gap-2">
              {TABS.map((t) => {
                const count = queues.data?.[t.role]?.pending.length ?? 0;
                const selected = tab === t.role;
                return (
                  <button
                    key={t.role}
                    onClick={() => setTab(t.role)}
                    className={cn(
                      "flex flex-1 items-center justify-center gap-2 rounded-full border px-3 py-2.5 text-[13.5px] font-bold transition-colors",
                      selected
                        ? "border-foreground bg-foreground text-background"
                        : "border-border bg-card text-foreground hover:bg-accent"
                    )}
                  >
                    {t.label}
                    {count > 0 && (
                      <span
                        className={cn(
                          "rounded-full px-1.5 py-0.5 text-[11px] font-extrabold",
                          selected
                            ? "bg-background text-foreground"
                            : "bg-foreground text-background"
                        )}
                      >
                        {count}
                      </span>
                    )}
                  </button>
                );
              })}
              <button
                onClick={() => setTab("team")}
                className={cn(
                  "flex flex-1 items-center justify-center gap-2 rounded-full border px-3 py-2.5 text-[13.5px] font-bold transition-colors",
                  tab === "team"
                    ? "border-foreground bg-foreground text-background"
                    : "border-border bg-card text-foreground hover:bg-accent"
                )}
              >
                <Shield className="h-4 w-4" />
                Team
              </button>
              <button
                onClick={() => setTab("recruiters")}
                className={cn(
                  "flex flex-1 items-center justify-center gap-2 rounded-full border px-3 py-2.5 text-[13.5px] font-bold transition-colors",
                  tab === "recruiters"
                    ? "border-foreground bg-foreground text-background"
                    : "border-border bg-card text-foreground hover:bg-accent"
                )}
              >
                <Star className="h-4 w-4" />
                Recruiters
              </button>
              <button
                onClick={() => setTab("applicants")}
                className={cn(
                  "flex flex-1 items-center justify-center gap-2 rounded-full border px-3 py-2.5 text-[13.5px] font-bold transition-colors",
                  tab === "applicants"
                    ? "border-foreground bg-foreground text-background"
                    : "border-border bg-card text-foreground hover:bg-accent"
                )}
              >
                <ClipboardList className="h-4 w-4" />
                Applicants
              </button>
            </div>

            {tab === "applicants" ? (
              <section className="mt-6 space-y-6">
                <div className="flex items-center justify-between">
                  <h2 className="text-[13px] font-extrabold uppercase tracking-wider text-muted-foreground">
                    Applicant Questionnaire Editor
                  </h2>
                  <Link
                    to="/admin/applicants"
                    className="flex items-center gap-1.5 rounded-full bg-foreground px-3 py-1.5 text-xs font-bold text-background"
                  >
                    View all applicants <ChevronRight className="h-3 w-3" />
                  </Link>
                </div>
                <AdminApplicantQuestions />
              </section>
            ) : tab === "recruiters" ? (
              <RecruiterLeaderboard
                rows={recruitersList.data ?? []}
                loading={recruitersList.isPending}
                error={
                  recruitersList.isError
                    ? recruitersList.error instanceof Error
                      ? recruitersList.error.message
                      : "Couldn't load recruiters."
                    : null
                }
                onRetry={() => void recruitersList.refetch()}
                expandedRecruiter={expandedRecruiter}
                setExpandedRecruiter={setExpandedRecruiter}
                reviews={recruiterReviews.data}
                reviewsLoading={recruiterReviews.isLoading}
              />
            ) : tab === "team" ? (
              <section className="mt-6">
                <h2 className="text-[13px] font-extrabold uppercase tracking-wider text-muted-foreground">
                  Admins &amp; moderators
                </h2>
                <p className="mt-2 text-[13px] leading-relaxed text-muted-foreground">
                  Everyone here can review applications. Owners and admins can
                  also manage this list — changes sync to the app instantly.
                </p>

                {team.isPending ? (
                  <div className="flex justify-center pt-12">
                    <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
                  </div>
                ) : team.isError ? (
                  <div className="mt-4 rounded-[20px] border border-border bg-card p-6 text-center text-[14px] text-muted-foreground">
                    Couldn't load the team.
                    <Button
                      variant="outline"
                      className="mx-auto mt-4 block rounded-full"
                      onClick={() => void team.refetch()}
                    >
                      Retry
                    </Button>
                  </div>
                ) : (
                  <>
                    {canManageTeam && (
                      <div className="mt-4 rounded-[20px] border border-border bg-card p-4">
                        <p className="flex items-center gap-2 text-[14px] font-bold">
                          <UserPlus className="h-4 w-4" />
                          Add a team member
                        </p>
                        <div className="mt-3 flex flex-col gap-2 sm:flex-row">
                          <input
                            value={newIdentifier}
                            onChange={(e) => setNewIdentifier(e.target.value)}
                            placeholder="@username or email"
                            className="h-10 flex-1 rounded-full border border-border bg-background px-4 text-[14px] outline-none focus:border-foreground"
                          />
                          <select
                            value={newRole}
                            onChange={(e) =>
                              setNewRole(e.target.value as AdminRole)
                            }
                            className="h-10 rounded-full border border-border bg-background px-3 text-[13.5px] font-semibold outline-none focus:border-foreground"
                          >
                            <option value="moderator">Moderator</option>
                            <option value="admin">Admin</option>
                            {team.data.callerRole === "owner" && (
                              <option value="owner">Owner</option>
                            )}
                          </select>
                          <Button
                            className="h-10 rounded-full px-5 text-[13.5px] font-bold"
                            disabled={
                              upsertMember.isPending || !newIdentifier.trim()
                            }
                            onClick={() =>
                              upsertMember.mutate({
                                identifier: newIdentifier.trim(),
                                role: newRole,
                              })
                            }
                          >
                            {upsertMember.isPending ? (
                              <Loader2 className="h-4 w-4 animate-spin" />
                            ) : (
                              "Add"
                            )}
                          </Button>
                        </div>
                      </div>
                    )}

                    <div className="mt-4 space-y-2">
                      {team.data.members.length === 0 ? (
                        <div className="rounded-[20px] border border-dashed border-border p-8 text-center text-[14px] text-muted-foreground">
                          No team members yet — run the setup SQL or add one
                          above.
                        </div>
                      ) : (
                        team.data.members.map((m) => (
                          <div
                            key={m.id}
                            className="flex items-center justify-between rounded-[16px] border border-border bg-card px-4 py-3"
                          >
                            <div className="flex min-w-0 items-center gap-2.5">
                              {m.role === "owner" ? (
                                <Crown className="h-4 w-4 shrink-0 text-amber-500" />
                              ) : (
                                <Shield className="h-4 w-4 shrink-0 text-muted-foreground" />
                              )}
                              <div className="min-w-0">
                                <p className="truncate text-[14px] font-semibold">
                                  {m.username
                                    ? `@${m.username}`
                                    : (m.email ?? m.user_id.slice(0, 8))}
                                </p>
                                {m.email && m.username && (
                                  <p className="truncate text-[12px] text-muted-foreground">
                                    {m.email}
                                  </p>
                                )}
                              </div>
                            </div>
                            <div className="flex shrink-0 items-center gap-2">
                              <span
                                className={cn(
                                  "rounded-full px-2.5 py-1 text-[11px] font-extrabold uppercase tracking-wide",
                                  ROLE_BADGE[m.role].classes
                                )}
                              >
                                {ROLE_BADGE[m.role].label}
                              </span>
                              {canManageTeam &&
                                m.user_id !== team.data.callerUserId && (
                                  <button
                                    className="rounded-full p-2 text-muted-foreground transition-colors hover:bg-accent hover:text-red-500"
                                    disabled={removeMember.isPending}
                                    onClick={() =>
                                      removeMember.mutate(m.user_id)
                                    }
                                    aria-label={`Remove ${m.username ?? m.email ?? "member"}`}
                                  >
                                    <Trash2 className="h-4 w-4" />
                                  </button>
                                )}
                            </div>
                          </div>
                        ))
                      )}
                    </div>
                  </>
                )}
              </section>
            ) : (
            <>
            <section className="mt-6">
              <h2 className="text-[13px] font-extrabold uppercase tracking-wider text-muted-foreground">
                Pending review
              </h2>
              {!active || active.pending.length === 0 ? (
                <div className="mt-3 rounded-[20px] border border-dashed border-border p-8 text-center text-[14px] text-muted-foreground">
                  <Clock className="mx-auto mb-2 h-6 w-6" />
                  No pending applications — new submissions land here.
                </div>
              ) : (
                <div className="mt-3 space-y-3">
                  {active.pending.map((row) => (
                    <div
                      key={row.id}
                      className="rounded-[20px] border border-border bg-card p-4"
                    >
                      <button
                        className="w-full text-left"
                        onClick={() =>
                          setExpanded(expanded === row.id ? null : row.id)
                        }
                      >
                        <div className="flex items-center gap-2">
                          <span
                            className={
                              TABS.find((t) => t.role === tab)?.accent
                            }
                          >
                            {roleIcon(tab)}
                          </span>
                          <span className="text-[15px] font-bold">
                            {row.full_name}
                          </span>
                          <span className="text-[13px] text-muted-foreground">
                            @{row.username}
                          </span>
                        </div>
                        {detailLine(row, tab) && (
                          <p className="mt-1 text-[13px] text-muted-foreground">
                            {detailLine(row, tab)}
                          </p>
                        )}
                        {expanded === row.id && (
                          <div className="mt-3 space-y-2 border-t border-border pt-3 text-[13.5px] leading-relaxed">
                            {row.email && <p>Email: {row.email}</p>}
                            {row.credentials && (
                              <p>Credentials: {row.credentials}</p>
                            )}
                            {row.prs && <p>Personal records: {row.prs}</p>}
                            {row.bio && <p>Bio: {row.bio}</p>}
                            {row.reason && <p>Reason: {row.reason}</p>}
                            {row.links && <p>Links: {row.links}</p>}
                            {row.website && <p>Website: {row.website}</p>}
                            {row.social && <p>Social: {row.social}</p>}
                          </div>
                        )}
                      </button>
                      <div className="mt-3 flex gap-2">
                        <Button
                          className="h-10 flex-1 rounded-full text-[13.5px] font-bold"
                          disabled={decide.isPending}
                          onClick={() =>
                            decide.mutate({
                              role: tab,
                              id: row.id,
                              decision: "approved",
                            })
                          }
                        >
                          {decide.isPending ? (
                            <Loader2 className="h-4 w-4 animate-spin" />
                          ) : (
                            "Approve + send payment link"
                          )}
                        </Button>
                        <Button
                          variant="outline"
                          className="h-10 flex-1 rounded-full text-[13.5px] font-bold"
                          disabled={decide.isPending}
                          onClick={() =>
                            decide.mutate({
                              role: tab,
                              id: row.id,
                              decision: "denied",
                            })
                          }
                        >
                          Deny
                        </Button>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </section>

            {active && active.recent.length > 0 && (
              <section className="mt-8">
                <h2 className="text-[13px] font-extrabold uppercase tracking-wider text-muted-foreground">
                  Recent decisions
                </h2>
                <div className="mt-3 space-y-2">
                  {active.recent.map((row) => (
                    <div
                      key={row.id}
                      className="flex items-center justify-between rounded-[16px] border border-border bg-card px-4 py-3"
                    >
                      <div>
                        <span className="text-[14px] font-semibold">
                          {row.full_name}
                        </span>
                        <span className="ml-2 text-[12.5px] text-muted-foreground">
                          @{row.username}
                        </span>
                      </div>
                      <span
                        className={cn(
                          "rounded-full px-2.5 py-1 text-[11px] font-extrabold uppercase tracking-wide",
                          row.status === "approved"
                            ? "bg-emerald-500/10 text-emerald-600"
                            : "bg-red-500/10 text-red-500"
                        )}
                      >
                        {row.status}
                      </span>
                    </div>
                  ))}
                </div>
              </section>
            )}
            </>
            )}
          </>
        )}

        {!!token && (
          <>
            <AdminReceiptsPanel token={token} />
            <AdminRefundsPanel token={token} />
            <AdminBadgeGrants token={token} />
          </>
        )}
      </main>

      <PublicFooter />
    </div>
  );
}

// ---------------------------------------------------------------------------
// Recruiter leaderboard — aggregate ratings + signup counts so the founder
// can see which recruiters are performing well and which aren't.
// ---------------------------------------------------------------------------

function RecruiterLeaderboard({
  rows,
  loading,
  error,
  onRetry,
  expandedRecruiter,
  setExpandedRecruiter,
  reviews,
  reviewsLoading,
}: {
  rows: RecruiterLeaderboardRow[];
  loading: boolean;
  error: string | null;
  onRetry: () => void;
  expandedRecruiter: string | null;
  setExpandedRecruiter: (id: string | null) => void;
  reviews?: RecruiterReviewSummary;
  reviewsLoading: boolean;
}) {
  if (loading) {
    return (
      <div className="mt-6 flex justify-center pt-12">
        <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
      </div>
    );
  }
  if (error) {
    return (
      <div className="mt-6 rounded-[20px] border border-border bg-card p-6 text-center text-[14px] text-muted-foreground">
        {error}
        <Button
          variant="outline"
          className="mx-auto mt-4 block rounded-full"
          onClick={onRetry}
        >
          Retry
        </Button>
      </div>
    );
  }
  if (rows.length === 0) {
    return (
      <div className="mt-6 rounded-[20px] border border-dashed border-border p-8 text-center text-[14px] text-muted-foreground">
        <UserCheck className="mx-auto mb-2 h-6 w-6" />
        No recruiters yet — approved recruiters will show up here with their
        ratings and referral counts.
      </div>
    );
  }

  return (
    <section className="mt-6">
      <h2 className="text-[13px] font-extrabold uppercase tracking-wider text-muted-foreground">
        Recruiter performance
      </h2>
      <p className="mt-2 text-[13px] leading-relaxed text-muted-foreground">
        Every recruiter's referrals, average rating, and reviews side-by-side
        so you can see who's bringing in talent and how they're treating them.
      </p>

      <div className="mt-4 space-y-2">
        {rows.map((r) => {
          const expanded = expandedRecruiter === r.userId;
          return (
            <div
              key={r.userId}
              className="rounded-[16px] border border-border bg-card overflow-hidden"
            >
              <button
                className="flex w-full items-center gap-3 px-4 py-3 text-left transition-colors hover:bg-secondary/40"
                onClick={() =>
                  setExpandedRecruiter(expanded ? null : r.userId)
                }
              >
                <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-secondary text-foreground/70">
                  <UserCheck className="h-5 w-5" />
                </div>
                <div className="min-w-0 flex-1">
                  <p className="truncate text-[14px] font-bold">
                    {r.displayName ?? `@${r.username ?? r.userId.slice(0, 8)}`}
                  </p>
                  <p className="truncate text-[12px] text-muted-foreground">
                    @{r.username ?? "unknown"} · {r.signupCount} referrals
                  </p>
                </div>
                {/* Star summary */}
                {r.reviewCount > 0 ? (
                  <div className="flex shrink-0 items-center gap-1.5">
                    <span className="flex items-center gap-0.5">
                      <Star className="h-3.5 w-3.5 fill-amber-400 text-amber-400" />
                      <span className="text-[14px] font-extrabold tabular-nums">
                        {r.averageRating?.toFixed(1) ?? "-"}
                      </span>
                    </span>
                    <span className="text-[11px] text-muted-foreground">
                      ({r.reviewCount})
                    </span>
                  </div>
                ) : (
                  <span className="shrink-0 text-[11px] text-muted-foreground">
                    No reviews
                  </span>
                )}
              </button>

              {expanded && (
                <div className="border-t border-border bg-background/50 px-4 py-3">
                  {reviewsLoading ? (
                    <div className="flex justify-center py-4">
                      <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
                    </div>
                  ) : reviews && reviews.reviews.length > 0 ? (
                    <div className="space-y-3">
                      <div className="flex gap-3 text-[12px] font-semibold text-muted-foreground">
                        <span className="text-emerald-600">
                          {reviews.positiveCount} positive
                        </span>
                        <span className="text-red-500">
                          {reviews.negativeCount} negative
                        </span>
                        <span>{reviews.reviewCount} total</span>
                      </div>
                      {reviews.reviews.map((rv, i) => (
                        <div
                          key={i}
                          className="rounded-xl border border-border bg-card p-3"
                        >
                          <div className="flex items-center gap-1.5">
                            {Array.from({ length: 5 }).map((_, j) => (
                              <Star
                                key={j}
                                className={cn(
                                  "h-3 w-3",
                                  j < rv.rating
                                    ? "fill-amber-400 text-amber-400"
                                    : "text-muted-foreground/30"
                                )}
                              />
                            ))}
                            <span className="ml-1 text-[11px] text-muted-foreground">
                              {new Date(rv.created_at).toLocaleDateString()}
                            </span>
                          </div>
                          {rv.review && (
                            <p className="mt-1.5 text-[13px] leading-snug text-foreground/90">
                              {rv.review}
                            </p>
                          )}
                        </div>
                      ))}
                    </div>
                  ) : (
                    <p className="py-3 text-center text-[13px] text-muted-foreground">
                      No reviews yet for this recruiter.
                    </p>
                  )}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </section>
  );
}
