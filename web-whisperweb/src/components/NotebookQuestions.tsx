import { useEffect, useMemo, useRef, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Sparkles } from "lucide-react";
import { toast } from "sonner";
import { Button } from "./ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "./ui/dialog";
import { useChatOperationGuard } from "@/hooks/useChatOperationGuard";
import { notebookSelectionSources } from "@/lib/notebookSelection";
import { runNotebookIntelligence } from "@/lib/notebookIntelligence";
import { listNotebookDocuments, saveNotebookDocument } from "@/lib/notebookStorage";
import { type NotebookDocument, type NotebookProposal, type NotebookResult } from "@/lib/notebookDocument";
import { NOTEBOOK_WORKFLOWS, notebookBrief, notebookResultWriting, type NotebookWorkflow } from "@/lib/notebookWorkflow";

/** One Jasper surface: its entire context is the parent workspace's explicit selection. */
export function NotebookQuestions({ ownerId, documents, disabled = false, onDocumentSaved }: { ownerId: string; documents: NotebookDocument[]; disabled?: boolean; onDocumentSaved?: () => void }): JSX.Element {
  const client = useQueryClient();
  const [workflow, setWorkflow] = useState<NotebookWorkflow>("ask");
  const [question, setQuestion] = useState<string>("");
  const [consent, setConsent] = useState<boolean>(false);
  const [answer, setAnswer] = useState<NotebookResult | null>(null);
  const [resultDocuments, setResultDocuments] = useState<NotebookDocument[]>([]);
  const [resultContext, setResultContext] = useState<string>("");
  const [writing, setWriting] = useState<string>("");
  const [title, setTitle] = useState<string>("Combined brief");
  const [proposal, setProposal] = useState<NotebookProposal | null>(null);
  const [destination, setDestination] = useState<string>("");
  const [review, setReview] = useState<{ title: string; owner: string; when: string }>({ title: "", owner: "", when: "" });
  const controller = useRef<AbortController | null>(null);
  const signature = documents.map((entry) => `${entry.id}:${entry.storageRevision}`).join("|");
  const context = `${signature}:${workflow}:${question}`;
  const scope = `${context}:${disabled}`;
  const resultCurrent = resultContext === context && !disabled;
  const begin = useChatOperationGuard(ownerId, scope);
  const validation = useMemo(() => { try { notebookSelectionSources(ownerId, documents); return null; } catch (error) { return (error as Error).message; } }, [ownerId, documents]);
  useEffect(() => { controller.current?.abort(); setConsent(false); setProposal(null); return () => controller.current?.abort(); }, [scope]);
  useEffect(() => { if (documents.length !== 1 && workflow === "enhance") setWorkflow("summarize"); }, [documents.length, workflow]);
  async function verify(check: () => void): Promise<NotebookDocument[]> {
    check(); if (disabled) throw new Error("Finish saving your writing first.");
    const current = await listNotebookDocuments(ownerId); check();
    if (documents.some((entry) => !current.some((item) => item.id === entry.id && item.storageRevision === entry.storageRevision))) throw new Error("A selected note changed. Refresh and try again.");
    return current;
  }
  const ask = useMutation({ mutationFn: async () => {
    if (workflow === "enhance" && documents.length !== 1) throw new Error("Enhance works with one note; choose Summarize for multiple notes.");
    if (!consent || (workflow === "ask" && !question.trim())) throw new Error("Review the sources and approve this request first.");
    const check = begin(); const abort = new AbortController(); controller.current = abort;
    await verify(check);
    const sources = notebookSelectionSources(ownerId, documents);
    const result = await runNotebookIntelligence(documents[0], question.trim() || null, check, abort.signal, sources, workflow);
    await verify(check); abort.signal.throwIfAborted();
    setResultDocuments(documents); setResultContext(context); setAnswer(result); setWriting(notebookResultWriting(result)); setTitle(workflow === "summarize" ? "Combined brief" : `${NOTEBOOK_WORKFLOWS[workflow].label} · selected notes`); setConsent(false);
  } });
  const saveOutput = useMutation({ networkMode: "always", mutationFn: async () => {
    const check = begin(); check(); const current = await listNotebookDocuments(ownerId); check();
    if (disabled || resultDocuments.some((note) => note.ownerId !== ownerId)) throw new Error("Finish saving the open note first.");
    if (!answer || !writing.trim() || !title.trim()) throw new Error("Review and name your draft first.");
    if (current.length >= 200) throw new Error("Notebook is full. Export and remove a note first; your draft remains here.");
    const saved = await saveNotebookDocument(notebookBrief(ownerId, resultDocuments, answer, title.trim(), writing), check); check(); return saved;
  }, onSuccess: () => { toast.success("Saved a new note; private account saving is queued. Originals are unchanged."); void client.invalidateQueries({ queryKey: ["personal-notebook", ownerId] }); } });
  const keepEnhancement = useMutation({ networkMode: "always", mutationFn: async () => {
    const check = begin(); const current = await verify(check);
    const target = current.find((note) => note.id === documents[0]?.id);
    if (!resultCurrent || workflow !== "enhance" || documents.length !== 1 || !target || !answer) throw new Error("Generate a fresh enhancement for this note first.");
    const saved = await saveNotebookDocument({ ...target, enhancement: { ...answer, revision: target.revision } }, check); check(); return saved;
  }, onSuccess: (saved) => { client.setQueryData<NotebookDocument[]>(["personal-notebook", ownerId], (prior) => (prior ?? []).map((note) => note.id === saved.id ? saved : note)); onDocumentSaved?.(); toast.success("Enhanced version kept in this note. Your original writing is unchanged."); } });
  const track = useMutation({ networkMode: "always", mutationFn: async () => {
    const check = begin(); const current = await verify(check);
    const target = current.find((note) => note.id === destination && documents.some((picked) => picked.id === note.id));
    if (!resultCurrent) throw new Error("Sources changed. Generate a fresh draft before tracking.");
    if (!target || !proposal || !answer || !review.title.trim()) throw new Error("Choose a destination note and review the follow-up.");
    if (target.commitments.length >= 100 || target.commitments.some((item) => item.title.toLocaleLowerCase() === review.title.trim().toLocaleLowerCase())) throw new Error("That item is already tracked, or the destination holds 100 follow-ups.");
    const saved = await saveNotebookDocument({ ...target, commitments: [...target.commitments, { ...review, title: review.title.trim(), id: crypto.randomUUID(), done: false, sources: answer.sources.filter((source) => proposal.sourceIds.includes(source.id)) }] }, check); check(); return saved;
  }, onSuccess: (saved) => { setProposal(null); client.setQueryData<NotebookDocument[]>(["personal-notebook", ownerId], (prior) => (prior ?? []).map((note) => note.id === saved.id ? saved : note)); onDocumentSaved?.(); toast.success("Follow-up tracked. Nothing was sent."); } });
  const citations = (ids: string[]): JSX.Element => <>{ids.map((id) => { const source = answer?.sources.find((entry) => entry.id === id); const note = resultDocuments[Number(id.match(/^M(\d+)-/)?.[1] ?? 0) - 1]; return <details key={id} className="mt-2 border-l-2 border-border pl-3"><summary className="min-h-11 cursor-pointer py-3 text-xs font-medium">Source {id} · {note?.title || "Untitled note"}</summary><p className="whitespace-pre-wrap pb-3 text-xs leading-relaxed text-muted-foreground">{source?.text}</p><p className="pb-3 text-xs text-muted-foreground">Saved revision {note?.storageRevision} · Original selection kept</p></details>; })}</>;
  return <section aria-label="Jasper for selected notes" className="border-t border-border py-5">
    <header className="flex items-center gap-2"><Sparkles className="h-5 w-5 text-[#FF7340]" /><h2 className="font-semibold">Jasper</h2><span className="ml-auto text-xs text-muted-foreground">{documents.length} selected · private</span></header>
    <p className="mt-2 text-xs leading-relaxed text-muted-foreground">Only these notes. Never your entire notebook.</p>
    <div className="my-3 flex flex-wrap gap-1">{(Object.keys(NOTEBOOK_WORKFLOWS) as NotebookWorkflow[]).filter((key) => key !== "highlights" && (key !== "enhance" || documents.length === 1)).map((key) => <Button key={key} variant={workflow === key ? "default" : "ghost"} className="h-11 rounded-full px-3 text-xs" aria-pressed={workflow === key} onClick={() => setWorkflow(key)}>{NOTEBOOK_WORKFLOWS[key].label}</Button>)}</div>
    {workflow === "followups" && <details className="mb-3"><summary className="min-h-11 cursor-pointer py-3 text-sm">Already tracked by you</summary>{documents.map((note) => <div key={note.id} className="py-2"><h3 className="text-xs font-semibold">{note.title || "Untitled note"}</h3>{note.commitments.length ? note.commitments.map((item) => <p key={item.id} className="py-2 text-sm">{item.done ? "Completed" : "Open"} · {item.title} · {item.owner || "Unassigned"} · {item.when || "No date"}</p>) : <p className="py-2 text-xs text-muted-foreground">No tracked items</p>}</div>)}</details>}
    <textarea aria-label="Question across selected notes" maxLength={600} rows={2} className="w-full rounded-xl border border-border bg-background p-3 text-sm" placeholder={workflow === "ask" ? "What would you like to know?" : "Optional direction for this draft…"} value={question} onChange={(event) => setQuestion(event.target.value)} />
    <details className="mt-2"><summary className="min-h-11 cursor-pointer py-3 text-xs font-semibold">Review sources · {documents.length} notes</summary>{documents.map((note, index) => <div key={note.id} className="mb-3"><h3 className="text-sm font-medium">M{index + 1} · {note.title || "Untitled note"}</h3><p className="max-h-40 overflow-y-auto whitespace-pre-wrap py-2 text-xs text-muted-foreground">{note.notes}{note.transcript ? `\n\nSupplied transcript\n${note.transcript}` : ""}</p></div>)}</details>
    {validation && <p role="status" className="py-2 text-xs text-muted-foreground">{validation}</p>}
    {disabled && <p className="py-2 text-xs">Waiting for saved writing. Resolve any save error before using Jasper.</p>}
    <label className="flex min-h-11 items-center gap-3 py-3 text-xs leading-relaxed"><input type="checkbox" checked={consent} disabled={disabled || !!validation} onChange={(event) => setConsent(event.target.checked)} />Allow cloud AI to read the selected writing and supplied transcripts {workflow === "enhance" ? "and this note’s format preferences " : ""}for this request using Cloud Credits. Explicitly copied meeting notes are included. No recording bytes or unselected archive notes are sent.</label>
    {answer && <p className="pb-3 text-xs text-muted-foreground">Generating again replaces this temporary draft. Save or copy any edits you want to keep first.</p>}
    <Button className="h-11 rounded-full" disabled={disabled || !!validation || !consent || (workflow === "ask" && !question.trim()) || ask.isPending} onClick={() => ask.mutate()}>{ask.isPending ? "Reading selected sources…" : `${NOTEBOOK_WORKFLOWS[workflow].label} with Jasper`}</Button>
    {ask.isPending && <Button variant="ghost" className="h-11" onClick={() => controller.current?.abort()}>Stop</Button>}
    {ask.error && <p role="alert" className="mt-3 text-sm">{ask.error.message}</p>}
    {answer && <div aria-live="polite" className="mt-6 space-y-5"><p className="text-xs text-muted-foreground">{resultCurrent ? "AI draft" : "Previous draft · not the current request"} · {resultDocuments.map((note) => note.title || "Untitled note").join(" · ")}. Original source snapshots retained; check citations.</p>{answer.insufficient && <p>There isn’t enough evidence in the selected notes.</p>}{answer.sections.map((section) => <section key={section.title}><h3 className="font-serif text-xl">{section.title}</h3>{section.items.map((item) => <div key={item.text} className="mt-3 text-sm leading-relaxed"><p>{item.text}</p>{citations(item.sourceIds)}</div>)}</section>)}
      {workflow === "enhance" && documents.length === 1 && <div><Button variant="outline" className="h-11 rounded-full" disabled={!resultCurrent || keepEnhancement.isPending} onClick={() => keepEnhancement.mutate()}>Keep enhanced version in this note</Button>{keepEnhancement.error && <p role="alert" className="py-2 text-sm">{keepEnhancement.error.message}</p>}</div>}
      {answer.actions.map((action) => <article key={action.title} className="border-t border-border pt-4"><p className="text-xs text-muted-foreground">Suggested · not tracked</p><h3 className="mt-2 text-sm font-semibold">{action.title}</h3><p className="mt-1 text-xs">{action.owner || "Unassigned"} · {action.when || "No date stated"}</p>{citations(action.sourceIds)}<Button variant="outline" className="h-11 rounded-full text-xs" disabled={!resultCurrent} onClick={() => { setProposal(action); setDestination(""); setReview({ title: action.title, owner: action.owner, when: action.when }); }}>Review & track</Button></article>)}
      {!answer.insufficient && <details><summary className="min-h-11 cursor-pointer py-3 text-sm font-semibold">Edit & save a separate draft</summary><input aria-label="Combined draft title" value={title} maxLength={160} onChange={(event) => setTitle(event.target.value)} className="my-2 min-h-11 w-full rounded-xl border border-border bg-background px-3 text-sm" /><textarea aria-label="Editable combined draft" value={writing} maxLength={30000} onChange={(event) => setWriting(event.target.value)} className="min-h-48 w-full rounded-xl border border-border bg-background p-3 text-sm leading-relaxed" /><p className="py-3 text-xs text-muted-foreground">A new private note includes the original source snapshots and note references, with account saving queued. Nothing is sent to attendees.</p><div className="flex flex-wrap gap-2"><Button className="h-11 rounded-full" disabled={disabled || saveOutput.isPending || !writing.trim()} onClick={() => saveOutput.mutate()}>Save as new note</Button><Button variant="outline" className="h-11 rounded-full" onClick={() => void navigator.clipboard.writeText(writing).then(() => toast.success("Draft copied for your review."), () => toast.error("Select the draft text and copy it manually."))}>Copy draft</Button></div>{saveOutput.error && <p role="alert" className="py-2 text-sm">{saveOutput.error.message}</p>}</details>}
    </div>}
    <Dialog open={!!proposal} onOpenChange={(open) => { if (!open) setProposal(null); }}><DialogContent><DialogHeader><DialogTitle>Review follow-up</DialogTitle><DialogDescription>Choose where to track it. Nobody is notified.</DialogDescription></DialogHeader><label className="text-xs">Destination note<select aria-label="Destination note" className="mt-1 min-h-11 w-full border border-border bg-background px-2" value={destination} onChange={(event) => setDestination(event.target.value)}><option value="">Choose a note…</option>{documents.map((note) => <option key={note.id} value={note.id}>{note.title || "Untitled note"}</option>)}</select></label>{(["title", "owner", "when"] as const).map((key) => <label key={key} className="text-xs">{key === "title" ? "Follow-up" : key === "owner" ? "Owner (optional)" : "Timing (optional)"}<input className="mt-1 min-h-11 w-full rounded-xl border border-border bg-background px-3 text-sm" value={review[key]} maxLength={key === "title" ? 300 : 80} onChange={(event) => setReview((old) => ({ ...old, [key]: event.target.value }))} /></label>)}<Button className="h-11" disabled={track.isPending || disabled || !destination || !review.title.trim()} onClick={() => track.mutate()}>Track in chosen note</Button>{track.error && <p role="alert" className="text-sm">{track.error.message}</p>}</DialogContent></Dialog>
  </section>;
}
