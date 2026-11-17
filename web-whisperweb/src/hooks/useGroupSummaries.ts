import { useEffect, useMemo, useState } from "react";
import { useInfiniteQuery, useQueryClient } from "@tanstack/react-query";
import { fetchGroupSummaries, uniqueGroupSummaries } from "@/lib/groupSummaries";
import type { MessageCursor } from "@/lib/messageHistory";

export function useGroupSummaries(owner: string, active = true) {
  const client = useQueryClient();
  const [foreground, setForeground] = useState(() => document.visibilityState === "visible");
  useEffect(() => {
    const update = () => setForeground(document.visibilityState === "visible");
    document.addEventListener("visibilitychange", update);
    return () => document.removeEventListener("visibilitychange", update);
  }, []);
  const visible = active && foreground;
  const queryKey = useMemo(() => ["group-wire", owner, "summaries"] as const, [owner]);
  const query = useInfiniteQuery({
    queryKey, initialPageParam: null as MessageCursor | null,
    queryFn: ({ pageParam, signal }) => fetchGroupSummaries(owner, pageParam, signal),
    getNextPageParam: page => page.next ?? undefined,
    enabled: !!owner && visible, staleTime: 15_000, gcTime: 5 * 60_000,
    refetchInterval: visible ? 30_000 : false, refetchIntervalInBackground: false,
    refetchOnReconnect: "always", retry: 1,
  });
  useEffect(() => { if (!visible) void client.cancelQueries({ queryKey, exact: true }); }, [client, queryKey, visible]);
  useEffect(() => () => { void client.cancelQueries({ queryKey, exact: true }); }, [client, queryKey]);
  return { ...query, visible, groups: useMemo(() => uniqueGroupSummaries(query.data?.pages ?? []), [query.data]) };
}
