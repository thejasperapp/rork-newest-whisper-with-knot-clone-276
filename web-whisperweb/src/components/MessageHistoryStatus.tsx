import { Loader2 } from "lucide-react";

/** Intentionally accepts a failure category, never a transport error or cursor.
 * Pagination is automatic; members only see progress or an actionable retry. */
export function MessageHistoryStatus({ loading, failure, onRetry }: {
  loading: boolean;
  failure: "earlier" | "refresh" | null;
  onRetry: () => void;
}) {
  return <>
    {loading && (
      <div role="status" aria-label="Loading messages" className="mb-3 flex h-7 items-center justify-center text-muted-foreground">
        <Loader2 aria-hidden="true" className="h-4 w-4 animate-spin motion-reduce:animate-none" />
      </div>
    )}
    {failure && (
      <div role="status" className="mb-4 text-center text-sm text-muted-foreground">
        <p>{failure === "earlier" ? "Earlier messages are unavailable for a moment." : "Messages couldn’t refresh just now."}</p>
        <button type="button" disabled={loading} className="mt-2 min-h-11 rounded-full bg-secondary px-5 font-semibold text-foreground transition-colors hover:bg-secondary/70 disabled:opacity-50" onClick={onRetry}>Try again</button>
      </div>
    )}
  </>;
}
