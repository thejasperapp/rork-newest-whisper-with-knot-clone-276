import { meetingRecordingSchema, type MeetingRecording, type RecordingChunk, type TimedPassage } from "./meetingRecordingModel";

let database: Promise<IDBDatabase> | null = null;
const readIssues = new Map<string, number>();
export function recordingReadIssues(owner: string): number { return readIssues.get(owner) ?? 0; }
function open(): Promise<IDBDatabase> {
  if (!database) database = new Promise<IDBDatabase>((resolve, reject) => {
    const request = indexedDB.open("whisper-recordings-v1", 1);
    request.onupgradeneeded = () => {
      request.result.createObjectStore("recordings", { keyPath: "key" }).createIndex("ownerId", "ownerId");
      request.result.createObjectStore("chunks", { keyPath: "key" }).createIndex("recordingKey", "recordingKey");
    };
    request.onsuccess = () => { request.result.onversionchange = () => { request.result.close(); database = null; }; resolve(request.result); };
    request.onerror = request.onblocked = () => reject(new Error("Recording storage could not open. Use a regular browser window with available storage."));
  }).catch((error: unknown) => { database = null; throw error; });
  return database;
}
function complete(transaction: IDBTransaction): Promise<void> {
  return new Promise((resolve, reject) => { transaction.oncomplete = () => resolve(); transaction.onerror = transaction.onabort = () => reject(new Error("Recording could not be saved. Storage may be full. Earlier saved parts are retained.")); });
}
/** Reserve an immutable recording identity before any media is captured. */
export async function createRecording(recording: MeetingRecording): Promise<void> {
  const db = await open(); const tx = db.transaction("recordings", "readwrite");
  tx.objectStore("recordings").add({ key: `${recording.ownerId}:${recording.id}`, ownerId: recording.ownerId, recording: meetingRecordingSchema.parse(recording) });
  await complete(tx);
}
/** Atomic edits preserve concurrently arriving transcript and capture updates, without resurrecting deletion. */
export async function editRecording(ownerId: string, id: string, edit: (current: MeetingRecording) => MeetingRecording): Promise<void> {
  const db = await open(); const tx = db.transaction("recordings", "readwrite"); const store = tx.objectStore("recordings");
  const request = store.get(`${ownerId}:${id}`);
  request.onsuccess = () => {
    try { if (!request.result) { tx.abort(); return; } const next = meetingRecordingSchema.parse(edit(request.result.recording)); if (next.id !== id || next.ownerId !== ownerId) { tx.abort(); return; } store.put({ ...request.result, recording: { ...next, revision: next.revision + 1 } }); } catch { tx.abort(); }
  };
  await complete(tx);
}
/** Persist chunks incrementally; a closed tab cannot lose an entire meeting held only in memory. */
export async function saveRecordingChunk(ownerId: string, id: string, chunk: Omit<RecordingChunk, "key" | "recordingKey">): Promise<RecordingChunk> {
  if (!Number.isInteger(chunk.index) || chunk.index < 0 || !Number.isFinite(chunk.start) || !Number.isFinite(chunk.end) || chunk.start < 0 || chunk.end < chunk.start || !(chunk.blob instanceof Blob) || !["media", "audio", "speaker"].includes(chunk.kind)) throw new Error("Invalid recording chunk.");
  const db = await open(); const tx = db.transaction(["recordings", "chunks"], "readwrite"); const recordingKey = `${ownerId}:${id}`;
  const value: RecordingChunk = { ...chunk, recordingKey, key: `${recordingKey}:${chunk.kind}:${chunk.index}` };
  const request = tx.objectStore("recordings").get(recordingKey);
  request.onsuccess = () => { if (!request.result || request.result.recording.status !== "recording") { tx.abort(); return; } tx.objectStore("chunks").add(value); const row = request.result; tx.objectStore("recordings").put({ ...row, recording: { ...row.recording, revision: row.recording.revision + 1, lastWriteAt: Date.now(), duration: Math.max(row.recording.duration, chunk.end) } }); };
  await complete(tx); return value;
}
/** Read only the selected account; browser storage is not encryption or cloud sync. */
export async function listRecordings(ownerId: string): Promise<MeetingRecording[]> {
  const db = await open(); return new Promise((resolve, reject) => {
    const req = db.transaction("recordings").objectStore("recordings").index("ownerId").getAll(ownerId);
    req.onsuccess = () => {
      const rows = req.result as { recording: unknown }[];
      const valid = rows.flatMap((row) => { const parsed = meetingRecordingSchema.safeParse(row.recording); return parsed.success && parsed.data.ownerId === ownerId ? [parsed.data] : []; });
      readIssues.set(ownerId, rows.length - valid.length);
      resolve(valid.sort((a, b) => b.createdAt.localeCompare(a.createdAt)));
    };
    req.onerror = () => reject(new Error("Couldn't load recordings."));
  });
}
/** Chunks are retained in their original order, including the first container header. */
export async function recordingChunks(ownerId: string, id: string): Promise<RecordingChunk[]> {
  const db = await open(); return new Promise((resolve, reject) => { const req = db.transaction("chunks").objectStore("chunks").index("recordingKey").getAll(`${ownerId}:${id}`); req.onsuccess = () => resolve((req.result as RecordingChunk[]).sort((a, b) => a.index - b.index)); req.onerror = () => reject(new Error("Couldn't open the saved media.")); });
}
/** Read one persisted piece on demand so queued transcription never retains an entire call in RAM. */
export async function loadRecordingChunk(key: string): Promise<RecordingChunk> {
  const db = await open();
  return new Promise((resolve, reject) => { const request = db.transaction('chunks').objectStore('chunks').get(key); request.onsuccess = () => request.result ? resolve(request.result as RecordingChunk) : reject(new Error('Recording audio is no longer available.')); request.onerror = () => reject(new Error('Could not read recording audio.')); });
}

/** Commit timing and its processed flag together so retries cannot duplicate a transcript. */
export async function saveRecordingTranscript(chunk: RecordingChunk, passages: TimedPassage[], assertCurrent: () => void = () => undefined): Promise<void> {
  assertCurrent(); const db = await open(); assertCurrent(); const tx = db.transaction(["recordings", "chunks"], "readwrite"); const records = tx.objectStore("recordings"); const chunks = tx.objectStore("chunks");
  const req = records.get(chunk.recordingKey);
  req.onsuccess = () => { if (!req.result) { tx.abort(); return; } const record = req.result; const read = chunks.get(chunk.key); read.onsuccess = () => { if (!read.result) { tx.abort(); return; } if (read.result.transcribed) return; try { assertCurrent(); if (!record.recording.cloudConsent || !["audio", "speaker"].includes(read.result.kind) || read.result.recordingKey !== chunk.recordingKey || passages.some((p) => p.start < read.result.start || p.end > read.result.end + 0.01)) { tx.abort(); return; } const next = meetingRecordingSchema.parse({ ...record.recording, transcript: [...record.recording.transcript, ...passages].sort((a, b) => a.start - b.start), revision: record.recording.revision + 1 }); records.put({ ...record, recording: next }); chunks.put({ ...read.result, transcribed: true }); } catch { tx.abort(); } }; };
  await complete(tx);
}
/** Explicit deletion removes media, transcript and markers in one transaction. */
export async function deleteRecording(ownerId: string, id: string, assertCurrent: () => void = () => undefined): Promise<void> {
  assertCurrent(); const db = await open(); assertCurrent(); const tx = db.transaction(["recordings", "chunks"], "readwrite"); const key = `${ownerId}:${id}`;
  tx.objectStore("recordings").delete(key);
  const request = tx.objectStore("chunks").index("recordingKey").openCursor(key);
  request.onsuccess = () => { try { assertCurrent(); const cursor = request.result; if (cursor) { cursor.delete(); cursor.continue(); } } catch { tx.abort(); } };
  await complete(tx);
}
