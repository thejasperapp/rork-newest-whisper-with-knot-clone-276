import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import { startMeetingRecorderTranscription, transcribeSpeechChunk, transcriptionFailure } from './meetingTranscription';
const auth = vi.hoisted(() => ({ owner: 'alex', session: vi.fn() }));
vi.mock('./supabase', () => ({ supabase: { auth: { getSession: auth.session } } }));
vi.mock('./jasperMeetings', () => ({ JASPER_MEETINGS_URL: 'https://meeting.test' }));
const audio = { size: 1000, type: 'audio/wav', arrayBuffer: async () => new ArrayBuffer(1000) } as Blob;
beforeEach(() => { auth.owner = 'alex'; auth.session.mockReset().mockImplementation(async () => ({ data: { session: { access_token: 'test-session', user: { id: auth.owner } } } })); });
afterEach(() => { vi.unstubAllGlobals(); vi.useRealTimers(); });
describe('microphone capture lifecycle', () => {
  function harness(resume: () => Promise<void> = async () => undefined, addModule: () => Promise<void> = async () => undefined) {
    const errors: string[] = []; const ready = vi.fn(); const stopTrack = vi.fn();
    const track = { id: 'raw-mic', enabled: true, readyState: 'live', stop: stopTrack, addEventListener: vi.fn(), removeEventListener: vi.fn() };
    const source = { connect: vi.fn(), disconnect: vi.fn() };
    const close = vi.fn().mockResolvedValue(undefined);
    let processor: { port: { onmessage: ((event: { data: { stopped: boolean } }) => void) | null; postMessage: ReturnType<typeof vi.fn> }; onprocessorerror?: () => void; connect: ReturnType<typeof vi.fn>; disconnect: ReturnType<typeof vi.fn> } | undefined;
    vi.stubGlobal('AudioContext', class { state = 'running'; currentTime = 0; destination = {}; resume = resume; close = close; audioWorklet = { addModule }; createMediaStreamSource = () => source; createGain = () => ({ gain: { value: 0 }, connect: vi.fn() }); });
    vi.stubGlobal('MediaStream', class { getAudioTracks = () => [track]; });
    vi.stubGlobal('AudioWorkletNode', class { port = { onmessage: null, postMessage: vi.fn() }; connect = vi.fn(); disconnect = vi.fn(); constructor() { processor = this; } });
    const capture = startMeetingRecorderTranscription({ stream: { getAudioTracks: () => [track] } as unknown as MediaStream, onTranscript: vi.fn(), onError: (text) => errors.push(text), onReady: ready })!;
    return { capture, errors, ready, close, stopTrack, processor: () => processor };
  }
  it('cancels a stalled resume immediately and never stops the RTC track', async () => {
    const value = harness(() => new Promise(() => undefined));
    expect(value.capture.isStarting).toBe(true); expect(value.capture.isActive).toBe(false);
    await value.capture.stop(); expect(value.close).toHaveBeenCalled(); expect(value.stopTrack).not.toHaveBeenCalled(); expect(value.errors).toEqual([]);
  });
  it('bounds worklet setup and ignores its late completion', async () => {
    vi.useFakeTimers(); let resolve!: () => void;
    const value = harness(async () => undefined, () => new Promise<void>((done) => { resolve = done; }));
    await vi.advanceTimersByTimeAsync(5001);
    expect(value.capture.isStarting).toBe(false); expect(value.capture.isActive).toBe(false); expect(value.errors[0]).toContain('could not start');
    resolve(); await value.capture.stop(); expect(value.ready).not.toHaveBeenCalled(); expect(value.processor()).toBeUndefined();
  });
  it('reports a missing final audio acknowledgement instead of silently succeeding', async () => {
    vi.useFakeTimers(); const value = harness(); await vi.advanceTimersByTimeAsync(0);
    expect(value.capture.isActive).toBe(true); expect(value.ready).toHaveBeenCalledOnce();
    const done = value.capture.stop(); await vi.advanceTimersByTimeAsync(2001); await done;
    expect(value.errors[0]).toContain('gap'); expect(value.stopTrack).not.toHaveBeenCalled();
  });
  it('accepts a final acknowledgement and releases resources once', async () => {
    vi.useFakeTimers(); const value = harness(); await vi.advanceTimersByTimeAsync(0);
    const done = value.capture.stop(); await vi.advanceTimersByTimeAsync(0);
    value.processor()?.port.onmessage?.({ data: { stopped: true } }); await done; await value.capture.stop();
    expect(value.errors).toEqual([]); expect(value.close).toHaveBeenCalledOnce();
  });
  it('makes processor failure retryable through the capture watchdog', async () => {
    vi.useFakeTimers(); const value = harness(); await vi.advanceTimersByTimeAsync(0); value.processor()?.onprocessorerror?.();
    expect(value.capture.isActive).toBe(false); expect(value.errors[0]).toContain('interrupted');
    const done = value.capture.stop(); await vi.advanceTimersByTimeAsync(2001); await done;
  });
});

describe('authenticated live speech', () => {
  it('sends the correct audio type to the current backend with the preserved session header', async () => {
    const fetcher = vi.fn().mockResolvedValue(Response.json({ text: 'Hello everyone' })); vi.stubGlobal('fetch', fetcher);
    expect(await transcribeSpeechChunk(audio, 'alex')).toBe('Hello everyone');
    expect(fetcher.mock.calls[0][0]).toBe('https://meeting.test/ai/transcribe');
    expect(fetcher.mock.calls[0][1].headers['X-Whisper-Authorization']).toBe('Bearer test-session');
    expect(JSON.parse(fetcher.mock.calls[0][1].body).mediaType).toBe('audio/wav');
  });
  it('never falls through to another service after an authentication failure', async () => {
    const fetcher = vi.fn().mockResolvedValue(new Response('', { status: 401 })); vi.stubGlobal('fetch', fetcher);
    await expect(transcribeSpeechChunk(audio, 'alex')).rejects.toMatchObject({ retryable: false }); expect(fetcher).toHaveBeenCalledOnce();
  });
  it('rejects results after a speaker account switch', async () => {
    vi.stubGlobal('fetch', vi.fn().mockImplementation(async () => { auth.owner = 'josh'; return Response.json({ text: 'Alex speech' }); }));
    await expect(transcribeSpeechChunk(audio, 'alex')).rejects.toMatchObject({ retryable: false });
  });
  it('retries busy services but not corrupted audio', () => { expect(transcriptionFailure(429).retryable).toBe(true); expect(transcriptionFailure(422).retryable).toBe(false); });
});
