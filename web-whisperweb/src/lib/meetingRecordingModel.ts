import { z } from "zod";

/** Recording time is seconds from capture start, never database arrival time. */
export const timedPassageSchema = z.object({ id: z.string().min(1).max(80), start: z.number().finite().nonnegative(), end: z.number().finite().nonnegative(), text: z.string().max(12000), timing: z.enum(["speech", "chunk"]), sourceId: z.string().max(160).optional(), speakerName: z.string().max(160).optional() }).refine((v) => v.end >= v.start);
export type TimedPassage = z.infer<typeof timedPassageSchema>;
export const recordingMarkerSchema = z.object({ id: z.string(), seconds: z.number().finite().nonnegative(), title: z.string().min(1).max(300), kind: z.enum(["decision", "bookmark"]), sourceIds: z.array(z.string()).max(8), reviewed: z.boolean() });
export type RecordingMarker = z.infer<typeof recordingMarkerSchema>;
export const meetingRecordingSchema = z.object({
  version: z.literal(1), id: z.string().uuid(), ownerId: z.string().uuid(), meetingId: z.string().nullable(), title: z.string().max(160),
  lastWriteAt: z.number().finite().nonnegative().default(0), createdAt: z.string(), duration: z.number().finite().nonnegative(), mimeType: z.string(), status: z.enum(["recording", "ready", "interrupted"]),
  storageConsent: z.boolean().default(false), cloudConsent: z.boolean().default(false), coverage: z.string().max(1000), transcript: z.array(timedPassageSchema).max(20000), markers: z.array(recordingMarkerSchema).max(300),
  transcriptionState: z.enum(['pending', 'complete', 'incomplete', 'off']).optional(),
  speakerTranscription: z.boolean().optional(),
  warnings: z.array(z.string().max(500)).max(100), revision: z.number().int().nonnegative(),
});
export type MeetingRecording = z.infer<typeof meetingRecordingSchema>;
export type RecordingChunk = { key: string; recordingKey: string; kind: "media" | "audio" | "speaker"; sourceId?: string; speakerName?: string; index: number; start: number; end: number; blob: Blob; transcribed: boolean };

/** Human-readable playback position with an hour field for long meetings. */
export function recordingTime(seconds: number): string {
  const value = Math.max(0, Math.floor(Number.isFinite(seconds) ? seconds : 0));
  const minutes = Math.floor(value / 60);
  return minutes >= 60 ? `${Math.floor(minutes / 60)}:${String(minutes % 60).padStart(2, "0")}:${String(value % 60).padStart(2, "0")}` : `${minutes}:${String(value % 60).padStart(2, "0")}`;
}

/** Reject out-of-range model times; missing timing remains an explicitly labelled chunk range. */
export function timedTranscription(raw: unknown, start: number, end: number, prefix: string): TimedPassage[] {
  const result = z.object({ text: z.string().max(12000), segments: z.array(z.object({ text: z.string().max(12000), startSecond: z.number().finite(), endSecond: z.number().finite() })).optional() }).parse(raw);
  if (!Number.isFinite(start) || !Number.isFinite(end) || start < 0 || end <= start) throw new Error("Invalid recording interval.");
  const duration = end - start;
  if (!result.segments?.length) return result.text.trim() ? [{ id: `${prefix}-0`, start, end, text: result.text.trim(), timing: "chunk" }] : [];
  return result.segments.filter((s) => s.text.trim()).map((segment, index) => {
    if (segment.startSecond < 0 || segment.endSecond < segment.startSecond || segment.startSecond > duration || segment.endSecond > duration + 1) throw new Error("The transcript timing did not match this audio. Retry transcription.");
    return { id: `${prefix}-${index}`, start: start + segment.startSecond, end: start + Math.min(duration, segment.endSecond), text: segment.text.trim(), timing: "speech" };
  });
}

/** Encodes a self-contained mono WAV; unlike MediaRecorder slices each chunk is independently decodable. */
export function pcmWav(samples: Float32Array, rate: number): Blob {
  const data = new ArrayBuffer(44 + samples.length * 2);
  const view = new DataView(data);
  const text = (offset: number, value: string): void => { for (let i = 0; i < value.length; i++) view.setUint8(offset + i, value.charCodeAt(i)); };
  text(0, "RIFF"); view.setUint32(4, 36 + samples.length * 2, true); text(8, "WAVE"); text(12, "fmt ");
  view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true); view.setUint32(24, rate, true); view.setUint32(28, rate * 2, true); view.setUint16(32, 2, true); view.setUint16(34, 16, true); text(36, "data"); view.setUint32(40, samples.length * 2, true);
  samples.forEach((sample, index) => view.setInt16(44 + index * 2, Math.max(-1, Math.min(1, Number.isFinite(sample) ? sample : 0)) * 32767, true));
  return new Blob([data], { type: "audio/wav" });
}
