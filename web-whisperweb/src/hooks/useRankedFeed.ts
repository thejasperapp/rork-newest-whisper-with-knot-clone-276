import { useEffect, useMemo, useState } from "react";
import { useInfiniteQuery, useQueryClient, type InfiniteData } from "@tanstack/react-query";
import { fetchRankedFeedPage } from "@/lib/feedAlgorithm";
import { uniqueFeedPosts, type FeedPage, type FeedScope } from "@/lib/feedPaging";
import type { MessageCursor } from "@/lib/messageHistory";

/** Scoped pages share ranking/count snapshots, never a global candidate cap. */
export function useRankedFeed(owner: string | undefined, scope?: FeedScope, active = true) {
  const client = useQueryClient();
  const [visible, setVisible] = useState(() => document.visibilityState === "visible");
  useEffect(() => {
    const update = () => setVisible(document.visibilityState === "visible");
    document.addEventListener("visibilitychange", update);
    return () => document.removeEventListener("visibilitychange", update);
  }, []);
  const scopeKey = scope?.kind === "community" ? `community:${scope.id}` : scope?.kind === "search" ? `search:${scope.term}` : scope?.kind ?? "home";
  const queryKey = useMemo(() => scopeKey === "home" ? ["feed", owner ?? "anon", "pages"] as const : ["feed", owner ?? "anon", "pages", scopeKey] as const, [owner, scopeKey]);
  const query = useInfiniteQuery({
    queryKey, initialPageParam: null as MessageCursor | null,
    queryFn: ({ pageParam, signal }) => fetchRankedFeedPage(owner!, pageParam, signal, (posts, signals) => {
      if (signal.aborted) return;
      const cached = client.getQueryData<InfiniteData<FeedPage, MessageCursor | null>>(queryKey);
      const previous = cached?.pages ?? [];
      const ids = [...new Set([...previous.flatMap(page => page.posts.map(post => post.id)), ...posts.map(post => post.id)])].sort();
      if (!ids.length) return;
      const seed = (prefix: string, field: "likeCounts" | "commentCounts" | "repostCounts") => {
        const key = [prefix, ids];
        if (!client.getQueryState(key)) client.setQueryData(key, Object.assign({}, ...previous.map(page => page.signals[field]), signals[field]));
      };
      seed("feed-like-counts", "likeCounts"); seed("feed-comment-counts", "commentCounts"); seed("repost-counts", "repostCounts");
    }, scope),
    getNextPageParam: page => page.next ?? undefined,
    enabled: !!owner && visible && active, staleTime: 30_000, gcTime: 5 * 60_000,
    refetchOnReconnect: "always", retry: 1,
  });
  useEffect(() => { if (!visible || !active) void client.cancelQueries({ queryKey, exact: true }); }, [client, queryKey, visible, active]);
  useEffect(() => () => {
    // Home/Community may overlap briefly during navigation; do not cancel the
    // shared request if its next visible owner is already observing it.
    const pending = client.getQueryCache().find({ queryKey, exact: true });
    if (!pending?.getObserversCount()) void client.cancelQueries({ queryKey, exact: true });
  }, [client, queryKey]);
  return { ...query, visible, data: useMemo(() => uniqueFeedPosts(query.data?.pages ?? []), [query.data]) };
}
