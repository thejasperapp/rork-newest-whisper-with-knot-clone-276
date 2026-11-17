import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useAuth } from "@/hooks/useAuth";
import { useChatOperationGuard } from "@/hooks/useChatOperationGuard";
import { assertReceipt, safetyRequest, type Correction, type CorrectionAppeal, type ReviewReport } from "@/lib/safetyReview";
import { CorrectionContent } from "@/components/PostCorrectionNotice";

const control = "min-h-11 rounded-xl border border-border bg-background px-3 py-2 text-sm disabled:opacity-50";
function AppealForm({ owner, correction, appeal }: { owner: string; correction: Correction; appeal?: CorrectionAppeal }) {
  const [body, setBody] = useState(""); const client = useQueryClient(); const capture = useChatOperationGuard(owner, correction.id);
  const mutation = useMutation({ retry: false, mutationFn: async () => {
    const check = capture(); check(); const receipt = await safetyRequest(owner, "rpc/whisper_appeal_correction", { p_correction_id: correction.id, p_body: body }); check(); assertReceipt(receipt);
  }, onSuccess: () => { setBody(""); void client.invalidateQueries({ queryKey: ["safety-decisions", owner] }); } });
  if (appeal) return <div className="mt-3 border-t border-border pt-3"><p className="font-medium">Appeal: {appeal.status}</p><p className="whitespace-pre-wrap">{appeal.body}</p>{appeal.outcome && <p className="mt-2">Review outcome: {appeal.outcome}</p>}</div>;
  return <form className="mt-3 space-y-2" onSubmit={e => { e.preventDefault(); mutation.mutate(); }}><label className="block text-sm">Your response or appeal<textarea value={body} onChange={e => setBody(e.target.value)} minLength={10} maxLength={4000} required disabled={mutation.isPending || mutation.isSuccess} className={`${control} mt-2 block min-h-24 w-full`} /></label><button className={control} disabled={mutation.isPending || mutation.isSuccess}>{mutation.isSuccess ? "Appeal received" : mutation.isPending ? "Submitting…" : "Submit appeal"}</button>{mutation.isError && <p role="alert" className="text-sm text-destructive">Appeal not confirmed. Your text is still here; refresh decisions before retrying.</p>}</form>;
}
export function SafetyDecisions() { const { user } = useAuth(); return user ? <AccountDecisions key={user.id} owner={user.id} /> : null; }
function AccountDecisions({ owner }: { owner: string }) {
  const query = useQuery({ queryKey: ["safety-decisions", owner], gcTime: 0, retry: false, queryFn: async ({ signal }) => {
    const [corrections, appeals, restrictions, legacy] = await Promise.all([
      safetyRequest<Correction[]>(owner, `whisper_corrections?select=*&author_id=eq.${owner}&order=updated_at.desc`, undefined, signal),
      safetyRequest<CorrectionAppeal[]>(owner, `whisper_correction_appeals?select=*&author_id=eq.${owner}`, undefined, signal),
      safetyRequest<{ id: string; reason: string; review_at: string; expires_at: string; revoked_at: string | null }[]>(owner, `whisper_contact_restrictions?select=*&user_id=eq.${owner}`, undefined, signal),
      safetyRequest<{ id: string; body: string; status: string }[]>(owner, "whisper_liar_appeals?select=id,body,status&order=created_at.desc&limit=50", undefined, signal),
    ]); return { corrections, appeals, restrictions, legacy };
  } });
  return <section className="space-y-4 border-y border-border bg-card px-4 py-5 sm:rounded-3xl sm:border" aria-label="Decisions and appeals">
    <div className="flex items-center justify-between gap-3"><h2 className="text-lg font-semibold">Decisions & appeals</h2><button className={control} disabled={query.isFetching} onClick={() => void query.refetch()}>Refresh</button></div>
    <p className="text-sm text-muted-foreground">Private to this account and authorized reviewers. Corrections concern a reviewed post version, not your identity. AI analysis and report volume do not issue penalties.</p>
    {query.isPending && <p role="status">Loading decisions…</p>}{query.isError && <p role="alert" className="text-destructive">Decisions couldn’t be loaded. Refresh to try again.</p>}
    {query.data?.corrections.length === 0 && <p className="text-sm">No reviewed corrections for your posts.</p>}
    {query.data?.corrections.map(c => <article className="rounded-xl border border-border p-3" key={c.id}><CorrectionContent correction={c} /><AppealForm owner={owner} correction={c} appeal={query.data.appeals.find(a => a.correction_id === c.id)} /></article>)}
    {query.data?.restrictions.map(r => <article key={r.id} className="rounded-xl border border-border p-3 text-sm"><h3 className="font-semibold">Separate messaging restriction {r.revoked_at ? "· revoked" : Date.parse(r.expires_at) < Date.now() ? "· expired" : "· active"}</h3><p>{r.reason}</p><p>Review: {new Date(r.review_at).toLocaleString()}</p><p>Expiry: {new Date(r.expires_at).toLocaleString()}</p></article>)}
    {query.data?.legacy.map(a => <article key={a.id} className="rounded-xl border border-border p-3 text-sm"><h3 className="font-semibold">Historical appeal · {a.status}</h3><p>{a.body}</p><p className="text-muted-foreground">Preserved from the retired system. This is not a new confirmed finding or a public label.</p></article>)}
    <p className="text-xs text-muted-foreground">Historical username-only appeals are preserved for staff review. If yours is not listed, contact Support to confirm account ownership; a reused username does not grant access.</p>
    <ModerationReview owner={owner} />
  </section>;
}
function ModerationReview({ owner }: { owner: string }) {
  const permission = useQuery({ queryKey: ["reviewer-permission", owner], gcTime: 0, retry: false, queryFn: ({ signal }) => safetyRequest<boolean>(owner, "rpc/whisper_is_reviewer", {}, signal) });
  if (permission.data !== true) return null;
  return <ReviewerQueue key={owner} owner={owner} />;
}
function ReviewerQueue({ owner }: { owner: string }) {
  const [selected, setSelected] = useState<ReviewReport | null>(null); const [explanation, setExplanation] = useState(""); const [sources, setSources] = useState("");
  const [state, setState] = useState("active"); const [appealID, setAppealID] = useState(""); const [outcome, setOutcome] = useState("upheld"); const capture = useChatOperationGuard(owner, "review-queue");
  const query = useQuery({ queryKey: ["correction-review-queue", owner], gcTime: 0, retry: false, queryFn: async ({ signal }) => {
    const [reports, appeals, history, corrections] = await Promise.all([
      safetyRequest<ReviewReport[]>(owner, "whisper_reports?select=id,target_id,reason,details,post_snapshot,status&target_kind=in.(post,reel)&order=created_at.desc&limit=100", undefined, signal),
      safetyRequest<CorrectionAppeal[]>(owner, "whisper_correction_appeals?select=*&status=eq.pending&order=created_at.asc", undefined, signal),
      safetyRequest<{ id: string; correction_id: string; action: string; explanation: string; created_at: string }[]>(owner, "whisper_correction_history?select=*&order=created_at.desc&limit=100", undefined, signal),
      safetyRequest<Correction[]>(owner, "whisper_corrections?select=*&order=updated_at.desc&limit=100", undefined, signal),
    ]);
    const missing = [...new Set(appeals.map(a => a.correction_id).filter(id => !corrections.some(c => c.id === id)))];
    for (let i = 0; i < missing.length; i += 100) {
      const ids = missing.slice(i, i + 100).filter(id => /^[0-9a-f-]{36}$/i.test(id));
      if (ids.length) corrections.push(...await safetyRequest<Correction[]>(owner, `whisper_corrections?select=*&id=in.(${ids.join(",")})`, undefined, signal));
    }
    return { reports, appeals, history, corrections };
  } });
  const decision = useMutation({ retry: false, mutationFn: async () => {
    const check = capture(); check();
    const params = { p_explanation: explanation, p_sources: sources.split("\n").map(s => s.trim()).filter(Boolean) };
    const receipt = await safetyRequest(owner, appealID ? "rpc/whisper_review_correction_appeal" : "rpc/whisper_review_correction", appealID ? { ...params, p_appeal_id: appealID, p_outcome: outcome } : { ...params, p_report_id: selected?.id, p_state: state });
    check(); assertReceipt(receipt);
  }, onSuccess: () => { setSelected(null); setAppealID(""); setExplanation(""); setSources(""); void query.refetch(); } });
  return <details className="border-t border-border pt-4"><summary className="min-h-11 cursor-pointer font-semibold">Reviewer queue</summary>
    <p className="my-3 text-sm text-muted-foreground">Review the saved post version and independent sources. Do not treat opinions, satire, uncertainty, AI verdicts, or report counts as proof. You cannot review your own report or post; appeals require a different reviewer.</p>
    {query.isPending && <p>Loading queue…</p>}{query.isError && <p role="alert">Queue unavailable. <button className={control} onClick={() => void query.refetch()}>Retry</button></p>}
    <ul className="space-y-2">{query.data?.reports.map(r => <li key={r.id}><button className={`${control} w-full text-left`} disabled={decision.isPending} onClick={() => { setSelected(r); setAppealID(""); decision.reset(); setExplanation(""); setSources(""); }}>{r.reason} · {r.status} · {r.post_snapshot?.caption?.slice(0, 100) ?? "Historical report — no saved version"}</button></li>)}</ul>
    {(selected || appealID) && <form className="my-4 space-y-3 rounded-xl border border-border p-3" onSubmit={e => { e.preventDefault(); decision.mutate(); }}>
      <p className="text-sm whitespace-pre-wrap">Reported context: {selected?.details ?? "Appeal review"}</p><blockquote className="whitespace-pre-wrap border-l-2 border-border pl-3">{selected?.post_snapshot?.caption}</blockquote>
      {selected?.post_snapshot?.media_urls?.filter(url => /^https:\/\//.test(url)).map((url, i) => <a key={`${url}-${i}`} className="block min-h-11 text-sm underline" href={url} target="_blank" rel="noopener noreferrer">Reviewed media {i + 1}</a>)}
      {!selected?.post_snapshot && !appealID && <p>No immutable post version exists. Do not issue a correction from this legacy report.</p>}
      <label className="block text-sm">Human decision & reasoning<textarea required minLength={20} maxLength={4000} value={explanation} disabled={decision.isPending} onChange={e => setExplanation(e.target.value)} className={`${control} mt-2 block min-h-24 w-full`} /></label>
      <label className="block text-sm">Supporting HTTPS sources (one per line)<textarea value={sources} disabled={decision.isPending} onChange={e => setSources(e.target.value)} className={`${control} mt-2 block w-full`} /></label>
      {appealID ? <select className={control} value={outcome} onChange={e => setOutcome(e.target.value)}><option value="upheld">Uphold correction</option><option value="updated">Update correction</option><option value="withdrawn">Withdraw correction</option></select> : <select className={control} value={state} onChange={e => setState(e.target.value)}><option value="active">Publish / update correction</option><option value="withdrawn">Withdraw correction</option></select>}
      <button className={control} disabled={decision.isPending || (!selected?.post_snapshot && !appealID)}>Confirm reviewed decision</button>
      {decision.isError && <p role="alert" className="text-destructive">Decision not confirmed. Check permissions, independence, source links, and the saved post version. Refresh before retrying.</p>}
    </form>}
    <h3 className="mt-4 font-semibold">Pending appeals</h3>{query.data?.appeals.map(a => { const c = query.data.corrections.find(c => c.id === a.correction_id); return <article key={a.id} className="my-2 rounded-xl border border-border p-3"><p className="whitespace-pre-wrap text-sm">{a.body}</p>{c && <CorrectionContent correction={c} />}<button className={control} disabled={decision.isPending || !c} onClick={() => { setAppealID(a.id); setSelected(null); setExplanation(""); setSources(c?.sources.join("\n") ?? ""); decision.reset(); }}>Review appeal</button></article>; })}
    <details className="mt-4"><summary className="min-h-11 cursor-pointer">Action history</summary>{query.data?.history.map(h => <p key={h.id} className="border-b border-border py-2 text-xs">{new Date(h.created_at).toLocaleString()} · {h.action} · {h.explanation}</p>)}</details>
  </details>;
}
