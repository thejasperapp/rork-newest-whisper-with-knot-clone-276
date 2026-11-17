import { useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import {
  BadgeCheck,
  CheckCircle2,
  Clock,
  CircleAlert,
  Loader2,
  ShieldCheck,
  Sparkles,
} from "lucide-react";
import { toast } from "sonner";

import PublicNav from "@/components/PublicNav";
import PublicFooter from "@/components/PublicFooter";
import { EmbeddedCheckoutSheet } from "@/components/EmbeddedCheckoutSheet";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/hooks/useAuth";
import { fetchRoleState } from "@/lib/applications";
import {
  BADGE_PERKS,
  BADGE_PLANS,
  startEmbeddedCheckout,
  type BadgeRole,
  type EmbeddedCheckoutResult,
} from "@/lib/billing";

/**
 * Post-approval payment page for verified badges (Coach / Creator). Users
 * land here from the "you're approved" email. Checkout is gated server-side
 * too — the backend rejects any user without an approved application.
 */
export default function BadgeActivate() {
  const [params] = useSearchParams();
  const rawRole = params.get("role") ?? "";
  // Old approval emails linked ?role=athlete — that badge is a Creator niche now.
  const role: BadgeRole | null =
    rawRole === "coach"
      ? "coach"
      : rawRole === "verified" || rawRole === "athlete" || rawRole === "creator"
        ? "verified"
        : null;
  const { session, loading } = useAuth();
  const [starting, setStarting] = useState<boolean>(false);
  const [embedded, setEmbedded] = useState<EmbeddedCheckoutResult | null>(null);

  const state = useQuery({
    queryKey: ["badge-state", session?.user?.id ?? "", role ?? ""],
    queryFn: () => fetchRoleState(session!.user.id, role!),
    enabled: !!session?.user?.id && !!role,
  });

  const handleActivate = async () => {
    if (!role || !session?.user) return;
    setStarting(true);
    try {
      const result = await startEmbeddedCheckout(BADGE_PLANS[role].plan, {
        userId: session.user.id,
        email: session.user.email ?? "",
      });
      setEmbedded(result);
      setStarting(false);
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Couldn't start checkout."
      );
      setStarting(false);
    }
  };

  const meta = role ? BADGE_PLANS[role] : null;
  const selfPath = `/badge/activate?role=${role ?? "coach"}`;

  return (
    <div className="flex min-h-screen flex-col bg-background">
      {embedded && (
        <EmbeddedCheckoutSheet
          clientSecret={embedded.clientSecret}
          publishableKey={embedded.publishableKey}
          brief={
            role
              ? {
                  title: `${BADGE_PLANS[role].label} · Annual`,
                  price: BADGE_PLANS[role].price,
                  cadence: "/year",
                  note: "Renews once a year · cancel anytime",
                  perks: BADGE_PERKS[role],
                  refundDays: 14,
                }
              : undefined
          }
          onClose={() => setEmbedded(null)}
          onComplete={() => {
            setEmbedded(null);
            window.location.href = "/billing/success?embedded=1";
          }}
        />
      )}
      <PublicNav />

      <main className="flex flex-1 items-center justify-center px-4 pb-16 pt-32 sm:px-6">
        <div className="w-full max-w-md rounded-[32px] border border-border bg-card p-8 text-center sm:p-10">
          {!role ? (
            <>
              <ShieldCheck className="mx-auto mb-5 h-12 w-12 text-muted-foreground" />
              <h1 className="font-display text-[24px] font-extrabold">
                Activate your approved role
              </h1>
              <p className="mt-3 text-[15px] leading-relaxed text-muted-foreground">
                Pick the role you were approved for.
              </p>
              <div className="mt-6 space-y-3">
                {(Object.keys(BADGE_PLANS) as BadgeRole[]).map((r) => (
                  <Button
                    key={r}
                    variant="outline"
                    className="h-12 w-full rounded-full text-[15px] font-semibold"
                    asChild
                  >
                    <Link to={`/badge/activate?role=${r}`}>
                      {BADGE_PLANS[r].label} · {BADGE_PLANS[r].price}/yr
                    </Link>
                  </Button>
                ))}
              </div>
            </>
          ) : loading ? (
            <>
              <Loader2 className="mx-auto mb-5 h-10 w-10 animate-spin text-muted-foreground" />
              <h1 className="font-display text-[24px] font-extrabold">
                Checking your application…
              </h1>
            </>
          ) : !session ? (
            <>
              <ShieldCheck className="mx-auto mb-5 h-12 w-12 text-muted-foreground" />
              <h1 className="font-display text-[24px] font-extrabold">
                Sign in to activate your {meta?.label} tools
              </h1>
              <p className="mt-3 text-[15px] leading-relaxed text-muted-foreground">
                Use the same account you applied with so access activates for the
                right account.
              </p>
              <Button
                className="mt-7 h-12 w-full rounded-full text-[15px] font-semibold"
                asChild
              >
                <Link to={`/auth?next=${encodeURIComponent(selfPath)}`}>
                  Sign in
                </Link>
              </Button>
            </>
          ) : state.isPending ? (
            <>
              <Loader2 className="mx-auto mb-5 h-10 w-10 animate-spin text-muted-foreground" />
              <h1 className="font-display text-[24px] font-extrabold">
                Checking your application…
              </h1>
            </>
          ) : state.data?.active ? (
            <>
              <BadgeCheck className="mx-auto mb-5 h-12 w-12 text-foreground" />
              <h1 className="font-display text-[24px] font-extrabold">
                Your {meta?.label} tools are live
              </h1>
              <p className="mt-3 text-[15px] leading-relaxed text-muted-foreground">
                Nothing else to do—your approved tools are active. The subscription
                renews once a year.
              </p>
              <Button
                className="mt-7 h-12 w-full rounded-full text-[15px] font-semibold"
                asChild
              >
                <Link to="/">Open Whisper</Link>
              </Button>
            </>
          ) : state.data?.application === "approved" ? (
            <>
              <Sparkles className="mx-auto mb-5 h-12 w-12 text-foreground" />
              <h1 className="font-display text-[26px] font-extrabold">
                You're approved!
              </h1>
              <p className="mt-2 text-[13px] font-bold uppercase tracking-wider text-muted-foreground">
                {meta?.label} · {meta?.price}/year
              </p>
              <p className="mt-4 text-[15px] leading-relaxed text-muted-foreground">
                A real person reviewed and approved your application. Activate
                your role tools. Professional roles appear as plain profile
                details; identity indicators are separate.
              </p>
              <p className="mt-3 text-[13px] text-muted-foreground">
                {meta?.blurb}
              </p>
              {role && (
                <div className="mt-5 space-y-2 rounded-2xl border border-border bg-secondary/30 p-4 text-left">
                  <p className="text-[12px] font-bold uppercase tracking-wider text-muted-foreground">
                    What you get
                  </p>
                  {BADGE_PERKS[role].map((perk) => (
                    <div key={perk} className="flex items-start gap-2">
                      <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-emerald-500" />
                      <p className="text-[13.5px] leading-snug">{perk}</p>
                    </div>
                  ))}
                </div>
              )}
              <Button
                className="mt-7 h-12 w-full rounded-full text-[15px] font-semibold"
                onClick={handleActivate}
                disabled={starting}
              >
                {starting ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <BadgeCheck className="h-4 w-4" />
                )}
                Activate for {meta?.price}/year
              </Button>
              <p className="mt-4 text-[12.5px] text-muted-foreground">
                Cancel renewal anytime—paid access lasts through the paid period.
              </p>
            </>
          ) : state.data?.application === "pending" ? (
            <>
              <Clock className="mx-auto mb-5 h-12 w-12 text-muted-foreground" />
              <h1 className="font-display text-[24px] font-extrabold">
                Your application is in review
              </h1>
              <p className="mt-3 text-[15px] leading-relaxed text-muted-foreground">
                A real person reviews every {meta?.label} application. You'll
                get an email the moment you're approved — payment happens after
                that, never before.
              </p>
            </>
          ) : state.data?.application === "denied" ? (
            <>
              <CircleAlert className="mx-auto mb-5 h-12 w-12 text-muted-foreground" />
              <h1 className="font-display text-[24px] font-extrabold">
                This application wasn't approved
              </h1>
              <p className="mt-3 text-[15px] leading-relaxed text-muted-foreground">
                You weren't charged anything. You can strengthen your
                credentials and apply again from the app.
              </p>
            </>
          ) : (
            <>
              <ShieldCheck className="mx-auto mb-5 h-12 w-12 text-muted-foreground" />
              <h1 className="font-display text-[24px] font-extrabold">
                Apply first, pay after approval
              </h1>
              <p className="mt-3 text-[15px] leading-relaxed text-muted-foreground">
                We don't see a {meta?.label} application on this account.
                Applying is free — and you only pay once you're approved.
              </p>
              <Button
                className="mt-7 h-12 w-full rounded-full text-[15px] font-semibold"
                asChild
              >
                <Link to={`/apply/${role}`}>Apply now — it's free</Link>
              </Button>
              <Button
                variant="outline"
                className="mt-3 h-12 w-full rounded-full text-[15px] font-semibold"
                asChild
              >
                <Link to={`/roles/${role}`}>Learn about {meta?.label}</Link>
              </Button>
            </>
          )}
        </div>
      </main>

      <PublicFooter />
    </div>
  );
}
