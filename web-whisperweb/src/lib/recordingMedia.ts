import { fixWebmDuration } from "@fix-webm-duration/fix";
import type { MeetingRecording, RecordingChunk } from "./meetingRecordingModel";

/** Repairs missing WebM duration without altering encoded frames or the saved original slices. */
export async function recordingMedia(record: MeetingRecording, chunks: RecordingChunk[]): Promise<Blob> {
  const blob = new Blob(chunks.filter((chunk) => chunk.kind === "media").sort((a, b) => a.index - b.index).map((chunk) => chunk.blob), { type: record.mimeType });
  if (!blob.size || !record.mimeType.includes("webm") || record.status === "recording") return blob;
  return fixWebmDuration(blob, record.duration * 1000, { logger: false });
}
