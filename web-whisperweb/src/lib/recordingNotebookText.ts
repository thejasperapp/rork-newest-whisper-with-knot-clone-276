import { recordingTime, type TimedPassage } from "./meetingRecordingModel";

/** Keeps approximate timing visible in the editable source; rejects rather than silently truncating. */
export function recordingTranscriptText(passages: TimedPassage[]): string {
  const text = passages.map((p) => `[${recordingTime(p.start)}–${recordingTime(p.end)}${p.timing === "chunk" ? "; approximate range" : ""}] ${p.text}`).join("\n");
  if (text.length > 60000) throw new Error("This transcript exceeds one note's limit. Export it or paste a shorter excerpt; the complete recording is retained.");
  return text;
}
