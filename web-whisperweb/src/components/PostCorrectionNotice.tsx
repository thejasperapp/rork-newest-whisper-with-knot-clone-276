import { useQuery } from "@tanstack/react-query";
import { useAuth } from "@/hooks/useAuth";
import { safetyRequest, type Correction } from "@/lib/safetyReview";

export function CorrectionContent({ correction }: { correction: Correction }) {
  return <div className="space-y-2 text-sm">
    <p className="font-semibold">{correction.state === "withdrawn" ? "Correction withdrawn" : "Correction"}</p>
    <p>{correction.explanation}</p>
    <details><summary className="min-h-11 cursor-pointer text-muted-foreground">Reviewed post version & sources</summary>
      <blockquote className="my-2 border-l-2 border-border pl-3 whitespace-pre-wrap">{correction.reviewed_snapshot.caption || "Media post — no caption"}</blockquote>
      <p className="text-xs text-muted-foreground">This notice stays with this post after edits. It refers to the version reviewed, not every later change.</p>
      <ul className="mt-2 space-y-1">{(correction.reviewed_snapshot.media_urls ?? []).filter(url => /^https:\/\//.test(url)).map((url, i) => <li key={`${url}-${i}`}><a className="break-all underline" href={url} target="_blank" rel="noopener noreferrer">Reviewed media {i + 1}</a></li>)}</ul>
      <ul className="mt-2 space-y-1">{correction.sources.filter(source => /^https:\/\//.test(source)).map((source, i) => <li key={`${source}-${i}`}><a className="break-all underline" href={source} target="_blank" rel="noopener noreferrer">Source {i + 1}: {source}</a></li>)}</ul>
    </details>
  </div>;
}
export function PostCorrectionNotice({ postID }: { postID: string }) {
  const { user } = useAuth(); const owner = user?.id ?? "";
  const query = useQuery({ queryKey: ["post-corrections", owner, postID], enabled: !!owner, gcTime: 0, retry: false,
    queryFn: ({ signal }) => safetyRequest<Correction[]>(owner, `whisper_corrections?select=*&post_id=eq.${encodeURIComponent(postID)}&order=updated_at.desc`, undefined, signal) });
  if (query.isError) return <p className="px-4 py-2 text-xs text-muted-foreground">Correction status unavailable. <button className="min-h-11 underline" onClick={() => void query.refetch()}>Retry</button></p>;
  return <>{query.data?.map(correction => <aside key={correction.id} aria-label="Reviewed post correction" className="mx-4 my-3 rounded-xl border border-border bg-secondary/40 p-3"><CorrectionContent correction={correction} /></aside>)}</>;
}
