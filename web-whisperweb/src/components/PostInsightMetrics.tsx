import { useQuery } from "@tanstack/react-query";
import { supabaseUrl, supabaseAnonKey } from "@/lib/supabase";
import { groupThemeSession } from "@/lib/groupThemeSession";
import { useDocumentVisible } from "@/hooks/useDocumentVisible";

const metrics = [{ table: "whisper_post_views", label: "Views" }, { table: "whisper_post_likes", label: "Likes" }, { table: "whisper_post_comments", label: "Comments" }] as const;

/** Independent exact counts distinguish an unavailable metric from a confirmed zero. */
export function PostInsightMetrics({ postID, accountID }: { postID: string; accountID: string }) {
  const visible = useDocumentVisible();
  const query = useQuery({ queryKey: ["post-insights", accountID, postID], enabled: visible, staleTime: 0, gcTime: 0,
    queryFn: async ({ signal }) => {
      const session = await groupThemeSession(accountID);
      const timeout = AbortSignal.timeout(12000);
      const requestSignal = AbortSignal.any([signal, session.signal, timeout]);
      const headers = { apikey: supabaseAnonKey, Authorization: `Bearer ${session.token}`, Prefer: "count=exact" };
      try {
        const admission = await fetch(`${supabaseUrl}/rest/v1/whisper_posts?select=id&user_id=eq.${encodeURIComponent(accountID)}&id=eq.${encodeURIComponent(postID)}`, { headers, signal: requestSignal, redirect: "error" });
        if (!admission.ok) throw new Error("Post unavailable");
        const rows: unknown = await admission.json(); session.check();
        if (!Array.isArray(rows) || rows.length !== 1 || rows[0]?.id !== postID) throw new Error("Post unavailable");
        return await Promise.all(metrics.map(async metric => {
          try {
            const response = await fetch(`${supabaseUrl}/rest/v1/${metric.table}?select=post_id&post_id=eq.${encodeURIComponent(postID)}`, { method: "HEAD", headers, signal: requestSignal, redirect: "error" });
            session.check();
            if (!response.ok) return null;
            const total = response.headers.get("content-range")?.split("/")[1];
            return total && /^\d+$/.test(total) && Number.isSafeInteger(Number(total)) ? Number(total) : null;
          } catch { return null; }
        }));
      } finally { session.dispose(); }
    }, retry: false,
  });
  const values = visible && !query.isFetching && !query.isError ? query.data : undefined;
  return <div className="space-y-4">
    <div className="grid grid-cols-3 divide-x divide-border rounded-2xl border border-border py-6">{metrics.map((metric, index) => <div key={metric.table} className="text-center"><p className="text-2xl font-semibold tabular-nums">{values?.[index]?.toLocaleString() ?? "—"}</p><p className="mt-1 text-xs text-muted-foreground">{metric.label}</p></div>)}</div>
    <p className="text-xs leading-relaxed text-muted-foreground">{query.isFetching ? "Refreshing counts…" : "Recorded views are not unique reach. A dash means the metric could not be confirmed."}</p>
    <button type="button" disabled={query.isFetching || !visible} onClick={() => void query.refetch()} className="min-h-11 text-sm font-medium disabled:opacity-50">Refresh insights</button>
  </div>;
}
