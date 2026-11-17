import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Banknote, Eye, Landmark, Loader2, Sparkles } from "lucide-react";
import { toast } from "sonner";

import { BankLinkSheet } from "@/components/BankLinkSheet";
import { fetchWppSummary, wppCashOut } from "@/lib/wpp";
import { formatCents } from "@/lib/coachPay";
import { businessNumber } from "@/lib/business";

/**
 * Whisper Paid Partners card — the creator's cut of REAL ad revenue.
 * Every month, 50% of actual ad spend becomes the creator pool; a
 * creator's month = min(views × tier RPM, their view-share of the pool).
 * Months finalize on the 1st; only closed months cash out (min $10)
 * through the same in-app Stripe rail as coaches.
 */
export function WppCard() {
  const queryClient = useQueryClient();
  const [linkingBank, setLinkingBank] = useState<boolean>(false);

  const summary = useQuery({
    queryKey: ["wpp-summary"],
    queryFn: fetchWppSummary,
    staleTime: 60_000,
  });

  const cashout = useMutation({
    mutationFn: wppCashOut,
    onSuccess: ({ amountCents, sentToBank }) => {
      toast.success(
        sentToBank
          ? `${formatCents(amountCents)} is on its way to your bank.`
          : `${formatCents(amountCents)} moved to your payout balance.`
      );
      void queryClient.invalidateQueries({ queryKey: ["wpp-summary"] });
    },
    onError: (err) =>
      toast.error(err instanceof Error ? err.message : "Cash out failed."),
  });

  const s = summary.data;
  const monthName = new Date().toLocaleDateString("en-US", { month: "long" });

  return (
    <div className="rounded-[22px] border border-border bg-card p-4">
      <div className="flex items-center gap-2.5">
        <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-br from-orange-500 to-amber-500 text-white">
          <Sparkles className="h-[18px] w-[18px]" />
        </div>
        <div className="min-w-0 flex-1">
          <p className="text-[14px] font-extrabold">Whisper Paid Partners</p>
          <p className="text-[11px] text-muted-foreground">
            Your share of real ad revenue — 50% of ad spend pays creators
          </p>
        </div>
        <span
          className={`shrink-0 rounded-full px-2.5 py-1 text-[10px] font-black uppercase tracking-wide ${
            s?.eligible
              ? "bg-orange-500/15 text-orange-500"
              : "bg-muted/70 text-muted-foreground"
          }`}
        >
          {s?.eligible ? (s.tierLabel ?? "Partner") : "Locked"}
        </span>
      </div>

      {summary.isPending ? (
        <div className="flex justify-center py-6">
          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
        </div>
      ) : !s ? null : !s.eligible ? (
        <div className="mt-3">
          <p className="text-[13px] leading-snug text-muted-foreground">
            WPP unlocks at{" "}
            <span className="font-bold text-foreground">1,000 followers</span>{" "}
            — you're at{" "}
            <span className="font-bold text-foreground">
              {businessNumber.format(s.followers)}
            </span>
            {s.nextTierFollowers
              ? ` (${businessNumber.format(Math.max(0, s.nextTierFollowers - s.followers))} to go)`
              : ""}
            . Then your qualified views earn a monthly share of the ad-revenue
            pool — half of every ad dollar goes to creators.
          </p>
          <div className="mt-2.5 h-2 overflow-hidden rounded-full bg-muted/70">
            <div
              className="h-full rounded-full bg-gradient-to-r from-orange-500 to-amber-400 transition-all"
              style={{
                width: `${Math.min(100, (s.followers / 1000) * 100)}%`,
              }}
            />
          </div>
        </div>
      ) : (
        <>
          <div className="mt-3 grid grid-cols-3 gap-2">
            <div className="rounded-xl bg-muted/50 px-2.5 py-2">
              <div className="flex items-center gap-1 text-muted-foreground">
                <Eye className="h-3 w-3" />
                <p className="text-[9.5px] font-bold uppercase tracking-wide">
                  Views · month
                </p>
              </div>
              <p className="text-[15px] font-extrabold tabular-nums">
                {businessNumber.format(s.monthViews)}
              </p>
            </div>
            <div className="rounded-xl bg-muted/50 px-2.5 py-2">
              <p className="text-[9.5px] font-bold uppercase tracking-wide text-muted-foreground">
                {monthName} · est.
              </p>
              <p className="text-[15px] font-extrabold tabular-nums">
                {formatCents(s.monthEstimatedCents)}
              </p>
            </div>
            <div className="rounded-xl bg-muted/50 px-2.5 py-2">
              <p className="text-[9.5px] font-bold uppercase tracking-wide text-muted-foreground">
                Cashable
              </p>
              <p className="text-[15px] font-extrabold tabular-nums text-orange-500">
                {formatCents(s.availableCents)}
              </p>
            </div>
          </div>

          <p className="mt-2 text-[10.5px] leading-snug text-muted-foreground">
            {monthName}'s creator pool so far:{" "}
            <span className="font-bold text-foreground">
              {formatCents(s.poolMonthCents)}
            </span>{" "}
            — funded by real ad spend. Your month finalizes on the 1st and
            becomes cashable.
          </p>

          <div className="mt-3">
            {!s.payoutsReady ? (
              <button
                onClick={() => setLinkingBank(true)}
                className="flex h-11 w-full items-center justify-center gap-2 rounded-full bg-foreground text-[13.5px] font-bold text-background transition-transform active:scale-[0.98]"
              >
                <Landmark className="h-4 w-4" />
                Link bank to get paid — stays in the app
              </button>
            ) : (
              <button
                onClick={() => cashout.mutate()}
                disabled={cashout.isPending || s.availableCents < 1000}
                className="flex h-11 w-full items-center justify-center gap-2 rounded-full bg-gradient-to-r from-orange-500 to-amber-500 text-[13.5px] font-bold text-white transition-transform active:scale-[0.98] disabled:opacity-40"
              >
                {cashout.isPending ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <Banknote className="h-4 w-4" />
                )}
                {s.availableCents >= 1000
                  ? `Cash out ${formatCents(s.availableCents)}`
                  : "Cash out (unlocks at $10)"}
              </button>
            )}
          </div>

          <p className="mt-2.5 text-[10.5px] leading-snug text-muted-foreground">
            Your tier caps at {formatCents(s.rpmCents)}/1k qualified views ·
            one view per person per post per day, never self-views · paid via
            Stripe
            {s.cashedOutCents > 0
              ? ` · ${formatCents(s.cashedOutCents)} paid out so far`
              : ""}
          </p>
        </>
      )}

      {linkingBank && (
        <BankLinkSheet
          onClose={() => setLinkingBank(false)}
          onDone={() => {
            setLinkingBank(false);
            void queryClient.invalidateQueries({ queryKey: ["wpp-summary"] });
            toast.success("Bank details saved.");
          }}
        />
      )}
    </div>
  );
}
