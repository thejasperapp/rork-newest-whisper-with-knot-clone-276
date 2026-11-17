import "fake-indexeddb/auto";
import { describe, expect, it, vi } from "vitest";
import { newNotebookDocument } from "./notebookDocument";
import { deleteNotebookDocument, listNotebookDocuments, saveNotebookDocument } from "./notebookStorage";

const current = (): void => {};
describe("transactional notebook persistence", () => {
  it("stores and lists only the requested account's documents", async () => {
    const a = crypto.randomUUID(), b = crypto.randomUUID();
    const savedA = await saveNotebookDocument({ ...newNotebookDocument(a), notes: "A's writing" }, current);
    await saveNotebookDocument({ ...newNotebookDocument(b), notes: "B's writing" }, current);
    expect((await listNotebookDocuments(a)).map((note) => note.id)).toEqual([savedA.id]);
    expect((await listNotebookDocuments(b))[0].notes).toBe("B's writing");
  });
  it("rejects an outdated save without clobbering newer writing", async () => {
    const first = await saveNotebookDocument(newNotebookDocument(crypto.randomUUID()), current);
    await saveNotebookDocument({ ...first, notes: "Newer writing" }, current);
    await expect(saveNotebookDocument({ ...first, notes: "Stale overwrite" }, current)).rejects.toThrow("another tab");
    expect((await listNotebookDocuments(first.ownerId))[0].notes).toBe("Newer writing");
  });
  it("rejects stale deletion and allows deletion after renewed review", async () => {
    const first = await saveNotebookDocument(newNotebookDocument(crypto.randomUUID()), current);
    const latest = await saveNotebookDocument({ ...first, notes: "Review this change first" }, current);
    await expect(deleteNotebookDocument(first, current)).rejects.toThrow("another tab");
    expect(await listNotebookDocuments(first.ownerId)).toHaveLength(1);
    await deleteNotebookDocument(latest, current);
    expect(await listNotebookDocuments(first.ownerId)).toEqual([]);
  });
  it("never resurrects a deleted note from an old editor", async () => {
    const saved = await saveNotebookDocument(newNotebookDocument(crypto.randomUUID()), current);
    await deleteNotebookDocument(saved, current);
    await expect(saveNotebookDocument(saved, current)).rejects.toThrow();
    expect(await listNotebookDocuments(saved.ownerId)).toEqual([]);
  });
  it("aborts when the account changes at the final write boundary", async () => {
    const document = newNotebookDocument(crypto.randomUUID());
    let checks = 0;
    const guard = vi.fn(() => { if (++checks === 3) throw new Error("changed"); });
    await expect(saveNotebookDocument(document, guard)).rejects.toThrow("session changed");
    expect(await listNotebookDocuments(document.ownerId)).toEqual([]);
  });
  it("serializes concurrent editors so only one can commit a revision", async () => {
    const saved = await saveNotebookDocument(newNotebookDocument(crypto.randomUUID()), current);
    const results = await Promise.allSettled([saveNotebookDocument({ ...saved, notes: "First tab" }, current), saveNotebookDocument({ ...saved, notes: "Second tab" }, current)]);
    expect(results.filter((result) => result.status === "fulfilled")).toHaveLength(1);
    expect(results.filter((result) => result.status === "rejected")).toHaveLength(1);
  });
});
