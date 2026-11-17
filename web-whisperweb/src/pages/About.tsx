import { useCallback, useState } from "react";
import { Link } from "react-router-dom";
import {
  ArrowRight,
  CheckCircle2,
  Clapperboard,
  Download,
  Flame,
  Loader2,
  MessageCircle,
  ShieldCheck,
  Trophy,
  Users,
  Dumbbell,
  BarChart3,
} from "lucide-react";

import PublicNav from "@/components/PublicNav";
import PublicFooter from "@/components/PublicFooter";
import { WhisperLogo } from "@/components/WhisperLogo";
import { Reveal } from "@/components/Reveal";
import { Button } from "@/components/ui/button";
import { useMyBadge } from "@/hooks/useMyBadge";
import { isModOrHigher } from "@/lib/pitch";

/** Generated Instagram-style vertical ad for the Whisper app (mp4). */
const AD_VIDEO_URL =
  "https://rork.app/pa/96n31cqsobjtcpjwj8oyl/whisper_social_connection";

/**
 * Team-only ad asset section — visible to moderator status and above.
 * Shows the Instagram-style vertical video ad in a phone frame with a
 * one-click .mp4 download so the team can repost it anywhere.
 */
function TeamAdSection() {
  const badge = useMyBadge();
  const [videoFailed, setVideoFailed] = useState<boolean>(false);
  const [downloading, setDownloading] = useState<boolean>(false);

  const handleDownload = useCallback(async () => {
    setDownloading(true);
    try {
      const res = await fetch(AD_VIDEO_URL);
      if (!res.ok) throw new Error(`download failed: ${res.status}`);
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = "whisper-instagram-ad.mp4";
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
    } catch (err) {
      console.error("[About] ad download failed", err);
      window.open(AD_VIDEO_URL, "_blank");
    } finally {
      setDownloading(false);
    }
  }, []);

  if (!isModOrHigher(badge)) return null;

  return (
    <section className="border-t border-border px-4 py-14 sm:px-6 lg:px-8 lg:py-20">
      <div className="mx-auto max-w-5xl">
        <Reveal variant="fade" className="mb-10 text-center">
          <span className="inline-flex items-center gap-1.5 rounded-full border border-border bg-secondary px-3 py-1 text-[12px] font-semibold uppercase tracking-wide text-muted-foreground">
            <ShieldCheck className="h-3.5 w-3.5" />
            Moderators &amp; above only
          </span>
          <h2 className="mt-4 font-display text-[28px] font-extrabold sm:text-[36px]">
            Whisper video ad
          </h2>
          <p className="mt-3 text-[17px] text-muted-foreground">
            Instagram-style vertical spot for the app. Preview it here or
            download the .mp4 to post it anywhere.
          </p>
        </Reveal>

        <Reveal className="flex flex-col items-center gap-8 lg:flex-row lg:items-start lg:justify-center lg:gap-14">
          {/* Phone-framed 9:16 preview */}
          <div className="relative w-[270px] shrink-0 overflow-hidden rounded-[36px] border-[6px] border-foreground/90 bg-black shadow-2xl">
            <div className="absolute left-1/2 top-2 z-10 h-5 w-24 -translate-x-1/2 rounded-full bg-black" />
            <div className="aspect-[9/16] w-full">
              {videoFailed ? (
                <div className="flex h-full flex-col items-center justify-center gap-3 px-6 text-center">
                  <Clapperboard className="h-8 w-8 text-white/60" />
                  <p className="text-[14px] font-semibold text-white">
                    Ad video is still rendering
                  </p>
                  <p className="text-[12px] leading-relaxed text-white/60">
                    The clip hasn&apos;t finished generating yet — check back in
                    a few minutes.
                  </p>
                </div>
              ) : (
                <video
                  src={AD_VIDEO_URL}
                  className="h-full w-full object-cover"
                  autoPlay
                  muted
                  loop
                  playsInline
                  controls
                  onError={() => setVideoFailed(true)}
                />
              )}
            </div>
          </div>

          {/* Copy + download */}
          <div className="max-w-md text-center lg:pt-10 lg:text-left">
            <h3 className="text-[22px] font-bold">Built for the feed</h3>
            <p className="mt-3 text-[16px] leading-relaxed text-muted-foreground">
              9:16 vertical, high-contrast monochrome grade, punchy cuts —
              drop it straight into Instagram Reels, Stories, or TikTok. It
              sells Whisper as what it is: a social app about real connection,
              with fitness as just one slice of life. No watermark, ready to
              caption.
            </p>
            <ul className="mt-6 space-y-3 text-left">
              {[
                "Vertical 9:16 — native Reels & Stories format",
                "On-brand black & white with the Whisper energy",
                "MP4 file — works everywhere",
              ].map((line) => (
                <li key={line} className="flex items-start gap-3 text-[15px]">
                  <CheckCircle2 className="mt-0.5 h-5 w-5 shrink-0 text-emerald-500" />
                  <span className="leading-snug text-foreground/90">{line}</span>
                </li>
              ))}
            </ul>
            <Button
              size="lg"
              className="mt-8 h-12 rounded-full px-7 text-[15px] font-semibold"
              onClick={handleDownload}
              disabled={downloading || videoFailed}
            >
              {downloading ? (
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              ) : (
                <Download className="mr-2 h-4 w-4" />
              )}
              {downloading ? "Preparing download…" : "Download .mp4"}
            </Button>
          </div>
        </Reveal>
      </div>
    </section>
  );
}

const WHO_IT_IS_FOR = [
  {
    icon: <Users className="h-6 w-6" />,
    title: "Everyone",
    description:
      "Whisper is a social app first — share your day, post stories and reels, drop notes, and keep up with the people who actually matter to you.",
  },
  {
    icon: <BarChart3 className="h-6 w-6" />,
    title: "Creators",
    description:
      "Grow your audience with a verified blue check, algorithmic boost, and long-form posts. Get seen in Discover and trending rails.",
  },
  {
    icon: <Trophy className="h-6 w-6" />,
    title: "Athletes",
    description:
      "When training is your life, Whisper keeps up — highlight your PRs, get discovered, and unlock a dedicated stat sheet and meet countdown.",
  },
  {
    icon: <Dumbbell className="h-6 w-6" />,
    title: "Coaches",
    description:
      "Build programs, send macros, and manage clients through private threads. Verified coaches unlock the Coach Studio and rich DM embeds.",
  },
];

const VALUES = [
  "Your everyday, shared through posts, stories, Waves, and conversations.",
  "Fair accountability: reviewed post corrections, supporting sources, and private appeals.",
  "Knot helps you find the words, explore ideas, and make a plan. Review important AI answers.",
  "Your content, your profile, your communities. Apply for the role that fits you.",
];

export default function About() {
  return (
    <div className="min-h-screen bg-background">
      <PublicNav />

      <main>
        {/* Hero */}
        <section className="px-4 pb-16 pt-32 sm:px-6 lg:px-8 lg:pt-40">
          <div className="mx-auto max-w-4xl text-center">
            <h1 className="font-display text-[38px] font-extrabold leading-[1.1] tracking-tight sm:text-[52px] lg:text-[64px]">
              Whisper is the social network built on real connection.
            </h1>
            <p className="mx-auto mt-6 max-w-2xl text-[18px] leading-relaxed text-muted-foreground sm:text-[20px]">
              A social app for real conversations, real communities, and the
              people who matter. Share your life, ask your questions, and get
              a little perspective from Knot and your community. Create, connect,
              or find your next opportunity — in a way that feels like you.
            </p>
          </div>
        </section>

        {/* What it is */}
        <section className="border-y border-border px-4 py-14 sm:px-6 lg:px-8 lg:py-20">
          <div className="mx-auto grid max-w-6xl gap-12 lg:grid-cols-2 lg:items-center">
            <Reveal>
              <h2 className="font-display text-[28px] font-extrabold sm:text-[36px]">
                What makes Whisper different?
              </h2>
              <p className="mt-4 text-[17px] leading-relaxed text-muted-foreground">
                Most social apps are built to keep you scrolling. Whisper is
                built to keep you connected. Every feature — the feed, the DMs,
                the verified roles, and Knot — makes room for real people
                and different parts of life. The small everyday moments,
                the creative work, and the connections that go somewhere.
              </p>
              <ul className="mt-8 space-y-4">
                {VALUES.map((value) => (
                  <li key={value} className="flex items-start gap-3 text-[16px]">
                    <CheckCircle2 className="mt-0.5 h-5 w-5 shrink-0 text-emerald-500" />
                    <span className="leading-snug text-foreground/90">{value}</span>
                  </li>
                ))}
              </ul>
            </Reveal>
            <Reveal variant="left" className="grid gap-4">
              <div className="rounded-3xl border border-border bg-card p-6">
                <div className="mb-3 flex h-10 w-10 items-center justify-center rounded-2xl bg-secondary">
                  <Flame className="h-5 w-5 text-foreground" />
                </div>
                <h3 className="text-[18px] font-bold">A little help from Knot</h3>
                <p className="mt-2 text-[15px] leading-relaxed text-muted-foreground">
                  Whisper’s familiar assistant helps with writing, explanations,
                  ideas, and planning. Think of him as a little company for a big thought.
                </p>
              </div>
              <div className="rounded-3xl border border-border bg-card p-6">
                <div className="mb-3 flex h-10 w-10 items-center justify-center rounded-2xl bg-secondary">
                  <MessageCircle className="h-5 w-5 text-foreground" />
                </div>
                <h3 className="text-[18px] font-bold">DMs that do work</h3>
                <p className="mt-2 text-[15px] leading-relaxed text-muted-foreground">
                  Coaches can send structured programs, macros, targets, and diet
                  plans directly inside a conversation thread.
                </p>
              </div>
            </Reveal>
          </div>
        </section>

        {/* Who it's for */}
        <section className="px-4 py-14 sm:px-6 lg:px-8 lg:py-20">
          <div className="mx-auto max-w-6xl">
            <Reveal variant="fade" className="mb-12 text-center">
              <h2 className="font-display text-[28px] font-extrabold sm:text-[36px]">
                Who is Whisper for?
              </h2>
              <p className="mt-3 text-[17px] text-muted-foreground">
                Everyone gets the feed. Some get superpowers.
              </p>
            </Reveal>
            <Reveal stagger className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              {WHO_IT_IS_FOR.map((item) => (
                <div
                  key={item.title}
                  className="rounded-3xl border border-border bg-card p-6"
                >
                  <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-2xl bg-secondary">
                    {item.icon}
                  </div>
                  <h3 className="text-[19px] font-bold">{item.title}</h3>
                  <p className="mt-2 text-[15px] leading-relaxed text-muted-foreground">
                    {item.description}
                  </p>
                </div>
              ))}
            </Reveal>
          </div>
        </section>

        {/* Roles */}
        <section className="border-y border-border px-4 py-14 sm:px-6 lg:px-8 lg:py-20">
          <div className="mx-auto max-w-6xl">
            <Reveal variant="fade" className="mb-12 text-center">
              <h2 className="font-display text-[28px] font-extrabold sm:text-[36px]">
                Free to use. Verified to stand out.
              </h2>
              <p className="mt-3 text-[17px] text-muted-foreground">
                Everyone can post, follow, and message. Verified roles are
                application-based and unlock professional tools.
              </p>
            </Reveal>
            <Reveal stagger className="grid gap-4 md:grid-cols-3">
              <div className="rounded-3xl border border-border bg-card p-6">
                <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-2xl bg-sky-500/10">
                  <ShieldCheck className="h-6 w-6 text-sky-500" />
                </div>
                <h3 className="text-[20px] font-bold">Verified Creator</h3>
                <p className="mt-2 text-[15px] leading-relaxed text-muted-foreground">
                  Blue check, 1.6× algorithmic boost, long-form posts,
                  trending priority, and early access to new features.
                </p>
              </div>
              <div className="rounded-3xl border border-border bg-card p-6">
                <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-2xl bg-orange-500/10">
                  <Dumbbell className="h-6 w-6 text-orange-500" />
                </div>
                <h3 className="text-[20px] font-bold">Verified Coach</h3>
                <p className="mt-2 text-[15px] leading-relaxed text-muted-foreground">
                  Coach role, Coach Studio, client programs, macros, diet
                  plans, targets, and proposals in DMs.
                </p>
              </div>
              <div className="rounded-3xl border border-border bg-card p-6">
                <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-2xl bg-rose-500/10">
                  <Trophy className="h-6 w-6 text-rose-500" />
                </div>
                <h3 className="text-[20px] font-bold">Verified Athlete</h3>
                <p className="mt-2 text-[15px] leading-relaxed text-muted-foreground">
                  Athlete role label, stat sheet, meet countdown, and
                  discovery filters so coaches and fans can find you.
                </p>
              </div>
            </Reveal>
            <div className="mt-8 text-center">
              <Button
                variant="outline"
                className="rounded-full px-6 text-[15px] font-semibold"
                asChild
              >
                <Link to="/monetization">
                  Compare packages
                  <ArrowRight className="ml-1 h-4 w-4" />
                </Link>
              </Button>
            </div>
          </div>
        </section>

        {/* Team-only ad asset (moderator+) */}
        <TeamAdSection />

        {/* CTA */}
        <section className="px-4 py-14 sm:px-6 lg:px-8 lg:py-20">
          <Reveal variant="scale" className="mx-auto max-w-3xl rounded-[24px] bg-foreground p-7 text-center text-primary-foreground sm:rounded-[32px] sm:p-14">
            <WhisperLogo size={36} className="mx-auto mb-5" />
            <h2 className="font-display text-[24px] font-extrabold sm:text-[40px]">
              Join the movement
            </h2>
            <p className="mt-4 text-[17px] text-primary-foreground/80">
              Whisper is free to join. Apply for a verified role whenever you’re
              ready to level up.
            </p>
            <div className="mt-8 flex flex-col justify-center gap-3 sm:flex-row">
              <Button
                size="lg"
                className="h-14 rounded-full bg-background px-8 text-[16px] font-semibold text-foreground hover:bg-background/90"
                asChild
              >
                <Link to="/auth?mode=signup">
                  Create your account
                  <ArrowRight className="ml-1 h-5 w-5" />
                </Link>
              </Button>
              <Button
                size="lg"
                variant="outline"
                className="h-14 rounded-full border-primary-foreground/30 bg-transparent px-8 text-[16px] font-semibold text-primary-foreground hover:bg-primary-foreground/10 hover:text-primary-foreground"
                asChild
              >
                <Link to="/monetization">View packages</Link>
              </Button>
            </div>
          </Reveal>
        </section>
      </main>

      <PublicFooter />
    </div>
  );
}
