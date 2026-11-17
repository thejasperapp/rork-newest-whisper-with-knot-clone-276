import { useEffect, useRef } from "react";
import { Link, Navigate, useSearchParams, useParams } from "react-router-dom";
import {
  ArrowLeft,
  ArrowRight,
  BadgeDollarSign,
  Building2,
  CalendarCheck2,
  Gift,
  Layers,
  Lock,
  Megaphone,
  Search,
  ShieldCheck,
  Sparkles,
  Star,
  Users,
  Wallet,
} from "lucide-react";

import PublicNav from "@/components/PublicNav";
import PublicFooter from "@/components/PublicFooter";
import { Reveal } from "@/components/Reveal";
import { useAuth } from "@/hooks/useAuth";
import { useMyBadge } from "@/hooks/useMyBadge";
import {
  PITCH_AUDIENCES,
  canOpenPitchMode,
  pitchAudienceMeta,
} from "@/lib/pitch";
import { BrandMarketDemo, BrandDirectoryRow } from "@/components/pitch/BrandMarketDemo";
import { WppCalculator } from "@/components/pitch/WppCalculator";
import { PipelineDemo } from "@/components/pitch/PipelineDemo";
import { MeetingsDemo } from "@/components/pitch/MeetingsDemo";
import { CoachEarningsDemo } from "@/components/pitch/CoachEarningsDemo";
import { PaymentsDemo } from "@/components/pitch/PaymentsDemo";
import {
  BrandDashboardDemo,
  BrandDirectoryTeaser,
  BrandSignupTeaser,
  BrandsEmptyTeaser,
  EmberBrandCheckTeaser,
} from "@/components/pitch/BrandDashboardDemo";
import { PitchProvider, usePitch } from "@/components/pitch/PitchContext";
import { PitchPresenterBar } from "@/components/pitch/PitchPresenterBar";
import { PitchDemoBanner } from "@/components/pitch/PitchDemoBanner";
import { PitchBeforeAfter } from "@/components/pitch/PitchBeforeAfter";
import { PitchFaq } from "@/components/pitch/PitchFaq";
import { BrandRoiCalculator, CoachHoursCalculator } from "@/components/pitch/PitchRoiCalculator";
import { PitchFollowUp } from "@/components/pitch/PitchFollowUp";
import { PitchQrButton } from "@/components/pitch/PitchQr";
import { PitchPhoneFrame } from "@/components/pitch/PitchPhoneFrame";
import { PitchSpeakerNotes, PitchSpeakerNotesMobile, type PitchFaqItem } from "@/components/pitch/PitchSpeakerNotes";
import { PitchSecretsPanel, PitchSecretsMobile } from "@/components/pitch/PitchSecrets";
import { PitchExportPdf } from "@/components/pitch/PitchExportPdf";
import { SAMPLE_BRANDS } from "@/lib/pitch";
import { cn } from "@/lib/utils";

interface SectionProps {
  id: string;
  eyebrow: string;
  title: string;
  lead: string;
  children: React.ReactNode;
  hidden?: boolean;
}

function PitchSection({ id, eyebrow, title, lead, children, hidden }: SectionProps) {
  const { registerSection, unregisterSection } = usePitch();
  const ref = useRef<HTMLElement>(null);

  useEffect(() => {
    if (hidden) return;
    registerSection(id, ref.current);
    return () => unregisterSection(id);
  }, [id, hidden, registerSection, unregisterSection]);

  if (hidden) return null;

  return (
    <section ref={ref} id={id} className="scroll-mt-28">
      <Reveal variant="up" threshold={0.1}>
        <div className="space-y-3">
          <div>
            <p className="text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
              {eyebrow}
            </p>
            <h2 className="mt-0.5 text-lg font-extrabold tracking-tight sm:text-xl">
              {title}
            </h2>
            <p className="mt-1 text-sm leading-relaxed text-muted-foreground">{lead}</p>
          </div>
          {children}
        </div>
      </Reveal>
    </section>
  );
}

const BRAND_BEFORE_AFTER = [
  { before: "DMs and email chains to find creators", after: "Public directory with pay range on the card" },
  { before: "Chasing creators for proof of posts", after: "Tracked posts prove reach automatically" },
  { before: "Net-30 invoices and payment risk", after: "Escrow funded up front, released on verified posts" },
  { before: "Manual contract negotiation", after: "Accept / counter / deny in one screen" },
];

const BRAND_FAQ = [
  {
    question: "How do we know posts actually went live?",
    answer:
      "Creators link their Whisper post to the deal. Whisper verifies the post is live and reads likes + comments back into the deal card. Escrow only releases after verification.",
  },
  {
    question: "What if a creator doesn't deliver?",
    answer:
      "You can dispute any pending escrow payment. The funds are held until the dispute is resolved, and undelivered posts don't release.",
  },
  {
    question: "How does Jasper verify a brand?",
    answer:
      "We confirm the company, product line, and creator payout history. A score out of 100 is published on the brand profile.",
  },
];

const BRAND_NOTES = [
  { section: "Brand dashboard", bullets: ["Switch between the 3 sample brands to show scale.", "Tap Accept, Counter, or Deny to show live terms.", "Point out the escrow counter and dispute affordance."] },
  { section: "Directory", bullets: ["Pay range is printed on the card — no DM negotiation.", "Tapping a brand opens the real profile view."] },
  { section: "Jasper check", bullets: ["Trust layer: verified company + payout history.", "Brands without Jasper cannot sponsor."] },
];

const BRAND_SECRETS = [
  { label: "Pricing", content: "10% platform fee on released sponsorship payments. No listing fees, no subscription. Ads bill separately at a flat $5.00 CPM from a prepaid wallet." },
  { label: "Live now", content: "Whisper Ads is shipping: campaign → ad set → ad structure, feed/reels/comments placements, role + follower-band targeting, budgets, optional auto-recharge, and a public Ad Library like Meta's. 50% of all ad spend funds the WPP creator pool." },
  { label: "Edge case", content: "If a creator disputes a release, both parties get a DM thread and a 7-day mediation window before auto-refund." },
];

const CREATOR_BEFORE_AFTER = [
  { before: "Cold DM brands and hope for a reply", after: "Apply to vetted brands with pay range visible" },
  { before: "Chase invoices 30–90 days later", after: "Money held in escrow before you post" },
  { before: "Algorithm-dependent ad revenue", after: "Transparent WPP payout per 1k qualified views" },
  { before: "No proof of deliverables", after: "Tracked posts release payment automatically" },
];

const CREATOR_FAQ = [
  {
    question: "When do I get paid?",
    answer:
      "Per-post deals release when your tracked post goes live. Monthly deals release at the end of the week once your posts are verified. WPP months finalize on the 1st — closed months cash out from $10, via Stripe.",
  },
  {
    question: "Where does the WPP money come from?",
    answer:
      "Real ad revenue — not a promise. 50% of every ad dollar businesses spend becomes the monthly creator pool. Your month = min(your views × tier RPM, your view-share of the pool), so payouts can never exceed collected revenue.",
  },
  {
    question: "Can I negotiate terms?",
    answer:
      "Yes. When you apply, the brand can accept, counter with new terms, or pass. You see the counter in My Sponsorships.",
  },
  {
    question: "What counts as a qualified WPP view?",
    answer:
      "Views on Reels and threads that meet the partner tier's eligibility rules — one view per person per post per day, never self-views, per-viewer daily caps.",
  },
];

const CREATOR_NOTES = [
  { section: "Brand marketplace", bullets: ["Tap a brand card to show the real profile + apply flow.", "Point out Jasper verified badge and typical pay line."] },
  { section: "WPP", bullets: ["Drag sliders to show earnings at their follower/view level.", "Highlight the RPM tiers and perks."] },
  { section: "Earnings", bullets: ["Show the escrow > release flow.", "Click Fund to show the brand-side Stripe checkout simulation."] },
];

const CREATOR_SECRETS = [
  { label: "Eligibility", content: "WPP opens at 1,000 followers. Brand marketplace has no follower minimum, but each brand sets their own requirements." },
  { label: "Payouts", content: "WPP months finalize on the 1st and closed months cash out from $10 via Stripe — the same rail as coach payouts and live-gift earnings. Sponsorships release per-post or per-week depending on the deal basis." },
  { label: "Beyond deals", content: "Live gifts (hosts keep 70%), coaching subscriptions (coaches keep 90%), and Featured Film Friday premieres are all extra earning surfaces — mention them when a prospect wants the full picture." },
  { label: "Growth", content: "Featured creators get priority brand marketplace placement and recruiter introductions." },
];

const COACH_FAQ = [
  {
    question: "Do clients subscribe through Whisper or my own site?",
    answer:
      "Either. Every coach gets a shareable link (mydailywhisper.com/hire/you) and a Hire button on their profile. Clients subscribe in-app.",
  },
  {
    question: "How long until payouts hit my bank?",
    answer:
      "Stripe processes payouts automatically. Most coaches see the money in their bank account within 1–2 business days of release.",
  },
  {
    question: "Can I also take sponsorships?",
    answer:
      "Yes. Coaches with an audience can apply to brand deals from the same marketplace and earn WPP on their content.",
  },
];

const COACH_NOTES = [
  { section: "Money flow", bullets: ["Click through the 4 steps.", "Show the real rate/balance cards and the live calculator."] },
  { section: "Beyond subscriptions", bullets: ["Coaches can also do brand deals and WPP."] },
];

const COACH_SECRETS = [
  { label: "Stripe", content: "Stripe Connect Express onboarding — identity + bank collected INSIDE the app (embedded sheet); Whisper never holds coach funds." },
  { label: "Platform fee", content: "10% on client payments. No other fees for coaches." },
  { label: "Plan tiers", content: "Coaches publish up to three plan tiers ($5–$2,000/mo, six perks each). The hire page renders them as selectable cards and charges exactly the picked tier." },
  { label: "Churn", content: "Monthly subscriptions recur automatically. Failed payments retry 3 times before pausing. Clients get a 7-day refund window, handled in-app." },
];

const RECRUITER_FAQ = [
  {
    question: "How do prospects request a meeting?",
    answer:
      "Your featured public card has a Schedule a call button. The request comes in with their email, preferred time, and a message — your calendar stays private.",
  },
  {
    question: "Can I promote a user to verified?",
    answer:
      "Yes. Ready prospects can be promoted to coach, athlete, or creator. Promotions are logged server-side and show on their profile.",
  },
  {
    question: "How are signups credited to me?",
    answer:
      "Your referral link adds a server-side tracking parameter. Every signup through that link is credited to your dashboard automatically.",
  },
];

const RECRUITER_NOTES = [
  { section: "Pipeline", bullets: ["Filter by stage, advance prospects, promote the ready ones.", "The funnel bar animates live."] },
  { section: "Meetings", bullets: ["Approve with a Whisper Meet link — the room is minted for you, no external tools.", "Decline with a note to show the email notification."] },
  { section: "Toolkit", bullets: ["Walk the six OS views: Today → Pipeline → People → Inbox → Insights → Grow.", "Mention targets, referrals, and the featured card with custom action buttons."] },
];

const RECRUITER_SECRETS = [
  { label: "Compensation", content: "Recruiters earn per-promotion bounties and monthly bonuses against targets." },
  { label: "Territory", content: "Territory map is based on prospect location and source; recruiters claim territories with a real GPS pin." },
  { label: "The OS", content: "The Recruiting OS is a real ATS: Today work queue (every active person carries a next step), drag-and-drop pipeline with aging dots, scorecards, activity timelines, and insights — plus a guided walkthrough that teaches it on first open." },
];

/** The brand-side pitch deck — pitches companies on sponsoring through Whisper. */
function BrandsDeck() {
  const { pitchLength, secrets } = usePitch();
  const isShort = pitchLength === "short";

  return (
    <>
      <PitchSection
        id="brand-dashboard"
        eyebrow="The brand dashboard"
        title="One screen for every sponsorship"
        lead="This is the real /brand/dashboard view with sample data loaded. Switch between three sample brands at the top to see how applications, deals, and escrow payments scale. Tap Accept / Counter / Deny on any application, and Fund-into-escrow on any deal — every interaction is live."
      >
        <BrandDashboardDemo />
      </PitchSection>

      {!isShort && (
        <PitchSection
          id="brand-directory"
          eyebrow="How creators find you"
          title="Your brand profile is your storefront"
          lead="When you publish, your brand shows up in the public directory with the pay range printed on the card — no DM negotiating in the dark. Creators tap through to a full profile (about, Jasper check, requirements, perks) and apply in two taps."
        >
          <div className="space-y-3">
            <BrandSignupTeaser />
            {SAMPLE_BRANDS.map((b) => (
              <BrandDirectoryRow key={b.user_id} brand={b} />
            ))}
          </div>
        </PitchSection>
      )}

      {!isShort && (
        <PitchSection
          id="brand-ember"
          eyebrow="Jasper brand check"
          title="We verify every brand before they can sponsor"
          lead="Jasper is Whisper's trust layer for sponsorships. We verify the company, the product line, and the creator payout history — then publish a score out of 100 on the brand profile so creators know who they're dealing with before they apply."
        >
          <div className="space-y-3">
            <EmberBrandCheckTeaser />
            <div className="grid grid-cols-2 gap-2">
              <div className="rounded-2xl border border-border bg-card p-4 shadow-sm">
                <ShieldCheck className="h-5 w-5 text-emerald-600" />
                <p className="mt-2 text-sm font-bold">Escrow on accept</p>
                <p className="mt-0.5 text-xs text-muted-foreground">
                  You fund deals into escrow up front — Whisper holds the money until the tracked post goes live.
                </p>
              </div>
              <div className="rounded-2xl border border-border bg-card p-4 shadow-sm">
                <BadgeDollarSign className="h-5 w-5" />
                <p className="mt-2 text-sm font-bold">10% platform fee</p>
                <p className="mt-0.5 text-xs text-muted-foreground">
                  Whisper keeps 10% of each released payment. No listing fees, no monthly subscription, no ad spend required.
                </p>
              </div>
            </div>
          </div>
        </PitchSection>
      )}

      {!isShort && (
        <PitchSection
          id="brand-roi"
          eyebrow="ROI calculator"
          title="Show the value before they spend a dollar"
          lead="Drag the sliders to model a 3-month sponsorship budget, estimated reach, and what the same impressions would cost on a paid ad platform."
        >
          <BrandRoiCalculator />
        </PitchSection>
      )}

      {!isShort && (
        <PitchSection
          id="brand-ads"
          eyebrow="Whisper Ads"
          title="Paid reach, Meta-style — and it funds the creators"
          lead="Beyond sponsorships, brands run real ad campaigns: Campaign → Ad set → Ad structure, photo or video creatives, role + follower-band targeting, and three placements — feed, reels, and comment threads."
        >
          <div className="grid grid-cols-2 gap-2">
            {[
              { icon: Megaphone, title: "Flat $5.00 CPM", body: "Every impression bills at a flat CPM from a prepaid wallet — no auctions, no surprises." },
              { icon: Wallet, title: "Prepaid wallet", body: "Top up in-app with receipts; optional auto-recharge keeps campaigns live. Delivery pauses at $0." },
              { icon: Layers, title: "Three placements", body: "One sponsored card every 6 feed posts, a full-screen reels slide every 5 reels, one quiet row in comments." },
              { icon: ShieldCheck, title: "Public Ad Library", body: "Every live ad is publicly searchable — transparency like Meta's library. And 50% of all ad spend funds the WPP creator pool." },
            ].map((f) => (
              <div key={f.title} className="rounded-2xl border border-border bg-card p-4 shadow-sm">
                <f.icon className="h-5 w-5" />
                <p className="mt-2 text-sm font-bold">{f.title}</p>
                <p className="mt-0.5 text-xs text-muted-foreground">{f.body}</p>
              </div>
            ))}
          </div>
        </PitchSection>
      )}

      <PitchSection
        id="brand-before-after"
        eyebrow="Without vs. With Whisper"
        title="How sponsorships change when they're escrowed"
        lead="Four practical differences a brand feels immediately."
      >
        <PitchBeforeAfter
          eyebrow=""
          title=""
          lead=""
          items={BRAND_BEFORE_AFTER}
        />
      </PitchSection>

      <PitchSection
        id="brand-faq"
        eyebrow="Objections"
        title="Questions brands usually ask"
        lead="Tap any question to see the answer you should give in the room."
      >
        <PitchFaq eyebrow="" title="" items={BRAND_FAQ} />
      </PitchSection>

      {secrets && (
        <PitchSection
          id="brand-secrets"
          eyebrow="Presenter secrets"
          title="Internal talking points"
          lead="Only visible while the Secrets panel is open."
          hidden={!secrets}
        >
          <PitchSecretsMobile secrets={BRAND_SECRETS} />
        </PitchSection>
      )}
    </>
  );
}

/** The creator + athlete deck — brand marketplace + WPP + discovery. */
function CreatorAthleteDeck(audience: "creators" | "athletes") {
  const { pitchLength, secrets } = usePitch();
  const isShort = pitchLength === "short";
  const isAthlete = audience === "athletes";

  return (
    <>
      <PitchSection
        id="marketplace"
        eyebrow="Brand marketplace"
        title="Real brands, transparent pay, escrowed deals"
        lead={
          isAthlete
            ? "Athletes browse vetted brands, see the exact pay range up front, and apply in two taps. Money is escrowed the moment a brand accepts — released when your tracked post goes live."
            : "Creators browse vetted brands with the pay range printed on the card — no DM negotiating in the dark. Money is escrowed on acceptance and released when the tracked post lands."
        }
      >
        <BrandMarketDemo />
      </PitchSection>

      {!isShort && (
        <PitchSection
          id="wpp"
          eyebrow="WPP — Whisper Paid Partners"
          title="Ad revenue share, funded by real ad spend"
          lead="Not a promise fund — 50% of every ad dollar businesses spend becomes the monthly creator pool. Your month = min(your qualified views × tier RPM, your view-share of the pool), so payouts can never exceed collected revenue. Months finalize on the 1st; cash out from $10. Drag the sliders to show a prospect their numbers live."
        >
          <WppCalculator />
        </PitchSection>
      )}

      <PitchSection
        id="earnings"
        eyebrow="Your earnings, in your account"
        title="See exactly what money looks like when it lands"
        lead="This is the real /sponsorships earnings view with sample deal data. Pending-in-escrow, paid-out, per-deal ledger, escrow countdown, and the one-tap Fund flow."
      >
        <PaymentsDemo />
      </PitchSection>

      {!isShort && (
        <PitchSection
          id="discovery"
          eyebrow="Getting discovered"
          title={isAthlete ? "Featured cards + recruiter scouting" : "Featured placement for top creators"}
          lead={
            isAthlete
              ? "Our recruiters actively scout athletes and feature them on the public site with action buttons — email, schedule a call, or a direct profile link."
              : "Top creators get featured on the public Whisper site with direct action buttons, priority feed placement at higher WPP tiers, and warm brand introductions."
          }
        >
          <div className="grid grid-cols-3 gap-2">
            {[
              { icon: Search, label: "Scouted by our recruiter team" },
              { icon: Star, label: "Featured on the public site" },
              { icon: Building2, label: "Brands come to you" },
            ].map((f) => (
              <div
                key={f.label}
                className="rounded-2xl border border-border bg-card p-3 text-center shadow-sm"
              >
                <f.icon className="mx-auto h-5 w-5" />
                <p className="mt-2 text-[11px] font-semibold leading-tight">{f.label}</p>
              </div>
            ))}
          </div>
        </PitchSection>
      )}

      {!isShort && (
        <PitchSection
          id="more-earning"
          eyebrow="More ways to earn"
          title="Four money rails, one account"
          lead="Sponsorships and WPP are the headline — but the same Stripe payout rail also carries live gifts and coaching subscriptions."
        >
          <div className="grid grid-cols-3 gap-2">
            {[
              { icon: Gift, title: "Live gifts", body: "Viewers send paid gifts in live rooms — hosts keep 70%, cash out from $10." },
              { icon: Users, title: "Coaching", body: "Verified coaches publish up to 3 plan tiers — coaches keep 90% of every subscription." },
              { icon: Star, title: "Featured films", body: "Whisper Studios premieres director work every Featured Film Friday — right in the feed." },
            ].map((f) => (
              <div key={f.title} className="rounded-2xl border border-border bg-card p-3 shadow-sm">
                <f.icon className="h-5 w-5" />
                <p className="mt-2 text-[12px] font-bold leading-tight">{f.title}</p>
                <p className="mt-0.5 text-[11px] leading-snug text-muted-foreground">{f.body}</p>
              </div>
            ))}
          </div>
        </PitchSection>
      )}

      <PitchSection
        id="creator-before-after"
        eyebrow="Without vs. With Whisper"
        title="How creators get paid"
        lead="Four practical differences for a creator's day-to-day."
      >
        <PitchBeforeAfter eyebrow="" title="" lead="" items={CREATOR_BEFORE_AFTER} />
      </PitchSection>

      <PitchSection
        id="creator-faq"
        eyebrow="Objections"
        title="Questions creators usually ask"
        lead="Tap any question to see the answer."
      >
        <PitchFaq eyebrow="" title="" items={CREATOR_FAQ} />
      </PitchSection>

      {secrets && (
        <PitchSection
          id="creator-secrets"
          eyebrow="Presenter secrets"
          title="Internal talking points"
          lead="Only visible while the Secrets panel is open."
          hidden={!secrets}
        >
          <PitchSecretsMobile secrets={CREATOR_SECRETS} />
        </PitchSection>
      )}
    </>
  );
}

/** The coach deck — money flow + calculator + sample account. */
function CoachDeck() {
  const { pitchLength, secrets } = usePitch();
  const isShort = pitchLength === "short";

  return (
    <>
      <PitchSection
        id="coach-flow"
        eyebrow="The money flow"
        title="Exactly how coaches earn on Whisper"
        lead="Four steps, no fine print: publish up to three plan tiers ($5–$2,000/mo), clients subscribe on your hire page, Stripe pays you out — coaches keep 90%, and bank linking happens inside the app. Click through each step, then drag the calculator to show a prospect coach their real take-home."
      >
        <CoachEarningsDemo />
      </PitchSection>

      {!isShort && (
        <PitchSection
          id="coach-extra"
          eyebrow="Beyond subscriptions"
          title="Sponsorships and WPP apply to coaches too"
          lead="Coaches with an audience can take brand deals from the same marketplace and earn WPP ad revenue on their content."
        >
          <div className="grid grid-cols-2 gap-2">
            <div className="rounded-2xl border border-border bg-card p-4 shadow-sm">
              <Building2 className="h-5 w-5" />
              <p className="mt-2 text-sm font-bold">Brand deals</p>
              <p className="mt-0.5 text-xs text-muted-foreground">
                Recovery, apparel, and supplement brands actively look for coaches with engaged clients.
              </p>
            </div>
            <div className="rounded-2xl border border-border bg-card p-4 shadow-sm">
              <BadgeDollarSign className="h-5 w-5" />
              <p className="mt-2 text-sm font-bold">WPP payouts</p>
              <p className="mt-0.5 text-xs text-muted-foreground">
                Training content earns ad-revenue share monthly at your partner tier.
              </p>
            </div>
          </div>
        </PitchSection>
      )}

      {!isShort && (
        <PitchSection
          id="coach-hours"
          eyebrow="Hourly calculator"
          title="Side income from coaching time"
          lead="Show a coach what their weekly hours are worth if they run them through Whisper instead of spreadsheets and Venmo."
        >
          <CoachHoursCalculator />
        </PitchSection>
      )}

      <PitchSection
        id="coach-faq"
        eyebrow="Objections"
        title="Questions coaches usually ask"
        lead="Tap any question to see the answer."
      >
        <PitchFaq eyebrow="" title="" items={COACH_FAQ} />
      </PitchSection>

      {secrets && (
        <PitchSection
          id="coach-secrets"
          eyebrow="Presenter secrets"
          title="Internal talking points"
          lead="Only visible while the Secrets panel is open."
          hidden={!secrets}
        >
          <PitchSecretsMobile secrets={COACH_SECRETS} />
        </PitchSection>
      )}
    </>
  );
}

/** The recruiter deck — pipeline + meetings + toolkit. */
function RecruiterDeck() {
  const { pitchLength, secrets } = usePitch();
  const isShort = pitchLength === "short";

  return (
    <>
      <PitchSection
        id="pipeline"
        eyebrow="The pipeline"
        title="Scout → track → promote, in one board"
        lead="This is the real /recruiter pipeline view with sample talent loaded. Move prospects through the stages, then promote the ones marked ready — exactly what a recruiter does day-to-day."
      >
        <PipelineDemo />
      </PitchSection>

      {!isShort && (
        <PitchSection
          id="meetings"
          eyebrow="Meetings"
          title="Prospects request, you approve"
          lead="Your featured card carries a Schedule-a-call button. Requests land here with the person's email and preferred time — approve with a Whisper Meet link minted for you (the call runs in Whisper's own meeting rooms, with AI notes) or decline with a note."
        >
          <MeetingsDemo />
        </PitchSection>
      )}

      {!isShort && (
        <PitchSection
          id="toolkit"
          eyebrow="Your toolkit"
          title="A real recruiting OS, not a spreadsheet"
          lead="Six views run the whole desk — Today (a work queue where every active person carries a next step), Pipeline (drag-and-drop kanban with aging dots), People, Inbox, Insights, and Grow — plus monthly targets, a territory map with real GPS pins, referral links credited server-side, and a public featured card. A guided walkthrough teaches the whole desk on first open."
        >
          <div className="grid grid-cols-2 gap-2">
            {[
              {
                icon: Users,
                title: "Targets & referrals",
                body: "Monthly goals per role; every signup through your link is credited automatically.",
              },
              {
                icon: CalendarCheck2,
                title: "Featured card",
                body: "Public card on the site with up to 3 action buttons — including Schedule a call.",
              },
            ].map((f) => (
              <div
                key={f.title}
                className="rounded-2xl border border-border bg-card p-4 shadow-sm"
              >
                <f.icon className="h-5 w-5" />
                <p className="mt-2 text-sm font-bold">{f.title}</p>
                <p className="mt-0.5 text-xs text-muted-foreground">{f.body}</p>
              </div>
            ))}
          </div>
        </PitchSection>
      )}

      <PitchSection
        id="recruiter-faq"
        eyebrow="Objections"
        title="Questions recruiters usually ask"
        lead="Tap any question to see the answer."
      >
        <PitchFaq eyebrow="" title="" items={RECRUITER_FAQ} />
      </PitchSection>

      {secrets && (
        <PitchSection
          id="recruiter-secrets"
          eyebrow="Presenter secrets"
          title="Internal talking points"
          lead="Only visible while the Secrets panel is open."
          hidden={!secrets}
        >
          <PitchSecretsMobile secrets={RECRUITER_SECRETS} />
        </PitchSection>
      )}
    </>
  );
}

function PitchDeckInner() {
  const { audience } = useParams<{ audience: string }>();
  const [searchParams] = useSearchParams();
  // When loaded inside the recruiter dashboard's inline iframe/webview, the
  // `?embed=1` query param suppresses the public nav + footer so the deck
  // renders as a clean presentation surface.
  const embedded = searchParams.get("embed") === "1";
  const badge = useMyBadge();
  const { profile } = useAuth();
  const isRecruiter = !!profile?.is_recruiter;
  const meta = pitchAudienceMeta(audience);
  const { phoneFrame, speakerNotes, secrets } = usePitch();

  if (!meta) return <Navigate to="/pitch" replace />;

  if (!canOpenPitchMode(badge, isRecruiter)) {
    return (
      <div className="min-h-screen">
        {!embedded && <PublicNav />}
        <div className="mx-auto flex max-w-md flex-col items-center gap-3 px-6 pb-20 pt-32 text-center">
          <span className="flex h-14 w-14 items-center justify-center rounded-2xl bg-secondary">
            <Lock className="h-6 w-6 text-muted-foreground" />
          </span>
          <p className="text-lg font-bold">Team only</p>
          <p className="max-w-xs text-sm text-muted-foreground">
            Pitch Mode is reserved for Whisper moderators, admins, the
            founder, and recruiters.
          </p>
          <Link
            to="/auth"
            className="mt-2 rounded-full bg-foreground px-5 py-2.5 text-sm font-bold text-background transition-transform active:scale-95"
          >
            Sign in
          </Link>
        </div>
        {!embedded && <PublicFooter />}
      </div>
    );
  }

  const idx = PITCH_AUDIENCES.findIndex((a) => a.id === meta.id);
  const next = PITCH_AUDIENCES[(idx + 1) % PITCH_AUDIENCES.length];
  const prev = PITCH_AUDIENCES[(idx - 1 + PITCH_AUDIENCES.length) % PITCH_AUDIENCES.length];

  const notes =
    meta.id === "brands"
      ? BRAND_NOTES
      : meta.id === "coaches"
      ? COACH_NOTES
      : meta.id === "recruiters"
      ? RECRUITER_NOTES
      : CREATOR_NOTES;
  const secretList =
    meta.id === "brands"
      ? BRAND_SECRETS
      : meta.id === "coaches"
      ? COACH_SECRETS
      : meta.id === "recruiters"
      ? RECRUITER_SECRETS
      : CREATOR_SECRETS;

  const faqs: PitchFaqItem[] =
    meta.id === "brands"
      ? BRAND_FAQ
      : meta.id === "coaches"
      ? COACH_FAQ
      : meta.id === "recruiters"
      ? RECRUITER_FAQ
      : CREATOR_FAQ;

  return (
    <div className="min-h-screen">
      {!embedded && <PublicNav />}
      <PitchDemoBanner />
      <PitchQrButton />

      <div className="mx-auto max-w-2xl space-y-10 px-4 pb-24 pt-24">
        {speakerNotes && <PitchSpeakerNotesMobile notes={notes} faqs={faqs} />}
        {secrets && <PitchSecretsMobile secrets={secretList} />}
        <Link
          to="/pitch"
          className="inline-flex items-center gap-1.5 text-[13.5px] font-bold text-muted-foreground transition-colors hover:text-foreground"
        >
          <ArrowLeft className="h-4 w-4" /> All decks
        </Link>

        <Reveal variant="up">
          <div className="rounded-[24px] bg-foreground p-6 text-background sm:p-8">
            <p className="flex items-center gap-2 text-[11px] font-bold uppercase tracking-wider opacity-70">
              <meta.icon className="h-4 w-4" /> For {meta.title.toLowerCase()}
            </p>
            <h1 className="mt-2 text-2xl font-extrabold tracking-tight sm:text-3xl">
              {meta.tagline}
            </h1>
            <p className="mt-2 text-sm leading-relaxed opacity-80 sm:text-base">
              Everything below is live and clickable — sample data rendered through the same views the real product uses. Walk a prospect through every screen, tap every button, reset whenever.
            </p>
          </div>
        </Reveal>

        <PitchPhoneFrame enabled={phoneFrame}>
          <div id="pitch-deck-content" className="space-y-10">
            {meta.id === "brands" && <BrandsDeck />}
            {(meta.id === "creators" || meta.id === "athletes") && CreatorAthleteDeck(meta.id)}
            {meta.id === "coaches" && <CoachDeck />}
            {meta.id === "recruiters" && <RecruiterDeck />}

            <Reveal variant="fade">
              <div className="space-y-3">
                <Link
                  to={`/pitch/${next.id}`}
                  className="group flex items-center justify-between rounded-[20px] border border-border bg-card p-5 shadow-sm transition-all hover:border-foreground/25 hover:shadow-md active:scale-[0.99]"
                >
                  <div>
                    <p className="text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
                      Next deck
                    </p>
                    <p className="mt-0.5 text-base font-extrabold">{next.title}</p>
                    <p className="text-xs text-muted-foreground">{next.tagline}</p>
                  </div>
                  <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-secondary transition-all group-hover:bg-foreground group-hover:text-background">
                    <ArrowRight className="h-5 w-5 transition-transform group-hover:translate-x-0.5" />
                  </span>
                </Link>
                <Link
                  to={`/pitch/${prev.id}`}
                  className="group flex items-center justify-between rounded-[20px] border border-border bg-card p-5 shadow-sm transition-all hover:border-foreground/25 hover:shadow-md active:scale-[0.99]"
                >
                  <div>
                    <p className="text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
                      Previous deck
                    </p>
                    <p className="mt-0.5 text-base font-extrabold">{prev.title}</p>
                    <p className="text-xs text-muted-foreground">{prev.tagline}</p>
                  </div>
                  <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-secondary transition-all group-hover:bg-foreground group-hover:text-background">
                    <ArrowLeft className="h-5 w-5 transition-transform group-hover:-translate-x-0.5" />
                  </span>
                </Link>
              </div>
            </Reveal>

            <PitchFollowUp audienceTitle={meta.title} faqs={faqs} />

            <p className="flex items-center justify-center gap-1.5 text-center text-[11px] text-muted-foreground">
              <Sparkles className="h-3 w-3" />
              Internal Pitch Mode · sample data only · visible to moderators, recruiters, and above
            </p>
          </div>
        </PitchPhoneFrame>
      </div>

      <PitchPresenterBar />
      <PitchSpeakerNotes notes={notes} faqs={faqs} />
      <PitchSecretsPanel secrets={secretList} />
      {!embedded && <PublicFooter />}
    </div>
  );
}

export default function PitchDeck() {
  const { audience } = useParams<{ audience: string }>();
  const meta = pitchAudienceMeta(audience);
  const deckId = audience ?? "all";
  const deckUrl = `https://mydailywhisper.com/pitch/${audience}`;
  const deckTitle = meta ? `${meta.title} Pitch` : "Pitch";

  return (
    <PitchProvider deckUrl={deckUrl} deckTitle={deckTitle} deckId={deckId}>
      <PitchDeckInner />
    </PitchProvider>
  );
}
