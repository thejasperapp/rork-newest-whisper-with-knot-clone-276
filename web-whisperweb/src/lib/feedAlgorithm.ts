import { algorithmKeywords } from "@/lib/dearAlgorithm";
import { currentFeedRevision, feedWindow, FEED_PAGE_LIMIT, type FeedPage, type FeedScope } from "./feedPaging";
import { beforeMessage, type MessageCursor } from "./messageHistory";
import { supabase } from "@/lib/supabase";
import {
  fetchFeed,
  fetchLikeCounts,
  fetchCommentCounts,
  fetchRepostCounts,
} from "@/lib/api";
import type { WhisperPost } from "@/lib/types";

/**
 * The Whisper home-feed algorithm — MUST stay in sync with iOS
 * `WhisperBackendService.rankFeed` (identical constants on both apps):
 *
 *   score = recencyDecay × engagement × followBoost × freshKicker
 *   • recencyDecay = e^(-ageHours / 20), floored at 0.02 so a strong older
 *     post can still surface
 *   • engagement  = 1 + 0.6·ln(1 + likes + 2.5·comments + 2·reposts)
 *     (web overlays REAL counts from the engagement tables; iOS ranks
 *     without the repost term until repost counts ship there)
 *   • followBoost = 1.45 when the viewer follows the author
 *   • freshKicker = 1.2 for posts under 90 minutes old
 *
 * then a diversity pass keeps any single author from occupying more than
 * 2 consecutive feed slots.
 */

export interface FeedSignals {
  likeCounts: Record<string, number>;
  commentCounts: Record<string, number>;
  repostCounts: Record<string, number>;
  followingIds: Set<string>;
  wishKeywords?: string[];
}

/** Pure ranking — recency-decayed engagement, follow affinity, diversity. */
export function rankFeed(
  posts: WhisperPost[],
  signals: FeedSignals
): WhisperPost[] {
  if (posts.length <= 2) return posts;
  const now = Date.now();

  const score = (post: WhisperPost): number => {
    const parsed = post.created_at ? Date.parse(post.created_at) : NaN;
    const created = Number.isFinite(parsed) ? parsed : now;
    const ageHours = Math.max(0, (now - created) / 3_600_000);
    const recency = Math.max(0.02, Math.exp(-ageHours / 20));
    const likes = signals.likeCounts[post.id] ?? post.likes_count ?? 0;
    const comments =
      signals.commentCounts[post.id] ?? post.comments_count ?? 0;
    const reposts = signals.repostCounts[post.id] ?? 0;
    const engagement =
      1 + 0.6 * Math.log(1 + Math.max(0, likes + 2.5 * comments + 2 * reposts));
    const follow = signals.followingIds.has(post.user_id) ? 1.45 : 1.0;
    const fresh = ageHours < 1.5 ? 1.2 : 1.0;
    const caption = post.caption.toLowerCase();
    const wishBoost = (signals.wishKeywords ?? []).reduce((boost, keyword) => caption.includes(keyword) ? boost * 1.18 : boost, 1);
    return recency * engagement * follow * fresh * wishBoost;
  };

  const pool = posts
    .map((post) => ({ post, value: score(post) }))
    .sort((a, b) => b.value - a.value);

  const out: WhisperPost[] = [];
  let lastAuthor = "";
  let runLength = 0;
  while (pool.length > 0) {
    let pick = 0;
    if (runLength >= 2) {
      const alt = pool.findIndex((c) => c.post.user_id !== lastAuthor);
      if (alt >= 0) pick = alt;
    }
    const [chosen] = pool.splice(pick, 1);
    const author = chosen.post.user_id;
    if (author === lastAuthor) {
      runLength += 1;
    } else {
      runLength = 1;
      lastAuthor = author;
    }
    out.push(chosen.post);
  }
  return out;
}

/** Author ids the viewer follows — the ranker boosts these authors. */
async function fetchMyFollowingIds(viewerId: string, signal?: AbortSignal): Promise<Set<string>> {
  try {
    const request = supabase
      .from("whisper_follows")
      .select("followee_id")
      .eq("follower_id", viewerId)
      .limit(1000);
    const { data } = await (signal ? request.abortSignal(signal) : request);
    const rows = (data as { followee_id: string }[] | null) ?? [];
    return new Set(rows.map((r) => r.followee_id).filter(Boolean));
  } catch {
    return new Set<string>();
  }
}

/**
 * Ranked home feed: pulls a wide recency window, overlays REAL engagement
 * counts from the source-of-truth tables, boosts followed authors, then
 * applies the shared scoring. Every signal fetch fails soft, so the feed
 * still renders (as plain recency) if a table is unreachable.
 */
export async function fetchRankedFeed(
  viewerId?: string | null,
  limit = 60,
  onSignals?: (posts: WhisperPost[], signals: FeedSignals) => void
): Promise<WhisperPost[]> {
  const [candidates, followingIds] = await Promise.all([
    fetchFeed(120),
    viewerId ? fetchMyFollowingIds(viewerId) : Promise.resolve(new Set<string>()),
  ]);
  if (!candidates.length) return [];
  const ids = candidates.map((p) => p.id);
  const [likeCounts, commentCounts, repostCounts] =
    await Promise.all([
      fetchLikeCounts(ids).catch(() => ({}) as Record<string, number>),
      fetchCommentCounts(ids).catch(() => ({}) as Record<string, number>),
      fetchRepostCounts(ids).catch(() => ({}) as Record<string, number>),
    ]);
  const signals: FeedSignals = {
    likeCounts,
    commentCounts,
    repostCounts,
    followingIds,
    wishKeywords: algorithmKeywords(viewerId),
  };
  const ranked = rankFeed(candidates, signals).slice(0, limit);
  onSignals?.(ranked, signals);
  return ranked;
}

/** Small chronological candidate pages, ranked independently. No client-side
 * filter determines continuation or stops traversal through a quiet category. */
export async function fetchRankedFeedPage(owner: string, cursor: MessageCursor | null, signal?: AbortSignal,
  onSignals?: (posts: WhisperPost[], signals: FeedSignals) => void, scope?: FeedScope): Promise<FeedPage> {
  const revision = currentFeedRevision();
  const assertCurrent = async () => {
    const { data } = await supabase.auth.getSession();
    if (signal?.aborted || data.session?.user.id.toLowerCase() !== owner.toLowerCase() || revision !== currentFeedRevision()) {
      throw new Error("Your feed changed. Please refresh and try again.");
    }
  };
  await assertCurrent();
  const includeWaves = scope?.kind === "discover" || scope?.kind === "search";
  const clauses = includeWaves ? [] : ["or(is_reel.is.null,is_reel.eq.false,caption.ilike.*feed*:true*)"];
  if (cursor) clauses.push(`or(${beforeMessage(cursor)})`);
  let filtered = supabase.from("whisper_posts").select("*");
  if (clauses.length) filtered = filtered.or(`and(${clauses.join(",")})`);
  if (scope?.kind === "community") {
    if (!scope.id || scope.id.length > 200) throw new Error("Choose a community to continue.");
    filtered = filtered.eq("community_id", scope.id);
  }
  if (scope?.kind === "search") {
    // A normal query parameter, never interpolation into a PostgREST OR.
    // Escape wildcard syntax so punctuation cannot broaden the search.
    const term = scope.term.trim().slice(0, 100);
    if (!term) throw new Error("Enter a tag to search.");
    filtered = filtered.ilike("caption", `%${term.replace(/[\\%_*]/g, "\\$&")}%`);
  }
  const request = filtered
    .order("created_at", { ascending: false, nullsFirst: false }).order("id", { ascending: false }).limit(FEED_PAGE_LIMIT + 1);
  const [{ data, error }, followingIds] = await Promise.all([
    signal ? request.abortSignal(signal) : request, fetchMyFollowingIds(owner, signal),
  ]);
  await assertCurrent();
  if (error) throw new Error("Posts couldn't refresh. Please try again.");
  const window = feedWindow((data ?? []) as WhisperPost[], includeWaves);
  const ids = window.posts.map(post => post.id).sort();
  const [likeCounts, commentCounts, repostCounts] = ids.length ? await Promise.all([
    fetchLikeCounts(ids).catch(() => ({})), fetchCommentCounts(ids).catch(() => ({})), fetchRepostCounts(ids).catch(() => ({})),
  ]) : [{}, {}, {}];
  await assertCurrent();
  const signals: FeedSignals = { likeCounts, commentCounts, repostCounts, followingIds, wishKeywords: algorithmKeywords(owner) };
  const posts = rankFeed(window.posts, signals);
  onSignals?.(posts, signals);
  return { posts, next: window.next, signals };
}
