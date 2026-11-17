import { z } from "zod";
import { Upload } from "tus-js-client";
import { supabase, supabaseUrl } from "./supabase";
import { meetingRecordingSchema, type MeetingRecording } from "./meetingRecordingModel";
import { recordingChunks } from "./meetingRecordingStorage";
import { recordingAudioBackup } from "./recordingAudioBackup";
import { recordingMedia } from "./recordingMedia";

export const RECORDING_BUCKET = "whisper-private-recordings";
const TABLE = "whisper_recording_archives";
export const recordingArchiveSchema = z.object({ id: z.string().uuid(), owner_id: z.string().uuid(), recording_id: z.string().uuid(), source_revision: z.number().int().nonnegative(), snapshot: meetingRecordingSchema, media_bytes: z.number().int().positive().max(471859200), audio_bytes: z.number().int().min(44).max(471859200), state: z.enum(["uploading", "ready", "deleting"]), created_at: z.string() }).refine((row) => row.snapshot.ownerId === row.owner_id && row.snapshot.id === row.recording_id && row.snapshot.revision === row.source_revision && row.snapshot.storageConsent && row.snapshot.status !== "recording");
export type RecordingArchive = z.infer<typeof recordingArchiveSchema>;

/** A cloud operation is permanently invalidated by switching away, even if the same account returns. */
async function withOwner<T>(owner: string, signal: AbortSignal, assertCurrent: () => void, work: (check: () => void, signal: AbortSignal) => Promise<T>): Promise<T> {
  const abort = new AbortController();
  const cancel = (): void => abort.abort(); signal.addEventListener("abort", cancel, { once: true }); if (signal.aborted) cancel();
  const subscription = supabase.auth.onAuthStateChange((_event, session) => { if (session?.user.id !== owner) cancel(); });
  const check = (): void => { assertCurrent(); abort.signal.throwIfAborted(); };
  try { check(); const session = await supabase.auth.getSession(); check(); if (session.data.session?.user.id !== owner) throw new Error("Sign in to the recording’s account to continue."); const result = await work(check, abort.signal); check(); return result; }
  finally { signal.removeEventListener("abort", cancel); subscription.data.subscription.unsubscribe(); }
}

/** Paginated owner-only snapshots; no legacy recap or meeting membership lookup. */
export async function listRecordingArchives(owner: string, signal: AbortSignal, before?: string, meetingId?: string | null, recordingId?: string): Promise<RecordingArchive[]> {
  return (await listRecordingArchivePage(owner, signal, before, meetingId, recordingId)).items;
}

/** Cursor is based on raw rows, including incompatible metadata, so older media stays reachable. */
export async function listRecordingArchivePage(owner: string, signal: AbortSignal, before?: string, meetingId?: string | null, recordingId?: string): Promise<{ items: RecordingArchive[]; nextCursor?: string; issues: number }> {
  return withOwner(owner, signal, () => undefined, async (check, guarded) => {
    let request = supabase.from(TABLE).select("*").eq("owner_id", owner).order("created_at", { ascending: false }).order("id", { ascending: false }).limit(30);
    if (meetingId) request = request.eq("snapshot->>meetingId", meetingId);
    if (recordingId) request = request.eq("recording_id", recordingId);
    if (before) {
      const [time, id] = before.split("|");
      if (!/^\d{4}-\d\d-\d\dT[\d:.+Z-]+$/.test(time) || (id && !z.string().uuid().safeParse(id).success)) throw new Error("Refresh the recording list to continue.");
      request = id ? request.or(`created_at.lt.${time},and(created_at.eq.${time},id.lt.${id})`) : request.lt("created_at", time);
    }
    const { data, error } = await request.abortSignal(guarded); check();
    if (error) throw new Error("Couldn’t open private cloud recordings. Check your connection and try again.");
    const rows = data ?? [];
    const items = rows.flatMap((row) => { const parsed = recordingArchiveSchema.safeParse(row); return parsed.success && parsed.data.owner_id === owner && (!meetingId || parsed.data.snapshot.meetingId === meetingId) && (!recordingId || parsed.data.recording_id === recordingId) ? [parsed.data] : []; });
    const last = rows[rows.length - 1];
    return { items, nextCursor: rows.length === 30 && last ? `${last.created_at}|${last.id}` : undefined, issues: rows.length - items.length };
  });
}

async function uploadObject(owner: string, path: string, blob: Blob, check: () => void, signal: AbortSignal, progress: (fraction: number) => void): Promise<void> {
  const split = path.lastIndexOf("/");
  const existing = await supabase.storage.from(RECORDING_BUCKET).list(path.slice(0, split), { limit: 10 }); check();
  if (existing.error) throw new Error("Couldn’t check saved upload pieces. Try again; local media is retained.");
  const found = existing.data.find((item) => item.name === path.slice(split + 1));
  if (found) { if (Number(found.metadata?.size) !== blob.size) throw new Error("A cloud file has a different size. Delete that incomplete backup before retrying."); progress(1); return; }
  await new Promise<void>((resolve, reject) => {
    let settled = false;
    const finish = (error?: Error): void => { if (settled) return; settled = true; signal.removeEventListener("abort", cancel); if (error) reject(error); else resolve(); };
    const upload = new Upload(blob, {
      endpoint: `${supabaseUrl}/storage/v1/upload/resumable`, chunkSize: 6 * 1024 * 1024,
      retryDelays: [0, 3000, 5000, 10000], uploadDataDuringCreation: true, removeFingerprintOnSuccess: true,
      fingerprint: async () => `whisper-recording:${owner}:${path}:${blob.size}`,
      metadata: { bucketName: RECORDING_BUCKET, objectName: path, contentType: blob.type.split(";")[0], cacheControl: "0" },
      onBeforeRequest: async (request) => { check(); const { data } = await supabase.auth.getSession(); check(); if (data.session?.user.id !== owner) throw new Error("Recording account changed."); request.setHeader("Authorization", `Bearer ${data.session.access_token}`); const xhr = request.getUnderlyingObject() as XMLHttpRequest; xhr.timeout = 60000; xhr.ontimeout = () => xhr.dispatchEvent(new ProgressEvent("error")); },
      onShouldRetry: (error) => !signal.aborted && (!error.originalResponse || error.originalResponse.getStatus() >= 500 || error.originalResponse.getStatus() === 429 || error.originalResponse.getStatus() === 409 || error.originalResponse.getStatus() === 423 || error.originalResponse.getStatus() === 0),
      onProgress: (sent, total) => { if (!signal.aborted) progress(total ? sent / total : 0); },
      onError: () => finish(new Error("Cloud backup paused. Your local recording is safe. Retry to resume, or delete the incomplete cloud backup. The server’s storage limit may also apply.")),
      onSuccess: () => { try { check(); finish(); } catch { finish(new Error("Cloud backup stopped because this account or screen changed.")); } },
    });
    const cancel = (): void => { void upload.abort(false).catch(() => undefined); finish(new Error("Upload stopped. Local recording is retained; the incomplete cloud backup can be resumed or deleted.")); };
    signal.addEventListener("abort", cancel, { once: true });
    void (async () => { check(); const previous = await upload.findPreviousUploads(); check(); if (previous[0]) upload.resumeFromPreviousUpload(previous[0]); upload.start(); })().catch(() => { void upload.abort(false).catch(() => undefined); finish(new Error("Couldn’t start this upload. Local media is retained.")); });
    if (signal.aborted) cancel();
  });
}

/** An explicit snapshot backup, not automatic sync. Old recordings never inherit archive permission. */
export async function backupRecording(record: MeetingRecording, signal: AbortSignal, assertCurrent: () => void, progress: (fraction: number) => void): Promise<RecordingArchive> {
  if (record.transcriptionState === 'pending') throw new Error('The recording transcript is still finishing. Keep this tab open, then save the complete snapshot.');
  if (!record.storageConsent || record.status === "recording") throw new Error("Private cloud backup was not included in this recording’s permission, or capture is still active.");
  return withOwner(record.ownerId, signal, assertCurrent, async (check, guarded) => {
    const chunks = await recordingChunks(record.ownerId, record.id); check();
    if (!chunks.length) throw new Error("The original recording pieces are not on this browser. Resume from the browser where you recorded.");
    const media = await recordingMedia(record, chunks); check(); const audio = await recordingAudioBackup(chunks, record.duration, check); check();
    if (!media.size || !audio || media.size > 471859200 || audio.size > 471859200) throw new Error("This recording does not have both supported backup files. Export its saved pieces instead.");
    if (new Blob([JSON.stringify(record)]).size > 2900000) throw new Error("This transcript is too large for a cloud snapshot. Export a backup instead.");
    const previous = await supabase.from(TABLE).select("*").eq("owner_id", record.ownerId).eq("recording_id", record.id).eq("source_revision", record.revision).abortSignal(guarded).maybeSingle(); check();
    if (previous.error) throw new Error("Couldn’t check existing backups. Nothing local was removed.");
    let archive: RecordingArchive;
    if (previous.data) archive = recordingArchiveSchema.parse(previous.data);
    else {
      const created = await supabase.from(TABLE).insert({ owner_id: record.ownerId, recording_id: record.id, source_revision: record.revision, snapshot: record, media_bytes: media.size, audio_bytes: audio.size }).select("*").abortSignal(guarded).single(); check();
      if (created.error) throw new Error("Couldn’t reserve a private backup. Refresh Cloud recordings before retrying; another tab may have started it.");
      archive = recordingArchiveSchema.parse(created.data);
    }
    if (archive.state === "ready") return archive;
    if (archive.state === "deleting") throw new Error("Finish deleting the previous backup before uploading again.");
    if (archive.media_bytes !== media.size || archive.audio_bytes !== audio.size) throw new Error("The backup does not match the saved files. Delete the incomplete cloud copy before retrying.");
    const prefix = `${record.ownerId}/${archive.id}`;
    await uploadObject(record.ownerId, `${prefix}/original`, media, check, guarded, (part) => progress(part * media.size / (media.size + audio.size)));
    check(); await uploadObject(record.ownerId, `${prefix}/audio.wav`, audio, check, guarded, (part) => progress((media.size + part * audio.size) / (media.size + audio.size)));
    check(); const finalized = await supabase.from(TABLE).update({ state: "ready" }).eq("owner_id", record.ownerId).eq("id", archive.id).eq("state", "uploading").select("*").abortSignal(guarded).single(); check();
    if (finalized.error) throw new Error("Upload finished but the backup isn’t confirmed yet. Refresh Cloud recordings or retry finalization; keep your local copy.");
    return recordingArchiveSchema.parse(finalized.data);
  });
}

/** Temporary playback credentials are created only after checking current owner and ready state. */
export async function recordingPlaybackURL(archive: RecordingArchive, audioOnly: boolean, signal: AbortSignal): Promise<string> {
  return withOwner(archive.owner_id, signal, () => undefined, async (check, guarded) => {
    const current = await supabase.from(TABLE).select("id").eq("id", archive.id).eq("owner_id", archive.owner_id).eq("state", "ready").abortSignal(guarded).single(); check();
    if (current.error) throw new Error("This backup is not ready or has been removed.");
    const signed = await supabase.storage.from(RECORDING_BUCKET).createSignedUrl(`${archive.owner_id}/${archive.id}/${audioOnly ? "audio.wav" : "original"}`, 10800); check();
    if (signed.error) throw new Error("Couldn’t open private playback. Reopen the recording to try again.");
    return signed.data.signedUrl;
  });
}

/** Local copies and downloaded files are unaffected. Failed removal stays visible and retryable. */
export async function deleteRecordingArchive(archive: RecordingArchive, signal: AbortSignal, assertCurrent: () => void): Promise<void> {
  return withOwner(archive.owner_id, signal, assertCurrent, async (check, guarded) => {
    const marked = await supabase.from(TABLE).update({ state: "deleting" }).eq("id", archive.id).eq("owner_id", archive.owner_id).select("id").abortSignal(guarded).single(); check();
    if (marked.error) throw new Error("Couldn’t start cloud deletion. Refresh the list and try again.");
    const prefix = `${archive.owner_id}/${archive.id}`;
    const removed = await supabase.storage.from(RECORDING_BUCKET).remove([`${prefix}/original`, `${prefix}/audio.wav`]); check();
    if (removed.error) throw new Error("Cloud deletion is incomplete. Try Delete again to remove remaining media.");
    const deleted = await supabase.from(TABLE).delete().eq("id", archive.id).eq("owner_id", archive.owner_id).eq("state", "deleting").select("id").abortSignal(guarded).single(); check();
    if (deleted.error) throw new Error("Media was removed, but its archive entry still needs cleanup. Refresh and retry Delete.");
  });
}
