import { useEffect, useRef, useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { Highlighter, Loader2, Sparkles, X } from "lucide-react";
import { toast } from "sonner";
import { Button } from "./ui/button";
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "./ui/alert-dialog";
import { useChatOperationGuard } from "@/hooks/useChatOperationGuard";
import { notebookSources, type NotebookDocument, type NotebookResult, type NotebookSource } from "@/lib/notebookDocument";
import { selectedHighlight, type NotebookHighlight, type NotebookSelection } from "@/lib/notebookHighlights";
import { NOTEBOOK_WORKFLOWS, type NotebookWorkflow } from "@/lib/notebookWorkflow";
import { runNotebookIntelligence } from "@/lib/notebookIntelligence";

type Request = { snapshot: NotebookDocument; sources: NotebookSource[]; workflow: NotebookWorkflow; question: string; scope: string };

/** A frozen, explicitly chosen scope. Typing never expands an in-flight AI request. */
export function NotebookInlineJasper({ document, selection, external, onClearExternal, onHighlight, onKeep }: {
  document: NotebookDocument; selection: NotebookSelection | null; external?: { sources: NotebookSource[]; label: string } | null; onClearExternal?: () => void;
  onHighlight: (highlight: NotebookHighlight) => void; onKeep: (result: NotebookResult) => void;
}): JSX.Element {
  const begin = useChatOperationGuard(document.ownerId, document.id);
  const abort = useRef<AbortController | null>(null);
  const [question, setQuestion] = useState<string>("");
  const [asking, setAsking] = useState<boolean>(false);
  const [approved, setApproved] = useState<boolean>(false);
  const [consent, setConsent] = useState<Request | null>(null);
  const [dismissed, setDismissed] = useState<string[]>([]);
  const [kept, setKept] = useState<boolean>(false);
  useEffect(() => () => abort.current?.abort(), []);
  const validSelection = selection && selection.revision === document.revision && document[selection.kind].slice(selection.start, selection.end) === selection.text ? selection : null;
  const scope = external?.label ?? (validSelection ? `Selected ${validSelection.kind === "notes" ? "writing" : "transcript"} · ${validSelection.text.length} characters` : "Current note · writing and pasted transcript");
  const ai = useMutation({ networkMode: "always", mutationFn: async ({ request, check, controller }: { request: Request; check: () => void; controller: AbortController }) => {
    check(); controller.signal.throwIfAborted();
    const result = await runNotebookIntelligence(request.snapshot, request.question || null, check, controller.signal, request.sources, request.workflow);
    check(); return { result, request };
  }, onSuccess: () => { setDismissed([]); setKept(false); } });
  const send = (request: Request): void => {
    if (ai.isPending) return;
    const check = begin(), controller = new AbortController(); abort.current = controller;
    ai.mutate({ request, check, controller });
  };
  const start = (workflow: NotebookWorkflow): void => {
    if (ai.isPending) return;
    try {
      if (selection && !validSelection && !external) throw new Error("The selected passage changed. Select it again before using Jasper.");
      const sources = external?.sources ?? (validSelection ? notebookSources({ notes: validSelection.kind === "notes" ? validSelection.text : "", transcript: validSelection.kind === "transcript" ? validSelection.text : "" }) : notebookSources(document));
      const request = { snapshot: document, sources, workflow, question: workflow === "ask" ? question.trim() : "", scope };
      if (approved) send(request); else setConsent(request);
    } catch (error) { toast.error((error as Error).message); }
  };
  const highlightQuote = (text: string, kind: NotebookSource["kind"]): void => {
    const snapshot = ai.data?.request.snapshot;
    if (!snapshot || snapshot.revision !== document.revision) { toast("The writing changed. Find key points again before applying highlights."); return; }
    const start = document[kind].indexOf(text);
    if (start < 0 || document[kind].indexOf(text, start + 1) >= 0) { toast("Select this quote in your writing to highlight its exact occurrence."); return; }
    try { onHighlight(selectedHighlight(document, { kind, start, end: start + text.length, text, revision: document.revision }, "jasper")); setDismissed((prior) => [...prior, text]); } catch (error) { toast.error((error as Error).message); }
  };
  return <section aria-label="Inline Jasper" className="my-3 border-l-2 border-rose-300/70 pl-3 dark:border-rose-800">
    <div className="flex flex-wrap items-center gap-1">
      <Sparkles className="mr-1 h-4 w-4 text-rose-500" aria-hidden="true" />
      {validSelection && !external && <Button variant="ghost" className="h-11 rounded-full px-3 text-xs" onClick={() => { try { onHighlight(selectedHighlight(document, validSelection, "manual")); } catch (error) { toast.error((error as Error).message); } }}><Highlighter className="mr-1 h-3.5 w-3.5" />Highlight</Button>}
      <Button variant="ghost" className="h-11 rounded-full px-3 text-xs" onClick={() => setAsking((value) => !value)}>Ask Jasper</Button>
      {(["enhance", "summarize", "highlights", "followups"] as const).map((workflow) => <Button key={workflow} variant="ghost" className="h-11 rounded-full px-3 text-xs" disabled={ai.isPending} onClick={() => start(workflow)}>{NOTEBOOK_WORKFLOWS[workflow].label}</Button>)}
    </div>
    <p className="text-[11px] leading-5 text-muted-foreground">{scope}{external && <button className="ml-2 min-h-11 underline" onClick={onClearExternal}>Use note instead</button>}</p>
    {asking && <form className="mt-2 flex gap-2" onSubmit={(event) => { event.preventDefault(); start("ask"); }}><input aria-label="Ask Jasper about selected context" className="min-h-11 min-w-0 flex-1 rounded-xl border border-border bg-transparent px-3 text-sm" placeholder="What should I take away?" value={question} maxLength={600} onChange={(event) => setQuestion(event.target.value)} /><Button type="submit" className="h-11 rounded-full" disabled={!question.trim() || ai.isPending}>Ask</Button></form>}
    {ai.isPending && <div role="status" className="my-3 inline-flex items-center gap-2 rounded-full bg-rose-50 px-3 text-xs dark:bg-rose-950/30"><Loader2 className="h-3.5 w-3.5 motion-safe:animate-spin" />{ai.variables?.request.workflow === "enhance" ? "Enhancing notes…" : "Reading selected passages…"}<Button variant="ghost" className="h-11 px-2 text-xs" onClick={() => abort.current?.abort()}>Stop</Button></div>}
    {ai.isError && <p role="alert" className="py-3 text-xs text-destructive">{ai.error.message}</p>}
    {ai.data && <div className="mt-4 space-y-3 motion-safe:animate-in motion-safe:fade-in motion-safe:duration-300">
      <p className="text-xs text-muted-foreground">{ai.data.request.scope} · snapshot {new Date(ai.data.result.generatedAt).toLocaleTimeString()}{ai.data.request.snapshot.revision !== document.revision ? " · writing has since changed" : ""}</p>
      {ai.data.result.insufficient && <p className="text-sm">These passages don’t contain enough evidence to answer reliably.</p>}
      {ai.data.result.sections.map((section) => <div key={section.title}><h4 className="mb-2 font-serif text-lg">{section.title}</h4>{section.items.filter((item) => !dismissed.includes(item.text)).map((item) => <div key={item.text} className="mb-3"><p className="whitespace-pre-wrap text-sm leading-6">{item.text}</p><details className="text-xs text-muted-foreground"><summary className="min-h-11 cursor-pointer py-3">Source · {item.sourceIds.join(", ")}</summary>{ai.data.result.sources.filter((source) => item.sourceIds.includes(source.id)).map((source) => <p key={source.id} className="mb-2 whitespace-pre-wrap border-l border-border pl-3">{source.text}</p>)}</details>{ai.data.request.workflow === "highlights" && <div className="flex gap-2"><Button variant="outline" className="h-11 rounded-full text-xs" disabled={!!external} onClick={() => { const source = ai.data?.result.sources.find((entry) => item.sourceIds.includes(entry.id) && entry.text.includes(item.text)); if (source) highlightQuote(item.text, source.kind); else toast.error("That suggestion is not an exact quote. Your writing is unchanged."); }}>Keep highlight</Button><Button variant="ghost" className="h-11 text-xs" onClick={() => setDismissed((prior) => [...prior, item.text])}><X className="mr-1 h-3 w-3" />Dismiss</Button></div>}</div>)}</div>)}
      {!ai.data.result.insufficient && ai.data.request.workflow !== "highlights" && <Button variant="outline" className="h-11 rounded-full text-xs" disabled={kept} onClick={() => { onKeep(ai.data.result); setKept(true); }}>{kept ? "Draft retained below" : "Keep draft & review follow-ups"}</Button>}
      <Button variant="ghost" className="h-11 text-xs" onClick={() => ai.reset()}>Dismiss result</Button>
    </div>}
    <AlertDialog open={!!consent} onOpenChange={(open) => { if (!open) setConsent(null); }}><AlertDialogContent><AlertDialogHeader><AlertDialogTitle>Use Jasper with this context?</AlertDialogTitle><AlertDialogDescription>{consent?.scope}. These passages and outline preferences are processed by cloud AI. Nothing is sent to attendees. Later Jasper taps in this note use the context shown beside the controls; highlighting alone sends nothing.</AlertDialogDescription></AlertDialogHeader><AlertDialogFooter><AlertDialogCancel>Cancel</AlertDialogCancel><AlertDialogAction onClick={() => { if (consent) { setApproved(true); send(consent); setConsent(null); } }}>Continue with Jasper</AlertDialogAction></AlertDialogFooter></AlertDialogContent></AlertDialog>
  </section>;
}
