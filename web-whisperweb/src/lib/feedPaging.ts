import type { FeedSignals } from "./feedAlgorithm";
import type { InfiniteData, QueryClient } from "@tanstack/react-query";
import type { MessageCursor } from "./messageHistory";
import type { WhisperPost } from "./types";
import { waveSharedToFeed } from "./postMeta";

export type FeedScope = { kind: "community"; id: string } | { kind: "search"; term: string } | { kind: "discover" };
export interface FeedPage { posts: WhisperPost[]; next: MessageCursor | null; signals: FeedSignals }
export const FEED_PAGE_LIMIT = 24;
let revision = 0;
export function currentFeedRevision() { return revision; }
export function invalidateFeedSnapshot() { revision++; }
export function removePagedFeedPost(client: QueryClient, id: string) {
  client.setQueriesData<InfiniteData<FeedPage, MessageCursor | null>>({
    predicate: query => query.queryKey[0] === "feed" && query.queryKey[2] === "pages",
  }, old => old ? { ...old, pages: old.pages.map(page => ({ ...page, posts: page.posts.filter(post => post.id !== id) })) } : old);
}
/** Derive continuation before media/following/community/moderation filtering. */
export function feedWindow(rows: WhisperPost[], includeWaves = false) {
  const selected = rows.slice(0, FEED_PAGE_LIMIT);
  const last = selected[selected.length - 1];
  return { posts: selected.filter(row => includeWaves || !row.is_reel || waveSharedToFeed(row.caption)),
    next: rows.length > FEED_PAGE_LIMIT && last ? { id: last.id, createdAt: last.created_at } : null };
}
/** Appending an older page never moves or replaces an already displayed row. */
export function uniqueFeedPosts(pages: FeedPage[]): WhisperPost[] {
  const posts = new Map<string, WhisperPost>();
  for (const page of pages) for (const post of page.posts) if (!posts.has(post.id)) posts.set(post.id, post);
  return [...posts.values()];
}
