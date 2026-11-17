import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@/lib/supabase", () => ({ supabase: { removeChannel: vi.fn(async () => {}) } }));
vi.mock("@/lib/videoEffects", () => ({ videoFx: { outputTrack: null, release: vi.fn(), prefs: { mode: "none" } } }));
vi.mock("@/lib/billing", () => ({ backendFetch: vi.fn() }));
vi.mock("@/lib/meetPrefs", () => ({ preferredAudioConstraints: () => true, preferredVideoConstraints: () => true }));

import { WhisperLiveRTC } from "./whisperLiveRTC";

class TestStream {
  private tracks: MediaStreamTrack[];
  constructor(tracks: MediaStreamTrack[] = []) { this.tracks = [...tracks]; }
  getTracks(): MediaStreamTrack[] { return [...this.tracks]; }
  getVideoTracks(): MediaStreamTrack[] { return this.tracks.filter((track) => track.kind === "video"); }
  getAudioTracks(): MediaStreamTrack[] { return this.tracks.filter((track) => track.kind === "audio"); }
  addTrack(track: MediaStreamTrack): void { if (!this.tracks.includes(track)) this.tracks.push(track); }
  removeTrack(track: MediaStreamTrack): void { this.tracks = this.tracks.filter((item) => item !== track); }
}

function track(kind: "audio" | "video" = "video"): MediaStreamTrack {
  const item = { kind, id: crypto.randomUUID(), readyState: "live", enabled: true, onended: null, stop: vi.fn(), addEventListener: vi.fn(), removeEventListener: vi.fn() };
  item.stop.mockImplementation(() => { item.readyState = "ended"; });
  return item as unknown as MediaStreamTrack;
}

function deferred<T>(): { promise: Promise<T>; resolve: (value: T) => void } {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => { resolve = done; });
  return { promise, resolve };
}

// Inspect boundaries without adding test-only accessors to the production engine.
interface RTCInternals {
  channel: { send: ReturnType<typeof vi.fn> } | null;
  isSpeaker: boolean;
  cameraOn: boolean;
  localStream: MediaStream | null;
  screenSharing: boolean;
  screenShareTransition: string | null;
  peers: Map<string, unknown>;
  auxMicTrack: MediaStreamTrack | null;
  auxMixTrack: MediaStreamTrack | null;
  ensureIceServers: (maxAge?: number) => Promise<void>;
  refreshIceServers: () => Promise<void>;
  iceFetchedAt: number;
  recoverPeer: (peer: unknown, reason: string) => Promise<void>;
  notifyParticipants: () => void;
  requestNegotiation: (peer: unknown) => void;
  createPeerConnection: (peerId: string, userId: string, name: string, speaker: boolean, offerer: boolean) => Promise<void>;
  handleOffer: (peerId: string, sdp: string) => Promise<void>;
}

function engine(): { rtc: WhisperLiveRTC; state: RTCInternals } {
  const rtc = new WhisperLiveRTC("self", "viewer", "Viewer");
  const state = rtc as unknown as RTCInternals;
  state.channel = { send: vi.fn(async () => "ok") };
  state.isSpeaker = true;
  state.cameraOn = false;
  state.localStream = new MediaStream();
  state.notifyParticipants = vi.fn();
  state.requestNegotiation = vi.fn();
  return { rtc, state };
}

const displayPicker = vi.fn<() => Promise<MediaStream>>();
const cameraPicker = vi.fn<() => Promise<MediaStream>>();

beforeEach(() => {
  vi.stubGlobal("MediaStream", TestStream);
  Object.defineProperty(navigator, "mediaDevices", { configurable: true, value: { getDisplayMedia: displayPicker, getUserMedia: cameraPicker } });
  displayPicker.mockReset();
  cameraPicker.mockReset();
});
afterEach(() => { vi.unstubAllGlobals(); vi.restoreAllMocks(); });

describe("terminal meeting lifecycle", () => {
  it("concurrent ICE users wait for the same real refresh, never a prematurely fresh timestamp", async () => {
    const { rtc, state } = engine(); const result = deferred<void>();
    state.iceFetchedAt = 0; state.refreshIceServers = vi.fn(() => result.promise);
    let firstFinished = false, secondFinished = false;
    const first = state.ensureIceServers().then(() => { firstFinished = true; });
    const second = state.ensureIceServers().then(() => { secondFinished = true; });
    await Promise.resolve();
    expect(state.refreshIceServers).toHaveBeenCalledTimes(1);
    expect(firstFinished || secondFinished).toBe(false); expect(state.iceFetchedAt).toBe(0);
    result.resolve(); await Promise.all([first, second]);
    expect(firstFinished && secondFinished).toBe(true); rtc.leave();
  });
  it("stops late microphone permission and never notifies a departed room", async () => {
    const { rtc, state } = engine();
    const picker = deferred<MediaStream>(); cameraPicker.mockReturnValue(picker.promise);
    const preparing = rtc.prepareLocalMedia({ video: false });
    const rejection = expect(preparing).rejects.toMatchObject({ name: "AbortError" });
    rtc.leave(); const microphone = track("audio"); picker.resolve(new MediaStream([microphone]));
    await rejection;
    expect(microphone.stop).toHaveBeenCalledTimes(1);
    expect(state.localStream).toBeNull();
    expect(state.notifyParticipants).not.toHaveBeenCalled();
  });
  it("a closed instance cannot reacquire media or rejoin", async () => {
    const { rtc } = engine(); rtc.leave();
    await expect(rtc.prepareLocalMedia()).rejects.toMatchObject({ name: "AbortError" });
    await expect(rtc.join("room", false)).rejects.toMatchObject({ name: "AbortError" });
    expect(await rtc.setMicEnabled(true)).toBe(false);
    expect(cameraPicker).not.toHaveBeenCalled();
  });
  it("finishing an unmute sender replacement after leave cannot report mic on", async () => {
    const { rtc, state } = engine();
    const replacing = deferred<void>(); const began = deferred<void>();
    const microphone = track("audio");
    cameraPicker.mockResolvedValue(new MediaStream([microphone]));
    state.peers.set("remote", { pc: { getSenders: () => [{ track: track("audio"), replaceTrack: async () => { began.resolve(); await replacing.promise; } }], close: vi.fn() } });
    const unmuting = rtc.setMicEnabled(true); await began.promise;
    rtc.leave(); replacing.resolve();
    expect(await unmuting).toBe(false);
    expect(microphone.readyState).toBe("ended");
    expect(state.notifyParticipants).not.toHaveBeenCalled();
  });
  it("leaving also stops the physical microphone retained behind the auxiliary mix", () => {
    const { rtc, state } = engine();
    const microphone = track("audio"), mixed = track("audio");
    state.auxMicTrack = microphone; state.auxMixTrack = mixed;
    state.localStream = new MediaStream([mixed]);
    rtc.leave(); rtc.leave();
    expect(microphone.stop).toHaveBeenCalledTimes(1);
    expect(mixed.stop).toHaveBeenCalledTimes(1);
    expect(state.localStream).toBeNull();
  });
  it("ignores delayed peer creation and offer handling after leave", async () => {
    const { rtc, state } = engine(); const create = vi.fn(); vi.stubGlobal("RTCPeerConnection", create);
    rtc.leave();
    await state.createPeerConnection("remote", "other", "Other", true, false);
    await state.handleOffer("remote", "late-offer");
    expect(create).not.toHaveBeenCalled(); expect(state.peers.size).toBe(0);
  });
  it("serializes healing for a peer and does not restart it after leave", async () => {
    const { rtc, state } = engine(); const freshIce = deferred<void>();
    state.ensureIceServers = vi.fn(() => freshIce.promise);
    const peer = { peerId: "remote", name: "Other", attempts: 0, isOfferer: true, pc: { connectionState: "failed", restartIce: vi.fn(), close: vi.fn() } };
    state.peers.set("remote", peer);
    const first = state.recoverPeer(peer, "test"); const duplicate = state.recoverPeer(peer, "test");
    expect(peer.attempts).toBe(1); expect(state.ensureIceServers).toHaveBeenCalledTimes(1);
    rtc.leave(); freshIce.resolve(); await Promise.all([first, duplicate]);
    expect(peer.pc.restartIce).not.toHaveBeenCalled(); expect(state.peers.size).toBe(0);
  });
});

describe("screen-share lifecycle", () => {
  it.each(["stop", "leave"])("stops a late display-picker result after %s", async (action) => {
    const { rtc, state } = engine();
    const capture = track();
    const picker = deferred<MediaStream>();
    displayPicker.mockReturnValue(picker.promise);
    const starting = rtc.startScreenShare();
    if (action === "leave") rtc.leave(); else await rtc.stopScreenShare();
    picker.resolve(new MediaStream([capture]));
    expect(await starting).toBe(false);
    expect(capture.stop).toHaveBeenCalled();
    expect(state.screenSharing).toBe(false);
  });

  it("blocks a second picker and does not enable a previously-off camera", async () => {
    const { rtc, state } = engine();
    const picker = deferred<MediaStream>();
    const capture = track();
    displayPicker.mockReturnValue(picker.promise);
    const starting = rtc.startScreenShare();
    expect(await rtc.startScreenShare()).toBe(false);
    expect(displayPicker).toHaveBeenCalledTimes(1);
    picker.resolve(new MediaStream([capture]));
    expect(await starting).toBe(true);
    await rtc.stopScreenShare();
    expect(capture.stop).toHaveBeenCalled();
    expect(cameraPicker).not.toHaveBeenCalled();
    expect(state.cameraOn).toBe(false);
  });

  it("stops display capture before waiting for camera permission", async () => {
    const { rtc, state } = engine();
    state.cameraOn = true;
    state.localStream = new MediaStream([track()]);
    const capture = track();
    displayPicker.mockResolvedValue(new MediaStream([capture]));
    await rtc.startScreenShare();
    const permission = deferred<MediaStream>();
    cameraPicker.mockReturnValue(permission.promise);
    const stopping = rtc.stopScreenShare();
    expect(capture.stop).toHaveBeenCalled();
    expect(state.localStream?.getVideoTracks()).toHaveLength(0);
    expect(state.screenSharing).toBe(false);
    rtc.leave();
    const camera = track();
    permission.resolve(new MediaStream([camera]));
    await stopping;
    expect(camera.stop).toHaveBeenCalled();
    expect(state.localStream).toBeNull();
  });

  it("associates a reused video transceiver with the local stream", async () => {
    const { rtc, state } = engine();
    const sender = { track: null, replaceTrack: vi.fn(async () => {}), setStreams: vi.fn() };
    const transceiver = { currentDirection: "recvonly", direction: "recvonly", receiver: { track: track() }, sender };
    state.peers.set("remote", { pc: { getSenders: () => [], getTransceivers: () => [transceiver] } });
    const capture = track();
    displayPicker.mockResolvedValue(new MediaStream([capture]));
    expect(await rtc.startScreenShare()).toBe(true);
    expect(sender.replaceTrack).toHaveBeenCalledWith(capture);
    expect(sender.setStreams).toHaveBeenCalledWith(state.localStream);
    expect(transceiver.direction).toBe("sendrecv");
    expect(state.requestNegotiation).toHaveBeenCalled();
  });

  it("finishes a stale sender replacement before clearing the stopped share", async () => {
    const { rtc, state } = engine();
    const capture = track();
    const replacing = deferred<void>();
    const began = deferred<void>();
    const sender = { track: track() as MediaStreamTrack | null, replaceTrack: vi.fn(async (next: MediaStreamTrack | null) => {
      if (next === capture) { began.resolve(); await replacing.promise; }
      sender.track = next;
    }) };
    state.peers.set("remote", { pc: { getSenders: () => [sender] } });
    displayPicker.mockResolvedValue(new MediaStream([capture]));
    const starting = rtc.startScreenShare();
    await began.promise;
    const stopping = rtc.stopScreenShare();
    expect(capture.stop).toHaveBeenCalled();
    replacing.resolve();
    expect(await starting).toBe(false);
    await stopping;
    expect(sender.track).toBeNull();
    expect(state.screenShareTransition).toBeNull();
  });

  it("does not let a late camera permission replace an active share", async () => {
    const { rtc, state } = engine();
    const permission = deferred<MediaStream>();
    cameraPicker.mockReturnValue(permission.promise);
    const enabling = rtc.setCameraEnabled(true);
    const capture = track();
    displayPicker.mockResolvedValue(new MediaStream([capture]));
    await rtc.startScreenShare();
    const camera = track();
    permission.resolve(new MediaStream([camera]));
    await enabling;
    expect(camera.stop).toHaveBeenCalled();
    expect(state.localStream?.getVideoTracks()).toEqual([capture]);
    expect(state.screenSharing).toBe(true);
  });
});

describe("streamless remote tracks", () => {
  it("retains incoming tracks and emits a fresh stream on each arrival", async () => {
    const { rtc, state } = engine();
    let connection!: { ontrack: ((event: { track: MediaStreamTrack; streams: MediaStream[] }) => void) | null };
    class PeerConnection {
      ontrack = null;
      addTransceiver = vi.fn();
      getSenders = (): never[] => [];
    }
    vi.stubGlobal("RTCPeerConnection", vi.fn(function () {
      const created = new PeerConnection();
      connection = created;
      return created;
    }));
    rtc.onRemoteStream = vi.fn();
    await state.createPeerConnection("remote", "other", "Other", true, false);
    const audio = track("audio");
    const video = track();
    connection.ontrack?.({ track: audio, streams: [] });
    connection.ontrack?.({ track: video, streams: [] });
    const calls = vi.mocked(rtc.onRemoteStream).mock.calls;
    expect(calls[0][1]).not.toBe(calls[1][1]);
    expect(calls[1][1].getTracks()).toEqual([audio, video]);
  });
});
