import { useEffect, useMemo, useState } from "react";
import { useInfiniteQuery, useQueryClient, type InfiniteData } from "@tanstack/react-query";
import { fetchGroupHistory } from "@/lib/groupHistory";
import { useMessageSnapshot } from "./useMessageSnapshot";
import { uniqueHistory, type MessageCursor, type MessagePage } from "@/lib/messageHistory";

export function useGroupHistory(owner: string, group: string, active = true) {
  const client = useQueryClient();
  const [foreground, setForeground] = useState(() => document.visibilityState === "visible");
  useEffect(() => {
    const update = () => setForeground(document.visibilityState === "visible");
    document.addEventListener("visibilitychange", update);
    return () => document.removeEventListener("visibilitychange", update);
  }, []);
  const visible = active && foreground;
  const snapshot = useMessageSnapshot(owner, `group:${group.toLowerCase()}`, visible);
  // Existing group mutations already invalidate this owner prefix.
  const queryKey = useMemo(() => ["group-wire", owner, "history", group.toLowerCase()] as const, [owner, group]);
  const query = useInfiniteQuery({
    queryKey,
    initialPageParam: null as MessageCursor | null,
    queryFn: ({ pageParam, signal }) => fetchGroupHistory(owner, group, pageParam, signal),
    getNextPageParam: page => page.next ?? undefined,
    enabled: !!owner && !!group && visible,
    staleTime: 15_000,
    gcTime: 5 * 60_000,
    refetchInterval: visible ? 8_000 : false,
    refetchIntervalInBackground: false,
    refetchOnReconnect: "always",
    retry: 1,
  });
  useEffect(() => {
    if (!visible) void client.cancelQueries({ queryKey, exact: true });
  }, [client, queryKey, visible]);
  useEffect(() => () => {
    void client.cancelQueries({ queryKey, exact: true });
    client.setQueryData<InfiniteData<MessagePage, MessageCursor | null>>(queryKey, previous => previous ? {
      pages: previous.pages.slice(0, 1), pageParams: previous.pageParams.slice(0, 1),
    } : previous);
  }, [client, queryKey]);
  const messages = useMemo(() => query.data ? uniqueHistory(query.data.pages) : snapshot, [query.data, snapshot]);
  return { ...query, visible, messages };
}
