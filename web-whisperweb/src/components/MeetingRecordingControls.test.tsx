import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { useState } from "react";
import type { MeetingRecordingSession, RecordingSessionState } from "@/lib/meetingRecordingSession";
import { MeetingRecordingControls } from "./MeetingRecordingControls";
import { MeetingActivityShell } from "./MeetingActivityShell";

const actions = { request: vi.fn(), stop: vi.fn(async () => {}), reply: vi.fn() };
const session = actions as unknown as MeetingRecordingSession;
const idle: RecordingSessionState = { request: null, remote: null, approved: 0, required: 0, update: null, notice: null };
function Controls({ state = idle, isHost = true }: { state?: RecordingSessionState; isHost?: boolean }): JSX.Element {
  const [open, setOpen] = useState<boolean>(true);
  return <MeetingRecordingControls session={session} state={state} isHost={isHost} open={open} onOpenChange={setOpen} />;
}
beforeEach(() => { vi.clearAllMocks(); vi.stubGlobal("MediaRecorder", class {}); vi.stubGlobal("AudioWorkletNode", class {}); });
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });

describe("Meet-style recording controls", () => {
  it("restores the original trigger focus when an activity closes", () => {
    function Activity(): JSX.Element {
      const [open, setOpen] = useState<boolean>(false);
      return <><button onClick={() => setOpen(true)}>Activities</button>{open && <MeetingActivityShell title="Activities" onClose={() => setOpen(false)}>Tools</MeetingActivityShell>}</>;
    }
    render(<Activity />);
    const trigger = screen.getByRole("button", { name: "Activities" });
    trigger.focus(); fireEvent.click(trigger);
    const close = screen.getByRole("button", { name: "Close activities" });
    expect(close).toHaveFocus();
    fireEvent.keyDown(close, { key: "Escape" });
    expect(screen.queryByRole("region")).not.toBeInTheDocument();
    expect(trigger).toHaveFocus();
  });
  it("uses an elevated dialog and one Start with explicit cloud defaults off", () => {
    render(<Controls />);
    const dialog = screen.getByRole("dialog", { name: "Recording" });
    expect(dialog.className).toContain("z-[101]");
    expect(screen.getByLabelText("Include video and shared screen")).toBeChecked();
    expect(screen.getByLabelText("Also transcribe with Jasper")).not.toBeChecked();
    expect(screen.getByLabelText("Request permission for private cloud backup")).not.toBeChecked();
    fireEvent.click(within(dialog).getByRole("button", { name: "Start recording" }));
    expect(actions.request).toHaveBeenCalledWith(true, false, false, true);
  });
  it("uses a non-modal activity panel with back navigation and a meeting-scoped saved link", () => {
    const onBack = vi.fn();
    render(<MeetingRecordingControls session={session} state={idle} isHost open onOpenChange={() => {}} asPanel onBack={onBack} meetingId="room-id" />);
    expect(screen.getByRole("region", { name: "Recording" })).toBeVisible();
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Record meeting" })).not.toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Open saved recordings" })).toHaveAttribute("href", "/notebook?portal=workspace&meeting=room-id");
    fireEvent.click(screen.getByRole("button", { name: "Start recording" }));
    expect(actions.request).toHaveBeenCalledWith(true, false, false, true);
    fireEvent.click(screen.getByRole("button", { name: "Back to tools" })); expect(onBack).toHaveBeenCalledOnce();
  });
  it("lets waiting hosts cancel without a second Start button", () => {
    render(<Controls state={{ ...idle, request: { requestId: crypto.randomUUID(), video: true, transcribe: false, archive: false }, required: 2, approved: 1 }} />);
    expect(screen.getByText(/Recording starts automatically/)).toBeVisible();
    expect(screen.queryByRole("button", { name: "Start recording" })).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Cancel request" }));
    expect(actions.stop).toHaveBeenCalledTimes(1);
  });
  it("confirms Stop and explicitly keeps the meeting running", () => {
    render(<Controls state={{ ...idle, update: { state: "recording", recordingId: "saved", seconds: 72, audioInputs: 2, error: null } }} />);
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Stop recording" }));
    expect(screen.getByText(/The meeting will continue/)).toBeVisible();
    expect(actions.stop).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: "Stop and save" }));
    expect(actions.stop).toHaveBeenCalledTimes(1);
  });
  it("shows saved playback only as a Notebook link, never a live player", () => {
    render(<Controls state={{ ...idle, update: { state: "ready", recordingId: "saved", seconds: 72, audioInputs: 0, error: null } }} />);
    fireEvent.click(screen.getByRole("button", { name: "Close" }));
    expect(screen.getByRole("link", { name: "Recording saved · Open" })).toHaveAttribute("href", "/notebook?portal=workspace&recording=saved");
    expect(document.querySelector("video, audio")).toBeNull();
  });
  it("explains non-host and unsupported-browser states without a dead Start action", () => {
    const view = render(<Controls isHost={false} />);
    expect(screen.getByText(/Only the signed-in meeting host/)).toBeVisible();
    expect(screen.queryByRole("button", { name: "Start recording" })).not.toBeInTheDocument();
    vi.stubGlobal("MediaRecorder", undefined); view.rerender(<Controls />);
    expect(screen.getByRole("button", { name: "Start recording" })).toBeDisabled();
    expect(screen.getByRole("alert")).toHaveTextContent("isn’t supported");
  });
  it("lets guests review and decline before capture", () => {
    render(<Controls isHost={false} state={{ ...idle, remote: { requestId: crypto.randomUUID(), peerId: "host", name: "Host", video: true, transcribe: false, archive: false, active: false, accepted: null, heardAt: Date.now() } }} />);
    expect(screen.getByRole("dialog", { name: "Host wants to record" })).toBeVisible();
    expect(screen.getByText(/Cloud transcription and AI analysis are off/)).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Decline" }));
    expect(actions.reply).toHaveBeenCalledWith(false);
  });
});
