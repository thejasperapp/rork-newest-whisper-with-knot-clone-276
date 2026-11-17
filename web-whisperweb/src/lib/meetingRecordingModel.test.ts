import { describe, expect, it, vi } from "vitest";
vi.mock("./notebookIntelligence", () => ({ runNotebookIntelligence: vi.fn() }));
import { pcmWav, recordingTime, timedTranscription } from "./meetingRecordingModel";
import { recordingEvidence } from "./recordingIntelligence";

describe("recording-relative transcript evidence", () => {
  it("offsets speech times by the audio chunk start, not meeting/database time", () => { expect(timedTranscription({ text: "Agreed", segments: [{ text: "Agreed", startSecond: 2.5, endSecond: 4 }] }, 60, 90, "A2")).toEqual([{ id: "A2-0", text: "Agreed", start: 62.5, end: 64, timing: "speech" }]); });
  it("labels text-only responses as approximate chunk ranges", () => { expect(timedTranscription({ text: "Proceed" }, 30, 60, "A1")[0]).toMatchObject({ start: 30, end: 60, timing: "chunk" }); });
  it.each([-1, 31, Number.NaN])("rejects model times outside the captured audio (%s)", (startSecond) => { expect(() => timedTranscription({ text: "Bad", segments: [{ text: "Bad", startSecond, endSecond: 40 }] }, 30, 60, "A1")).toThrow(); });
  it("never creates evidence from empty text", () => { expect(timedTranscription({ text: " " }, 0, 30, "A0")).toEqual([]); });
  it("rejects invalid capture intervals and oversized text without truncation", () => { expect(() => timedTranscription({ text: "Hi" }, 30, 10, "A1")).toThrow(); expect(() => timedTranscription({ text: "a".repeat(12001) }, 0, 30, "A0")).toThrow(); });
  it("formats long recordings and invalid display input", () => { expect(recordingTime(3661.9)).toBe("1:01:01"); expect(recordingTime(-1)).toBe("0:00"); expect(recordingTime(Number.NaN)).toBe("0:00"); });
  it("writes independently decodable WAV pieces", () => { const blob = pcmWav(new Float32Array([0, 1, -1, Number.NaN]), 24000); expect(blob.type).toBe("audio/wav"); expect(blob.size).toBe(52); });
  it("maps split and multiline source citations back to the original recording passage", () => { const original = { id: "A4-1", start: 122, end: 129, text: "a".repeat(1205) + "\nDecision", timing: "speech" as const }; const evidence = recordingEvidence([original, { ...original, id: "A5-0", start: 150, end: 180, text: "Approved" }]); expect(evidence.positions.get("T1")).toBe(original); expect(evidence.positions.get("T2")).toBe(original); expect(evidence.positions.get("T3")?.start).toBe(150); expect(evidence.transcript.split("\n")).toHaveLength(3); });
  it("rejects an oversized evidence window instead of silently omitting passages", () => { expect(() => recordingEvidence([{ id: "A0", start: 0, end: 30, timing: "chunk", text: "a".repeat(25000) }])).toThrow("24,000"); });
});
