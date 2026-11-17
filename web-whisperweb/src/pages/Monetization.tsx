import { Link } from "react-router-dom";
import {
  ArrowRight,
  BadgeDollarSign,
  BarChart3,
  Check,
  Dumbbell,
  Eye,
  ShieldCheck,
  Users,
} from "lucide-react";

import PublicNav from "@/components/PublicNav";
import PublicFooter from "@/components/PublicFooter";
import { OneBadge } from "@/components/OneBadge";
import { SealBadge } from "@/components/SealBadge";
import { Reveal } from "@/components/Reveal";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/hooks/useAuth";

function CoachSeal({ size = 16 }: { size?: number }) {
  return (
    <SealBadge size={size + 3} solid="#fa7321" shadowColor="#fa7321" title="Verified Coach">
      <Dumbbell style={{ width: size * 0.5, height: size * 0.5 }} strokeWidth={3} />
    </SealBadge>
  );
}

function VerifiedCheck({ size = 16 }: { size?: number }) {
  return (
    <SealBadge size={size + 2} colors={["#4aa8ff", "#2f86f0"]} shadowColor="#3399ff" title="Verified">
      <Check style={{ width: size * 0.5, height: size * 0.5 }} strokeWidth={3.5} />
    </SealBadge>
  );
}

interface EarnPath {
  id: string;
  badge: React.ReactNode;
  name: string;
  price: string;
  access: string;
  headline: string;
  points: string[];
  /** Route for the application deep link (role pages) or product page. */
  learnHref: string;
  isApplication: boolean;
}

const PATHS: EarnPath[] = [
  {
    id: "coach",
    badge: <CoachSeal size={20} />,
    name: "Verified Coach",
    price: "$249.99/yr · billed if approved",
    access: "Application",
    headline: "The only role that gets paid inside Whisper",
    points: [
      "Set your own rates and send coaching proposals straight into DMs",
      "Unlimited client slots with programs, macros, and check-in tracking",
      "Coach shown as plain profile text after the existing application review",
    ],
    learnHref: "/roles/coach",
    isApplication: true,
  },
  {
    id: "creator",
    badge: <VerifiedCheck size={19} />,
    name: "Verified Creator",
    price: "$99.99/yr · billed if approved",
    access: "Application",
    headline: "Turn reach into partnerships",
    points: [
      "Your niche — Athlete, Fitness, Music, Comedy — shown under your name on your profile",
      "1.6× algorithmic boost, trending priority, and long-form posts",
      "Creator Studio analytics and featured placement in the brand marketplace",
    ],
    learnHref: "/roles/creator",
    isApplication: true,
  },
  {
    id: "one",
    badge: <OneBadge size={18} />,
    name: "Whisper One",
    price: "$14.99/mo · instant",
    access: "No application",
    headline: "The practice ground",
    points: [
      "Coach up to 3 clients and build a real check-in history",
      "Creator Studio Lite to learn what content performs",
      "Paid coaching still requires an approved Coach application",
    ],
    learnHref: "/one",
    isApplication: false,
  },
];

const COMPARISON: [string, string, string, string][] = [
  ["Post whispers & replies", "✓", "✓", "✓"],
  ["Get help from Knot", "✓", "✓", "✓"],
  ["DMs & communities", "✓", "✓", "✓"],
  ["Character limit", "500", "1,500", "1,500"],
  ["Verified badge / role label", "—", "Blue check", "Badge / label"],
  ["Algorithmic boost", "—", "1.6×", "1.6×"],
  ["Trending priority", "—", "✓", "✓"],
  ["Verified-only DM filter", "—", "✓", "✓"],
  ["Coach Studio / client tools", "—", "—", "✓"],
  ["Charge clients through Whisper", "—", "—", "Coach only"],
];

const FAQ: { q: string; a: string }[] = [
  {
    q: "Are these subscriptions or one-time purchases?",
    a: "Verified badges are annual: Creator is $99.99/year, Coach is $249.99/year. You're only billed after your application is approved. Whisper One is $14.99/month or $119.99/year, instant. Free is free forever.",
  },
  {
    q: "How do I apply for a verified role?",
    a: "Create your account first, then go to Settings → Verified badges. Submit your credentials or creator links and pick your niche. The team reviews and approves manually — no auto-approvals.",
  },
  {
    q: "What do the coach tier dots mean?",
    a: "Every verified coach carries a tier dot for their coaching style — Tier 1 (red), Tier 2 (yellow), Tier 3 (green) — so you can see their experience level at a glance.",
  },
  {
    q: "Can I hold multiple roles at once?",
    a: "Yes. If you hold multiple verified roles, you get all of their perks. Professional roles appear as plain profile details, with at most one separate identity or staff indicator.",
  },
  {
    q: "What is Whisper One?",
    a: "A no-application membership: 3 coaching client slots, Creator Studio Lite, and stat sharing on your wall, without a public membership badge. It can't paywall clients — that stays exclusive to verified Coaches.",
  },
  {
    q: "What's the refund policy?",
    a: "Every paid plan has a 14-day money-back window on the first charge and on renewals. Application-based roles are only billed after approval, so a declined application never costs anything. Full details are in our Terms.",
  },
  {
    q: "Does the free tier see ads?",
    a: "No. Whisper has no ads. The free tier is fully usable; paid paths add professional tools, reach, and earning ability.",
  },
];

const STEPS: { title: string; desc: string }[] = [
  {
    title: "Join free & build proof",
    desc: "Post your training, coach a friend on Whisper One, grow a following — reviewers look at what you've actually done.",
  },
  {
    title: "Apply in Settings → Verification",
    desc: "Pick your role and submit credentials, sport history, or creator links right from the app.",
  },
  {
    title: "A real person reviews it",
    desc: "No auto-approvals. Coaching credentials get the deepest review because Coaches charge clients.",
  },
  {
    title: "Approved → badge live → start earning",
    desc: "You're only billed once you're approved. Coaches can send paid proposals the same day.",
  },
];

export default function Monetization() {
  const { session } = useAuth();

  const applyHref = session ? "/settings" : "/auth?mode=signup";
  const applyLabel = session
    ? "Open your application — Settings → Verification"
    : "Join free to apply";

  return (
    <div className="min-h-screen bg-background">
      <PublicNav />

      <main>
        {/* Hero */}
        <section className="px-4 pb-12 pt-32 sm:px-6 lg:px-8 lg:pt-40">
          <div className="mx-auto max-w-4xl text-center">
            <div className="inline-flex items-center gap-2 rounded-full border border-border bg-card px-4 py-1.5 text-[13px] font-medium text-muted-foreground">
              <BadgeDollarSign className="h-4 w-4" />
              Monetization on Whisper
            </div>
            <h1 className="mt-6 font-display text-[38px] font-extrabold leading-[1.1] tracking-tight sm:text-[52px] lg:text-[62px]">
              Get paid for the training you already share.
            </h1>
            <p className="mx-auto mt-6 max-w-2xl text-[18px] leading-relaxed text-muted-foreground sm:text-[20px]">
              Whisper has four paths to earning — three verified roles you
              apply for, and one instant membership to build your track record
              on. Every path is designed so the people charging money are the
              people who've been vetted.
            </p>
            {session && (
              <p className="mx-auto mt-4 max-w-xl rounded-full border border-border bg-card px-5 py-2 text-[14px] text-muted-foreground">
                You're signed in — each path below links straight to its
                application.
              </p>
            )}
          </div>
        </section>

        {/* Paths */}
        <section className="px-4 py-12 sm:px-6 lg:px-8">
          <div className="mx-auto max-w-6xl">
            <div className="grid gap-4 md:grid-cols-2">
              {PATHS.map((path) => (
                <div
                  key={path.id}
                  className="flex flex-col rounded-[28px] border border-border bg-card p-6 sm:p-7"
                >
                  <div className="flex items-center gap-3">
                    <div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-secondary">
                      {path.badge}
                    </div>
                    <div className="min-w-0 flex-1">
                      <h3 className="text-[19px] font-extrabold leading-tight">
                        {path.name}
                      </h3>
                      <p className="text-[13px] text-muted-foreground">
                        {path.price}
                      </p>
                    </div>
                    <span className="shrink-0 rounded-full bg-secondary px-3 py-1 text-[11px] font-bold uppercase tracking-wide text-muted-foreground">
                      {path.access}
                    </span>
                  </div>
                  <p className="mt-4 text-[16px] font-bold">{path.headline}</p>
                  <ul className="mt-3 flex-1 space-y-2.5">
                    {path.points.map((point) => (
                      <li
                        key={point}
                        className="flex items-start gap-2.5 text-[14.5px] leading-snug text-muted-foreground"
                      >
                        <Check
                          className="mt-0.5 h-4 w-4 shrink-0 text-foreground"
                          strokeWidth={3}
                        />
                        {point}
                      </li>
                    ))}
                  </ul>
                  <div className="mt-6 flex flex-col gap-2 sm:flex-row">
                    <Button className="h-11 flex-1 rounded-full text-[14px] font-semibold" asChild>
                      <Link to={path.isApplication ? applyHref : path.learnHref}>
                        {path.isApplication ? applyLabel : "Explore Whisper One"}
                        <ArrowRight className="ml-1 h-4 w-4" />
                      </Link>
                    </Button>
                    <Button
                      variant="outline"
                      className="h-11 rounded-full px-5 text-[14px] font-semibold"
                      asChild
                    >
                      <Link to={path.learnHref}>Details</Link>
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* How it works */}
        <section className="border-y border-border px-4 py-12 sm:px-6 lg:px-8 lg:py-16">
          <div className="mx-auto max-w-5xl">
            <Reveal variant="fade">
              <h2 className="mb-10 text-center font-display text-[26px] font-extrabold sm:text-[34px]">
                From first post to first payout
              </h2>
            </Reveal>
            <Reveal stagger className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              {STEPS.map((step, index) => (
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

        {/* Comparison */}
        <section className="px-4 py-12 sm:px-6 lg:px-8 lg:py-16">
          <div className="mx-auto max-w-5xl">
            <Reveal variant="fade">
              <h2 className="mb-3 text-center font-display text-[26px] font-extrabold sm:text-[34px]">
                What each path unlocks in the app
              </h2>
              <p className="mx-auto mb-10 max-w-2xl text-center text-[16px] text-muted-foreground">
                Everyone starts free. Creator is $99.99/year, Coach is
                $249.99/year — billed only if approved. Whisper One is
                $14.99/month, instant.
              </p>
            </Reveal>
            <Reveal>
              <div className="overflow-hidden rounded-[24px] border border-border bg-card">
                <div className="hidden grid-cols-4 bg-secondary text-[13px] font-bold uppercase tracking-wider text-muted-foreground sm:grid">
                  <div className="px-4 py-3">Feature</div>
                  <div className="px-4 py-3 text-center">Free</div>
                  <div className="px-4 py-3 text-center">Creator</div>
                  <div className="px-4 py-3 text-center">Coach</div>
                </div>
                {COMPARISON.map(([feature, free, creator, pro]) => (
                  <div
                    key={feature}
                    className="border-t border-border sm:grid sm:grid-cols-4 sm:text-[14.5px]"
                  >
                    {/* Mobile: stacked label + values */}
                    <div className="px-4 py-3 sm:hidden">
                      <p className="text-[13px] font-bold">{feature}</p>
                      <div className="mt-2 grid grid-cols-3 gap-1 text-[12px]">
                        <div>
                          <span className="text-[10px] font-bold uppercase tracking-wider text-muted-foreground">Free</span>
                          <p className="text-muted-foreground">{free}</p>
                        </div>
                        <div>
                          <span className="text-[10px] font-bold uppercase tracking-wider text-muted-foreground">Creator</span>
                          <p className="text-muted-foreground">{creator}</p>
                        </div>
                        <div>
                          <span className="text-[10px] font-bold uppercase tracking-wider text-muted-foreground">Pro</span>
                          <p className="text-muted-foreground">{pro}</p>
                        </div>
                      </div>
                    </div>
                    {/* Desktop: row layout */}
                    <div className="hidden px-4 py-3.5 font-medium sm:block">{feature}</div>
                    <div className="hidden px-4 py-3.5 text-center text-muted-foreground sm:block">
                      {free}
                    </div>
                    <div className="hidden px-4 py-3.5 text-center text-muted-foreground sm:block">
                      {creator}
                    </div>
                    <div className="hidden px-4 py-3.5 text-center text-muted-foreground sm:block">
                      {pro}
                    </div>
                  </div>
                ))}
              </div>
            </Reveal>
          </div>
        </section>

        {/* FAQ */}
        <section className="border-t border-border px-4 py-12 sm:px-6 lg:px-8 lg:py-16">
          <div className="mx-auto max-w-3xl">
            <Reveal variant="fade">
              <h2 className="mb-10 text-center font-display text-[26px] font-extrabold sm:text-[34px]">
                Pricing questions
              </h2>
            </Reveal>
            <Reveal stagger className="space-y-4">
              {FAQ.map(({ q, a }) => (
                <div
                  key={q}
                  className="rounded-2xl border border-border bg-card p-5"
                >
                  <h3 className="text-[17px] font-bold">{q}</h3>
                  <p className="mt-2 text-[15px] leading-relaxed text-muted-foreground">
                    {a}
                  </p>
                </div>
              ))}
            </Reveal>
          </div>
        </section>

        {/* Trust strip */}
        <section className="px-4 py-12 sm:px-6 lg:px-8 lg:py-16">
          <Reveal stagger className="mx-auto grid max-w-5xl gap-4 sm:grid-cols-3">
            {[
              {
                icon: <ShieldCheck className="h-5 w-5" />,
                title: "Vetted earners only",
                desc: "Only approved Coaches can charge clients through Whisper. The role is plain profile text, not a guarantee of safety or outcomes.",
              },
              {
                icon: <Eye className="h-5 w-5" />,
                title: "Real numbers, no vanity",
                desc: "Studio analytics come from actual engagement — the same data reviewers and brands see.",
              },
              {
                icon: <Users className="h-5 w-5" />,
                title: "Start small, grow real",
                desc: "Whisper One's 3 client slots exist so you can prove yourself before you ever charge a dollar.",
              },
            ].map((item) => (
              <div
                key={item.title}
                className="flex items-start gap-3 rounded-3xl border border-border bg-card p-5"
              >
                <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-secondary">
                  {item.icon}
                </div>
                <div>
                  <h3 className="text-[15px] font-bold">{item.title}</h3>
                  <p className="mt-1 text-[13.5px] leading-snug text-muted-foreground">
                    {item.desc}
                  </p>
                </div>
              </div>
            ))}
          </Reveal>
        </section>

        {/* CTA */}
        <section className="px-4 pb-20 sm:px-6 lg:px-8">
          <Reveal variant="scale" className="mx-auto max-w-3xl rounded-[24px] bg-foreground p-7 text-center text-primary-foreground sm:rounded-[32px] sm:p-14">
            <div className="mx-auto mb-5 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary-foreground/10">
              <BarChart3 className="h-7 w-7" />
            </div>
            <h2 className="font-display text-[24px] font-extrabold sm:text-[36px]">
              Ready to make training pay?
            </h2>
            <p className="mx-auto mt-4 max-w-xl text-[17px] text-primary-foreground/80">
              {session
                ? "Your application lives in Settings → Verification — or start instantly with Whisper One."
                : "Join free, build your proof, and apply for the role that fits — or start instantly with Whisper One."}
            </p>
            <div className="mt-8 flex flex-col justify-center gap-3 sm:flex-row">
              <Button
                size="lg"
                className="h-14 rounded-full bg-background px-8 text-[16px] font-semibold text-foreground hover:bg-background/90"
                asChild
              >
                <Link to={applyHref}>
                  {session ? "Go to my application" : "Create your account"}
                  <ArrowRight className="ml-1 h-5 w-5" />
                </Link>
              </Button>
              <Button
                size="lg"
                variant="outline"
                className="h-14 rounded-full border-primary-foreground/30 bg-transparent px-8 text-[16px] font-semibold text-primary-foreground hover:bg-primary-foreground/10 hover:text-primary-foreground"
                asChild
              >
                <Link to="/one">Get Whisper One</Link>
              </Button>
            </div>
          </Reveal>
        </section>
      </main>

      <PublicFooter />
    </div>
  );
}
