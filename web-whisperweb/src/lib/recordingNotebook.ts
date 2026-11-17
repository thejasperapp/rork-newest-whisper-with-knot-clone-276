import { newNotebookDocument, type NotebookDocument } from "./notebookDocument";
import { createNotebookDocumentIfAbsent } from "./notebookStorage";
import type { MeetingRecording } from "./meetingRecordingModel";

/** One reusable private note per recording UUID, on both clients. Existing words are never imported over. */
export async function ensureRecordingNote(record: Pick<MeetingRecording, "id" | "ownerId" | "meetingId" | "title" | "createdAt" | "status">, assertCurrent: () => void): Promise<NotebookDocument> {
  assertCurrent();
  if (record.status === "recording") throw new Error("Stop and save the recording before writing its note.");
  const note = newNotebookDocument(record.ownerId, record.meetingId, record.title);
  // Recording UUIDs provide a stable cross-device identity without new JSON fields older clients could erase.
  note.id = record.id;
  note.createdAt = record.createdAt;
  return createNotebookDocumentIfAbsent(note, assertCurrent);
}

/** Local finalization belongs to the captured owner even after sign-out; never retargets the active account or syncs. */
export async function attachFinalizedRecordingNote(record: Parameters<typeof ensureRecordingNote>[0]): Promise<void> {
  let active = true;
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    await Promise.race([
      ensureRecordingNote(record, () => { if (!active) throw new Error("Notebook attachment timed out."); }),
      new Promise<never>((_, reject) => { timer = setTimeout(() => { active = false; reject(new Error("Notebook attachment timed out.")); }, 3000); }),
    ]);
  } finally { active = false; if (timer) clearTimeout(timer); }
}
