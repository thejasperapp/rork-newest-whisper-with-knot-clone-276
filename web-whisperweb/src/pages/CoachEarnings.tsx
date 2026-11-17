import { useEffect, useMemo, useRef, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ArrowDownLeft,
  ArrowLeft,
  BadgeCheck,
  Banknote,
  Check,
  CircleAlert,
  Copy,
  DollarSign,
  Landmark,
  Loader2,
  ReceiptText,
  TrendingUp,
  Wallet,
} from "lucide-react";
import { toast } from "sonner";

import { BankLinkSheet } from "@/components/BankLinkSheet";
import { Header } from "@/components/Header";
import { useAuth } from "@/hooks/useAuth";
import { cn } from "@/lib/utils";
import { fetchRoleState } from "@/lib/applications";
import {
  cashOut,
  fetchCoachEarnings,
  fetchStripeOverview,
  formatCents,
  saveCoachRate,
  startBankOnboarding,
  type StripeOverview,
} from "@/lib/coachPay";
import { CoachTierManager } from "@/components/CoachTierManager";
import { siteUrl } from "@/lib/site";

/** rAF count-up with an ease-out cubic — money that rolls into place. */
function useCountUp(target: number, durationMs = 950): number {
  const [value, setValue] = useState<number>(0);
  const currentRef = useRef<number>(0);

  useEffect(() => {
    if (typeof window === "undefined") return;
    const reduced = window.matchMedia?.(
      "(prefers-reduced-motion: reduce)"
    )?.matches;
    if (reduced) {
      currentRef.current = target;
      setValue(target);
      return;
    }
    const from = currentRef.current;
    if (from === target) return;
    const start = performance.now();
    let raf = 0;
    const tick = (now: number): void => {
      const t = Math.min(1, (now - start) / durationMs);
      const eased = 1 - Math.pow(1 - t, 3);
      const next = Math.round(from + (target - from) * eased);
      currentRef.current = next;
      setValue(next);
      if (t < 1) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [target, durationMs]);

  return value;
}

/** Animated money readout — counts to the new amount whenever it changes. */
function Money({
  cents,
  className,
}: {
  cents: number;
  className?: string;
}) {
  const animated = useCountUp(cents);
  return (
    <span className={cn("tabular-nums", className)}>
      {formatCents(animated)}
    </span>
  );
}

function CardShell({
  children,
  className,
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <div
      className={cn(
        "hover-lift rounded-[22px] border border-border bg-card p-5 shadow-sm",
        className
      )}
    >
      {children}
    </div>
  );
}

function SectionTitle({
  icon,
  title,
  right,
}: {
  icon: React.ReactNode;
  title: string;
  right?: React.ReactNode;
}) {
  return (
    <div className="flex items-center gap-2.5">
      <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-orange-500/12 text-orange-500">
        {icon}
      </span>
      <p className="text-[15px] font-bold">{title}</p>
      {right && <span className="ml-auto">{right}</span>}
    </div>
  );
}

function StatusPill({ ok, label }: { ok: boolean; label: string }) {
  return (
    <span
      className={cn(
        "flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[10.5px] font-bold",
        ok
          ? "bg-emerald-500/12 text-emerald-600"
          : "bg-amber-500/15 text-amber-600"
      )}
    >
      <span
        className={cn(
          "earn-live-dot h-1.5 w-1.5 rounded-full",
          ok ? "bg-emerald-500" : "bg-amber-500"
        )}
      />
      {label}
    </span>
  );
}

/** The dark wallet hero — balance count-up, pending/all-time chips, cash out. */
function WalletHero({
  availableCents,
  pendingCents,
  totalEarnedCents,
  connected,
  payoutsReady,
  loading,
  onCashOut,
  cashingOut,
}: {
  availableCents: number;
  pendingCents: number;
  totalEarnedCents: number;
  connected: boolean;
  payoutsReady: boolean;
  loading: boolean;
  onCashOut: () => void;
  cashingOut: boolean;
}) {
  const canCashOut = payoutsReady && availableCents >= 100 && !cashingOut;
  return (
    <div className="relative overflow-hidden rounded-[28px] border border-white/10 bg-zinc-950 p-6 text-white sm:p-7">
      {/* Static ember blooms — atmosphere, no rotation. */}
      <div
        aria-hidden
        className="pointer-events-none absolute -left-24 -top-28 h-72 w-72 rounded-full opacity-25 blur-3xl"
        style={{
          background:
            "radial-gradient(closest-side, rgba(249,115,22,0.85), transparent)",
        }}
      />
      <div
        aria-hidden
        className="pointer-events-none absolute -bottom-32 -right-20 h-80 w-80 rounded-full opacity-15 blur-3xl"
        style={{
          background:
            "radial-gradient(closest-side, rgba(251,191,36,0.8), transparent)",
        }}
      />

      <div className="relative">
        <div className="flex items-center justify-between">
          <p className="text-[10.5px] font-black uppercase tracking-[0.22em] text-white/60">
            Your balance
          </p>
          {connected && (
            <span className="flex items-center gap-1.5 rounded-full border border-white/12 bg-white/8 px-2.5 py-1 text-[10px] font-bold uppercase tracking-wide text-white/80">
              <span className="earn-live-dot h-1.5 w-1.5 rounded-full bg-emerald-400" />
              Live · Stripe
            </span>
          )}
        </div>

        <p
          className={cn(
            "mt-2.5 font-display text-[46px] font-extrabold leading-none sm:text-[54px]",
            loading && "animate-pulse text-white/70"
          )}
        >
          <Money cents={availableCents} />
        </p>

        <div className="mt-4 flex flex-wrap items-center gap-2">
          <span className="flex items-center gap-1.5 rounded-full border border-white/10 bg-white/8 px-3 py-1.5 text-[12px] font-semibold text-white/85">
            <span className="h-1.5 w-1.5 rounded-full bg-amber-400" />
            Pending <Money cents={pendingCents} />
          </span>
          <span className="flex items-center gap-1.5 rounded-full border border-white/10 bg-white/8 px-3 py-1.5 text-[12px] font-semibold text-white/85">
            <TrendingUp className="h-3.5 w-3.5 text-emerald-400" />
            All-time <Money cents={totalEarnedCents} />
          </span>
        </div>

        <button
          onClick={onCashOut}
          disabled={!canCashOut}
          className={cn(
            "mt-6 flex h-[52px] w-full items-center justify-center gap-2 rounded-full bg-gradient-to-r from-orange-500 to-amber-500 text-[15px] font-bold text-white shadow-lg shadow-orange-500/25 transition-all active:scale-[0.98] disabled:opacity-40 disabled:shadow-none",
            canCashOut && "earn-shine"
          )}
        >
          {cashingOut ? (
            <Loader2 className="h-4.5 w-4.5 animate-spin" />
          ) : (
            <Banknote className="h-4.5 w-4.5" />
          )}
          Cash out to bank
        </button>
        {!payoutsReady && (
          <p className="mt-2.5 text-center text-[12.5px] text-white/60">
            Link your bank below to enable cash outs.
          </p>
        )}
      </div>
    </div>
  );
}

/** Compact stat tiles under the hero — this month, payments, lifetime. */
function SnapshotRow({
  monthCents,
  monthCount,
  totalEarnedCents,
}: {
  monthCents: number;
  monthCount: number;
  totalEarnedCents: number;
}) {
  const monthCountUp = useCountUp(monthCount, 700);
  return (
    <div className="grid grid-cols-3 gap-2.5">
      <div className="hover-lift rounded-2xl border border-border bg-card p-3.5">
        <TrendingUp className="h-4 w-4 text-orange-500" />
        <p className="mt-2 text-[16px] font-extrabold leading-none">
          <Money cents={monthCents} />
        </p>
        <p className="mt-1 text-[10.5px] font-bold uppercase tracking-wide text-muted-foreground">
          This month
        </p>
      </div>
      <div className="hover-lift rounded-2xl border border-border bg-card p-3.5">
        <ReceiptText className="h-4 w-4 text-orange-500" />
        <p className="mt-2 text-[16px] font-extrabold leading-none tabular-nums">
          {monthCountUp}
        </p>
        <p className="mt-1 text-[10.5px] font-bold uppercase tracking-wide text-muted-foreground">
          Payments · month
        </p>
      </div>
      <div className="hover-lift rounded-2xl border border-border bg-card p-3.5">
        <Wallet className="h-4 w-4 text-orange-500" />
        <p className="mt-2 text-[16px] font-extrabold leading-none">
          <Money cents={totalEarnedCents} />
        </p>
        <p className="mt-1 text-[10.5px] font-bold uppercase tracking-wide text-muted-foreground">
          Lifetime
        </p>
      </div>
    </div>
  );
}

/**
 * Banking & payouts — bank on file, Stripe standing, live balance at Stripe,
 * requirements, and the in-app update button. Everything the Stripe
 * dashboard would show, styled like Whisper.
 */
function BankingCard({
  connected,
  payoutsReady,
  overview,
  overviewPending,
  redirecting,
  onOnboard,
}: {
  connected: boolean;
  payoutsReady: boolean;
  overview: StripeOverview | null | undefined;
  overviewPending: boolean;
  redirecting: boolean;
  onOnboard: () => void;
}) {
  const o = overview;
  return (
    <CardShell>
      <SectionTitle
        icon={<Landmark className="h-4.5 w-4.5" />}
        title="Banking & payouts"
        right={
          connected && payoutsReady ? (
            <span className="flex items-center gap-1 rounded-full bg-emerald-500 px-2.5 py-1 text-[10px] font-bold uppercase tracking-wide text-white">
              <BadgeCheck className="h-3 w-3" /> Linked
            </span>
          ) : (
            <span className="rounded-full bg-amber-500/15 px-2.5 py-1 text-[10px] font-bold uppercase tracking-wide text-amber-600">
              Not linked
            </span>
          )
        }
      />

      {!connected ? (
        <>
          <p className="mt-3 text-[13.5px] leading-relaxed text-muted-foreground">
            Payouts are handled securely by Stripe. Link your bank once —
            everything happens inside Whisper, and cash outs arrive in 1–2
            business days.
          </p>
          <button
            onClick={onOnboard}
            disabled={redirecting}
            className="earn-shine mt-4 flex h-12 w-full items-center justify-center gap-2 rounded-full bg-gradient-to-r from-orange-500 to-amber-500 text-[14px] font-bold text-white shadow-md shadow-orange-500/20 transition-transform active:scale-[0.98] disabled:opacity-50"
          >
            {redirecting && <Loader2 className="h-4 w-4 animate-spin" />}
            Link bank account — stays in the app
          </button>
        </>
      ) : overviewPending ? (
        <div className="mt-4 space-y-2.5">
          <div className="h-9 animate-pulse rounded-xl bg-secondary/70" />
          <div className="h-14 animate-pulse rounded-xl bg-secondary/50" />
          <div className="h-14 animate-pulse rounded-xl bg-secondary/40" />
        </div>
      ) : (
        <div className="mt-4 space-y-4">
          <div className="flex flex-wrap gap-1.5">
            <StatusPill ok={o?.chargesEnabled === true} label="Charges" />
            <StatusPill ok={o?.payoutsEnabled === true} label="Payouts" />
            <StatusPill ok={o?.detailsSubmitted === true} label="Details" />
          </div>

          {(o?.requirementsDue?.length ?? 0) > 0 && (
            <div className="rounded-2xl border border-amber-500/40 bg-amber-500/10 p-4">
              <p className="text-[13px] font-bold">Stripe still needs:</p>
              <ul className="mt-1.5 list-disc pl-5 text-[12.5px] leading-relaxed text-muted-foreground">
                {(o?.requirementsDue ?? []).slice(0, 6).map((r) => (
                  <li key={r}>{r}</li>
                ))}
              </ul>
              <button
                onClick={onOnboard}
                disabled={redirecting}
                className="mt-3 flex h-9 items-center gap-2 rounded-full bg-foreground px-4 text-[12.5px] font-bold text-background transition-transform active:scale-[0.97] disabled:opacity-50"
              >
                {redirecting && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
                Finish setup — stays in the app
              </button>
            </div>
          )}

          <div className="grid grid-cols-2 gap-2.5">
            <div className="rounded-2xl bg-secondary/50 px-4 py-3.5">
              <p className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">
                At Stripe · available
              </p>
              <p className="mt-1 text-[18px] font-extrabold leading-none">
                <Money cents={o?.balance?.availableCents ?? 0} />
              </p>
            </div>
            <div className="rounded-2xl bg-secondary/50 px-4 py-3.5">
              <p className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">
                On the way · pending
              </p>
              <p className="mt-1 text-[18px] font-extrabold leading-none">
                <Money cents={o?.balance?.pendingCents ?? 0} />
              </p>
            </div>
          </div>

          <div className="flex items-center gap-3 rounded-2xl border border-border px-4 py-3.5">
            <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-secondary">
              <Landmark className="h-4.5 w-4.5 text-muted-foreground" />
            </span>
            <div className="min-w-0 flex-1">
              <p className="truncate text-[13.5px] font-bold">
                {o?.bank
                  ? `${o.bank.bankName} ····${o.bank.last4}`
                  : "No bank on file yet"}
              </p>
              <p className="text-[11.5px] text-muted-foreground">
                Payouts run {o?.payoutSchedule?.interval ?? "daily"} · ~
                {o?.payoutSchedule?.delayDays ?? 2}-day rolling
              </p>
            </div>
            {o?.bank && (
              <span className="shrink-0 rounded-full bg-secondary px-2 py-0.5 text-[10px] font-bold uppercase text-muted-foreground">
                {o.bank.currency}
              </span>
            )}
          </div>

          <button
            onClick={onOnboard}
            disabled={redirecting}
            className="flex h-11 w-full items-center justify-center gap-2 rounded-full border border-border bg-background text-[13.5px] font-bold transition-colors hover:bg-secondary/50 active:scale-[0.99] disabled:opacity-50"
          >
            {redirecting && <Loader2 className="h-4 w-4 animate-spin" />}
            Update bank details — stays in the app
          </button>
        </div>
      )}
    </CardShell>
  );
}

const payoutDotColor = (status: string): string =>
  status === "paid"
    ? "bg-emerald-500"
    : status === "failed" || status === "canceled"
      ? "bg-red-500"
      : "bg-amber-500";

const payoutChipColor = (status: string): string =>
  status === "paid"
    ? "bg-emerald-500/12 text-emerald-600"
    : status === "failed" || status === "canceled"
      ? "bg-red-500/12 text-red-500"
      : "bg-amber-500/15 text-amber-600";

const shortDate = (iso: string | null): string =>
  iso
    ? new Date(iso).toLocaleDateString("en-US", {
        month: "short",
        day: "numeric",
      })
    : "";

/** Payout timeline + incoming transfers — the money's movement, visualized. */
function ActivityCard({ overview }: { overview: StripeOverview }) {
  const payouts = overview.payouts ?? [];
  const transfers = overview.transfers ?? [];
  return (
    <CardShell>
      <SectionTitle
        icon={<Banknote className="h-4.5 w-4.5" />}
        title="Money movement"
      />

      <p className="mt-3 text-[11px] font-black uppercase tracking-[0.14em] text-muted-foreground">
        Payouts to your bank
      </p>
      {payouts.length === 0 ? (
        <p className="mt-1.5 rounded-xl bg-secondary/40 px-3.5 py-3 text-[12.5px] text-muted-foreground">
          No payouts yet — cash out above and it appears here.
        </p>
      ) : (
        <div className="relative mt-2 pl-5">
          <span
            aria-hidden
            className="absolute bottom-2 left-[4px] top-2 w-px bg-border"
          />
          <div className="animate-list-in is-ready space-y-3.5">
            {payouts.slice(0, 8).map((p, i) => (
              <div key={`${p.createdAt}-${i}`} className="relative">
                <span
                  className={cn(
                    "absolute -left-5 top-1.5 h-2.5 w-2.5 rounded-full ring-4 ring-card",
                    payoutDotColor(p.status)
                  )}
                />
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-[14px] font-bold tabular-nums">
                      {formatCents(p.amountCents)}
                    </p>
                    <p className="text-[11.5px] text-muted-foreground">
                      {p.arrivalDate
                        ? `Arrives ${shortDate(p.arrivalDate)}`
                        : shortDate(p.createdAt)}
                    </p>
                  </div>
                  <span
                    className={cn(
                      "rounded-full px-2 py-0.5 text-[10px] font-bold uppercase",
                      payoutChipColor(p.status)
                    )}
                  >
                    {p.status.replace(/_/g, " ")}
                  </span>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      <p className="mt-5 text-[11px] font-black uppercase tracking-[0.14em] text-muted-foreground">
        Money in — recent transfers
      </p>
      {transfers.length === 0 ? (
        <p className="mt-1.5 rounded-xl bg-secondary/40 px-3.5 py-3 text-[12.5px] text-muted-foreground">
          Client payments route here automatically.
        </p>
      ) : (
        <div className="animate-list-in is-ready mt-1 divide-y divide-border">
          {transfers.slice(0, 8).map((t, i) => (
            <div
              key={`${t.createdAt}-${i}`}
              className="flex items-center gap-3 py-2.5"
            >
              <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-emerald-500/12 text-emerald-600">
                <ArrowDownLeft className="h-4 w-4" />
              </span>
              <div className="min-w-0 flex-1">
                <p className="truncate text-[13px] font-semibold">
                  {t.description}
                </p>
                <p className="text-[11.5px] text-muted-foreground">
                  {shortDate(t.createdAt)}
                </p>
              </div>
              <p className="shrink-0 text-[13.5px] font-bold text-emerald-600">
                +{formatCents(t.amountCents)}
              </p>
            </div>
          ))}
        </div>
      )}
    </CardShell>
  );
}

/** Monthly rate with a live "you keep" preview as the coach types. */
function PricingCard({ initialCents }: { initialCents: number | null }) {
  const [dollars, setDollars] = useState<string>(
    initialCents ? (initialCents / 100).toFixed(2) : ""
  );
  const queryClient = useQueryClient();

  useEffect(() => {
    if (initialCents) setDollars((initialCents / 100).toFixed(2));
  }, [initialCents]);

  const parsed = Number(dollars.replace(/[^0-9.]/g, ""));
  const keepCents =
    Number.isFinite(parsed) && parsed > 0 ? Math.round(parsed * 100 * 0.9) : 0;

  const save = useMutation({
    mutationFn: async () => {
      const cents = Math.round(parsed * 100);
      if (!Number.isFinite(cents) || cents < 500 || cents > 200000) {
        throw new Error("Enter a monthly rate between $5 and $2,000.");
      }
      await saveCoachRate(cents);
      return cents;
    },
    onSuccess: (cents) => {
      toast.success(`Your rate is set — ${formatCents(cents)}/month`);
      queryClient.invalidateQueries({ queryKey: ["coach-rate"] });
    },
    onError: (err) =>
      toast.error(err instanceof Error ? err.message : "Couldn't save rate."),
  });

  return (
    <CardShell>
      <SectionTitle
        icon={<DollarSign className="h-4.5 w-4.5" />}
        title="Your monthly rate"
      />
      <p className="mt-3 text-[13px] leading-snug text-muted-foreground">
        What clients pay per month for coaching. Whisper keeps a 10% platform
        fee — the rest lands in your balance.
      </p>
      <div className="mt-4 flex items-center gap-3">
        <div className="flex flex-1 items-center rounded-2xl border border-border bg-background px-4 transition-shadow focus-within:ring-2 focus-within:ring-orange-500/30">
          <span className="text-[15px] font-semibold text-muted-foreground">
            $
          </span>
          <input
            inputMode="decimal"
            value={dollars}
            onChange={(e) => setDollars(e.target.value)}
            placeholder="149.99"
            className="w-full bg-transparent px-2 py-3 text-[15px] font-semibold outline-none placeholder:font-normal placeholder:text-muted-foreground/60"
          />
          <span className="text-[13px] text-muted-foreground">/month</span>
        </div>
        <button
          onClick={() => save.mutate()}
          disabled={save.isPending || !dollars.trim()}
          className="flex h-12 items-center justify-center gap-2 rounded-full bg-gradient-to-r from-orange-500 to-amber-500 px-6 text-[14px] font-bold text-white shadow-md shadow-orange-500/20 transition-transform active:scale-[0.97] disabled:opacity-40 disabled:shadow-none"
        >
          {save.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
          Save
        </button>
      </div>
      {keepCents > 0 && (
        <p className="mt-2.5 text-[12.5px] font-semibold text-emerald-600">
          You keep {formatCents(keepCents)}/month per client after the fee.
        </p>
      )}
    </CardShell>
  );
}

/** Share link with a copy → check micro-interaction. */
function ShareLinkCard({ hireLink }: { hireLink: string }) {
  const [copied, setCopied] = useState<boolean>(false);
  return (
    <CardShell>
      <SectionTitle
        icon={<Copy className="h-4.5 w-4.5" />}
        title="Your coaching link"
      />
      <p className="mt-3 text-[13px] leading-snug text-muted-foreground">
        Share this anywhere — clients open it, see your plans, and subscribe in
        one tap.
      </p>
      <button
        onClick={() => {
          void navigator.clipboard.writeText(hireLink);
          setCopied(true);
          toast.success("Link copied");
          window.setTimeout(() => setCopied(false), 1600);
        }}
        className={cn(
          "mt-3.5 flex w-full items-center gap-2 rounded-2xl border px-4 py-3 text-left transition-colors",
          copied
            ? "border-emerald-500/50 bg-emerald-500/8"
            : "border-border bg-background hover:bg-secondary/40"
        )}
      >
        <span className="min-w-0 flex-1 truncate text-[13.5px] text-muted-foreground">
          {hireLink}
        </span>
        {copied ? (
          <Check className="h-4 w-4 shrink-0 text-emerald-600" />
        ) : (
          <Copy className="h-4 w-4 shrink-0 text-muted-foreground" />
        )}
      </button>
    </CardShell>
  );
}

interface PaymentRow {
  created_at: string;
  description: string | null;
  client_email: string | null;
  net_cents: number;
  gross_cents: number;
}

/** Payment history — monogram chips, staggered rows, friendly empty state. */
function PaymentsCard({
  payments,
  pending,
  hireLink,
}: {
  payments: PaymentRow[];
  pending: boolean;
  hireLink: string;
}) {
  return (
    <CardShell>
      <SectionTitle
        icon={<ReceiptText className="h-4.5 w-4.5" />}
        title="Payments"
      />
      {pending ? (
        <div className="mt-4 space-y-2.5">
          <div className="h-12 animate-pulse rounded-xl bg-secondary/60" />
          <div className="h-12 animate-pulse rounded-xl bg-secondary/45" />
          <div className="h-12 animate-pulse rounded-xl bg-secondary/30" />
        </div>
      ) : payments.length === 0 ? (
        <div className="flex flex-col items-center py-8 text-center">
          <span className="flex h-14 w-14 items-center justify-center rounded-full bg-orange-500/10">
            <Banknote className="h-6 w-6 text-orange-500" />
          </span>
          <p className="mt-3 text-[14.5px] font-bold">No payments yet</p>
          <p className="mt-1 max-w-[260px] text-[12.5px] leading-relaxed text-muted-foreground">
            Share your coaching link to get your first client — payments land
            here the moment they subscribe.
          </p>
          <button
            onClick={() => {
              void navigator.clipboard.writeText(hireLink);
              toast.success("Link copied");
            }}
            className="mt-4 flex h-10 items-center gap-2 rounded-full bg-foreground px-5 text-[13px] font-bold text-background transition-transform active:scale-[0.97]"
          >
            <Copy className="h-3.5 w-3.5" />
            Copy your link
          </button>
        </div>
      ) : (
        <div className="animate-list-in is-ready mt-2 divide-y divide-border">
          {payments.map((p, i) => (
            <div
              key={`${p.created_at}-${i}`}
              className="flex items-center gap-3 py-3"
            >
              <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-orange-500 to-amber-500 text-[13px] font-black uppercase text-white">
                {(p.client_email ?? "C").slice(0, 1)}
              </span>
              <div className="min-w-0 flex-1">
                <p className="truncate text-[14px] font-semibold">
                  {(p.description ?? "Coaching payment").replace(
                    /\s*\[program:[^\]]*\]/g,
                    ""
                  )}
                </p>
                <p className="text-[12px] text-muted-foreground">
                  {new Date(p.created_at).toLocaleDateString("en-US", {
                    month: "short",
                    day: "numeric",
                    year: "numeric",
                  })}
                  {p.client_email ? ` · ${p.client_email}` : ""}
                </p>
              </div>
              <div className="text-right">
                <p className="text-[14px] font-bold text-emerald-600">
                  +{formatCents(p.net_cents)}
                </p>
                <p className="text-[11px] text-muted-foreground">
                  {formatCents(p.gross_cents)} − fee
                </p>
              </div>
            </div>
          ))}
        </div>
      )}
    </CardShell>
  );
}

/** Full-page loading skeleton shaped like the real layout. */
function EarningsSkeleton() {
  return (
    <div className="space-y-4">
      <div className="h-[248px] animate-pulse rounded-[28px] bg-zinc-950/90" />
      <div className="grid grid-cols-3 gap-2.5">
        <div className="h-[92px] animate-pulse rounded-2xl bg-secondary/70" />
        <div className="h-[92px] animate-pulse rounded-2xl bg-secondary/55" />
        <div className="h-[92px] animate-pulse rounded-2xl bg-secondary/40" />
      </div>
      <div className="h-[180px] animate-pulse rounded-[22px] bg-secondary/50" />
      <div className="h-[140px] animate-pulse rounded-[22px] bg-secondary/35" />
    </div>
  );
}

/**
 * Coach earnings — the money home: animated wallet hero, live Stripe
 * standing, payout timeline, pricing, plans, share link, and history.
 */
export default function CoachEarnings() {
  const navigate = useNavigate();
  const { user, profile, loading } = useAuth();
  const queryClient = useQueryClient();
  const [redirecting, setRedirecting] = useState<boolean>(false);
  const [linkingBank, setLinkingBank] = useState<boolean>(false);

  const coachState = useQuery({
    queryKey: ["role-state", user?.id ?? "", "coach"],
    queryFn: () => fetchRoleState(user!.id, "coach"),
    enabled: !!user?.id,
  });

  const earnings = useQuery({
    queryKey: ["coach-earnings", user?.id ?? ""],
    queryFn: fetchCoachEarnings,
    enabled: !!user?.id,
    refetchInterval: 60_000,
  });

  const rate = useQuery({
    queryKey: ["coach-rate", user?.id ?? ""],
    queryFn: async () => {
      const { fetchCoachRate } = await import("@/lib/coachPay");
      return fetchCoachRate(user!.id);
    },
    enabled: !!user?.id,
  });

  const connected = earnings.data?.connected === true;

  const overview = useQuery({
    queryKey: ["stripe-overview"],
    queryFn: fetchStripeOverview,
    enabled: connected,
    refetchInterval: 120_000,
  });

  const payout = useMutation({
    mutationFn: cashOut,
    onSuccess: (cents) => {
      toast.success(
        `Cash out started — ${formatCents(cents)} is on its way to your bank.`
      );
      queryClient.invalidateQueries({ queryKey: ["coach-earnings"] });
      queryClient.invalidateQueries({ queryKey: ["stripe-overview"] });
    },
    onError: (err) =>
      toast.error(err instanceof Error ? err.message : "Cash out failed."),
  });

  /**
   * In-app bank linking first (embedded, Cash App style). Falls back to the
   * hosted Stripe redirect only if the embedded flow isn't configured.
   */
  const handleOnboard = async () => {
    setRedirecting(true);
    try {
      const { createConnectSession } = await import("@/lib/coachPay");
      await createConnectSession();
      setLinkingBank(true);
      setRedirecting(false);
    } catch (err) {
      const msg = err instanceof Error ? err.message : "";
      try {
        await startBankOnboarding();
        return;
      } catch (fallbackErr) {
        toast.error(
          (msg !== "embedded_not_configured" && msg) ||
            (fallbackErr instanceof Error
              ? fallbackErr.message
              : "Couldn't start onboarding.")
        );
      }
      setRedirecting(false);
    }
  };

  const handleBankDone = () => {
    setLinkingBank(false);
    void import("@/lib/coachPay")
      .then((m) => m.fetchConnectStatus())
      .catch(() => undefined)
      .finally(() => {
        queryClient.invalidateQueries({ queryKey: ["coach-earnings"] });
        queryClient.invalidateQueries({ queryKey: ["coach-rate"] });
        queryClient.invalidateQueries({ queryKey: ["stripe-overview"] });
      });
    toast.success("Bank details saved.");
  };

  const hireLink = siteUrl(`/hire/${user?.id ?? ""}`);

  const isCoach =
    coachState.data?.active || coachState.data?.application === "approved";

  const e = earnings.data;

  const monthStats = useMemo(() => {
    const list = e?.payments ?? [];
    const now = new Date();
    let cents = 0;
    let count = 0;
    for (const p of list) {
      const d = new Date(p.created_at);
      if (
        d.getMonth() === now.getMonth() &&
        d.getFullYear() === now.getFullYear()
      ) {
        cents += p.net_cents;
        count += 1;
      }
    }
    return { cents, count };
  }, [e?.payments]);

  let body: React.ReactNode;
  if (loading || coachState.isPending) {
    body = <EarningsSkeleton />;
  } else if (!isCoach) {
    body = (
      <CardShell>
        <div className="flex flex-col items-center py-8 text-center">
          <span className="flex h-16 w-16 items-center justify-center rounded-full bg-orange-500/10">
            <CircleAlert className="h-7 w-7 text-orange-500" />
          </span>
          <p className="mt-4 text-[17px] font-extrabold">Coaches only</p>
          <p className="mt-2 max-w-sm text-[14px] leading-relaxed text-muted-foreground">
            Earnings unlock once your coach application is approved. Applying
            is free.
          </p>
          <Link
            to="/apply/coach"
            className="mt-5 flex h-11 items-center justify-center rounded-full bg-gradient-to-r from-orange-500 to-amber-500 px-6 text-[14px] font-bold text-white shadow-md shadow-orange-500/20"
          >
            Apply to become a coach
          </Link>
        </div>
      </CardShell>
    );
  } else {
    const payoutsReady = e?.payoutsEnabled === true;
    body = (
      <div className="animate-list-in is-ready space-y-4">
        <WalletHero
          availableCents={e?.availableCents ?? 0}
          pendingCents={e?.pendingCents ?? 0}
          totalEarnedCents={e?.totalEarnedCents ?? 0}
          connected={connected}
          payoutsReady={payoutsReady}
          loading={earnings.isPending}
          onCashOut={() => payout.mutate()}
          cashingOut={payout.isPending}
        />

        <SnapshotRow
          monthCents={monthStats.cents}
          monthCount={monthStats.count}
          totalEarnedCents={e?.totalEarnedCents ?? 0}
        />

        <BankingCard
          connected={connected}
          payoutsReady={payoutsReady}
          overview={overview.data}
          overviewPending={connected && overview.isPending}
          redirecting={redirecting}
          onOnboard={handleOnboard}
        />

        {connected && overview.data?.connected && (
          <ActivityCard overview={overview.data} />
        )}

        <PricingCard initialCents={rate.data?.monthlyPriceCents ?? null} />

        {/* Plan tiers — clients pick one of these on the hire page. */}
        <div id="plans" className="scroll-mt-24">
          <CoachTierManager userId={user?.id} />
        </div>

        <ShareLinkCard hireLink={hireLink} />

        <PaymentsCard
          payments={e?.payments ?? []}
          pending={earnings.isPending}
          hireLink={hireLink}
        />

        <p className="px-2 text-[12px] leading-snug text-muted-foreground">
          Signed in as @{profile?.username ?? "you"} · Payments and payouts are
          processed by Stripe. Whisper keeps a 10% platform fee on client
          payments; payouts to your bank are free.
        </p>
      </div>
    );
  }

  return (
    <div>
      <Header
        title="Earnings"
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
      <div className="px-4 pb-12 sm:px-0">
        <div className="mx-auto w-full max-w-[720px]">{body}</div>
      </div>
      {linkingBank && (
        <BankLinkSheet
          onClose={() => {
            setLinkingBank(false);
            queryClient.invalidateQueries({ queryKey: ["coach-earnings"] });
          }}
          onDone={handleBankDone}
        />
      )}
    </div>
  );
}
