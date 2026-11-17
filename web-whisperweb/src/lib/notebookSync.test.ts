import "fake-indexeddb/auto";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { syncNotebook, protectNotebookEditor, notebookSyncError, type NotebookCloudRow } from "./notebookSync";
import { listNotebookDocuments, saveNotebookDocument, deleteNotebookDocument } from "./notebookStorage";
import { newNotebookDocument } from "./notebookDocument";
const state = vi.hoisted(() => ({ owner: "", remote: [] as unknown[], readError: false, rpc: vi.fn() }));
vi.mock("./supabase", () => ({ supabase: {
  auth: { getSession: async () => ({ data: { session: { user: { id: state.owner } } } }) },
  from: () => { const chain = { select: () => chain, eq: () => chain, order: () => chain, limit: () => chain, abortSignal: () => chain, gt: () => chain, then: (resolve: (value: unknown) => unknown) => Promise.resolve({ data: state.remote, error: state.readError ? { code: "offline" } : null }).then(resolve) }; return chain; },
  rpc: (...args: unknown[]) => ({ abortSignal: async () => state.rpc(...args) }),
} }));
const check = () => {};
beforeEach(() => {
  state.owner = crypto.randomUUID(); state.remote = []; state.readError = false;
  state.rpc.mockReset().mockImplementation(async (_name, args) => ({ error: null, data: { id: args.p_id, owner_id: state.owner, document: args.p_deleted ? null : args.p_document, deleted: args.p_deleted, operation_id: args.p_operation, revision: args.p_revision + 1, updated_at: new Date().toISOString() } }));
});
const sync = () => syncNotebook(state.owner, () => null, check, new AbortController().signal);
describe("default private account saving", () => {
  it("continues independent uploads after a note conflicts and only acknowledges successful saves", async () => {
    const failed = await saveNotebookDocument(newNotebookDocument(state.owner), check);
    const good = await saveNotebookDocument(newNotebookDocument(state.owner), check);
    state.rpc.mockImplementation(async (_name, args) => args.p_id === failed.id ? { error: { code: "40001" }, data: null } : { error: null, data: { id: args.p_id, owner_id: state.owner, document: args.p_document, deleted: false, operation_id: args.p_operation, revision: 1, updated_at: new Date().toISOString() } });
    await expect(sync()).rejects.toThrow("1 note needs attention");
    const entries = await listNotebookDocuments(state.owner);
    expect(state.rpc).toHaveBeenCalledTimes(2);
    expect(entries.find((item) => item.id === good.id)?.syncedStorageRevision).toBe(good.storageRevision);
    expect(entries.find((item) => item.id === failed.id)?.cloudRevision).toBeUndefined();
  });
  it("does not report newer edits for an already acknowledged open note", async () => {
    const local = await saveNotebookDocument(newNotebookDocument(state.owner), check);
    await sync();
    const [saved] = await listNotebookDocuments(state.owner);
    const release = protectNotebookEditor(state.owner, local.id);
    state.remote = [{ owner_id: state.owner, id: local.id, document: saved, deleted: false, revision: saved.cloudRevision, operation_id: saved.syncOperationId, updated_at: new Date().toISOString() }];
    try { expect(await sync()).toBe("Account sync up to date"); } finally { release(); }
  });
  it("distinguishes missing server setup from authentication and connectivity", () => {
    expect(notebookSyncError("PGRST202")).toContain("isn't configured");
    expect(notebookSyncError("42501")).toContain("Sign in again");
    expect(notebookSyncError()).toContain("connection");
  });
  it("enrolls existing writing after remote lookup and records only acknowledged revisions", async () => {
    const local = await saveNotebookDocument({ ...newNotebookDocument(state.owner), syncEnabled: false, notes: "Existing local writing" }, check);
    await sync(); const [saved] = await listNotebookDocuments(state.owner);
    expect(saved.syncEnabled).toBe(true); expect(saved.syncedStorageRevision).toBe(saved.storageRevision); expect(saved.notes).toBe(local.notes); expect(state.rpc).toHaveBeenCalledTimes(1);
  });
  it("does not enroll notes while the remote deletion check is unavailable", async () => {
    await saveNotebookDocument({ ...newNotebookDocument(state.owner), syncEnabled: false }, check); state.readError = true;
    await expect(sync()).rejects.toThrow("sync"); expect(state.rpc).not.toHaveBeenCalled(); expect((await listNotebookDocuments(state.owner))[0].syncEnabled).toBe(false);
  });
  it("never reenrolls deleted local notes", async () => {
    const local = await saveNotebookDocument({ ...newNotebookDocument(state.owner), syncEnabled: false }, check); await deleteNotebookDocument(local, check);
    await sync(); expect(state.rpc).not.toHaveBeenCalled(); expect(await listNotebookDocuments(state.owner)).toEqual([]);
  });
  it("protects another mounted editor from remote replacement and migration", async () => {
    const local = await saveNotebookDocument({ ...newNotebookDocument(state.owner), syncEnabled: false, notes: "Open writing" }, check);
    const release = protectNotebookEditor(state.owner, local.id);
    state.remote = [{ owner_id: state.owner, id: local.id, document: { ...local, notes: "Remote text" }, deleted: false, revision: 2, operation_id: crypto.randomUUID(), updated_at: new Date().toISOString() } satisfies NotebookCloudRow];
    try { await sync(); expect((await listNotebookDocuments(state.owner))[0].notes).toBe("Open writing"); expect(state.rpc).not.toHaveBeenCalled(); } finally { release(); }
  });
});
