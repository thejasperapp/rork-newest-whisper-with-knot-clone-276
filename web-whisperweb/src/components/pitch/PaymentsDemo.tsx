import { useState } from "react";
import { usePitchReset, usePitchToast } from "@/components/pitch/PitchContext";
import {
  ArrowUpRight,
  CheckCircle2,
  Clock,
  Handshake,
  Landmark,
  Link2,
  Loader2,
  Lock,
  ShieldCheck,
  Wallet,
} from "lucide-react";

import {
  BASIS_SHORT,
  formatSponsorAmount,
  type SponsorPayment,
} from "@/lib/brands";
import {
  SAMPLE_BRAND_DEALS,
  SAMPLE_BRAND_PAYMENTS,
  SAMPLE_BRAND_POSTS,
  SAMPLE_CREATOR_EARNINGS,
  formatUsd,
  type SampleSponsorPayment,
} from "@/lib/pitch";
import { cn } from "@/lib/utils";

function fmt(c: number): string {
  return (c / 100).toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
  });
}

/**
 * Payments-in-account visualization for Pitch Mode. Mirrors the real
 * /sponsorships "Your earnings" card and the deal/payment ledger exactly:
 * the Wallet header, the two-up Pending-in-escrow / Paid-out stat tiles, the
 * bank-link prompt, and the per-deal cards with Pending / Released / Posts
 * tracked stats and the tracked-post reach row. All sample data so a prospect
 * sees precisely what their account looks like once deals are live.
 */
export function PaymentsDemo() {
  const [fundingingDeal, setFundingDeal] = useState<string | null>(null);
  const e = SAMPLE_CREATOR_EARNINGS;
  const showToast = usePitchToast();
  usePitchReset(() => setFundingDeal(null));

  return (
    <div className="space-y-4">
      {/* Earnings snapshot — verbatim from /sponsorships */}
      <div className="rounded-[20px] border border-border bg-card p-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <span className="flex h-8 w-8 items-center justify-center rounded-full bg-emerald-500/12">
              <Wallet className="h-4 w-4 text-emerald-600" />
            </span>
            <p className="text-[14px] font-extrabold">Your earnings</p>
          </div>
          <span className="text-[12px] font-bold text-indigo-500">
            Payouts & bank →
          </span>
        </div>
        <div className="mt-3 grid grid-cols-2 gap-2 text-center">
          <div className="rounded-xl bg-amber-500/8 py-2.5">
            <p className="text-[17px] font-black text-amber-600">
              {fmt(e.pendingCents)}
            </p>
            <p className="text-[11px] text-muted-foreground">In escrow for you</p>
          </div>
          <div className="rounded-xl bg-emerald-500/8 py-2.5">
            <p className="text-[17px] font-black text-emerald-600">
              {fmt(e.releasedCents)}
            </p>
            <p className="text-[11px] text-muted-foreground">Paid out to date</p>
          </div>
        </div>
        <p className="mt-2 flex items-center gap-1.5 text-[11.5px] leading-snug text-muted-foreground">
          <ShieldCheck className="h-3.5 w-3.5 shrink-0 text-emerald-600" />
          Your bank is linked — released funds transfer automatically to your
          Stripe balance.
        </p>
      </div>

      {/* Per-deal ledger — mirrors the real DealCard */}
      <p className="text-[14px] font-extrabold">Active deals</p>
      <div className="space-y-3">
        {SAMPLE_BRAND_DEALS.map((deal) => {
          const dealPayments = SAMPLE_BRAND_PAYMENTS.filter(
            (p) => p.deal_id === deal.id
          );
          const dealPosts = SAMPLE_BRAND_POSTS.filter(
            (p) => p.deal_id === deal.id
          );
          const pendingNet = dealPayments
            .filter((p) => p.status === "pending")
            .reduce((s, p) => s + p.net_cents, 0);
          const releasedNet = dealPayments
            .filter((p) => p.status === "released")
            .reduce((s, p) => s + p.net_cents, 0);
          const totalLikes = dealPosts.reduce((s, p) => s + (p.likes_count ?? 0), 0);
          const totalComments = dealPosts.reduce(
            (s, p) => s + (p.comments_count ?? 0),
            0
          );
          const isFunding = fundingingDeal === deal.id;
          return (
            <div
              key={deal.id}
              className="rounded-[20px] border border-border bg-card p-4"
            >
              <div className="flex items-start justify-between gap-2">
                <div>
                  <p className="text-[15px] font-extrabold">
                    {deal.brand_company ?? "Brand"}
                  </p>
                  <p className="text-[13px] font-bold text-indigo-500">
                    {formatSponsorAmount(deal.amount_cents, deal.basis)}
                  </p>
                </div>
                <span className="rounded-full bg-emerald-500/15 px-2.5 py-0.5 text-[11px] font-bold capitalize text-emerald-600">
                  {deal.status}
                </span>
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
                  <p className="text-[14px] font-black">{dealPosts.length}</p>
                  <p className="text-[11px] text-muted-foreground">Posts tracked</p>
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
                      <span className="font-bold text-foreground">
                        Deliverables:
                      </span>{" "}
                      {deal.deliverables}
                    </p>
                  )}
                </div>
              )}
              {dealPosts.length > 0 && (
                <div className="mt-2.5 flex items-center gap-3 rounded-xl bg-secondary/60 px-3 py-2">
                  <p className="text-[11.5px] font-bold">Verified reach</p>
                  <span className="inline-flex items-center gap-1 text-[11.5px] text-muted-foreground">
                    <Wallet className="h-3 w-3 text-emerald-600" />{" "}
                    {totalLikes.toLocaleString()} likes
                  </span>
                  <span className="inline-flex items-center gap-1 text-[11.5px] text-muted-foreground">
                    <Link2 className="h-3 w-3 text-indigo-500" />
                    {totalComments.toLocaleString()} comments
                  </span>
                </div>
              )}
              {dealPayments.filter((p) => p.status === "pending").length > 0 && (
                <div className="mt-2.5 space-y-1.5">
                  {dealPayments
                    .filter((p) => p.status === "pending")
                    .map((p) => (
                      <PaymentRow key={p.id} payment={p} />
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
                  onClick={() => {
                    setFundingDeal(deal.id);
                    showToast(`Funded ${deal.amount_cents / 100} into escrow for ${deal.brand_company ?? "brand"}`, "success");
                    setTimeout(() => setFundingDeal(null), 1200);
                  }}
                  className="mt-3 flex w-full items-center justify-center gap-2 rounded-full bg-emerald-600 py-2.5 text-[13px] font-bold text-white transition-transform active:scale-[0.98] disabled:opacity-40"
                  disabled={isFunding}
                >
                  {isFunding ? (
                    <Loader2 className="h-4 w-4 animate-spin" />
                  ) : (
                    <Lock className="h-3.5 w-3.5" />
                  )}
                  {isFunding
                    ? "Opening Stripe Checkout…"
                    : `Fund ${formatSponsorAmount(deal.amount_cents, deal.basis).split(" ")[0]} into escrow`}
                </button>
              )}
            </div>
          );
        })}
      </div>

      {/* Bank link prompt — mirrors the "Link your bank" banner */}
      <div className="flex items-start gap-2.5 rounded-[16px] border border-amber-500/30 bg-amber-500/5 p-3.5">
        <Landmark className="mt-0.5 h-4.5 w-4.5 shrink-0 text-amber-600" />
        <span className="text-[12.5px] leading-snug">
          <span className="font-bold">How the money reaches you.</span>{" "}
          <span className="text-muted-foreground">
            Sponsorship payments stay pending in escrow until your tracked post
            goes live, then release to your Stripe balance and transfer to your
            bank automatically — typically 1–2 business days.
          </span>
        </span>
      </div>

      <p className="text-center text-[11px] text-muted-foreground">
        Sample account for presentation · no real funds, no real Stripe checkout
      </p>
    </div>
  );
}

function PaymentRow({ payment }: { payment: SampleSponsorPayment }) {
  return (
    <div className="flex items-center justify-between rounded-xl border border-amber-500/25 bg-amber-500/5 px-3 py-2">
      <p className="text-[12px] font-bold text-amber-600">
        {fmt(payment.gross_cents)} in escrow
        {payment.requires_post ? " · awaiting post" : ""}
      </p>
      <span className="inline-flex items-center gap-1 text-[11px] font-bold text-muted-foreground">
        <Clock className="h-3 w-3" />
        {payment.hold_until
          ? `releases ${new Date(payment.hold_until).toLocaleDateString("en-US", { month: "short", day: "numeric" })}`
          : "on post"}
      </span>
    </div>
  );
}
