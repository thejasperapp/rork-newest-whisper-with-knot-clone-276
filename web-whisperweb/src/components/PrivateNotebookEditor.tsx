import { NotebookInlineJasper } from "./NotebookInlineJasper";
import { NotebookTextArea } from "./NotebookTextArea";
import { rebaseHighlights, selectedHighlight, type NotebookSelection } from "@/lib/notebookHighlights";
import { protectNotebookEditor } from "@/lib/notebookSync";
import { useEffect, useImperativeHandle, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { useMutation } from "@tanstack/react-query";
import { useForm } from "react-hook-form";
import { Check, CheckCircle2, Circle, MoreHorizontal, Sparkles } from "lucide-react";
import { toast } from "sonner";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog";
import type { ReactNode, Ref } from "react";
import { useChatOperationGuard } from "@/hooks/useChatOperationGuard";
import { exportNotebook, NOTEBOOK_TEMPLATES, type NotebookDocument, type NotebookProposal, type NotebookResult, type NotebookSource } from "@/lib/notebookDocument";
import { saveNotebookDocument } from "@/lib/notebookStorage";
import { runNotebookIntelligence } from "@/lib/notebookIntelligence";
import { clearNotebookRecovery, retainNotebookRecovery } from "@/lib/notebookRecovery";

const inputClass = "min-h-11 w-full rounded-xl border border-border bg-background px-3 py-2 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring";

/** Autosaved human writing with separately versioned, source-checked Jasper drafts. */
export function PrivateNotebookEditor({ initial, onClose, onSaved, onBusyChange, recordingContent, workspaceMode = true, editorRef, titleContainer, externalContext, onClearExternal, syncError, onRetrySync, sidekickMode = false }: { onRetrySync?: () => void; sidekickMode?: boolean; externalContext?: { sources: NotebookSource[]; label: string } | null; onClearExternal?: () => void; syncError?: string; initial: NotebookDocument; onClose: () => void; onSaved: (saved?: NotebookDocument) => void; onBusyChange?: (busy: boolean) => void; recordingContent?: (importTranscript: (text: string) => void) => ReactNode; workspaceMode?: boolean; titleContainer?: HTMLElement | null; editorRef?: Ref<{ importTranscript: (text: string) => void }> }): JSX.Element {
  const [document, setDocument] = useState<NotebookDocument>(initial);
  const current = useRef<NotebookDocument>(initial);
  const [selection, setSelection] = useState<NotebookSelection | null>(null);
  const [previousDraft, setPreviousDraft] = useState<{ result: NotebookResult | null } | null>(null);
  useEffect(() => protectNotebookEditor(initial.ownerId, initial.id), [initial.ownerId, initial.id]);
  const editNumber = useRef<number>(0);
  const editorId = useRef<string>(crypto.randomUUID());
  const [recoveryError, setRecoveryError] = useState<string | null>(null);
  const [dirty, setDirty] = useState<boolean>(false);
  const [showEnhanced, setShowEnhanced] = useState<boolean>(false);
  const enhancementTime = initial.enhancement?.generatedAt;
  useEffect(() => { if (sidekickMode && enhancementTime) setShowEnhanced(true); }, [enhancementTime, sidekickMode]);
  const [organizeOpen, setOrganizeOpen] = useState<boolean>(false);
  const [transcriptOpen, setTranscriptOpen] = useState<boolean>(false);
  const [jasperOpen, setJasperOpen] = useState<boolean>(false);
  const [question, setQuestion] = useState<string>("");
  const [consent, setConsent] = useState<{ question: string | null } | null>(null);
  const [answer, setAnswer] = useState<NotebookResult | null>(null);
  const [source, setSource] = useState<NotebookSource | null>(null);
  const [proposal, setProposal] = useState<NotebookProposal | null>(null);
  const [discard, setDiscard] = useState<boolean>(false);
  const controller = useRef<AbortController | null>(null);
  const beginOperation = useChatOperationGuard(initial.ownerId, initial.id);
  const mounted = useRef<boolean>(true);
  useEffect(() => { mounted.current = true; return () => { mounted.current = false; controller.current?.abort(); }; }, []);

  const save = useMutation({
    networkMode: "always",
    mutationFn: async (input: { document: NotebookDocument; edit: number }) => {
      const assertCurrent = beginOperation();
      const saved = await saveNotebookDocument(input.document, assertCurrent);
      assertCurrent(); return saved;
    },
    onSuccess: (saved, sent) => {
      if (!mounted.current) return;
      const next = { ...current.current, storageRevision: saved.storageRevision, updatedAt: saved.updatedAt, cloudRevision: saved.cloudRevision, syncedStorageRevision: saved.syncedStorageRevision, syncOperationId: saved.syncOperationId, syncEnabled: saved.syncEnabled };
      current.current = next; setDocument(next); setDirty(editNumber.current !== sent.edit);
      if (editNumber.current === sent.edit) { clearNotebookRecovery(initial.ownerId, editorId.current); setRecoveryError(null); }
      else { try { retainNotebookRecovery(next, editorId.current); } catch (error) { setRecoveryError((error as Error).message); } }
      onSaved(saved);
    },
  });
  const mutateSave = save.mutate;
  useEffect(() => {
    if (!dirty || save.isPending || save.isError || discard) return;
    const timer = setTimeout(() => mutateSave({ document: current.current, edit: editNumber.current }), 650);
    return () => clearTimeout(timer);
  }, [document, dirty, save.isPending, save.isError, discard, mutateSave]);
  useEffect(() => {
    const warn = (event: BeforeUnloadEvent): void => { if (dirty || save.isPending) { event.preventDefault(); event.returnValue = ""; } };
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [dirty, save.isPending]);

  function update(patch: Partial<NotebookDocument>, sourcesChanged = false): void {
    if ((patch.notes?.length ?? 0) > 60000 || (patch.transcript?.length ?? 0) > 60000) { toast.error("That paste exceeds 60,000 characters. Nothing was pasted; split it into smaller entries."); return; }
    onBusyChange?.(true);
    ++editNumber.current;
    let highlights = patch.highlights ?? current.current.highlights ?? [];
    for (const kind of ["notes", "transcript"] as const) if (patch[kind] !== undefined) highlights = rebaseHighlights(highlights, kind, current.current[kind], patch[kind], current.current.revision + 1);
    const next = { ...current.current, ...patch, highlights, updatedAt: new Date().toISOString(), revision: current.current.revision + (sourcesChanged ? 1 : 0) };
    try { retainNotebookRecovery(next, editorId.current); setRecoveryError(null); } catch (error) { setRecoveryError((error as Error).message); }
    current.current = next; setDocument(next); setDirty(true);
    if (sourcesChanged) setAnswer(null);
    if (save.isError) save.reset();
  }
  useImperativeHandle(editorRef, () => ({ importTranscript: (text: string) => {
    if (current.current.transcript.trim()) { toast.error("This note already has a transcript. Your existing text was kept."); return; }
    update({ transcript: text }, true); setTranscriptOpen(true);
  } }));
  useEffect(() => {
    if (!dirty && !save.isPending && initial.storageRevision >= current.current.storageRevision) { current.current = initial; setDocument(initial); }
  }, [initial, dirty, save.isPending]);
  const ai = useMutation({
    mutationFn: async (question: string | null) => {
      const snapshot = current.current;
      const assertCurrent = beginOperation();
      controller.current?.abort();
      const abort = new AbortController(); controller.current = abort;
      const result = await runNotebookIntelligence(snapshot, question, assertCurrent, abort.signal);
      assertCurrent();
      if (current.current.revision !== snapshot.revision) throw new Error("Your sources changed while Jasper worked. Run it again for the updated note.");
      return { result, question };
    },
    onSuccess: ({ result, question }) => { if (question !== null) setAnswer(result); else update({ enhancement: result }); },
  });
  useEffect(() => { onBusyChange?.(dirty || save.isPending || save.isError); }, [dirty, save.isPending, save.isError, onBusyChange]);
  const stale = !!document.enhancement && document.enhancement.revision !== document.revision;
  const close = (): void => { if (dirty || save.isPending) { setDiscard(true); return; } onClose(); };
  const download = (): void => {
    const url = URL.createObjectURL(new Blob([exportNotebook(current.current)], { type: "text/markdown;charset=utf-8" }));
    const link = window.document.createElement("a"); link.href = url; link.download = "whisper-notebook.md"; link.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
  };

  return <>
    <section aria-label="Expanded note" className={sidekickMode ? "min-w-0 bg-transparent" : "min-w-0 bg-background"}>
        <header className="flex items-center justify-between gap-3 py-1">
          <p className="flex flex-wrap items-center gap-2 text-xs" aria-live="polite">{save.isError || recoveryError ? "Couldn't save changes" : dirty || save.isPending ? "Saving…" : document.syncEnabled && document.cloudRevision && document.syncedStorageRevision === document.storageRevision ? <><Check className="h-3 w-3" />Saved to account</> : syncError ? "Account save needs attention" : navigator.onLine ? "Waiting for account confirmation" : "Waiting for connection"} · private</p><DropdownMenu><DropdownMenuTrigger asChild><Button variant="ghost" size="icon" className="h-11 w-11 shrink-0" aria-label="Note options"><MoreHorizontal className="h-5 w-5" /></Button></DropdownMenuTrigger><DropdownMenuContent align="end" className={sidekickMode ? "z-[90]" : undefined}><DropdownMenuItem onSelect={download}>Export entire note</DropdownMenuItem><DropdownMenuItem onSelect={() => setOrganizeOpen((value) => !value)}>Organize & format</DropdownMenuItem>{!document.syncEnabled && <DropdownMenuItem onSelect={() => update({ syncEnabled: true })}>Save to my account</DropdownMenuItem>}<DropdownMenuItem onSelect={close}>{sidekickMode ? "Finish editing" : "Collapse note"}</DropdownMenuItem></DropdownMenuContent></DropdownMenu>
        </header>
        <div className="pb-6 pt-3">
          {!sidekickMode && (titleContainer ? createPortal(<input aria-label="Note title" value={document.title} maxLength={160} onChange={(event) => update({ title: event.target.value })} placeholder="Untitled note" className="mb-5 w-full bg-transparent font-serif text-3xl tracking-tight outline-none sm:text-4xl" />, titleContainer) : <input aria-label="Note title" value={document.title} maxLength={160} onChange={(event) => update({ title: event.target.value })} placeholder="Untitled note" className="mb-5 w-full bg-transparent font-serif text-3xl tracking-tight outline-none sm:text-4xl" />)}
          {recordingContent?.((text) => {
            if (current.current.transcript.trim()) { toast.error("This note already has a transcript. Your existing text was kept."); return; }
            update({ transcript: text }, true); setTranscriptOpen(true);
          })}
          <details open={organizeOpen} hidden={!organizeOpen} onToggle={(event) => setOrganizeOpen(event.currentTarget.open)} className="mb-5 rounded-xl border border-border px-3"><summary className="cursor-pointer py-3 text-sm font-semibold">Organize & format</summary><div className="grid gap-3 pb-3 sm:grid-cols-2">
            <label className="text-xs text-muted-foreground">Folder or project<input className={`${inputClass} mt-1`} value={document.folder} maxLength={80} onChange={(event) => update({ folder: event.target.value })} /></label>
            <label className="text-xs text-muted-foreground">People (for your reference)<input className={`${inputClass} mt-1`} value={document.people} maxLength={300} onChange={(event) => update({ people: event.target.value })} /></label>
            <label className="text-xs text-muted-foreground">Format<select className={`${inputClass} mt-1`} value={document.templateId} onChange={(event) => update({ templateId: event.target.value }, true)}>{NOTEBOOK_TEMPLATES.map((template) => <option key={template.id} value={template.id}>{template.label}</option>)}</select></label>
            <label className="text-xs text-muted-foreground">Custom outline preferences<textarea className={`${inputClass} mt-1`} value={document.instructions} maxLength={1000} placeholder="Optional · e.g. highlight unanswered questions" onChange={(event) => update({ instructions: event.target.value }, true)} /></label>
            <p className="text-xs text-muted-foreground sm:col-span-2">Changing the format never replaces your writing.</p>
          </div></details>
          {sidekickMode && document.enhancement && <label className="mb-4 block text-xs text-muted-foreground"><select aria-label="Notes version" className="h-11 bg-transparent pr-3 text-xs" value={showEnhanced ? "enhanced" : "original"} onChange={(event) => setShowEnhanced(event.target.value === "enhanced")}><option value="original">Original notes</option><option value="enhanced">Enhanced notes</option></select></label>}
          {sidekickMode && showEnhanced && document.enhancement && <div className="pb-6">{stale && <p className="mb-3 text-xs text-muted-foreground">Your writing changed after this enhancement. Its original sources are preserved.</p>}<ResultSections result={document.enhancement} onSource={setSource} /></div>}
          <div hidden={sidekickMode && showEnhanced && !!document.enhancement} className="pb-4">{!sidekickMode && <h3 className="mb-3 text-sm font-medium text-muted-foreground">My notes</h3>}<NotebookTextArea label="My original notes" value={document.notes} kind="notes" revision={document.revision} highlights={document.highlights ?? []} onChange={(notes) => update({ notes }, true)} onSelection={setSelection} placeholder="Write something worth remembering…" /></div>
            <details hidden={sidekickMode && !document.transcript} open={transcriptOpen} onToggle={(event) => setTranscriptOpen(event.currentTarget.open)} className="border-t border-border"><summary className="min-h-11 cursor-pointer py-3 text-sm font-semibold">Transcript</summary><div className="pb-4"><h3 className="text-xs font-bold uppercase tracking-wider">Pasted transcript</h3><p className="my-3 text-xs leading-relaxed text-muted-foreground">Paste text you have permission to use. Use the recording above to bring in its transcript, or paste text here. Speaker labels in pasted text are not verified.</p><NotebookTextArea label="Pasted transcript" value={document.transcript} kind="transcript" revision={document.revision} highlights={document.highlights ?? []} onChange={(transcript) => update({ transcript }, true)} onSelection={setSelection} placeholder="Paste a transcript you have permission to use…" /><p className="text-xs leading-relaxed text-muted-foreground">Jasper reads up to 24,000 characters and 160 passages per entry. Longer text stays saved, but needs splitting before enhancement.</p></div></details>
            {sidekickMode && selection && <Button variant="ghost" className="h-11 text-xs" onClick={() => { try { const highlight = selectedHighlight(document, selection, "manual"); if ((document.highlights?.length ?? 0) >= 100) throw new Error("Keep up to 100 highlights."); update({ highlights: [...(document.highlights ?? []), highlight] }); } catch (error) { toast.error((error as Error).message); } }}>Highlight selected writing</Button>}
            {!sidekickMode && <NotebookInlineJasper document={document} selection={selection} external={externalContext} onClearExternal={onClearExternal} onHighlight={(highlight) => {
              const existing = current.current.highlights ?? [];
              if (existing.length >= 100) { toast.error("Keep up to 100 highlights per note."); return; }
              if (existing.some((item) => !item.stale && item.kind === highlight.kind && item.start === highlight.start && item.end === highlight.end)) return;
              update({ highlights: [...existing, highlight] });
            }} onKeep={(result) => { setPreviousDraft({ result: current.current.enhancement }); update({ enhancement: result }); setJasperOpen(true); }} />}
            {previousDraft && <Button variant="ghost" className="h-11 text-xs" onClick={() => { update({ enhancement: previousDraft.result }); setPreviousDraft(null); }}>Undo retained draft</Button>}
            {!!document.highlights?.length && <details className="border-t border-border"><summary className="min-h-11 cursor-pointer py-3 text-xs">Retained highlights · {document.highlights.length}</summary>{document.highlights.map((item) => <div key={item.id} className="mb-2 flex items-start gap-2"><p className="flex-1 whitespace-pre-wrap text-sm leading-6"><mark className="bg-amber-300/25 text-foreground">{item.text}</mark><span className="block text-[11px] text-muted-foreground">{item.kind} · {item.origin}{item.stale ? " · original quote; writing changed" : ""}</span></p><Button variant="ghost" className="h-11 text-xs" onClick={() => update({ highlights: (current.current.highlights ?? []).filter((row) => row.id !== item.id) })}>Remove</Button></div>)}</details>}
            {syncError && document.syncedStorageRevision !== document.storageRevision && <p role="status" className="py-3 text-xs text-muted-foreground">{syncError}{onRetrySync && <Button variant="ghost" className="h-11 text-xs" onClick={onRetrySync}>Retry account save</Button>}</p>}
            <details hidden={sidekickMode && !document.commitments.length && !document.enhancement?.actions.length} open={jasperOpen} onToggle={(event) => setJasperOpen(event.currentTarget.open)} className="border-t border-border"><summary className="min-h-11 cursor-pointer py-3 text-sm font-semibold">{sidekickMode ? "Next steps" : workspaceMode ? "Saved drafts & tracked items" : "Review with Jasper"}</summary><div className="space-y-6 py-4">
              {!workspaceMode && <><div className="flex items-start gap-3"><Sparkles className="mt-1 h-6 w-6 text-[#FF7340]" /><div><h3 className="font-semibold">From conversation to clarity.</h3><p className="mt-1 text-xs text-muted-foreground">Source-linked drafts. You make the final call.</p></div></div>
              <Button className="h-11 w-full rounded-full bg-foreground text-background hover:bg-foreground/90" disabled={ai.isPending || save.isPending || dirty || save.isError} onClick={() => setConsent({ question: null })}>{ai.isPending ? "Jasper is reading your sources…" : document.enhancement ? "Regenerate draft" : "Enhance my notes"}</Button>
              {ai.isPending && <Button variant="ghost" className="h-11" onClick={() => controller.current?.abort()}>Stop</Button>}
              {ai.isError && <p role="alert" className="text-sm text-destructive">{ai.error.message}</p>}</>}
              {stale && <p className="rounded-xl border border-amber-500/30 bg-amber-500/5 p-3 text-xs">Your sources or format changed. This draft refers to its original snapshot.</p>}
              {document.enhancement && <>
                {!sidekickMode && <ResultSections result={document.enhancement} onSource={setSource} />}
                {!!document.enhancement.actions.length && <div className="space-y-3"><h3 className="text-xs font-bold uppercase tracking-wider">Proposed follow-ups</h3><p className="text-xs leading-relaxed text-muted-foreground">Review wording, owner and timing before tracking. No messages, invitations or project tasks are sent.</p>{document.enhancement.actions.map((action) => <article key={action.title} className="rounded-2xl border border-border bg-muted/20 p-4"><h4 className="text-sm font-semibold">{action.title}</h4><p className="mt-1 text-xs text-muted-foreground">{action.owner || "Unassigned"} · {action.when || "No date stated"}</p><SourceLinks ids={action.sourceIds} sources={document.enhancement?.sources ?? []} onSource={setSource} /><Button variant="outline" className="mt-2 h-11 rounded-full text-xs" disabled={stale || document.commitments.some((item) => item.title.toLocaleLowerCase() === action.title.toLocaleLowerCase())} onClick={() => setProposal(action)}>Review & track</Button></article>)}</div>}
              </>}
              {!!document.commitments.length && <div className="space-y-3"><h3 className="text-xs font-bold uppercase tracking-wider">Tracked by you</h3>{document.commitments.map((item) => <div key={item.id}><button className="flex min-h-11 w-full items-start gap-3 text-left" onClick={() => update({ commitments: current.current.commitments.map((row) => row.id === item.id ? { ...row, done: !row.done } : row) })} aria-label={`${item.done ? "Reopen" : "Complete"} follow-up: ${item.title}`}>{item.done ? <CheckCircle2 className="mt-1 h-5 w-5 shrink-0" /> : <Circle className="mt-1 h-5 w-5 shrink-0" />}<div><p className={item.done ? "text-sm line-through opacity-60" : "text-sm"}>{item.title}</p><p className="mt-1 text-xs text-muted-foreground">{item.owner || "Unassigned"} · {item.when || "No due date"}</p></div></button><SourceLinks ids={item.sources.map((entry) => entry.id)} sources={item.sources} onSource={setSource} /></div>)}</div>}
              {!workspaceMode && <div className="space-y-3 border-t border-border pt-5"><h3 className="font-semibold">Ask this note</h3><textarea aria-label="Question for Jasper" className={inputClass} maxLength={600} value={question} onChange={(event) => setQuestion(event.target.value)} placeholder="What is still unresolved?" /><Button variant="outline" className="h-11 rounded-full" disabled={!question.trim() || ai.isPending || dirty || save.isPending || save.isError} onClick={() => setConsent({ question: question.trim() })}>Ask Jasper</Button>{answer && <ResultSections result={answer} onSource={setSource} />}</div>}
              <p className="text-xs leading-relaxed text-muted-foreground">Jasper can make mistakes. Check sources before relying on a draft. Answers search this entry only; they are not team-wide memory.</p>
            </div></details>
          {recoveryError && <p role="alert" className="mt-4 text-xs text-destructive">{recoveryError}</p>}
          {save.isError && <div role="alert" className="mt-5 rounded-xl border border-destructive/30 p-4"><p className="text-sm">{save.error.message}</p><Button variant="outline" className="mt-3 h-11" onClick={() => save.mutate({ document: current.current, edit: editNumber.current })}>Try saving again</Button></div>}
        </div>
    </section>
    <AlertDialog open={!!consent} onOpenChange={(open) => { if (!open) setConsent(null); }}><AlertDialogContent portalContainer={window.document.fullscreenElement as HTMLElement | null} overlayClassName="z-[100]" className="z-[110]"><AlertDialogHeader><AlertDialogTitle>Send this entry to Jasper?</AlertDialogTitle><AlertDialogDescription>Your notes, pasted transcript and outline preferences will be processed by cloud AI using Cloud Credits. Your original writing stays unchanged. Nothing is sent to attendees or your team.</AlertDialogDescription></AlertDialogHeader><AlertDialogFooter><AlertDialogCancel>Cancel</AlertDialogCancel><AlertDialogAction onClick={() => { if (consent) ai.mutate(consent.question); setConsent(null); }}>Continue</AlertDialogAction></AlertDialogFooter></AlertDialogContent></AlertDialog>
    <Dialog open={!!source} onOpenChange={(open) => { if (!open) setSource(null); }}><DialogContent portalContainer={window.document.fullscreenElement as HTMLElement | null} overlayClassName="z-[100]" className="z-[110]"><DialogHeader><DialogTitle>Source {source?.id}</DialogTitle><DialogDescription>{source?.provenance ?? (source?.kind === "notes" ? "Your original notes" : "Pasted transcript")} · snapshot at generation</DialogDescription></DialogHeader><p className="max-h-[50dvh] overflow-y-auto whitespace-pre-wrap text-sm leading-relaxed">{source?.text}</p><p className="text-xs text-muted-foreground">A citation lets you check the text; it doesn't guarantee Jasper interpreted it correctly.</p></DialogContent></Dialog>
    {proposal && <ReviewFollowup proposal={proposal} onCancel={() => setProposal(null)} onTrack={(edited) => {
      if (current.current.commitments.length >= 100) { toast.error("This note holds up to 100 tracked follow-ups."); return; }
      if (current.current.commitments.some((item) => item.title.toLocaleLowerCase() === edited.title.toLocaleLowerCase())) { toast.error("That follow-up is already tracked."); return; }
      update({ commitments: [...current.current.commitments, { id: crypto.randomUUID(), ...edited, done: false, sources: current.current.enhancement?.sources.filter((entry) => proposal.sourceIds.includes(entry.id)) ?? [] }] }); setProposal(null);
    }} />}
    <AlertDialog open={discard} onOpenChange={setDiscard}><AlertDialogContent portalContainer={window.document.fullscreenElement as HTMLElement | null} overlayClassName="z-[100]" className="z-[110]"><AlertDialogHeader><AlertDialogTitle>{save.isPending ? "Still saving your note" : "Keep your latest changes?"}</AlertDialogTitle><AlertDialogDescription>Stay here until the note is saved, or export a copy first. Discard closes the editor without saving changes that are still pending.</AlertDialogDescription></AlertDialogHeader><AlertDialogFooter><AlertDialogCancel>Keep editing</AlertDialogCancel><AlertDialogAction disabled={save.isPending} onClick={() => { clearNotebookRecovery(initial.ownerId, editorId.current); onClose(); }}>Discard unsaved edits</AlertDialogAction></AlertDialogFooter></AlertDialogContent></AlertDialog>
  </>;
}

function SourceLinks({ ids, sources, onSource }: { ids: string[]; sources: NotebookSource[]; onSource: (source: NotebookSource) => void }): JSX.Element {
  return <div className="mt-1 flex flex-wrap gap-1">{[...new Set(ids)].map((id) => <button key={id} className="min-h-11 min-w-11 rounded-full px-2 font-mono text-[11px] font-semibold text-muted-foreground hover:bg-muted hover:text-foreground" aria-label={`Read source ${id}`} onClick={() => { const source = sources.find((item) => item.id === id); if (source) onSource(source); }}>{id}</button>)}</div>;
}
function ResultSections({ result, onSource }: { result: NotebookResult; onSource: (source: NotebookSource) => void }): JSX.Element {
  return <div className="space-y-5">{result.insufficient && <p className="text-sm text-muted-foreground">There isn't enough information in these sources to answer that reliably.</p>}{result.sections.map((section) => <section key={section.title}><h3 className="mb-3 font-semibold">{section.title}</h3><div className="space-y-3">{section.items.map((item) => <div key={item.text}><p className="text-sm leading-relaxed">{item.text}</p><SourceLinks ids={item.sourceIds} sources={result.sources} onSource={onSource} /></div>)}</div></section>)}</div>;
}
function ReviewFollowup({ proposal, onTrack, onCancel }: { proposal: NotebookProposal; onTrack: (edited: Pick<NotebookProposal, "title" | "owner" | "when">) => void; onCancel: () => void }): JSX.Element {
  const { register, handleSubmit, formState: { errors } } = useForm<Pick<NotebookProposal, "title" | "owner" | "when">>({ defaultValues: { title: proposal.title, owner: proposal.owner, when: proposal.when } });
  return <Dialog open onOpenChange={(open) => { if (!open) onCancel(); }}><DialogContent portalContainer={window.document.fullscreenElement as HTMLElement | null} overlayClassName="z-[100]" className="z-[110]"><DialogHeader><DialogTitle>Review follow-up</DialogTitle><DialogDescription>Track it in this note only. No one is notified and no event or project task is created.</DialogDescription></DialogHeader><form className="space-y-4" onSubmit={handleSubmit((values) => onTrack({ ...values, title: values.title.trim() }))}><label className="block text-xs">Follow-up<textarea className={`${inputClass} mt-1`} {...register("title", { required: true, maxLength: 300, validate: (value) => !!value.trim() })} /></label><label className="block text-xs">Owner (optional)<input className={`${inputClass} mt-1`} {...register("owner", { maxLength: 80 })} /></label><label className="block text-xs">Due date or timing (optional)<input className={`${inputClass} mt-1`} {...register("when", { maxLength: 80 })} /></label>{Object.keys(errors).length > 0 && <p role="alert" className="text-xs text-destructive">Add a follow-up under 300 characters; owner and timing can each be up to 80.</p>}<Button type="submit" className="h-11 w-full rounded-full">Track follow-up</Button></form></DialogContent></Dialog>;
}
