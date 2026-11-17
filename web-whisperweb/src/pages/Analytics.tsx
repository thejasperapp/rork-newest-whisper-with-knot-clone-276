import { useMemo, useState } from "react";
import { Navigate, useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import {
  ArrowLeft,
  BadgeCheck,
  BarChart3,
  Heart,
  LayoutGrid,
  Users,
} from "lucide-react";
import { Bar, BarChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";

import { Header } from "@/components/Header";
import { GradientTypeIn } from "@/components/GradientTypeIn";
import { useAuth } from "@/hooks/useAuth";
import {
  canOpenAnalytics,
  canOpenCreatorStudio,
  tierLabel,
} from "@/lib/accountAccess";
import { fetchFollowCounts, fetchPostsByUser } from "@/lib/api";
import {
  WHISPER_BRAND_ACCENT,
  WHISPER_BRAND_GRADIENT_DIAGONAL,
  WHISPER_BRAND_INDIGO,
  WHISPER_BRAND_MINT,
} from "@/lib/brand";
import { stripPostMeta } from "@/lib/postMeta";
import type { WhisperPost } from "@/lib/types";
import { cn } from "@/lib/utils";

type RangeDays = 7 | 30 | 90;

interface Entry {
  post: WhisperPost;
  date: Date;
  likes: number;
  comments: number;
  interactions: number;
  isWave: boolean;
  hasMedia: boolean;
}

function compact(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 10_000) return `${Math.round(n / 1_000)}K`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
  return String(n);
}

function delta(now: number, before: number): number | null {
  if (before <= 0) return null;
  return Math.round(((now - before) / before) * 100);
}

/**
 * ANALYTICS — the insights page for PROFESSIONAL accounts (self-selected
 * creator / business types) and Whisper One members. Deliberately the basic
 * tier: reach on your own posts, interactions, followers, content mix, top
 * posts. Creator Studio (score ring, WPP creator pay, momentum) stays
 * VERIFIED-ONLY — this page says so plainly at the bottom instead of
 * pretending to be it. Mirrors iOS `WhisperAnalyticsView` 1:1.
 */
export default function Analytics() {
  const navigate = useNavigate();
  const { user, profile, loading } = useAuth();
  const [range, setRange] = useState<RangeDays>(30);

  const postsQuery = useQuery({
    queryKey: ["user-posts", user?.id],
    queryFn: () => fetchPostsByUser(user!.id),
    enabled: !!user,
  });
  const countsQuery = useQuery({
    queryKey: ["follow-counts", user?.id],
    queryFn: () => fetchFollowCounts(user!.id),
    enabled: !!user,
  });

  const entries = useMemo<Entry[]>(() => {
    return (postsQuery.data ?? [])
      .map((post) => {
        const date = post.created_at ? new Date(post.created_at) : null;
        if (!date || Number.isNaN(date.getTime())) return null;
        const likes = post.likes_count ?? 0;
        const comments = post.comments_count ?? 0;
        return {
          post,
          date,
          likes,
          comments,
          interactions: likes + comments,
          isWave: post.is_reel === true,
          hasMedia: (post.media_urls ?? []).length > 0,
        } satisfies Entry;
      })
      .filter((e): e is Entry => e !== null)
      .sort((a, b) => b.date.getTime() - a.date.getTime());
  }, [postsQuery.data]);

  const now = Date.now();
  const rangeStart = now - range * 86_400_000;
  const prevStart = rangeStart - range * 86_400_000;
  const inRange = useMemo(
    () => entries.filter((e) => e.date.getTime() >= rangeStart),
    [entries, rangeStart]
  );
  const previous = useMemo(
    () =>
      entries.filter(
        (e) => e.date.getTime() >= prevStart && e.date.getTime() < rangeStart
      ),
    [entries, prevStart, rangeStart]
  );

  const totalInteractions = inRange.reduce((a, e) => a + e.interactions, 0);
  const prevInteractions = previous.reduce((a, e) => a + e.interactions, 0);
  const totalLikes = inRange.reduce((a, e) => a + e.likes, 0);
  const totalComments = inRange.reduce((a, e) => a + e.comments, 0);
  const avgPerPost = inRange.length ? totalInteractions / inRange.length : 0;
  const waves = inRange.filter((e) => e.isWave).length;
  const media = inRange.filter((e) => !e.isWave && e.hasMedia).length;
  const text = inRange.filter((e) => !e.isWave && !e.hasMedia).length;
  const mixTotal = Math.max(1, inRange.length);

  const dayPoints = useMemo(() => {
    const buckets = new Map<string, { label: string; interactions: number; posts: number }>();
    for (let i = range - 1; i >= 0; i -= 1) {
      const d = new Date();
      d.setHours(0, 0, 0, 0);
      d.setDate(d.getDate() - i);
      const key = d.toISOString().slice(0, 10);
      buckets.set(key, {
        label: d.toLocaleDateString(undefined, { month: "short", day: "numeric" }),
        interactions: 0,
        posts: 0,
      });
    }
    for (const e of inRange) {
      const d = new Date(e.date);
      d.setHours(0, 0, 0, 0);
      const key = d.toISOString().slice(0, 10);
      const b = buckets.get(key);
      if (b) {
        b.interactions += e.interactions;
        b.posts += 1;
      }
    }
    return Array.from(buckets.values());
  }, [inRange, range]);

  const topPosts = useMemo(
    () => [...inRange].sort((a, b) => b.interactions - a.interactions).slice(0, 3),
    [inRange]
  );

  const counts = countsQuery.data ?? { followers: 0, following: 0 };
  const coverageConfirmed = (postsQuery.data?.length ?? 120) < 120 && !postsQuery.isError;
  const metricsKnown = !!postsQuery.data && !postsQuery.isError && inRange.every(e => e.post.likes_count != null && e.post.comments_count != null);
  const interactionsDelta = coverageConfirmed && metricsKnown ? delta(totalInteractions, prevInteractions) : null;
  const postsDelta = coverageConfirmed ? delta(inRange.length, previous.length) : null;

  if (loading) return null;
  if (!user) return <Navigate to="/auth" replace />;
  // Verified creators own the bigger tool — send them there.
  if (canOpenCreatorStudio(profile)) return <Navigate to="/dashboard" replace />;

  const allowed = canOpenAnalytics(profile);

  return (
    <div>
      <Header
        title="Analytics"
        left={
          <button
            onClick={() => navigate(-1)}
            aria-label="Back"
            className="glass flex h-10 w-10 items-center justify-center rounded-full border border-border/60 shadow-sm transition-transform active:scale-90"
          >
            <ArrowLeft className="h-5 w-5" />
          </button>
        }
        right={<span className="h-10 w-10" />}
      />

      <div className="mx-auto max-w-2xl space-y-5 px-4 pb-16 pt-3">
        {!allowed ? (
          <div className="rounded-[20px] border border-border bg-card p-6">
            <p className="text-[11px] font-black uppercase tracking-[0.12em] text-muted-foreground">
              Professional accounts
            </p>
            <h1 className="mt-2 text-[24px] font-bold leading-tight">
              Analytics is for creator and business accounts.
            </h1>
            <p className="mt-2 text-[14px] leading-relaxed text-muted-foreground">
              Switch your account type in Settings → Account type & tools — it's free, and
              it unlocks reach, interactions, followers, and top posts right here.
            </p>
            <button
              onClick={() => navigate("/settings")}
              className="mt-4 rounded-full bg-foreground px-5 py-2.5 text-[14px] font-bold text-background transition-transform active:scale-95"
            >
              Open settings
            </button>
          </div>
        ) : (
          <>
            {/* Headline */}
            <div className="space-y-2">
              <span
                className="inline-flex rounded-full px-2.5 py-1 text-[10px] font-black uppercase tracking-[0.12em]"
                style={{ background: `${WHISPER_BRAND_ACCENT}1F`, color: WHISPER_BRAND_ACCENT }}
              >
                {tierLabel(profile)}
              </span>
              <GradientTypeIn
                key={range}
                text={`Here's how your last ${range} days landed.`}
                speed={34}
                className="text-[26px] font-bold leading-tight"
                as="h1"
              />
              <p className="text-[13px] text-muted-foreground">
                Current interactions on posts published in this period. Based on your latest 120 posts, not unique reach or the date each interaction happened.
              </p>
            </div>

            {/* Range */}
            <div className="grid grid-cols-3 rounded-full bg-secondary p-1 text-[13px] font-semibold">
              {([7, 30, 90] as RangeDays[]).map((r) => (
                <button
                  key={r}
                  onClick={() => setRange(r)}
                  className={cn(
                    "rounded-full py-1.5 transition-colors",
                    range === r ? "bg-background shadow-sm" : "text-muted-foreground"
                  )}
                >
                  {r}D
                </button>
              ))}
            </div>

            {/* Overview tiles */}
            <div className="grid grid-cols-2 gap-2.5">
              <Tile icon={<LayoutGrid className="h-4 w-4" />} title="Posts" value={String(inRange.length)} delta={postsDelta} />
              <Tile icon={<Heart className="h-4 w-4" />} title="Interactions" value={metricsKnown ? compact(totalInteractions) : "—"} delta={interactionsDelta} />
              <Tile icon={<Users className="h-4 w-4" />} title="Current followers" value={countsQuery.data && !countsQuery.isError ? compact(counts.followers) : "—"} footnote={`${compact(counts.following)} following`} />
              <Tile icon={<BarChart3 className="h-4 w-4" />} title="Avg per post" value={metricsKnown ? avgPerPost.toFixed(1) : "—"} footnote={`${compact(totalLikes)} likes · ${compact(totalComments)} comments`} />
            </div>

            {/* Chart */}
            <section className="rounded-[18px] border border-border bg-card p-4">
              <p className="text-[11px] font-black uppercase tracking-[0.1em] text-muted-foreground">
                Interactions by publish day
              </p>
              {inRange.length === 0 ? (
                <p className="py-8 text-[13px] text-muted-foreground">
                  Post something in this window and the chart fills in.
                </p>
              ) : (
                <div className="mt-3 h-44">
                  <ResponsiveContainer width="100%" height="100%">
                    <BarChart data={dayPoints} margin={{ top: 4, right: 4, left: -18, bottom: 0 }}>
                      <defs>
                        <linearGradient id="whisperBrandBar" x1="0" y1="0" x2="0" y2="1">
                          <stop offset="0%" stopColor={WHISPER_BRAND_MINT} />
                          <stop offset="50%" stopColor={WHISPER_BRAND_ACCENT} />
                          <stop offset="100%" stopColor={WHISPER_BRAND_INDIGO} />
                        </linearGradient>
                      </defs>
                      <XAxis
                        dataKey="label"
                        tick={{ fontSize: 10 }}
                        interval={Math.max(0, Math.floor(range / 6) - 1)}
                        axisLine={false}
                        tickLine={false}
                      />
                      <YAxis tick={{ fontSize: 10 }} axisLine={false} tickLine={false} allowDecimals={false} />
                      <Tooltip
                        cursor={{ fill: "hsl(var(--secondary))" }}
                        contentStyle={{ borderRadius: 12, fontSize: 12 }}
                        formatter={(value: number) => [value, "Interactions"]}
                      />
                      <Bar dataKey="interactions" fill="url(#whisperBrandBar)" radius={[4, 4, 0, 0]} />
                    </BarChart>
                  </ResponsiveContainer>
                </div>
              )}
            </section>

            {/* Content mix */}
            <section className="rounded-[18px] border border-border bg-card p-4">
              <p className="text-[11px] font-black uppercase tracking-[0.1em] text-muted-foreground">
                Content mix
              </p>
              <div className="mt-3 flex h-2.5 overflow-hidden rounded-full bg-secondary">
                <span style={{ width: `${(text / mixTotal) * 100}%`, background: WHISPER_BRAND_MINT }} />
                <span style={{ width: `${(media / mixTotal) * 100}%`, background: WHISPER_BRAND_ACCENT }} />
                <span style={{ width: `${(waves / mixTotal) * 100}%`, background: WHISPER_BRAND_INDIGO }} />
              </div>
              <div className="mt-2.5 flex flex-wrap gap-4 text-[12px] font-semibold text-muted-foreground">
                <Legend color={WHISPER_BRAND_MINT} label={`Whisps ${text}`} />
                <Legend color={WHISPER_BRAND_ACCENT} label={`Media ${media}`} />
                <Legend color={WHISPER_BRAND_INDIGO} label={`Waves ${waves}`} />
              </div>
            </section>

            {/* Top posts */}
            <section className="rounded-[18px] border border-border bg-card p-4">
              <p className="text-[11px] font-black uppercase tracking-[0.1em] text-muted-foreground">
                Top posts
              </p>
              {topPosts.length === 0 ? (
                <p className="mt-3 text-[13px] text-muted-foreground">
                  Your best-performing posts in this window show up here.
                </p>
              ) : (
                <ul className="mt-3 divide-y divide-border">
                  {topPosts.map((e, i) => {
                    const caption = stripPostMeta(e.post.caption ?? "").trim();
                    const thumb = e.post.media_urls?.[0];
                    const isVideo = thumb ? /\.(mp4|mov|webm|m3u8)(\?|$)/i.test(thumb) : false;
                    return (
                      <li key={e.post.id}><button type="button" onClick={() => navigate(e.isWave ? `/reels?wave=${encodeURIComponent(e.post.id)}` : `/?post=${encodeURIComponent(e.post.id)}`)} className="flex min-h-11 w-full items-center gap-3 rounded-xl py-3 text-left hover:bg-secondary">
                        <span
                          className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-[12px] font-black text-white"
                          style={{ background: WHISPER_BRAND_GRADIENT_DIAGONAL }}
                        >
                          {i + 1}
                        </span>
                        <div className="h-11 w-11 shrink-0 overflow-hidden rounded-lg bg-secondary">
                          {thumb && !isVideo ? (
                            <img src={thumb} alt="" className="h-full w-full object-cover" loading="lazy" />
                          ) : null}
                        </div>
                        <div className="min-w-0 flex-1">
                          <p className="line-clamp-2 text-[14px] font-semibold leading-snug">
                            {caption || (e.isWave ? "Wave" : "Media post")}
                          </p>
                          <p className="text-[12px] text-muted-foreground">
                            {compact(e.likes)} likes · {compact(e.comments)} comments ·{" "}
                            {e.date.toLocaleDateString(undefined, { month: "short", day: "numeric" })}
                          </p>
                        </div>
                      </button></li>
                    );
                  })}
                </ul>
              )}
            </section>

            {/* The separation, stated plainly */}
            <section className="rounded-[18px] border border-border bg-card/60 p-4">
              <div className="flex items-center gap-2">
                <BadgeCheck className="h-4 w-4 text-[#3389FF]" />
                <p className="text-[14px] font-bold">Creator Studio is for verified creators</p>
              </div>
              <p className="mt-2 text-[13px] leading-relaxed text-muted-foreground">
                Verification adds the creator score, WPP creator pay from ad revenue, momentum
                tracking, pinned posts, and the grid composer. Analytics here is the professional
                tier — apply for verification from Settings → Verification when you're ready.
              </p>
              <button
                onClick={() => navigate("/apply?role=creator")}
                className="mt-3 text-[13px] font-semibold"
                style={{ color: WHISPER_BRAND_ACCENT }}
              >
                Learn about verification ›
              </button>
            </section>
          </>
        )}
      </div>
    </div>
  );
}

function Tile({
  icon,
  title,
  value,
  delta: d,
  footnote,
}: {
  icon: React.ReactNode;
  title: string;
  value: string;
  delta?: number | null;
  footnote?: string;
}) {
  return (
    <div className="rounded-[16px] border border-border bg-card p-3.5">
      <div className="flex items-center justify-between text-muted-foreground">
        {icon}
        {typeof d === "number" && (
          <span
            className="text-[11px] font-bold"
            style={{ color: d >= 0 ? WHISPER_BRAND_ACCENT : "#E05A5A" }}
          >
            {d >= 0 ? "↗" : "↘"} {Math.abs(d)}%
          </span>
        )}
      </div>
      <p className="mt-2 text-[26px] font-bold leading-none tabular-nums">{value}</p>
      <p className="mt-1.5 truncate text-[12px] text-muted-foreground">{footnote ?? title}</p>
    </div>
  );
}

function Legend({ color, label }: { color: string; label: string }) {
  return (
    <span className="inline-flex items-center gap-1.5">
      <span className="h-2 w-2 rounded-full" style={{ background: color }} />
      {label}
    </span>
  );
}
