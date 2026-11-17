import { supabase } from "./supabase";
import { JASPER_MEETINGS_URL } from './jasperMeetings';
import { timedTranscription, type RecordingChunk } from "./meetingRecordingModel";
import { transcriptionFailure } from './meetingTranscription';
import { recordingChunks, saveRecordingTranscript, editRecording, listRecordings } from "./meetingRecordingStorage";

/** Verified deployed endpoint, separate from the historical billing failover hosts. */
export const RECORDING_BACKEND = JASPER_MEETINGS_URL;

/** Transcribes a saved WAV, invalidating switch-away-and-back and cancellation through the transaction boundary. */
export async function transcribeRecordingChunk(ownerId: string, chunk: RecordingChunk, signal: AbortSignal, assertCurrent: () => void = () => undefined): Promise<void> {
  const abort = new AbortController();
  const cancel = (): void => abort.abort();
  signal.addEventListener("abort", cancel, { once: true }); if (signal.aborted) cancel();
  const subscription = supabase.auth.onAuthStateChange((_event, session) => { if (session?.user.id !== ownerId) cancel(); });
  const current = (): void => { assertCurrent(); abort.signal.throwIfAborted(); };
  try {
    current();
    if (!chunk.recordingKey.startsWith(`${ownerId}:`) || !['audio', 'speaker'].includes(chunk.kind) || chunk.blob.size > 6_000_000) throw new Error("Invalid recording audio.");
    const { data } = await supabase.auth.getSession(); current();
    if (!data.session || data.session.user.id !== ownerId) throw new Error("Sign in to the recording’s account to transcribe it.");
    const bytes = new Uint8Array(await chunk.blob.arrayBuffer()); current(); let binary = "";
    for (let i = 0; i < bytes.length; i += 8192) binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
    const response = await fetch(`${RECORDING_BACKEND}/notebook/transcribe`, { method: "POST", signal: AbortSignal.any([abort.signal, AbortSignal.timeout(50000)]), headers: { Authorization: `Bearer ${data.session.access_token}`, 'X-Whisper-Authorization': `Bearer ${data.session.access_token}`, "Content-Type": "application/json" }, body: JSON.stringify({ audio: btoa(binary), mediaType: chunk.blob.type }) });
    current(); if (!response.ok) throw transcriptionFailure(response.status);
    const result: unknown = await response.json(); current();
    const live = await supabase.auth.getSession(); current();
    if (live.data.session?.user.id !== ownerId) throw new Error("Recording session changed.");
    await saveRecordingTranscript(chunk, timedTranscription(result, chunk.start, chunk.end, `${chunk.kind === 'speaker' ? 'S' : 'A'}${chunk.index}`).map((passage) => ({ ...passage, ...(chunk.sourceId ? { sourceId: chunk.sourceId, speakerName: chunk.speakerName } : {}) })), current);
  } finally { signal.removeEventListener("abort", cancel); subscription.data.subscription.unsubscribe(); }
}

/** Only unprocessed pieces are retried; successful passages and flags commit atomically. */
export async function retryRecordingTranscription(ownerId: string, id: string, signal: AbortSignal, assertCurrent: () => void = () => undefined): Promise<void> {
  assertCurrent(); const chunks = await recordingChunks(ownerId, id); assertCurrent();
  const recording = (await listRecordings(ownerId)).find((row) => row.id === id); assertCurrent();
  for (const chunk of chunks) if (chunk.kind === (recording?.speakerTranscription ? 'speaker' : 'audio') && !chunk.transcribed) { signal.throwIfAborted(); assertCurrent(); await transcribeRecordingChunk(ownerId, chunk, signal, assertCurrent); }
  signal.throwIfAborted(); assertCurrent();
  await editRecording(ownerId, id, (row) => ({ ...row, transcriptionState: 'complete' }));
}
