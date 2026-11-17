import { act, renderHook } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { MeetingHostProvider, useMeetingHost, type MeetingSaveStatus } from "./useMeetingHost";
const status = (state: MeetingSaveStatus["update"]["state"]): MeetingSaveStatus => ({ ownerId: "owner", meetingId: "meeting-a", inCall: true, update: { state, recordingId: "recording", seconds: 1, audioInputs: 1, error: null } });
describe("recording-safe meeting host", () => {
  it("blocks replacement and close synchronously, before React publishes the status", () => {
    const { result } = renderHook(useMeetingHost, { wrapper: MeetingHostProvider });
    act(() => { expect(result.current.open("meeting-a")).toBe(true); });
    act(() => {
      result.current.setRecordingStatus(status("saving"));
      expect(result.current.open("meeting-b")).toBe(false);
      expect(result.current.close()).toBe(false);
    });
    expect(result.current.active?.id).toBe("meeting-a");
    act(() => { result.current.setRecordingStatus(status("ready")); expect(result.current.close()).toBe(true); });
    expect(result.current.active).toBeNull();
  });
  it("retains status on same-room restore and ignores departed-room callbacks", () => {
    const { result } = renderHook(useMeetingHost, { wrapper: MeetingHostProvider });
    act(() => { result.current.open("meeting-a"); result.current.setRecordingStatus(status("ready")); });
    act(() => { result.current.open("meeting-a"); }); expect(result.current.recordingStatus?.update.state).toBe("ready");
    act(() => { result.current.open("meeting-b"); result.current.setRecordingStatus(status("error")); });
    expect(result.current.recordingStatus).toBeNull(); expect(result.current.active?.id).toBe("meeting-b");
  });
});
