import { describe, expect, it } from "vitest";
import { newNotebookDocument } from "./notebookDocument";
import { notebookSelectionSources } from "./notebookSelection";

describe("explicit selected Notebook sources", () => {
  it("keeps exact excerpts under distinct source IDs without treating titles as evidence", () => {
    const owner = crypto.randomUUID();
    const documents = [{ ...newNotebookDocument(owner), title: "Invented decision", notes: "Proposal only." }, { ...newNotebookDocument(owner), transcript: "Approved on Friday." }];
    expect(notebookSelectionSources(owner, documents)).toEqual([{ id: "M1-N1", kind: "notes", text: "Proposal only." }, { id: "M2-T1", kind: "transcript", text: "Approved on Friday." }]);
  });
  it("rejects other accounts, deleted entries, duplicate entries and empty selection", () => {
    const owner = crypto.randomUUID(), note = { ...newNotebookDocument(owner), notes: "Private" };
    expect(() => notebookSelectionSources(crypto.randomUUID(), [note])).toThrow("account");
    expect(() => notebookSelectionSources(owner, [{ ...note, deletedAt: new Date().toISOString() }])).toThrow("account");
    expect(() => notebookSelectionSources(owner, [note, note])).toThrow("eight");
    expect(() => notebookSelectionSources(owner, [])).toThrow("eight");
  });
  it("refuses oversized combined context instead of silently truncating", () => {
    const owner = crypto.randomUUID();
    expect(() => notebookSelectionSources(owner, [1, 2].map(() => ({ ...newNotebookDocument(owner), notes: "x".repeat(13000) })))).toThrow("24,000");
    expect(() => notebookSelectionSources(owner, Array.from({ length: 9 }, () => ({ ...newNotebookDocument(owner), notes: "x" })))).toThrow("eight");
  });
});
