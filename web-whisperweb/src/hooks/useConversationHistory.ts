import { useEffect, useMemo, useState } from "react";
import { useMessageSnapshot } from "./useMessageSnapshot";
import { useInfiniteQuery, useQueryClient, type InfiniteData } from "@tanstack/react-query";
import { fetchConversationHistory } from "@/lib/conversationHistory";
import { uniqueHistory, type MessageCursor, type MessagePage } from "@/lib/messageHistory";
import type { ConversationKind } from "@/lib/conversationIdentity";

/** History is separate from the bounded inbox window. Older pages exist only
 * while the thread is open; revisiting retains at most the recent 100 rows. */
export function useConversationHistory(owner: string, peer: string, kind: ConversationKind) {
  const client = useQueryClient();
  const [visible, setVisible] = useState(() => document.visibilityState === "visible");
  useEffect(() => {
    const update = () => setVisible(document.visibilityState === "visible");
    document.addEventListener("visibilitychange", update);
    return () => document.removeEventListener("visibilitychange", update);
  }, []);
  const snapshot = useMessageSnapshot(owner, `${kind}:${peer.toLowerCase()}`, visible);
  const queryKey = useMemo(() => ["conversations", owner, "history", kind, peer] as const, [owner, peer, kind]);
  const query = useInfiniteQuery({
    queryKey,
    initialPageParam: null as MessageCursor | null,
    queryFn: ({ pageParam, signal }) => fetchConversationHistory(owner, peer, kind, pageParam, signal),
    getNextPageParam: (page) => page.next ?? undefined,
    enabled: !!owner && !!peer && visible,
    staleTime: 15_000,
    gcTime: 5 * 60_000,
    refetchOnReconnect: "always",
    retry: 1,
  });
  useEffect(() => { if (!visible) void client.cancelQueries({ queryKey, exact: true }); }, [client, queryKey, visible]);
  useEffect(() => () => {
    // Cancellation prevents a late next-page response restoring trimmed pages.
    void client.cancelQueries({ queryKey, exact: true });
    client.setQueryData<InfiniteData<MessagePage, MessageCursor | null>>(queryKey, previous => previous ? {
      pages: previous.pages.slice(0, 1), pageParams: previous.pageParams.slice(0, 1),
    } : previous);
  }, [client, queryKey]);
  const messages = useMemo(() => query.data ? uniqueHistory(query.data.pages) : snapshot, [query.data, snapshot]);
  return { ...query, messages };
}
