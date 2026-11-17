/**
 * Creator analytics inside meetings — the web twin of the iOS
 * `WhisperCreatorMeetingKit`. Builds the exact Creator Studio numbers
 * (score, momentum, engagement, ranked posts) into the camelCase wire
 * payload both platforms broadcast over the meeting's app-event channel,
 * and produces the grounded context block so in-meeting Jasper answers
 * cite the asker's REAL numbers.
 *
 * Wire events (shared with iOS):
 *   "creator-analytics"      → full CreatorAnalyticsCardPayload (rev-stamped)
 *   "creator-analytics-end"  → { presenterUserId }
 */
import { fetchCreatorStats } from "@/lib/api";
import { rankEntries, scorePost } from "@/lib/algorithm";
import { timeAgo } from "@/lib/format";
import type { VerificationBadge } from "@/lib/verification";
import type { WhisperPostStat } from "@/lib/types";

/** One top-performing post on the wire — enough to render the real row
 *  and open a detail view on any platform. Mirrors iOS `TopPost`. */
export interface CreatorAnalyticsTopPost {
  id: string;
  caption?: string | null;
  kind?: string | null;
  isReel?: boolean | null;
  symbol?: string | null;
  accentHex?: string | null;
  likes?: number | null;
  comments?: number | null;
  createdAt?: string | null;
  mediaUrls?: string[] | null;
  score?: number | null;
}

/** The live analytics card a creator presents into a meeting. Field names
 *  match iOS `WhisperCreatorAnalyticsCard` byte-for-byte. */
export interface CreatorAnalyticsCardPayload {
  id: string;
  username?: string | null;
  imageUrl?: string | null;
  score?: number | null;
  followers?: number | null;
  followerDelta?: number | null;
  engagementPct?: number | null;
  posts30?: number | null;
  likes30?: number | null;
  comments30?: number | null;
  reels?: number | null;
  photos?: number | null;
  verdict?: string | null;
  topPosts?: CreatorAnalyticsTopPost[] | null;
  /** Bumped on every re-broadcast carrying fresher data so viewers accept
   *  the update instead of ignoring it as a heartbeat. */
  rev?: number | null;
  presenterUserId: string;
  presenterName: string;
}

const DAY_MS = 86_400_000;

interface CreatorNumbers {
  score: number;
  followers: number;
  delta: number;
  engagementPct: number;
  posts30: number;
  likes30: number;
  comments30: number;
  reels: number;
  photos: number;
  verdict: string;
  ranked: WhisperPostStat[];
}

function postTime(iso: string | null): number {
  if (!iso) return NaN;
  const ts = new Date(iso).getTime();
  return Number.isNaN(ts) ? NaN : ts;
}

/** Fetches posts + followers and computes the dashboard numbers — the
 *  byte-for-byte Creator Studio math (iOS parity). Null = no posts yet. */
async function computeNumbers(
  userId: string,
  username: string,
  badge: VerificationBadge
): Promise<CreatorNumbers | null> {
  const stats = await fetchCreatorStats(userId);
  if (stats.entries.length === 0) return null;

  const cutoff = Date.now() - 30 * DAY_MS;
  const last30 = stats.entries.filter((e) => {
    const ts = postTime(e.post.created_at);
    return Number.isFinite(ts) && ts >= cutoff;
  });
  const likes30 = last30.reduce((acc, e) => acc + e.likes, 0);
  const comments30 = last30.reduce((acc, e) => acc + e.comments, 0);
  const engagementPct =
    stats.followers > 0 && last30.length > 0
      ? Math.min(100, ((likes30 + comments30) / (stats.followers * last30.length)) * 100)
      : 0;

  // Read-only view of the weekly snapshot Creator Studio stamps.
  let delta = 0;
  try {
    const last = Number(
      localStorage.getItem(`whisper_creator_studio_followers_${username.toLowerCase()}`) ?? "0"
    );
    delta = last > 0 ? stats.followers - last : 0;
  } catch {
    /* storage unavailable */
  }

  const engagement = Math.min(40, engagementPct * 8);
  const cadence = Math.min(30, last30.length * 3);
  const audience = Math.min(20, stats.followers / 50);
  const momentum = delta > 0 ? 10 : delta < 0 ? 0 : 5;
  const score = Math.round(Math.min(100, engagement + cadence + audience + momentum));

  const verdict =
    score >= 75
      ? "On fire — the algorithm loves this pace."
      : score >= 50
        ? "Solid momentum. One more post this week pushes higher."
        : score >= 25
          ? "Warming up — consistency is your fastest lever."
          : "Post something today to wake the algorithm up.";

  const reels = stats.entries.filter((e) => e.post.is_reel === true).length;

  return {
    score,
    followers: stats.followers,
    delta,
    engagementPct,
    posts30: last30.length,
    likes30,
    comments30,
    reels,
    photos: stats.entries.length - reels,
    verdict,
    ranked: rankEntries(stats.entries, badge),
  };
}

/** Builds the broadcast payload from live data. Null when the creator has
 *  no posts yet (callers show an honest empty state instead). */
export async function buildCreatorAnalyticsCard(opts: {
  userId: string;
  username: string;
  imageUrl?: string | null;
  badge: VerificationBadge;
  presenterName: string;
}): Promise<CreatorAnalyticsCardPayload | null> {
  const n = await computeNumbers(opts.userId, opts.username, opts.badge);
  if (!n) return null;
  const topPosts: CreatorAnalyticsTopPost[] = n.ranked.slice(0, 3).map((e) => ({
    id: e.post.id,
    caption: e.post.caption || null,
    kind: e.post.kind,
    isReel: e.post.is_reel ?? false,
    symbol: e.post.symbol,
    accentHex: e.post.accent_hex,
    likes: e.likes,
    comments: e.comments,
    createdAt: e.post.created_at,
    mediaUrls: e.post.media_urls ?? [],
    score: scorePost(e, opts.badge),
  }));
  return {
    id: crypto.randomUUID().toLowerCase(),
    username: opts.username,
    imageUrl: opts.imageUrl ?? null,
    score: n.score,
    followers: n.followers,
    followerDelta: n.delta,
    engagementPct: n.engagementPct,
    posts30: n.posts30,
    likes30: n.likes30,
    comments30: n.comments30,
    reels: n.reels,
    photos: n.photos,
    verdict: n.verdict,
    topPosts,
    rev: Date.now(),
    presenterUserId: opts.userId,
    presenterName: opts.presenterName,
  };
}

let ctxCache: { key: string; text: string; at: number } | null = null;

/** The asker's live analytics as a grounded text block for in-meeting
 *  Jasper — identical wording to iOS so answers match across platforms.
 *  Cached 3 minutes; plain DB read, zero AI spend; null on failure/empty. */
export async function creatorJasperContext(
  userId: string,
  username: string,
  badge: VerificationBadge
): Promise<string | null> {
  if (ctxCache && ctxCache.key === userId && Date.now() - ctxCache.at < 180_000) {
    return ctxCache.text;
  }
  try {
    const n = await computeNumbers(userId, username, badge);
    if (!n) return null;
    const lines: string[] = [
      "=== LIVE CREATOR ANALYTICS (the asker's own, fresh this moment — ground any content, growth, or analytics answer in these real numbers; name their actual posts) ===",
      `Creator score ${n.score}/100 · followers ${n.followers} (${n.delta >= 0 ? "+" : ""}${n.delta} this week) · engagement ${n.engagementPct.toFixed(1)}% · posts 30d ${n.posts30} · likes 30d ${n.likes30} · comments 30d ${n.comments30}`,
      `Formats: ${n.reels} reels · ${n.photos} posts`,
    ];
    for (const e of n.ranked.slice(0, 5)) {
      lines.push(
        `- ${e.post.is_reel ? "reel" : "post"} · ${e.likes} likes · ${e.comments} comments · ${timeAgo(e.post.created_at)} · ${(e.post.caption || "(media post)").slice(0, 60)}`
      );
    }
    const text = lines.join("\n");
    ctxCache = { key: userId, text, at: Date.now() };
    return text;
  } catch {
    return null;
  }
}
