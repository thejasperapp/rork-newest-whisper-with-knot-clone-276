import { useState } from "react";
import { usePitchReset, usePitchToast } from "@/components/pitch/PitchContext";
import {
  ArrowLeft,
  BadgeCheck,
  Banknote,
  BanknoteIcon,
  CircleAlert,
  Copy,
  DollarSign,
  ExternalLink,
  Landmark,
  Loader2,
  TrendingUp,
} from "lucide-react";

import {
  COACH_PLATFORM_FEE_PERCENT,
  COACH_RATE_MAX,
  COACH_RATE_MIN,
  SAMPLE_COACH_EARNINGS,
  formatUsd,
} from "@/lib/pitch";
import { cn } from "@/lib/utils";

const STEPS = [
  {
    icon: DollarSign,
    title: "Set your monthly rate",
    body: `You pick any rate from $${COACH_RATE_MIN} to $${COACH_RATE_MAX}/month inside Coach Studio. Change it whenever you want.`,
  },
  {
    icon: Landmark,
    title: "Link your bank once",
    body: "Stripe onboarding takes ~2 minutes. Whisper never touches your money — payouts go straight from Stripe to your bank.",
  },
  {
    icon: BadgeCheck,
    title: "Clients hire you in-app",
    body: "Anyone can tap Hire on your profile or the Coaches page. They subscribe monthly with Apple Pay or a card.",
  },
  {
    icon: Banknote,
    title: "You get paid automatically",
    body: `Every month, ${100 - COACH_PLATFORM_FEE_PERCENT}% of each subscription lands in your Stripe balance. Whisper keeps ${COACH_PLATFORM_FEE_PERCENT}% — that's the whole fee.`,
  },
] as const;

/**
 * Coach money-flow walkthrough for Pitch Mode. The earnings view below is a
 * faithful mirror of the real /coach/earnings page: the black balance card,
 * pending + all-time stats, the bank-account card with the Stripe-linked
 * badge, the rate card, the shareable coaching link, and the payments history
 * list — all rendered with sample data so a prospect coach sees exactly what
 * their account will look like once clients are subscribing.
 */
export function CoachEarningsDemo() {
  const [activeStep, setActiveStep] = useState<number>(0);
  const [rate, setRate] = useState<number>(150);
  const [clients, setClients] = useState<number>(10);
  const showToast = usePitchToast();
  usePitchReset(() => {
    setActiveStep(0);
    setRate(150);
    setClients(10);
  });

  const grossCents = rate * clients * 100;
  const feeCents = Math.round((grossCents * COACH_PLATFORM_FEE_PERCENT) / 100);
  const netCents = grossCents - feeCents;
  const e = SAMPLE_COACH_EARNINGS;
  const fmt = (c: number) => formatUsd(c);

  return (
    <div className="space-y-4">
      {/* Step walkthrough — clickable during a live pitch */}
      <div className="space-y-2">
        {STEPS.map((step, i) => {
          const active = i === activeStep;
          return (
            <button
              key={step.title}
              onClick={() => {
                setActiveStep(i);
                showToast(STEPS[i].title, "info");
              }}
              className={cn(
                "flex w-full items-start gap-3 rounded-2xl border p-4 text-left transition-all active:scale-[0.99]",
                active
                  ? "border-foreground bg-foreground text-background shadow-md"
                  : "border-border bg-card hover:border-foreground/25"
              )}
            >
              <span
                className={cn(
                  "flex h-9 w-9 shrink-0 items-center justify-center rounded-xl",
                  active ? "bg-background/15" : "bg-secondary"
                )}
              >
                <step.icon className="h-4.5 w-4.5" />
              </span>
              <div className="min-w-0">
                <p className="text-sm font-bold">
                  <span
                    className={cn(
                      "mr-1.5",
                      active ? "opacity-60" : "text-muted-foreground"
                    )}
                  >
                    {i + 1}.
                  </span>
                  {step.title}
                </p>
                <p
                  className={cn(
                    "mt-0.5 text-[13px] leading-snug",
                    active ? "opacity-85" : "text-muted-foreground"
                  )}
                >
                  {step.body}
                </p>
              </div>
            </button>
          );
        })}
      </div>

      {/* Real CoachEarnings view — sample data */}
      <div className="space-y-4">
        {/* Balance card — verbatim from /coach/earnings */}
        <div className="rounded-[24px] bg-foreground p-6 text-background">
          <p className="text-[11px] font-black uppercase tracking-[0.2em] opacity-70">
            Your balance
          </p>
          <p className="mt-2 text-[40px] font-extrabold leading-none">
            {fmt(e.availableCents)}
          </p>
          <div className="mt-3 flex items-center gap-4 text-[13px] opacity-80">
            <span>Pending: {fmt(e.pendingCents)}</span>
            <span className="flex items-center gap-1">
              <TrendingUp className="h-3.5 w-3.5" />
              Earned all-time: {fmt(e.totalEarnedCents)}
            </span>
          </div>
          <button
            className="mt-5 flex h-12 w-full items-center justify-center gap-2 rounded-full bg-background text-[15px] font-bold text-foreground transition-transform active:scale-[0.98]"
          >
            <Banknote className="h-4 w-4" />
            Cash out to bank
          </button>
          <p className="mt-2.5 text-center text-[12.5px] opacity-70">
            Tap to transfer your available balance — arrives in 1–2 business days.
          </p>
        </div>

        {/* Bank account card — verbatim */}
        <div className="rounded-[20px] border border-border bg-card p-5 shadow-sm">
          <div className="flex items-center gap-2.5">
            <Landmark className="h-5 w-5" />
            <p className="text-[15px] font-bold">Bank account</p>
            <span className="ml-auto flex items-center gap-1 rounded-full bg-emerald-500 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide text-white">
              <BadgeCheck className="h-3 w-3" /> Linked
            </span>
          </div>
          <p className="mt-1.5 text-[13px] leading-snug text-muted-foreground">
            Your bank is linked through Stripe. Manage details or view payouts anytime.
          </p>
          <div className="mt-4 flex flex-col gap-2 sm:flex-row">
            <button className="flex h-11 flex-1 items-center justify-center gap-2 rounded-full bg-foreground text-[14px] font-bold text-background transition-transform active:scale-[0.98]">
              Update bank details
            </button>
            <button className="flex h-11 items-center justify-center gap-2 rounded-full border border-border px-5 text-[14px] font-bold transition-colors hover:bg-secondary/50">
              <ExternalLink className="h-4 w-4" />
              Stripe dashboard
            </button>
          </div>
        </div>

        {/* Rate card — verbatim */}
        <div className="rounded-[20px] border border-border bg-card p-5 shadow-sm">
          <div className="flex items-center gap-2.5">
            <DollarSign className="h-5 w-5 text-orange-500" />
            <p className="text-[15px] font-bold">Your monthly rate</p>
          </div>
          <p className="mt-1.5 text-[13px] leading-snug text-muted-foreground">
            What clients pay you per month for coaching. Whisper keeps a 10%
            platform fee — the rest lands in your balance below.
          </p>
          <div className="mt-4 flex items-center gap-3">
            <div className="flex flex-1 items-center rounded-xl border border-border bg-background px-3.5">
              <span className="text-[15px] font-semibold text-muted-foreground">$</span>
              <input
                inputMode="decimal"
                value={String((rate / 100).toFixed(2))}
                readOnly
                className="w-full bg-transparent px-2 py-2.5 text-[15px] outline-none"
              />
              <span className="text-[13px] text-muted-foreground">/month</span>
            </div>
            <span className="rounded-full bg-orange-500 px-5 py-2.5 text-[14px] font-bold text-white">
              Set
            </span>
          </div>
        </div>

        {/* Share link card — verbatim */}
        <div className="rounded-[20px] border border-border bg-card p-5 shadow-sm">
          <p className="text-[15px] font-bold">Your coaching link</p>
          <p className="mt-1.5 text-[13px] leading-snug text-muted-foreground">
            Share this anywhere — clients open it, see your rate, and subscribe
            in one tap.
          </p>
          <button
            className="mt-3 flex w-full items-center gap-2 rounded-xl border border-border bg-background px-3.5 py-2.5 text-left"
          >
            <span className="min-w-0 flex-1 truncate text-[13.5px] text-muted-foreground">
              mydailywhisper.com/hire/you
            </span>
            <Copy className="h-4 w-4 shrink-0 text-muted-foreground" />
          </button>
        </div>

        {/* Payments history — verbatim */}
        <div className="rounded-[20px] border border-border bg-card p-5 shadow-sm">
          <p className="text-[15px] font-bold">Payments</p>
          <div className="mt-2 divide-y divide-border">
            {e.payments.map((p, i) => (
              <div
                key={`${p.created_at}-${i}`}
                className="flex items-center gap-3 py-3"
              >
                <div className="min-w-0 flex-1">
                  <p className="truncate text-[14px] font-semibold">
                    {p.description ?? "Coaching payment"}
                  </p>
                  <p className="text-[12.5px] text-muted-foreground">
                    {new Date(p.created_at).toLocaleDateString("en-US", {
                      month: "short",
                      day: "numeric",
                      year: "numeric",
                    })}
                    {p.client_email ? ` · ${p.client_email}` : ""}
                  </p>
                </div>
                <div className="text-right">
                  <p className="text-[14px] font-bold">+{fmt(p.net_cents)}</p>
                  <p className="text-[11.5px] text-muted-foreground">
                    {fmt(p.gross_cents)} − fee
                  </p>
                </div>
              </div>
            ))}
          </div>
        </div>

        <p className="px-2 text-[12px] leading-snug text-muted-foreground">
          Sample data for presentation · Payments and payouts are processed by
          Stripe. Whisper keeps a 10% platform fee on client payments; payouts
          to your bank are free.
        </p>
      </div>

      {/* Live earnings calculator — uses real platform constants */}
      <div className="rounded-2xl border border-border bg-card p-4 shadow-sm">
        <p className="flex items-center gap-1.5 text-xs font-bold uppercase tracking-wider text-muted-foreground">
          <BanknoteIcon className="h-3.5 w-3.5" /> Live take-home calculator
        </p>
        <div className="mt-4 space-y-5">
          <div>
            <div className="flex items-baseline justify-between">
              <p className="text-sm font-semibold">Your monthly rate</p>
              <p className="text-sm font-bold">${rate}/mo</p>
            </div>
            <input
              type="range"
              min={COACH_RATE_MIN}
              max={COACH_RATE_MAX}
              step={5}
              value={rate}
              onChange={(e) => setRate(Number(e.target.value))}
              className="mt-2 w-full accent-foreground"
            />
          </div>
          <div>
            <div className="flex items-baseline justify-between">
              <p className="text-sm font-semibold">Active clients</p>
              <p className="text-sm font-bold">{clients}</p>
            </div>
            <input
              type="range"
              min={1}
              max={100}
              step={1}
              value={clients}
              onChange={(e) => setClients(Number(e.target.value))}
              className="mt-2 w-full accent-foreground"
            />
          </div>
        </div>
        <div className="mt-5 space-y-1.5 rounded-xl bg-secondary/50 p-3 text-sm">
          <div className="flex justify-between">
            <span className="text-muted-foreground">Gross subscriptions</span>
            <span className="font-semibold">{fmt(grossCents)}/mo</span>
          </div>
          <div className="flex justify-between">
            <span className="text-muted-foreground">
              Whisper fee ({COACH_PLATFORM_FEE_PERCENT}%)
            </span>
            <span className="font-semibold">−{fmt(feeCents)}</span>
          </div>
        </div>
        <div className="mt-3 rounded-xl bg-foreground p-4 text-background">
          <p className="text-[11px] font-bold uppercase tracking-wider opacity-70">
            You take home
          </p>
          <p className="mt-0.5 text-3xl font-extrabold tracking-tight">
            {fmt(netCents)}
            <span className="text-base font-semibold opacity-70">/mo</span>
          </p>
          <p className="mt-1 text-xs opacity-70">
            Paid out by Stripe on a rolling basis · no listing fees, no ad spend
          </p>
        </div>
      </div>
    </div>
  );
}
