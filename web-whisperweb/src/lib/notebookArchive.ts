import { supabase } from "./supabase";
import type { WhisperMeeting } from "./meetings";
import { newNotebookDocument, type NotebookDocument } from "./notebookDocument";
import { applyNotebookCloud, createNotebookDocumentIfAbsent, listNotebookDocuments } from "./notebookStorage";
import { notebookCloudSchema } from "./notebookSync";

/** Paged, read-only archive discovery. Never joins a meeting or generates new notes. */
export async function fetchNotebookArchive(owner: string, page: number, signal?: AbortSignal, includeWithoutSummary = false): Promise<{ meetings: WhisperMeeting[]; hasMore: boolean }> {
  const [hosted, joined] = await Promise.all([
    supabase.from("whisper_meetings").select("*").eq("host_id", owner).order("created_at", { ascending: false }).order("id").range(page * 30, page * 30 + 29).abortSignal(signal ?? new AbortController().signal),
    supabase.from("whisper_meeting_participants").select("meeting_id").eq("user_id", owner).order("joined_at", { ascending: false }).order("meeting_id").range(page * 30, page * 30 + 29).abortSignal(signal ?? new AbortController().signal),
  ]);
  if (hosted.error || joined.error) throw new Error("Couldn't load your notes archive. Please retry.");
  const rows = [...((hosted.data ?? []) as WhisperMeeting[])];
  const ids = ((joined.data ?? []) as { meeting_id: string }[]).map((row) => row.meeting_id).filter((id) => !rows.some((row) => row.id === id));
  if (ids.length) {
    const extra = await supabase.from("whisper_meetings").select("*").in("id", ids).abortSignal(signal ?? new AbortController().signal);
    if (extra.error) throw new Error("Couldn't load all your meeting notes. Please retry.");
    rows.push(...((extra.data ?? []) as WhisperMeeting[]));
  }
  return { meetings: rows.filter((row) => includeWithoutSummary || !!row.summary?.trim()), hasMore: hosted.data?.length === 30 || joined.data?.length === 30 };
}

/** Restores an existing private copy or tombstone before creating an archive note on a new device. */
export async function restoreArchivedNotebookCopy(owner: string, id: string, check: () => void): Promise<void> {
  check();
  const { data, error } = await supabase.from("whisper_private_notebooks").select("*").eq("owner_id", owner).eq("id", id).maybeSingle();
  check();
  if (error) throw new Error("Couldn't check for an existing private copy. Retry when connected; nothing was replaced.");
  if (data) {
    const row = notebookCloudSchema.parse(data);
    if (row.owner_id !== owner || row.id !== id) throw new Error("Couldn't verify this private note.");
    const local = await listNotebookDocuments(owner, true); check();
    if (!local.some((note) => note.id === id)) await applyNotebookCloud(row, check);
  }
}

/** The meeting UUID identifies its private recap copy. Repeat use never replaces writing or a deletion. */
export async function importArchivedMeetingNote(owner: string, meeting: Pick<WhisperMeeting, "id" | "title" | "summary" | "ended_at" | "created_at">, recordingIds: string[], check: () => void, restore = restoreArchivedNotebookCopy): Promise<NotebookDocument> {
  check();
  const id = meeting.id.toLowerCase();
  const existing = (await listNotebookDocuments(owner, true)).find((note) => note.id === id); check();
  if (!existing) await restore(owner, id, check);
  check();
  const known = (await listNotebookDocuments(owner, true)).find((note) => note.id === id); check();
  if (known?.deletedAt) throw new Error("Your private copy was deleted. The archived meeting note and recordings are still available; create a separate note to keep new writing.");
  if (known) {
    if (known.meetingId !== meeting.id) throw new Error("This note identity is already in use. Your writing was kept.");
    return known;
  }
  if (!meeting.summary?.trim()) throw new Error("This meeting doesn't have generated notes yet.");
  if (meeting.summary.length > 60000) throw new Error("This recap exceeds the note limit. Copy smaller sections into separate notes; nothing was truncated.");
  const note = newNotebookDocument(owner, meeting.id, meeting.title);
  note.id = id; note.notes = meeting.summary; note.revision = 1;
  note.createdAt = meeting.ended_at ?? meeting.created_at ?? note.createdAt;
  note.recapCopiedAt = new Date().toISOString(); note.recordingIds = [...new Set(recordingIds)];
  if (note.recordingIds.length > 30) throw new Error("Attach up to 30 recordings to a note.");
  return createNotebookDocumentIfAbsent(note, check, "meeting");
}
