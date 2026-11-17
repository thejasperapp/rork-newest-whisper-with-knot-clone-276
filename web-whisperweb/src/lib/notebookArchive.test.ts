import "fake-indexeddb/auto";
import { describe, expect, it, vi } from "vitest";
import { importArchivedMeetingNote } from "./notebookArchive";
import { applyNotebookCloud, deleteNotebookDocument, listNotebookDocuments, saveNotebookDocument } from "./notebookStorage";
import { newNotebookDocument, notebookDocumentSchema } from "./notebookDocument";

const check = (): void => {};
const restore = async (): Promise<void> => {};
const meeting = (): Parameters<typeof importArchivedMeetingNote>[1] => ({ id: crypto.randomUUID(), title: "Planning recap", summary: "# Decisions\nSam will send the plan on Friday.", created_at: "2026-09-12T12:00:00Z", ended_at: "2026-09-12T12:30:00Z" });

describe("explicit meeting archive copies", () => {
  it("saves generated notes and recording references with private account saving but without transcript ingestion", async () => {
    const owner = crypto.randomUUID(), source = meeting(), recording = crypto.randomUUID();
    const note = await importArchivedMeetingNote(owner, source, [recording, recording], check, restore);
    expect(note.id).toBe(source.id); expect(note.meetingId).toBe(source.id); expect(note.notes).toBe(source.summary);
    expect(note.recordingIds).toEqual([recording]); expect(note.recapCopiedAt).toBeTruthy(); expect(note.transcript).toBe(""); expect(note.syncEnabled).toBe(true);
    expect(notebookDocumentSchema.parse(JSON.parse(JSON.stringify(note))).recordingIds).toEqual([recording]);
  });
  it("reopens existing writing and attachments unchanged even if the shared recap was regenerated", async () => {
    const owner = crypto.randomUUID(), source = meeting(), recording = crypto.randomUUID();
    const first = await importArchivedMeetingNote(owner, source, [recording], check, restore);
    const edited = await saveNotebookDocument({ ...first, notes: "My reviewed wording", revision: 2 }, check);
    const used = await importArchivedMeetingNote(owner, { ...source, summary: "New generated text" }, [], check, restore);
    expect(used).toEqual(edited); expect(await listNotebookDocuments(owner)).toHaveLength(1);
  });
  it("never resurrects a deleted private copy and preserves the original shared text", async () => {
    const owner = crypto.randomUUID(), source = meeting();
    const note = await importArchivedMeetingNote(owner, source, [], check, restore); await deleteNotebookDocument(note, check);
    await expect(importArchivedMeetingNote(owner, source, [], check, restore)).rejects.toThrow("private copy was deleted");
    expect(await listNotebookDocuments(owner)).toHaveLength(0); expect(source.summary).toContain("Sam will send");
  });
  it("checks remote tombstones before creating a private copy on a new device", async () => {
    const owner = crypto.randomUUID(), source = meeting();
    const remote = vi.fn(async () => { await applyNotebookCloud({ id: source.id, owner_id: owner, revision: 3, operation_id: crypto.randomUUID(), updated_at: new Date().toISOString(), deleted: true, document: null }, check); });
    await expect(importArchivedMeetingNote(owner, source, [], check, remote)).rejects.toThrow("private copy was deleted");
    expect(remote).toHaveBeenCalledOnce(); expect(await listNotebookDocuments(owner)).toEqual([]);
  });
  it("stops on account changes and unavailable remote checks without creating writing", async () => {
    const owner = crypto.randomUUID(), source = meeting(); let current = true;
    await expect(importArchivedMeetingNote(owner, source, [], () => { if (!current) throw new Error("Account changed"); }, async () => { current = false; })).rejects.toThrow("Account changed");
    await expect(importArchivedMeetingNote(owner, source, [], check, async () => { throw new Error("Offline"); })).rejects.toThrow("Offline");
    expect(await listNotebookDocuments(owner)).toEqual([]);
  });
  it("rejects oversized generated notes instead of truncating and separates owners", async () => {
    const owner = crypto.randomUUID(), other = crypto.randomUUID(), source = meeting();
    await expect(importArchivedMeetingNote(owner, { ...source, summary: "x".repeat(60001) }, [], check, restore)).rejects.toThrow("nothing was truncated");
    const a = await importArchivedMeetingNote(owner, source, [], check, restore), b = await importArchivedMeetingNote(other, source, [], check, restore);
    expect(a.id).toBe(b.id); expect(a.ownerId).not.toBe(b.ownerId);
  });
  it("respects capacity without changing the archive or media", async () => {
    const owner = crypto.randomUUID(), source = meeting();
    await Promise.all(Array.from({ length: 200 }, () => saveNotebookDocument(newNotebookDocument(owner), check)));
    await expect(importArchivedMeetingNote(owner, source, [], check, restore)).rejects.toThrow("Notebook is full");
    expect(await listNotebookDocuments(owner)).toHaveLength(200);
  });
});
