import { useEffect, useMemo, useState } from "react";
import {
  ArrowRight,
  Check,
  Loader2,
  Lock,
  ShieldCheck,
  X,
} from "lucide-react";
import { loadStripe, type Stripe } from "@stripe/stripe-js";
import {
  EmbeddedCheckoutProvider,
  EmbeddedCheckout,
} from "@stripe/react-stripe-js";

import { cn } from "@/lib/utils";
import { GradientTypeIn } from "@/components/GradientTypeIn";
import { TestModeBanner } from "@/components/TestModeBanner";
import type { CheckoutBrief } from "@/lib/billing";

/** Confetti burst for the success step — fixed layout, staggered starts. */
const CONFETTI: { left: string; color: string; delay: string }[] = [
  { left: "6%", color: "#34D399", delay: "0s" },
  { left: "14%", color: "#F59E0B", delay: "0.12s" },
  { left: "22%", color: "#818CF8", delay: "0.05s" },
  { left: "30%", color: "#F472B6", delay: "0.2s" },
  { left: "38%", color: "#34D399", delay: "0.02s" },
  { left: "46%", color: "#FBBF24", delay: "0.16s" },
  { left: "54%", color: "#60A5FA", delay: "0.08s" },
  { left: "62%", color: "#F472B6", delay: "0.22s" },
  { left: "70%", color: "#34D399", delay: "0.1s" },
  { left: "78%", color: "#818CF8", delay: "0.03s" },
  { left: "86%", color: "#F59E0B", delay: "0.18s" },
  { left: "93%", color: "#60A5FA", delay: "0.07s" },
];

type SheetStep = "brief" | "pay" | "done";

/**
 * In-app checkout sheet — an animated "what you get" brief, then Stripe's
 * Embedded Checkout inline (no redirect), then a confetti success moment.
 * The publishable key comes from the backend so keys are never hardcoded.
 */
export function EmbeddedCheckoutSheet({
  clientSecret,
  publishableKey,
  brief,
  onClose,
  onComplete,
}: {
  clientSecret: string;
  publishableKey: string;
  /** Optional staggered perk brief shown before the payment form. */
  brief?: CheckoutBrief;
  onClose: () => void;
  onComplete: () => void;
}) {
  const stripePromise = useMemo<Promise<Stripe | null>>(
    () => loadStripe(publishableKey).catch(() => null),
    [publishableKey]
  );
  const [step, setStep] = useState<SheetStep>(brief ? "brief" : "pay");
  const [loadFailed, setLoadFailed] = useState<boolean>(false);

  // Hold the celebration for a beat, then hand control back to the caller.
  useEffect(() => {
    if (step !== "done") return;
    const timer = window.setTimeout(onComplete, 2400);
    return () => window.clearTimeout(timer);
  }, [step, onComplete]);

  const options = useMemo(
    () => ({
      clientSecret,
      onComplete: () => {
        setLoadFailed(false);
        setStep("done");
      },
    }),
    [clientSecret]
  );

  const headerTitle =
    step === "brief"
      ? "Review your order"
      : step === "done"
        ? "Payment complete"
        : "Checkout";

  return (
    <div className="fixed inset-0 z-[80] flex items-end justify-center sm:items-center">
      <button
        aria-label="Close"
        onClick={step === "done" ? onComplete : onClose}
        className="absolute inset-0 bg-black/50 backdrop-blur-sm"
      />
      <div
        className={cn(
          "checkout-sheet-in relative flex w-full flex-col overflow-hidden rounded-t-[24px] bg-card shadow-2xl sm:max-w-lg sm:rounded-[24px]",
          step === "pay" ? "h-[92dvh] sm:h-[88vh]" : "max-h-[92dvh]"
        )}
      >
        <div className="flex items-center justify-between border-b border-border px-5 py-4">
          <div>
            <p className="text-[16px] font-extrabold">{headerTitle}</p>
            <p className="text-[12.5px] text-muted-foreground">
              Secured by Stripe — no redirect ·{" "}
              <a
                href="/policies#billing"
                target="_blank"
                rel="noreferrer"
                className="underline"
              >
                refund policy
              </a>
            </p>
          </div>
          <button
            onClick={step === "done" ? onComplete : onClose}
            aria-label="Close"
            className="flex h-9 w-9 items-center justify-center rounded-full bg-secondary transition-transform active:scale-90"
          >
            <X className="h-4.5 w-4.5" />
          </button>
        </div>

        {step === "brief" && brief ? (
          <div className="overflow-y-auto px-5 pb-6 pt-4">
            <TestModeBanner />

            {/* Order summary */}
            <div
              className="checkout-rise mt-2 rounded-2xl border border-border bg-background p-4"
              style={{ animationDelay: "0.04s" }}
            >
              <p className="text-[10.5px] font-black uppercase tracking-[0.18em] text-muted-foreground">
                Your order
              </p>
              <div className="mt-1.5 flex items-end justify-between gap-3">
                {/* The Whisper type-in — the brief's headline types in wearing
                    the brand gradient and settles to ink (iOS paywall parity). */}
                <GradientTypeIn
                  text={brief.title}
                  speed={28}
                  as="p"
                  className="min-w-0 text-[19px] font-extrabold leading-tight"
                />
                <p
                  className="checkout-pop shrink-0 text-right"
                  style={{ animationDelay: "0.16s" }}
                >
                  <span className="text-[22px] font-black tabular-nums">
                    {brief.price}
                  </span>
                  <span className="text-[12.5px] font-semibold text-muted-foreground">
                    {brief.cadence}
                  </span>
                </p>
              </div>
              {brief.note && (
                <p className="mt-1 text-[12.5px] text-muted-foreground">
                  {brief.note}
                </p>
              )}
            </div>

            {/* What you get — staggered perk rows */}
            <p
              className="checkout-rise mt-5 px-1 text-[10.5px] font-black uppercase tracking-[0.18em] text-muted-foreground"
              style={{ animationDelay: "0.12s" }}
            >
              What you get
            </p>
            <div className="mt-2 space-y-1.5">
              {brief.perks.map((perk, i) => (
                <div
                  key={perk}
                  className="checkout-rise flex items-start gap-2.5 rounded-xl border border-border bg-background px-3 py-2.5"
                  style={{ animationDelay: `${0.16 + i * 0.07}s` }}
                >
                  <span className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-emerald-500/15">
                    <Check
                      className="h-3 w-3 text-emerald-600"
                      strokeWidth={3.5}
                    />
                  </span>
                  <p className="text-[13.5px] font-medium leading-snug">
                    {perk}
                  </p>
                </div>
              ))}
            </div>

            {/* Trust rows */}
            <div
              className="checkout-rise mt-4 space-y-2 px-1"
              style={{
                animationDelay: `${0.2 + brief.perks.length * 0.07}s`,
              }}
            >
              <p className="flex items-start gap-2 text-[12.5px] leading-snug text-muted-foreground">
                <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" />
                <span>
                  {brief.refundDays}-day refund window — every request is
                  reviewed by a human in Settings → Billing &amp; refunds.
                </span>
              </p>
              <p className="flex items-start gap-2 text-[12.5px] leading-snug text-muted-foreground">
                <Lock className="mt-0.5 h-4 w-4 shrink-0" />
                <span>
                  Card details never touch Whisper. A receipt lands in your
                  email the moment payment clears.
                </span>
              </p>
            </div>

            <button
              onClick={() => setStep("pay")}
              className="tap-scale checkout-rise mt-5 flex h-12 w-full items-center justify-center gap-2 rounded-full bg-foreground text-[14.5px] font-extrabold text-background"
              style={{
                animationDelay: `${0.26 + brief.perks.length * 0.07}s`,
              }}
            >
              Continue to secure payment
              <ArrowRight className="h-4 w-4" />
            </button>
          </div>
        ) : step === "done" ? (
          <div className="relative overflow-hidden px-6 pb-9 pt-8 text-center">
            <div className="pointer-events-none absolute inset-x-0 top-0 h-44">
              {CONFETTI.map((c, i) => (
                <span
                  key={i}
                  className="checkout-confetti absolute top-0 h-2 w-1.5 rounded-[2px]"
                  style={{
                    left: c.left,
                    background: c.color,
                    animationDelay: c.delay,
                  }}
                />
              ))}
            </div>
            <svg viewBox="0 0 56 56" className="mx-auto h-16 w-16">
              <circle
                cx="28"
                cy="28"
                r="26"
                fill="none"
                stroke="#10B981"
                strokeWidth="3"
                strokeLinecap="round"
                className="checkout-check-circle"
                transform="rotate(-90 28 28)"
              />
              <path
                d="M17 29.5 25 37l14-16"
                fill="none"
                stroke="#10B981"
                strokeWidth="4"
                strokeLinecap="round"
                strokeLinejoin="round"
                className="checkout-check-mark"
              />
            </svg>
            <h2
              className="checkout-pop mt-4 text-[22px] font-black"
              style={{ animationDelay: "0.25s" }}
            >
              You&rsquo;re in!
            </h2>
            {brief && (
              <p className="mt-1 text-[13px] font-bold uppercase tracking-wider text-muted-foreground">
                {brief.title}
              </p>
            )}
            <p className="mx-auto mt-3 max-w-xs text-[13.5px] leading-relaxed text-muted-foreground">
              Payment confirmed. Your receipt is on its way to your email and
              saved in Settings → Billing &amp; refunds.
            </p>
            <button
              onClick={onComplete}
              className="tap-scale mt-6 h-11 rounded-full bg-foreground px-8 text-[13.5px] font-extrabold text-background"
            >
              Continue
            </button>
          </div>
        ) : (
          <div className="flex-1 overflow-y-auto">
            <div className="px-4 pt-3">
              <TestModeBanner />
            </div>
            {loadFailed ? (
              <div className="flex h-full flex-col items-center justify-center px-6 text-center">
                <p className="text-[14px] font-semibold">
                  Checkout couldn&rsquo;t load
                </p>
                <p className="mt-2 text-[13px] leading-relaxed text-muted-foreground">
                  Please close and try again. Your card wasn&rsquo;t charged.
                </p>
                <button
                  onClick={onClose}
                  className="mt-4 rounded-full bg-foreground px-5 py-2.5 text-[13.5px] font-bold text-background"
                >
                  Close
                </button>
              </div>
            ) : (
              <EmbeddedCheckoutProvider stripe={stripePromise} options={options}>
                <div className="relative flex min-h-[200px] items-center justify-center">
                  <EmbeddedCheckout />
                  <Loader2 className="absolute h-7 w-7 animate-spin text-muted-foreground opacity-50" />
                </div>
              </EmbeddedCheckoutProvider>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
