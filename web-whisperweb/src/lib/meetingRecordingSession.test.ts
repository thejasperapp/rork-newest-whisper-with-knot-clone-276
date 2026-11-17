import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { RecorderUpdate } from "./meetingRecorder";
import type { LiveParticipantInfo, WhisperLiveRTC } from "./whisperLiveRTC";
const captures = vi.hoisted(() => ({ starts: vi.fn(), stops: vi.fn(), updates: vi.fn(), finish: null as ((update: RecorderUpdate) => void) | null, cloudResolve: null as (() => void) | null }));
vi.mock("./meetingRecorder", () => ({ MeetingRecorder: class {
  id = "saved-recording";
  cloudCompletion = new Promise<void>((resolve) => { captures.cloudResolve = resolve; });
  constructor(_owner: string, _meeting: string, _title: string, notify: (update: RecorderUpdate) => void) { captures.finish = notify; }
  start = captures.starts;
  update = captures.updates;
  stop(cancel: boolean): Promise<void> { captures.stops(cancel); return Promise.resolve(); }
} }));
import { MeetingRecordingSession } from "./meetingRecordingSession";
const host = "00000000-0000-4000-8000-000000000001";
const other = "00000000-0000-4000-8000-000000000002";
function person(peerId: string, userId: string): LiveParticipantInfo { return { peerId, userId, name: userId === host ? "Host" : "Guest", remoteStream: null, hasVideo: false, isScreenSharing: false, isSpeaking: false, micOn: true } as LiveParticipantInfo; }
const sessions: MeetingRecordingSession[] = [];
const preparedContexts: PreparedContext[] = [];
class PreparedContext {
  resume = vi.fn(async () => {});
  close = vi.fn(async () => {});
  constructor() { preparedContexts.push(this); }
}
function make(asHost = true): { session: MeetingRecordingSession; send: ReturnType<typeof vi.fn>; roster: LiveParticipantInfo[] } {
  const send = vi.fn(); const rtc = { localPeerId: asHost ? "host-peer" : "guest-peer", sendAppEvent: send } as unknown as WhisperLiveRTC;
  const session = new MeetingRecordingSession(asHost ? host : other, null, () => rtc, () => host, () => "Review", vi.fn()); sessions.push(session); session.activate();
  const roster = [person("host-peer", host), person("guest-peer", other)]; session.reconcile(roster); return { session, send, roster };
}
beforeEach(() => { preparedContexts.length = 0; vi.stubGlobal("AudioContext", PreparedContext); vi.useFakeTimers(); vi.setSystemTime(new Date("2026-09-11T12:00:00Z")); captures.starts.mockReset().mockResolvedValue(undefined); captures.stops.mockReset(); captures.updates.mockReset(); captures.finish = null; Object.defineProperty(document, "hidden", { configurable: true, value: false }); });
afterEach(() => { sessions.forEach((session) => session.dispose()); sessions.length = 0; captures.cloudResolve?.(); vi.useRealTimers(); vi.unstubAllGlobals(); });

describe("fail-closed meeting recording consent", () => {
  it("reports terminal save status after disposal and republishes on BFCache restore", async () => {
    const ui = vi.fn(), lifecycle = vi.fn();
    const rtc = { localPeerId: "host-peer", sendAppEvent: vi.fn() } as unknown as WhisperLiveRTC;
    const session = new MeetingRecordingSession(host, null, () => rtc, () => host, () => "Review", ui, lifecycle);
    sessions.push(session); session.activate(); session.reconcile([person("host-peer", host)]);
    session.request(false, false); await session.start();
    expect(lifecycle.mock.lastCall?.[0].update.state).toBe("starting");
    session.dispose(); ui.mockClear();
    captures.finish?.({ state: "ready", seconds: 30, recordingId: "saved-recording", audioInputs: 0, error: null });
    expect(lifecycle.mock.lastCall?.[0].update.state).toBe("ready");
    expect(ui).not.toHaveBeenCalled();
    session.activate(); expect(ui.mock.lastCall?.[0].update.state).toBe("ready");
    expect(session.state.request).toBeNull();
  });
  it("one host Start unlocks empty audio but attaches no capture until the last approval", () => {
    const { session, roster } = make();
    session.reconcile([...roster, person("second-guest", crypto.randomUUID())]);
    session.request(true, false, false, true);
    expect(preparedContexts).toHaveLength(1);
    expect(preparedContexts[0].resume).toHaveBeenCalledTimes(1);
    expect(captures.starts).not.toHaveBeenCalled();
    const requestId = session.state.request!.requestId;
    session.receive("recording-reply-v2", { requestId, accepted: true }, "guest-peer");
    expect(captures.starts).not.toHaveBeenCalled();
    session.receive("recording-reply-v2", { requestId, accepted: true }, "second-guest");
    expect(captures.starts).toHaveBeenCalledTimes(1);
    expect(captures.starts).toHaveBeenCalledWith(expect.any(Array), true, false, false);
    session.receive("recording-reply-v2", { requestId, accepted: true }, "second-guest");
    expect(captures.starts).toHaveBeenCalledTimes(1);
  });
  it("starts a solo recording directly from the first host click", () => {
    const { session, roster } = make(); session.reconcile([roster[0]]);
    session.request(false, false, false, true);
    expect(captures.starts).toHaveBeenCalledTimes(1);
    expect(preparedContexts[0].close).not.toHaveBeenCalled();
  });
  it.each(["cancel", "decline", "timeout", "dispose"])("closes the untransferred audio context on %s", (action) => {
    const { session } = make(); session.request(true, false, false, true);
    const requestId = session.state.request!.requestId;
    if (action === "cancel") void session.stop();
    if (action === "decline") session.receive("recording-reply-v2", { requestId, accepted: false }, "guest-peer");
    if (action === "timeout") vi.advanceTimersByTime(64000);
    if (action === "dispose") session.dispose();
    expect(preparedContexts[0].close).toHaveBeenCalledTimes(1);
    session.receive("recording-reply-v2", { requestId, accepted: true }, "guest-peer");
    expect(captures.starts).not.toHaveBeenCalled();
    expect(session.state.request).toBeNull();
  });
  it("rejects a hidden-tab auto-start without retaining the prepared context", () => {
    const { session } = make(); session.request(false, false, false, true);
    Object.defineProperty(document, "hidden", { configurable: true, value: true });
    session.receive("recording-reply-v2", { requestId: session.state.request!.requestId, accepted: true }, "guest-peer");
    expect(captures.starts).not.toHaveBeenCalled();
    expect(preparedContexts[0].close).toHaveBeenCalledTimes(1);
    expect(session.state.request).toBeNull();
    expect(session.state.notice).toContain("visible");
  });
  it("reports unsupported audio setup rather than leaving a silent consent request", () => {
    vi.stubGlobal("AudioContext", class { constructor() { throw new Error("unavailable"); } });
    const { session, send } = make(); session.request(false, false, false, true);
    expect(session.state.request).toBeNull(); expect(send).not.toHaveBeenCalled();
    expect(session.state.notice).toContain("cannot start audio");
  });
  it("never accepts old-version approval for cloud archiving", async () => { const { session } = make(); session.request(false, true, true); session.receive("recording-reply-v1", { requestId: session.state.request!.requestId, accepted: true }, "guest-peer"); await session.start(); expect(captures.starts).not.toHaveBeenCalled(); });
  it("revokes an active announcement that expands archive scope", () => { const { session, send } = make(false); const request = { requestId: crypto.randomUUID(), video: false, transcribe: true, archive: false }; session.receive("recording-request-v2", request, "host-peer"); session.reply(true); session.receive("recording-state-v2", { ...request, archive: true, active: true }, "host-peer"); expect(session.state.remote?.accepted).toBe(false); expect(send).toHaveBeenLastCalledWith("recording-reply-v2", { requestId: request.requestId, accepted: false }); });
  it("requires an explicit archive field, not transcription as a substitute", () => { const { session } = make(false); session.receive("recording-request-v2", { requestId: crypto.randomUUID(), video: false, transcribe: true }, "host-peer"); expect(session.state.remote).toBeNull(); });
  it("requires every known peer to approve and ignores strangers/stale replies", async () => { const { session } = make(); session.request(false, true); const requestId = session.state.request!.requestId; await session.start(); expect(captures.starts).not.toHaveBeenCalled(); session.receive("recording-reply-v2", { requestId, accepted: true }, "stranger"); session.receive("recording-reply-v2", { requestId: crypto.randomUUID(), accepted: true }, "guest-peer"); expect(session.state.approved).toBe(0); session.receive("recording-reply-v2", { requestId, accepted: true }, "guest-peer"); await session.start(); expect(captures.starts).toHaveBeenCalledTimes(1); });
  it("never lets a non-host request recording", () => { const { session, send } = make(false); session.request(false, true); expect(session.state.request).toBeNull(); expect(send).not.toHaveBeenCalled(); });
  it("stops before reconciling a newly unconsented peer’s audio", async () => { const { session, roster } = make(); session.request(false, true); session.receive("recording-reply-v2", { requestId: session.state.request!.requestId, accepted: true }, "guest-peer"); await session.start(); captures.updates.mockClear(); session.reconcile([...roster, person("late-peer", crypto.randomUUID())]); expect(captures.stops).toHaveBeenCalled(); expect(captures.updates).not.toHaveBeenCalled(); expect(session.state.request).toBeNull(); });
  it("invalidates permission after a same-account reconnect under a new peer", () => { const { session, roster } = make(); session.request(false, true); session.reconcile([roster[0], person("replacement", other)]); expect(session.state.request).toBeNull(); });
  it("decline or withdrawal cancels immediately", async () => { const { session } = make(); session.request(false, true); const requestId = session.state.request!.requestId; session.receive("recording-reply-v2", { requestId, accepted: true }, "guest-peer"); await session.start(); session.receive("recording-reply-v2", { requestId, accepted: false }, "guest-peer"); expect(captures.stops).toHaveBeenCalled(); expect(session.state.notice).toContain("withdrew"); });
  it("expires active consent when heartbeat replies stop", async () => { const { session } = make(); session.request(false, true); session.receive("recording-reply-v2", { requestId: session.state.request!.requestId, accepted: true }, "guest-peer"); await session.start(); vi.advanceTimersByTime(16000); expect(captures.stops).toHaveBeenCalled(); expect(session.state.notice).toContain("connection was lost"); });
  it("does not treat an active-state announcement as consent", () => { const { session, send } = make(false); const requestId = crypto.randomUUID(); session.receive("recording-state-v2", { requestId, active: true }, "host-peer"); expect(send).toHaveBeenLastCalledWith("recording-reply-v2", { requestId, accepted: false }); expect(session.state.remote).toBeNull(); });
  it("keeps explicit approval across duplicate requests, not across a changed scope", () => { const { session, send } = make(false); const request = { requestId: crypto.randomUUID(), video: false, transcribe: true, archive: false }; session.receive("recording-request-v2", request, "host-peer"); expect(session.state.remote?.accepted).toBeNull(); session.reply(true); session.receive("recording-request-v2", request, "host-peer"); expect(session.state.remote?.accepted).toBe(true); session.receive("recording-request-v2", { ...request, video: true }, "host-peer"); expect(send).toHaveBeenLastCalledWith("recording-reply-v2", { requestId: request.requestId, accepted: false }); });
  it("requires fresh consent after disposal, BFCache reactivation and disablement", async () => { const { session } = make(); session.dispose(); session.request(false, true); await session.start(); expect(session.state.request).toBeNull(); session.activate(); session.request(false, true); expect(session.state.approved).toBe(0); session.setEnabled(false); session.request(false, true); await session.start(); expect(captures.starts).not.toHaveBeenCalled(); });
  it("continues to own and cancel transcription after media has finished saving", async () => { const { session } = make(); session.request(false, true); session.receive("recording-reply-v2", { requestId: session.state.request!.requestId, accepted: true }, "guest-peer"); await session.start(); captures.finish?.({ state: "ready", seconds: 30, recordingId: "saved-recording", audioInputs: 0, error: null }); expect(session.state.request).toBeNull(); session.dispose(); expect(captures.stops).toHaveBeenCalledWith(true); });
  it("times out unanswered requests rather than recording older clients silently", () => { const { session } = make(); session.request(false, true); vi.advanceTimersByTime(64000); expect(session.state.request).toBeNull(); expect(session.state.notice).toContain("expired"); });
  it("never starts capture in a hidden tab", async () => { const { session, roster } = make(); session.reconcile([roster[0]]); session.request(false, true); Object.defineProperty(document, "hidden", { configurable: true, value: true }); await session.start(); expect(captures.starts).not.toHaveBeenCalled(); });
});
