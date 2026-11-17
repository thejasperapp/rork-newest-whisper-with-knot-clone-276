import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ArrowLeft,
  Building2,
  CheckCircle2,
  Clock,
  Handshake,
  Landmark,
  Link2,
  Loader2,
  Wallet,
  X,
} from "lucide-react";
import { toast } from "sonner";

import { useAuth } from "@/hooks/useAuth";
import { fetchPostsByUser } from "@/lib/api";
import { fetchConnectStatus } from "@/lib/coachPay";
import {
  creatorRespond,
  fetchApplications,
  fetchCreatorEarnings,
  fetchDeals,
  formatSponsorAmount,
  trackSponsoredPost,
  type SponsorDeal,
  type SponsorPayment,
  type SponsorPost,
} from "@/lib/brands";

function StatusPill({ status }: { status: string }) {
  const styles: Record<string, string> = {
    pending: "bg-amber-500/15 text-amber-600",
    countered: "bg-indigo-500/15 text-indigo-500",
    accepted: "bg-emerald-500/15 text-emerald-600",
    active: "bg-emerald-500/15 text-emerald-600",
    denied: "bg-red-500/15 text-red-500",
    withdrawn: "bg-muted text-muted-foreground",
  };
  const labels: Record<string, string> = { countered: "New terms" };
  return (
    <span
      className={`rounded-full px-2.5 py-0.5 text-[11px] font-bold capitalize ${styles[status] ?? "bg-muted text-muted-foreground"}`}
    >
      {labels[status] ?? status}
    </span>
  );
}

function TrackPostModal({
  deal,
  onClose,
}: {
  deal: SponsorDeal;
  onClose: () => void;
}) {
  const { user } = useAuth();
  const queryClient = useQueryClient();

  const postsQuery = useQuery({
    queryKey: ["my-posts", user?.id ?? ""],
    queryFn: () => fetchPostsByUser(user!.id),
    enabled: !!user?.id,
  });

  const track = useMutation({
    mutationFn: (postId: string) =>
      trackSponsoredPost({ dealId: deal.id, postId }),
    onSuccess: () => {
      toast.success("Post linked — per-post payments release automatically.");
      queryClient.invalidateQueries({ queryKey: ["sponsorship-deals"] });
      onClose();
    },
    onError: (err) =>
      toast.error(err instanceof Error ? err.message : "Couldn't link post."),
  });

  const posts = postsQuery.data ?? [];

  return (
    <div className="fixed inset-0 z-[80] flex items-end justify-center sm:items-center">
      <button
        aria-label="Close"
        onClick={onClose}
        className="absolute inset-0 bg-black/50 backdrop-blur-sm"
      />
      <div className="relative flex max-h-[80dvh] w-full max-w-md flex-col overflow-hidden rounded-t-[24px] bg-card shadow-2xl sm:rounded-[24px]">
        <div className="flex items-center justify-between border-b border-border px-5 py-4">
          <div>
            <p className="text-[16px] font-extrabold">Link a sponsored post</p>
            <p className="text-[12.5px] text-muted-foreground">
              Fulfills your {deal.brand_company ?? "brand"} deal
            </p>
          </div>
          <button
            onClick={onClose}
            aria-label="Close"
            className="flex h-9 w-9 items-center justify-center rounded-full bg-secondary"
          >
            <X className="h-4 w-4" />
          </button>
        </div>
        <div className="flex-1 space-y-2 overflow-y-auto p-4">
          {postsQuery.isLoading ? (
            <div className="flex justify-center py-10">
              <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
            </div>
          ) : posts.length === 0 ? (
            <p className="py-8 text-center text-[13px] text-muted-foreground">
              No posts yet — publish your sponsored post first, then link it
              here.
            </p>
          ) : (
            posts.slice(0, 25).map((post) => (
              <button
                key={post.id}
                onClick={() => track.mutate(post.id)}
                disabled={track.isPending}
                className="flex w-full items-center gap-3 rounded-[14px] border border-border bg-background p-3 text-left transition-transform active:scale-[0.99] disabled:opacity-50"
              >
                <Link2 className="h-4 w-4 shrink-0 text-indigo-500" />
                <span className="min-w-0 flex-1 truncate text-[13.5px] font-semibold">
                  {post.caption?.trim() ? post.caption : "Untitled post"}
                </span>
              </button>
            ))
          )}
        </div>
      </div>
    </div>
  );
}

function DealCard({
  deal,
  payments,
  posts,
  onTrack,
}: {
  deal: SponsorDeal;
  payments: SponsorPayment[];
  posts: SponsorPost[];
  onTrack: () => void;
}) {
  const pendingNet = payments
    .filter((p) => p.status === "pending")
    .reduce((s, p) => s + p.net_cents, 0);
  const releasedNet = payments
    .filter((p) => p.status === "released")
    .reduce((s, p) => s + p.net_cents, 0);
  const fmt = (c: number) =>
    (c / 100).toLocaleString("en-US", { style: "currency", currency: "USD" });

  return (
    <div className="rounded-[20px] border border-border bg-card p-4">
      <div className="flex items-start justify-between gap-2">
        <div>
          <p className="text-[15px] font-extrabold">
            {deal.brand_company ?? "Brand"}
          </p>
          <p className="text-[13px] font-bold text-indigo-500">
            {formatSponsorAmount(deal.amount_cents, deal.basis)}
          </p>
        </div>
        <StatusPill status={deal.status} />
      </div>
      <div className="mt-3 grid grid-cols-3 gap-2 text-center">
        <div className="rounded-xl bg-secondary/60 py-2">
          <p className="text-[14px] font-black text-amber-600">
            {fmt(pendingNet)}
          </p>
          <p className="text-[11px] text-muted-foreground">Pending</p>
        </div>
        <div className="rounded-xl bg-secondary/60 py-2">
          <p className="text-[14px] font-black text-emerald-600">
            {fmt(releasedNet)}
          </p>
          <p className="text-[11px] text-muted-foreground">Released</p>
        </div>
        <div className="rounded-xl bg-secondary/60 py-2">
          <p className="text-[14px] font-black">{posts.length}</p>
          <p className="text-[11px] text-muted-foreground">Posts tracked</p>
        </div>
      </div>
      {deal.notes && (
        <p className="mt-2.5 text-[12.5px] leading-snug text-muted-foreground">
          {deal.notes}
        </p>
      )}
      {deal.status === "active" && (
        <button
          onClick={onTrack}
          className="mt-3 flex w-full items-center justify-center gap-2 rounded-full bg-indigo-500/10 py-2.5 text-[13px] font-bold text-indigo-500 transition-transform active:scale-[0.98]"
        >
          <Link2 className="h-3.5 w-3.5" /> Link a sponsored post
        </button>
      )}
    </div>
  );
}

/**
 * Creator sponsorship hub — sent applications (accept counters, withdraw),
 * active deals with post tracking, and the escrow payment ledger.
 */
export default function MySponsorships() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const [trackingDeal, setTrackingDeal] = useState<SponsorDeal | null>(null);

  const appsQuery = useQuery({
    queryKey: ["sponsorship-applications", user?.id ?? ""],
    queryFn: () => fetchApplications(),
    enabled: !!user?.id,
  });

  const dealsQuery = useQuery({
    queryKey: ["sponsorship-deals", user?.id ?? ""],
    queryFn: () => fetchDeals(),
    enabled: !!user?.id,
  });

  const connectQuery = useQuery({
    queryKey: ["connect-status", user?.id ?? ""],
    queryFn: () => fetchConnectStatus(),
    enabled: !!user?.id,
  });

  const earningsQuery = useQuery({
    queryKey: ["creator-earnings", user?.id ?? ""],
    queryFn: () => fetchCreatorEarnings(),
    enabled: !!user?.id,
  });

  const respond = useMutation({
    mutationFn: (opts: { id: string; action: "accept" | "withdraw" }) =>
      creatorRespond(opts),
    onSuccess: (_d, opts) => {
      toast.success(
        opts.action === "accept" ? "Deal created!" : "Application withdrawn."
      );
      queryClient.invalidateQueries({ queryKey: ["sponsorship-applications"] });
      queryClient.invalidateQueries({ queryKey: ["sponsorship-deals"] });
    },
    onError: (err) =>
      toast.error(err instanceof Error ? err.message : "Couldn't respond."),
  });

  const apps = appsQuery.data?.asCreator ?? [];
  const myDeals = (dealsQuery.data?.deals ?? []).filter(
    (d) => d.creator_user_id === user?.id
  );
  const needsBank =
    myDeals.length > 0 && connectQuery.data?.payoutsEnabled !== true;

  return (
    <div className="mx-auto w-full max-w-xl px-4 pb-24 pt-3">
      <button
        onClick={() => navigate(-1)}
        className="mb-3 inline-flex items-center gap-1.5 text-[13.5px] font-bold text-muted-foreground"
      >
        <ArrowLeft className="h-4 w-4" /> Back
      </button>

      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-[20px] font-black">My Sponsorships</h1>
          <p className="text-[13px] text-muted-foreground">
            Applications, deals, and escrow payouts.
          </p>
        </div>
        <Link
          to="/brands"
          className="inline-flex items-center gap-1.5 rounded-full border border-border bg-card px-4 py-2 text-[12.5px] font-bold"
        >
          <Building2 className="h-3.5 w-3.5" /> Browse brands
        </Link>
      </div>

      {earningsQuery.data &&
        (myDeals.length > 0 ||
          earningsQuery.data.pendingCents > 0 ||
          earningsQuery.data.releasedCents > 0) && (
          <div className="mt-4 rounded-[20px] border border-border bg-card p-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <span className="flex h-8 w-8 items-center justify-center rounded-full bg-emerald-500/12">
                  <Wallet className="h-4 w-4 text-emerald-600" />
                </span>
                <p className="text-[14px] font-extrabold">Your earnings</p>
              </div>
              <Link
                to="/coach/earnings"
                className="text-[12px] font-bold text-indigo-500"
              >
                Payouts & bank →
              </Link>
            </div>
            <div className="mt-3 grid grid-cols-2 gap-2 text-center">
              <div className="rounded-xl bg-amber-500/8 py-2.5">
                <p className="text-[17px] font-black text-amber-600">
                  {(earningsQuery.data.pendingCents / 100).toLocaleString(
                    "en-US",
                    { style: "currency", currency: "USD" }
                  )}
                </p>
                <p className="text-[11px] text-muted-foreground">
                  In escrow for you
                </p>
              </div>
              <div className="rounded-xl bg-emerald-500/8 py-2.5">
                <p className="text-[17px] font-black text-emerald-600">
                  {(earningsQuery.data.releasedCents / 100).toLocaleString(
                    "en-US",
                    { style: "currency", currency: "USD" }
                  )}
                </p>
                <p className="text-[11px] text-muted-foreground">
                  Paid out to date
                </p>
              </div>
            </div>
            <p className="mt-2 text-[11.5px] leading-snug text-muted-foreground">
              {earningsQuery.data.payoutsEnabled
                ? "Your bank is linked — released funds transfer automatically."
                : "Link your bank so released funds can reach you."}
            </p>
          </div>
        )}

      {needsBank && (
        <Link
          to="/coach/earnings"
          className="mt-4 flex items-start gap-2.5 rounded-[16px] border border-amber-500/30 bg-amber-500/5 p-3.5"
        >
          <Landmark className="mt-0.5 h-4.5 w-4.5 shrink-0 text-amber-600" />
          <span className="text-[12.5px] leading-snug">
            <span className="font-bold">Link your bank to get paid.</span>{" "}
            <span className="text-muted-foreground">
              Sponsorship payments stay pending until a payout account is
              connected — takes about a minute.
            </span>
          </span>
        </Link>
      )}

      {appsQuery.isLoading || dealsQuery.isLoading ? (
        <div className="flex justify-center py-16">
          <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
        </div>
      ) : apps.length === 0 && myDeals.length === 0 ? (
        <div className="py-16 text-center">
          <Handshake className="mx-auto h-8 w-8 text-muted-foreground" />
          <p className="mt-3 text-[15px] font-bold">No sponsorships yet</p>
          <p className="mx-auto mt-1 max-w-xs text-[13px] text-muted-foreground">
            Browse sponsor brands, see exactly what they pay, and apply. Your
            applications and deals live here.
          </p>
          <Link
            to="/brands"
            className="mt-4 inline-block rounded-full bg-indigo-500 px-5 py-2.5 text-[13.5px] font-bold text-white"
          >
            Browse brands
          </Link>
        </div>
      ) : (
        <>
          {myDeals.length > 0 && (
            <>
              <p className="mt-6 text-[14px] font-extrabold">Active deals</p>
              <div className="mt-2.5 space-y-3">
                {myDeals.map((deal) => (
                  <DealCard
                    key={deal.id}
                    deal={deal}
                    payments={(dealsQuery.data?.payments ?? []).filter(
                      (p) => p.deal_id === deal.id
                    )}
                    posts={(dealsQuery.data?.posts ?? []).filter(
                      (p) => p.deal_id === deal.id
                    )}
                    onTrack={() => setTrackingDeal(deal)}
                  />
                ))}
              </div>
            </>
          )}

          {apps.length > 0 && (
            <>
              <p className="mt-6 text-[14px] font-extrabold">My applications</p>
              <div className="mt-2.5 space-y-3">
                {apps.map((app) => (
                  <div
                    key={app.id}
                    className="rounded-[20px] border border-border bg-card p-4"
                  >
                    <div className="flex items-start justify-between gap-2">
                      <div>
                        <p className="text-[14.5px] font-extrabold">
                          {app.brand_company ?? "Brand"}
                        </p>
                        <p className="text-[12.5px] text-muted-foreground">
                          Asked{" "}
                          {formatSponsorAmount(
                            app.desired_amount_cents,
                            app.desired_basis
                          )}
                        </p>
                      </div>
                      <StatusPill status={app.status} />
                    </div>
                    {app.status === "countered" &&
                      app.terms_amount_cents != null && (
                        <div className="mt-2.5 rounded-xl bg-indigo-500/5 p-3">
                          <p className="text-[13px] font-bold text-indigo-500">
                            Counter-offer:{" "}
                            {formatSponsorAmount(
                              app.terms_amount_cents,
                              app.terms_basis ?? app.desired_basis
                            )}
                            {app.terms_exclusive && " · exclusive"}
                          </p>
                          {app.terms_deliverables && (
                            <p className="mt-1 text-[12.5px] text-muted-foreground">
                              <span className="font-bold text-foreground">
                                Deliverables:
                              </span>{" "}
                              {app.terms_deliverables}
                            </p>
                          )}
                          {app.terms_notes && (
                            <p className="mt-1 text-[12.5px] text-muted-foreground">
                              {app.terms_notes}
                            </p>
                          )}
                          {app.terms_expires_at && (
                            <p className="mt-1 inline-flex items-center gap-1 text-[11.5px] font-bold text-amber-600">
                              <Clock className="h-3 w-3" />
                              Offer expires{" "}
                              {new Date(
                                app.terms_expires_at
                              ).toLocaleDateString("en-US", {
                                month: "short",
                                day: "numeric",
                              })}
                            </p>
                          )}
                          <div className="mt-2.5 grid grid-cols-2 gap-1.5">
                            <button
                              onClick={() =>
                                respond.mutate({ id: app.id, action: "accept" })
                              }
                              disabled={respond.isPending}
                              className="flex items-center justify-center gap-1 rounded-full bg-emerald-600 py-2 text-[12.5px] font-bold text-white disabled:opacity-40"
                            >
                              <CheckCircle2 className="h-3.5 w-3.5" /> Accept
                              terms
                            </button>
                            <button
                              onClick={() =>
                                respond.mutate({
                                  id: app.id,
                                  action: "withdraw",
                                })
                              }
                              disabled={respond.isPending}
                              className="rounded-full bg-red-500/10 py-2 text-[12.5px] font-bold text-red-500 disabled:opacity-40"
                            >
                              Decline
                            </button>
                          </div>
                        </div>
                      )}
                    {app.status === "pending" && (
                      <button
                        onClick={() =>
                          respond.mutate({ id: app.id, action: "withdraw" })
                        }
                        disabled={respond.isPending}
                        className="mt-2 text-[12px] font-bold text-red-500"
                      >
                        Withdraw
                      </button>
                    )}
                  </div>
                ))}
              </div>
            </>
          )}
        </>
      )}

      {trackingDeal && (
        <TrackPostModal
          deal={trackingDeal}
          onClose={() => setTrackingDeal(null)}
        />
      )}
    </div>
  );
}
