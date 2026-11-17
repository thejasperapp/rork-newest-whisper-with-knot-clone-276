import { listRecordings, recordingChunks } from "./meetingRecordingStorage";
import { recordingMedia } from "./recordingMedia";

/** Verifies committed slices using Notebook's own assembly and a bounded media decode probe. */
export async function verifyStoredRecording(owner: string, id: string, duration: number, expectedSlices: number): Promise<void> {
  const record = (await listRecordings(owner)).find((entry) => entry.id === id);
  if (!record || expectedSlices < 1) throw new Error("Missing saved recording");
  const chunks = await recordingChunks(owner, id);
  const media = chunks.filter((chunk) => chunk.kind === "media");
  if (media.length !== expectedSlices || media.some((chunk, index) => chunk.index !== index || !chunk.blob.size)) throw new Error("Missing recording slices");
  const blob = await recordingMedia({ ...record, duration, status: "ready" }, chunks);
  if (!blob.size) throw new Error("Empty recording");
  const url = URL.createObjectURL(blob);
  const probe = document.createElement(record.mimeType.startsWith("video/") ? "video" : "audio");
  probe.muted = true; probe.preload = "auto";
  try {
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => finish(false), 15000);
      const finish = (ok: boolean): void => { clearTimeout(timer); probe.onloadeddata = null; probe.onerror = null; if (ok) resolve(); else reject(new Error("Saved media could not be reopened")); };
      probe.onloadeddata = () => finish(probe.readyState >= 2);
      probe.onerror = () => finish(false);
      probe.src = url; probe.load();
    });
  } finally { probe.pause(); probe.removeAttribute("src"); probe.load(); URL.revokeObjectURL(url); }
}
