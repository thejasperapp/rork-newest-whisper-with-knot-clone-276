import { Link } from "react-router-dom";
import {
  ArrowRight,
  BadgeCheck,
  Banknote,
  BarChart3,
  Dumbbell,
  Handshake,
  Megaphone,
  PenLine,
  Sparkles,
  Star,
  TrendingUp,
} from "lucide-react";

import PublicNav from "@/components/PublicNav";
import PublicFooter from "@/components/PublicFooter";
import { Reveal } from "@/components/Reveal";
import { Button } from "@/components/ui/button";
import { usePageMeta } from "@/hooks/usePageMeta";

/**
 * The unified earn/grow hub — one clear ladder from "just joined" to
 * "getting paid", replacing the previous maze of Monetization / Brands /
 * Coach Studio silos.
 */

interface LadderStep {
  n: number;
  icon: React.ReactNode;
  title: string;
  blurb: string;
  cta: string;
  to: string;
}

const LADDER: LadderStep[] = [
  {
    n: 1,
    icon: <BadgeCheck className="h-6 w-6" />,
    title: "Get verified",
    blurb:
      "Apply for a Creator, Coach, or Athlete seal. A real person reviews every application — the badge tells everyone you're legit, and unlocks the pro tools for your role.",
    cta: "Compare verified roles",
    to: "/monetization",
  },
  {
    n: 2,
    icon: <Star className="h-6 w-6" />,
    title: "Get featured",
    blurb:
      "Verified profiles can be spotlighted on the Whisper team pages and in-app discovery rails. Featured creators get seen by every new member who walks in the door.",
    cta: "See featured profiles",
    to: "/team",
  },
  {
    n: 3,
    icon: <Handshake className="h-6 w-6" />,
    title: "Get sponsored",
    blurb:
      "Brands post real sponsorship opportunities with real budgets. Apply with your live profile stats, negotiate terms in-app, and every deal is escrow-protected.",
    cta: "Browse brand deals",
    to: "/brands",
  },
  {
    n: 4,
    icon: <Banknote className="h-6 w-6" />,
    title: "Get paid",
    blurb:
      "Coaching income, sponsorship payouts, and long-form articles — all run safely through the app with transparent fees. Your audience becomes your business.",
    cta: "How payouts work",
    to: "/monetization",
  },
];

const SURFACES = [
  {
    icon: <BarChart3 className="h-5 w-5" />,
    title: "Your numbers, live",
    blurb:
      "Explore your engagement — likes, comments, and posting consistency — and use Knot to help make sense of your next creative step.",
  },
  {
    icon: <Dumbbell className="h-5 w-5" />,
    title: "Coach Studio",
    blurb:
      "Verified coaches run whole client rosters through DMs — programs, macros, check-ins, and proposals, with payments handled in-app.",
  },
  {
    icon: <PenLine className="h-5 w-5" />,
    title: "Articles",
    blurb:
      "Long-form writing lives on whisper too. Publish articles that rank, build authority, and funnel readers to your profile.",
  },
  {
    icon: <Megaphone className="h-5 w-5" />,
    title: "Communities",
    blurb:
      "Own the conversation in your niche. Communities give your content a home base and your followers a place to gather.",
  },
];

export default function ForCreators() {
  usePageMeta(
    "For Creators",
    "The Whisper creator ladder — get verified, get featured, get sponsored, get paid. One clear path from your first post to a real business."
  );

  return (
    <div className="min-h-screen bg-background">
      <PublicNav />

      <main>
        {/* Hero */}
        <section className="px-4 pb-12 pt-32 sm:px-6 lg:px-8 lg:pt-40">
          <div className="mx-auto max-w-4xl text-center">
            <div className="inline-flex items-center gap-2 rounded-full border border-border bg-card px-4 py-1.5 text-[13px] font-medium text-muted-foreground">
              <TrendingUp className="h-4 w-4" />
              The creator ladder
            </div>
            <h1 className="mt-6 font-display text-[38px] font-extrabold leading-[1.1] tracking-tight sm:text-[52px] lg:text-[64px]">
              Turn your Whisper <br className="hidden sm:block" />
              into a business.
            </h1>
            <p className="mx-auto mt-6 max-w-2xl text-[18px] leading-relaxed text-muted-foreground sm:text-[20px]">
              Whisper isn't just where you post — it's where you get paid.
              Four steps, one place: verification, visibility, sponsorships,
              and payouts, with none of it scattered across other platforms.
            </p>
            <Button className="mt-8 h-13 rounded-full px-8 text-[15px] font-semibold" asChild>
              <Link to="/auth?mode=signup">
                Start the ladder
                <ArrowRight className="ml-1 h-4 w-4" />
              </Link>
            </Button>
          </div>
        </section>

        {/* The ladder */}
        <section className="px-4 py-10 sm:px-6 lg:px-8">
          <Reveal stagger className="mx-auto grid max-w-5xl gap-5 md:grid-cols-2">
            {LADDER.map((step) => (
              <div
                key={step.n}
                className="flex flex-col rounded-[28px] border border-border bg-card p-7"
              >
                <div className="flex items-center gap-3">
                  <span className="flex h-12 w-12 items-center justify-center rounded-2xl bg-secondary">
                    {step.icon}
                  </span>
                  <span className="font-display text-[13px] font-extrabold uppercase tracking-widest text-muted-foreground">
                    Step {step.n}
                  </span>
                </div>
                <h2 className="mt-4 font-display text-[24px] font-extrabold">
                  {step.title}
                </h2>
                <p className="mt-2 flex-1 text-[15px] leading-relaxed text-muted-foreground">
                  {step.blurb}
                </p>
                <Link
                  to={step.to}
                  className="mt-5 inline-flex items-center gap-1 text-[14px] font-semibold underline-offset-4 hover:underline"
                >
                  {step.cta} <ArrowRight className="h-4 w-4" />
                </Link>
              </div>
            ))}
          </Reveal>
        </section>

        {/* Surfaces that do the work */}
        <section className="border-y border-border px-4 py-14 sm:px-6 lg:px-8 lg:py-20">
          <div className="mx-auto max-w-6xl">
            <Reveal variant="fade" className="mb-10 text-center">
              <h2 className="font-display text-[28px] font-extrabold sm:text-[36px]">
                Tools that pull their weight
              </h2>
              <p className="mt-3 text-[17px] text-muted-foreground">
                Every surface in the app is built to compound your audience.
              </p>
            </Reveal>
            <Reveal stagger className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              {SURFACES.map((s) => (
                <div key={s.title} className="rounded-3xl border border-border bg-card p-6">
                  <div className="mb-4 flex h-11 w-11 items-center justify-center rounded-2xl bg-secondary">
                    {s.icon}
                  </div>
                  <h3 className="text-[17px] font-bold">{s.title}</h3>
                  <p className="mt-2 text-[14px] leading-relaxed text-muted-foreground">
                    {s.blurb}
                  </p>
                </div>
              ))}
            </Reveal>
          </div>
        </section>

        {/* CTA */}
        <section className="px-4 py-14 sm:px-6 lg:px-8 lg:py-20">
          <Reveal variant="scale" className="mx-auto max-w-3xl rounded-[24px] bg-foreground p-7 text-center text-primary-foreground sm:rounded-[32px] sm:p-14">
            <Sparkles className="mx-auto mb-5 h-8 w-8" />
            <h2 className="font-display text-[24px] font-extrabold sm:text-[36px]">
              Your audience is already here.
            </h2>
            <p className="mx-auto mt-4 max-w-xl text-[17px] text-primary-foreground/80">
              Join free, post real, and climb when you're ready — every rung
              of the ladder is application-based and human-reviewed.
            </p>
            <div className="mt-8 flex flex-col justify-center gap-3 sm:flex-row">
              <Button
                size="lg"
                className="h-13 rounded-full bg-background px-7 text-[15px] font-semibold text-foreground hover:bg-background/90"
                asChild
              >
                <Link to="/auth?mode=signup">
                  Create your account
                  <ArrowRight className="ml-1 h-4 w-4" />
                </Link>
              </Button>
              <Button
                size="lg"
                variant="outline"
                className="h-13 rounded-full border-primary-foreground/30 bg-transparent px-7 text-[15px] font-semibold text-primary-foreground hover:bg-primary-foreground/10 hover:text-primary-foreground"
                asChild
              >
                <Link to="/brands">Browse brand deals</Link>
              </Button>
            </div>
          </Reveal>
        </section>
      </main>

      <PublicFooter />
    </div>
  );
}
