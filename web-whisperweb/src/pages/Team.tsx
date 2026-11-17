import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import {
  ArrowRight,
  ArrowUpRight,
  BadgeCheck,
  Check,
  Dumbbell,
  Handshake,
  HeartHandshake,
  Megaphone,
  Rocket,
  ShieldCheck,
  Sparkles,
  Users,
  UserSearch,
  Film,
  PenLine,
} from "lucide-react";

import PublicNav from "@/components/PublicNav";
import PublicFooter from "@/components/PublicFooter";
import { PresentationIntro, PresentationLink } from "@/components/Presentation";
import { Reveal } from "@/components/Reveal";
import { Button } from "@/components/ui/button";
import { usePageMeta } from "@/hooks/usePageMeta";
import { fetchFeaturedProfiles } from "@/lib/featured";

function CoachSeal({ size = 22 }: { size?: number }) {
  return (
    <Dumbbell size={size} aria-hidden="true" />
  );
}

function CreatorSeal({ size = 22 }: { size?: number }) {
  return (
    <PenLine size={size} aria-hidden="true" />
  );
}

interface TeamGroup {
  key: "coach" | "creator" | "recruiter";
  title: string;
  to: string;
  seal: React.ReactNode;
  icon: React.ReactNode;
  blurb: string;
  points: string[];
  cta: string;
}

const GROUPS: TeamGroup[] = [
  {
    key: "coach",
    title: "Coaches",
    to: "/coaches",
    seal: <CoachSeal />,
    icon: <Dumbbell className="h-5 w-5" />,
    blurb:
      "Application-reviewed professionals who train real clients through Whisper — programs, check-ins, and macros right in your DMs. Every coaching style carries a tier so you always know who you're training with.",
    points: [
      "Credentials reviewed by a real person",
      "Tiered by experience per coaching style",
      "Programs, check-ins, and coaching conversations together",
    ],
    cta: "Meet the coaches",
  },
  {
    key: "creator",
    title: "Creators",
    to: "/creators",
    seal: <CreatorSeal />,
    icon: <BadgeCheck className="h-5 w-5" />,
    blurb:
      "People with their own point of view—athletes, artists, educators, and public figures. Discover their work and learn what they create through their profile details.",
    points: [
      "Applications reviewed by a real person",
      "Niche shown on the profile — Athlete, Music, Fitness…",
      "Communities and series inside Whisper",
    ],
    cta: "Meet the creators",
  },
  {
    key: "recruiter", title: "Recruiters", to: "/recruiters", seal: <UserSearch size={22} />, icon: <UserSearch className="h-5 w-5" />,
    blurb: "The connectors who spot potential. Recruiters bring local knowledge, thoughtful introductions, and a place to keep the next step in view.",
    points: ["Application-reviewed role with no fee", "Territories, prospects, and personal invite links", "Contact permissions apply to everyone"], cta: "Meet the recruiters",
  },
];

/**
 * "Our Team" — the family page. Explains the three verified team styles and
 * highlights the Jasper partnership.
 */
export default function Team() {
  usePageMeta(
    "People & professional roles",
    "Meet Whisper’s coaches, creators, and recruiters, and explore tools for directors and writers."
  );

  const counts = useQuery({
    queryKey: ["featured-profiles", "counts"],
    staleTime: 60_000,
    queryFn: async () => {
      const [coaches, creators, recruiters] = await Promise.all([
        fetchFeaturedProfiles("coach"),
        fetchFeaturedProfiles("creator"),
        fetchFeaturedProfiles("recruiter"),
      ]);
      return {
        coach: coaches.length + 1, // + built-in Hudson card
        creator: creators.length,
        recruiter: recruiters.length,
      };
    },
  });

  return (
    <div className="presentation-page min-h-screen bg-background">
      <PublicNav />

      <main>
        <div className="presentation-container !pb-0">
          <PresentationIntro eyebrow="The people who make it Whisper" title="Different talents. A little more possibility." description="Coaches who show up. Creators with something to say. Recruiters who see potential. Meet the people, then find the tools that fit what you do.">
            <PresentationLink to="/roles/coach" primary>Explore professional roles</PresentationLink>
            <PresentationLink to="/safety">Understand our reviews</PresentationLink>
          </PresentationIntro>
        </div>

        {/* Team styles */}
        <section className="px-4 py-8 sm:px-6 lg:px-8 lg:py-10">
          <Reveal stagger className="mx-auto grid max-w-5xl gap-5 lg:grid-cols-3">
            {GROUPS.map((group) => {
              const count = counts.data?.[group.key] ?? 0;
              return (
                <div
                  key={group.key}
                  className="flex flex-col rounded-[28px] border border-border bg-card p-7"
                >
                  <div className="flex items-center gap-3">
                    {group.seal}
                    <h2 className="font-display text-[24px] font-extrabold">
                      {group.title}
                    </h2>
                    {count > 0 && (
                      <span className="ml-auto rounded-full bg-secondary px-2.5 py-1 text-[12px] font-extrabold">
                        {count} featured
                      </span>
                    )}
                  </div>
                  <p className="mt-4 flex-1 text-[15px] leading-relaxed text-muted-foreground">
                    {group.blurb}
                  </p>
                  <ul className="mt-5 space-y-2.5">
                    {group.points.map((point) => (
                      <li
                        key={point}
                        className="flex items-start gap-2.5 text-[13.5px] font-medium"
                      >
                        <span className="mt-0.5 text-foreground/60">
                          <ShieldCheck className="h-4 w-4" />
                        </span>
                        {point}
                      </li>
                    ))}
                  </ul>
                  <Button
                    className="mt-7 h-11 w-full rounded-full text-[14px] font-bold"
                    asChild
                  >
                    <Link to={group.to}>
                      {group.cta}
                      <ArrowRight className="ml-1 h-4 w-4" />
                    </Link>
                  </Button>
                </div>
              );
            })}
          </Reveal>
        </section>

        <div className="mx-auto grid max-w-5xl gap-4 px-4 py-8 sm:grid-cols-2">
          <div className="presentation-card"><Film size={24} /><h3>For the storytellers.</h3><p>Give your films a home in Director Studio, with team-granted publishing access.</p><div className="presentation-actions"><PresentationLink to="/roles/director">Explore Director</PresentationLink></div></div>
          <div className="presentation-card"><PenLine size={24} /><h3>For the longer thought.</h3><p>Make room for articles, essays, and the ideas that need more than a caption.</p><div className="presentation-actions"><PresentationLink to="/roles/writer">Explore Writer</PresentationLink></div></div>
        </div>
        {/* Whisper’s people and possibilities */}
        <section className="px-4 py-10 sm:px-6 lg:px-8 lg:py-14">
          <Reveal variant="scale" className="mx-auto max-w-4xl overflow-hidden rounded-[24px] bg-foreground p-7 text-primary-foreground sm:rounded-[32px] sm:p-14">
            <div className="mb-5 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary-foreground/10">
              <Handshake className="h-7 w-7" />
            </div>
            <h2 className="font-display text-[28px] font-extrabold sm:text-[36px]">
              Good things happen between people.
            </h2>
            <p className="mt-4 max-w-2xl text-[17px] leading-relaxed text-primary-foreground/80">
              The creators putting something new into the world. The coaches
              showing up for their people. The recruiters spotting potential.
              Whisper brings different perspectives together, with space for
              the conversations and communities that make it all feel human.
            </p>
            <div className="mt-8 flex flex-col gap-3 sm:flex-row">
              <Button
                size="lg"
                className="h-13 rounded-full bg-background px-7 text-[15px] font-semibold text-foreground hover:bg-background/90"
                asChild
              >
                <Link to="/for-creators">
                  Explore Creator Studio
                  <ArrowUpRight className="ml-1 h-4 w-4" />
                </Link>
              </Button>
              <Button
                size="lg"
                variant="outline"
                className="h-13 rounded-full border-primary-foreground/30 bg-transparent px-7 text-[15px] font-semibold text-primary-foreground hover:bg-primary-foreground/10 hover:text-primary-foreground"
                asChild
              >
                <Link to="/about">More about Whisper</Link>
              </Button>
            </div>
          </Reveal>
        </section>

        {/* Building the team — open surfaces & how we hire */}
        <section className="border-t border-border px-4 py-14 sm:px-6 lg:px-8 lg:py-20">
          <div className="mx-auto max-w-5xl">
            <Reveal variant="fade" className="mb-10 text-center">
              <span className="inline-flex items-center gap-2 rounded-full border border-border bg-card px-4 py-1.5 text-[13px] font-medium text-muted-foreground">
                <Rocket className="h-4 w-4" />
                We're building the team
              </span>
              <h2 className="mt-5 font-display text-[28px] font-extrabold sm:text-[36px]">
                Own a surface, not a job title.
              </h2>
              <p className="mx-auto mt-3 max-w-2xl text-[16px] leading-relaxed text-muted-foreground">
                Whisper hires against the bottleneck. Early people don't get a
                generalist role — they get a whole surface of the product to
                own, real equity, and the tools we already built to do the job.
              </p>
            </Reveal>

            <Reveal stagger className="grid gap-5 lg:grid-cols-3">
              {[
                {
                  icon: <ShieldCheck className="h-5 w-5" />,
                  title: "Community & Safety Lead",
                  own: "You own trust",
                  blurb:
                    "Run the private report queue, reviewed post corrections and appeals, and community health. Set fair standards based on evidence, not AI verdicts or report counts.",
                },
                {
                  icon: <Megaphone className="h-5 w-5" />,
                  title: "Brand Partnerships",
                  own: "You own the marketplace",
                  blurb:
                    "Bring brands to the sponsorship marketplace and keep them renewing. Escrow deals, applications, and creator matching are built — the pipeline is yours to fill.",
                },
                {
                  icon: <HeartHandshake className="h-5 w-5" />,
                  title: "Creator Success",
                  own: "You own the ladder",
                  blurb:
                    "Get creators from first post to first payout. Verification reviews, featured spotlights, and the earnings ladder exist — your job is making people climb it.",
                },
              ].map((role) => (
                <div
                  key={role.title}
                  className="flex flex-col rounded-[28px] border border-border bg-card p-7"
                >
                  <div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-secondary">
                    {role.icon}
                  </div>
                  <p className="mt-4 text-[11px] font-extrabold uppercase tracking-widest text-muted-foreground">
                    {role.own}
                  </p>
                  <h3 className="mt-1 font-display text-[20px] font-extrabold">
                    {role.title}
                  </h3>
                  <p className="mt-2 flex-1 text-[14.5px] leading-relaxed text-muted-foreground">
                    {role.blurb}
                  </p>
                </div>
              ))}
            </Reveal>

            <Reveal className="mt-6 grid gap-3 sm:grid-cols-3">
              {[
                {
                  icon: <Sparkles className="h-4 w-4" />,
                  text: "Equity over salary — early people share the upside.",
                },
                {
                  icon: <Check className="h-4 w-4" />,
                  text: "We dogfood our own recruiter tools to hire — apply inside the app.",
                },
                {
                  icon: <Users className="h-4 w-4" />,
                  text: "Small team, full ownership, direct line to the founder.",
                },
              ].map((v) => (
                <div
                  key={v.text}
                  className="flex items-start gap-2.5 rounded-2xl border border-border bg-card px-4 py-3.5 text-[13.5px] font-medium leading-snug"
                >
                  <span className="mt-0.5 text-foreground/60">{v.icon}</span>
                  {v.text}
                </div>
              ))}
            </Reveal>

            <div className="mt-8 text-center">
              <Button className="h-12 rounded-full px-8 text-[15px] font-semibold" asChild>
                <Link to="/auth?mode=signup">
                  Join us — apply in the app
                  <ArrowRight className="ml-1 h-4 w-4" />
                </Link>
              </Button>
              <p className="mt-3 text-[13px] text-muted-foreground">
                Creators climbing instead of hiring? See{" "}
                <Link to="/for-creators" className="font-semibold underline underline-offset-4">
                  the creator ladder
                </Link>
                .
              </p>
            </div>
          </div>
        </section>

        {/* Join CTA */}
        <section className="px-4 pb-20 pt-4 sm:px-6 lg:px-8">
          <Reveal className="mx-auto max-w-3xl rounded-[28px] border border-border bg-card p-10 text-center">
            <h2 className="font-display text-[24px] font-extrabold sm:text-[30px]">
              Think you belong on this page?
            </h2>
            <p className="mx-auto mt-3 max-w-xl text-[15.5px] leading-relaxed text-muted-foreground">
              Coach and Creator are application-based verified badges.
              Submitting an application is free — you're only ever billed after
              a real person approves you.
            </p>
            <Button className="mt-7 h-12 rounded-full px-8 text-[15px] font-semibold" asChild>
              <Link to="/auth?mode=signup">
                Apply in the app
                <ArrowRight className="ml-1 h-4 w-4" />
              </Link>
            </Button>
          </Reveal>
        </section>
      </main>

      <PublicFooter />
    </div>
  );
}
