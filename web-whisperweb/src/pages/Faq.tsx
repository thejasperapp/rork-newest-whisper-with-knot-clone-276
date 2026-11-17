import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import {
  BadgeCheck,
  BarChart3,
  BookOpen,
  ChevronDown,
  CircleDollarSign,
  Clapperboard,
  Dumbbell,
  Ghost,
  HeartHandshake,
  LifeBuoy,
  Megaphone,
  NotebookPen,
  Radio,
  Search,
  Sparkles,
  UserPlus,
  Video,
  X,
} from "lucide-react";

/**
 * The in-depth Whisper FAQ — public, searchable, categorized. Every system
 * in the product is covered: accounts, Knot, meetings + Notebook +
 * Workspace, badges, coaching money, WPP, the Recruiting OS, ads, billing,
 * live, and safety. Linked from the profile menu and shareable by URL.
 */

interface FaqItem {
  q: string;
  a: string;
}

interface FaqCategory {
  id: string;
  label: string;
  accent: string;
  icon: typeof Ghost;
  items: FaqItem[];
}

const CATEGORIES: FaqCategory[] = [
  {
    id: "getting-started",
    label: "Getting started",
    accent: "#34D399",
    icon: Sparkles,
    items: [
      {
        q: "What is Whisper?",
        a: "Whisper is a social home for posts, stories, Waves, messages, live conversations, and communities. Knot helps with ideas and everyday questions, while professional tools give creators, coaches, and recruiters room to grow.",
      },
      {
        q: "How do I create an account?",
        a: "Choose Join Whisper and follow the signup and onboarding steps. Set up your profile, find people and communities, and review the community guidelines. You can update your profile and preferences later in Settings.",
      },
      {
        q: "What are 'lanes' and do they lock my account?",
        a: "Your lane just tells Whisper what to show you first — it never locks anything. Paid roles and badges (coach, recruiter, verified creator…) are separate and earned through applications or approval.",
      },
      {
        q: "Is Whisper free?",
        a: "Yes. The core app — feed, reels, messages, communities, meetings, live — is free. Whisper One is an optional subscription with VIP perks, and role badges carry a small verification fee that only bills AFTER a human approves you.",
      },
      {
        q: "How do I find the tools for my role?",
        a: "Start with your Whisper account. The tools available to you depend on your role and approvals. Explore Creator Studio, coaching, or recruiting from the relevant area in Whisper; the role pages explain current access requirements.",
      },
    ],
  },
  {
    id: "jasper",
    label: "Knot",
    accent: "#34D399",
    icon: Ghost,
    items: [
      {
        q: "Who is Knot?",
        a: "Knot is Whisper’s familiar assistant for writing, explanations, ideas, and planning. He can help untangle a thought or find the words for a reply. AI can make mistakes; review important answers.",
      },
      {
        q: "Can I connect fitness data?",
        a: "Fitness data is optional. Connected insights depend on a supported account link and the permissions you grant. Review the connection and sharing controls in Settings; you don’t need a fitness connection to enjoy Whisper.",
      },
      {
        q: "Can other people see my Knot chats?",
        a: "Your direct conversations with Knot are private to your account. An assistant reply you choose to share in a group or meeting is visible to that audience. Check who you’re sharing with before posting.",
      },
      {
        q: "Does Knot have different personalities?",
        a: "Yes — pick his personality from the chat header (each has its own color and voice). It changes his tone, not his honesty: the facts and your data stay the same.",
      },
      {
        q: "Why did Knot stop mid-answer or say he can't right now?",
        a: "AI features share fair-use limits to keep the lights on. Heavy tools (video answers, long analyses) are tap-to-run instead of automatic. If something fails, wait a moment and try again — your question isn't lost.",
      },
    ],
  },
  {
    id: "meetings",
    label: "Calls & meeting notes",
    accent: "#0E9F76",
    icon: Video,
    items: [
      {
        q: "How do I start a meeting?",
        a: "Open Meetings anywhere in the app (it opens Whisper Meet) and tap New meeting — your link copies automatically, share it with anyone. You can also join by pasting a code like wsp-abcd-efgh.",
      },
      {
        q: "Can people without a Whisper account join my meeting?",
        a: "Yes. Anyone with the link joins as a guest — they pick a display name and get full video and audio. Captions, transcripts, and calendar actions stay account-only.",
      },
      {
        q: "I opened a meeting link and it says 'Waiting for this room to open.'",
        a: "Code rooms unlock the moment the first signed-in member arrives — usually the person who created the link. Keep the tab open; the room opens by itself the second they join.",
      },
      {
        q: "Where do my meeting notes go?",
        a: "When a meeting ends, the assistant turns the transcript into structured notes (summary, key points, decisions, action items). They live in the Notebook — every note you own, searchable, with favorites pinned to the top. Rename any meeting from the Notebook; the name is yours alone and never changes the shared meeting.",
      },
      {
        q: "Where do I find professional tools?",
        a: "Whisper organizes professional tools around your role. Creator Studio, Coach Studio, and recruiting tools are available according to your account’s access and approvals. Visit the role pages to learn more before applying.",
      },
      {
        q: "Do meetings work between iOS and web?",
        a: "Yes — same rooms, same links. A meeting started on the web rings and joins fine from the iOS app and vice versa.",
      },
    ],
  },
  {
    id: "badges",
    label: "Badges & verification",
    accent: "#F59E0B",
    icon: BadgeCheck,
    items: [
      {
        q: "How do badges work?",
        a: "Badges are earned, never bought. You apply for a badge (Coach or Creator — recruiters are invited), a human reviews it, and only AFTER approval does the annual fee bill. Deny = no charge, ever. Creators pick a niche (Athlete, Fitness, Music…) that shows in gray under their name.",
      },
      {
        q: "What badges exist?",
        a: "Coach (ember seal), Verified creator (the check, with the creator's niche under their name), Recruiter (violet), Brand (indigo), Blogger, Director, plus staff marks for moderators and admins. Each shows on your profile, posts, comments, and search.",
      },
      {
        q: "Can a badge be removed?",
        a: "Yes — badges follow the house rules. Serious violations can suspend or remove a badge through the same review ladder as everything else (warning → strike → timeout → door).",
      },
      {
        q: "Is there a refund on the badge fee?",
        a: "Badge and Whisper One charges carry a 14-day refund window. Request it from Settings → Billing & refunds; approved refunds return the full charge.",
      },
    ],
  },
  {
    id: "coaching",
    label: "Coaches & clients",
    accent: "#F97316",
    icon: Dumbbell,
    items: [
      {
        q: "How do I hire a coach?",
        a: "Open a coach's profile or their share link and tap Hire. If they publish plans, pick the tier that fits; payment happens right in the app through Stripe, and your membership starts immediately.",
      },
      {
        q: "How much do coaches keep?",
        a: "Coaches keep 90% of every payment. The 10% platform fee covers processing and running Whisper. Payouts land in the bank account the coach links inside Coach Studio.",
      },
      {
        q: "How do coach plans (tiers) work?",
        a: "Coaches publish up to three plans — name, tagline, monthly price ($5–$2,000), and up to six perks each. Clients pick a plan on the hire page and are billed exactly that amount monthly until they cancel.",
      },
      {
        q: "How do coaches get paid out?",
        a: "Coach Studio → Earnings shows your balance, the bank on file, payout schedule, and history — Stripe runs inside the app, including bank linking. Cash out moves your balance to your bank; no external dashboard needed.",
      },
      {
        q: "What's the refund window for coaching?",
        a: "Coaching payments carry a 7-day refund window; training programs carry 14 days. File from Settings → Billing & refunds — approved refunds make you 100% whole and end the subscription immediately.",
      },
      {
        q: "What are programs?",
        a: "One-time purchases coaches build in the Programs studio — a structured plan you buy once and keep. They ride the same in-app checkout and the 14-day refund window.",
      },
    ],
  },
  {
    id: "creators",
    label: "Creators & WPP",
    accent: "#38BDF8",
    icon: Clapperboard,
    items: [
      {
        q: "What is WPP (Whisper Paid Partners)?",
        a: "The program that pays creators from real ad revenue. Every month, half of actual ad spend becomes the creator pool. Your earnings = min(your qualified views × your tier RPM, your view-share of the pool) — so payouts can never exceed what advertisers actually paid.",
      },
      {
        q: "What are the WPP tiers?",
        a: "Partner at 1k+ followers ($0.90 per 1,000 qualified views), Partner+ at 10k+ ($1.40), Elite at 100k+ ($2.20). Your tier updates as you grow; the WPP card in Creator Studio shows your live tier, views, and estimate.",
      },
      {
        q: "What counts as a qualified view?",
        a: "One view per person per post per day, from the real feed. Self-views never count and per-viewer daily caps stop farming. This protects the pool for everyone.",
      },
      {
        q: "When can I cash out?",
        a: "Months finalize on the 1st; only closed months are cashable, minimum $10. Cash out from the WPP card — it rides the same in-app Stripe rail coaches use, straight to your linked bank.",
      },
      {
        q: "How do I get verified as a creator?",
        a: "Apply from the app (Apply → Creator). Verification is reviewed by a human; the badge fee bills only after approval.",
      },
    ],
  },
  {
    id: "recruiting",
    label: "Recruiters & the Recruiting OS",
    accent: "#7059E8",
    icon: UserPlus,
    items: [
      {
        q: "What is the Recruiting OS?",
        a: "The recruiter's whole desk in six views: Today (your work queue), Pipeline (drag-and-drop stages), People (the searchable pool), Inbox (applications + meeting requests), Insights (goals, speed, sources), and Grow (invite link, QR poster, territories).",
      },
      {
        q: "How do I learn it fast?",
        a: "The guided walkthrough plays automatically on your first visit — it highlights each tool in real time and literally says 'click here' as you move through the sections. Replay it anytime with the Walkthrough button at the top of the dashboard.",
      },
      {
        q: "What do the pipeline stages mean?",
        a: "Sourced (found, not contacted) → Contacted (first touch sent) → In talks (they replied) → Evaluating (meeting/tryout) → Offer (ready to sign). Drag cards between stages; the aging dot goes green → amber → red as someone sits untouched.",
      },
      {
        q: "What's a 'next step' and why does the app nag me about it?",
        a: "Rule one of talent CRMs: every active person carries a next step (DM them, call, book a meeting, follow up) with a due date. The Today queue is built from those. When you complete one, Whisper logs the touch and immediately asks for the next — that discipline is what signs people.",
      },
      {
        q: "How do scorecards work?",
        a: "Four criteria — Talent, Drive, Coachability, Audience — each rated 1–5 stars in the person's drawer. The composite shows on their cards so you can rank your pool objectively.",
      },
      {
        q: "How do I sign someone?",
        a: "Move them to Offer, then tap Sign them. Whisper finds their account by @username and flips their badge (creator or coach) on the spot — it counts toward your monthly goal and your source stats.",
      },
      {
        q: "How do people apply to ME?",
        a: "Grow holds your invite link and a printable QR poster. Scans land in your Inbox as applications with the questionnaire attached; approving a meeting request can mint a Whisper Meet link for you automatically.",
      },
      {
        q: "How do I become a recruiter?",
        a: "Open Recruiter HQ and submit the application — a human reviews it. Once approved, the OS and the walkthrough unlock immediately.",
      },
    ],
  },
  {
    id: "ads",
    label: "Business & Ads",
    accent: "#5A5FE8",
    icon: Megaphone,
    items: [
      {
        q: "How is the Ads Manager structured?",
        a: "Exactly like Meta's: Campaign (objective + on/off + optional lifetime budget) → Ad set (audience, schedule, placements, daily pacing) → Ad (the creative). An ad only serves when all three levels are live.",
      },
      {
        q: "Where can my ads appear?",
        a: "Three placements, multi-selectable per ad set: the Feed (a sponsored card in the rotation), Reels (a full-screen sponsored slide every few reels), and Comments (one quiet sponsored row inside opened threads). All three feed the same analytics.",
      },
      {
        q: "What targeting is available?",
        a: "Role targeting (coaches, creators, recruiters, brands) resolved from real verified roles at serve time, plus follower-size bands (under 1k / 1k–10k / 10k+), a schedule window, and daily pacing.",
      },
      {
        q: "How does ad billing work?",
        a: "Ads bill at a $5.00 CPM from your prepaid Ads wallet. Top up $25/$100/$250 in-app (with receipts); delivery auto-pauses at $0. Optional auto-recharge saves a card once and tops up automatically when the wallet dips under your threshold — with a cooldown, receipts, and one-tap off.",
      },
      {
        q: "Can I upload real photos and videos for ads?",
        a: "Yes — upload photo or video creatives (up to 80 MB) right in the wizard or the ad editor. Video ads autoplay muted wherever they serve, and the live preview shows exactly what viewers see.",
      },
      {
        q: "What is the Ad Library?",
        a: "A public transparency page at /ad-library — every ad currently running on Whisper, searchable by advertiser or headline, with creative, placements, objective, and running-since date. Just like Meta's. Library views never bill advertisers.",
      },
      {
        q: "Do my ads fund creators?",
        a: "Yes — half of real ad spend becomes the monthly WPP creator pool. Every view your campaign buys helps pay the creators who make Whisper worth watching.",
      },
    ],
  },
  {
    id: "billing",
    label: "Billing, receipts & refunds",
    accent: "#22C55E",
    icon: CircleDollarSign,
    items: [
      {
        q: "Where are my receipts?",
        a: "Settings → Billing & refunds → Purchase history: every charge with amount, date, status, and a receipt number (WSP-2026-…). Each successful charge also emails you a branded receipt.",
      },
      {
        q: "What are the refund windows?",
        a: "Whisper One & badge fees: 14 days. Coaching: 7 days. Programs: 14 days. The full policy lives at /policies.",
      },
      {
        q: "How do I request a refund?",
        a: "Settings → Billing & refunds → pick the purchase → Request refund. You get an email at every step; approved refunds return the money to your original payment method and end the related subscription immediately.",
      },
      {
        q: "Is my card information safe?",
        a: "Whisper never sees or stores card numbers — payments run through Stripe's embedded forms inside the app. Saved cards for ad auto-recharge live at Stripe as payment methods, not on our servers.",
      },
      {
        q: "What is Whisper One?",
        a: "The optional membership with additional perks in Whisper. Check the Whisper One page for current benefits, billing options, and terms before subscribing. Manage your subscription through the relevant purchase provider.",
      },
    ],
  },
  {
    id: "live",
    label: "Live",
    accent: "#EF4444",
    icon: Radio,
    items: [
      {
        q: "How do I go live?",
        a: "Live → Go live. Viewers chat, react with floating emoji, and join as speakers when you approve them. Your live shows on the Live tab and to your followers.",
      },
      {
        q: "What are the host stream tools?",
        a: "A live goal bar every reaction pushes forward (synced on all screens), slow mode (5/15/30s), followers-only chat (you're exempt), and raids that send your whole audience to another live room when you end.",
      },
      {
        q: "Can I schedule a live?",
        a: "Yes — schedule from Live start; scheduled rooms show their time and don't kick early arrivals.",
      },
    ],
  },
  {
    id: "notebookpen",
    label: "Posts, reels & the feed",
    accent: "#A855F7",
    icon: NotebookPen,
    items: [
      {
        q: "How does the feed decide what I see?",
        a: "Honest math, same on iOS and web: recency with a 20-hour half-life, engagement (a comment weighs 2.5× a like), a 1.45× boost for people you follow, a freshness kicker for posts under 90 minutes, and a diversity pass so nobody dominates. One ad slot in six, clearly labeled Sponsored.",
      },
      {
        q: "What's the difference between posts and reels?",
        a: "Posts live on your profile grid and the feed; reels are full-screen vertical videos with their own swipe surface. Both count toward creator stats and WPP qualified views.",
      },
      {
        q: "Can I share things into DMs?",
        a: "Yes — posts, reels, articles, films, profiles, quizzes, and meeting notes all share as proper preview cards in chat, never raw code.",
      },
    ],
  },
  {
    id: "safety",
    label: "Safety & the house rules",
    accent: "#F43F5E",
    icon: HeartHandshake,
    items: [
      {
        q: "What are the house rules?",
        a: "Be real, be respectful, and keep it safe. No hate, harassment, sexual content, violence, or anything that endangers minors. The full Community Guidelines, code of conduct, and enforcement steps live in our Policies and Terms.",
      },
      {
        q: "How does enforcement work?",
        a: "Four fair steps: warning → strike → timeout → door. Instant-removal offenses (the serious stuff) skip the ladder. Every action is reviewable.",
      },
      {
        q: "How do I appeal a strike or removal?",
        a: "Email support@mydailywhisper.com from the address on your account. A human reads every appeal.",
      },
      {
        q: "How do I report content or a user?",
        a: "Use the report action on any post, comment, message, or profile. Reports route to moderators; you'll never be shown as the reporter.",
      },
    ],
  },
];

/** Flat searchable list with category context. */
interface FlatItem extends FaqItem {
  catId: string;
  catLabel: string;
  accent: string;
}

const ALL_ITEMS: FlatItem[] = CATEGORIES.flatMap((c) =>
  c.items.map((i) => ({
    ...i,
    catId: c.id,
    catLabel: c.label,
    accent: c.accent,
  }))
);

export default function Faq() {
  const [query, setQuery] = useState<string>("");
  const [open, setOpen] = useState<Record<string, boolean>>({});

  const needle = query.trim().toLowerCase();
  const results = useMemo(() => {
    if (!needle) return null;
    return ALL_ITEMS.filter(
      (i) =>
        i.q.toLowerCase().includes(needle) ||
        i.a.toLowerCase().includes(needle) ||
        i.catLabel.toLowerCase().includes(needle)
    );
  }, [needle]);

  const toggle = (key: string): void =>
    setOpen((o) => ({ ...o, [key]: !o[key] }));

  const itemRow = (item: FlatItem, key: string) => {
    const isOpen = !!open[key];
    return (
      <div
        key={key}
        className="overflow-hidden rounded-[18px] border border-border/60 bg-card transition-colors"
      >
        <button
          onClick={() => toggle(key)}
          aria-expanded={isOpen}
          aria-controls={`faq-${encodeURIComponent(key)}`}
          className="flex w-full items-center gap-3 px-4 py-3.5 text-left"
        >
          <span className="min-w-0 flex-1 text-[13.5px] font-extrabold leading-snug">
            {item.q}
          </span>
          <ChevronDown
            className={`h-4 w-4 shrink-0 text-muted-foreground transition-transform ${
              isOpen ? "rotate-180" : ""
            }`}
          />
        </button>
        {isOpen && (
          <div id={`faq-${encodeURIComponent(key)}`} className="border-t border-border/40 px-4 py-3.5">
            <p className="whitespace-pre-line text-[13px] leading-relaxed text-muted-foreground">
              {item.a}
            </p>
          </div>
        )}
      </div>
    );
  };

  return (
    <div className="relative min-h-screen bg-background">
      {/* Soft atmosphere */}
      <div
        aria-hidden
        className="pointer-events-none absolute -top-44 left-1/2 h-[420px] w-[760px] -translate-x-1/2 rounded-full opacity-20 blur-3xl"
        style={{
          background:
            "radial-gradient(closest-side, rgba(232,151,96,0.35), transparent)",
        }}
      />

      <div className="relative mx-auto w-full max-w-3xl px-4 pb-24 pt-10 sm:pt-14">
        {/* Hero */}
        <div className="text-center">
          <span className="mx-auto flex h-14 w-14 items-center justify-center rounded-3xl bg-secondary text-foreground">
            <LifeBuoy className="h-7 w-7" />
          </span>
          <h1 className="mt-4 font-display text-[30px] font-extrabold leading-tight sm:text-[36px]">
            How can we help?
          </h1>
          <p className="mx-auto mt-2 max-w-md text-[13.5px] leading-relaxed text-muted-foreground">
            A little clarity on everything Whisper — your account, Knot,
            creating, conversations, recruiting, and the rules of the room.
          </p>
        </div>

        {/* Search */}
        <div className="mt-6 flex h-12 items-center gap-2.5 rounded-full border border-border bg-card px-5 shadow-sm">
          <Search className="h-[18px] w-[18px] shrink-0 text-muted-foreground" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search the FAQ — try 'refund', 'meeting code', 'WPP'…"
            className="min-w-0 flex-1 bg-transparent text-[14px] outline-none placeholder:text-muted-foreground/60"
          />
          {query && (
            <button
              onClick={() => setQuery("")}
              aria-label="Clear search"
              className="text-muted-foreground transition-colors hover:text-foreground"
            >
              <X className="h-4 w-4" />
            </button>
          )}
        </div>

        {/* Category chips */}
        {!results && (
          <div className="no-scrollbar mt-4 flex gap-1.5 overflow-x-auto pb-1">
            {CATEGORIES.map((c) => (
              <a
                key={c.id}
                href={`#${c.id}`}
                className="flex shrink-0 items-center gap-1.5 rounded-full border border-border/60 bg-card px-3 py-1.5 text-[11.5px] font-bold text-muted-foreground transition-colors hover:text-foreground"
              >
                <c.icon className="h-3.5 w-3.5" style={{ color: "var(--wm-muted, currentColor)" }} />
                {c.label}
              </a>
            ))}
          </div>
        )}

        {/* Search results */}
        {results && (
          <div className="mt-6">
            <p className="mb-3 text-[11px] font-black uppercase tracking-[0.16em] text-muted-foreground">
              {results.length} answer{results.length === 1 ? "" : "s"} found
            </p>
            <div className="space-y-2">
              {results.map((i, idx) => (
                <div key={`${i.catId}-${idx}`}>
                  <p
                    className="mb-1 ml-1 text-[10px] font-black uppercase tracking-[0.14em]"
                    style={{ color: "var(--wm-muted, currentColor)" }}
                  >
                    {i.catLabel}
                  </p>
                  {itemRow(i, `s-${i.catId}-${i.q}`)}
                </div>
              ))}
              {results.length === 0 && (
                <div className="rounded-[22px] border border-border/60 bg-card px-6 py-10 text-center">
                  <p className="text-[14px] font-extrabold">No matches</p>
                  <p className="mx-auto mt-1 max-w-xs text-[12px] leading-relaxed text-muted-foreground">
                    Try a different word — or email{" "}
                    <a
                      href="mailto:support@mydailywhisper.com"
                      className="font-bold text-foreground underline-offset-4 hover:underline"
                    >
                      support@mydailywhisper.com
                    </a>{" "}
                    and a human will answer.
                  </p>
                </div>
              )}
            </div>
          </div>
        )}

        {/* Categories */}
        {!results &&
          CATEGORIES.map((c) => (
            <section key={c.id} id={c.id} className="mt-9 scroll-mt-24">
              <div className="mb-3 flex items-center gap-2.5">
                <span
                  className="flex h-9 w-9 items-center justify-center rounded-xl"
                  style={{ backgroundColor: "var(--wm-card)", color: "var(--wm-ink)" }}
                >
                  <c.icon className="h-[18px] w-[18px]" />
                </span>
                <h2 className="font-display text-[18px] font-extrabold">
                  {c.label}
                </h2>
              </div>
              <div className="space-y-2">
                {c.items.map((i) =>
                  itemRow(
                    { ...i, catId: c.id, catLabel: c.label, accent: c.accent },
                    `${c.id}-${i.q}`
                  )
                )}
              </div>
            </section>
          ))}

        {/* Footer links */}
        <div className="mt-12 rounded-[22px] border border-border/60 bg-card px-5 py-5">
          <p className="text-[14px] font-extrabold">Still stuck?</p>
          <p className="mt-1 text-[12.5px] leading-relaxed text-muted-foreground">
            A human reads every message at{" "}
            <a
              href="mailto:support@mydailywhisper.com"
              className="font-bold text-foreground underline-offset-4 hover:underline"
            >
              support@mydailywhisper.com
            </a>
            . For the fine print: <Link to="/policies" className="font-bold text-foreground underline-offset-4 hover:underline">Policies</Link>,{" "}
            <Link to="/terms" className="font-bold text-foreground underline-offset-4 hover:underline">Terms</Link>,{" "}
            <Link to="/privacy" className="font-bold text-foreground underline-offset-4 hover:underline">Privacy</Link>.
          </p>
          <div className="mt-3 flex items-center gap-1.5 text-[11px] text-muted-foreground">
            <BookOpen className="h-3.5 w-3.5" />
            Features and access can change. Check the relevant role and
            policy pages for current details.
          </div>
          <div className="mt-1 flex items-center gap-1.5 text-[11px] text-muted-foreground">
            <BarChart3 className="h-3.5 w-3.5" />
            Advertisers: the public Ad Library lives at{" "}
            <Link to="/ad-library" className="font-bold underline-offset-4 hover:underline">
              /ad-library
            </Link>
            .
          </div>
        </div>
      </div>
    </div>
  );
}
