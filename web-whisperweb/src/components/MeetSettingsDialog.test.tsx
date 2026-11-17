import { cleanup, render, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { MeetSettingsDialog } from "./MeetSettingsDialog";

vi.mock("@/lib/meetPrefs", () => ({ useMeetPrefs: () => [{ micId: "", camId: "", speakerId: "" }, vi.fn()] }));
const getUserMedia = vi.fn();
const close = vi.fn(async () => {});
class Context {
  close = close;
  createMediaStreamSource(): { connect: () => void } { return { connect: () => {} }; }
  createAnalyser(): { fftSize: number; frequencyBinCount: number; getByteTimeDomainData: () => void } { return { fftSize: 512, frequencyBinCount: 256, getByteTimeDomainData: () => {} }; }
}
beforeEach(() => {
  vi.clearAllMocks();
  vi.stubGlobal("AudioContext", Context);
  Object.defineProperty(navigator, "mediaDevices", { configurable: true, value: { getUserMedia, enumerateDevices: vi.fn(async () => []) } });
  vi.spyOn(HTMLMediaElement.prototype, "play").mockResolvedValue(undefined);
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });

describe("meeting device preview ownership", () => {
  it.each(["audio", "video"] as const)("the in-room %s preview borrows call media and never stops it", async (tab) => {
    const stop = vi.fn();
    const audio = { kind: "audio", enabled: true, readyState: "live", stop };
    const video = { kind: "video", enabled: true, readyState: "live", stop };
    const callStream = { getAudioTracks: () => [audio], getVideoTracks: () => [video], getTracks: () => [audio, video] } as unknown as MediaStream;
    const view = render(<MeetSettingsDialog open onClose={() => {}} context="room" initialTab={tab} callStream={callStream} />);
    await waitFor(() => expect(navigator.mediaDevices.enumerateDevices).toHaveBeenCalled());
    if (tab === "video") await waitFor(() => expect(document.querySelector("video")?.srcObject).toBe(callStream));
    view.unmount();
    expect(getUserMedia).not.toHaveBeenCalled();
    expect(stop).not.toHaveBeenCalled();
    if (tab === "audio") expect(close).toHaveBeenCalledTimes(1);
  });
  it("opening settings without a call stream never silently acquires another microphone", async () => {
    const view = render(<MeetSettingsDialog open onClose={() => {}} context="room" />);
    await waitFor(() => expect(navigator.mediaDevices.enumerateDevices).toHaveBeenCalled());
    view.unmount(); expect(getUserMedia).not.toHaveBeenCalled();
  });
});
