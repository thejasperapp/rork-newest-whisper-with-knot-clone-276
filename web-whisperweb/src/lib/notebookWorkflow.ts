import { newNotebookDocument, type NotebookDocument, type NotebookResult } from "./notebookDocument";

/** Explicit tasks, independent of whether optional user guidance is supplied. */
export const NOTEBOOK_WORKFLOWS = {
  highlights: { label: "Find key points", instruction: "Suggest up to 5 important highlights. In a Key passages section, each item text must be a VERBATIM continuous quote from exactly one cited source. Do not paraphrase or add quotation marks. Return no actions." },
  ask: { label: "Ask", instruction: "Answer the question in an Answer section. Return no actions." },
  enhance: { label: "Enhance", instruction: "Enhance the selected writing without replacing it. Organize supported decisions and open questions; distinguish proposals from decisions." },
  summarize: { label: "Summarize", instruction: "Create a combined brief across ALL selected notes. Identify themes, decisions and unresolved questions. Return no actions. Do not invent agreement." },
  compare: { label: "Compare", instruction: "Compare ALL selected notes: agreements, conflicts, changes and unresolved questions. Identify notes by their M source prefix. Do not infer chronology or consensus without evidence. Return no actions." },
  followups: { label: "Follow-ups", instruction: "Propose source-supported action items in actions. Draft a concise follow-up message in a Follow-up draft section, with cited sentences. Do not claim anything was sent or assign owners or timing absent from sources." },
} as const;
export type NotebookWorkflow = keyof typeof NOTEBOOK_WORKFLOWS;

/** Human-editable output with immutable evidence and note/version references; originals are untouched. */
export function notebookBrief(documentOwner: string, documents: NotebookDocument[], result: NotebookResult, title: string, writing: string): NotebookDocument {
  const note = newNotebookDocument(documentOwner, null, title);
  const references = documents.map((document, index) => `M${index + 1}: ${document.title || "Untitled note"} · note ${document.id} · saved revision ${document.storageRevision}`);
  note.notes = `${writing}\n\nSource notes (snapshot)\n${references.join("\n")}\n\nSupplied passages\n${result.sources.map((source) => `[${source.id}] ${source.text}`).join("\n\n")}`;
  note.enhancement = { ...result, revision: 0 };
  return note;
}

export function notebookResultWriting(result: NotebookResult): string {
  return result.sections.map((section) => `${section.title}\n${section.items.map((item) => `${item.text} [${item.sourceIds.join(", ")}]`).join("\n\n")}`).join("\n\n");
}
