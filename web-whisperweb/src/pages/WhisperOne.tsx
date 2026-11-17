import { useEffect, useRef, useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import { useMutation } from "@tanstack/react-query";
import { toast } from "sonner";
import {
  ArrowRight,
  BarChart3,
  Check,
  ClipboardList,
  Loader2,
  Lock,
  Share2,
  Users,
  Zap,
} from "lucide-react";

import PublicNav from "@/components/PublicNav";
import PublicFooter from "@/components/PublicFooter";
import { OneBadge } from "@/components/OneBadge";
import { EmbeddedCheckoutSheet } from "@/components/EmbeddedCheckoutSheet";
import { Reveal } from "@/components/Reveal";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/hooks/useAuth";
import { cn } from "@/lib/utils";
import {
  ONE_PERKS,
  ONE_PLANS,
  startEmbeddedCheckout,
  type EmbeddedCheckoutResult,
  type WhisperOnePlan,
} from "@/lib/billing";

/**
 * Whisper One details page — same structure as the verified role detail
 * pages (/roles/coach etc.): hero with badge + price, intro, features grid,
 * how-it-works steps, honest comparison, FAQ, and role cross-links. The only
 * difference: One is instant, so checkout buttons live right in the hero.
 */

const INTRO: string[] = [
  "Whisper One is the practice ground. It's a sampler of the creator and coach kits in one instant membership — coach up to 3 clients, run Creator Studio Lite, share your stats on your wall, with no public membership marker.",
  "There's no application and no review. You buy it, it's live. The trade-off is honest: One can't charge clients through the app — paid coaching stays exclusive to verified Coaches, with the same application review and tool access.",
];

const INCLUDED: { icon: React.ReactNode; title: string; desc: string }[] = [
  {
    icon: <Users className="h-5 w-5" />,
    title: "Coach tools — 3 client slots",
    desc: "Take on up to 3 clients at a time. Build programs, send macros and daily targets, and run check-ins right in your DMs.",
  },
  {
    icon: <BarChart3 className="h-5 w-5" />,
    title: "Creator Studio Lite",
    desc: "A lighter cut of the verified Creator Studio: post performance, audience trends, and your top whispers — enough to learn what works.",
  },
  {
    icon: <Share2 className="h-5 w-5" />,
    title: "Stats on your wall",
    desc: "Share your stat sheet on your profile whenever you want. Show your PRs, training volume, and streaks — or keep them private.",
  },
  {
    icon: <ClipboardList className="h-5 w-5" />,
    title: "Programs & macros in DMs",
    desc: "The same structured program and nutrition embeds verified coaches use — applied by your clients with one tap.",
  },
  {
    icon: <Zap className="h-5 w-5" />,
    title: "Longer posts",
    desc: "Whisper One raises your character limit from 500 to 1,000, so training write-ups don't get cut short.",
  },
  {
    icon: <Lock className="h-5 w-5" />,
    title: "No paywalls — by design",
    desc: "Whisper One can't charge clients through the app. Paywalled coaching stays exclusive to verified Coaches, with the same application review and tool access.",
  },
];

const HOW_IT_WORKS: { title: string; desc: string }[] = [
  {
    title: "Get it today",
    desc: "No application, no review queue. Pick monthly or annual and check out — the membership is live the moment payment clears.",
  },
  {
    title: "Tools, not a public label",
    desc: "Your membership unlocks the kit without adding a public marker to your name. Identity indicators are separate from subscriptions.",
  },
  {
    title: "Build a real track record",
    desc: "Coach up to 3 clients, study your numbers in Studio Lite, and put your stats on your wall. Every check-in becomes proof.",
  },
  {
    title: "Upgrade when you're ready",
    desc: "Apply for a verified role from Settings → Verification. Your One history — real clients, real analytics — is exactly what reviewers look for.",
  },
];

const COMPARISON: [string, string, string][] = [
  ["Access", "Instant — buy it today", "Application, reviewed by a real person"],
  ["Profile", "No public membership marker", "Professional role as plain profile text"],
  ["Client slots", "Up to 3 at a time", "Unlimited (verified Coach)"],
  ["Paywalled coaching", "—", "Set your rates, get paid (Coach)"],
  ["Studio", "Creator Studio Lite", "Full Studio + 1.6× reach boost"],
  ["Profile niche", "—", "Your niche under your name (Creator)"],
  ["Character limit", "1,000", "1,500"],
  ["Price", "$14.99/mo or $119.99/yr", "$99.99–$249.99/yr, billed if approved"],
];

const FAQ: { q: string; a: string }[] = [
  {
    q: "Does membership add a public badge?",
    a: "No. Whisper One unlocks tools, not a public reputation marker. Application-based roles keep their existing review requirements and appear as plain profile details. Any identity indicator is separate and is not a safety guarantee.",
  },
  {
    q: "Why can't I paywall clients on Whisper One?",
    a: "Charging people for coaching requires the credential review that verified Coaches go through. Whisper One is the practice ground: coach up to 3 clients, build your track record, then apply for Coach when you're ready to charge.",
  },
  {
    q: "What happens when my 3 client slots are full?",
    a: "New coaching requests wait until a slot opens, or you can upgrade by applying for the verified Coach role — approved Coaches get unlimited clients.",
  },
  {
    q: "Can I cancel anytime?",
    a: "Yes. Whisper One is a subscription you can cancel whenever you like — you keep the perks until the end of your billing period. See the refund policy in our Terms.",
  },
  {
    q: "Does Whisper One help my verified application?",
    a: "It doesn't skip the review, but a Whisper One history — real clients, real check-ins, real analytics — is exactly the track record reviewers look for.",
  },
];

const OTHER_ROLES: { key: string; name: string }[] = [
  { key: "creator", name: "Verified Creator" },
  { key: "coach", name: "Verified Coach" },
];

function CheckoutButtons({
  onDark = false,
  autoResume = false,
}: {
  onDark?: boolean;
  autoResume?: boolean;
}) {
  const { user, loading } = useAuth();
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const resumedRef = useRef<boolean>(false);
  const [embedded, setEmbedded] = useState<EmbeddedCheckoutResult | null>(null);

  const checkout = useMutation({
    mutationFn: (plan: WhisperOnePlan) =>
      startEmbeddedCheckout(plan, {
        userId: user?.id,
        email: user?.email ?? undefined,
      }),
    onSuccess: (result) => setEmbedded(result),
    onError: (error: Error) => toast(error.message),
  });

  /**
   * Buying Whisper One requires an account so the subscription has a home.
   * Signed-out visitors are sent to sign up first, then bounced back here
   * where checkout resumes automatically via the ?checkout= param.
   */
  const buy = (plan: WhisperOnePlan): void => {
    if (loading) return;
    if (!user) {
      toast("Create an account or sign in first — your membership needs a home.");
      const next = encodeURIComponent(`/one?checkout=${plan}`);
      navigate(`/auth?mode=signup&next=${next}`);
      return;
    }
    checkout.mutate(plan);
  };

  useEffect(() => {
    if (!autoResume || resumedRef.current || loading) return;
    const pending = searchParams.get("checkout");
    if (pending !== "one-monthly" && pending !== "one-annual") return;
    resumedRef.current = true;
    const nextParams = new URLSearchParams(searchParams);
    nextParams.delete("checkout");
    setSearchParams(nextParams, { replace: true });
    if (user) {
      checkout.mutate(pending);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [autoResume, loading, user, searchParams]);

  const [selected, setSelected] = useState<WhisperOnePlan>("one-annual");

  const PLAN_META: Record<
    WhisperOnePlan,
    { label: string; sub: string; badge: string | null }
  > = {
    "one-annual": {
      label: "Annual",
      sub: "12 months \u00b7 works out to $10/mo",
      badge: "SAVE 33%",
    },
    "one-monthly": {
      label: "Monthly",
      sub: "Billed monthly \u00b7 cancel anytime",
      badge: null,
    },
  };

  const briefPlan: WhisperOnePlan = checkout.variables ?? selected;

  return (
    <>
    {embedded && (
      <EmbeddedCheckoutSheet
        clientSecret={embedded.clientSecret}
        publishableKey={embedded.publishableKey}
        brief={{
          title: `Whisper One · ${briefPlan === "one-annual" ? "Annual" : "Monthly"}`,
          price: ONE_PLANS[briefPlan].price,
          cadence: ONE_PLANS[briefPlan].detail,
          note: ONE_PLANS[briefPlan].blurb,
          perks: ONE_PERKS,
          refundDays: 14,
        }}
        onClose={() => setEmbedded(null)}
        onComplete={() => {
          setEmbedded(null);
          navigate("/billing/success?embedded=1");
        }}
      />
    )}
    <div className="mx-auto flex w-full max-w-md flex-col gap-3">
      {/* Plan cards */}
      {("one-annual one-monthly".split(" ") as WhisperOnePlan[]).map((plan) => {
        const meta = PLAN_META[plan];
        const isSelected = selected === plan;
        return (
          <button
            key={plan}
            type="button"
            onClick={() => setSelected(plan)}
            className={cn(
              "flex w-full items-center gap-3.5 rounded-[18px] border px-4 py-3.5 text-left transition-all",
              isSelected
                ? "border-emerald-500 bg-emerald-500/[0.06] ring-1 ring-emerald-500"
                : "border-border bg-card hover:border-foreground/25",
              onDark && !isSelected && "border-primary-foreground/20 bg-transparent"
            )}
          >
            {/* Radio */}
            <span
              className={cn(
                "flex h-[22px] w-[22px] shrink-0 items-center justify-center rounded-full border-2 transition-colors",
                isSelected ? "border-emerald-500" : "border-border",
                onDark && !isSelected && "border-primary-foreground/30"
              )}
            >
              {isSelected && (
                <span className="h-3 w-3 rounded-full bg-emerald-500" />
              )}
            </span>
            <span className="min-w-0 flex-1">
              <span className="flex items-center gap-2">
                <span className={cn("text-[15.5px] font-bold", onDark && "text-primary-foreground")}>
                  {meta.label}
                </span>
                {meta.badge && (
                  <span className="rounded-full bg-emerald-500 px-2 py-0.5 text-[10px] font-black text-white">
                    {meta.badge}
                  </span>
                )}
              </span>
              <span className={cn("block text-[12px] text-muted-foreground", onDark && "text-primary-foreground/60")}>
                {meta.sub}
              </span>
            </span>
            <span className="text-right">
              <span className={cn("block text-[16px] font-extrabold", onDark && "text-primary-foreground")}>
                {ONE_PLANS[plan].price}
              </span>
              <span className={cn("block text-[11px] text-muted-foreground", onDark && "text-primary-foreground/60")}>
                {ONE_PLANS[plan].detail.replace("/", "per ")}
              </span>
            </span>
          </button>
        );
      })}

      {/* Subscribe */}
      <Button
        size="lg"
        disabled={checkout.isPending}
        onClick={() => buy(selected)}
        className={cn(
          "h-14 w-full rounded-full text-[16px] font-bold",
          onDark && "bg-background text-foreground hover:bg-background/90"
        )}
      >
        {checkout.isPending ? (
          <>
            <Loader2 className="h-5 w-5 animate-spin" />
            Opening secure checkout…
          </>
        ) : (
          <>
            Continue — {ONE_PLANS[selected].price}
            {ONE_PLANS[selected].detail}
          </>
        )}
      </Button>

      {/* Trust row */}
      <div
        className={cn(
          "flex items-center justify-center gap-4 text-[11.5px] font-semibold text-muted-foreground",
          onDark && "text-primary-foreground/60"
        )}
      >
        <span className="inline-flex items-center gap-1.5">
          <Lock className="h-3 w-3" />
          Secure Stripe checkout
        </span>
        <span className="inline-flex items-center gap-1.5">
          <Check className="h-3 w-3" />
          Cancel anytime
        </span>
      </div>
    </div>
    </>
  );
}

export default function WhisperOne() {
  return (
    <div className="min-h-screen bg-background">
      <PublicNav />

      <main>
        {/* Hero — same structure as the role detail pages */}
        <section className="px-4 pb-10 pt-32 sm:px-6 lg:px-8 lg:pt-40">
          <div className="mx-auto max-w-4xl text-center">
            <div className="mx-auto mb-6 flex h-20 w-20 items-center justify-center rounded-[24px] border border-border bg-card">
              <OneBadge size={44} />
            </div>
            <h1 className="font-display text-[36px] font-extrabold leading-[1.1] tracking-tight sm:text-[50px] lg:text-[60px]">
              Whisper One
            </h1>
            <p className="mt-4 text-[19px] font-semibold text-muted-foreground sm:text-[22px]">
              Every toolkit, today.
            </p>
            <div className="mt-6 inline-flex items-baseline gap-1 rounded-full border border-border bg-card px-6 py-3">
              <span className="text-[28px] font-extrabold tracking-tight">
                {ONE_PLANS["one-monthly"].price}
              </span>
              <span className="text-[15px] text-muted-foreground">
                /month · or {ONE_PLANS["one-annual"].price}/year
              </span>
            </div>
            <p className="mt-3 text-[13.5px] text-muted-foreground">
              No application — instant membership. Cancel anytime.
            </p>
            <div className="mx-auto mt-8 max-w-2xl space-y-4 text-left">
              {INTRO.map((paragraph) => (
                <p
                  key={paragraph}
                  className="text-[16.5px] leading-relaxed text-muted-foreground"
                >
                  {paragraph}
                </p>
              ))}
            </div>
            <div className="mt-8">
              <CheckoutButtons autoResume />
            </div>
            <p className="mt-4 text-[13px] text-muted-foreground">
              Annual saves two months · verified roles still require an
              application
            </p>
          </div>
        </section>

        {/* Features in depth — mirrors "Everything {role} unlocks" */}
        <section className="px-4 py-10 sm:px-6 lg:px-8 lg:py-14">
          <div className="mx-auto max-w-5xl">
            <Reveal variant="fade">
              <h2 className="mb-10 text-center font-display text-[26px] font-extrabold sm:text-[34px]">
                Everything Whisper One unlocks
              </h2>
            </Reveal>
            <Reveal stagger className="grid gap-4 sm:grid-cols-2">
              {INCLUDED.map((feature) => (
                <div
                  key={feature.title}
                  className="rounded-3xl border border-border bg-card p-6"
                >
                  <div className="mb-4 flex h-11 w-11 items-center justify-center rounded-2xl bg-secondary">
                    {feature.icon}
                  </div>
                  <h3 className="text-[17px] font-bold">{feature.title}</h3>
                  <p className="mt-1.5 text-[14.5px] leading-relaxed text-muted-foreground">
                    {feature.desc}
                  </p>
                </div>
              ))}
            </Reveal>
          </div>
        </section>

        {/* How it works — mirrors "How the application works" */}
        <section className="border-y border-border px-4 py-12 sm:px-6 lg:px-8 lg:py-16">
          <div className="mx-auto max-w-4xl">
            <Reveal variant="fade">
              <h2 className="mb-10 text-center font-display text-[26px] font-extrabold sm:text-[34px]">
                How Whisper One works
              </h2>
            </Reveal>
            <Reveal stagger className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              {HOW_IT_WORKS.map((step, index) => (
                <div
                  key={step.title}
                  className="rounded-3xl border border-border bg-card p-5"
                >
                  <span className="mb-3 flex h-9 w-9 items-center justify-center rounded-full bg-foreground text-[15px] font-extrabold text-primary-foreground">
                    {index + 1}
                  </span>
                  <h3 className="text-[15px] font-bold leading-tight">
                    {step.title}
                  </h3>
                  <p className="mt-1.5 text-[13.5px] leading-snug text-muted-foreground">
                    {step.desc}
                  </p>
                </div>
              ))}
            </Reveal>
          </div>
        </section>

        {/* One vs verified — the honest comparison */}
        <section className="px-4 py-12 sm:px-6 lg:px-8 lg:py-16">
          <div className="mx-auto max-w-4xl">
            <Reveal variant="fade">
              <h2 className="mb-3 text-center font-display text-[26px] font-extrabold sm:text-[34px]">
                One vs. the verified roles
              </h2>
              <p className="mx-auto mb-10 max-w-2xl text-center text-[16px] text-muted-foreground">
                Whisper One is the fast lane, not a shortcut around
                verification. Here's the honest difference.
              </p>
            </Reveal>
            <Reveal>
            <div className="overflow-hidden rounded-[24px] border border-border bg-card">
              <div className="hidden grid-cols-[1.1fr_1fr_1fr] bg-secondary text-[12.5px] font-bold uppercase tracking-wider text-muted-foreground sm:grid">
                <div className="px-4 py-3">Feature</div>
                <div className="flex items-center gap-1.5 px-4 py-3">
                  <OneBadge size={12} /> Whisper One
                </div>
                <div className="px-4 py-3">Verified roles</div>
              </div>
              {COMPARISON.map(([feature, one, verified]) => (
                <div
                  key={feature}
                  className="border-t border-border sm:grid sm:grid-cols-[1.1fr_1fr_1fr] sm:text-[14px]"
                >
                  {/* Mobile: stacked */}
                  <div className="px-4 py-3 sm:hidden">
                    <p className="text-[13px] font-bold">{feature}</p>
                    <div className="mt-2 grid grid-cols-2 gap-2 text-[12px]">
                      <div>
                        <span className="flex items-center gap-1 text-[10px] font-bold uppercase tracking-wider text-muted-foreground">
                          <OneBadge size={10} /> One
                        </span>
                        <p className="text-muted-foreground">{one}</p>
                      </div>
                      <div>
                        <span className="text-[10px] font-bold uppercase tracking-wider text-muted-foreground">Verified</span>
                        <p className="text-muted-foreground">{verified}</p>
                      </div>
                    </div>
                  </div>
                  {/* Desktop */}
                  <div className="hidden px-4 py-3.5 font-semibold sm:block">{feature}</div>
                  <div className="hidden px-4 py-3.5 text-muted-foreground sm:block">{one}</div>
                  <div className="hidden px-4 py-3.5 text-muted-foreground sm:block">
                    {verified}
                  </div>
                </div>
              ))}
            </div>
            </Reveal>
            <div className="mt-6 rounded-2xl border border-border bg-card p-5 text-center">
              <p className="text-[15px] text-muted-foreground">
                <strong className="text-foreground">The upgrade path:</strong>{" "}
                start on Whisper One, build a real client and content history,
                then apply for a verified role from Settings → Verification
                whenever you're ready.{" "}
                <Link
                  to="/monetization"
                  className="font-semibold text-foreground underline-offset-4 hover:underline"
                >
                  See how monetization works
                </Link>
                .
              </p>
            </div>
          </div>
        </section>

        {/* FAQ — mirrors "Common questions" */}
        <section className="border-t border-border px-4 py-12 sm:px-6 lg:px-8 lg:py-16">
          <div className="mx-auto max-w-3xl">
            <Reveal variant="fade">
              <h2 className="mb-8 text-center font-display text-[26px] font-extrabold sm:text-[32px]">
                Common questions
              </h2>
            </Reveal>
            <Reveal stagger className="space-y-4">
              {FAQ.map(({ q, a }) => (
                <div key={q} className="rounded-2xl border border-border bg-card p-5">
                  <h3 className="text-[16px] font-bold">{q}</h3>
                  <p className="mt-2 text-[14.5px] leading-relaxed text-muted-foreground">
                    {a}
                  </p>
                </div>
              ))}
            </Reveal>
          </div>
        </section>

        {/* Other paths — mirrors the role cross-links */}
        <section className="px-4 pb-6 sm:px-6 lg:px-8">
          <div className="mx-auto flex max-w-3xl flex-wrap items-center justify-center gap-3">
            {OTHER_ROLES.map((other) => (
              <Link
                key={other.key}
                to={`/roles/${other.key}`}
                className="inline-flex items-center gap-2 rounded-full border border-border bg-card px-5 py-2.5 text-[14px] font-semibold transition-colors hover:bg-secondary"
              >
                Explore {other.name}
                <ArrowRight className="h-4 w-4" />
              </Link>
            ))}
            <Link
              to="/monetization"
              className="inline-flex items-center gap-2 rounded-full border border-border bg-card px-5 py-2.5 text-[14px] font-semibold transition-colors hover:bg-secondary"
            >
              Compare all packages
              <ArrowRight className="h-4 w-4" />
            </Link>
          </div>
        </section>

        {/* CTA */}
        <section className="px-4 py-12 pb-20 sm:px-6 lg:px-8 lg:py-16">
          <Reveal variant="scale" className="mx-auto max-w-3xl rounded-[24px] bg-foreground p-7 text-center text-primary-foreground sm:rounded-[32px] sm:p-14">
            <div className="mx-auto mb-5 flex h-16 w-16 items-center justify-center rounded-[20px] bg-primary-foreground/10">
              <OneBadge size={30} />
            </div>
            <h2 className="font-display text-[24px] font-extrabold sm:text-[40px]">
              Start everything today.
            </h2>
            <p className="mx-auto mt-4 max-w-xl text-[17px] text-primary-foreground/80">
              {ONE_PLANS["one-monthly"].price}
              {ONE_PLANS["one-monthly"].detail} or {ONE_PLANS["one-annual"].price}
              {ONE_PLANS["one-annual"].detail} — no application, cancel anytime.
            </p>
            <div className="mt-8 flex justify-center">
              <CheckoutButtons onDark />
            </div>
            <p className="mt-5 flex items-center justify-center gap-1.5 text-[13px] text-primary-foreground/60">
              <Check className="h-4 w-4" />
              Secure checkout by Stripe · covered by our{" "}
              <Link to="/terms" className="underline underline-offset-2">
                refund policy
              </Link>
            </p>
          </Reveal>
        </section>
      </main>

      <PublicFooter />
    </div>
  );
}
