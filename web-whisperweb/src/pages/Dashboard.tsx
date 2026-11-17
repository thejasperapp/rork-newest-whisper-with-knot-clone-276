import { useCallback, useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import {
  ArrowDownRight,
  ArrowLeft,
  ArrowUpRight,
  BadgeCheck,
  Clock,
  Crown,
  Eye,
  Heart,
  Image as ImageIcon,
  Lightbulb,
  MessageCircle,
  Sparkles,
  Target,
  TrendingUp,
  Brain,
  Briefcase,
  Users,
  WandSparkles,
} from "lucide-react";

import { Header } from "@/components/Header";
import { WppCard } from "@/components/WppCard";
import { Avatar } from "@/components/Avatar";
import { JasperAnalysisDock } from "@/components/JasperAnalysisDock";
import { useAuth } from "@/hooks/useAuth";
import { useMyBadge } from "@/hooks/useMyBadge";
import { fetchCreatorStats } from "@/lib/api";
import { openPortal } from "@/lib/portal";
import { compactCount, timeAgo } from "@/lib/format";
import {
  RECENCY_HALF_LIFE,
  SEEN_DECAY,
  algorithmBoost,
  rankEntries,
  scorePost,
} from "@/lib/algorithm";
import type { WhisperCreatorStats, WhisperPostStat } from "@/lib/types";

/**
 * Creator Studio — the iOS command-center design, 1:1: cinematic hero with
 * the animated Creator Score ring, momentum tiles, follower delta, top-post
 * spotlight, 14-day cadence bars, the real algorithm multipliers, and the
 * full ranked post list. Everything computes client-side from the same
 * numbers iOS uses.
 */

const ELECTRIC = "#409EFF";
const VIOLET = "#9E66FF";
const MINT = "#33D499";
const GOLD = "#FFC721";
const ROSE = "#FA5973";

/** Hours → ms guard for the 30-day window. */
const DAY_MS = 86_400_000;

function hoursAgo(iso: string | null): number {
  if (!iso) return Number.POSITIVE_INFINITY;
  const ts = new Date(iso).getTime();
  if (Number.isNaN(ts)) return Number.POSITIVE_INFINITY;
  return (Date.now() - ts) / 3_600_000;
}

/** The animated Creator Score ring — electric→violet→mint sweep. */
function ScoreRing({ score }: { score: number }) {
  const [progress, setProgress] = useState<number>(0);
  useEffect(() => {
    const t = window.setTimeout(() => setProgress(Math.max(0, Math.min(1, score / 100))), 180);
    return () => window.clearTimeout(t);
  }, [score]);
  const R = 40;
  const C = 2 * Math.PI * R;
  return (
    <div className="relative h-[88px] w-[88px] shrink-0">
      <svg viewBox="0 0 88 88" className="h-full w-full -rotate-90">
        <circle cx="44" cy="44" r={R} fill="none" stroke="rgba(255,255,255,0.10)" strokeWidth="8" />
        <defs>
          <linearGradient id="creator-score-ring" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor={ELECTRIC} />
            <stop offset="55%" stopColor={VIOLET} />
            <stop offset="100%" stopColor={MINT} />
          </linearGradient>
        </defs>
        <circle
          cx="44"
          cy="44"
          r={R}
          fill="none"
          stroke="url(#creator-score-ring)"
          strokeWidth="8"
          strokeLinecap="round"
          strokeDasharray={C}
          strokeDashoffset={C * (1 - progress)}
          style={{ transition: "stroke-dashoffset 1.1s cubic-bezier(0.34, 1.2, 0.5, 1)" }}
        />
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <p className="text-[26px] font-black leading-none text-white">{score}</p>
        <p className="mt-0.5 text-[8px] font-black uppercase tracking-[0.14em] text-white/55">
          Score
        </p>
      </div>
    </div>
  );
}

function HeroChip({ value, label }: { value: string; label: string }) {
  return (
    <div className="min-w-0 flex-1 rounded-xl border border-white/10 bg-white/[0.08] px-3 py-2">
      <p className="truncate text-[16px] font-black leading-tight text-white">{value}</p>
      <p className="mt-0.5 truncate text-[9px] font-bold uppercase tracking-[0.06em] text-white/55">
        {label}
      </p>
    </div>
  );
}

function MomentumTile({
  icon,
  value,
  label,
  tint,
}: {
  icon: React.ReactNode;
  value: string;
  label: string;
  tint: string;
}) {
  return (
    <div className="flex flex-1 items-center gap-2.5 rounded-2xl border border-border bg-card p-3">
      <span
        className="flex h-[34px] w-[34px] shrink-0 items-center justify-center rounded-full"
        style={{ background: `${tint}24`, color: tint }}
      >
        {icon}
      </span>
      <span className="min-w-0">
        <span className="block truncate text-[18px] font-black leading-tight">{value}</span>
        <span className="block truncate text-[10px] font-semibold text-muted-foreground">
          {label}
        </span>
      </span>
    </div>
  );
}

function AlgoRow({
  icon,
  tint,
  label,
  value,
  hint,
}: {
  icon: React.ReactNode;
  tint: string;
  label: string;
  value: string;
  hint: string;
}) {
  return (
    <div className="flex items-center gap-2.5 py-1.5">
      <span
        className="flex h-[26px] w-[26px] shrink-0 items-center justify-center rounded-full"
        style={{ background: `${tint}21`, color: tint }}
      >
        {icon}
      </span>
      <span className="min-w-0 flex-1">
        <span className="block text-[13px] font-bold leading-tight">{label}</span>
        <span className="block text-[11px] leading-snug text-muted-foreground">{hint}</span>
      </span>
      <span
        className="shrink-0 text-[12px] font-black tabular-nums"
        style={{ color: tint }}
      >
        {value}
      </span>
    </div>
  );
}

export default function Dashboard() {
  const { user, profile } = useAuth();
  const navigate = useNavigate();
  const badge = useMyBadge();
  const username = profile?.username ?? "";

  const statsQuery = useQuery({
    queryKey: ["creator-stats", user?.id],
    queryFn: () => fetchCreatorStats(user!.id),
    enabled: !!user,
  });

  const stats: WhisperCreatorStats = statsQuery.data ?? {
    posts: 0,
    likes: 0,
    comments: 0,
    reposts: 0,
    followers: 0,
    topPosts: [],
    entries: [],
  };

  const ranked = useMemo(
    () => rankEntries(stats.entries, badge),
    [stats.entries, badge]
  );

  // ── The iOS composite metrics (last 30 days) ─────────────────────────────
  const last30 = useMemo(
    () => stats.entries.filter((e) => hoursAgo(e.post.created_at) <= (30 * DAY_MS) / 3_600_000),
    [stats.entries]
  );
  const likes30 = last30.reduce((acc, e) => acc + e.likes, 0);
  const comments30 = last30.reduce((acc, e) => acc + e.comments, 0);
  const engagementPct30 = useMemo(() => {
    if (stats.followers <= 0 || last30.length === 0) return 0;
    return Math.min(100, ((likes30 + comments30) / (stats.followers * last30.length)) * 100);
  }, [stats.followers, last30.length, likes30, comments30]);

  /** Week-over-week follower delta from a locally stored weekly snapshot. */
  const [followerDelta, setFollowerDelta] = useState<number>(0);
  useEffect(() => {
    if (!statsQuery.isSuccess || !username) return;
    try {
      const key = `whisper_creator_studio_followers_${username.toLowerCase()}`;
      const stampKey = `${key}_at`;
      const last = Number(localStorage.getItem(key) ?? "0");
      const lastAt = Number(localStorage.getItem(stampKey) ?? "0");
      setFollowerDelta(last > 0 ? stats.followers - last : 0);
      const now = Date.now();
      if (now - lastAt > 7 * DAY_MS || last === 0) {
        localStorage.setItem(key, String(stats.followers));
        localStorage.setItem(stampKey, String(now));
      }
    } catch {
      /* storage unavailable */
    }
  }, [statsQuery.isSuccess, username, stats.followers]);

  /** 0–100 composite — engagement, cadence, audience, momentum (iOS math). */
  const creatorScore = useMemo(() => {
    const engagement = Math.min(40, engagementPct30 * 8);
    const cadence = Math.min(30, last30.length * 3);
    const audience = Math.min(20, stats.followers / 50);
    const momentum = followerDelta > 0 ? 10 : followerDelta < 0 ? 0 : 5;
    return Math.round(Math.min(100, engagement + cadence + audience + momentum));
  }, [engagementPct30, last30.length, stats.followers, followerDelta]);

  const scoreVerdict = useMemo(() => {
    if (creatorScore >= 75) return "On fire — the algorithm loves this pace.";
    if (creatorScore >= 50) return "Solid momentum. One more post this week pushes higher.";
    if (creatorScore >= 25) return "Warming up — consistency is your fastest lever.";
    return "Post something today to wake the algorithm up.";
  }, [creatorScore]);

  /** Posting cadence over the last 14 days, count per day (oldest first). */
  const cadence14 = useMemo(() => {
    const buckets = Array.from({ length: 14 }, () => 0);
    for (const e of stats.entries) {
      const h = hoursAgo(e.post.created_at);
      if (!Number.isFinite(h)) continue;
      const days = Math.floor(h / 24);
      if (days >= 0 && days < 14) buckets[13 - days] += 1;
    }
    return buckets;
  }, [stats.entries]);

  const cadenceHint = useMemo(() => {
    const recent = cadence14.slice(7).reduce((a, b) => a + b, 0);
    if (recent === 0) return "Nothing this week yet — even one post restarts your recency boost.";
    if (recent >= 5) return "Excellent rhythm — recency boost is working for you all week.";
    return `${recent} post${recent === 1 ? "" : "s"} this week. 4–5 keeps the recency boost alive.`;
  }, [cadence14]);

  const topPost: WhisperPostStat | null = ranked[0] ?? null;

  // Live creator context for the Jasper dock — the same client-side numbers
  // the dashboard cards render (iOS Creator Studio parity).
  const buildCreatorContext = useCallback((): string | null => {
    if (stats.posts === 0 && ranked.length === 0) return null;
    const reels = stats.entries.filter((e) => e.post.is_reel).length;
    const lines: string[] = [
      "CREATOR DASHBOARD (live, last 30 days)",
      `Creator score ${creatorScore}/100 · followers ${stats.followers} (${followerDelta >= 0 ? "+" : ""}${followerDelta} this week) · engagement ${engagementPct30.toFixed(1)}% · posts 30d ${last30.length}`,
      `Formats: ${reels} reels · ${stats.entries.length - reels} posts`,
    ];
    for (const entry of ranked.slice(0, 5)) {
      lines.push(
        `- ${entry.post.is_reel ? "reel" : "post"} · ${entry.likes} likes · ${entry.comments} comments · ${timeAgo(entry.post.created_at)} · ${(entry.post.caption || "(media)").slice(0, 60)}`
      );
    }
    return lines.join("\n");
  }, [stats, ranked, creatorScore, followerDelta, engagementPct30, last30.length]);

  const maxCadence = Math.max(1, ...cadence14);

  return (
    <div>
      <Header
        title="Creator Studio"
        left={
          <button
            onClick={() => navigate(-1)}
            aria-label="Back"
            className="glass flex h-10 w-10 items-center justify-center rounded-full border border-border/60 shadow-sm transition-transform active:scale-90"
          >
            <ArrowLeft className="h-5 w-5" />
          </button>
        }
        right={
          <div className="flex items-center gap-2">
            <button
              onClick={() => void openPortal("business")}
              aria-label="Whisper Business — sponsorship pipeline"
              title="Whisper Business — sponsorship pipeline"
              className="glass flex h-10 w-10 items-center justify-center rounded-full border border-border/60 shadow-sm transition-transform active:scale-90"
            >
              <Briefcase className="h-5 w-5 text-[#E76F3A]" />
            </button>
            {(badge === "admin" || badge === "owner") && (
              <button
                onClick={() => navigate("/jasper-brain")}
                aria-label="Jasper Brain — shared Jasper rules"
                title="Jasper Brain — shared Jasper rules"
                className="glass flex h-10 w-10 items-center justify-center rounded-full border border-border/60 shadow-sm transition-transform active:scale-90"
              >
                <Brain className="h-5 w-5 text-[#E76F3A]" />
              </button>
            )}
          </div>
        }
      />

      <div className="px-4 pt-2">
        <div className="mx-auto max-w-2xl space-y-3.5">
          {/* ── WPP — the ad-revenue share that pays creators ────────────── */}
          <WppCard />

          {/* ── Cinematic hero — identity, verdict, the score ring ─────────── */}
          <div
            className="rounded-[22px] p-4"
            style={{
              background: "linear-gradient(135deg, #0F142B 0%, #1A1A42 55%, #29174D 100%)",
              border: "1px solid transparent",
              backgroundImage:
                "linear-gradient(135deg, #0F142B 0%, #1A1A42 55%, #29174D 100%), linear-gradient(135deg, rgba(64,158,255,0.55), rgba(158,102,255,0.35), transparent)",
              backgroundOrigin: "border-box",
              backgroundClip: "padding-box, border-box",
            }}
          >
            <div className="flex items-start gap-3">
              <div className="min-w-0 flex-1 space-y-2.5">
                <div className="flex items-center gap-2">
                  <Avatar url={profile?.profile_image_url} name={username || "?"} size={34} />
                  <div className="min-w-0">
                    <p className="truncate text-[14px] font-black text-white">
                      @{username || "creator"}
                    </p>
                    <p
                      className="text-[10px] font-bold uppercase tracking-[0.08em]"
                      style={{ color: ELECTRIC }}
                    >
                      {badge !== "none" ? "Verified creator" : "Studio preview"}
                    </p>
                  </div>
                </div>
                <p className="text-[13px] font-semibold leading-snug text-white/75">
                  {scoreVerdict}
                </p>
              </div>
              <ScoreRing score={creatorScore} />
            </div>
            <div className="mt-4 flex gap-2">
              <HeroChip value={compactCount(stats.followers)} label="Followers" />
              <HeroChip value={`${engagementPct30.toFixed(1)}%`} label="Engage" />
              <HeroChip value={String(last30.length)} label="Posts · 30d" />
            </div>
          </div>

          {/* ── Momentum tiles ──────────────────────────────────────────────── */}
          <div className="flex gap-2.5">
            <MomentumTile
              icon={<Heart className="h-4 w-4" fill="currentColor" />}
              value={compactCount(likes30)}
              label="Likes · 30 days"
              tint={ROSE}
            />
            <MomentumTile
              icon={<MessageCircle className="h-4 w-4" fill="currentColor" />}
              value={compactCount(comments30)}
              label="Comments · 30 days"
              tint={ELECTRIC}
            />
          </div>

          {/* ── Followers with week-over-week delta ─────────────────────────── */}
          <div className="flex items-center gap-3 rounded-2xl border border-border bg-card p-3.5">
            <span
              className="flex h-[34px] w-[34px] shrink-0 items-center justify-center rounded-full"
              style={{ background: `${VIOLET}24`, color: VIOLET }}
            >
              <Users className="h-4 w-4" />
            </span>
            <span className="min-w-0 flex-1">
              <span className="block text-[10px] font-bold uppercase tracking-[0.06em] text-muted-foreground">
                Followers
              </span>
              <span className="block text-[21px] font-black leading-tight">
                {stats.followers.toLocaleString()}
              </span>
            </span>
            {followerDelta !== 0 ? (
              <span
                className="flex shrink-0 items-center gap-1 rounded-full px-2.5 py-1.5 text-[11.5px] font-bold"
                style={{
                  background: `${followerDelta > 0 ? MINT : "#F26659"}1f`,
                  color: followerDelta > 0 ? MINT : "#F26659",
                }}
              >
                {followerDelta > 0 ? (
                  <ArrowUpRight className="h-3 w-3" strokeWidth={3} />
                ) : (
                  <ArrowDownRight className="h-3 w-3" strokeWidth={3} />
                )}
                {followerDelta > 0 ? "+" : ""}
                {followerDelta} this week
              </span>
            ) : (
              <span className="text-[12px] font-semibold text-muted-foreground">steady</span>
            )}
          </div>

          {/* ── Top-post spotlight ──────────────────────────────────────────── */}
          {topPost && (
            <div
              className="rounded-2xl border bg-card p-3.5"
              style={{ borderColor: `${GOLD}66` }}
            >
              <div className="flex items-center gap-2">
                <Crown className="h-3.5 w-3.5" style={{ color: GOLD }} fill={GOLD} />
                <p className="text-[13.5px] font-black">Top performing post</p>
                <span
                  className="ml-auto rounded-full px-2.5 py-0.5 text-[11.5px] font-black text-black"
                  style={{ background: GOLD }}
                >
                  {scorePost(topPost, badge).toFixed(1)}
                </span>
              </div>
              <p className="mt-2 line-clamp-3 text-[13.5px] leading-relaxed">
                {topPost.post.caption || "(media post)"}
              </p>
              <div className="mt-2.5 flex items-center gap-3.5 text-[11.5px] font-bold">
                <span className="flex items-center gap-1" style={{ color: ROSE }}>
                  <Heart className="h-3 w-3" fill="currentColor" /> {topPost.likes}
                </span>
                <span className="flex items-center gap-1" style={{ color: ELECTRIC }}>
                  <MessageCircle className="h-3 w-3" fill="currentColor" /> {topPost.comments}
                </span>
                <span className="ml-auto font-semibold text-muted-foreground">
                  {timeAgo(topPost.post.created_at)}
                </span>
              </div>
            </div>
          )}

          {/* ── 14-day cadence bars ─────────────────────────────────────────── */}
          <div className="rounded-2xl border border-border bg-card p-3.5">
            <div className="flex items-baseline justify-between">
              <p className="text-[13.5px] font-black">Posting cadence</p>
              <p className="text-[10.5px] font-semibold text-muted-foreground">last 14 days</p>
            </div>
            <div className="mt-2.5 flex h-[60px] items-end gap-1">
              {cadence14.map((count, i) => {
                const h = Math.max(4, (count / maxCadence) * 56);
                const isToday = i === cadence14.length - 1;
                return (
                  <span
                    key={i}
                    className="min-w-0 flex-1 rounded-[4px]"
                    style={{
                      height: h,
                      background:
                        count === 0
                          ? "hsl(var(--border))"
                          : isToday
                            ? `linear-gradient(to top, ${MINT}, ${ELECTRIC})`
                            : `linear-gradient(to top, ${ELECTRIC}8C, ${ELECTRIC})`,
                    }}
                  />
                );
              })}
            </div>
            <p className="mt-2 text-[10.5px] font-semibold text-muted-foreground">{cadenceHint}</p>
          </div>

          {/* ── What the algorithm sees — the real multipliers ─────────────── */}
          <div className="rounded-2xl border border-border bg-card p-3.5">
            <div className="flex items-center gap-2 pb-1.5">
              <WandSparkles className="h-4 w-4" style={{ color: VIOLET }} />
              <p className="text-[13.5px] font-black">What the algorithm sees</p>
            </div>
            <AlgoRow
              icon={<BadgeCheck className="h-3 w-3" />}
              tint={ELECTRIC}
              label="Badge boost"
              value={`${algorithmBoost(badge).toFixed(2)}×`}
              hint={
                badge === "none"
                  ? "Get verified to unlock a feed multiplier."
                  : "Active when a post has ≥ 3 likes + comments."
              }
            />
            <AlgoRow
              icon={<Clock className="h-3 w-3" />}
              tint={MINT}
              label="Recency half-life"
              value={`${RECENCY_HALF_LIFE}h`}
              hint="Posts decay smoothly — ~3d of strong push."
            />
            <AlgoRow
              icon={<Eye className="h-3 w-3" />}
              tint={GOLD}
              label="Seen decay"
              value={`${SEEN_DECAY.toFixed(2)}×`}
              hint="Applied after a viewer scrolls past once."
            />
            <AlgoRow
              icon={<Target className="h-3 w-3" />}
              tint={ROSE}
              label="Interest match"
              value="1.40×"
              hint="Use specific topic words in captions."
            />
            <AlgoRow
              icon={<ImageIcon className="h-3 w-3" />}
              tint={VIOLET}
              label="Media bonus"
              value="1.15× / video 1.10×"
              hint="Attaching media outperforms text-only."
            />
          </div>

          {/* ── Full ranked post list ───────────────────────────────────────── */}
          <div className="rounded-2xl border border-border bg-card p-3.5">
            <p className="pb-1.5 text-[13.5px] font-black">Your posts, ranked</p>
            {statsQuery.isLoading ? (
              <p className="py-8 text-center text-[12.5px] text-muted-foreground">
                Scoring your posts…
              </p>
            ) : ranked.length === 0 ? (
              <p className="py-8 text-center text-[12.5px] text-muted-foreground">
                Post something to start seeing analytics here.
              </p>
            ) : (
              ranked.slice(0, 20).map((entry, index) => {
                const media = (entry.post.media_urls ?? [])[0];
                const rank = index + 1;
                return (
                  <div key={entry.post.id} className="flex items-center gap-2.5 py-2">
                    <span
                      className="w-[26px] shrink-0 text-[11px] font-black"
                      style={{ color: rank <= 3 ? GOLD : undefined }}
                    >
                      #{rank}
                    </span>
                    {media ? (
                      <img
                        src={media}
                        alt=""
                        className="h-[26px] w-[26px] shrink-0 rounded-full object-cover"
                      />
                    ) : (
                      <span
                        className="flex h-[26px] w-[26px] shrink-0 items-center justify-center rounded-full"
                        style={{ background: `${ELECTRIC}21`, color: ELECTRIC }}
                      >
                        <Sparkles className="h-3 w-3" />
                      </span>
                    )}
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-[13px] font-semibold">
                        {entry.post.caption || "(media)"}
                      </span>
                      <span className="block truncate text-[11px] text-muted-foreground">
                        {entry.likes} likes · {entry.comments} comments ·{" "}
                        {timeAgo(entry.post.created_at)}
                      </span>
                    </span>
                    <span
                      className="shrink-0 rounded-full px-2 py-1 text-[11px] font-black tabular-nums"
                      style={{ background: `${ELECTRIC}1f`, color: ELECTRIC }}
                    >
                      {scorePost(entry, badge).toFixed(1)}
                    </span>
                  </div>
                );
              })
            )}
          </div>

          <div className="h-28" />
        </div>
      </div>

      {/* The meeting-style Jasper dock — a live read of the creator numbers
          with content-focused quick lenses (iOS Creator Studio parity). */}
      <JasperAnalysisDock
        pillLabel="Knot's read"
        boxTitle="Creator analysis"
        focus="You are analyzing a creator's private analytics. From the numbers and recent posts below, give a tight read: what's genuinely working (name the actual post), the one metric holding the score back, then ONE concrete move for this week. Speak to the creator directly. No generic advice."
        buildContext={buildCreatorContext}
        emptyText="Post something first — then I'll read your numbers here."
        actions={[
          {
            id: "ideas",
            label: "Post ideas",
            icon: Lightbulb,
            kind: "lens",
            focus:
              "From what performed below, pitch 3 specific post ideas this creator should make next — one line each (format + hook), grounded in their best-performing content. No generic filler.",
          },
          {
            id: "growth",
            label: "Growth move",
            icon: TrendingUp,
            kind: "lens",
            focus:
              "Pick the SINGLE highest-leverage growth move for this creator right now (cadence, format shift, reels vs photos, engagement plays) based on the numbers below — explain it in 2-3 sentences with the expected effect.",
          },
        ]}
      />
    </div>
  );
}
