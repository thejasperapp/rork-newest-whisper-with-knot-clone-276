import { useEffect } from "react";
import { Link } from "react-router-dom";
import {
  ArrowRight,
  BadgeCheck,
  Briefcase,
  Coins,
  Gift,
  Handshake,
  Megaphone,
  Repeat,
  ShieldCheck,
  Sparkles,
  Target,
  TrendingUp,
  Users,
  Video,
} from "lucide-react";

import PublicNav from "@/components/PublicNav";
import PublicFooter from "@/components/PublicFooter";
import { cn } from "@/lib/utils";

/**
 * mydailywhisper.com/investors — Whisper's business model and growth strategy.
 * Every price and take rate on this page is the one live in the product; the
 * unit-economics section is explicitly labeled as an illustrative model.
 */

interface RevenueStream {
  icon: typeof Coins;
  name: string;
  pricing: string;
  type: string;
  description: string;
}

const REVENUE_STREAMS: RevenueStream[] = [
  {
    icon: Sparkles,
    name: "Whisper One membership",
    pricing: "$14.99 / month · $119.99 / year",
    type: "Consumer subscription",
    description:
      "The premium tier for individual members: expanded creator tools, live stat sharing, coaching for up to three clients, and the One mark on the profile.",
  },
  {
    icon: BadgeCheck,
    name: "Verified professional roles",
    pricing: "Creator $99.99 / year · Coach $249.99 / year",
    type: "Annual subscription (application-based)",
    description:
      "Creators and coaches apply, a team member reviews the application, and the annual fee is charged only after approval. Verified creators select a niche that appears on their profile.",
  },
  {
    icon: Handshake,
    name: "Coaching marketplace",
    pricing: "10% platform fee",
    type: "Transaction fee",
    description:
      "Coaches publish up to three monthly plans and are paid through Stripe Connect. Whisper retains 10% of each subscription; coaches keep 90%.",
  },
  {
    icon: Briefcase,
    name: "Training programs",
    pricing: "10% platform fee",
    type: "Transaction fee",
    description:
      "One-time purchases of coach-authored programs, processed through the same payment rail as coaching subscriptions.",
  },
  {
    icon: Megaphone,
    name: "Whisper Ads",
    pricing: "$5.00 CPM · prepaid wallet",
    type: "Advertising",
    description:
      "Self-serve campaigns with feed, video, and comment placements, audience targeting, scheduling, budgets, and a public Ad Library. Delivery is billed per impression from a prepaid balance.",
  },
  {
    icon: Gift,
    name: "Live gifts",
    pricing: "30% platform share",
    type: "Virtual goods",
    description:
      "Viewers purchase gift credits and send them during live streams. Hosts receive 70% and cash out through Stripe.",
  },
  {
    icon: Briefcase,
    name: "Business+",
    pricing: "$100.00 / month · $999.99 / year",
    type: "B2B subscription",
    description:
      "The business workspace: team seats and roles, hiring with auto-matched applications, a private team group, team chat, a team calendar, and in-meeting company presentations.",
  },
  {
    icon: Coins,
    name: "Brand sponsorships",
    pricing: "Escrowed payments",
    type: "Marketplace",
    description:
      "Brands fund creator deals into escrow; funds release when deliverables post. Whisper operates the marketplace and the payment rail.",
  },
];

interface FunnelStage {
  step: string;
  name: string;
  summary: string;
  drivers: string[];
  kpi: string;
  target: string;
}

const FUNNEL: FunnelStage[] = [
  {
    step: "01",
    name: "Acquisition",
    summary: "New members arrive through people they already know.",
    drivers: [
      "Creators, coaches, and recruiters bring existing audiences onto the platform.",
      "Location-based campus and gym communities give every new area an immediate home.",
      "Shareable public surfaces: profiles, articles, films, meeting links, application pages.",
      "Integration with the Jasper fitness app introduces its users to Whisper.",
    ],
    kpi: "Cost per activated member",
    target: "Organic-first; paid acquisition only after retention targets are met",
  },
  {
    step: "02",
    name: "Activation",
    summary: "A new member reaches value in the first session.",
    drivers: [
      "A five-step onboarding: profile, communities (including Dating), people to follow, an optional Jasper connection, and community guidelines.",
      "A Getting Started checklist in the feed tracks the first post, first community, and first connection.",
      "Follow suggestions and community picks seed a populated feed from minute one.",
    ],
    kpi: "Day-7 retention",
    target: "20%",
  },
  {
    step: "03",
    name: "Engagement",
    summary: "Members return for the people and communities they joined.",
    drivers: [
      "A ranked feed built on recency, engagement, and follow relationships.",
      "Stories, Waves (short video), direct messages, group chats, and live streaming.",
      "Communities with their own feeds, including Dating with blind-date video rooms.",
      "Whisper Meet video meetings with AI notes, available to every member.",
    ],
    kpi: "Day-30 retention · weekly active / monthly active ratio",
    target: "10% D30 · 45% WAU/MAU",
  },
  {
    step: "04",
    name: "Monetization",
    summary: "Value is captured from members, professionals, and businesses.",
    drivers: [
      "Whisper One for individuals; verified roles for creators and coaches.",
      "Transaction fees on coaching and programs; a 30% share of live gifts.",
      "Whisper Ads and Business+ for companies; escrowed brand sponsorships.",
    ],
    kpi: "Paid conversion · blended ARPU",
    target: "3% of MAU on Whisper One · ARPU tracked monthly",
  },
  {
    step: "05",
    name: "Retention & referral",
    summary: "Paying creators and communities bring the next cohort.",
    drivers: [
      "The creator revenue-share program pays creators from ad revenue, which retains supply.",
      "Meeting links convert guests into members; sounds turn every video into a template for the next.",
      "Recruiters are credited for every professional they bring onto the platform.",
    ],
    kpi: "Viral coefficient (K)",
    target: "≥ 0.4",
  },
];

interface ScenarioLine {
  label: string;
  assumption: string;
  monthly: number;
}

const SCENARIO: ScenarioLine[] = [
  { label: "Whisper One", assumption: "30 members (3%) × $14.99", monthly: 450 },
  { label: "Verified roles", assumption: "15 creators + 5 coaches, annual fees amortized", monthly: 229 },
  { label: "Coaching fees", assumption: "5 coaches × 6 clients × $60 × 10%", monthly: 180 },
  { label: "Whisper Ads", assumption: "1 ad per 6 feed slots, 40 sessions/member/month, $5 CPM", monthly: 400 },
  { label: "Live gifts", assumption: "$350 gifted per month × 30%", monthly: 105 },
];

const SCENARIO_TOTAL = SCENARIO.reduce((sum, line) => sum + line.monthly, 0);

interface Phase {
  number: string;
  name: string;
  milestone: string;
  focus: string[];
}

const ROADMAP: Phase[] = [
  {
    number: "Phase 1",
    name: "Product completeness",
    milestone: "Complete — iOS and web at feature parity",
    focus: [
      "Social core: feed, stories, short video, messaging, communities, live.",
      "Professional tools: coaching, creator analytics, recruiting, business suite.",
      "Payments: Stripe checkout, Connect payouts, receipts, refunds, and policies.",
    ],
  },
  {
    number: "Phase 2",
    name: "Community density",
    milestone: "First 10,000 members concentrated in seeded communities",
    focus: [
      "Seed campus and gym communities market by market rather than spreading thin.",
      "Recruit coaches and creators first so every community has active supply.",
      "Hold Day-7 retention at 20% before increasing acquisition spend.",
    ],
  },
  {
    number: "Phase 3",
    name: "Monetization at scale",
    milestone: "100,000 members · advertising self-sustaining",
    focus: [
      "Grow the advertiser base against verified reach; 50% of ad revenue funds creator pay.",
      "Expand Business+ and the sponsorship marketplace with the brand directory.",
      "Introduce paid acquisition where retention and payback are proven.",
    ],
  },
  {
    number: "Phase 4",
    name: "Network expansion",
    milestone: "1,000,000 members across regions",
    focus: [
      "Replicate the density playbook in new regions and verticals.",
      "Deepen the Jasper integration and partner distribution.",
      "Operate as a multi-sided marketplace: members, professionals, businesses, advertisers.",
    ],
  },
];

interface Risk {
  risk: string;
  mitigation: string;
}

const RISKS: Risk[] = [
  {
    risk: "Cold-start in new markets",
    mitigation:
      "Location-based communities and recruiter-led supply give every new market immediate content and people; expansion is sequenced by density, not geography.",
  },
  {
    risk: "Creator payout exposure",
    mitigation:
      "Creator pay is drawn from a pool equal to 50% of collected ad revenue; payouts are capped at the lesser of view-share or tier RPM, so distributions can never exceed revenue.",
  },
  {
    risk: "Trust and safety",
    mitigation:
      "Application-based verification reviewed by staff, in-app reporting and blocking, database-enforced moderation in live rooms, and published refund and conduct policies.",
  },
  {
    risk: "Platform dependency",
    mitigation:
      "Whisper ships on iOS and the web with a shared backend; payments run on Stripe with receipts, refunds, and audit trails owned by Whisper.",
  },
];

const currency = (value: number): string =>
  value.toLocaleString("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 });

export default function Investors() {
  useEffect(() => {
    document.title = "Whisper — Business Model & Growth Strategy";
  }, []);

  return (
    <div className="min-h-screen bg-background text-foreground">
      <PublicNav />

      {/* Hero */}
      <section className="border-b border-border bg-[#0C1014] text-white">
        <div className="mx-auto max-w-5xl px-6 py-20 md:py-28">
          <p className="text-xs font-bold uppercase tracking-[0.22em] text-white/50">
            Business model &amp; growth strategy
          </p>
          <h1 className="mt-4 max-w-3xl font-display text-4xl font-extrabold tracking-tight md:text-6xl">
            A social platform built on real communities, with eight revenue streams live today.
          </h1>
          <p className="mt-6 max-w-2xl text-lg leading-relaxed text-white/70">
            Whisper combines a consumer social network — feed, stories, short video, messaging,
            communities, dating, and live — with professional tools for creators, coaches,
            recruiters, and businesses. Every product on this page is in production on iOS and the
            web, and every price is the one members pay.
          </p>
          <div className="mt-10 grid grid-cols-2 gap-3 sm:grid-cols-4">
            {[
              { value: "8", label: "Revenue streams live" },
              { value: "2", label: "Platforms at parity (iOS · web)" },
              { value: "$5.00", label: "Ad CPM" },
              { value: "50%", label: "Of ad revenue paid to creators" },
            ].map((stat) => (
              <div key={stat.label} className="rounded-2xl border border-white/10 bg-white/[0.04] p-4">
                <p className="font-display text-3xl font-extrabold">{stat.value}</p>
                <p className="mt-1 text-xs font-semibold text-white/55">{stat.label}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Executive summary */}
      <section className="mx-auto max-w-5xl px-6 py-16">
        <SectionHeading kicker="Overview" title="Executive summary" />
        <div className="mt-6 grid gap-6 md:grid-cols-3">
          {[
            {
              icon: Users,
              title: "Who it serves",
              body: "Members who want a smaller, more genuine social network; creators and coaches who want to earn from their audience; recruiters and businesses who need to reach and hire them.",
            },
            {
              icon: Target,
              title: "How it grows",
              body: "Density before reach: communities are seeded by location and interest, supply (coaches, creators) is recruited first, and members arrive through people they already follow.",
            },
            {
              icon: TrendingUp,
              title: "How it earns",
              body: "Subscriptions from members and professionals, transaction fees on coaching and programs, advertising billed per impression, a share of live gifts, and a business subscription.",
            },
          ].map((item) => {
            const Icon = item.icon;
            return (
              <div key={item.title} className="rounded-2xl border border-border bg-card p-6">
                <span className="flex h-10 w-10 items-center justify-center rounded-xl bg-secondary">
                  <Icon className="h-5 w-5" />
                </span>
                <h3 className="mt-4 text-base font-bold">{item.title}</h3>
                <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{item.body}</p>
              </div>
            );
          })}
        </div>
      </section>

      {/* Revenue model */}
      <section className="border-y border-border bg-secondary/30">
        <div className="mx-auto max-w-5xl px-6 py-16">
          <SectionHeading
            kicker="Revenue model"
            title="Eight revenue streams, all in production"
            subtitle="Prices and take rates below are the ones live in the product. Verified-role fees are charged only after a staff member approves the application."
          />
          <div className="mt-8 overflow-hidden rounded-2xl border border-border bg-card">
            {REVENUE_STREAMS.map((stream, index) => {
              const Icon = stream.icon;
              return (
                <div
                  key={stream.name}
                  className={cn(
                    "grid gap-4 p-5 md:grid-cols-[minmax(0,1.3fr)_minmax(0,1fr)_minmax(0,2fr)] md:items-start",
                    index > 0 && "border-t border-border"
                  )}
                >
                  <div className="flex items-start gap-3">
                    <span className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-secondary">
                      <Icon className="h-4 w-4" />
                    </span>
                    <div>
                      <p className="text-sm font-bold">{stream.name}</p>
                      <p className="mt-0.5 text-xs font-semibold text-muted-foreground">{stream.type}</p>
                    </div>
                  </div>
                  <p className="text-sm font-semibold tabular-nums">{stream.pricing}</p>
                  <p className="text-sm leading-relaxed text-muted-foreground">{stream.description}</p>
                </div>
              );
            })}
          </div>
        </div>
      </section>

      {/* Customer funnel */}
      <section className="mx-auto max-w-5xl px-6 py-16">
        <SectionHeading
          kicker="Customer funnel"
          title="Acquisition to referral, with the metric we manage at each stage"
          subtitle="Each stage lists the product capabilities that drive it and the key performance indicator we track. Targets are internal operating goals."
        />
        <div className="mt-8 space-y-4">
          {FUNNEL.map((stage) => (
            <div key={stage.step} className="rounded-2xl border border-border bg-card p-6">
              <div className="flex flex-wrap items-start justify-between gap-4">
                <div className="flex items-start gap-4">
                  <span className="font-display text-2xl font-extrabold text-muted-foreground/60">{stage.step}</span>
                  <div>
                    <h3 className="text-lg font-bold">{stage.name}</h3>
                    <p className="mt-1 text-sm text-muted-foreground">{stage.summary}</p>
                  </div>
                </div>
                <div className="rounded-xl border border-border bg-secondary/40 px-4 py-3 text-sm">
                  <p className="text-[11px] font-bold uppercase tracking-wider text-muted-foreground">KPI</p>
                  <p className="mt-0.5 font-semibold">{stage.kpi}</p>
                  <p className="mt-1 text-xs text-muted-foreground">Target: {stage.target}</p>
                </div>
              </div>
              <ul className="mt-5 grid gap-2 md:grid-cols-2">
                {stage.drivers.map((driver) => (
                  <li key={driver} className="flex items-start gap-2 text-sm leading-relaxed text-muted-foreground">
                    <span className="mt-2 h-1.5 w-1.5 shrink-0 rounded-full bg-foreground/60" />
                    {driver}
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      </section>

      {/* Advertising → creator economics */}
      <section className="border-y border-border bg-[#0C1014] text-white">
        <div className="mx-auto max-w-5xl px-6 py-16">
          <SectionHeading
            kicker="Advertising economics"
            title="How advertising revenue funds creator pay"
            subtitle="The creator revenue-share program is funded exclusively from collected ad revenue, so payouts scale with — and never exceed — what advertisers pay."
            dark
          />
          <div className="mt-8 grid gap-3 md:grid-cols-4">
            {[
              { icon: Megaphone, title: "Advertisers prepay", body: "Campaigns run from a prepaid wallet and are billed at a $5.00 CPM per delivered impression." },
              { icon: Repeat, title: "50% forms the creator pool", body: "Each month, half of collected ad revenue becomes the creator revenue-share pool." },
              { icon: Video, title: "Creators earn by qualified views", body: "A creator's month equals the lesser of views × tier RPM ($0.90 / $1.40 / $2.20 per 1,000) or their share of the pool." },
              { icon: Coins, title: "Paid through Stripe", body: "Months close on the first; balances of $10 or more are paid out through Stripe Connect." },
            ].map((step, index) => {
              const Icon = step.icon;
              return (
                <div key={step.title} className="rounded-2xl border border-white/10 bg-white/[0.04] p-5">
                  <div className="flex items-center gap-2">
                    <span className="text-xs font-bold text-white/40">{index + 1}</span>
                    <Icon className="h-4 w-4 text-white/70" />
                  </div>
                  <h3 className="mt-3 text-sm font-bold">{step.title}</h3>
                  <p className="mt-2 text-sm leading-relaxed text-white/60">{step.body}</p>
                </div>
              );
            })}
          </div>
        </div>
      </section>

      {/* Unit economics */}
      <section className="mx-auto max-w-5xl px-6 py-16">
        <SectionHeading
          kicker="Unit economics"
          title="Illustrative revenue per 1,000 monthly active members"
          subtitle="This is a model, not reported results. It applies live prices to the internal conversion targets above and excludes Business+, sponsorships, and program sales."
        />
        <div className="mt-8 overflow-hidden rounded-2xl border border-border bg-card">
          <div className="grid grid-cols-[minmax(0,1fr)_auto] gap-4 border-b border-border bg-secondary/40 px-5 py-3 text-[11px] font-bold uppercase tracking-wider text-muted-foreground md:grid-cols-[minmax(0,1fr)_minmax(0,1.6fr)_auto]">
            <span>Stream</span>
            <span className="hidden md:block">Assumption</span>
            <span className="text-right">Monthly</span>
          </div>
          {SCENARIO.map((line) => (
            <div
              key={line.label}
              className="grid grid-cols-[minmax(0,1fr)_auto] gap-4 border-b border-border px-5 py-4 text-sm md:grid-cols-[minmax(0,1fr)_minmax(0,1.6fr)_auto]"
            >
              <div>
                <p className="font-semibold">{line.label}</p>
                <p className="mt-0.5 text-xs text-muted-foreground md:hidden">{line.assumption}</p>
              </div>
              <p className="hidden text-muted-foreground md:block">{line.assumption}</p>
              <p className="text-right font-semibold tabular-nums">{currency(line.monthly)}</p>
            </div>
          ))}
          <div className="grid grid-cols-[minmax(0,1fr)_auto] gap-4 px-5 py-4 text-sm md:grid-cols-[minmax(0,1fr)_minmax(0,1.6fr)_auto]">
            <p className="font-bold">Total per 1,000 members</p>
            <p className="hidden text-muted-foreground md:block">
              ≈ {currency(SCENARIO_TOTAL * 12 / 1000)} blended annual revenue per member
            </p>
            <p className="text-right font-bold tabular-nums">{currency(SCENARIO_TOTAL)} / month</p>
          </div>
        </div>
        <p className="mt-3 text-xs leading-relaxed text-muted-foreground">
          Amortized verified-role revenue assumes annual fees recognized monthly. Advertising revenue
          assumes one sponsored placement per six feed positions at the live CPM. Coaching revenue is
          the platform fee only; the remaining 90% is paid to coaches.
        </p>
      </section>

      {/* Go-to-market */}
      <section className="border-y border-border bg-secondary/30">
        <div className="mx-auto max-w-5xl px-6 py-16">
          <SectionHeading
            kicker="Go-to-market"
            title="Density first, then reach"
            subtitle="Whisper is built to win one community at a time. Concentrating members and professionals in the same places produces the retention that makes acquisition spend efficient."
          />
          <div className="mt-8 grid gap-4 md:grid-cols-2">
            {[
              {
                title: "Location-based communities",
                body: "Campus and gym communities are created automatically from a member's location, so every new market has a populated home the moment the first members arrive.",
              },
              {
                title: "Supply-side recruiting",
                body: "A recruiting toolset with territories, pipelines, and credit for every signed professional brings coaches and creators onto the platform before the audience that follows them.",
              },
              {
                title: "Verified professionals as the trust layer",
                body: "Application-based verification for creators and coaches means members can hire, follow, and buy with confidence — and professionals pay for the credential.",
              },
              {
                title: "Partner distribution",
                body: "The Jasper fitness app integration connects health data to Whisper and introduces Jasper's users to the platform through a one-tap account link.",
              },
            ].map((item) => (
              <div key={item.title} className="rounded-2xl border border-border bg-card p-6">
                <h3 className="text-base font-bold">{item.title}</h3>
                <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{item.body}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Roadmap */}
      <section className="mx-auto max-w-5xl px-6 py-16">
        <SectionHeading
          kicker="Growth roadmap"
          title="Four phases, each with a measurable milestone"
        />
        <div className="mt-8 grid gap-4 md:grid-cols-2">
          {ROADMAP.map((phase) => (
            <div key={phase.number} className="rounded-2xl border border-border bg-card p-6">
              <p className="text-xs font-bold uppercase tracking-wider text-muted-foreground">{phase.number}</p>
              <h3 className="mt-1 text-lg font-bold">{phase.name}</h3>
              <p className="mt-1 text-sm font-semibold">{phase.milestone}</p>
              <ul className="mt-4 space-y-2">
                {phase.focus.map((line) => (
                  <li key={line} className="flex items-start gap-2 text-sm leading-relaxed text-muted-foreground">
                    <span className="mt-2 h-1.5 w-1.5 shrink-0 rounded-full bg-foreground/60" />
                    {line}
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      </section>

      {/* Risks */}
      <section className="border-y border-border bg-secondary/30">
        <div className="mx-auto max-w-5xl px-6 py-16">
          <SectionHeading kicker="Risk factors" title="Key risks and how they are mitigated" />
          <div className="mt-8 overflow-hidden rounded-2xl border border-border bg-card">
            {RISKS.map((item, index) => (
              <div
                key={item.risk}
                className={cn("grid gap-3 p-5 md:grid-cols-[minmax(0,1fr)_minmax(0,2.2fr)]", index > 0 && "border-t border-border")}
              >
                <div className="flex items-start gap-2">
                  <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
                  <p className="text-sm font-bold">{item.risk}</p>
                </div>
                <p className="text-sm leading-relaxed text-muted-foreground">{item.mitigation}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* CTA */}
      <section className="mx-auto max-w-5xl px-6 py-16">
        <div className="rounded-3xl border border-border bg-card p-8 md:p-10">
          <h2 className="font-display text-2xl font-extrabold tracking-tight md:text-3xl">
            Review the product, then talk to the founder.
          </h2>
          <p className="mt-3 max-w-2xl text-sm leading-relaxed text-muted-foreground">
            The public Ad Library shows every live campaign, the Policies page documents pricing,
            refunds, and verification, and the monetization overview explains each product in
            member-facing terms.
          </p>
          <div className="mt-6 flex flex-wrap gap-3">
            <Link
              to="/ad-library"
              className="inline-flex items-center gap-2 rounded-full bg-foreground px-5 py-2.5 text-sm font-bold text-background transition-transform active:scale-[0.98]"
            >
              Ad Library <ArrowRight className="h-4 w-4" />
            </Link>
            <Link
              to="/policies"
              className="inline-flex items-center gap-2 rounded-full border border-border px-5 py-2.5 text-sm font-bold transition-colors hover:bg-secondary"
            >
              Policies
            </Link>
            <Link
              to="/monetization"
              className="inline-flex items-center gap-2 rounded-full border border-border px-5 py-2.5 text-sm font-bold transition-colors hover:bg-secondary"
            >
              Monetization overview
            </Link>
          </div>
        </div>
      </section>

      <PublicFooter />
    </div>
  );
}

function SectionHeading({
  kicker,
  title,
  subtitle,
  dark = false,
}: {
  kicker: string;
  title: string;
  subtitle?: string;
  dark?: boolean;
}) {
  return (
    <div className="max-w-3xl">
      <p className={cn("text-xs font-bold uppercase tracking-[0.22em]", dark ? "text-white/50" : "text-muted-foreground")}>
        {kicker}
      </p>
      <h2 className="mt-2 font-display text-2xl font-extrabold tracking-tight md:text-3xl">{title}</h2>
      {subtitle && (
        <p className={cn("mt-3 text-sm leading-relaxed", dark ? "text-white/60" : "text-muted-foreground")}>{subtitle}</p>
      )}
    </div>
  );
}
