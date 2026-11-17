import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
const storage = vi.hoisted(() => ({ create: vi.fn(), edit: vi.fn(), save: vi.fn(), transcribe: vi.fn(), verify: vi.fn(), attach: vi.fn(), load: vi.fn(), chunks: new Map<string, unknown>() }));
vi.mock("./meetingRecordingStorage", () => ({ createRecording: storage.create, editRecording: storage.edit, saveRecordingChunk: storage.save, loadRecordingChunk: storage.load }));
vi.mock("./recordingNotebook", () => ({ attachFinalizedRecordingNote: storage.attach }));
vi.mock("./verifyStoredRecording", () => ({ verifyStoredRecording: storage.verify }));
vi.mock("./recordingTranscription", () => ({ transcribeRecordingChunk: storage.transcribe }));
vi.mock("./meetPipMosaic", () => ({ MeetPipMosaic: vi.fn() }));
import { MeetingTranscriptionError } from './meetingTranscription';
import { MeetingRecorder, type RecorderUpdate } from "./meetingRecorder";
import type { MeetingRecording } from "./meetingRecordingModel";
import type { PipMosaicSource } from "./meetPipMosaic";

class Stream {
  constructor(private readonly tracks: MediaStreamTrack[] = []) {}
  getAudioTracks(): MediaStreamTrack[] { return this.tracks.filter((t) => t.kind === "audio"); }
  getVideoTracks(): MediaStreamTrack[] { return this.tracks.filter((t) => t.kind === "video"); }
  getTracks(): MediaStreamTrack[] { return this.tracks; }
}
function audioTrack(): MediaStreamTrack { return { kind: "audio", readyState: "live", stop: vi.fn(), enabled: true } as unknown as MediaStreamTrack; }
class Node { connect = vi.fn(); disconnect = vi.fn(); }
let contexts: Context[] = [];
let worklets: Worklet[] = [];
let mediaRecorders: Recorder[] = [];
let moduleReady: Promise<void> = Promise.resolve();
class Context {
  currentTime = 5; state = "running"; sampleRate = 24000; destination = new Node(); onstatechange: (() => void) | null = null;
  inputs: { stream: Stream; node: Node }[] = []; output = audioTrack();
  audioWorklet = { addModule: () => moduleReady };
  constructor() { contexts.push(this); }
  resume = vi.fn(async () => {}); close = vi.fn(async () => {});
  createGain(): Node & { gain: { value: number } } { return Object.assign(new Node(), { gain: { value: 1 } }); }
  createDynamicsCompressor(): Node & { threshold: { value: number }; knee: { value: number }; ratio: { value: number } } { return Object.assign(new Node(), { threshold: { value: 0 }, knee: { value: 0 }, ratio: { value: 0 } }); }
  createMediaStreamDestination(): Node & { stream: Stream } { return Object.assign(new Node(), { stream: new Stream([this.output]) }); }
  createMediaStreamSource(stream: Stream): Node { const node = new Node(); this.inputs.push({ stream, node }); return node; }
}
class Worklet extends Node {
  port = { onmessage: null as ((event: { data: unknown }) => void) | null, postMessage: (message: string) => { if (message === "stop") queueMicrotask(() => this.port.onmessage?.({ data: { stopped: true } })); } };
  constructor() { super(); worklets.push(this); }
}
class Recorder extends EventTarget {
  static isTypeSupported(): boolean { return true; }
  state = "inactive"; mimeType = "audio/webm"; ondataavailable: ((event: { data: Blob }) => void) | null = null; onerror: (() => void) | null = null;
  constructor() { super(); mediaRecorders.push(this); }
  start(): void { this.state = "recording"; }
  stop(): void { this.state = "inactive"; queueMicrotask(() => { this.ondataavailable?.({ data: new Blob(["container-end"]) }); this.dispatchEvent(new Event("stop")); }); }
}
function source(track: MediaStreamTrack, id: string): PipMosaicSource { return { id, name: id, stream: new Stream([track]) as unknown as MediaStream, hasVideo: false, isSelf: id === "self", isScreenShare: false, isSpeaking: false, micOn: true }; }
const engines: MeetingRecorder[] = [];
function make(): { engine: MeetingRecorder; updates: RecorderUpdate[] } { const updates: RecorderUpdate[] = []; const engine = new MeetingRecorder(crypto.randomUUID(), null, "Review", (value) => updates.push(value)); engines.push(engine); return { engine, updates }; }
beforeEach(() => { contexts = []; worklets = []; mediaRecorders = []; moduleReady = Promise.resolve(); storage.attach.mockReset().mockResolvedValue(undefined); storage.verify.mockReset().mockResolvedValue(undefined); storage.create.mockReset().mockResolvedValue(undefined); storage.edit.mockReset().mockResolvedValue(undefined); storage.chunks.clear(); storage.load.mockReset().mockImplementation(async (key: string) => storage.chunks.get(key)); storage.save.mockReset().mockImplementation(async (_owner, _id, chunk) => { const key = `${chunk.kind}:${chunk.index}`; const saved = { ...chunk, key }; storage.chunks.set(key, saved); return saved; }); storage.transcribe.mockReset().mockResolvedValue(undefined); vi.stubGlobal("AudioContext", Context); vi.stubGlobal("AudioWorkletNode", Worklet); vi.stubGlobal("MediaRecorder", Recorder); vi.stubGlobal("MediaStream", Stream); });
afterEach(async () => { await Promise.all(engines.splice(0).map((engine) => engine.stop(true))); vi.unstubAllGlobals(); });

describe("recording graph lifecycle", () => {
  it('makes media ready while the last permitted transcript finishes independently', async () => {
    let finish!: () => void; storage.transcribe.mockImplementation(() => new Promise<void>((resolve) => { finish = resolve; }));
    const { engine, updates } = make(); await engine.start([source(audioTrack(), 'Taylor')], false, true);
    worklets[1].port.onmessage?.({ data: { samples: new Float32Array([0.4]), rate: 24000, start: 5, end: 6 } });
    await vi.waitFor(() => expect(storage.transcribe).toHaveBeenCalledOnce());
    await engine.stop();
    expect(updates[updates.length - 1]?.state).toBe('ready'); expect(updates[updates.length - 1]?.transcriptionPending).toBe(true); expect(storage.transcribe.mock.calls[0][2].aborted).toBe(false);
    finish(); await engine.cloudCompletion; expect(updates[updates.length - 1]?.state).toBe('ready');
    const edit = storage.edit.mock.calls[storage.edit.mock.calls.length - 1][2]; expect(edit({ duration: 1, warnings: [] }).transcriptionState).toBe('complete');
  });
  it('does not call a transcript complete after a speaker lane fails to flush', async () => {
    const { engine, updates } = make(); await engine.start([source(audioTrack(), 'Alex')], false, true);
    worklets[1].port.postMessage = () => undefined;
    vi.useFakeTimers();
    try {
      const stopped = engine.stop(); await vi.advanceTimersByTimeAsync(2001); await stopped; await engine.cloudCompletion;
      expect(updates[updates.length - 1]?.state).toBe('ready');
      const edit = storage.edit.mock.calls[storage.edit.mock.calls.length - 1][2]; expect(edit({ duration: 1, warnings: [] }).transcriptionState).toBe('incomplete');
    } finally { vi.useRealTimers(); }
  });
  it('keeps simultaneous sources separately named and does not transcribe the mixed backup', async () => {
    const { engine } = make(); await engine.start([source(audioTrack(), 'Alex'), source(audioTrack(), 'Josh')], false, true);
    worklets[1].port.onmessage?.({ data: { samples: new Float32Array([0.4]), rate: 24000, start: 7, end: 8 } });
    worklets[2].port.onmessage?.({ data: { samples: new Float32Array([0.5]), rate: 24000, start: 7, end: 8 } });
    await engine.stop(); await engine.cloudCompletion; expect(storage.transcribe.mock.calls.map((call) => [call[1].speakerName, call[1].start])).toEqual([['Alex', 2], ['Josh', 2]]);
  });
  it("attaches a verified recording to its stable note identity without changing the owner", async () => {
    const { engine } = make(); await engine.start([source(audioTrack(), "self")], false, false); await engine.stop();
    expect(storage.attach).toHaveBeenCalledWith(expect.objectContaining({ id: engine.id, ownerId: engine.ownerId, status: "ready" }));
  });
  it("keeps media ready and reports an actionable retry when notebook attachment fails", async () => {
    storage.attach.mockRejectedValue(new Error("Notebook full"));
    const { engine, updates } = make(); await engine.start([source(audioTrack(), "self")], false, false); await engine.stop();
    expect(storage.save).toHaveBeenCalled();
    expect(updates[updates.length - 1]).toMatchObject({ state: "ready", recordingId: engine.id });
    expect(updates[updates.length - 1]?.error).toContain("Your recording is retained");
  });
  it("does not report ready when persisted media cannot reopen", async () => {
    storage.verify.mockRejectedValue(new Error("decode failed"));
    const { engine, updates } = make(); await engine.start([source(audioTrack(), "self")], false, false);
    await engine.stop();
    expect(updates.some((update) => update.state === "ready")).toBe(false);
    expect(updates[updates.length - 1]?.error).toContain("playback could not be verified");
  });
  it("remains saving until the persisted playback probe completes", async () => {
    let resolve!: () => void; storage.verify.mockImplementation(() => new Promise<void>((done) => { resolve = done; }));
    const { engine, updates } = make(); await engine.start([source(audioTrack(), "self")], false, false);
    const stop = engine.stop(); await vi.waitFor(() => expect(storage.verify).toHaveBeenCalled());
    expect(updates[updates.length - 1]?.state).toBe("saving"); resolve(); await stop;
    expect(updates[updates.length - 1]?.state).toBe("ready");
  });
  it("adopts the gesture-unlocked context and closes only recording-owned resources", async () => {
    const prepared = new Context();
    const engine = new MeetingRecorder(crypto.randomUUID(), null, "Prepared recording", vi.fn(), prepared as unknown as AudioContext);
    engines.push(engine);
    const callTrack = audioTrack();
    await engine.start([source(callTrack, "self")], false, false);
    expect(contexts).toEqual([prepared]);
    await engine.stop();
    expect(prepared.close).toHaveBeenCalledTimes(1);
    expect(callTrack.stop).not.toHaveBeenCalled();
  });
  it("releases a transferred context on unsupported encoder startup", async () => {
    const prepared = new Context();
    const engine = new MeetingRecorder(crypto.randomUUID(), null, "Unsupported recording", vi.fn(), prepared as unknown as AudioContext);
    engines.push(engine); vi.stubGlobal("MediaRecorder", undefined);
    await expect(engine.start([source(audioTrack(), "self")], false, false)).rejects.toThrow("recent browser");
    expect(prepared.close).toHaveBeenCalledTimes(1);
    expect(prepared.inputs).toHaveLength(0);
  });
  it("settles stop and releases recording resources even when media.stop throws", async () => { const { engine, updates } = make(); await engine.start([source(audioTrack(), "self")], false, false); mediaRecorders[0].stop = () => { throw new Error("encoder gone"); }; await engine.stop(); expect(contexts[0].close).toHaveBeenCalled(); expect(contexts[0].output.stop).toHaveBeenCalled(); expect(updates[updates.length - 1]?.state).toBe("error"); });
  it("cancelled worklet startup exits even if the browser never resolves loading", async () => { moduleReady = new Promise(() => {}); const { engine } = make(); const starting = engine.start([source(audioTrack(), "self")], false, false); const rejected = expect(starting).rejects.toThrow("cancelled"); await Promise.resolve(); await engine.stop(); await rejected; expect(contexts[0].close).toHaveBeenCalled(); });
  it("never reports a cancelled storage reservation as saved", async () => {
    let complete!: () => void; storage.create.mockImplementation(() => new Promise<void>((resolve) => { complete = resolve; }));
    const { engine, updates } = make(); const starting = engine.start([source(audioTrack(), "self")], false, false);
    const rejected = expect(starting).rejects.toThrow("cancelled");
    await vi.waitFor(() => expect(storage.create).toHaveBeenCalled()); const stopped = engine.stop(); complete();
    await rejected; await stopped;
    expect(updates.some((update) => update.state === "ready")).toBe(false);
    const edit = storage.edit.mock.calls[0][2] as (record: MeetingRecording) => MeetingRecording;
    expect(edit({ duration: 0, warnings: [] } as unknown as MeetingRecording).status).toBe("interrupted");
  });
  it("uses the audio clock, freezes stop time, and cannot reconnect sources during saving", async () => {
    const { engine } = make(); await engine.start([source(audioTrack(), "self")], false, false);
    contexts[0].currentTime = 12.25; expect(engine.seconds).toBe(7.25);
    const stop = engine.stop(); contexts[0].currentTime = 100; engine.update([source(audioTrack(), "late")]);
    expect(engine.seconds).toBe(7.25); expect(contexts[0].inputs).toHaveLength(1); await stop;
  });
  it("waits for delayed final media rather than discarding it at four seconds", async () => {
    vi.useFakeTimers();
    try {
      const { engine, updates } = make(); await engine.start([source(audioTrack(), "self")], false, false);
      const recorder = mediaRecorders[0]; recorder.stop = () => { recorder.state = "inactive"; setTimeout(() => { recorder.ondataavailable?.({ data: new Blob(["late-footer"]) }); recorder.dispatchEvent(new Event("stop")); }, 6000); };
      const stopped = engine.stop(); await vi.advanceTimersByTimeAsync(4500);
      expect(updates[updates.length - 1]?.state).toBe("saving"); expect(updates[updates.length - 1]?.error).toContain("Still saving");
      await vi.advanceTimersByTimeAsync(2000); await stopped;
      expect(storage.save).toHaveBeenCalled(); expect(updates[updates.length - 1]?.state).toBe("ready"); expect(updates[updates.length - 1]?.error).toBeNull();
    } finally { vi.useRealTimers(); }
  });
  it("mixes all received and outgoing audio, deduplicating tracks without owning them", async () => { const { engine } = make(); const self = audioTrack(), remote = audioTrack(); await engine.start([source(self, "self"), source(remote, "remote"), source(remote, "duplicate")], false, false); expect(contexts[0].inputs).toHaveLength(2); await engine.stop(); expect(self.stop).not.toHaveBeenCalled(); expect(remote.stop).not.toHaveBeenCalled(); expect(contexts[0].output.stop).toHaveBeenCalled(); expect(storage.save).toHaveBeenCalledWith(expect.any(String), expect.any(String), expect.objectContaining({ kind: "media", index: 0 })); });
  it("uses the latest source roster after asynchronous worklet loading", async () => { let resolve!: () => void; moduleReady = new Promise((done) => { resolve = done; }); const { engine } = make(); const old = audioTrack(), fresh = audioTrack(); const start = engine.start([source(old, "self")], false, false); await Promise.resolve(); engine.update([source(fresh, "self")]); resolve(); await start; expect(contexts[0].inputs[0].stream.getAudioTracks()).toEqual([fresh]); });
  it("does not start media capture after startup was cancelled", async () => { let resolve!: () => void; moduleReady = new Promise((done) => { resolve = done; }); const { engine } = make(); const starting = engine.start([source(audioTrack(), "self")], false, false); const rejection = expect(starting).rejects.toThrow(); await Promise.resolve(); const stop = engine.stop(true); resolve(); await rejection; await stop; expect(mediaRecorders.every((recorder) => recorder.state === "inactive")).toBe(true); expect(contexts[0].close).toHaveBeenCalled(); });
  it("disconnects sources synchronously and finalizes only once", async () => { const { engine } = make(); await engine.start([source(audioTrack(), "self")], false, false); const first = engine.stop(); expect(contexts[0].inputs[0].node.disconnect).toHaveBeenCalled(); expect(engine.stop()).toBe(first); await first; expect(storage.edit).toHaveBeenCalledTimes(1); });
  it("saves independent mixed backup and named PCM with the same capture-relative offsets", async () => { const { engine } = make(); await engine.start([source(audioTrack(), "Alex")], false, true); for (const worklet of worklets) worklet.port.onmessage?.({ data: { samples: new Float32Array([0.2, 0.3]), rate: 24000, start: 35, end: 65 } }); await engine.stop(); await engine.cloudCompletion; expect(storage.save).toHaveBeenCalledWith(expect.any(String), expect.any(String), expect.objectContaining({ kind: "audio", start: 30, end: 60 })); expect(storage.transcribe).toHaveBeenCalledTimes(1); expect(storage.transcribe.mock.calls[0][1]).toMatchObject({ kind: 'speaker', speakerName: 'Alex', sourceId: 'Alex', start: 30, end: 60 }); });
  it("keeps recording media when cloud transcription fails", async () => { storage.transcribe.mockRejectedValue(new MeetingTranscriptionError('invalid audio', false)); const { engine, updates } = make(); await engine.start([source(audioTrack(), "self")], false, true); worklets[1].port.onmessage?.({ data: { samples: new Float32Array([0.3]), rate: 24000, start: 5, end: 6 } }); await engine.cloudCompletion; expect(mediaRecorders[0].state).toBe("recording"); expect(updates[updates.length - 1]?.error).toContain("needs retry"); await engine.stop(); const saved = storage.edit.mock.calls.reduce((record, call) => call[2](record), { duration: 1, warnings: [], status: 'recording' }); expect(saved.status).toBe('ready'); expect(saved.transcriptionState).toBe('incomplete'); expect(updates[updates.length - 1]?.state).toBe('ready'); });
});
