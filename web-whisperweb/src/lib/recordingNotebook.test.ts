import "fake-indexeddb/auto";
import { describe, expect, it } from "vitest";
import { ensureRecordingNote } from "./recordingNotebook";
import { recordingTranscriptText } from "./recordingNotebookText";
import { applyNotebookCloud, deleteNotebookDocument, listNotebookDocuments, saveNotebookDocument } from "./notebookStorage";
import { newNotebookDocument } from "./notebookDocument";

const check = (): void => {};
const recording = () => ({ id: crypto.randomUUID(), ownerId: crypto.randomUUID(), meetingId: crypto.randomUUID(), title: "Planning recording", createdAt: "2026-09-12T00:00:00Z", status: "ready" as const });

describe("durable recording-note relationship", () => {
  it("uses the recording identity and creates once across concurrent opens with account saving but without importing recording content", async () => {
    const record = recording();
    const [first, second] = await Promise.all([ensureRecordingNote(record, check), ensureRecordingNote(record, check)]);
    expect(first).toEqual(second); expect(first.id).toBe(record.id); expect(first.createdAt).toBe(record.createdAt);
    expect(first.notes).toBe(""); expect(first.transcript).toBe(""); expect(first.syncEnabled).toBe(true);
    expect(await listNotebookDocuments(record.ownerId)).toHaveLength(1);
  });
  it("reuses existing edited writing without resetting its title, transcript, revision, or permissions", async () => {
    const record = recording(); const initial = await ensureRecordingNote(record, check);
    const edited = await saveNotebookDocument({ ...initial, title: "My title", notes: "My private writing", transcript: "My reviewed source", syncEnabled: true }, check);
    expect(await ensureRecordingNote(record, check)).toEqual(edited);
    await expect(ensureRecordingNote({ ...record, meetingId: crypto.randomUUID() }, check)).rejects.toThrow();
    expect((await listNotebookDocuments(record.ownerId))[0]).toEqual(edited);
  });
  it("does not resurrect a deleted recording note or its writing", async () => {
    const record = recording(); const note = await ensureRecordingNote(record, check);
    await deleteNotebookDocument(note, check);
    await expect(ensureRecordingNote(record, check)).rejects.toThrow("deleted");
    expect(await listNotebookDocuments(record.ownerId)).toEqual([]);
    const [tombstone] = await listNotebookDocuments(record.ownerId, true);
    expect(tombstone.deletedAt).toBeTruthy(); expect(tombstone.notes).toBe(""); expect(tombstone.syncEnabled).toBe(true);
  });
  it("remembers a cloud deletion even on a device that never had the note", async () => {
    const record = recording();
    await applyNotebookCloud({ id: record.id, owner_id: record.ownerId, document: null, deleted: true, revision: 2, operation_id: crypto.randomUUID(), updated_at: record.createdAt }, check);
    await expect(ensureRecordingNote(record, check)).rejects.toThrow("deleted");
    expect(await listNotebookDocuments(record.ownerId)).toEqual([]);
  });
  it("isolates account owners and aborts at the final transaction boundary on account change", async () => {
    const record = recording(); let checks = 0;
    await expect(ensureRecordingNote(record, () => { if (++checks === 4) throw new Error("changed"); })).rejects.toThrow();
    expect(await listNotebookDocuments(record.ownerId)).toEqual([]);
    await ensureRecordingNote(record, check);
    const other = await ensureRecordingNote({ ...record, ownerId: crypto.randomUUID() }, check);
    expect(other.ownerId).not.toBe(record.ownerId); expect(await listNotebookDocuments(other.ownerId)).toHaveLength(1);
  });
  it("rejects unfinished capture and full notebooks while allowing reuse at capacity", async () => {
    const record = recording();
    await expect(ensureRecordingNote({ ...record, status: "recording" }, check)).rejects.toThrow("Stop");
    const saved = await ensureRecordingNote(record, check);
    await Promise.all(Array.from({ length: 199 }, () => saveNotebookDocument(newNotebookDocument(record.ownerId), check)));
    expect(await ensureRecordingNote(record, check)).toEqual(saved);
    await expect(ensureRecordingNote({ ...record, id: crypto.randomUUID() }, check)).rejects.toThrow("full");
    expect(await listNotebookDocuments(record.ownerId)).toHaveLength(200);
  });
  it("keeps approximate source timing visible and rejects oversized imports without truncating", () => {
    expect(recordingTranscriptText([{ id: "p", start: 0, end: 30, text: "An approved source", timing: "chunk" }])).toContain("approximate range");
    expect(() => recordingTranscriptText([{ id: "long", start: 0, end: 30, text: "a".repeat(60000), timing: "speech" }])).toThrow("exceeds");
  });
});
