import { pcmWav, type RecordingChunk } from "./meetingRecordingModel";

/** Joins our PCM16 WAV pieces at their capture offsets, retaining silence across missing pieces. */
export async function recordingAudioBackup(chunks: RecordingChunk[], duration: number, assertCurrent: () => void = () => undefined): Promise<Blob | null> {
  const audio = chunks.filter((chunk) => chunk.kind === "audio").sort((a, b) => a.index - b.index);
  if (!audio.length) return null;
  if (!Number.isFinite(duration) || duration < 0 || duration > 7230) throw new Error("Invalid recording duration.");
  let rate = 0;
  let previousEnd = 0;
  const parts: BlobPart[] = [];
  for (const chunk of audio) {
    assertCurrent();
    const bytes = await chunk.blob.slice(0, 44).arrayBuffer(); assertCurrent();
    if (bytes.byteLength !== 44) throw new Error("A saved audio piece is incomplete. Export the remaining pieces separately.");
    const view = new DataView(bytes);
    const text = (start: number, count: number): string => String.fromCharCode(...new Uint8Array(bytes, start, count));
    const sampleRate = view.getUint32(24, true);
    const count = view.getUint32(40, true) / 2;
    if (text(0, 4) !== "RIFF" || text(8, 4) !== "WAVE" || text(12, 4) !== "fmt " || text(36, 4) !== "data" || view.getUint32(16, true) !== 16 || view.getUint16(20, true) !== 1 || view.getUint16(22, true) !== 1 || view.getUint16(34, true) !== 16 || sampleRate < 8000 || sampleRate > 96000 || (rate && rate !== sampleRate) || count * 2 + 44 !== chunk.blob.size || !Number.isInteger(count)) throw new Error("A saved audio piece has an unsupported format.");
    rate = sampleRate;
    if (!Number.isFinite(chunk.start) || !Number.isFinite(chunk.end) || chunk.start < 0 || chunk.end < chunk.start || chunk.end > 7231 || Math.abs((chunk.end - chunk.start) - count / rate) > 0.1) throw new Error("A saved audio piece has invalid timing.");
    const start = Math.round(chunk.start * rate);
    if (start < previousEnd - Math.ceil(rate * 0.02)) throw new Error("Saved audio overlaps. Export the pieces separately to preserve the originals.");
    const gap = Math.max(0, start - previousEnd);
    if (gap) parts.push(new Uint8Array(gap * 2));
    const overlap = Math.max(0, previousEnd - start);
    parts.push(chunk.blob.slice(44 + overlap * 2));
    previousEnd = Math.max(previousEnd, start + count);
  }
  const expected = Math.round(duration * rate);
  if (expected > previousEnd) { parts.push(new Uint8Array((expected - previousEnd) * 2)); previousEnd = expected; }
  const header = await pcmWav(new Float32Array(0), rate).arrayBuffer(); assertCurrent();
  const view = new DataView(header); view.setUint32(4, 36 + previousEnd * 2, true); view.setUint32(40, previousEnd * 2, true);
  return new Blob([header, ...parts], { type: "audio/wav" });
}
