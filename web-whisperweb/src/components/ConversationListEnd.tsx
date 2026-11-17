import { useEffect, useRef, useState } from "react";
import { Loader2 } from "lucide-react";

/** The marker stays after the merged group/direct list, including when local
 * filters hide a whole server page. Hidden inboxes never traverse more pages. */
export function ConversationListEnd({ active, hasMore, busy, loading, failed, onLoad, content = "conversations" }: {
  active: boolean; hasMore: boolean; busy: boolean; loading: boolean;
  failed: boolean; onLoad: () => Promise<unknown>; content?: "conversations" | "posts";
}) {
  const marker = useRef<HTMLDivElement>(null);
  const pending = useRef(false);
  const [visible, setVisible] = useState(() => !document.hidden);
  useEffect(() => {
    const update = () => setVisible(!document.hidden);
    document.addEventListener("visibilitychange", update);
    return () => document.removeEventListener("visibilitychange", update);
  }, []);
  useEffect(() => {
    if (!active || !visible || !hasMore || busy || failed || !marker.current || typeof IntersectionObserver === "undefined") return;
    const observer = new IntersectionObserver(entries => {
      if (!entries.some(entry => entry.isIntersecting) || pending.current || document.hidden) return;
      pending.current = true;
      void onLoad().finally(() => { pending.current = false; });
    }, { rootMargin: "0px 0px 240px 0px" });
    observer.observe(marker.current);
    return () => observer.disconnect();
  }, [active, visible, hasMore, busy, failed, onLoad]);
  return <div ref={marker} className="min-h-px">
    {loading && <div role="status" aria-label={`Loading ${content}`} className="flex h-11 items-center justify-center text-muted-foreground"><Loader2 aria-hidden="true" className="h-4 w-4 animate-spin motion-reduce:animate-none" /></div>}
    {failed && <div role="status" className="px-4 py-3 text-center text-sm text-muted-foreground">
      <p>{content === "posts" ? "Posts couldn’t load just now." : "More conversations couldn’t load just now."}</p>
      <button type="button" disabled={busy} className="mt-1 min-h-11 rounded-full bg-secondary px-5 font-semibold text-foreground disabled:opacity-50" onClick={() => void onLoad()}>Try again</button>
    </div>}
  </div>;
}
