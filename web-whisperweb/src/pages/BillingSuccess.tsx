import { Link, useSearchParams } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { ArrowRight, CircleAlert, Loader2 } from "lucide-react";

import PublicNav from "@/components/PublicNav";
import PublicFooter from "@/components/PublicFooter";
import { OneBadge } from "@/components/OneBadge";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/hooks/useAuth";
import { fetchCheckoutSession } from "@/lib/billing";

export default function BillingSuccess() {
  const [params] = useSearchParams();
  const sessionId = params.get("session_id") ?? "";
  /** Embedded checkout completions land here without a session id. */
  const embeddedDone = params.get("embedded") === "1";
  const { session } = useAuth();

  const verify = useQuery({
    queryKey: ["stripe-session", sessionId],
    queryFn: () => fetchCheckoutSession(sessionId),
    enabled: sessionId.length > 0,
    retry: 2,
  });

  const paid =
    verify.data?.paymentStatus === "paid" ||
    verify.data?.status === "complete";
  const plan = verify.data?.plan ?? "";
  const badgeRole =
    plan === "coach-annual"
      ? "Verified Coach"
      : plan === "athlete-annual"
        ? "Verified Athlete"
        : null;
  const planLabel = badgeRole
    ? `${badgeRole} · Annual`
    : plan === "one-annual"
      ? "Whisper One · Annual"
      : "Whisper One · Monthly";

  return (
    <div className="flex min-h-screen flex-col bg-background">
      <PublicNav />

      <main className="flex flex-1 items-center justify-center px-4 pb-16 pt-32 sm:px-6">
        <div className="w-full max-w-md rounded-[32px] border border-border bg-card p-8 text-center sm:p-10">
          {embeddedDone && !sessionId ? (
            <>
              <svg viewBox="0 0 56 56" className="mx-auto mb-5 h-16 w-16">
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
              <h1 className="font-display text-[26px] font-extrabold">
                Payment confirmed
              </h1>
              <p className="mt-4 text-[15px] leading-relaxed text-muted-foreground">
                You&rsquo;re all set — your perks are unlocking now. A receipt
                is on its way to your email and saved in Settings → Billing
                &amp; refunds.
              </p>
              <Button className="mt-7 h-12 w-full rounded-full text-[15px] font-semibold" asChild>
                <Link to={session ? "/" : "/auth"}>
                  {session ? "Open Whisper" : "Sign in to Whisper"}
                  <ArrowRight className="ml-1 h-4 w-4" />
                </Link>
              </Button>
              <p className="mt-4 text-[12.5px] text-muted-foreground">
                Covered by the refund windows in our{" "}
                <Link to="/policies" className="underline underline-offset-2">
                  policies
                </Link>
                .
              </p>
            </>
          ) : !sessionId || verify.isError ? (
            <>
              <div className="mx-auto mb-5 flex h-16 w-16 items-center justify-center rounded-full bg-secondary">
                <CircleAlert className="h-8 w-8 text-muted-foreground" />
              </div>
              <h1 className="font-display text-[24px] font-extrabold">
                We couldn't verify that payment
              </h1>
              <p className="mt-3 text-[15px] leading-relaxed text-muted-foreground">
                If you completed checkout, don't worry — Stripe has your
                receipt and your membership will activate. If the charge shows
                up without perks, contact support from Settings → Help &
                Support.
              </p>
              <Button className="mt-7 h-12 w-full rounded-full text-[15px] font-semibold" asChild>
                <Link to="/one">Back to Whisper One</Link>
              </Button>
            </>
          ) : verify.isPending ? (
            <>
              <Loader2 className="mx-auto mb-5 h-10 w-10 animate-spin text-muted-foreground" />
              <h1 className="font-display text-[24px] font-extrabold">
                Confirming your payment…
              </h1>
              <p className="mt-3 text-[15px] text-muted-foreground">
                One second while we check with Stripe.
              </p>
            </>
          ) : (
            <>
              <div className="mx-auto mb-5 flex h-16 w-16 items-center justify-center rounded-[20px] bg-secondary">
                <OneBadge size={34} />
              </div>
              <h1 className="font-display text-[26px] font-extrabold">
                {badgeRole
                  ? paid
                    ? `Your ${badgeRole} badge is live`
                    : "Payment received"
                  : paid
                    ? "Welcome to Whisper One"
                    : "Payment received"}
              </h1>
              <p className="mt-2 text-[13px] font-bold uppercase tracking-wider text-muted-foreground">
                {planLabel}
              </p>
              <p className="mt-4 text-[15px] leading-relaxed text-muted-foreground">
                {badgeRole ? (
                  <>
                    Your {badgeRole} badge is now active on your profile,
                    posts, replies, and DMs, along with all the role perks. It
                    renews once a year.
                  </>
                ) : (
                  <>
                    Your membership is active. The black{" "}
                    <span className="font-semibold text-foreground">+</span>{" "}
                    badge, 3 client slots, Creator Studio Lite, and stat
                    sharing unlock in the app
                    {session ? "" : " once you sign in"}.
                  </>
                )}
                {verify.data?.customerEmail
                  ? ` A receipt is on its way to ${verify.data.customerEmail}.`
                  : " A receipt is on its way to your email."}
              </p>
              <Button className="mt-7 h-12 w-full rounded-full text-[15px] font-semibold" asChild>
                <Link to={session ? "/" : "/auth"}>
                  {session ? "Open Whisper" : "Sign in to Whisper"}
                  <ArrowRight className="ml-1 h-4 w-4" />
                </Link>
              </Button>
              <p className="mt-4 text-[12.5px] text-muted-foreground">
                Covered by the 14-day refund policy in our{" "}
                <Link to="/terms" className="underline underline-offset-2">
                  Terms
                </Link>
                .
              </p>
            </>
          )}
        </div>
      </main>

      <PublicFooter />
    </div>
  );
}
