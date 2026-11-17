import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { ArrowRight, Check, Medal, Trophy, UserSearch } from "lucide-react";

import PublicNav from "@/components/PublicNav";
import PublicFooter from "@/components/PublicFooter";
import { PresentationIntro, PresentationLink } from "@/components/Presentation";
import { FeaturedProfileCard } from "@/components/FeaturedProfileCard";
import { Reveal } from "@/components/Reveal";
import { SealBadge } from "@/components/SealBadge";
import { Button } from "@/components/ui/button";
import { usePageMeta } from "@/hooks/usePageMeta";
import {
  fetchFeaturedProfiles,
  TAYLOR_BROOKE_TEMPLATE,
  type FeaturedKind,
  type FeaturedProfile,
} from "@/lib/featured";

interface KindCopy {
  badge: React.ReactNode;
  badgeLabel: string;
  heading: string;
  sub: string;
  emptyTitle: string;
  emptyBody: string;
  ctaHeading: string;
  ctaBody: string;
  applyLabel: string;
  roleLink: string;
  meta: { title: string; description: string };
}

function AthleteSeal({ size = 14 }: { size?: number }) {
  return (
    <SealBadge
      size={size + 3}
      colors={["#fb7185", "#e11d48"]}
      shadowColor="#e11d48"
      title="Verified Athlete"
    >
      <Trophy style={{ width: size * 0.5, height: size * 0.5 }} strokeWidth={3} />
    </SealBadge>
  );
}

function CreatorSeal({ size = 14 }: { size?: number }) {
  return (
    <SealBadge
      size={size + 3}
      colors={["#4aa8ff", "#2f86f0"]}
      shadowColor="#3399ff"
      title="Verified Creator"
    >
      <Check style={{ width: size * 0.5, height: size * 0.5 }} strokeWidth={3.5} />
    </SealBadge>
  );
}

function RecruiterSeal({ size = 14 }: { size?: number }) {
  return (
    <SealBadge
      size={size + 3}
      colors={["#34d399", "#059669"]}
      shadowColor="#10b981"
      title="Whisper Recruiter"
    >
      <UserSearch
        style={{ width: size * 0.5, height: size * 0.5 }}
        strokeWidth={3}
      />
    </SealBadge>
  );
}

const COPY: Record<"athletes" | "creators" | "recruiters", KindCopy> = {
  athletes: {
    badge: <AthleteSeal />,
    badgeLabel: "Every athlete is verified & reviewed",
    heading: "Meet the Whisper athletes.",
    sub: "Verified competitors sharing the real grind — training blocks, PRs, and honest check-ins. No highlight-reel-only accounts here.",
    emptyTitle: "Athlete spotlights are coming.",
    emptyBody:
      "Athlete verification is application-based and reviewed by a real person — the first spotlights are being finalized right now.",
    ctaHeading: "Compete? Get the athlete seal.",
    ctaBody:
      "Athlete verification is application-based. Submit your competitive history in the app and, if approved, unlock the athlete badge for $99.99/year.",
    applyLabel: "Apply as an athlete",
    roleLink: "/roles/athlete",
    meta: {
      title: "Athletes",
      description:
        "Meet Whisper's verified athletes — real competitors sharing training blocks, PRs, and honest progress.",
    },
  },
  creators: {
    badge: <CreatorSeal />,
    badgeLabel: "Every creator is verified & reviewed",
    heading: "Meet the Whisper creators.",
    sub: "Creators with their own perspective—from training and education to art, music, and the everyday things worth sharing. Meet the person behind the work.",
    emptyTitle: "Creator spotlights are coming.",
    emptyBody:
      "Creator verification is application-based and reviewed by a real person — the first spotlights are being finalized right now.",
    ctaHeading: "Make something that feels like you.",
    ctaBody:
      "Submit your work for review. Approved Creator access is $99.99/year, billed only after approval. Your role appears in your profile details, alongside your existing creator tools.",
    applyLabel: "Apply as a creator",
    roleLink: "/roles/creator",
    meta: {
      title: "Creators",
      description:
        "Meet Whisper's verified creators — trusted voices making fitness content that teaches instead of sells.",
    },
  },
  recruiters: {
    badge: <RecruiterSeal />,
    badgeLabel: "Every recruiter is hand-picked & vetted",
    heading: "Meet the Whisper recruiters.",
    sub: "The talent scouts of Whisper — recruiters find standout coaches, athletes, and creators in their territory and bring them onto the platform.",
    emptyTitle: "Recruiter spotlights are coming.",
    emptyBody:
      "The recruiter program is application-based and every recruiter is reviewed by a real person — the first spotlights are being finalized right now.",
    ctaHeading: "Know talent when you see it?",
    ctaBody:
      "Recruiting on Whisper is application-based and free — you get a territory, a prospect pipeline, and the tools to promote the coaches, athletes, and creators you discover.",
    applyLabel: "Apply as a recruiter",
    roleLink: "/roles/recruiter",
    meta: {
      title: "Recruiters",
      description:
        "Meet Whisper's recruiters — hand-picked talent scouts who find and onboard the platform's best coaches, athletes, and creators.",
    },
  },
};

interface TeamMembersProps {
  kind: "athletes" | "creators" | "recruiters";
}

/** Public directory for athletes, creators, and recruiters. */
export default function TeamMembers({ kind }: TeamMembersProps) {
  const copy = COPY[kind];

  usePageMeta(copy.meta.title, copy.meta.description);

  const featuredKind: FeaturedKind =
    kind === "creators"
      ? "creator"
      : kind === "recruiters"
        ? "recruiter"
        : "athlete";
  const featured = useQuery({
    queryKey: ["featured-profiles", featuredKind],
    queryFn: () => fetchFeaturedProfiles(featuredKind),
    staleTime: 60_000,
  });

  const dynamic = featured.data ?? [];

  // The admin created a Taylor Brooke row but with thin content. We enrich
  // it at render time with the detailed template (from her website) while
  // keeping their uploaded photo and any username link. This way the public
  // creators page always shows the rich, personalized spotlight.
  const profiles: FeaturedProfile[] =
    kind === "creators"
      ? dynamic.map((p) => {
          if (p.name.trim().toLowerCase() !== "taylor brooke") return p;
          return {
            ...TAYLOR_BROOKE_TEMPLATE,
            // Keep the admin's uploaded photo and any linked account
            photo_url: p.photo_url || TAYLOR_BROOKE_TEMPLATE.photo_url,
            username: p.username ?? null,
            user_id: p.user_id ?? null,
            id: p.id,
          };
        })
      : dynamic;

  // If no Taylor Brooke row exists at all, prepend the built-in template.
  const hasTaylor = profiles.some(
    (p) => p.name.trim().toLowerCase() === "taylor brooke"
  );
  const finalProfiles: FeaturedProfile[] =
    kind === "creators" && !hasTaylor
      ? [TAYLOR_BROOKE_TEMPLATE, ...profiles]
      : profiles;

  return (
    <div className="presentation-page min-h-screen bg-background">
      <PublicNav />

      <main>
        <div className="presentation-container !pb-0"><PresentationIntro eyebrow={`The Whisper ${kind}`} title={kind === "recruiters" ? "Good people know good people." : "A point of view worth knowing."} description={copy.sub}>
          <PresentationLink to={copy.roleLink} primary>Explore the role</PresentationLink><PresentationLink to="/team">Meet the wider community</PresentationLink>
        </PresentationIntro><p className="presentation-body mb-8 max-w-2xl">Professional roles describe what people do. They are not a guarantee of safety, quality, or the accuracy of every claim.</p></div>

        {/* Featured spotlight cards */}
        <section className="px-4 py-10 sm:px-6 lg:px-8">
          <div className="mx-auto max-w-5xl">
            {finalProfiles.length > 0 ? (
              <div className="space-y-14">
                {finalProfiles.map((profile) => (
                  <Reveal key={profile.id}>
                    <FeaturedProfileCard profile={profile} />
                  </Reveal>
                ))}
              </div>
            ) : (
              <div className="rounded-[28px] border border-dashed border-border p-10 text-center">
                <p className="text-[16px] font-semibold">{copy.emptyTitle}</p>
                <p className="mx-auto mt-1.5 max-w-xl text-[14.5px] text-muted-foreground">
                  {copy.emptyBody}
                </p>
              </div>
            )}
          </div>
        </section>

        {/* Apply CTA */}
        <section className="px-4 py-14 pb-20 sm:px-6 lg:px-8">
          <Reveal variant="scale" className="mx-auto max-w-3xl rounded-[32px] bg-foreground p-10 text-center text-primary-foreground sm:p-14">
            <div className="mx-auto mb-5 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary-foreground/10">
              <Medal className="h-7 w-7" />
            </div>
            <h2 className="font-display text-[28px] font-extrabold sm:text-[36px]">
              {copy.ctaHeading}
            </h2>
            <p className="mx-auto mt-4 max-w-xl text-[17px] text-primary-foreground/80">
              {copy.ctaBody}
            </p>
            <div className="mt-8 flex flex-col justify-center gap-3 sm:flex-row">
              <Button
                size="lg"
                className="h-14 rounded-full bg-background px-8 text-[16px] font-semibold text-foreground hover:bg-background/90"
                asChild
              >
                <Link to="/auth?mode=signup">
                  {copy.applyLabel}
                  <ArrowRight className="ml-1 h-5 w-5" />
                </Link>
              </Button>
              <Button
                size="lg"
                variant="outline"
                className="h-14 rounded-full border-primary-foreground/30 bg-transparent px-8 text-[16px] font-semibold text-primary-foreground hover:bg-primary-foreground/10 hover:text-primary-foreground"
                asChild
              >
                <Link to={copy.roleLink}>What the role unlocks</Link>
              </Button>
            </div>
          </Reveal>
        </section>
      </main>

      <PublicFooter />
    </div>
  );
}
