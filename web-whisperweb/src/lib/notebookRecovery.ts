import { notebookDocumentSchema, type NotebookDocument } from "./notebookDocument";

export interface NotebookRecovery { key: string; document: NotebookDocument }
const prefix = (ownerId: string): string => `whisper-notebook-recovery:${ownerId}:`;

/** Synchronous recovery survives route changes or account switches before IndexedDB autosave. */
export function retainNotebookRecovery(document: NotebookDocument, editorId: string): void {
  try { localStorage.setItem(`${prefix(document.ownerId)}${editorId}`, JSON.stringify(document)); }
  catch { throw new Error("Draft recovery is unavailable. Keep this editor open until it says saved, or export your writing."); }
}

/** Clearing one editor's recovery cannot discard a different tab's unsaved writing. */
export function clearNotebookRecovery(ownerId: string, editorId: string): void {
  try { localStorage.removeItem(`${prefix(ownerId)}${editorId}`); } catch { /* A retained recovery is safer than discarding a note. */ }
}

/** Recovery is explicit, account-scoped, and always restored as a new copy. */
export function listNotebookRecoveries(ownerId: string): NotebookRecovery[] {
  const result: NotebookRecovery[] = [];
  try {
    for (const key of Object.keys(localStorage)) {
      if (!key.startsWith(prefix(ownerId))) continue;
      try {
        const raw = localStorage.getItem(key) ?? "";
        if (raw.length > 2_000_000) continue;
        const document = notebookDocumentSchema.parse(JSON.parse(raw));
        if (document.ownerId === ownerId) result.push({ key: key.slice(prefix(ownerId).length), document });
      } catch { /* Never erase malformed recovery data. */ }
    }
  } catch { return []; }
  return result.sort((a, b) => b.document.updatedAt.localeCompare(a.document.updatedAt));
}
