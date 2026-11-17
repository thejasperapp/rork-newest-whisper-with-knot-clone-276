import { useEffect, useMemo } from "react";
import { useInfiniteQuery, useQueryClient } from "@tanstack/react-query";
import { fetchConversationSummaries, uniqueConversations } from "@/lib/conversationSummaries";
import type { MessageCursor } from "@/lib/messageHistory";

export function useConversationSummaries(owner: string | undefined) {
  const client = useQueryClient();
  const queryKey = useMemo(() => ["conversations", owner, "summaries"] as const, [owner]);
  const query = useInfiniteQuery({
    queryKey,
    initialPageParam: null as MessageCursor | null,
    queryFn: ({ pageParam, signal }) => fetchConversationSummaries(owner!, pageParam, signal),
    getNextPageParam: page => page.next ?? undefined,
    enabled: !!owner,
    staleTime: 15_000,
    gcTime: 5 * 60_000,
    refetchInterval: 30_000,
    refetchIntervalInBackground: false,
    refetchOnReconnect: "always",
    retry: 1,
  });
  useEffect(() => () => { void client.cancelQueries({ queryKey, exact: true }); }, [client, queryKey]);
  return { ...query, conversations: useMemo(() => uniqueConversations(query.data?.pages ?? []), [query.data]) };
}
