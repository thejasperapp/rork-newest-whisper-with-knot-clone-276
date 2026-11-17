import { z } from "zod";
import { supabase } from "./supabase";
import { notebookDocumentSchema } from "./notebookDocument";
import { applyNotebookCloud, listNotebookDocuments, saveNotebookDocument } from "./notebookStorage";

export const notebookCloudSchema = z.object({ owner_id: z.string().uuid(), id: z.string().uuid(), revision: z.number().int().positive(), operation_id: z.string().uuid(), document: notebookDocumentSchema.nullable(), deleted: z.boolean(), updated_at: z.string() });
export type NotebookCloudRow = z.infer<typeof notebookCloudSchema>;

const editors = new Map<string, Set<string>>();
const running = new Set<string>();
/** Protect every mounted editor, including the in-call notepad, from remote replacement. */
export function protectNotebookEditor(owner: string, id: string): () => void {
  const key = `${owner}:${id}`; const token = crypto.randomUUID();
  const tokens = editors.get(key) ?? new Set<string>(); tokens.add(token); editors.set(key, tokens);
  return () => { tokens.delete(token); if (!tokens.size) editors.delete(key); };
}

/** Safe, actionable copy; database diagnostics and note contents never reach the UI. */
export function notebookSyncError(code?: string): string {
  if (["42P01", "42883", "PGRST202", "PGRST205"].includes(code ?? "")) return "Account saving isn't configured on the server yet. Your writing remains on this device; retry after setup is completed.";
  if (["42501", "PGRST301", "PGRST302", "28000"].includes(code ?? "")) return "Your account couldn't authorize this save. Sign in again and retry.";
  if (code === "40001") return "Another device has newer edits. Finish editing and close the note, then retry; both versions will be kept.";
  if (code === "54000") return "Your account's note limit was reached. Free space before retrying this save.";
  return "Couldn't sync to your account. Check your connection and retry; unsent changes remain on this device.";
}

/** Account sync uses durable writes as its retry queue. Independent uploads survive a single-note failure. */
export async function syncNotebook(owner: string, activeEditor: () => string | null, assertCurrent: () => void, signal: AbortSignal): Promise<string> {
  const check = (): void => { assertCurrent(); if (signal.aborted) throw new Error("Sync stopped. Unsent writing remains on this device."); };
  while (running.has(owner)) { check(); await new Promise((resolve) => setTimeout(resolve, 100)); }
  check(); running.add(owner);
  const protectedEntry = (id: string): boolean => id === activeEditor() || editors.has(`${owner}:${id}`);
  try {
    const auth = await supabase.auth.getSession(); check();
    if (auth.error || auth.data.session?.user.id !== owner) throw new Error("Sign in again to sync your notes.");
    let cursor: string | null = null; let deferred = false; let conflicts = 0;
    for (;;) {
      let query = supabase.from("whisper_private_notebooks").select("*").eq("owner_id", owner).order("id").limit(50).abortSignal(signal);
      if (cursor) query = query.gt("id", cursor);
      const { data, error } = await query; check();
      if (error) throw new Error(notebookSyncError(error.code));
      const rows = z.array(notebookCloudSchema).parse(data);
      for (const row of rows) {
        check();
        if (row.owner_id !== owner || (row.document && (row.document.ownerId !== owner || row.document.id !== row.id))) throw new Error("Could not verify this notebook. Nothing was replaced.");
        if (protectedEntry(row.id)) {
          const stored = (await listNotebookDocuments(owner, true)).find((note) => note.id === row.id); check();
          if (stored && stored.syncOperationId === row.operation_id) await applyNotebookCloud(row, check, stored);
          else if (!stored || row.revision > (stored.cloudRevision ?? 0)) deferred = true;
          continue;
        }
        conflicts += await applyNotebookCloud(row, () => { check(); if (protectedEntry(row.id)) throw new Error("Finish editing and close the note to receive newer edits."); });
      }
      if (rows.length < 50) break;
      cursor = rows[rows.length - 1].id;
    }
    // Pull all edits and tombstones before enrolling older writing. Never overwrite an open editor.
    for (const note of await listNotebookDocuments(owner)) {
      check();
      if (!note.syncEnabled && !protectedEntry(note.id)) await saveNotebookDocument({ ...note, syncEnabled: true }, check);
    }
    const local = await listNotebookDocuments(owner, true); check();
    const failures: string[] = [];
    for (const document of [...local.filter((entry) => !!entry.deletedAt), ...local.filter((entry) => !entry.deletedAt)]) {
      check();
      if (!document.syncEnabled || document.syncedStorageRevision === document.storageRevision) continue;
      try {
        if (!document.syncOperationId) throw new Error("Reopen and save this note before syncing.");
        const { data, error } = await supabase.rpc("save_private_notebook", {
          p_id: document.id, p_revision: document.cloudRevision ?? 0, p_operation: document.syncOperationId,
          p_document: document, p_deleted: !!document.deletedAt,
        }).abortSignal(signal); check();
        if (error) throw new Error(notebookSyncError(error.code));
        const row = notebookCloudSchema.parse(data); check();
        await applyNotebookCloud(row, check, document);
      } catch (error) {
        check();
        failures.push(error instanceof z.ZodError ? "Couldn't verify the account save confirmation. Retry your save." : error instanceof Error ? error.message : notebookSyncError());
      }
    }
    check();
    if (failures.length) throw new Error(`${failures.length} note${failures.length === 1 ? " needs" : "s need"} attention. ${failures[0]}`);
    return conflicts ? `Synced. ${conflicts} conflicting version(s) kept for recovery.` : deferred ? "Newer edits available · finish editing and close the note to receive them" : "Account sync up to date";
  } finally { running.delete(owner); }
}
