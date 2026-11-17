import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ArrowLeft,
  Briefcase,
  CheckCircle2,
  Heart,
  Loader2,
  Lock,
  MessageCircle,
  Pencil,
  ShieldAlert,
  ShieldX,
  Undo2,
} from "lucide-react";
import { toast } from "sonner";

import { useAuth } from "@/hooks/useAuth";
import {
  BASIS_LABELS,
  disputePayment,
  fetchApplications,
  fetchBrand,
  fetchDeals,
  formatSponsorAmount,
  fundDeal,
  respondToApplication,
  type SponsorApplication,
  type SponsorBasis,
  type SponsorDeal,
  type SponsorPayment,
  type SponsorPost,
} from "@/lib/brands";

const BASES: SponsorBasis[] = ["per_post", "per_month", "per_year"];

function StatusPill({ status }: { status: string }) {
  const styles: Record<string, string> = {
    pending: "bg-amber-500/15 text-amber-600",
    countered: "bg-indigo-500/15 text-indigo-500",
    accepted: "bg-emerald-500/15 text-emerald-600",
    active: "bg-emerald-500/15 text-emerald-600",
    released: "bg-emerald-500/15 text-emerald-600",
    denied: "bg-red-500/15 text-red-500",
    withdrawn: "bg-muted text-muted-foreground",
  };
  const labels: Record<string, string> = {
    countered: "New terms",
    released: "Released",
  };
  return (
    <span
      className={`rounded-full px-2.5 py-0.5 text-[11px] font-bold capitalize ${styles[status] ?? "bg-muted text-muted-foreground"}`}
    >
      {labels[status] ?? status}
    </span>
  );
}

/**
 * One incoming application with the brand's editable terms form —
 * accept as-is, counter with edited terms, or deny (deny = DM block).
 */
function ApplicationCard({ app }: { app: SponsorApplication }) {
  const queryClient = useQueryClient();
  const [basis, setBasis] = useState<SponsorBasis>(
    app.terms_basis ?? app.desired_basis
  );
  const [amount, setAmount] = useState<string>(
    String((app.terms_amount_cents ?? app.desired_amount_cents) / 100)
  );
  const [notes, setNotes] = useState<string>(app.terms_notes ?? "");
  const [deliverables, setDeliverables] = useState<string>(
    app.terms_deliverables ?? ""
  );
  const [exclusive, setExclusive] = useState<boolean>(
    app.terms_exclusive === true
  );
  const [expiresInDays, setExpiresInDays] = useState<number>(0);

  const respond = useMutation({
    mutationFn: async (action: "accept" | "deny" | "counter") => {
      if (action === "deny") {
        await respondToApplication({ id: app.id, action });
        return action;
      }
      const dollars = Number(amount.replace(/[^0-9.]/g, ""));
      if (!Number.isFinite(dollars) || dollars < 1) {
        throw new Error("Enter a valid amount.");
      }
      await respondToApplication({
        id: app.id,
        action,
        termsBasis: basis,
        termsAmountCents: Math.round(dollars * 100),
        termsNotes: notes.trim(),
        termsDeliverables: deliverables.trim(),
        termsExclusive: exclusive,
        ...(action === "counter" && expiresInDays > 0
          ? { expiresInDays }
          : {}),
      });
      return action;
    },
    onSuccess: (action) => {
      toast.success(
        action === "accept"
          ? "Deal created — fund it from the Deals section."
          : action === "counter"
            ? "Counter-offer sent."
            : "Application denied — this brand can no longer DM the creator."
      );
      queryClient.invalidateQueries({ queryKey: ["sponsorship-applications"] });
      queryClient.invalidateQueries({ queryKey: ["sponsorship-deals"] });
    },
    onError: (err) =>
      toast.error(err instanceof Error ? err.message : "Couldn't respond."),
  });

  return (
    <div className="rounded-[20px] border border-border bg-card p-4">
      <div className="flex items-start justify-between gap-2">
        <div>
          <p className="text-[15px] font-extrabold">
            @{app.creator_username ?? "creator"}
          </p>
          <p className="text-[12.5px] text-muted-foreground">
            {app.creator_followers != null &&
              `${app.creator_followers.toLocaleString()} followers`}
            {app.creator_age != null && ` · ${app.creator_age} yrs`}
          </p>
          <p className="mt-1 text-[13px] font-bold text-indigo-500">
            Asking {formatSponsorAmount(app.desired_amount_cents, app.desired_basis)}
          </p>
        </div>
        <StatusPill status={app.status} />
      </div>

      {app.message && (
        <p className="mt-2 rounded-xl bg-secondary/60 p-3 text-[13px] leading-snug text-muted-foreground">
          {app.message}
        </p>
      )}

      <p className="mt-3.5 text-[12px] font-bold uppercase tracking-wide text-muted-foreground">
        Terms (edit to counter)
      </p>
      <div className="mt-1.5 grid grid-cols-3 gap-1.5">
        {BASES.map((b) => (
          <button
            key={b}
            onClick={() => setBasis(b)}
            className={`rounded-full px-2 py-1.5 text-[12px] font-bold transition-colors ${
              basis === b
                ? "bg-indigo-500 text-white"
                : "bg-secondary text-muted-foreground"
            }`}
          >
            {BASIS_LABELS[b]}
          </button>
        ))}
      </div>
      <div className="mt-2 flex items-center rounded-xl border border-border bg-background px-3.5">
        <span className="text-[14px] font-semibold text-muted-foreground">$</span>
        <input
          inputMode="decimal"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          className="w-full bg-transparent px-2 py-2.5 text-[14.5px] outline-none"
        />
      </div>
      <textarea
        value={deliverables}
        onChange={(e) => setDeliverables(e.target.value)}
        placeholder="Deliverables brief — e.g. 2 feed posts + 1 story, product visible, tag @yourbrand…"
        rows={2}
        className="mt-2 w-full resize-none rounded-xl border border-border bg-background px-3.5 py-2.5 text-[13.5px] outline-none placeholder:text-muted-foreground/60"
      />
      <textarea
        value={notes}
        onChange={(e) => setNotes(e.target.value)}
        placeholder="Other notes — timelines, usage rights…"
        rows={2}
        className="mt-2 w-full resize-none rounded-xl border border-border bg-background px-3.5 py-2.5 text-[13.5px] outline-none placeholder:text-muted-foreground/60"
      />
      <div className="mt-2 flex flex-wrap items-center gap-2">
        <button
          onClick={() => setExclusive((v) => !v)}
          className={`rounded-full border px-3 py-1.5 text-[12px] font-bold transition-colors ${
            exclusive
              ? "border-indigo-500/50 bg-indigo-500/10 text-indigo-500"
              : "border-border text-muted-foreground"
          }`}
        >
          {exclusive ? "✓ " : ""}Exclusivity clause
        </button>
        <select
          value={expiresInDays}
          onChange={(e) => setExpiresInDays(Number(e.target.value))}
          className="rounded-full border border-border bg-background px-3 py-1.5 text-[12px] font-bold text-muted-foreground outline-none"
          aria-label="Counter-offer deadline"
        >
          <option value={0}>No offer deadline</option>
          <option value={3}>Counter expires in 3 days</option>
          <option value={7}>Counter expires in 7 days</option>
          <option value={14}>Counter expires in 14 days</option>
        </select>
      </div>

      <div className="mt-3 grid grid-cols-3 gap-1.5">
        <button
          onClick={() => respond.mutate("accept")}
          disabled={respond.isPending}
          className="flex items-center justify-center gap-1 rounded-full bg-emerald-600 py-2.5 text-[12.5px] font-bold text-white transition-transform active:scale-[0.97] disabled:opacity-40"
        >
          <CheckCircle2 className="h-3.5 w-3.5" /> Accept
        </button>
        <button
          onClick={() => respond.mutate("counter")}
          disabled={respond.isPending}
          className="flex items-center justify-center gap-1 rounded-full bg-indigo-500 py-2.5 text-[12.5px] font-bold text-white transition-transform active:scale-[0.97] disabled:opacity-40"
        >
          <Undo2 className="h-3.5 w-3.5" /> Counter
        </button>
        <button
          onClick={() => {
            if (
              window.confirm(
                "Deny this application? Your brand will no longer be able to DM this creator."
              )
            ) {
              respond.mutate("deny");
            }
          }}
          disabled={respond.isPending}
          className="flex items-center justify-center gap-1 rounded-full bg-red-500/10 py-2.5 text-[12.5px] font-bold text-red-500 transition-transform active:scale-[0.97] disabled:opacity-40"
        >
          <ShieldX className="h-3.5 w-3.5" /> Deny
        </button>
      </div>
    </div>
  );
}

function DealCard({
  deal,
  payments,
  posts,
}: {
  deal: SponsorDeal;
  payments: SponsorPayment[];
  posts: SponsorPost[];
}) {
  const queryClient = useQueryClient();
  const [funding, setFunding] = useState<boolean>(false);
  const pending = payments.filter((p) => p.status === "pending");
  const released = payments.filter((p) => p.status === "released");
  const totalLikes = posts.reduce((s, p) => s + (p.likes_count ?? 0), 0);
  const totalComments = posts.reduce((s, p) => s + (p.comments_count ?? 0), 0);
  const fmt = (c: number) =>
    (c / 100).toLocaleString("en-US", { style: "currency", currency: "USD" });

  const dispute = useMutation({
    mutationFn: (paymentId: string) => {
      const reason = window.prompt(
        "Why are you disputing this payment? The escrowed money will be refunded to you.",
        "Deliverables were not met"
      );
      if (reason === null) return Promise.reject(new Error("cancelled"));
      return disputePayment({ paymentId, reason });
    },
    onSuccess: () => {
      toast.success("Payment disputed — the escrowed funds are being refunded.");
      queryClient.invalidateQueries({ queryKey: ["sponsorship-deals"] });
    },
    onError: (err) => {
      if (err instanceof Error && err.message === "cancelled") return;
      toast.error(err instanceof Error ? err.message : "Couldn't dispute.");
    },
  });

  const startFund = async (): Promise<void> => {
    setFunding(true);
    try {
      await fundDeal(deal.id);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Couldn't start checkout.");
      setFunding(false);
    }
  };

  return (
    <div className="rounded-[20px] border border-border bg-card p-4">
      <div className="flex items-start justify-between gap-2">
        <div>
          <p className="text-[15px] font-extrabold">
            @{deal.creator_username ?? "creator"}
          </p>
          <p className="text-[13px] font-bold text-indigo-500">
            {formatSponsorAmount(deal.amount_cents, deal.basis)}
          </p>
        </div>
        <StatusPill status={deal.status} />
      </div>

      <div className="mt-3 grid grid-cols-3 gap-2 text-center">
        <div className="rounded-xl bg-secondary/60 py-2">
          <p className="text-[15px] font-black text-amber-600">{pending.length}</p>
          <p className="text-[11px] text-muted-foreground">In escrow</p>
        </div>
        <div className="rounded-xl bg-secondary/60 py-2">
          <p className="text-[15px] font-black text-emerald-600">
            {released.length}
          </p>
          <p className="text-[11px] text-muted-foreground">Released</p>
        </div>
        <div className="rounded-xl bg-secondary/60 py-2">
          <p className="text-[15px] font-black">{posts.length}</p>
          <p className="text-[11px] text-muted-foreground">Posts live</p>
        </div>
      </div>

      {(deal.deliverables || deal.exclusive) && (
        <div className="mt-2.5 rounded-xl bg-secondary/60 p-3">
          {deal.exclusive && (
            <p className="text-[11.5px] font-bold text-indigo-500">
              Exclusive partnership
            </p>
          )}
          {deal.deliverables && (
            <p className="text-[12px] leading-snug text-muted-foreground">
              <span className="font-bold text-foreground">Deliverables:</span>{" "}
              {deal.deliverables}
            </p>
          )}
        </div>
      )}

      {posts.length > 0 && (
        <div className="mt-2.5 flex items-center gap-3 rounded-xl bg-secondary/60 px-3 py-2">
          <p className="text-[11.5px] font-bold">Verified reach</p>
          <span className="inline-flex items-center gap-1 text-[11.5px] text-muted-foreground">
            <Heart className="h-3 w-3 text-red-500" /> {totalLikes.toLocaleString()}
          </span>
          <span className="inline-flex items-center gap-1 text-[11.5px] text-muted-foreground">
            <MessageCircle className="h-3 w-3 text-indigo-500" />{" "}
            {totalComments.toLocaleString()}
          </span>
        </div>
      )}

      {pending.length > 0 && (
        <div className="mt-2.5 space-y-1.5">
          {pending.map((p) => (
            <div
              key={p.id}
              className="flex items-center justify-between rounded-xl border border-amber-500/25 bg-amber-500/5 px-3 py-2"
            >
              <p className="text-[12px] font-bold text-amber-600">
                {fmt(p.gross_cents)} in escrow
                {p.requires_post ? " · awaiting post" : ""}
              </p>
              <button
                onClick={() => dispute.mutate(p.id)}
                disabled={dispute.isPending}
                className="inline-flex items-center gap-1 rounded-full bg-red-500/10 px-2.5 py-1 text-[11px] font-bold text-red-500 disabled:opacity-40"
              >
                <ShieldAlert className="h-3 w-3" /> Dispute & refund
              </button>
            </div>
          ))}
        </div>
      )}

      <p className="mt-2.5 text-[11.5px] leading-snug text-muted-foreground">
        {deal.basis === "per_post"
          ? "Funds are held by Whisper and release to the creator as each sponsored post goes live."
          : "Funds are held by Whisper and release at the end of the week once the creator's posts are verified."}
      </p>

      {deal.status === "active" && (
        <button
          onClick={() => void startFund()}
          disabled={funding}
          className="mt-3 flex w-full items-center justify-center gap-2 rounded-full bg-emerald-600 py-2.5 text-[13px] font-bold text-white transition-transform active:scale-[0.98] disabled:opacity-40"
        >
          {funding ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : (
            <Lock className="h-3.5 w-3.5" />
          )}
          Fund {formatSponsorAmount(deal.amount_cents, deal.basis).split(" ")[0]}{" "}
          into escrow
        </button>
      )}
    </div>
  );
}

/**
 * Brand dashboard — incoming sponsorship applications (accept / counter
 * with editable terms / deny), and active deals with escrow funding.
 */
export default function BrandDashboard({ embedded = false }: { embedded?: boolean }) {
  const navigate = useNavigate();
  const { user } = useAuth();

  const brandQuery = useQuery({
    queryKey: ["brand", user?.id ?? ""],
    queryFn: () => fetchBrand(user!.id),
    enabled: !!user?.id,
  });

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

  const apps = appsQuery.data?.asBrand ?? [];
  const open = apps.filter((a) => ["pending", "countered"].includes(a.status));
  const decided = apps.filter(
    (a) => !["pending", "countered"].includes(a.status)
  );
  const myDeals = (dealsQuery.data?.deals ?? []).filter(
    (d) => d.brand_user_id === user?.id
  );

  // Campaign analytics — the numbers a brand needs to judge ROI at a glance.
  const myDealIds = new Set(myDeals.map((d) => d.id));
  const trackedPosts = (dealsQuery.data?.posts ?? []).filter((p) =>
    myDealIds.has(p.deal_id)
  );
  const accepted = apps.filter((a) =>
    ["accepted", "active"].includes(a.status)
  ).length;
  const acceptRate =
    apps.length > 0 ? Math.round((accepted / apps.length) * 100) : null;
  const postEngagement = trackedPosts.reduce(
    (n, p) => n + (p.likes_count ?? 0) + (p.comments_count ?? 0),
    0
  );
  const escrowedCents = (dealsQuery.data?.payments ?? [])
    .filter((p) => myDealIds.has(p.deal_id) && p.status === "pending")
    .reduce((n, p) => n + p.gross_cents, 0);

  if (brandQuery.isSuccess && !brandQuery.data) {
    return (
      <div className="mx-auto w-full max-w-xl px-4 py-16 text-center">
        <Briefcase className="mx-auto h-8 w-8 text-muted-foreground" />
        <p className="mt-3 text-[15px] font-bold">You don't have a brand profile yet</p>
        <Link
          to="/brand/signup"
          className="mt-4 inline-block rounded-full bg-indigo-500 px-5 py-2.5 text-[13.5px] font-bold text-white"
        >
          Create your brand profile
        </Link>
      </div>
    );
  }

  return (
    <div className="mx-auto w-full max-w-xl px-4 pb-24 pt-3">
      {!embedded && <button
        onClick={() => navigate(-1)}
        className="mb-3 inline-flex items-center gap-1.5 text-[13.5px] font-bold text-muted-foreground"
      >
        <ArrowLeft className="h-4 w-4" /> Back
      </button>}

      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-[20px] font-black">
            {brandQuery.data?.company_name ?? "Brand"} dashboard
          </h1>
          <p className="text-[13px] text-muted-foreground">
            Applications, deals, and escrow payments.
          </p>
        </div>
        <Link
          to="/brand/signup"
          className="flex h-10 w-10 items-center justify-center rounded-full border border-border bg-card"
          aria-label="Edit brand profile"
        >
          <Pencil className="h-4 w-4" />
        </Link>
      </div>

      {appsQuery.isLoading || dealsQuery.isLoading ? (
        <div className="flex justify-center py-16">
          <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
        </div>
      ) : (
        <>
          {/* Campaign performance at a glance */}
          <div className="mt-5 grid grid-cols-2 gap-2 sm:grid-cols-4">
            {[
              { label: "Applications", value: String(apps.length) },
              {
                label: "Accept rate",
                value: acceptRate === null ? "—" : `${acceptRate}%`,
              },
              {
                label: "Tracked posts",
                value: `${trackedPosts.length}${postEngagement > 0 ? ` · ${postEngagement} eng.` : ""}`,
              },
              {
                label: "In escrow",
                value: `$${(escrowedCents / 100).toLocaleString()}`,
              },
            ].map((stat) => (
              <div
                key={stat.label}
                className="rounded-[16px] border border-border bg-card px-3 py-2.5"
              >
                <p className="text-[15px] font-black tabular-nums">{stat.value}</p>
                <p className="text-[11px] font-semibold text-muted-foreground">
                  {stat.label}
                </p>
              </div>
            ))}
          </div>

          <p className="mt-6 text-[14px] font-extrabold">
            Applications{" "}
            <span className="ml-1 rounded-full bg-indigo-500 px-2 py-0.5 text-[11px] font-bold text-white">
              {open.length}
            </span>
          </p>
          <div className="mt-2.5 space-y-3">
            {open.length === 0 ? (
              <p className="rounded-[16px] border border-border bg-card p-4 text-[13px] text-muted-foreground">
                No open applications. Creators who meet your requirements can
                apply from your brand profile.
              </p>
            ) : (
              open.map((app) => <ApplicationCard key={app.id} app={app} />)
            )}
          </div>

          <p className="mt-6 text-[14px] font-extrabold">
            Deals{" "}
            <span className="ml-1 rounded-full bg-emerald-600 px-2 py-0.5 text-[11px] font-bold text-white">
              {myDeals.length}
            </span>
          </p>
          <div className="mt-2.5 space-y-3">
            {myDeals.length === 0 ? (
              <p className="rounded-[16px] border border-border bg-card p-4 text-[13px] text-muted-foreground">
                Accepted applications become deals here — fund them into escrow
                and watch tracked posts land.
              </p>
            ) : (
              myDeals.map((deal) => (
                <DealCard
                  key={deal.id}
                  deal={deal}
                  payments={(dealsQuery.data?.payments ?? []).filter(
                    (p) => p.deal_id === deal.id
                  )}
                  posts={(dealsQuery.data?.posts ?? []).filter(
                    (p) => p.deal_id === deal.id
                  )}
                />
              ))
            )}
          </div>

          {decided.length > 0 && (
            <>
              <p className="mt-6 text-[14px] font-extrabold">History</p>
              <div className="mt-2.5 space-y-2">
                {decided.map((app) => (
                  <div
                    key={app.id}
                    className="flex items-center justify-between rounded-[14px] border border-border bg-card px-4 py-2.5"
                  >
                    <p className="text-[13px] font-semibold">
                      @{app.creator_username ?? "creator"}
                    </p>
                    <StatusPill status={app.status} />
                  </div>
                ))}
              </div>
            </>
          )}
        </>
      )}
    </div>
  );
}
