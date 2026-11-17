// @vitest-environment node
import { describe, expect, it } from "vitest";
import { pcmWav, type RecordingChunk } from "./meetingRecordingModel";
import { recordingAudioBackup } from "./recordingAudioBackup";
const chunk = (index: number, start: number, sample: number): RecordingChunk => ({ key: `${index}`, recordingKey: "owner:id", index, kind: "audio", start, end: start + 1, transcribed: false, blob: pcmWav(new Float32Array(8000).fill(sample), 8000) });
describe("continuous recording audio backup", () => {
  it("retains source positions and silence across a missing piece", async () => {
    const blob = await recordingAudioBackup([chunk(1, 2, 0.7), chunk(0, 0, 0.2)], 4);
    const view = new DataView(await blob!.arrayBuffer());
    expect(blob!.size).toBe(44 + 4 * 8000 * 2); expect(view.getUint32(40, true)).toBe(64000);
    expect(view.getInt16(44, true)).toBeCloseTo(6553, 0); expect(view.getInt16(44 + 8000 * 2, true)).toBe(0);
    expect(view.getInt16(44 + 16000 * 2, true)).toBeGreaterThan(22000); expect(view.getInt16(44 + 24000 * 2, true)).toBe(0);
  });
  it("rejects corrupt, overlapping and mistimed audio instead of shifting transcript times", async () => {
    await expect(recordingAudioBackup([{ ...chunk(0, 0, 0), blob: new Blob(["bad"]) }], 1)).rejects.toThrow("incomplete");
    await expect(recordingAudioBackup([chunk(0, 0, 0), chunk(1, 0.5, 0)], 2)).rejects.toThrow("overlaps");
    await expect(recordingAudioBackup([{ ...chunk(0, 0, 0), end: 20 }], 20)).rejects.toThrow("timing");
  });
  it("returns no backup without source audio and respects cancellation", async () => {
    expect(await recordingAudioBackup([], 1)).toBeNull();
    await expect(recordingAudioBackup([chunk(0, 0, 0)], 1, () => { throw new Error("cancelled"); })).rejects.toThrow("cancelled");
  });
});
