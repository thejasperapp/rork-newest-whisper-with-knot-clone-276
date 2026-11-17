import "fake-indexeddb/auto";
import { describe, expect, it } from "vitest";
import { newNotebookDocument, type NotebookDocument } from "./notebookDocument";
import { applyNotebookCloud, deleteNotebookDocument, listNotebookDocuments, saveNotebookDocument } from "./notebookStorage";
import type { NotebookCloudRow } from "./notebookSync";
const check = (): void => {};
const cloud = (document: NotebookDocument, revision = 1, operation: string = crypto.randomUUID()): NotebookCloudRow => ({ id: document.id, owner_id: document.ownerId, operation_id: operation, revision, document, deleted: false, updated_at: new Date().toISOString() });
const enabled = async (): Promise<NotebookDocument> => saveNotebookDocument({ ...newNotebookDocument(crypto.randomUUID()), notes: "Initial writing", syncEnabled: true }, check);

describe("private cloud reconciliation", () => {
  it("acknowledges an upload without erasing edits made during the request", async () => {
    const sent = await enabled();
    const edited = await saveNotebookDocument({ ...sent, notes: "New offline text" }, check);
    await applyNotebookCloud(cloud(sent, 1, sent.syncOperationId), check, sent);
    const [stored] = await listNotebookDocuments(sent.ownerId);
    expect(stored.notes).toBe(edited.notes);
    expect(stored.syncedStorageRevision).toBe(sent.storageRevision);
    expect(stored.storageRevision).toBe(edited.storageRevision);
  });
  it("keeps queued deletion when a late save acknowledgment lands", async () => {
    const sent = await enabled(); await deleteNotebookDocument(sent, check);
    await applyNotebookCloud(cloud(sent, 1, sent.syncOperationId), check, sent);
    expect(await listNotebookDocuments(sent.ownerId)).toEqual([]);
    const [tombstone] = await listNotebookDocuments(sent.ownerId, true);
    expect(tombstone.notes).toBe(""); expect(tombstone.deletedAt).toBeTruthy();
    expect(tombstone.storageRevision).not.toBe(tombstone.syncedStorageRevision);
  });
  it("preserves unseen remote text before advancing a conflicting deletion", async () => {
    const sent = await enabled(); await applyNotebookCloud(cloud(sent, 1, sent.syncOperationId), check, sent);
    const [stored] = await listNotebookDocuments(sent.ownerId); await deleteNotebookDocument(stored, check);
    expect(await applyNotebookCloud(cloud({ ...sent, notes: "Unseen remote writing" }, 2), check)).toBe(1);
    const [copy] = await listNotebookDocuments(sent.ownerId);
    expect(copy.notes).toBe("Unseen remote writing"); expect(copy.syncEnabled).toBe(false); expect(copy.id).not.toBe(sent.id);
    const tombstone = (await listNotebookDocuments(sent.ownerId, true)).find((entry) => entry.id === sent.id)!;
    expect(tombstone.deletedAt).toBeTruthy(); expect(tombstone.cloudRevision).toBe(2);
  });
  it("keeps both dirty local text and a newer cloud version", async () => {
    const sent = await enabled();
    expect(await applyNotebookCloud(cloud({ ...sent, notes: "Remote writing" }, 2), check)).toBe(1);
    const list = await listNotebookDocuments(sent.ownerId);
    expect(list.map((entry) => entry.notes).sort()).toEqual(["Initial writing", "Remote writing"]);
    expect(list.find((entry) => entry.id !== sent.id)?.syncEnabled).toBe(false);
  });
  it("recognizes an idempotent response and rejects mismatched acknowledgments", async () => {
    const sent = await enabled(); const row = cloud(sent, 1, sent.syncOperationId);
    await applyNotebookCloud(row, check);
    expect(await applyNotebookCloud(row, check)).toBe(0);
    expect(await listNotebookDocuments(sent.ownerId)).toHaveLength(1);
    await expect(applyNotebookCloud({ ...row, owner_id: crypto.randomUUID() }, check, sent)).rejects.toThrow();
    await expect(applyNotebookCloud({ ...row, operation_id: crypto.randomUUID() }, check, sent)).rejects.toThrow("acknowledgment");
  });
  it("aborts reconciliation if account generation changes inside the transaction", async () => {
    const sent = await enabled(); let calls = 0;
    await expect(applyNotebookCloud(cloud({ ...sent, notes: "Never adopted" }, 2), () => { if (++calls === 3) throw new Error("account changed"); })).rejects.toThrow();
    expect((await listNotebookDocuments(sent.ownerId))[0].notes).toBe("Initial writing");
  });
});
