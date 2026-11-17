import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
const mocks = vi.hoisted(() => ({ list: vi.fn(), chunks: vi.fn(), assemble: vi.fn() }));
vi.mock("./meetingRecordingStorage", () => ({ listRecordings: mocks.list, recordingChunks: mocks.chunks }));
vi.mock("./recordingMedia", () => ({ recordingMedia: mocks.assemble }));
import { verifyStoredRecording } from "./verifyStoredRecording";
let probe: HTMLMediaElement;
beforeEach(() => {
  vi.clearAllMocks(); vi.useFakeTimers(); mocks.list.mockResolvedValue([{ id: "recording", mimeType: "audio/webm" }]);
  mocks.chunks.mockResolvedValue([{ kind: "media", index: 0, blob: new Blob(["bytes"]) }]); mocks.assemble.mockResolvedValue(new Blob(["media"]));
  probe = document.createElement("audio");
  vi.spyOn(document, "createElement").mockReturnValue(probe);
  vi.spyOn(probe, "load").mockImplementation(() => {}); vi.spyOn(probe, "pause").mockImplementation(() => {});
  vi.stubGlobal("URL", { createObjectURL: vi.fn(() => "blob:probe"), revokeObjectURL: vi.fn() });
});
afterEach(() => { vi.useRealTimers(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });
describe("reopening committed recording media", () => {
  it("requires actual decoded data and releases the object URL", async () => {
    const result = verifyStoredRecording("owner", "recording", 2, 1);
    await vi.advanceTimersByTimeAsync(0);
    Object.defineProperty(probe, "readyState", { value: 2 }); probe.dispatchEvent(new Event("loadeddata"));
    await result; expect(URL.revokeObjectURL).toHaveBeenCalledWith("blob:probe"); expect(probe.hasAttribute("src")).toBe(false);
  });
  it("rejects missing or empty slices before starting a probe", async () => {
    mocks.chunks.mockResolvedValue([{ kind: "media", index: 1, blob: new Blob(["bytes"]) }]);
    await expect(verifyStoredRecording("owner", "recording", 2, 1)).rejects.toThrow("slices");
    expect(mocks.assemble).not.toHaveBeenCalled();
  });
  it("rejects decode errors without declaring Saved", async () => {
    const result = expect(verifyStoredRecording("owner", "recording", 2, 1)).rejects.toThrow("reopened");
    await vi.advanceTimersByTimeAsync(0); probe.dispatchEvent(new Event("error"));
    await result; expect(URL.revokeObjectURL).toHaveBeenCalledWith("blob:probe");
  });
  it("times out and clears handlers for unreadable media", async () => {
    const result = expect(verifyStoredRecording("owner", "recording", 2, 1)).rejects.toThrow("reopened");
    await vi.advanceTimersByTimeAsync(15001); await result;
    expect(probe.onloadeddata).toBeNull(); expect(probe.onerror).toBeNull();
  });
});
