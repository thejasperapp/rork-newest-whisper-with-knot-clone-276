import { useState, useMemo } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import {
  ArrowLeft,
  Users,
  Loader2,
  TrendingUp,
  Award,
  Gauge,
  ChevronRight,
} from "lucide-react";

import { Avatar } from "@/components/Avatar";
import { useAuth } from "@/hooks/useAuth";
import { fetchAllResponses, type ApplicantResponse } from "@/lib/applicantQuestionnaire";
import { fetchProfilesByIds } from "@/lib/api";
import { cn } from "@/lib/utils";

const POSITION_META: Record<string, { label: string; color: string }> = {
  coach: { label: "Coach", color: "#f97316" },
  athlete: { label: "Athlete", color: "#ef4444" },
  creator: { label: "Creator", color: "#3b82f6" },
};

export default function AdminApplicants() {
  const { user } = useAuth();
  const [searchParams, setSearchParams] = useSearchParams();
  const selectedRecruiter = searchParams.get("recruiter") ?? null;

  const allResponsesQuery = useQuery({
    queryKey: ["admin-all-applicants", user?.id],
    queryFn: () => fetchAllResponses(),
    enabled: !!user,
  });

  const responses = allResponsesQuery.data ?? [];

  // Group by recruiter
  const byRecruiter = useMemo(() => {
    const map: Record<string, ApplicantResponse[]> = {};
    for (const r of responses) {
      if (!map[r.recruiter_id]) map[r.recruiter_id] = [];
      map[r.recruiter_id].push(r);
    }
    return map;
  }, [responses]);

  const recruiterIds = Object.keys(byRecruiter).sort();
  const profilesQuery = useQuery({
    queryKey: ["admin-applicant-recruiters", user?.id, recruiterIds],
    queryFn: () => fetchProfilesByIds(recruiterIds),
    enabled: !!user && recruiterIds.length > 0,
  });
  const recruiterProfiles = profilesQuery.data ?? {};

  // Filtered responses for selected recruiter
  const filteredResponses = selectedRecruiter
    ? byRecruiter[selectedRecruiter] ?? []
    : responses;

  // Fetch applicant profiles for the filtered responses
  const applicantUserIds = [...new Set(filteredResponses
    .map((r) => r.applicant_user_id)
    .filter((id): id is string => !!id))].sort();
  const applicantProfilesQuery = useQuery({
    queryKey: ["admin-applicant-profiles", user?.id, applicantUserIds],
    queryFn: () => fetchProfilesByIds(applicantUserIds),
    enabled: !!user && applicantUserIds.length > 0,
  });
  const applicantProfiles = applicantProfilesQuery.data ?? {};

  return (
    <div className="min-h-screen bg-muted/30">
      <div className="sticky top-0 z-30 flex h-14 items-center gap-3 rounded-b-[22px] border-b border-border bg-background px-4">
        <Link to="/admin/applications" className="flex h-10 w-10 items-center justify-center rounded-full transition-colors hover:bg-secondary">
          <ArrowLeft className="h-5 w-5" />
        </Link>
        <h1 className="font-display text-base font-bold">Applicant Pipeline</h1>
      </div>

      <div className="mx-auto max-w-4xl px-4 py-6">
        {/* Stats */}
        <div className="mb-6 grid grid-cols-4 gap-2">
          <div className="rounded-xl bg-card p-3 text-center">
            <p className="text-2xl font-black tabular-nums">{responses.length}</p>
            <p className="text-[11px] font-semibold text-muted-foreground">Total applicants</p>
          </div>
          <div className="rounded-xl bg-card p-3 text-center">
            <p className="text-2xl font-black tabular-nums text-amber-600">
              {responses.filter((r) => r.status === "submitted").length}
            </p>
            <p className="text-[11px] font-semibold text-muted-foreground">Pending</p>
          </div>
          <div className="rounded-xl bg-card p-3 text-center">
            <p className="text-2xl font-black tabular-nums text-emerald-600">
              {responses.filter((r) => r.status === "accepted").length}
            </p>
            <p className="text-[11px] font-semibold text-muted-foreground">Accepted</p>
          </div>
          <div className="rounded-xl bg-card p-3 text-center">
            <p className="text-2xl font-black tabular-nums">{recruiterIds.length}</p>
            <p className="text-[11px] font-semibold text-muted-foreground">Recruiters</p>
          </div>
        </div>

        {/* Recruiter filter chips */}
        {recruiterIds.length > 0 && (
          <div className="mb-6">
            <p className="mb-2 text-xs font-bold uppercase tracking-wider text-muted-foreground">
              Filter by recruiter
            </p>
            <div className="flex flex-wrap gap-2">
              <button
                onClick={() => setSearchParams({})}
                className={cn(
                  "rounded-full border px-3 py-1.5 text-xs font-bold transition-colors",
                  !selectedRecruiter
                    ? "border-foreground bg-foreground text-background"
                    : "border-border bg-card text-foreground hover:bg-secondary"
                )}
              >
                All ({responses.length})
              </button>
              {recruiterIds.map((rid) => {
                const p = recruiterProfiles[rid];
                const count = byRecruiter[rid]?.length ?? 0;
                return (
                  <button
                    key={rid}
                    onClick={() => setSearchParams({ recruiter: rid })}
                    className={cn(
                      "flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-bold transition-colors",
                      selectedRecruiter === rid
                        ? "border-foreground bg-foreground text-background"
                        : "border-border bg-card text-foreground hover:bg-secondary"
                    )}
                  >
                    <Avatar url={p?.profile_image_url ?? null} name={p?.username ?? "R"} size={18} />
                    @{p?.username ?? "recruiter"} ({count})
                  </button>
                );
              })}
            </div>
          </div>
        )}

        {/* Applications list */}
        {allResponsesQuery.isLoading ? (
          <div className="flex justify-center py-20">
            <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
          </div>
        ) : filteredResponses.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-border bg-card p-8 text-center">
            <Users className="mx-auto mb-3 h-10 w-10 text-muted-foreground" />
            <p className="text-sm font-bold">No applicants yet</p>
            <p className="mt-1 text-xs text-muted-foreground">
              When leads scan a recruiter's QR code and fill the questionnaire, they'll appear here.
            </p>
          </div>
        ) : (
          <div className="space-y-2">
            {filteredResponses.map((r) => {
              const profile = r.applicant_user_id ? applicantProfiles[r.applicant_user_id] : null;
              const recruiterProfile = recruiterProfiles[r.recruiter_id];
              const positionMeta = r.best_position ? POSITION_META[r.best_position] : null;
              return (
                <div
                  key={r.id}
                  className="flex items-center gap-3 rounded-2xl border border-border bg-card p-4"
                >
                  <Avatar
                    url={profile?.profile_image_url ?? null}
                    name={r.applicant_name ?? "A"}
                    size={48}
                  />
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <p className="truncate text-sm font-bold">
                        {r.applicant_name ?? profile?.username ?? "Unknown"}
                      </p>
                      <StatusBadge status={r.status} />
                    </div>
                    <p className="truncate text-xs text-muted-foreground">
                      {r.applicant_email ?? "No email"}
                    </p>
                    {!selectedRecruiter && recruiterProfile && (
                      <p className="mt-0.5 truncate text-[10px] text-muted-foreground">
                        via @{recruiterProfile.username}
                      </p>
                    )}
                    {positionMeta && (
                      <div className="mt-1 flex items-center gap-2">
                        <span
                          className="rounded-full px-2 py-0.5 text-[10px] font-bold"
                          style={{
                            backgroundColor: `${positionMeta.color}20`,
                            color: positionMeta.color,
                          }}
                        >
                          {positionMeta.label}
                        </span>
                        <span className="flex items-center gap-0.5 text-[10px] font-semibold text-muted-foreground">
                          <Award className="h-3 w-3" /> {r.potential_score}/100
                        </span>
                        <span className="flex items-center gap-0.5 text-[10px] font-semibold text-muted-foreground">
                          <Gauge className="h-3 w-3" /> {r.confidence_score}%
                        </span>
                      </div>
                    )}
                  </div>
                  <ChevronRight className="h-5 w-5 shrink-0 text-muted-foreground" />
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}

function StatusBadge({ status }: { status: string }) {
  const styles: Record<string, string> = {
    submitted: "bg-amber-500/10 text-amber-600",
    reviewed: "bg-blue-500/10 text-blue-600",
    accepted: "bg-emerald-500/10 text-emerald-600",
    rejected: "bg-red-500/10 text-red-600",
  };
  const labels: Record<string, string> = {
    submitted: "Pending",
    reviewed: "Reviewed",
    accepted: "Accepted",
    rejected: "Rejected",
  };
  return (
    <span className={cn("rounded-full px-2 py-0.5 text-[10px] font-bold", styles[status] ?? styles.submitted)}>
      {labels[status] ?? status}
    </span>
  );
}
